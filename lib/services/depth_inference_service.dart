import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class DepthInferenceService {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  static const int modelInputSize = 518; // Size required for quantized Depth-Anything-V2-Small mobile profile

  bool get isInitialized => _isInitialized;

  Future<void> initializeEngine() async {
    if (_isInitialized) return;
    try {
      final options = InterpreterOptions();
      options.threads = 4;
      
      _interpreter = await Interpreter.fromAsset(
        'assets/models/depth_anything_v2.tflite',
        options: options,
      );
      _isInitialized = true;
      debugPrint("Local Hardware Accelerated Depth-Anything-V2 engine online.");
    } catch (e) {
      debugPrint("NNAPI initialization failed. Falling back to default CPU interpreter execution: $e");
      try {
        _interpreter = await Interpreter.fromAsset('assets/models/depth_anything_v2.tflite');
        _isInitialized = true;
      } catch (criticalError) {
        debugPrint("Critical Error mapping TFLite model binary: $criticalError");
      }
    }
  }

  // Orchestrate inference flow using an isolated thread
  Future<Float32List> runLocalInference(File imageFile) async {
    if (!_isInitialized || _interpreter == null) {
      throw Exception("TFLite runtime context not ready.");
    }

    final rawBytes = await imageFile.readAsBytes();
    // Move array restructuring and normalization into a separate Isolate thread
    final Float32List preprocessedTensor = await compute(_preprocessImageThread, rawBytes);

    // Prepare output tensor payload configuration matching: [1, 518, 518, 1]
    var outputBuffer = List.generate(
      1, (_) => List.generate(
        modelInputSize, (_) => List.generate(
          modelInputSize, (_) => List.filled(1, 0.0)
        )
      )
    );

    // Forwarding pass across the local silicon array
    _interpreter!.run(preprocessedTensor.reshape([1, modelInputSize, modelInputSize, 3]), outputBuffer);

    // Flatten multi-dimensional output array to an optimized single continuous Float32 list
    final Float32List flattenedDepthMap = Float32List(modelInputSize * modelInputSize);
    int index = 0;
    
    // Find absolute boundaries for localized linear contrast scaling
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    
    for (int y = 0; y < modelInputSize; y++) {
      for (int x = 0; x < modelInputSize; x++) {
        double val = outputBuffer[0][y][x][0];
        if (val < minVal) minVal = val;
        if (val > maxVal) maxVal = val;
      }
    }
    
    double range = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;

    for (int y = 0; y < modelInputSize; y++) {
      for (int x = 0; x < modelInputSize; x++) {
        // Linearly normalize depth results to full 0.0 - 1.0 space metrics
        flattenedDepthMap[index++] = (outputBuffer[0][y][x][0] - minVal) / range;
      }
    }

    return flattenedDepthMap;
  }

  static Float32List _preprocessImageThread(Uint8List rawBytes) {
    img.Image? decoded = img.decodeImage(rawBytes);
    if (decoded == null) throw Exception("Failed to parse image formats.");

    img.Image resized = img.copyResize(decoded, width: modelInputSize, height: modelInputSize);
    final tensorBuffer = Float32List(1 * 3 * modelInputSize * modelInputSize);
    int channelStride = modelInputSize * modelInputSize;

    int pixelIndex = 0;
    for (int y = 0; y < modelInputSize; y++) {
      for (int x = 0; x < modelInputSize; x++) {
        img.Pixel pixel = resized.getPixel(x, y);

        // Map RGB channels down to linear normalization ranges [0.0, 1.0]
        double r = pixel.r / 255.0;
        double g = pixel.g / 255.0;
        double b = pixel.b / 255.0;

        // Interleaved/HWC data structure arrangement : [R, G, B, R, G, B...]
        tensorBuffer[pixelIndex * 3] = r;
        tensorBuffer[pixelIndex * 3 + 1] = g;
        tensorBuffer[pixelIndex * 3 + 2] = b;
        pixelIndex++;
      }
    }
    return tensorBuffer;
  }

  void dispose() {
    _interpreter?.close();
  }
}
