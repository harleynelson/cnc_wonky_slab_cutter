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
        // Calculate image display properties
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        
        return CustomPaint(
          size: canvasSize,
          painter: MarkerPainter(
            markers: markers,
            imageSize: imageSize,
            canvasSize: canvasSize,
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
    
    // Draw connections between markers
    final connectionPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    final originIndex = markers.indexWhere((marker) => marker.role == MarkerRole.origin);
    final xAxisIndex = markers.indexWhere((marker) => marker.role == MarkerRole.xAxis);
    final scaleIndex = markers.indexWhere((marker) => marker.role == MarkerRole.scale);
    
    if (originIndex >= 0 && xAxisIndex >= 0) {
      final originPos = Offset(
        markers[originIndex].x * scaleX + offsetX,
        markers[originIndex].y * scaleY + offsetY,
      );
      final xAxisPos = Offset(
        markers[xAxisIndex].x * scaleX + offsetX,
        markers[xAxisIndex].y * scaleY + offsetY,
      );
      
      canvas.drawLine(originPos, xAxisPos, connectionPaint);
    }
    
    if (originIndex >= 0 && scaleIndex >= 0) {
      final originPos = Offset(
        markers[originIndex].x * scaleX + offsetX,
        markers[originIndex].y * scaleY + offsetY,
      );
      final scalePos = Offset(
        markers[scaleIndex].x * scaleX + offsetX,
        markers[scaleIndex].y * scaleY + offsetY,
      );
      
      canvas.drawLine(originPos, scalePos, connectionPaint);
    }
    
    // Draw each marker
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
          label = "X-Axis";
          break;
        case MarkerRole.scale:
          color = Colors.blue;
          label = "Y-Axis";
          break;
      }
      
      // Draw outer circle
      final outerCirclePaint = Paint()
        ..color = color.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      
      canvas.drawCircle(position, 20.0, outerCirclePaint);
      
      // Draw inner circle
      final innerCirclePaint = Paint()
        ..color = color.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(position, 8.0, innerCirclePaint);
      
      // Draw center dot
      final centerDotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(position, 2.5, centerDotPaint);
      
      // Draw crosshair
      final crosshairPaint = Paint()
        ..color = color
        ..strokeWidth = 1.0;
        
      canvas.drawLine(
        Offset(position.dx - 10, position.dy),
        Offset(position.dx + 10, position.dy),
        crosshairPaint,
      );
      
      canvas.drawLine(
        Offset(position.dx, position.dy - 10),
        Offset(position.dx, position.dy + 10),
        crosshairPaint,
      );
      
      // Draw label with background for better readability
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      
      // Draw text background
      final textBgRect = Rect.fromLTWH(
        position.dx + 12,
        position.dy - 8,
        textPainter.width + 6,
        textPainter.height + 4,
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
        Offset(position.dx + 15, position.dy - 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}