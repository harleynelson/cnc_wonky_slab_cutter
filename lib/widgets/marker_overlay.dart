// lib/widgets/marker_overlay.dart
import 'package:flutter/material.dart';
import '../utils/general/machine_coordinates.dart';
import '../detection/marker_detector.dart';
import '../utils/general/constants.dart';

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
  
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = markerLineStrokeWidth;

  // Draw each marker using standardized coordinate functions
  for (final marker in markers) {
    // Use the standard utility method
    final markerPoint = CoordinatePointXY(marker.x.toDouble(), marker.y.toDouble());
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
        label = "Origin   ";
        break;
      case MarkerRole.xAxis:
        color = Colors.green;
        label = "X   ";
        break;
      case MarkerRole.scale:
        color = Colors.blue;
        label = "Y   ";
        break;
    
    // switch (marker.role) {
    //   case MarkerRole.origin:
    //     color = Colors.red;
    //     label = "Origin (${marker.x.toInt()},${marker.y.toInt()})";
    //     break;
    //   case MarkerRole.xAxis:
    //     color = Colors.green;
    //     label = "X-Axis (${marker.x.toInt()},${marker.y.toInt()})";
    //     break;
    //   case MarkerRole.scale:
    //     color = Colors.blue;
    //     label = "Y-Axis (${marker.x.toInt()},${marker.y.toInt()})";
    //     break;
    }
    
    // Draw marker at transformed position
    paint.color = color;
    
    // Draw outer circle
    canvas.drawCircle(Offset(x, y), markerCircleRadius, paint);
    
    // Draw inner filled circle
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.5);
    canvas.drawCircle(Offset(x, y), markerInnerCircleRadius, fillPaint);
    
    // Draw label
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: Colors.white,
        fontSize: markerLabelFontSize,
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
      x + markerLabelPadding, 
      y - markerLabelPadding, 
      textPainter.width + markerLabelPadding, 
      textPainter.height + markerLabelPadding
    );
    
    canvas.drawRect(
      bgRect, 
      Paint()..color = color.withOpacity(contourBackgroundOpacity)
    );
    
    // Text itself
    textPainter.paint(canvas, Offset(x + markerLabelXOffset, y + markerLabelYOffset));
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
      
      // Create points from markers
      final originPoint = CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble());
      final xAxisPoint = CoordinatePointXY(xAxisMarker.x.toDouble(), xAxisMarker.y.toDouble());
      final scalePoint = CoordinatePointXY(scaleMarker.x.toDouble(), scaleMarker.y.toDouble());
      
      // Convert to display coordinates using the same transformation as the markers
      final originDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(originPoint, imageSize, size);
      final xAxisDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(xAxisPoint, imageSize, size);
      final scaleDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(scalePoint, imageSize, size);
      
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(markerLineOpacity)
        ..strokeWidth = markerLineStrokeWidth;
      
      canvas.drawLine(
        Offset(originDisplay.x, originDisplay.y), 
        Offset(xAxisDisplay.x, xAxisDisplay.y), 
        linePaint
      );
      
      canvas.drawLine(
        Offset(originDisplay.x, originDisplay.y), 
        Offset(scaleDisplay.x, scaleDisplay.y), 
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