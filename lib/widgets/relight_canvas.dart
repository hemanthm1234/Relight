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
    const double maxIntensity = 500000.0;
    const double minIntensity = 1000.0;

    for (int i = 0; i < state.lights.length; i++) {
      final light = state.lights[i];
      final bool isSelected = (i == state.selectedLightIndex);

      // World (0,0) = center of the draw rect
      final double screenX = light.pos.x + drawRect.left + drawRect.width / 2.0;
      final double screenY = light.pos.y + drawRect.top + drawRect.height / 2.0;
      final Offset center = Offset(screenX, screenY);

      // Normalized Z: 0.0 is front (bigger), 1.0 is back (smaller)
      final double heightNorm = (1.0 - light.pos.z).clamp(0.0, 1.0);
      final double depthScale = 0.6 + 0.8 * heightNorm; // 0.6x to 1.4x

      final double intensityNorm = ((light.intensity - minIntensity) / (maxIntensity - minIntensity)).clamp(0.0, 1.0);
      final double pwrScale = 0.8 + 0.8 * intensityNorm; // 0.8x to 1.6x
      
      final double finalScale = (depthScale * pwrScale).clamp(0.4, 2.5); // Hard bounds just in case
      
      canvas.save();
      canvas.translate(center.dx, center.dy);

      if (light.type == LightType.conical) {
        // Anti-clockwise rotation for Theta
        double thetaRad = light.theta * math.pi / 180.0;
        canvas.rotate(-thetaRad);

        // Phi determines foreshortening
        double phiRad = light.phi * math.pi / 180.0;
        double foreshortening = math.sin(phiRad).abs();
        
        canvas.scale(finalScale);

        if (isSelected) {
          final Path beamPath = Path();
          double beamLength = 80.0 * foreshortening; 
          double innerRadius = 8.0;
          double outerRadius = 8.0 + beamLength * math.tan(light.coneOuterAngle * math.pi / 180.0);
          
          if (beamLength > 5.0) {
            beamPath.moveTo(0, -innerRadius);
            beamPath.lineTo(beamLength, -outerRadius);
            beamPath.lineTo(beamLength, outerRadius);
            beamPath.lineTo(0, innerRadius);
            beamPath.close();

            final Paint beamPaint = Paint()
              ..shader = ui.Gradient.linear(
                const Offset(0, 0),
                Offset(beamLength, 0),
                [light.color.withAlpha(150), light.color.withAlpha(0)],
              );
            canvas.drawPath(beamPath, beamPaint);
          }
        }

        double headWidth = math.max(6.0 * foreshortening, 2.0);
        double bodyLength = math.max(30.0 * foreshortening, 6.0);

        final Rect handleRect = Rect.fromCenter(
          center: Offset(-bodyLength / 2.0 - headWidth, 0), 
          width: bodyLength, 
          height: 10.0
        );
        
        final Rect headRect = Rect.fromCenter(
          center: Offset(-headWidth / 2.0, 0), 
          width: headWidth, 
          height: 18.0
        );

        final Paint basePaint = Paint()
          ..color = isSelected ? Colors.grey[300]! : Colors.grey[700]!
          ..style = PaintingStyle.fill;
          
        canvas.drawRRect(RRect.fromRectAndRadius(handleRect, const Radius.circular(3.0)), basePaint);
        canvas.drawRRect(RRect.fromRectAndRadius(headRect, const Radius.circular(2.0)), basePaint);

        final Rect lensRect = Rect.fromCenter(
          center: Offset(0, 0), 
          width: 3.0, 
          height: 14.0
        );
        final Paint lensPaint = Paint()
          ..color = light.color
          ..style = PaintingStyle.fill;
        canvas.drawRRect(RRect.fromRectAndRadius(lensRect, const Radius.circular(1.0)), lensPaint);

        if (isSelected) {
            final Paint outlinePaint = Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
            canvas.drawRRect(RRect.fromRectAndRadius(handleRect, const Radius.circular(3.0)), outlinePaint);
            canvas.drawRRect(RRect.fromRectAndRadius(headRect, const Radius.circular(2.0)), outlinePaint);
        }

      } else {
        canvas.scale(finalScale);

        final Paint glowPaint = Paint()
          ..color = light.color.withAlpha(isSelected ? 160 : 60)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
        canvas.drawCircle(Offset.zero, 18.0, glowPaint);

        final Paint bulbPaint = Paint()
          ..color = isSelected ? Colors.white : Colors.white70
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset.zero, 8.0, bulbPaint);

        final Paint outlinePaint = Paint()
          ..color = light.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 3.0 : 1.5;
        canvas.drawCircle(Offset.zero, 8.0, outlinePaint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant PBRShaderPainter oldDelegate) => true;
}
