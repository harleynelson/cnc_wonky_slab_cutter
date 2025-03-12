// lib/widgets/contour_overlay.dart
import 'package:flutter/material.dart';
import '../services/gcode/machine_coordinates.dart';

class ContourOverlay extends StatelessWidget {
  final List<Point> contourPoints;
  final Size imageSize;
  final Color color;

  const ContourOverlay({
    Key? key,
    required this.contourPoints,
    required this.imageSize,
    this.color = Colors.green,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: imageSize,
      painter: ContourPainter(
        contourPoints: contourPoints,
        color: color,
      ),
    );
  }
}

class ContourPainter extends CustomPainter {
  final List<Point> contourPoints;
  final Color color;

  ContourPainter({
    required this.contourPoints,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (contourPoints.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final path = Path();
    path.moveTo(contourPoints.first.x.toDouble(), contourPoints.first.y.toDouble());

    for (int i = 1; i < contourPoints.length; i++) {
      path.lineTo(contourPoints[i].x.toDouble(), contourPoints[i].y.toDouble());
    }

    // Close the path if not already closed
    if (contourPoints.first.x != contourPoints.last.x || 
        contourPoints.first.y != contourPoints.last.y) {
      path.close();
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}