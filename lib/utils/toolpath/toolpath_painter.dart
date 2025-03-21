// lib/utils/visualization/toolpath_painter.dart
// Utility for painting toolpaths on a canvas

import 'package:flutter/material.dart';
import '../general/machine_coordinates.dart';
import '../general/settings_model.dart';
import '../drawing/line_drawing_utils.dart';

class ToolpathPainter extends CustomPainter {
  final List<List<CoordinatePointXY>> toolpaths;
  final Size imageSize;
  final MachineCoordinateSystem coordSystem;
  final SettingsModel settings;

  ToolpathPainter({
    required this.toolpaths,
    required this.imageSize,
    required this.coordSystem,
    required this.settings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (toolpaths.isEmpty) return;
    
    // Create paints
    final cutPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final rapidPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
      
    // Special paint for return-to-home movement
    final homePaint = Paint()
      ..color = Colors.purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
      
    // Create dashed pattern for return-to-home
    final homeDashPaint = Paint()
      ..color = Colors.purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;
    
    // Draw the machine origin for reference
    final originPixel = coordSystem.machineToPixelCoords(CoordinatePointXY(0, 0));
    final originDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
      originPixel, imageSize, size);
    
    canvas.drawCircle(
      Offset(originDisplay.x, originDisplay.y),
      6.0,
      Paint()..color = Colors.purple..style = PaintingStyle.fill
    );
    
    // Draw text "Origin" next to the point
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Machine Origin',
        style: TextStyle(
          color: Colors.purple,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.white.withOpacity(0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(originDisplay.x + 10, originDisplay.y - 10));
    
    // First draw traverse paths (if present - assumed to be the first path)
    if (toolpaths.length > 0 && toolpaths[0].isNotEmpty) {
      bool isFirstPath = true;
      final traversePath = toolpaths[0];
      final traversePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      
      // Special dashed pattern for traverse moves
      traversePaint.strokeWidth = 1.5;
      
      if (traversePath.length > 1) {
        for (int i = 0; i < traversePath.length - 1; i++) {
          final CoordinatePointXY p1 = traversePath[i];
          final CoordinatePointXY p2 = traversePath[i + 1];
          
          // Convert to display coordinates
          final p1Pixel = coordSystem.machineToPixelCoords(p1);
          final p2Pixel = coordSystem.machineToPixelCoords(p2);
          
          final p1Display = MachineCoordinateSystem.imageToDisplayCoordinates(
            p1Pixel, imageSize, size);
          final p2Display = MachineCoordinateSystem.imageToDisplayCoordinates(
            p2Pixel, imageSize, size);
          
          // Draw traverse line
          canvas.drawLine(
            Offset(p1Display.x, p1Display.y),
            Offset(p2Display.x, p2Display.y),
            traversePaint
          );
          
          // Draw small circles at the start and end
          canvas.drawCircle(
            Offset(p1Display.x, p1Display.y),
            2.0,
            Paint()..color = Colors.red..style = PaintingStyle.fill
          );
          
          // Mark the first point with a special indicator
          if (isFirstPath && i == 0) {
            canvas.drawCircle(
              Offset(p1Display.x, p1Display.y),
              5.0,
              Paint()
                ..color = Colors.yellow
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.0
            );
            
            // Add "Start" label
            final textPainter = TextPainter(
              text: TextSpan(
                text: 'Start',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  backgroundColor: Colors.yellow.withOpacity(0.7),
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            textPainter.layout();
            textPainter.paint(canvas, Offset(p1Display.x + 10, p1Display.y - 10));
            
            isFirstPath = false;
          }
        }
      }
    }
    
    // Then draw cutting paths (skip the first one if it's traverse)
    for (int i = 1; i < toolpaths.length; i++) {
      final path = toolpaths[i];
      if (path.isEmpty) continue;
      
      // Adjust opacity based on layer index for multi-layer display
      final opacity = toolpaths.length <= 2 ? 
          1.0 : 
          0.3 + (0.7 * i / (toolpaths.length - 1));
      
      cutPaint.color = Colors.blue.withOpacity(opacity);
      
      // Draw the complete cutting path as one continuous line
      // This helps prevent any apparent slope due to improper point placement
      final cutPath = Path();
      bool first = true;
      
      for (int j = 0; j < path.length; j++) {
        final point = path[j];
        
        // Convert to display coordinates
        final pixelPoint = coordSystem.machineToPixelCoords(point);
        final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
          pixelPoint, imageSize, size);
        
        if (first) {
          cutPath.moveTo(displayPoint.x, displayPoint.y);
          first = false;
        } else {
          cutPath.lineTo(displayPoint.x, displayPoint.y);
        }
        
        // Draw points at vertices
        if (j % 10 == 0 || j == 0 || j == path.length - 1) { // Draw fewer points to reduce clutter
          canvas.drawCircle(
            Offset(displayPoint.x, displayPoint.y),
            1.0,
            pointPaint
          );
        }
      }
      
      // Draw the complete path at once
      canvas.drawPath(cutPath, cutPaint);
      
      // Draw start and end points more prominently
      if (path.length > 1) {
        // Start point
        final startPixel = coordSystem.machineToPixelCoords(path.first);
        final startDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
          startPixel, imageSize, size);
        
        canvas.drawCircle(
          Offset(startDisplay.x, startDisplay.y),
          3.0,
          Paint()..color = Colors.green..style = PaintingStyle.fill
        );
        
        // End point
        final endPixel = coordSystem.machineToPixelCoords(path.last);
        final endDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
          endPixel, imageSize, size);
        
        canvas.drawCircle(
          Offset(endDisplay.x, endDisplay.y),
          3.0,
          Paint()..color = Colors.orange..style = PaintingStyle.fill
        );
        
        // Add return-to-home visualization if it's the last toolpath
        if (i == toolpaths.length - 1 && settings.returnToHome) {
          // Draw the return-to-home path
          final lastPoint = path.last;
          final homePoint = CoordinatePointXY(0, 0);
          
          // Convert to display coordinates
          final lastPixel = coordSystem.machineToPixelCoords(lastPoint);
          final homePixel = coordSystem.machineToPixelCoords(homePoint);
          
          final lastDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
            lastPixel, imageSize, size);
          final homeDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
            homePixel, imageSize, size);
          
          // Draw dashed return-to-home line
          LineDrawingUtils.drawDashedLine(
            canvas,
            Offset(lastDisplay.x, lastDisplay.y),
            Offset(homeDisplay.x, homeDisplay.y),
            homeDashPaint,
            dashLength: 5,
            spaceLength: 5
          );
          
          // Add "Return Home" label
          final textPainter = TextPainter(
            text: TextSpan(
              text: 'Return Home',
              style: TextStyle(
                color: Colors.purple,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                backgroundColor: Colors.white.withOpacity(0.7),
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          
          // Calculate midpoint of return-to-home line for label placement
          final midX = (lastDisplay.x + homeDisplay.x) / 2;
          final midY = (lastDisplay.y + homeDisplay.y) / 2;
          
          textPainter.paint(canvas, Offset(midX, midY - 15));
        }
      }
    }
  }

  

  // Use the utility class for drawing dashed lines

  @override
  bool shouldRepaint(ToolpathPainter oldDelegate) {
    return toolpaths != oldDelegate.toolpaths ||
           imageSize != oldDelegate.imageSize ||
           settings != oldDelegate.settings;
  }
}