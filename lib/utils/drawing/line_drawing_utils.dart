// lib/utils/drawing/line_drawing_utils.dart
// Utilities for drawing various types of lines on a canvas

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Utility class for drawing various types of lines
class LineDrawingUtils {
  /// Draw a dashed line between two points
  static void drawDashedLine(
    Canvas canvas, 
    Offset start, 
    Offset end, 
    Paint paint, 
    {double dashLength = 5, double spaceLength = 5}
  ) {
    // Calculate the delta values and the total distance
    double dx = end.dx - start.dx;
    double dy = end.dy - start.dy;
    double distance = math.sqrt(dx * dx + dy * dy);
    
    // Normalize the direction vector
    double nx = dx / distance;
    double ny = dy / distance;
    
    // Pattern: dash, space, dash, space, ...
    double drawn = 0;
    bool isDash = true;
    
    while (drawn < distance) {
      double segmentLength = isDash ? dashLength : spaceLength;
      if (drawn + segmentLength > distance) {
        segmentLength = distance - drawn;
      }
      
      if (isDash) {
        double startX = start.dx + drawn * nx;
        double startY = start.dy + drawn * ny;
        double endX = start.dx + (drawn + segmentLength) * nx;
        double endY = start.dy + (drawn + segmentLength) * ny;
        
        canvas.drawLine(
          Offset(startX, startY),
          Offset(endX, endY),
          paint
        );
      }
      
      drawn += segmentLength;
      isDash = !isDash;
    }
  }
  
  /// Draw a dotted line between two points
  static void drawDottedLine(
    Canvas canvas, 
    Offset start, 
    Offset end, 
    Paint paint, 
    {double dotRadius = 2, double spacing = 5}
  ) {
    // Calculate the delta values and the total distance
    double dx = end.dx - start.dx;
    double dy = end.dy - start.dy;
    double distance = math.sqrt(dx * dx + dy * dy);
    
    // Normalize the direction vector
    double nx = dx / distance;
    double ny = dy / distance;
    
    // Total step size (dot + space)
    double stepSize = spacing;
    int steps = (distance / stepSize).ceil();
    
    // Draw dots along the line
    for (int i = 0; i < steps; i++) {
      double t = i * stepSize;
      if (t > distance) break;
      
      double x = start.dx + t * nx;
      double y = start.dy + t * ny;
      
      canvas.drawCircle(Offset(x, y), dotRadius, paint);
    }
  }
  
  /// Draw a line with an arrow at the end
  static void drawArrowLine(
    Canvas canvas, 
    Offset start, 
    Offset end, 
    Paint paint, 
    {double arrowSize = 10}
  ) {
    // Draw the main line
    canvas.drawLine(start, end, paint);
    
    // Calculate arrow head
    double angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    
    Path path = Path();
    path.moveTo(end.dx, end.dy);
    path.lineTo(
      end.dx - arrowSize * math.cos(angle - math.pi / 6),
      end.dy - arrowSize * math.sin(angle - math.pi / 6)
    );
    path.lineTo(
      end.dx - arrowSize * math.cos(angle + math.pi / 6),
      end.dy - arrowSize * math.sin(angle + math.pi / 6)
    );
    path.close();
    
    canvas.drawPath(path, paint);
  }
  
  /// Draw a thick line with adjustable thickness
  static void drawThickLine(
    Canvas canvas, 
    Offset start, 
    Offset end, 
    Paint paint, 
    {double thickness = 3}
  ) {
    // Calculate direction and perpendicular vectors
    double dx = end.dx - start.dx;
    double dy = end.dy - start.dy;
    double length = math.sqrt(dx * dx + dy * dy);
    
    if (length < 1e-10) return; // Skip very short lines
    
    // Normalize and get perpendicular
    double nx = dx / length;
    double ny = dy / length;
    double px = -ny;
    double py = nx;
    
    // Half thickness
    double halfThickness = thickness / 2;
    
    // Create a polygon for the thick line
    final path = Path();
    path.moveTo(start.dx + px * halfThickness, start.dy + py * halfThickness);
    path.lineTo(end.dx + px * halfThickness, end.dy + py * halfThickness);
    path.lineTo(end.dx - px * halfThickness, end.dy - py * halfThickness);
    path.lineTo(start.dx - px * halfThickness, start.dy - py * halfThickness);
    path.close();
    
    // Draw the path
    canvas.drawPath(path, paint);
  }
}