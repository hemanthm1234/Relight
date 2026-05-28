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
      // Canvas is wider than image — pillarbox (bars on left/right)
      drawH = canvasSize.height;
      drawW = drawH * imageAspect;
      offsetX = (canvasSize.width - drawW) / 2.0;
      offsetY = 0.0;
    } else {
      // Canvas is taller than image — letterbox (bars on top/bottom)
      drawW = canvasSize.width;
      drawH = drawW / imageAspect;
      offsetX = 0.0;
      offsetY = (canvasSize.height - drawH) / 2.0;
    }

    return Rect.fromLTWH(offsetX, offsetY, drawW, drawH);
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
              // Convert screen tap to draw-rect-relative coordinates
              final double relX = (details.localPosition.dx - drawRect.left).clamp(0.0, drawRect.width);
              final double relY = (details.localPosition.dy - drawRect.top).clamp(0.0, drawRect.height);
              lightingState.updateSelectedLightPos(relX, relY);
            }
          },
          onTapDown: (details) {
            if (lightingState.isLightingEnabled && lightingState.selectedLightIndex >= 0) {
              final double relX = (details.localPosition.dx - drawRect.left).clamp(0.0, drawRect.width);
              final double relY = (details.localPosition.dy - drawRect.top).clamp(0.0, drawRect.height);
              lightingState.updateSelectedLightPos(relX, relY);
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

    final int effectiveMode = state.effectiveViewMode;
    final double imgW = original.width.toDouble();
    final double imgH = original.height.toDouble();

    int fi = 0;

    // View Mode (0)
    shader.setFloat(fi++, effectiveMode.toDouble()); 

    // Canvas Resolution (1, 2)
    shader.setFloat(fi++, size.width);    
    shader.setFloat(fi++, size.height);   

    // Calculated BoxFit.contain offset (3, 4)
    shader.setFloat(fi++, drawRect.left);   
    shader.setFloat(fi++, drawRect.top);    

    // Calculated BoxFit.contain size (5, 6)
    shader.setFloat(fi++, drawRect.width);  
    shader.setFloat(fi++, drawRect.height); 

    // Raw Image Size (7, 8)
    shader.setFloat(fi++, imgW);  
    shader.setFloat(fi++, imgH);  

    // Global Params (9, 10, 11, 12, 13, 14)
    shader.setFloat(fi++, state.roughness); 
    shader.setFloat(fi++, state.metallic);  
    shader.setFloat(fi++, state.ambientColor.r); 
    shader.setFloat(fi++, state.ambientColor.g); 
    shader.setFloat(fi++, state.ambientColor.b); 
    shader.setFloat(fi++, state.shadowSoftness); 

    // Lights (15+)
    int numLights = state.lights.length.clamp(0, 4);
    shader.setFloat(fi++, numLights.toDouble()); 

    for (int i = 0; i < 4; i++) {
      if (i < numLights) {
        final light = state.lights[i];
        
        // Feed raw relative coords (matches localCoord in shader)
        shader.setFloat(fi++, light.pos.x);
        shader.setFloat(fi++, light.pos.y);
        shader.setFloat(fi++, light.pos.z);
        shader.setFloat(fi++, light.color.r);
        shader.setFloat(fi++, light.color.g);
        shader.setFloat(fi++, light.color.b);
        shader.setFloat(fi++, light.intensity);
      } else {
        for(int p = 0; p < 7; p++) shader.setFloat(fi++, 0.0);
      }
    }

    final Paint shaderPaint = Paint()..shader = shader;
    canvas.drawRect(drawRect, shaderPaint);

    if (effectiveMode == 0 && state.lights.isNotEmpty) {
      _drawLightIndicators(canvas);
    }
  }

  void _drawLightIndicators(Canvas canvas) {
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

      // Convert draw-rect-relative coords to screen coords for drawing
      final double screenX = light.pos.x + drawRect.left;
      final double screenY = light.pos.y + drawRect.top;
      final Offset center = Offset(screenX, screenY);

      // Center dot: radius inversely proportional to depth
      final double depthNorm = (light.pos.z / maxZ).clamp(0.0, 1.0);
      final double dotRadius = maxDotRadius * (1.0 - depthNorm) + minDotRadius;

      // Outer circle: radius proportional to intensity
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

      // Draw border around the dot for contrast
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
