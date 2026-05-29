import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class DepthInferenceService {
  Interpreter? _interpreter;
  bool _isInitialized = false;
  String? _currentModelPath;
  static const int modelInputSize = 518; // Size required for quantized Depth-Anything mobile profile

  bool get isInitialized => _isInitialized;
  String? get currentModelPath => _currentModelPath;

  Future<void> initializeEngine(String modelAssetPath) async {
    if (_isInitialized && _currentModelPath == modelAssetPath && _interpreter != null) {
      debugPrint("Depth engine already initialized with model: $modelAssetPath.");
      return;
    }
    
    // Close existing interpreter
    try {
      _interpreter?.close();
    } catch (e) {
      debugPrint("Error closing previous interpreter: $e");
    }
    _interpreter = null;
    _isInitialized = false;
    _currentModelPath = null;

    try {
      final options = InterpreterOptions();
      options.threads = 4;
      
      _interpreter = await Interpreter.fromAsset(
        modelAssetPath,
        options: options,
      );
      _isInitialized = true;
      _currentModelPath = modelAssetPath;
      debugPrint("Local Hardware Accelerated Depth engine online with model: $modelAssetPath.");
    } catch (e) {
      debugPrint("NNAPI initialization failed. Falling back to default CPU interpreter execution: $e");
      try {
        _interpreter = await Interpreter.fromAsset(modelAssetPath);
        _isInitialized = true;
        _currentModelPath = modelAssetPath;
      } catch (criticalError) {
        debugPrint("Critical Error mapping TFLite model binary: $criticalError");
        rethrow;
      }
    }
  }

  // Orchestrate inference flow using an isolated thread
  Future<Float32List> runLocalInference(File imageFile) async {
    if (!_isInitialized || _interpreter == null) {
      throw Exception("TFLite runtime context not ready.");
    }

    final rawBytes = await imageFile.readAsBytes();
    
    // Perform array restructuring, inference, and normalization in a separate Isolate thread
    // This totally unblocks the main isolate so the UI spinner remains smooth
    final Float32List computedDepthMatrix = await compute(_fullInferenceTask, {
      'address': _interpreter!.address,
      'rawBytes': rawBytes,
      'modelInputSize': modelInputSize,
    });

    return computedDepthMatrix;
  }

  static Float32List _fullInferenceTask(Map<String, dynamic> args) {
    final int address = args['address'];
    final Uint8List rawBytes = args['rawBytes'];
    final int inputSize = args['modelInputSize'];

    // 1. Preprocess
    img.Image? decoded = img.decodeImage(rawBytes);
    if (decoded == null) throw Exception("Failed to parse image formats.");

    img.Image resized = img.copyResize(decoded, width: inputSize, height: inputSize);
    final tensorBuffer = Float32List(1 * 3 * inputSize * inputSize);

    int pixelIndex = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        img.Pixel pixel = resized.getPixel(x, y);
        tensorBuffer[pixelIndex * 3] = pixel.r / 255.0;
        tensorBuffer[pixelIndex * 3 + 1] = pixel.g / 255.0;
        tensorBuffer[pixelIndex * 3 + 2] = pixel.b / 255.0;
        pixelIndex++;
      }
    }

    // 2. Initialize Interpreter from address
    Interpreter isolateInterpreter = Interpreter.fromAddress(address);

    var outputBuffer = List.generate(
      1, (_) => List.generate(
        inputSize, (_) => List.generate(
          inputSize, (_) => List.filled(1, 0.0)
        )
      )
    );

    // 3. Run Inference synchronously inside the isolate
    isolateInterpreter.run(tensorBuffer.reshape([1, inputSize, inputSize, 3]), outputBuffer);

    // 4. Flatten and Normalize
    final Float32List flattenedDepthMap = Float32List(inputSize * inputSize);
    int index = 0;
    
    double minVal = double.infinity;
    double maxVal = double.negativeInfinity;
    
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        double val = (outputBuffer[0][y][x][0] as num).toDouble();
        if (val < minVal) minVal = val;
        if (val > maxVal) maxVal = val;
      }
    }
    
    double range = (maxVal - minVal) > 0 ? (maxVal - minVal) : 1.0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        flattenedDepthMap[index++] = ((outputBuffer[0][y][x][0] as num).toDouble() - minVal) / range;
      }
    }

    return flattenedDepthMap;
  }

  void dispose() {
    _interpreter?.close();
  }
}
