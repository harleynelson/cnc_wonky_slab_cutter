// lib/widgets/marker_overlay.dart
import 'package:flutter/material.dart';
import '../services/image_processing/marker_detector.dart';

class MarkerOverlay extends StatelessWidget {
  final List<MarkerPoint> markers;
  final Size imageSize;

  const MarkerOverlay({
    Key? key,
    required this.markers,
    required this.imageSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: MarkerPainter(
            markers: markers,
            imageSize: imageSize,
            canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }
}

class MarkerPainter extends CustomPainter {
  final List<MarkerPoint> markers;
  final Size imageSize;
  final Size canvasSize;

  MarkerPainter({
    required this.markers,
    required this.imageSize,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
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
    
    for (final marker in markers) {
      // Calculate position with proper scaling
      final position = Offset(
        marker.x * scaleX + offsetX,
        marker.y * scaleY + offsetY,
      );
      
      // Choose color and label based on marker role
      Color color;
      String label;
      
      switch (marker.role) {
        case MarkerRole.origin:
          color = Colors.red;
          label = "Origin";
          break;
        case MarkerRole.xAxis:
          color = Colors.green;
          label = "X";
          break;
        case MarkerRole.scale:
          color = Colors.blue;
          label = "Y";
          break;
      }
      
      // Draw outer circle
      final outerCirclePaint = Paint()
        ..color = color.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      
      canvas.drawCircle(position, 15.0, outerCirclePaint);
      
      // Draw inner circle
      final innerCirclePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(position, 5.0, innerCirclePaint);
      
      // Draw label
      final textSpan = TextSpan(
        text: label,
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
      );
      
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(position.dx + 10, position.dy - 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}