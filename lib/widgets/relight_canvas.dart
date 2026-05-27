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
  /// Compute the fitted image rect (BoxFit.contain) within the given canvas size.
  Rect _computeFittedRect(Size canvasSize) {
    final double imageW = widget.originalTexture.width.toDouble();
    final double imageH = widget.originalTexture.height.toDouble();
    final double imageAspect = imageW / imageH;
    final double canvasAspect = canvasSize.width / canvasSize.height;

    double drawW, drawH, offsetX, offsetY;

    if (canvasAspect > imageAspect) {
      // Canvas is wider than image → pillarbox (bars on left/right)
      drawH = canvasSize.height;
      drawW = drawH * imageAspect;
      offsetX = (canvasSize.width - drawW) / 2.0;
      offsetY = 0.0;
    } else {
      // Canvas is taller than image → letterbox (bars on top/bottom)
      drawW = canvasSize.width;
      drawH = drawW / imageAspect;
      offsetX = 0.0;
      offsetY = (canvasSize.height - drawH) / 2.0;
    }

    return Rect.fromLTWH(offsetX, offsetY, drawW, drawH);
  }

  /// Convert screen-space position to image-space position (within the draw rect)
  Offset _screenToImageSpace(Offset screenPos, Rect drawRect) {
    return Offset(
      screenPos.dx - drawRect.left,
      screenPos.dy - drawRect.top,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lightingState = context.watch<LightingState>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final drawRect = _computeFittedRect(canvasSize);

        return GestureDetector(
          onPanUpdate: (details) {
            if (lightingState.isLightingEnabled && lightingState.selectedLightIndex >= 0) {
              // Light positions are stored in draw-rect-relative coordinates
              final imagePos = _screenToImageSpace(details.localPosition, drawRect);
              // Clamp to the draw rect bounds
              final clampedX = imagePos.dx.clamp(0.0, drawRect.width);
              final clampedY = imagePos.dy.clamp(0.0, drawRect.height);
              lightingState.updateSelectedLightPos(clampedX, clampedY);
            }
          },
          onTapDown: (details) {
            if (lightingState.isLightingEnabled && lightingState.selectedLightIndex >= 0) {
              final imagePos = _screenToImageSpace(details.localPosition, drawRect);
              final clampedX = imagePos.dx.clamp(0.0, drawRect.width);
              final clampedY = imagePos.dy.clamp(0.0, drawRect.height);
              lightingState.updateSelectedLightPos(clampedX, clampedY);
            }
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

  PBRShaderPainter({
    required this.shader,
    required this.albedo,
    required this.original,
    required this.depth,
    required this.state,
    required this.drawRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Set image samplers
    shader.setImageSampler(0, albedo);
    shader.setImageSampler(1, original);
    shader.setImageSampler(2, depth);

    // Float index tracker
    int fi = 0;

    // u_ViewMode
    shader.setFloat(fi++, state.viewMode.toDouble()); // 0

    // u_Resolution
    shader.setFloat(fi++, size.width);  // 1
    shader.setFloat(fi++, size.height); // 2

    // u_DrawOffset
    shader.setFloat(fi++, drawRect.left); // 3
    shader.setFloat(fi++, drawRect.top);  // 4

    // u_DrawSize
    shader.setFloat(fi++, drawRect.width);  // 5
    shader.setFloat(fi++, drawRect.height); // 6

    // u_ImageSize
    shader.setFloat(fi++, original.width.toDouble());  // 7
    shader.setFloat(fi++, original.height.toDouble()); // 8

    // u_Roughness
    shader.setFloat(fi++, state.roughness); // 9

    // u_Metallic
    shader.setFloat(fi++, state.metallic); // 10

    // u_AmbientLight (vec3)
    shader.setFloat(fi++, state.ambientColor.r); // 11
    shader.setFloat(fi++, state.ambientColor.g); // 12
    shader.setFloat(fi++, state.ambientColor.b); // 13

    // u_ShadowSoftness
    shader.setFloat(fi++, state.shadowSoftness); // 14

    // u_ActiveLights
    int numLights = state.lights.length.clamp(0, 4);
    shader.setFloat(fi++, numLights.toDouble()); // 15

    // Light data: 4 lights × 7 floats each (pos.xyz, color.rgb, intensity)
    for (int i = 0; i < 4; i++) {
      if (i < numLights) {
        final light = state.lights[i];
        // Light positions are in draw-rect-relative coords.
        // Convert to screen-space for the shader (add drawRect offset).
        shader.setFloat(fi++, light.pos.x + drawRect.left);
        shader.setFloat(fi++, light.pos.y + drawRect.top);
        shader.setFloat(fi++, light.pos.z);
        shader.setFloat(fi++, light.color.r);
        shader.setFloat(fi++, light.color.g);
        shader.setFloat(fi++, light.color.b);
        shader.setFloat(fi++, light.intensity);
      } else {
        shader.setFloat(fi++, 0.0);
        shader.setFloat(fi++, 0.0);
        shader.setFloat(fi++, 0.0);
        shader.setFloat(fi++, 0.0);
        shader.setFloat(fi++, 0.0);
        shader.setFloat(fi++, 0.0);
        shader.setFloat(fi++, 0.0);
      }
    }

    // Draw the shader across the entire canvas (shader handles clipping to draw rect)
    final Paint shaderPaint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), shaderPaint);

    // Draw light source indicators on top of the shader output
    if (state.isLightingEnabled && state.lights.isNotEmpty) {
      _drawLightIndicators(canvas, size);
    }
  }

  void _drawLightIndicators(Canvas canvas, Size size) {
    const double maxZ = 800.0;
    const double minDotRadius = 4.0;
    const double maxDotRadius = 14.0;
    const double minCircleRadius = 18.0;
    const double maxCircleRadius = 80.0;
    const double maxIntensity = 10000.0;
    const double minIntensity = 50.0;

    for (int i = 0; i < state.lights.length; i++) {
      final light = state.lights[i];
      final bool isSelected = (i == state.selectedLightIndex);

      // Light positions are in draw-rect-relative coords.
      // Convert to screen coords for drawing.
      final double screenX = light.pos.x + drawRect.left;
      final double screenY = light.pos.y + drawRect.top;
      final Offset center = Offset(screenX, screenY);

      // --- Center dot: radius inversely proportional to depth ---
      final double depthNorm = (light.pos.z / maxZ).clamp(0.0, 1.0);
      final double dotRadius = maxDotRadius * (1.0 - depthNorm) + minDotRadius;

      // --- Outer circle: radius proportional to intensity ---
      final double intensityNorm = ((light.intensity - minIntensity) / (maxIntensity - minIntensity)).clamp(0.0, 1.0);
      final double circleRadius = minCircleRadius + (maxCircleRadius - minCircleRadius) * intensityNorm;

      final Color lightColor = light.color;

      // Draw outer circle (intensity indicator)
      final Paint circlePaint = Paint()
        ..color = lightColor.withAlpha(isSelected ? 180 : 100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.0 : 2.0;
      canvas.drawCircle(center, circleRadius, circlePaint);

      // Draw subtle filled glow inside circle for selected light
      if (isSelected) {
        final Paint glowPaint = Paint()
          ..color = lightColor.withAlpha(30)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, circleRadius, glowPaint);
      }

      // Draw center dot (filled)
      final Paint dotPaint = Paint()
        ..color = lightColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, dotRadius, dotPaint);

      // Draw a thin border around the dot for contrast
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
