// lib/widgets/contour_overlay.dart
import 'package:flutter/material.dart';
import '../services/gcode/machine_coordinates.dart';

class ContourOverlay extends StatelessWidget {
  final List<Point> contourPoints;
  final Size imageSize;
  final Color color;
  final double strokeWidth;
  final bool showPoints;

  const ContourOverlay({
    Key? key,
    required this.contourPoints,
    required this.imageSize,
    this.color = Colors.green,
    this.strokeWidth = 2.0,
    this.showPoints = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return CustomPaint(
          size: canvasSize,
          painter: ContourPainter(
            contourPoints: contourPoints,
            imageSize: imageSize,
            canvasSize: canvasSize,
            color: color,
            strokeWidth: strokeWidth,
            showPoints: showPoints,
          ),
        );
      },
    );
  }
}

class ContourPainter extends CustomPainter {
  final List<Point> contourPoints;
  final Size imageSize;
  final Size canvasSize;
  final Color color;
  final double strokeWidth;
  final bool showPoints;

  ContourPainter({
    required this.contourPoints,
    required this.imageSize,
    required this.canvasSize,
    required this.color,
    required this.strokeWidth,
    required this.showPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (contourPoints.isEmpty) return;

    // Calculate how the image is displayed within the canvas
    final imageAspectRatio = imageSize.width / imageSize.height;
    final canvasAspectRatio = canvasSize.width / canvasSize.height;
    
    double displayWidth, displayHeight;
    double offsetX = 0, offsetY = 0;
    
    if (imageAspectRatio > canvasAspectRatio) {
      // Image is wider than canvas (letterboxed)
      displayWidth = canvasSize.width;
      displayHeight = canvasSize.width / imageAspectRatio;
      offsetY = (canvasSize.height - displayHeight) / 2;
    } else {
      // Image is taller than canvas (pillarboxed)
      displayHeight = canvasSize.height;
      displayWidth = canvasSize.height * imageAspectRatio;
      offsetX = (canvasSize.width - displayWidth) / 2;
    }
    
    // Calculate scale factors
    final scaleX = displayWidth / imageSize.width;
    final scaleY = displayHeight / imageSize.height;

    // Create main contour paint
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Create glow effect paint
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);

    // Create the path for the contour
    final path = Path();
    
    if (contourPoints.isNotEmpty) {
      // Scale the first point to canvas coordinates
      final firstPoint = Offset(
        contourPoints.first.x * scaleX + offsetX,
        contourPoints.first.y * scaleY + offsetY,
      );
      
      path.moveTo(firstPoint.dx, firstPoint.dy);
      
      // Add the rest of the points
      for (int i = 1; i < contourPoints.length; i++) {
        final point = Offset(
          contourPoints[i].x * scaleX + offsetX,
          contourPoints[i].y * scaleY + offsetY,
        );
        path.lineTo(point.dx, point.dy);
      }
      
      // Close the path if needed
      if (contourPoints.first.x != contourPoints.last.x || 
          contourPoints.first.y != contourPoints.last.y) {
        path.close();
      }
    }

    // Draw the glow effect first
    canvas.drawPath(path, glowPaint);
    
    // Then draw the actual contour
    canvas.drawPath(path, paint);

    // Draw points at each vertex if requested
    if (showPoints) {
      final pointPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      
      final pointOutlinePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      
      for (final point in contourPoints) {
        final canvasPoint = Offset(
          point.x * scaleX + offsetX,
          point.y * scaleY + offsetY,
        );
        
        // Draw white dot with colored outline
        canvas.drawCircle(canvasPoint, 3.0, pointPaint);
        canvas.drawCircle(canvasPoint, 3.0, pointOutlinePaint);
      }
    }
    
    // Calculate and show contour area if it's a closed shape
    if (contourPoints.length > 2) {
      double area = 0.0;
      for (int i = 0; i < contourPoints.length - 1; i++) {
        area += contourPoints[i].x * contourPoints[i + 1].y;
        area -= contourPoints[i + 1].x * contourPoints[i].y;
      }
      // Close the polygon
      area += contourPoints.last.x * contourPoints.first.y;
      area -= contourPoints.first.x * contourPoints.last.y;
      area = area.abs() / 2;
      
      // Calculate center of contour for text placement
      double centerX = 0, centerY = 0;
      for (final point in contourPoints) {
        centerX += point.x;
        centerY += point.y;
      }
      centerX /= contourPoints.length;
      centerY /= contourPoints.length;
      
      // Convert to canvas coordinates
      final centerPoint = Offset(
        centerX * scaleX + offsetX,
        centerY * scaleY + offsetY,
      );
      
      // Format area text based on size
      String areaText;
      if (area < 10000) {
        areaText = "${area.toStringAsFixed(1)} px²";
      } else {
        areaText = "${(area / 1000).toStringAsFixed(1)}k px²";
      }
      
      // Draw area text with background for better visibility
      final textSpan = TextSpan(
        text: areaText,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      
      textPainter.layout();
      
      // Draw text background
      final textBgRect = Rect.fromCenter(
        center: centerPoint,
        width: textPainter.width + 16,
        height: textPainter.height + 8,
      );
      
      final rrect = RRect.fromRectAndRadius(
        textBgRect,
        Radius.circular(4),
      );
      
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withOpacity(0.7)
          ..style = PaintingStyle.fill,
      );
      
      // Draw text
      textPainter.paint(
        canvas,
        Offset(
          centerPoint.dx - textPainter.width / 2,
          centerPoint.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant ContourPainter oldDelegate) {
    return contourPoints != oldDelegate.contourPoints ||
           imageSize != oldDelegate.imageSize ||
           canvasSize != oldDelegate.canvasSize ||
           color != oldDelegate.color ||
           strokeWidth != oldDelegate.strokeWidth ||
           showPoints != oldDelegate.showPoints;
  }
}