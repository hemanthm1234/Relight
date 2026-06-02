// ============================================================================
// File: lib/widgets/control_panel.dart
// Purpose: Workspace configuration panel drawer.
// 
// Responsibility:
// - Renders a premium, collapsible bottom drawer displaying fine-tuning controls.
// - Manages two primary parameter tabs:
//   1. Lights: Instantiates individual light sources, tracks selections, and exposes controls for depth (Z position), color hues, and intensity.
//   2. Controls: Hosts PBR sliders to fine-tune global ambient intensity, roughness, metallicity, and shadow softness in a clean two-column grid.
// - Features a gorgeous, interactive radial focal dial for 3D Camera Field of View (FOV) adjustment.
// - Uses highly compressed custom slider layouts and shrink-wrap tap geometries to ensure zero horizontal/vertical layout overflows.
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/lighting_state.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({super.key});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  int _currentIndex = 0;
  int _lastExpandedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F13).withAlpha(245), // Premium solid obsidian dark background
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28.0),
          topRight: Radius.circular(28.0),
        ),
        border: Border(
          top: BorderSide(
            color: Colors.white.withAlpha(20),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(180),
            blurRadius: 30.0,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                if (_currentIndex == -1) {
                  _currentIndex = _lastExpandedIndex;
                } else {
                  _lastExpandedIndex = _currentIndex;
                  _currentIndex = -1;
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12.0),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: const BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
          if (_currentIndex != -1) 
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: SingleChildScrollView(
                child: _buildActiveTabContent(context),
              ),
            ),
          const SizedBox(height: 4),
          BottomNavigationBar(
            backgroundColor: Colors.transparent,
            selectedItemColor: Colors.blueAccent,
            unselectedItemColor: Colors.white.withAlpha(120),
            currentIndex: _currentIndex == -1 ? _lastExpandedIndex : _currentIndex,
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.2),
            unselectedLabelStyle: const TextStyle(fontSize: 11, letterSpacing: 0.2),
            elevation: 0,
            onTap: (idx) {
              setState(() {
                if (_currentIndex == idx) {
                  _currentIndex = -1; // Minimize on double tap
                } else {
                  _currentIndex = idx;
                }
              });
            },
            items: [
              BottomNavigationBarItem(
                icon: Icon(
                  _currentIndex == 0 ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
                  size: 22,
                ),
                label: 'Lights',
              ),
              BottomNavigationBarItem(
                icon: Icon(
                  _currentIndex == 1 ? Icons.tune_rounded : Icons.tune_outlined,
                  size: 22,
                ),
                label: 'Controls',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTabContent(BuildContext context) {
    if (_currentIndex == 0) {
      return _buildLightsTab(context);
    }
    return _buildControlsTab(context);
  }

  Widget _buildLightsTab(BuildContext context) {
    final state = context.watch<LightingState>();
    
    if (!state.isLightingEnabled || state.lights.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 24.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "No light sources active",
                style: TextStyle(
                  color: Colors.white.withAlpha(120),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: state.addLight,
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                label: const Text(
                  "Add Light Source",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final activeLight = state.selectedLightIndex >= 0 ? state.lights[state.selectedLightIndex] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < state.lights.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text("Light ${i+1}"),
                      labelStyle: TextStyle(
                        color: state.selectedLightIndex == i ? Colors.white : Colors.white.withAlpha(140),
                        fontSize: 12,
                        fontWeight: state.selectedLightIndex == i ? FontWeight.bold : FontWeight.normal,
                      ),
                      selected: state.selectedLightIndex == i,
                      onSelected: (_) => state.selectLight(i),
                      selectedColor: Colors.blueAccent.withAlpha(70),
                      backgroundColor: Colors.white.withAlpha(10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: state.selectedLightIndex == i ? Colors.blueAccent : Colors.white.withAlpha(20),
                          width: 1.0,
                        ),
                      ),
                      showCheckmark: false,
                    ),
                  ),
                if (state.lights.length < 16)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.blueAccent, size: 26),
                    onPressed: state.addLight,
                    tooltip: "Add Light Source",
                  ),
                if (state.lights.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 26),
                    onPressed: state.removeLight,
                    tooltip: "Remove Selected Light",
                  ),
              ],
            ),
          ),
          if (activeLight != null) ...[
            const SizedBox(height: 12),
            
            // Light Type Toggle
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: SegmentedButton<LightType>(
                  segments: const [
                    ButtonSegment(value: LightType.spherical, label: Text('Spherical'), icon: Icon(Icons.wb_sunny)),
                    ButtonSegment(value: LightType.conical, label: Text('Spotlight'), icon: Icon(Icons.highlight)),
                  ],
                  selected: {activeLight.type},
                  onSelectionChanged: (Set<LightType> newSelection) {
                    state.updateSelectedLight(type: newSelection.first);
                  },
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.white.withAlpha(10),
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor: Colors.blueAccent.withAlpha(80),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            _buildSlider(
              label: "Intensity",
              value: activeLight.intensity,
              min: 1000.0, max: 500000.0,
              onChanged: (v) => state.updateSelectedLight(intensity: v),
            ),

            _buildSlider(
              label: "Light Depth (Z)",
              value: activeLight.pos.z,
              min: -1.0, max: 1.0,
              onChanged: (v) => state.updateSelectedLightPos(activeLight.pos.x, activeLight.pos.y, z: v),
            ),

            _buildSlider(
              label: "Light Falloff (Decay)",
              value: activeLight.attenuationDecay,
              min: 0.1, max: 3.0,
              onChanged: (v) => state.updateSelectedLight(attenuationDecay: v),
            ),

            if (activeLight.type == LightType.conical) ...[
              _buildSlider(
                label: "Spotlight Theta (X-Y Angle)",
                value: activeLight.theta,
                min: 0.0, max: 360.0,
                onChanged: (v) => state.updateSelectedLight(theta: v),
              ),
              _buildSlider(
                label: "Spotlight Phi (Z Angle)",
                value: activeLight.phi,
                min: 0.0, max: 180.0,
                onChanged: (v) => state.updateSelectedLight(phi: v),
              ),
              _buildSlider(
                label: "Inner Cone Angle",
                value: activeLight.coneInnerAngle,
                min: 1.0, max: activeLight.coneOuterAngle - 1.0,
                onChanged: (v) => state.updateSelectedLight(coneInnerAngle: v),
              ),
              _buildSlider(
                label: "Outer Cone Angle",
                value: activeLight.coneOuterAngle,
                min: activeLight.coneInnerAngle + 1.0, max: 90.0,
                onChanged: (v) => state.updateSelectedLight(coneOuterAngle: v),
              ),
            ],

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Light Color",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ...[
                      Colors.white,
                      const Color(0xFFF25022), // Microsoft Red
                      const Color(0xFF7FBA00), // Microsoft Green
                      const Color(0xFF00A4EF), // Microsoft Blue
                      const Color(0xFFFFB900), // Microsoft Yellow
                    ].map((color) {
                      final bool isSelected = activeLight.color == color;
                      return GestureDetector(
                        onTap: () => state.updateSelectedLight(color: color),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withAlpha(120),
                                      blurRadius: 8.0,
                                      spreadRadius: 2.0,
                                    ),
                                  ]
                                : null,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.white.withAlpha(40),
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                        ),
                      );
                    }),
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            Color pickerColor = activeLight.color;
                            return AlertDialog(
                              title: const Text('Pick a color!'),
                              backgroundColor: const Color(0xFF161622),
                              content: SingleChildScrollView(
                                child: ColorPicker(
                                  pickerColor: pickerColor,
                                  onColorChanged: (Color color) {
                                    pickerColor = color;
                                    state.updateSelectedLight(color: color);
                                  },
                                  pickerAreaHeightPercent: 0.8,
                                ),
                              ),
                              actions: <Widget>[
                                TextButton(
                                  child: const Text('Done', style: TextStyle(color: Colors.blueAccent)),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withAlpha(40), width: 1.0),
                          gradient: const SweepGradient(
                            colors: [
                              Colors.red,
                              Colors.yellow,
                              Colors.green,
                              Colors.cyan,
                              Colors.blue,
                              Color(0xFFFF00FF), // Magenta
                              Colors.red,
                            ],
                          ),
                        ),
                        child: const Icon(Icons.palette, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildControlsTab(BuildContext context) {
    final state = context.watch<LightingState>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Global PBR/Material variables
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4.0, bottom: 4.0),
                  child: Text(
                    "PBR Properties",
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                _buildSlider(
                  label: "Ambient Intensity",
                  value: state.ambientIntensity,
                  min: 0.0, max: 1.0,
                  onChanged: (v) => state.updateGlobalParameters(newAmbientIntensity: v),
                ),
                _buildSlider(
                  label: "Roughness",
                  value: state.roughness,
                  min: 0.0, max: 1.0,
                  onChanged: (v) => state.updateGlobalParameters(newRoughness: v),
                ),
                _buildSlider(
                  label: "Metallic",
                  value: state.metallic,
                  min: 0.0, max: 1.0,
                  onChanged: (v) => state.updateGlobalParameters(newMetallic: v),
                ),
                _buildSlider(
                  label: "Shadow Softness",
                  value: state.shadowSoftness,
                  min: 0.1, max: 2.0,
                  onChanged: (v) => state.updateGlobalParameters(newShadowSoftness: v),
                ),
                _buildSlider(
                  label: "Micro Detail",
                  value: state.microDetailStrength,
                  min: 0.0, max: 5.0,
                  onChanged: (v) => state.updateGlobalParameters(newMicroDetail: v),
                ),
                _buildSlider(
                  label: "De-Lighting (Albedo Mix)",
                  value: state.albedoBlend,
                  min: 0.0, max: 1.0,
                  onChanged: (v) => state.updateGlobalParameters(newAlbedoBlend: v),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right Column: Camera projection variables & Focal radial dial
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 4.0, bottom: 4.0),
                    child: Text(
                      "3D Camera Projection",
                      style: TextStyle(
                        color: Colors.blueAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _buildSlider(
                  label: "Field of View (FOV)",
                  value: state.fov,
                  min: 30.0,
                  max: 150.0,
                  onChanged: (v) => state.updateGlobalParameters(newFov: v),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Depth Range (Z)",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                VerticalDepthRange(
                  zMin: state.zMinRatio,
                  zMax: state.zMaxRatio,
                  onZMinChanged: (v) => state.updateGlobalParameters(newZMin: v),
                  onZMaxChanged: (v) => state.updateGlobalParameters(newZMax: v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return DebouncedSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
    );
  }
}

class DebouncedSlider extends StatefulWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const DebouncedSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<DebouncedSlider> createState() => _DebouncedSliderState();
}

class _DebouncedSliderState extends State<DebouncedSlider> {
  late double _localValue;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
  }

  @override
  void didUpdateWidget(DebouncedSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_debounceTimer == null || !_debounceTimer!.isActive) {
      _localValue = widget.value;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onChanged(double newValue) {
    setState(() {
      _localValue = newValue;
    });
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 32), () {
      widget.onChanged(newValue);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: Colors.white.withAlpha(200),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _localValue.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
              activeTrackColor: Colors.blueAccent,
              inactiveTrackColor: Colors.white.withAlpha(15),
              thumbColor: Colors.blueAccent,
              overlayColor: Colors.blueAccent.withAlpha(30),
            ),
            child: SizedBox(
              height: 24,
              child: Slider(
                value: _localValue,
                min: widget.min,
                max: widget.max,
                onChanged: _onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM INTERACTIVE RADIAL GAUGE DIAL FOR FIELD OF VIEW IN DEGREES
// ─────────────────────────────────────────────────────────────────────────────
class RadialFovDial extends StatefulWidget {
  final double value; // In human-readable degrees
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const RadialFovDial({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<RadialFovDial> createState() => _RadialFovDialState();
}

class _RadialFovDialState extends State<RadialFovDial> {
  void _handleGesture(Offset localPosition) {
    const center = Offset(41, 41); // Size is 82x82
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    
    double angle = math.atan2(dy, dx);
    double degrees = angle * 180 / math.pi;
    if (degrees < 0) degrees += 360;

    double relativeAngle = degrees - 135.0;
    if (relativeAngle < 0) relativeAngle += 360.0;
    
    if (relativeAngle > 270.0) {
       if (relativeAngle < (270.0 + 45.0)) {
           relativeAngle = 270.0;
       } else {
           relativeAngle = 0.0;
       }
    }

    double fraction = relativeAngle / 270.0;
    double newValue = widget.min + fraction * (widget.max - widget.min);
    
    widget.onChanged(newValue);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onPanUpdate: (details) => _handleGesture(details.localPosition),
            onTapDown: (details) => _handleGesture(details.localPosition),
            child: CustomPaint(
              size: const Size(82, 82),
              painter: _FovDialPainter(
                value: widget.value,
                min: widget.min,
                max: widget.max,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Focal Field of View",
            style: TextStyle(
              color: Colors.white.withAlpha(140),
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FovDialPainter extends CustomPainter {
  final double value;
  final double min;
  final double max;

  _FovDialPainter({
    required this.value,
    required this.min,
    required this.max,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2 - 6;

    // Draw background track arc
    final Paint trackPaint = Paint()
      ..color = Colors.white.withAlpha(12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    
    // We draw a gorgeous 260-degree arc from bottom-left to bottom-right
    const double startAngle = 135 * math.pi / 180;
    const double sweepAngle = 270 * math.pi / 180;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Draw active track arc
    final double norm = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final Paint activePaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      norm * sweepAngle,
      false,
      activePaint,
    );

    // Draw indicators inside
    final Paint tickPaint = Paint()
      ..color = Colors.white.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 0; i <= 8; i++) {
      final double angle = startAngle + (i / 8) * sweepAngle;
      final Offset p1 = Offset(
        center.dx + (radius - 7) * math.cos(angle),
        center.dy + (radius - 7) * math.sin(angle),
      );
      final Offset p2 = Offset(
        center.dx + (radius - 3) * math.cos(angle),
        center.dy + (radius - 3) * math.sin(angle),
      );
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Draw glowing thumb pointer
    final double currentAngle = startAngle + norm * sweepAngle;
    final Offset thumbPos = Offset(
      center.dx + radius * math.cos(currentAngle),
      center.dy + radius * math.sin(currentAngle),
    );

    final Paint thumbGlow = Paint()
      ..color = Colors.blueAccent.withAlpha(80)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(thumbPos, 6.0, thumbGlow);

    final Paint thumbPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(thumbPos, 3.5, thumbPaint);

    // Draw digital readout inside dial center
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: "${value.round()}°",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _FovDialPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.min != min || oldDelegate.max != max;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATEFUL TEXT INPUT COMPONENT FOR EXACT NUMERICAL PARAMS (Z-MIN / Z-MAX)
// ─────────────────────────────────────────────────────────────────────────────
class NumberInputField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const NumberInputField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<NumberInputField> createState() => _NumberInputFieldState();
}

class _NumberInputFieldState extends State<NumberInputField> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(2));
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _submitValue();
      }
    });
  }

  @override
  void didUpdateWidget(covariant NumberInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (!_focusNode.hasFocus) {
        final currentParsed = double.tryParse(_controller.text);
        if (currentParsed != widget.value) {
          _controller.text = widget.value.toStringAsFixed(2);
        }
      }
    }
  }

  void _submitValue() {
    final parsed = double.tryParse(_controller.text);
    if (parsed != null) {
      widget.onChanged(parsed);
    } else {
      _controller.text = widget.value.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              widget.label,
              style: TextStyle(
                color: Colors.white.withAlpha(200),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 50,
            height: 24,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                filled: true,
                fillColor: Colors.white.withAlpha(15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              onSubmitted: (_) => _submitValue(),
            ),
          ),
        ],
      ),
    );
  }
}

class VerticalDepthRange extends StatefulWidget {
  final double zMin;
  final double zMax;
  final ValueChanged<double> onZMinChanged;
  final ValueChanged<double> onZMaxChanged;

  const VerticalDepthRange({
    super.key,
    required this.zMin,
    required this.zMax,
    required this.onZMinChanged,
    required this.onZMaxChanged,
  });

  @override
  State<VerticalDepthRange> createState() => _VerticalDepthRangeState();
}

class _VerticalDepthRangeState extends State<VerticalDepthRange> {
  final double _minScale = 0.1;
  final double _maxScale = 20.0;
  
  bool _isDraggingMin = false;
  bool _isDraggingMax = false;

  void _handleDrag(Offset localPosition, double height) {
    final double padding = 16.0;
    final double trackHeight = height - padding * 2;
    double dy = (localPosition.dy - padding).clamp(0.0, trackHeight);
    
    double fraction = 1.0 - (dy / trackHeight);
    double val = _minScale + fraction * (_maxScale - _minScale);
    
    if (_isDraggingMin) {
      if (val >= widget.zMax - 0.1) val = widget.zMax - 0.1;
      widget.onZMinChanged(val);
    } else if (_isDraggingMax) {
      if (val <= widget.zMin + 0.1) val = widget.zMin + 0.1;
      widget.onZMaxChanged(val);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180, // Reduced height to fit without scrolling
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double h = constraints.maxHeight;
          final double padding = 16.0;
          final double trackHeight = h - padding * 2;
          
          double minFrac = (widget.zMin - _minScale) / (_maxScale - _minScale);
          double maxFrac = (widget.zMax - _minScale) / (_maxScale - _minScale);
          
          // Clamp fractions just in case
          minFrac = minFrac.clamp(0.0, 1.0);
          maxFrac = maxFrac.clamp(0.0, 1.0);
          
          double minY = padding + trackHeight * (1.0 - minFrac);
          double maxY = padding + trackHeight * (1.0 - maxFrac);

          return GestureDetector(
            onVerticalDragDown: (details) {
              double distMin = (details.localPosition.dy - minY).abs();
              double distMax = (details.localPosition.dy - maxY).abs();
              
              if (distMin < distMax) {
                _isDraggingMin = true;
              } else {
                _isDraggingMax = true;
              }
              _handleDrag(details.localPosition, h);
            },
            onVerticalDragUpdate: (details) {
              _handleDrag(details.localPosition, h);
            },
            onVerticalDragEnd: (_) {
              _isDraggingMin = false;
              _isDraggingMax = false;
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Background Track
                Positioned(
                  left: constraints.maxWidth / 2 - 2,
                  top: padding,
                  bottom: padding,
                  width: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Active Track (between min and max)
                Positioned(
                  left: constraints.maxWidth / 2 - 2,
                  top: maxY,
                  bottom: h - minY,
                  width: 4,
                  child: Container(
                    color: Colors.blueAccent,
                  ),
                ),
                // Min indicator (Left)
                Positioned(
                  left: 0,
                  top: minY - 12,
                  right: constraints.maxWidth / 2 + 10,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "Z-Min\n${widget.zMin.toStringAsFixed(1)}",
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white70, fontSize: 10, height: 1.1),
                    ),
                  ),
                ),
                // Min Handle
                Positioned(
                  left: constraints.maxWidth / 2 - 8,
                  top: minY - 8,
                  width: 16,
                  height: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 4)],
                    ),
                  ),
                ),
                // Max indicator (Right)
                Positioned(
                  left: constraints.maxWidth / 2 + 10,
                  top: maxY - 12,
                  right: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Z-Max\n${widget.zMax.toStringAsFixed(1)}",
                      style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, height: 1.1),
                    ),
                  ),
                ),
                // Max Handle
                Positioned(
                  left: constraints.maxWidth / 2 - 8,
                  top: maxY - 8,
                  width: 16,
                  height: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: Colors.blueAccent.withAlpha(100), blurRadius: 6)],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}