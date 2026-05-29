import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lighting_state.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({super.key});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<LightingState>().setActiveTab(1);
    });
  }

  int _currentIndex = 0;
  int _lastExpandedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24.0), topRight: Radius.circular(24.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {

              final state = context.read<LightingState>();

              setState(() {

                if (_currentIndex == -1) {

                  _currentIndex = _lastExpandedIndex;

                  state.setActiveTab(
                    _currentIndex + 1,
                  );

                } else {

                  _lastExpandedIndex = _currentIndex;

                  _currentIndex = -1;
                }

              });
            },
            child: Container(
              width: 40,
              height: 4,
              decoration: const BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.all(Radius.circular(2))),
            ),
          ),
          const SizedBox(height: 12),
          if (_currentIndex != -1) _buildActiveTabContent(context),
          BottomNavigationBar(
            backgroundColor: Colors.transparent,
            selectedItemColor: Colors.blueAccent,
            unselectedItemColor: Colors.white54,
            currentIndex: _currentIndex == -1 ? _lastExpandedIndex : _currentIndex, // Fallback to 0 if minimized just for UI, but handle tap below
            type: BottomNavigationBarType.fixed,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            elevation: 0,

            onTap: (idx) {
              final state = context.read<LightingState>();
              setState(() {
                if (_currentIndex == idx) {
                  _currentIndex = -1; // Minimize on double tap
                } else {
                  _currentIndex = idx;
                }
              });
              // Sync active tab to LightingState so the canvas knows which view to show
              if (_currentIndex >= 0) {
                state.setActiveTab(_currentIndex + 1);
              }
            },
            items: [
              BottomNavigationBarItem(
                icon: Icon(
                  _currentIndex == 0
                  ? Icons.lightbulb
                  : Icons.lightbulb_outline,
                ),
                label: 'Lights',
              ),

              BottomNavigationBarItem(
                icon: Icon(
                  _currentIndex == 1
                  ? Icons.tune
                  : Icons.tune_outlined,
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
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ElevatedButton.icon(
            onPressed: state.addLight,
            icon: const Icon(Icons.add_circle),
            label: const Text("Add First Light Source"),
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
                      selected: state.selectedLightIndex == i,
                      onSelected: (_) => state.selectLight(i),
                      selectedColor: Colors.blue.withAlpha(77),
                    ),
                  ),
                if (state.lights.length < 4)
                  IconButton(icon: const Icon(Icons.add_circle, color: Colors.blueAccent), onPressed: state.addLight),
                if (state.lights.isNotEmpty)
                  IconButton(icon: const Icon(Icons.remove_circle, color: Colors.redAccent), onPressed: state.removeLight),
              ],
            ),
          ),
          if (activeLight != null) ...[
            const SizedBox(height: 16),
            _buildSlider(
              label: "Intensity",
              value: activeLight.intensity,
              min: 50.0, max: 10000.0,
              onChanged: (v) => state.updateSelectedLight(intensity: v),
            ),
            _buildSlider(
              label: "Light Depth",
              value: activeLight.pos.z,
              min: -400.0, max: 2400.0,
              onChanged: (v) => state.updateSelectedLightPos(activeLight.pos.x, activeLight.pos.y, z: v),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Color", style: TextStyle(color: Colors.white70, fontSize: 13)),
                Wrap(
                  spacing: 8,
                  children: [Colors.white, Colors.orangeAccent, Colors.cyanAccent, Colors.greenAccent, Colors.purpleAccent, Colors.redAccent].map((color) {
                    return GestureDetector(
                      onTap: () => state.updateSelectedLight(color: color),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: activeLight.color == color ? Border.all(color: Colors.blue, width: 3) : null,
                        ),
                      ),
                    );
                  }).toList(),
                )
              ],
            )
          ]
        ],
      ),
    );
  }

  Widget _buildControlsTab(BuildContext context) {
    final state = context.watch<LightingState>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          _buildSlider(
            label: "Ambient Intensity",
            value: state.ambientIntensity,
            min: 0.0, max: 1.0,
            onChanged: (v) => state.updateGlobalParameters(newAmbientIntensity: v),
          ),
          _buildSlider(
            label: "Global Roughness",
            value: state.roughness,
            min: 0.05, max: 1.0,
            onChanged: (v) => state.updateGlobalParameters(newRoughness: v),
          ),
          _buildSlider(
            label: "Global Metallic",
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
        ],
      ),
    );
  }

  Widget _buildSlider({required String label, required double value, required double min, required double max, required ValueChanged<double> onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider( value: value, min: min, max: max, activeColor: Colors.blueAccent, inactiveColor: Colors.white24, onChanged: onChanged ),
        ],
      ),
    );
  }
}