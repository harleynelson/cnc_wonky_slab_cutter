import 'package:flutter/material.dart';

class CameraOverlay extends StatelessWidget {
  final double markerSize;
  final Color markerOriginColor;
  final Color markerXAxisColor;
  final Color markerScaleColor;

  const CameraOverlay({
    Key? key,
    required this.markerSize,
    required this.markerOriginColor,
    required this.markerXAxisColor,
    required this.markerScaleColor,
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

  MarkerGuidePainter({
    required this.markerSize,
    required this.markerOriginColor,
    required this.markerXAxisColor,
    required this.markerScaleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Define marker positions
    final originPosition = Offset(size.width * 0.2, size.height * 0.2);
    final xAxisPosition = Offset(size.width * 0.8, size.height * 0.2);
    final scalePosition = Offset(size.width * 0.2, size.height * 0.8);

    // Draw guide circles for markers
    _drawMarkerGuide(canvas, originPosition, markerOriginColor, "Origin");
    _drawMarkerGuide(canvas, xAxisPosition, markerXAxisColor, "X-Axis");
    _drawMarkerGuide(canvas, scalePosition, markerScaleColor, "Scale");
    
    // Draw connecting lines between markers
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    // Origin to X-Axis line
    canvas.drawLine(originPosition, xAxisPosition, linePaint);
    
    // Origin to Scale line
    canvas.drawLine(originPosition, scalePosition, linePaint);
    
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
      "Position the three markers as shown and place your slab in the work area"
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