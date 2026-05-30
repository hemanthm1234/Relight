// ============================================================================
// File: lib/widgets/map_selector.dart
// Purpose: Multi-map buffer view selection widget.
// 
// Responsibility:
// - Displays a modern, floating toggle bar at the top of the active workspace.
// - Allows the user to select between four primary preview channels:
//   1. Original: The unmodified target image.
//   2. Albedo: The reflection map isolated from shading.
//   3. Depth: The monocular depth estimation map.
//   4. Normal: The surface orientation/bump normal vector map.
// - Dispatches visual view mode updates to the unified `LightingState` listener.
// - Built with an elegant segmented glass design and glowing animated active tabs.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lighting_state.dart';

class GlobalMapSelector extends StatelessWidget {
  const GlobalMapSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LightingState>();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF141418), // Deep premium dark background
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withAlpha(12),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(3.0),
      child: Row(
        children: [
          Expanded(
            child: _ViewModeBtn(
              label: "Original",
              mode: 1,
              current: state.viewMode,
              onTap: state.setViewMode,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _ViewModeBtn(
              label: "Albedo",
              mode: 2,
              current: state.viewMode,
              onTap: state.setViewMode,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _ViewModeBtn(
              label: "Depth",
              mode: 3,
              current: state.viewMode,
              onTap: state.setViewMode,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _ViewModeBtn(
              label: "Normal",
              mode: 4,
              current: state.viewMode,
              onTap: state.setViewMode,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewModeBtn extends StatelessWidget {
  final String label;
  final int mode;
  final int current;
  final Function(int) onTap;

  const _ViewModeBtn({
    required this.label,
    required this.mode,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = current == mode;

    return GestureDetector(
      onTap: () => onTap(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.blueAccent.withAlpha(60),
                    blurRadius: 8.0,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white.withAlpha(140),
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}