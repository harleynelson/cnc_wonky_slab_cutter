// lib/widgets/contour_overlay.dart
import 'package:flutter/material.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/general/constants.dart';

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
    this.strokeWidth = defaultContourStrokeWidth,
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

  // Create paints
  final pathPaint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeJoin = StrokeJoin.round;

  // Create path with strict transformation
  final path = Path();
  bool isFirst = true;

  // Calculate exactly how the image fits in the container
  final imageAspect = imageSize.width / imageSize.height;
  final displayAspect = size.width / size.height;
  
  double scale, offsetX = 0, offsetY = 0;
  if (imageAspect > displayAspect) {
    // Image is wider than display area
    scale = size.width / imageSize.width;
    offsetY = (size.height - imageSize.height * scale) / 2;
  } else {
    // Image is taller than display area
    scale = size.height / imageSize.height;
    offsetX = (size.width - imageSize.width * scale) / 2;
  }

  for (final point in contourPoints) {
    // Direct coordinate transformation without using helper functions
    final x = point.x * scale + offsetX;
    final y = point.y * scale + offsetY;
    
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

  // Draw the contour only once
  canvas.drawPath(path, pathPaint);
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