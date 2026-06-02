// ============================================================================
// File: lib/widgets/relight_canvas.dart
// Purpose: Interactive rendering canvas and gesture coordinate hub.
//
// Responsibility:
// - Computes aspect-ratio-aware bounding constraints for the workspace image.
// - Translates touch/pan gestures into origin-centered world coordinates
//   matching the shader's `(uv - 0.5) * u_DrawSize` math.
// - Houses `PBRShaderPainter` which binds GPU textures and forwards all
//   PBR/lighting/camera uniform vectors to the fragment shader.
// - Draws interactive light indicators with depth/intensity proportional sizing.
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lighting_state.dart';

class RelightCanvas extends StatefulWidget {
  final ui.Image albedoTexture;
  final ui.Image originalTexture;
  final ui.Image depthTexture;
  final ui.FragmentShader compiledShader;

  const RelightCanvas({
    super.key,
    required this.albedoTexture,
    required this.originalTexture,
    required this.depthTexture,
    required this.compiledShader,
  });

  @override
  State<RelightCanvas> createState() => _RelightCanvasState();
}

class _RelightCanvasState extends State<RelightCanvas> {
  Rect _computeFittedRect(Size canvasSize) {
    final double imageW = widget.originalTexture.width.toDouble();
    final double imageH = widget.originalTexture.height.toDouble();
    final double imageAspect = imageW / imageH;
    final double canvasAspect = canvasSize.width / canvasSize.height;

    double drawW, drawH, offsetX, offsetY;

    if (canvasAspect > imageAspect) {
      drawH = canvasSize.height;
      drawW = drawH * imageAspect;
      offsetX = (canvasSize.width - drawW) / 2.0;
      offsetY = 0.0;
    } else {
      drawW = canvasSize.width;
      drawH = drawW / imageAspect;
      offsetX = 0.0;
      offsetY = (canvasSize.height - drawH) / 2.0;
    }

    return Rect.fromLTWH(offsetX, offsetY, drawW, drawH);
  }

  void _handleTouchStart(Offset localPosition, LightingState state, Size canvasSize) {
    if (!state.isLightingEnabled || state.selectedLightIndex < 0) return;
    
    double mappedX, mappedY;
    (mappedX, mappedY) = _mapToWorld(localPosition, canvasSize);

    state.updateSelectedLightPos(mappedX, mappedY);
  }

  void _handleTouchUpdate(Offset localPosition, LightingState state, Size canvasSize) {
    if (!state.isLightingEnabled || state.selectedLightIndex < 0) return;

    double mappedX, mappedY;
    (mappedX, mappedY) = _mapToWorld(localPosition, canvasSize);

    state.updateSelectedLightPos(mappedX, mappedY);
  }

  (double, double) _mapToWorld(Offset localPosition, Size canvasSize) {
    double scaleX = canvasSize.width / widget.originalTexture.width;
    double scaleY = canvasSize.height / widget.originalTexture.height;
    double scale = math.min(scaleX, scaleY);

    double drawWidth = widget.originalTexture.width * scale;
    double drawHeight = widget.originalTexture.height * scale;
    double offsetX = (canvasSize.width - drawWidth) / 2.0;
    double offsetY = (canvasSize.height - drawHeight) / 2.0;

    double mappedX = localPosition.dx - (offsetX + drawWidth / 2.0);
    double mappedY = localPosition.dy - (offsetY + drawHeight / 2.0);
    
    mappedX = mappedX.clamp(-(drawWidth / 2.0), drawWidth / 2.0);
    mappedY = mappedY.clamp(-(drawHeight / 2.0), drawHeight / 2.0);
    return (mappedX, mappedY);
  }

  @override
  Widget build(BuildContext context) {
    final lightingState = context.watch<LightingState>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final drawRect = _computeFittedRect(canvasSize);

        return GestureDetector(
          onPanDown: (details) {
            _handleTouchStart(details.localPosition, lightingState, canvasSize);
          },
          onPanUpdate: (details) {
            _handleTouchUpdate(details.localPosition, lightingState, canvasSize);
          },
          onPanEnd: (details) {
          },
          child: CustomPaint(
            size: canvasSize,
            painter: PBRShaderPainter(
              shader: widget.compiledShader,
              albedo: widget.albedoTexture,
              original: widget.originalTexture,
              depth: widget.depthTexture,
              state: lightingState,
              drawRect: drawRect,
            ),
          ),
        );
      },
    );
  }
}

class PBRShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image albedo;
  final ui.Image original;
  final ui.Image depth;
  final LightingState state;
  final Rect drawRect;
  final bool showIndicators;

  PBRShaderPainter({
    required this.shader,
    required this.albedo,
    required this.original,
    required this.depth,
    required this.state,
    required this.drawRect,
    this.showIndicators = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    shader.setImageSampler(0, albedo);
    shader.setImageSampler(1, original);
    shader.setImageSampler(2, depth);

    final int effectiveMode = state.effectiveViewMode;
    final double imgW = original.width.toDouble();
    final double imgH = original.height.toDouble();

    int fi = 0;

    shader.setFloat(fi++, effectiveMode.toDouble());
    shader.setFloat(fi++, size.width);
    shader.setFloat(fi++, size.height);
    shader.setFloat(fi++, drawRect.left);
    shader.setFloat(fi++, drawRect.top);
    shader.setFloat(fi++, drawRect.width);
    shader.setFloat(fi++, drawRect.height);
    shader.setFloat(fi++, imgW);
    shader.setFloat(fi++, imgH);
    shader.setFloat(fi++, state.roughness);
    shader.setFloat(fi++, state.metallic);
    shader.setFloat(fi++, state.ambientColor.r);
    shader.setFloat(fi++, state.ambientColor.g);
    shader.setFloat(fi++, state.ambientColor.b);
    shader.setFloat(fi++, state.shadowSoftness);

    int numLights = state.lights.length.clamp(0, 16);
    shader.setFloat(fi++, numLights.toDouble());

    // --- PHOTOREALISM TUNING UNIFORMS ---
    shader.setFloat(fi++, state.microDetailStrength);
    shader.setFloat(fi++, state.albedoBlend);

    // --- CAMERA UNIFORMS ---
    shader.setFloat(fi++, state.fov * math.pi / 180.0);
    shader.setFloat(fi++, state.zMinRatio);
    shader.setFloat(fi++, state.zMaxRatio);
    // ---------------------------

    // Loop exactly 16 times to fill the 224-float uniform array
    for (int i = 0; i < 16; i++) {
      if (i < numLights) {
        final light = state.lights[i];
        
        // Calculate Direction vector for shader from theta and phi
        double thetaRad = light.theta * math.pi / 180.0;
        double phiRad = light.phi * math.pi / 180.0;
        
        double dx = math.sin(phiRad) * math.cos(thetaRad);
        double dy = -math.sin(phiRad) * math.sin(thetaRad); // Negated for anti-clockwise rotation
        double dz = math.cos(phiRad);

        double innerCos = math.cos(light.coneInnerAngle * math.pi / 180.0);
        double outerCos = math.cos(light.coneOuterAngle * math.pi / 180.0);

        shader.setFloat(fi++, light.type.index.toDouble());
        shader.setFloat(fi++, light.pos.x);
        shader.setFloat(fi++, light.pos.y);
        shader.setFloat(fi++, light.pos.z);
        shader.setFloat(fi++, dx); // dir.x
        shader.setFloat(fi++, dy); // dir.y
        shader.setFloat(fi++, dz); // dir.z
        shader.setFloat(fi++, light.color.r);
        shader.setFloat(fi++, light.color.g);
        shader.setFloat(fi++, light.color.b);
        shader.setFloat(fi++, light.intensity);
        shader.setFloat(fi++, light.attenuationDecay);
        shader.setFloat(fi++, innerCos);
        shader.setFloat(fi++, outerCos);
      } else {
        // Pad empty lights with 14 zeroes
        for (int p = 0; p < 14; p++) {
          shader.setFloat(fi++, 0.0);
        }
      }
    }

    final Paint shaderPaint = Paint()..shader = shader;
    canvas.drawRect(drawRect, shaderPaint);

    if (showIndicators && state.isLightingEnabled && state.lights.isNotEmpty) {
      _drawLightIndicators(canvas);
    }
  }

  void _drawLightIndicators(Canvas canvas) {
    const double minDotRadius = 4.0;
    const double maxDotRadius = 14.0;
    const double minCircleRadius = 18.0;
    const double maxCircleRadius = 80.0;
    const double maxIntensity = 500000.0;
    const double minIntensity = 1000.0;

    for (int i = 0; i < state.lights.length; i++) {
      final light = state.lights[i];

      final bool isSelected = (i == state.selectedLightIndex);

      // World (0,0) = center of the draw rect
      final double screenX = light.pos.x + drawRect.left + drawRect.width / 2.0;
      final double screenY = light.pos.y + drawRect.top + drawRect.height / 2.0;
      final Offset center = Offset(screenX, screenY);

      // Normalized Z: 0.0 is front (bigger dot), 1.0 is back (smaller dot)
      final double heightNorm = (1.0 - light.pos.z).clamp(0.0, 1.0);
      final double dotRadius = minDotRadius + (maxDotRadius - minDotRadius) * heightNorm;

      final double intensityNorm = ((light.intensity - minIntensity) / (maxIntensity - minIntensity)).clamp(0.0, 1.0);
      final double circleRadius = minCircleRadius + (maxCircleRadius - minCircleRadius) * intensityNorm;

      final Color lightColor = light.color;

      final Paint circlePaint = Paint()
        ..color = lightColor.withAlpha(isSelected ? 180 : 100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.0 : 2.0;
      canvas.drawCircle(center, circleRadius, circlePaint);

      if (isSelected) {
        final Paint glowPaint = Paint()
          ..color = lightColor.withAlpha(30)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, circleRadius, glowPaint);
      }

      final Paint dotPaint = Paint()
        ..color = lightColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, dotRadius, dotPaint);

      final Paint dotBorderPaint = Paint()
        ..color = isSelected ? Colors.white : Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 2.0 : 1.0;
      canvas.drawCircle(center, dotRadius, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PBRShaderPainter oldDelegate) => true;
}
