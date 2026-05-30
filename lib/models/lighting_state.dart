// ============================================================================
// File: lib/models/lighting_state.dart
// Purpose: Manages the reactive global state for the 3D Relighting application.
// 
// Responsibility:
// - Represents individual light sources via the `LightSource` class (holding position, color, intensity).
// - Inherits from `ChangeNotifier` to act as the primary state container (`LightingState`).
// - Tracks view modes (Lit, Original, Albedo, Depth, Normal) and active light source selections (up to 4 lights).
// - Manages camera projection parameters (FOV, Z-min/max ratios) for the true 3D perspective frustum.
// - Encapsulates modification handlers for adding, removing, and adjusting properties of light sources
//   (position, intensity, color) and global PBR parameters (roughness, metallic, shadow softness, ambient intensity).
// ============================================================================

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
  int viewMode = 1; 
  bool isLightingEnabled = false;

  List<LightSource> lights = [];
  int selectedLightIndex = -1;

  // Material & Lighting parameters
  double roughness = 0.4;
  double metallic = 0.1;
  double shadowSoftness = 0.5;
  Color ambientColor = const Color(0xFF1A1A1A);

  // Photorealism Tuning Parameters
  double microDetailStrength = 0.0; // 0.0 = smooth (portraits), up to 5.0 for textured surfaces
  double lightRadius = 1500.0;      // UE4-style physical light attenuation bounds

  // Camera Projection Parameters
  double fov = 60.0; // In degrees (30.0 to 150.0)
  double zMinRatio = 0.1;
  double zMaxRatio = 1.5;

  double get ambientIntensity => ambientColor.r;

  int get effectiveViewMode {
    if (isLightingEnabled && viewMode == 1) return 0;
    return viewMode;
  }

  void setViewMode(int mode) {
    viewMode = mode;
    notifyListeners();
  }

  void toggleLighting(bool enabled) {
    isLightingEnabled = enabled;
    notifyListeners();
  }

  void addLight() {
    if (lights.length < 4) {
      // Spawn light at the exact center of the screen (0,0) and slightly in front of the image plane (-150.0)
      lights.add(LightSource(
        pos: Vector3(0.0, 0.0, 0.5), // Normalized depth range (0.0 to 1.0)
        color: Colors.white,
        intensity: 250000.0, // Perspective lights need higher intensity due to true inverse-square falloff
      ));
      selectedLightIndex = lights.length - 1;
      if (!isLightingEnabled) isLightingEnabled = true;
      notifyListeners();
    }
  }

  void removeLight() {
    if (selectedLightIndex >= 0 && selectedLightIndex < lights.length) {
      lights.removeAt(selectedLightIndex);
      selectedLightIndex = lights.isEmpty ? -1 : 0;
      if (lights.isEmpty) isLightingEnabled = false;
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
    double? newFov,
    double? newZMin,
    double? newZMax,
    double? newMicroDetail,
    double? newLightRadius,
  }) {
    if (newRoughness != null) roughness = newRoughness;
    if (newMetallic != null) metallic = newMetallic;
    if (newShadowSoftness != null) shadowSoftness = newShadowSoftness;
    if (newFov != null) fov = newFov;
    if (newZMin != null) zMinRatio = newZMin;
    if (newZMax != null) zMaxRatio = newZMax;
    if (newMicroDetail != null) microDetailStrength = newMicroDetail;
    if (newLightRadius != null) lightRadius = newLightRadius;
    if (newAmbientIntensity != null) {
      int v = (newAmbientIntensity * 255).clamp(0, 255).toInt();
      ambientColor = Color.fromARGB(255, v, v, v);
    }
    notifyListeners();
  }
}
