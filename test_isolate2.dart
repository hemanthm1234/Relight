import 'package:tflite_flutter/tflite_flutter.dart';
void main() async {
  final interpreter = await Interpreter.fromAsset('assets/models/depth_anything_v2.tflite');
  final isolateInterpreter = await IsolateInterpreter.create(address: interpreter.address);
}
