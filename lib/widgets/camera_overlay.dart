// lib/widgets/camera_overlay.dart
import 'package:flutter/material.dart';

class CameraOverlay extends StatelessWidget {
  final double markerSize;
  final Color markerOriginColor;
  final Color markerXAxisColor;
  final Color markerScaleColor;
  final Color markerTopRightColor;

  const CameraOverlay({
    Key? key,
    required this.markerSize,
    required this.markerOriginColor,
    required this.markerXAxisColor,
    required this.markerScaleColor,
    this.markerTopRightColor = Colors.yellow, // Default color for top-right marker
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: MarkerGuidePainter(
            markerSize: markerSize,
            markerOriginColor: markerOriginColor,
            markerXAxisColor: markerXAxisColor,
            markerScaleColor: markerScaleColor,
            markerTopRightColor: markerTopRightColor,
          ),
        );
      },
    );
  }
}

class MarkerGuidePainter extends CustomPainter {
  final double markerSize;
  final Color markerOriginColor;
  final Color markerXAxisColor;
  final Color markerScaleColor;
  final Color markerTopRightColor;

  MarkerGuidePainter({
    required this.markerSize,
    required this.markerOriginColor,
    required this.markerXAxisColor,
    required this.markerScaleColor,
    required this.markerTopRightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Define marker positions - forming a rectangle
    final originPosition = Offset(size.width * 0.2, size.height * 0.8);    // Bottom left
    final xAxisPosition = Offset(size.width * 0.8, size.height * 0.8);     // Bottom right
    final scalePosition = Offset(size.width * 0.2, size.height * 0.2);     // Top left
    final topRightPosition = Offset(size.width * 0.8, size.height * 0.2);  // Top right

    // Draw guide circles for markers
    _drawMarkerGuide(canvas, originPosition, markerOriginColor, "Origin");
    _drawMarkerGuide(canvas, xAxisPosition, markerXAxisColor, "X-Axis");
    _drawMarkerGuide(canvas, scalePosition, markerScaleColor, "Y-Axis");
    _drawMarkerGuide(canvas, topRightPosition, markerTopRightColor, "Top-Right");
    
    // Draw connecting lines between markers to form a rectangle
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    // Origin to X-Axis line (bottom edge)
    canvas.drawLine(originPosition, xAxisPosition, linePaint);
    
    // Origin to Scale line (left edge)
    canvas.drawLine(originPosition, scalePosition, linePaint);
    
    // X-Axis to Top-Right line (right edge)
    canvas.drawLine(xAxisPosition, topRightPosition, linePaint);
    
    // Scale to Top-Right line (top edge)
    canvas.drawLine(scalePosition, topRightPosition, linePaint);
    
    // Draw work area border
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.1,
        size.height * 0.1,
        size.width * 0.8,
        size.height * 0.8,
      ),
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    
    // Add instructional text
    _drawInstructionText(
      canvas, 
      size, 
      "Position the 4 markers in a rectangle: Origin (bottom left), X-Axis (bottom right), Y-Axis (top left), Top-Right (top right)"
    );
  }
  
  void _drawMarkerGuide(Canvas canvas, Offset position, Color color, String label) {
    // Draw outer circle
    final outerCirclePaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    canvas.drawCircle(
      position,
      markerSize,
      outerCirclePaint,
    );
    
    // Draw inner circle
    final innerCirclePaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      position,
      markerSize / 2,
      innerCirclePaint,
    );
    
    // Draw crosshair
    final crosshairPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    canvas.drawLine(
      Offset(position.dx - markerSize/2, position.dy),
      Offset(position.dx + markerSize/2, position.dy),
      crosshairPaint,
    );
    
    canvas.drawLine(
      Offset(position.dx, position.dy - markerSize/2),
      Offset(position.dx, position.dy + markerSize/2),
      crosshairPaint,
    );
    
    // Draw label
    _drawText(canvas, label, position, color);
  }
  
  void _drawText(Canvas canvas, String text, Offset position, Color color) {
    final labelOffset = Offset(0, markerSize + 10);
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            blurRadius: 3.0,
            color: Colors.black,
            offset: Offset(1.0, 1.0),
          ),
        ],
      ),
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy + labelOffset.dy,
      ),
    );
  }
  
  void _drawInstructionText(Canvas canvas, Size size, String instruction) {
    final textSpan = TextSpan(
      text: instruction,
      style: TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            blurRadius: 3.0,
            color: Colors.black,
            offset: Offset(1.0, 1.0),
          ),
        ],
      ),
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    
    textPainter.layout(maxWidth: size.width * 0.8);
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        size.height * 0.05,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}