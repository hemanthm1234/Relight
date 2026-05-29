import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lighting_state.dart';

class GlobalMapSelector extends StatelessWidget {
  const GlobalMapSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LightingState>();

    return Container(
      // color: Colors.black,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 5,
      ),
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

          const SizedBox(width: 8),

          Expanded(
            child: _ViewModeBtn(
              label: "Albedo",
              mode: 2,
              current: state.viewMode,
              onTap: state.setViewMode,
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: _ViewModeBtn(
              label: "Depth",
              mode: 3,
              current: state.viewMode,
              onTap: state.setViewMode,
            ),
          ),

          const SizedBox(width: 8),

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
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: active
                ? Colors.blueAccent
                : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? Colors.white
                : Colors.white70,
          ),
        ),
      ),
    );
  }
}