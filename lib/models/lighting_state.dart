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
  int viewMode = 1; // Default to Original (used by Maps tab)
  bool isLightingEnabled = false;

  // Active bottom nav tab: 0=Maps, 1=Lights, 2=Controls
  int activeTab = 1;

  List<LightSource> lights = [];
  int selectedLightIndex = -1;

  double roughness = 0.4;
  double metallic = 0.1;
  double shadowSoftness = 0.5;
  Color ambientColor = const Color(0xFF1A1A1A);

  double get ambientIntensity => ambientColor.red / 255.0;

  /// Compute the effective view mode based on the active tab.
  /// Maps tab: use user-selected viewMode (Original/Albedo/Depth/Normal)
  /// Lights/Controls tabs: show Lit (0) if lighting enabled, Original (1) if not
  int get effectiveViewMode {
    if (viewMode == 1) {
      return isLightingEnabled ? 0 : 1;
    }
    return viewMode;
  }

  void setActiveTab(int tab) {
    activeTab = tab;
    notifyListeners();
  }

  void setViewMode(int mode) {
    viewMode = mode;
    notifyListeners();
  }

  void toggleLighting(bool enabled) {
    isLightingEnabled = enabled;
    // Don't change viewMode — the effectiveViewMode getter handles this
    notifyListeners();
  }

  void addLight() {
    if (lights.length < 4) {
      lights.add(LightSource(
        pos: Vector3(150.0, 150.0, 200.0),
        color: Colors.white,
        intensity: 1500.0,
      ));
      selectedLightIndex = lights.length - 1;
      // Auto-enable lighting if not enabled
      if (!isLightingEnabled) {
        isLightingEnabled = true;
      }
      notifyListeners();
    }
  }

  void removeLight() {
    if (selectedLightIndex >= 0 && selectedLightIndex < lights.length) {
      lights.removeAt(selectedLightIndex);
      selectedLightIndex = lights.isEmpty ? -1 : 0;
      if (lights.isEmpty) {
        isLightingEnabled = false;
      }
      notifyListeners();
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
    double? newAmbientIntensity,
  }) {
    if (newRoughness != null) roughness = newRoughness;
    if (newMetallic != null) metallic = newMetallic;
    if (newShadowSoftness != null) shadowSoftness = newShadowSoftness;
    if (newAmbientIntensity != null) {
      int v = (newAmbientIntensity * 255).clamp(0, 255).toInt();
      ambientColor = Color.fromARGB(255, v, v, v);
    }
    notifyListeners();
  }
}
