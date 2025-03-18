// lib/widgets/contour_overlay.dart
import 'package:flutter/material.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/general/coordinate_utils.dart';

class ContourOverlay extends StatelessWidget {
  final List<CoordinatePointXY> contourPoints;
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
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: ContourPainter(
            contourPoints: contourPoints,
            imageSize: imageSize,
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
  final List<CoordinatePointXY> contourPoints;
  final Size imageSize;
  final Color color;
  final double strokeWidth;
  final bool showPoints;

  ContourPainter({
    required this.contourPoints,
    required this.imageSize,
    required this.color,
    required this.strokeWidth,
    required this.showPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (contourPoints.isEmpty) return;
  
    print('DEBUG CONTOUR: Painting contour on canvas size: ${size.width}x${size.height}');
    print('DEBUG CONTOUR: Image size: ${imageSize.width}x${imageSize.height}');
  
    // Create paints
    final pathPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;
  
    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3);
  
    // Create path with standardized transformation
    final path = Path();
    bool isFirst = true;
  
    for (final point in contourPoints) {
      // Use the standardized utility for coordinate transformation
      final displayPosition = CoordinateUtils.imageCoordinatesToDisplayPosition(
        point,
        imageSize,
        size
      );
      
      final x = displayPosition.dx;
      final y = displayPosition.dy;
      
      if (isFirst) {
        path.moveTo(x, y);
        isFirst = false;
      } else {
        path.lineTo(x, y);
      }
    }
  
    // Close the contour if needed
    if (contourPoints.length > 2 && 
        (contourPoints.first.x != contourPoints.last.x || 
         contourPoints.first.y != contourPoints.last.y)) {
      path.close();
    }
  
    // Draw the contour with glow effect
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, pathPaint);
  
    // Draw points if requested
    if (showPoints) {
      final pointPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      
      final outlinePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      
      for (final point in contourPoints) {
        final displayPosition = CoordinateUtils.imageCoordinatesToDisplayPosition(
          point,
          imageSize,
          size
        );
        
        // Draw point
        canvas.drawCircle(Offset(displayPosition.dx, displayPosition.dy), 3, pointPaint);
        canvas.drawCircle(Offset(displayPosition.dx, displayPosition.dy), 3, outlinePaint);
      }
    }
    
    // Calculate and show area
    if (contourPoints.length > 2) {
      // Calculate center point of contour for label placement
      double sumX = 0, sumY = 0;
      
      for (final point in contourPoints) {
        sumX += point.x;
        sumY += point.y;
      }
      
      final centerPoint = CoordinatePointXY(
        sumX / contourPoints.length,
        sumY / contourPoints.length
      );
      
      final displayCenter = CoordinateUtils.imageCoordinatesToDisplayPosition(
        centerPoint,
        imageSize,
        size
      );
      
      // Calculate area (in sq mm if converting from image to world coordinates)
      double area = 0;
      
      for (int i = 0; i < contourPoints.length; i++) {
        final j = (i + 1) % contourPoints.length;
        area += contourPoints[i].x * contourPoints[j].y;
        area -= contourPoints[j].x * contourPoints[i].y;
      }
      
      area = area.abs() / 2;
      
      // Format area text
      String areaText;
      if (area < 10000) {
        areaText = "${area.toStringAsFixed(1)} sq units";
      } else {
        areaText = "${(area / 1000).toStringAsFixed(1)}k sq units";
      }
      
      // Draw area label
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
      
      // Draw background
      final bgRect = Rect.fromCenter(
        center: Offset(displayCenter.dx, displayCenter.dy),
        width: textPainter.width + 16,
        height: textPainter.height + 8,
      );
      
      canvas.drawRect(
        bgRect, 
        Paint()..color = color.withOpacity(0.7)
      );
      
      // Draw text
      textPainter.paint(
        canvas,
        Offset(
          displayCenter.dx - textPainter.width / 2,
          displayCenter.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(ContourPainter oldDelegate) {
    return contourPoints != oldDelegate.contourPoints ||
           imageSize != oldDelegate.imageSize ||
           color != oldDelegate.color ||
           strokeWidth != oldDelegate.strokeWidth ||
           showPoints != oldDelegate.showPoints;
  }
}