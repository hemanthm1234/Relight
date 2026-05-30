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
    final Float32List depthData = args['depthData'];

    img.Image? original = img.decodeImage(imageBytes);
    if (original == null) throw Exception("Cannot parse image source.");

    int w = original.width;
    int h = original.height;

    // 1. Synthesize High Resolution Depth Texture Asset Buffer
    img.Image depthTexImg = img.Image(width: w, height: h, numChannels: 1, format: img.Format.uint8);
    // Depth Anything outputs continuous 518x518 data. Sample back symmetrically to original proportions.
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double modelX = (x / w) * 518.0;
        double modelY = (y / h) * 518.0;
        
        int mX = modelX.floor().clamp(0, 517);
        int mY = modelY.floor().clamp(0, 517);
        double depthVal = depthData[mY * 518 + mX].toDouble();
        
        depthTexImg.setPixelR(x, y, (depthVal * 255.0).round().clamp(0, 255));
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
        estimatedShading = estimatedShading.clamp(1e-4, 1.0); // Safe threshold floor clamping bounds

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
