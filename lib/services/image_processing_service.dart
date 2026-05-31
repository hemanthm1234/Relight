// ============================================================================
// File: lib/services/image_processing_service.dart
// Purpose: Handles heavy CPU-bound image manipulation and intrinsic decomposition.
// 
// Responsibility:
// - Transforms raw byte arrays into platform-optimized Flutter `ui.Image` GPU texture handles.
// - Performs Intrinsic Image Decomposition via a bilateral edge-preservation filter approximation on a background thread (Isolate).
// - Decouples target images into three components:
//   1. Albedo Map: Extracted by dividing luminance intensity by low-frequency shading approximations.
//   2. Depth Map: Up-sampled and mapped symmetrically from the raw ML output matrix back to the target's original resolution.
//   3. Original Scene: Retained as the source template for high-fidelity rendering.
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class ImageProcessingService {
  
  static Future<ui.Image> bytesToUiImage(Uint8List rawData) {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(rawData, (ui.Image img) => completer.complete(img));
    return completer.future;
  }

  Future<Map<String, Uint8List>> executeIntrinsicDecomposition(Uint8List targetImageBytes, Float32List depthMapData) async {
    return await compute(_processTexturesIsolate, {
      'imageBytes': targetImageBytes,
      'depthData': depthMapData,
    });
  }

  static Map<String, Uint8List> _processTexturesIsolate(Map<String, dynamic> args) {
    final Uint8List imageBytes = args['imageBytes'];
    final Float32List rawDepthData = args['depthData'];

    img.Image? original = img.decodeImage(imageBytes);
    if (original == null) throw Exception("Cannot parse image source.");

    int w = original.width;
    int h = original.height;

    // =====================================================================
    // DEPTH MAP EDGE-PRESERVING SMOOTHING (BILATERAL FILTER)
    // Smooths planar wobble from the AI model while preserving sharp object silhouettes.
    // Applied at the native 518x518 model resolution for speed (~10-20ms per pass).
    // Two passes are run for stronger smoothing of AI terracing artifacts.
    // =====================================================================
    const int depthDim = 518;
    const int numPasses = 2;             // Multiple passes for stronger smoothing

    const int radius = 5;                // 11x11 kernel
    const double sigmaSpatial = 5.0;     // How far neighboring pixels influence the center
    const double sigmaRange = 0.05;      // 5% depth difference limit (preserves sharp edges)

    // Precompute spatial Gaussian weights for the kernel
    final int kernelWidth = radius * 2 + 1;
    final List<double> spatialWeights = List.filled(kernelWidth * kernelWidth, 0.0);
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        spatialWeights[(dy + radius) * kernelWidth + (dx + radius)] =
            math.exp(-(dx * dx + dy * dy) / (2.0 * sigmaSpatial * sigmaSpatial));
      }
    }

    // Ping-pong buffers for multi-pass filtering
    Float32List sourceBuffer = rawDepthData;
    Float32List destBuffer = Float32List(depthDim * depthDim);

    for (int pass = 0; pass < numPasses; pass++) {
      for (int y = 0; y < depthDim; y++) {
        for (int x = 0; x < depthDim; x++) {
          final double centerDepth = sourceBuffer[y * depthDim + x];
          double weightSum = 0.0;
          double depthSum = 0.0;

          for (int dy = -radius; dy <= radius; dy++) {
            final int ny = (y + dy).clamp(0, depthDim - 1);
            for (int dx = -radius; dx <= radius; dx++) {
              final int nx = (x + dx).clamp(0, depthDim - 1);

              final double neighborDepth = sourceBuffer[ny * depthDim + nx];

              // Pre-calculated spatial weight
              final double wSpatial = spatialWeights[(dy + radius) * kernelWidth + (dx + radius)];

              // Range weight: drops to ~0 if depth jump exceeds sigmaRange
              final double depthDiff = neighborDepth - centerDepth;
              final double wRange = math.exp(-(depthDiff * depthDiff) / (2.0 * sigmaRange * sigmaRange));

              final double combinedWeight = wSpatial * wRange;
              weightSum += combinedWeight;
              depthSum += neighborDepth * combinedWeight;
            }
          }
          destBuffer[y * depthDim + x] = depthSum / weightSum;
        }
      }
      // Swap buffers for next pass
      final Float32List temp = sourceBuffer == rawDepthData
          ? Float32List.fromList(destBuffer)
          : destBuffer;
      sourceBuffer = temp;
      destBuffer = Float32List(depthDim * depthDim);
    }
    final Float32List depthData = sourceBuffer;
    // =====================================================================

    // 1. Synthesize High Resolution Depth Texture Asset Buffer
    // 16-BIT DEPTH PACKING: R = coarse (high byte), G = fine (low byte)
    // This gives 65,025 distinct depth levels instead of only 256 from 8-bit.
    // The shader's unpackDepth() reconstructs: depth = R + G/255.0
    img.Image depthTexImg = img.Image(width: w, height: h, numChannels: 3, format: img.Format.uint8);
    // Depth Anything outputs continuous 518x518 data. Sample back symmetrically to original proportions.
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double modelX = (x / w) * 518.0;
        double modelY = (y / h) * 518.0;
        
        int mX = modelX.floor().clamp(0, 517);
        int mY = modelY.floor().clamp(0, 517);
        double depthVal = depthData[mY * 518 + mX].toDouble().clamp(0.0, 1.0);
        
        // 16-bit pack: split depth into coarse R and fine G channels
        double scaledDepth = depthVal * 255.0;
        int rByte = scaledDepth.floor().clamp(0, 255);
        double fractPart = scaledDepth - rByte;
        int gByte = (fractPart * 255.0).round().clamp(0, 255);
        
        depthTexImg.setPixelRgb(x, y, rByte, gByte, 0);
      }
    }

    // 2. Perform Intrinsic Image Decomposition via Bilateral Edge Preservation Filter Approximation
    img.Image albedoTexImg = img.Image(width: w, height: h, numChannels: 3, format: img.Format.uint8);
    
    // Exact manual combination weights from linear luminance conversion logic
    double rWeight = 0.299;
    double gWeight = 0.587;
    double bWeight = 0.114;

    // Create intermediate low-frequency shading reference map structure
    List<double> luminanceGrid = List.filled(w * h, 0.0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        var p = original.getPixel(x, y);
        luminanceGrid[y * w + x] = (p.r * rWeight + p.g * gWeight + p.b * bWeight) / 255.0;
      }
    }

    // Run Bilateral Shading Smoothing Loop Pass
    int spatialRadius = 5;
    double sigmaSpace = 6.0;
    double sigmaColor = 0.15;
    
    List<double> spaceLUT = List.generate(spatialRadius + 1, (i) => math.exp(-(i * i) / (2.0 * sigmaSpace * sigmaSpace)));

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double sumWeights = 0.0;
        double sumIntensity = 0.0;
        double centerIntensity = luminanceGrid[y * w + x];

        for (int ky = -spatialRadius; ky <= spatialRadius; ky++) {
          int ny = (y + ky).clamp(0, h - 1);
          for (int kx = -spatialRadius; kx <= spatialRadius; kx++) {
            int nx = (x + kx).clamp(0, w - 1);

            double neighborIntensity = luminanceGrid[ny * w + nx];
            double distSpace = math.sqrt((ky * ky + kx * kx).toDouble());
            
            if (distSpace > spatialRadius) continue;

            double wSpace = spaceLUT[distSpace.round()];
            double diffColor = neighborIntensity - centerIntensity;
            double wColor = math.exp(-(diffColor * diffColor) / (2.0 * sigmaColor * sigmaColor));

            double weight = wSpace * wColor;
            sumWeights += weight;
            sumIntensity += neighborIntensity * weight;
          }
        }

        double estimatedShading = sumWeights > 0 ? (sumIntensity / sumWeights) : centerIntensity;
        
        // --- CRITICAL ALBEDO FIX: Soft Illumination Division ---
        // Clamping to 1e-4 amplified dark pixel noise by 10,000x, causing neon splotches.
        // We clamp to 0.4 to mathematically cap the maximum brightness boost to 2.5x.
        estimatedShading = math.max(estimatedShading, 0.4); 

        // Recover Albedo: R(x,y) = I(x,y) / S(x,y)
        var origPixel = original.getPixel(x, y);
        int rAlbedo = ((origPixel.r / 255.0 / estimatedShading) * 255.0).round().clamp(0, 255);
        int gAlbedo = ((origPixel.g / 255.0 / estimatedShading) * 255.0).round().clamp(0, 255);
        int bAlbedo = ((origPixel.b / 255.0 / estimatedShading) * 255.0).round().clamp(0, 255);

        albedoTexImg.setPixelRgb(x, y, rAlbedo, gAlbedo, bAlbedo);
      }
    }

    return {
      'albedo': Uint8List.fromList(img.encodePng(albedoTexImg)),
      'depth': Uint8List.fromList(img.encodePng(depthTexImg)),
      'original': Uint8List.fromList(img.encodePng(original)),
    };
  }

  static Future<ui.Image> createUiImageFromBytes(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (img) => completer.complete(img));
    return completer.future;
  }
}
