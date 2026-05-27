import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class LightSource {
  Vector3 pos;
  Color color;
  double intensity;

  LightSource({
    required this.pos,
    required this.color,
    required this.intensity,
  });
}

class LightingState extends ChangeNotifier {
  // View Modes: 0=Lit, 1=Original, 2=Albedo, 3=Depth, 4=Normal
  int viewMode = 1; // Default to Original
  bool isLightingEnabled = false;

  List<LightSource> lights = [];
  int selectedLightIndex = -1;

  double roughness = 0.4;
  double metallic = 0.1;
  double shadowSoftness = 0.5;
  Color ambientColor = const Color(0xFF1A1A1A);

  void setViewMode(int mode) {
    viewMode = mode;
    notifyListeners();
  }

  void toggleLighting(bool enabled) {
    isLightingEnabled = enabled;
    viewMode = enabled ? 0 : 1;
    notifyListeners();
  }

  void addLight() {
    if (lights.length < 4) {
      lights.add(LightSource(
        pos: Vector3(200.0, 300.0, 200.0),
        color: Colors.white,
        intensity: 1500.0,
      ));
      selectedLightIndex = lights.length - 1;
      // Auto-enable lighting if not enabled
      if (!isLightingEnabled) {
        toggleLighting(true);
      } else {
        notifyListeners();
      }
    }
  }

  void removeLight() {
    if (selectedLightIndex >= 0 && selectedLightIndex < lights.length) {
      lights.removeAt(selectedLightIndex);
      selectedLightIndex = lights.isEmpty ? -1 : 0;
      if (lights.isEmpty) {
        toggleLighting(false);
      } else {
        notifyListeners();
      }
    }
  }

  void selectLight(int index) {
    if (index >= 0 && index < lights.length) {
      selectedLightIndex = index;
      notifyListeners();
    }
  }

  void updateSelectedLightPos(double x, double y, {double? z}) {
    if (selectedLightIndex >= 0) {
      lights[selectedLightIndex].pos.x = x;
      lights[selectedLightIndex].pos.y = y;
      if (z != null) lights[selectedLightIndex].pos.z = z;
      notifyListeners();
    }
  }

  void updateSelectedLight({Color? color, double? intensity}) {
    if (selectedLightIndex >= 0) {
      if (color != null) lights[selectedLightIndex].color = color;
      if (intensity != null) lights[selectedLightIndex].intensity = intensity;
      notifyListeners();
    }
  }

  void updateGlobalParameters({
    double? newRoughness,
    double? newMetallic,
    double? newShadowSoftness,
    Color? newAmbient,
  }) {
    if (newRoughness != null) roughness = newRoughness;
    if (newMetallic != null) metallic = newMetallic;
    if (newShadowSoftness != null) shadowSoftness = newShadowSoftness;
    if (newAmbient != null) ambientColor = newAmbient;
    notifyListeners();
  }
}
