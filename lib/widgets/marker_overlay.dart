// lib/widgets/marker_overlay.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/general/coordinate_utils.dart';
import '../services/detection/marker_detector.dart';

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
      ..strokeWidth = 3.0;

    // Draw each marker using standardized coordinate functions
    for (final marker in markers) {
      // Convert image coordinates to display coordinates
      final markerPoint = CoordinatePointXY(marker.x.toDouble(), marker.y.toDouble());
      final displayPosition = CoordinateUtils.imageCoordinatesToDisplayPosition(
        markerPoint,
        imageSize,
        size,
        debug: true
      );
      
      final x = displayPosition.dx;
      final y = displayPosition.dy;
      
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
        case MarkerRole.topRight:
          color = Colors.yellow;
          label = "Top-Right (${marker.x.toInt()},${marker.y.toInt()})";
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
      
      // Draw label with better position and visibility
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.black,
              blurRadius: 2.0,
              offset: Offset(1, 1),
            ),
          ],
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      
      // Calculate label position based on marker role for better visibility
      double labelX, labelY;
      switch (marker.role) {
        case MarkerRole.origin:
          labelX = x + 15;
          labelY = y - 15 - textPainter.height; // Above
          break;
        case MarkerRole.xAxis:
          labelX = x - 15 - textPainter.width;
          labelY = y - 15 - textPainter.height; // Above left
          break;
        case MarkerRole.scale:
          labelX = x + 15;
          labelY = y + 15; // Below
          break;
        case MarkerRole.topRight:
          labelX = x - 15 - textPainter.width;
          labelY = y + 15; // Below left
          break;
      }
      
      // Background for text
      final bgRect = Rect.fromLTWH(
        labelX - 5, 
        labelY - 3, 
        textPainter.width + 10, 
        textPainter.height + 6
      );
      
      canvas.drawRect(
        bgRect, 
        Paint()..color = color.withOpacity(0.7)
      );
      
      // Text itself
      textPainter.paint(canvas, Offset(labelX, labelY));
    }
    
    // Draw connection lines if we have all four markers
    if (markers.length >= 4) {
      MarkerPoint? originMarker, xAxisMarker, scaleMarker, topRightMarker;
      
      // Find all required markers
      for (final marker in markers) {
        switch (marker.role) {
          case MarkerRole.origin:
            originMarker = marker;
            break;
          case MarkerRole.xAxis:
            xAxisMarker = marker;
            break;
          case MarkerRole.scale:
            scaleMarker = marker;
            break;
          case MarkerRole.topRight:
            topRightMarker = marker;
            break;
        }
      }
      
      // If we have all four markers, draw connecting lines
      if (originMarker != null && xAxisMarker != null && scaleMarker != null && topRightMarker != null) {
        // Create points from markers
        final originPoint = CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble());
        final xAxisPoint = CoordinatePointXY(xAxisMarker.x.toDouble(), xAxisMarker.y.toDouble());
        final scalePoint = CoordinatePointXY(scaleMarker.x.toDouble(), scaleMarker.y.toDouble());
        final topRightPoint = CoordinatePointXY(topRightMarker.x.toDouble(), topRightMarker.y.toDouble());
        
        // Convert to display coordinates
        final originDisplay = CoordinateUtils.imageCoordinatesToDisplayPosition(originPoint, imageSize, size);
        final xAxisDisplay = CoordinateUtils.imageCoordinatesToDisplayPosition(xAxisPoint, imageSize, size);
        final scaleDisplay = CoordinateUtils.imageCoordinatesToDisplayPosition(scalePoint, imageSize, size);
        final topRightDisplay = CoordinateUtils.imageCoordinatesToDisplayPosition(topRightPoint, imageSize, size);
        
        final linePaint = Paint()
          ..color = Colors.white.withOpacity(0.7)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        
        // Draw the rectangle formed by the markers
        canvas.drawLine(
          originDisplay, 
          xAxisDisplay, 
          linePaint
        );
        
        canvas.drawLine(
          originDisplay, 
          scaleDisplay, 
          linePaint
        );
        
        canvas.drawLine(
          xAxisDisplay, 
          topRightDisplay, 
          linePaint
        );
        
        canvas.drawLine(
          scaleDisplay, 
          topRightDisplay, 
          linePaint
        );
        
        // Optional: Draw perpendicularity indicators at corners
        _drawCornerIndicator(canvas, originDisplay.dx, originDisplay.dy, Colors.red);
        _drawCornerIndicator(canvas, xAxisDisplay.dx, xAxisDisplay.dy, Colors.green);
        _drawCornerIndicator(canvas, scaleDisplay.dx, scaleDisplay.dy, Colors.blue);
        _drawCornerIndicator(canvas, topRightDisplay.dx, topRightDisplay.dy, Colors.yellow);
      }
    }
    
    // Draw a debug outline of the image display area
    final imageRect = CoordinateUtils.getImageDisplayRect(imageSize, size);
    canvas.drawRect(
      imageRect,
      Paint()
        ..color = Colors.purple.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
    );
  }
  
  /// Draw a small corner indicator showing perpendicularity
  void _drawCornerIndicator(Canvas canvas, double x, double y, Color color) {
    final indicatorPaint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    
    // Draw a small right angle indicator
    canvas.drawLine(Offset(x - 8, y), Offset(x - 3, y), indicatorPaint);
    canvas.drawLine(Offset(x, y - 8), Offset(x, y - 3), indicatorPaint);
    
    // Draw small corner arc to represent 90-degree angle
    final rect = Rect.fromCenter(center: Offset(x, y), width: 10, height: 10);
    canvas.drawArc(rect, -math.pi/2, math.pi/2, false, indicatorPaint);
  }

  @override
  bool shouldRepaint(MarkerPainter oldDelegate) {
    return markers != oldDelegate.markers || 
           imageSize != oldDelegate.imageSize;
  }
}