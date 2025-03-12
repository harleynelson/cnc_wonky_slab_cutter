// lib/widgets/marker_overlay.dart
import 'package:flutter/material.dart';
import '../services/gcode/machine_coordinates.dart';
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
          ),
        );
      },
    );
  }
}

class MarkerPainter extends CustomPainter {
  final List<MarkerPoint> markers;
  final Size imageSize;

  MarkerPainter({
    required this.markers,
    required this.imageSize,
  });


@override
void paint(Canvas canvas, Size size) {
  print('DEBUG OVERLAY: Canvas size: ${size.width}x${size.height}');
  print('DEBUG OVERLAY: Image size: ${imageSize.width}x${imageSize.height}');
  
  final imageAspect = imageSize.width / imageSize.height;
  final canvasAspect = size.width / size.height;
  
  double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
  
  if (imageAspect > canvasAspect) {
    // Image is wider than canvas (letterboxed)
    displayWidth = size.width;
    displayHeight = size.width / imageAspect;
    offsetY = (size.height - displayHeight) / 2;
  } else {
    // Image is taller than canvas (pillarboxed)
    displayHeight = size.height;
    displayWidth = size.height * imageAspect;
    offsetX = (size.width - displayWidth) / 2;
  }
  
  print('DEBUG OVERLAY: Letterboxed offsetY: $offsetY');
  print('DEBUG OVERLAY: Display area: ${displayWidth}x${displayHeight}');
  print('DEBUG OVERLAY: Scale factors: ${imageSize.width/displayWidth} x ${imageSize.height/displayHeight}');
  
  
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0;

  // Draw each marker using standardized coordinate functions
  for (final marker in markers) {
    // Use the standard utility method
    final markerPoint = Point(marker.x.toDouble(), marker.y.toDouble());
    final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
      markerPoint,
      imageSize,
      size
    );
    
    final x = displayPoint.x;
    final y = displayPoint.y;
    
    print('DEBUG OVERLAY: Marker at (${marker.x},${marker.y}) -> display (${x.toStringAsFixed(1)},${y.toStringAsFixed(1)})');
    
    // Choose color based on marker role
    Color color;
    String label;
    
    switch (marker.role) {
      case MarkerRole.origin:
        color = Colors.red;
        label = "Origin (${marker.x.toInt()},${marker.y.toInt()})";
        break;
      case MarkerRole.xAxis:
        color = Colors.green;
        label = "X-Axis (${marker.x.toInt()},${marker.y.toInt()})";
        break;
      case MarkerRole.scale:
        color = Colors.blue;
        label = "Y-Axis (${marker.x.toInt()},${marker.y.toInt()})";
        break;
    }
    
    // Draw marker at transformed position
    paint.color = color;
    
    // Draw outer circle
    canvas.drawCircle(Offset(x, y), 20, paint);
    
    // Draw inner filled circle
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.5);
    canvas.drawCircle(Offset(x, y), 10, fillPaint);
    
    // Draw label
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
    
    // Background for text
    final bgRect = Rect.fromLTWH(
      x + 15, 
      y - 10, 
      textPainter.width + 10, 
      textPainter.height + 6
    );
    
    canvas.drawRect(
      bgRect, 
      Paint()..color = color.withOpacity(0.7)
    );
    
    // Text itself
    textPainter.paint(canvas, Offset(x + 20, y - 7));
  }
  
  // Draw connection lines if we have enough markers
  if (markers.length >= 3) {
      final originMarker = markers.firstWhere(
        (m) => m.role == MarkerRole.origin, 
        orElse: () => markers[0]
      );
      
      final xAxisMarker = markers.firstWhere(
        (m) => m.role == MarkerRole.xAxis, 
        orElse: () => markers[1]
      );
      
      final scaleMarker = markers.firstWhere(
        (m) => m.role == MarkerRole.scale, 
        orElse: () => markers[2]
      );
      
      // Origin to X-axis line
      final originX = (originMarker.x / imageSize.width) * size.width;
      final originY = (originMarker.y / imageSize.height) * size.height;
      
      final xAxisX = (xAxisMarker.x / imageSize.width) * size.width;
      final xAxisY = (xAxisMarker.y / imageSize.height) * size.height;
      
      final scaleX = (scaleMarker.x / imageSize.width) * size.width;
      final scaleY = (scaleMarker.y / imageSize.height) * size.height;
      
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(0.7)
        ..strokeWidth = 2.0;
      
      canvas.drawLine(
        Offset(originX, originY), 
        Offset(xAxisX, xAxisY), 
        linePaint
      );
      
      canvas.drawLine(
        Offset(originX, originY), 
        Offset(scaleX, scaleY), 
        linePaint
      );
    }
  }

  @override
  bool shouldRepaint(MarkerPainter oldDelegate) {
    return markers != oldDelegate.markers || 
           imageSize != oldDelegate.imageSize;
  }
}