// lib/utils/visualization/contour_painter.dart
// Utility for painting contours on a canvas

import 'package:flutter/material.dart';
import '../general/machine_coordinates.dart';

class ContourPainter extends CustomPainter {
  final List<CoordinatePointXY> contour;
  final Size imageSize;
  final MachineCoordinateSystem coordSystem;
  final Color color;
  final double strokeWidth;

  ContourPainter({
    required this.contour,
    required this.imageSize,
    required this.coordSystem,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (contour.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool first = true;

    for (final point in contour) {
      // This conversion is critical for proper display
      final pixelPoint = coordSystem.machineToPixelCoords(point);
      final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
        pixelPoint, imageSize, size);

      if (first) {
        path.moveTo(displayPoint.x, displayPoint.y);
        first = false;
      } else {
        path.lineTo(displayPoint.x, displayPoint.y);
      }
    }

    // Close the contour
    path.close();

    // Draw the path
    canvas.drawPath(path, paint);
    
    // Draw a dot for the first point to verify orientation
    if (contour.isNotEmpty) {
      final startPoint = coordSystem.machineToPixelCoords(contour.first);
      final displayStart = MachineCoordinateSystem.imageToDisplayCoordinates(
        startPoint, imageSize, size);
      
      canvas.drawCircle(
        Offset(displayStart.x, displayStart.y), 
        5.0, 
        Paint()..color = Colors.red..style = PaintingStyle.fill
      );
    }
  }

  @override
  bool shouldRepaint(ContourPainter oldDelegate) {
    return contour != oldDelegate.contour ||
           imageSize != oldDelegate.imageSize ||
           color != oldDelegate.color ||
           strokeWidth != oldDelegate.strokeWidth;
  }
}