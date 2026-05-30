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

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
          if (_currentIndex != -1) _buildActiveTabContent(context),
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
                if (state.lights.length < 4)
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
            _buildSlider(
              label: "Intensity",
              value: activeLight.intensity,
              min: 1000.0, max: 500000.0,
              onChanged: (v) => state.updateSelectedLight(intensity: v),
            ),
            _buildSlider(
              label: "Light Depth (Z)",
              value: activeLight.pos.z,
              min: 0.0, max: 1.0,
              onChanged: (v) => state.updateSelectedLightPos(activeLight.pos.x, activeLight.pos.y, z: v),
            ),
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
                  children: [
                    Colors.white,
                    Colors.orangeAccent,
                    Colors.cyanAccent,
                    Colors.greenAccent,
                    Colors.purpleAccent,
                    Colors.redAccent,
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
                  }).toList(),
                )
              ],
            ),
            const SizedBox(height: 4),
          ]
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
                  label: "Light Radius",
                  value: state.lightRadius,
                  min: 500.0, max: 5000.0,
                  onChanged: (v) => state.updateGlobalParameters(newLightRadius: v),
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
                RadialFovDial(
                  value: state.fov,
                  min: 30.0,
                  max: 150.0,
                  onChanged: (v) => state.updateGlobalParameters(newFov: v),
                ),
                const SizedBox(height: 6),
                NumberInputField(
                  label: "Z-Min (Near)",
                  value: state.zMinRatio,
                  onChanged: (v) => state.updateGlobalParameters(newZMin: v),
                ),
                NumberInputField(
                  label: "Z-Max (Far)",
                  value: state.zMaxRatio,
                  onChanged: (v) => state.updateGlobalParameters(newZMax: v),
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
                    label,
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
                  value.toStringAsFixed(2),
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
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
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