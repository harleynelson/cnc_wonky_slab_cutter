// lib/widgets/debug_overlay.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/general/coordinate_utils.dart';
import '../utils/general/machine_coordinates.dart';

/// An overlay that shows debug information about coordinate systems
/// Use this during development to visualize coordinate transformations
class DebugOverlay extends StatelessWidget {
  final Size imageSize;
  final bool enabled;

  const DebugOverlay({
    Key? key,
    required this.imageSize,
    this.enabled = kDebugMode, // Only enabled in debug mode by default
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: DebugPainter(
            imageSize: imageSize,
          ),
        );
      },
    );
  }
}

class DebugPainter extends CustomPainter {
  final Size imageSize;

  DebugPainter({
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    print('DEBUG OVERLAY: Painting debug info on canvas size: ${size.width}x${size.height}');
    
    // Draw canvas boundaries
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = Colors.red.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
    );
    
    // Draw image display area
    final imageRect = CoordinateUtils.getImageDisplayRect(imageSize, size);
    canvas.drawRect(
      imageRect,
      Paint()
        ..color = Colors.green.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
    );
    
    // Draw coordinate grid
    _drawCoordinateGrid(canvas, imageRect, size);
    
    // Add text labels
    _drawDebugLabels(canvas, imageRect, size);
  }
  
  void _drawCoordinateGrid(Canvas canvas, Rect imageRect, Size size) {
    final gridPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    // Draw vertical grid lines
    for (int x = 0; x < imageSize.width; x += imageSize.width ~/ 10) {
      final displayPoint1 = CoordinateUtils.imageCoordinatesToDisplayPosition(
        CoordinatePointXY(x.toDouble(), 0),
        imageSize,
        size
      );
      
      final displayPoint2 = CoordinateUtils.imageCoordinatesToDisplayPosition(
        CoordinatePointXY(x.toDouble(), imageSize.height),
        imageSize,
        size
      );
      
      canvas.drawLine(
        displayPoint1,
        displayPoint2,
        gridPaint
      );
    }
    
    // Draw horizontal grid lines
    for (int y = 0; y < imageSize.height; y += imageSize.height ~/ 10) {
      final displayPoint1 = CoordinateUtils.imageCoordinatesToDisplayPosition(
        CoordinatePointXY(0, y.toDouble()),
        imageSize,
        size
      );
      
      final displayPoint2 = CoordinateUtils.imageCoordinatesToDisplayPosition(
        CoordinatePointXY(imageSize.width, y.toDouble()),
        imageSize,
        size
      );
      
      canvas.drawLine(
        displayPoint1,
        displayPoint2,
        gridPaint
      );
    }
  }
  
  void _drawDebugLabels(Canvas canvas, Rect imageRect, Size size) {
    // Draw canvas size info
    _drawText(
      canvas, 
      'Canvas: ${size.width.toInt()}x${size.height.toInt()}', 
      Offset(10, 10),
      Colors.red
    );
    
    // Draw image size info
    _drawText(
      canvas, 
      'Image: ${imageSize.width.toInt()}x${imageSize.height.toInt()}', 
      Offset(10, 30),
      Colors.green
    );
    
    // Draw display area info
    _drawText(
      canvas, 
      'Display Area: ${imageRect.width.toInt()}x${imageRect.height.toInt()} at (${imageRect.left.toInt()},${imageRect.top.toInt()})', 
      Offset(10, 50),
      Colors.blue
    );
    
    // Draw aspect ratio info
    final imageAspect = imageSize.width / imageSize.height;
    final canvasAspect = size.width / size.height;
    _drawText(
      canvas, 
      'Aspect Ratio - Image: ${imageAspect.toStringAsFixed(2)}, Canvas: ${canvasAspect.toStringAsFixed(2)}', 
      Offset(10, 70),
      Colors.purple
    );
  }
  
  void _drawText(Canvas canvas, String text, Offset position, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              color: Colors.white,
              blurRadius: 2,
              offset: Offset(1, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    
    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(
        position.dx - 2, 
        position.dy - 2, 
        textPainter.width + 4, 
        textPainter.height + 4
      ),
      Paint()..color = Colors.white.withOpacity(0.7)
    );
    
    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(DebugPainter oldDelegate) {
    return imageSize != oldDelegate.imageSize;
  }
}