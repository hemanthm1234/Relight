import 'package:tflite_flutter/tflite_flutter.dart';
void main() async {
  final interpreter = await Interpreter.fromAsset('assets/models/depth_anything_v2.tflite');
  Interpreter interpreter2 = Interpreter.fromAddress(interpreter.address);
}
