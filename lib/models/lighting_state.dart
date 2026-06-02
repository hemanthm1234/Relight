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

enum LightType { spherical, conical }

class LightSource {
  LightType type;
  Vector3 pos;
  Color color;
  double intensity;
  double attenuationDecay;
  double coneInnerAngle; // In degrees
  double coneOuterAngle; // In degrees
  
  // Direction angles for Conical light
  double theta; // Angle in x-y plane from x-axis (0 to 360)
  double phi;   // Azimuthal angle from z-axis (0 to 180)

  LightSource({
    this.type = LightType.spherical,
    required this.pos,
    required this.color,
    required this.intensity,
    this.attenuationDecay = 2.0,
    this.coneInnerAngle = 15.0,
    this.coneOuterAngle = 25.0,
    this.theta = 0.0,
    this.phi = 180.0, // Default pointing straight back at the camera (z = -1)
  });
}

class LightingState extends ChangeNotifier {
  int viewMode = 1; 
  bool isLightingEnabled = false;

  List<LightSource> lights = [];
  int selectedLightIndex = -1;

  // Material & Lighting parameters
  double roughness = 0.2;
  double metallic = 0.1;
  double shadowSoftness = 0.5;
  Color ambientColor = const Color(0xFF1A1A1A);

  // Photorealism Tuning Parameters
  double microDetailStrength = 0.0; // 0.0 = smooth (portraits), up to 5.0 for textured surfaces
  double albedoBlend = 0.4;         // Controls De-Lighting Strength

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
    if (lights.length < 16) { // Expanded max to 16 lights
      // Spawn light at the exact center of the screen
      lights.add(LightSource(
        type: LightType.spherical,
        pos: Vector3(0.0, 0.0, 0.5), // Normalized depth range (0.0 to 1.0)
        color: Colors.white,
        intensity: 250000.0,
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

  void updateSelectedLight({
    LightType? type,
    Color? color, 
    double? intensity, 
    double? attenuationDecay,
    double? coneInnerAngle,
    double? coneOuterAngle,
    double? theta,
    double? phi,
  }) {
    if (selectedLightIndex >= 0) {
      final l = lights[selectedLightIndex];
      if (type != null) l.type = type;
      if (color != null) l.color = color;
      if (intensity != null) l.intensity = intensity;
      if (attenuationDecay != null) l.attenuationDecay = attenuationDecay;
      if (coneInnerAngle != null) l.coneInnerAngle = coneInnerAngle;
      if (coneOuterAngle != null) l.coneOuterAngle = coneOuterAngle;
      if (theta != null) l.theta = theta;
      if (phi != null) l.phi = phi;
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
    double? newAlbedoBlend,
  }) {
    if (newRoughness != null) roughness = newRoughness;
    if (newMetallic != null) metallic = newMetallic;
    if (newShadowSoftness != null) shadowSoftness = newShadowSoftness;
    if (newFov != null) fov = newFov;
    if (newZMin != null) zMinRatio = newZMin;
    if (newZMax != null) zMaxRatio = newZMax;
    if (newMicroDetail != null) microDetailStrength = newMicroDetail;
    if (newAlbedoBlend != null) albedoBlend = newAlbedoBlend;
    if (newAmbientIntensity != null) {
      int v = (newAmbientIntensity * 255).clamp(0, 255).toInt();
      ambientColor = Color.fromARGB(255, v, v, v);
    }
    notifyListeners();
  }
}
