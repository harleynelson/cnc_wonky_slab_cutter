// lib/services/gcode/gcode_generator.dart
// Enhanced G-code generator for CNC operations

import '../../utils/general/machine_coordinates.dart';
import 'dart:math' as math;

/// Class to generate G-code for CNC operations
class GcodeGenerator {
  final double safetyHeight;
  final double feedRate;
  final double plungeRate;
  final double cuttingDepth;
  final double stepover;
  final double toolDiameter;
  final int spindleSpeed;
  
  GcodeGenerator({
    required this.safetyHeight,
    required this.feedRate,
    required this.plungeRate,
    required this.cuttingDepth,
    required this.stepover,
    required this.toolDiameter,
    this.spindleSpeed = 18000,
  });

  /// Generate G-code for a surfacing operation within a contour
  String generateSurfacingGcode(List<Point> contour) {
    final buffer = StringBuffer();
    
    // Write G-code header with initialization commands
    _writeHeader(buffer);
    
    // Calculate bounding box of the contour
    final boundingBox = _calculateBoundingBox(contour);
    
    // Generate toolpath for surfacing
    final toolpath = _generateSurfacingToolpath(contour, boundingBox);
    
    // Write the toolpath commands
    _writeSurfacingToolpath(buffer, toolpath, boundingBox);
    
    // Add footer
    _writeFooter(buffer);
    
    return buffer.toString();
  }

  /// Write G-code header with initialization commands
  void _writeHeader(StringBuffer buffer) {
    buffer.writeln("(CNC Slab Scanner - Surfacing Operation)");
    buffer.writeln("(Generated on ${DateTime.now().toString()})");
    buffer.writeln("(Tool Diameter: ${toolDiameter}mm)");
    buffer.writeln("(Stepover: ${stepover}mm)");
    buffer.writeln("(Cutting Depth: ${cuttingDepth}mm)");
    buffer.writeln("(Feed Rate: ${feedRate}mm/min)");
    buffer.writeln("(Plunge Rate: ${plungeRate}mm/min)");
    buffer.writeln("");
    buffer.writeln("G90 G94"); // Absolute positioning, Feed rate mode in units per minute
    buffer.writeln("G17");     // XY plane selection
    buffer.writeln("G21");     // Set units to millimeters
    buffer.writeln("");
    buffer.writeln("(Start operation)");
    buffer.writeln("S$spindleSpeed M3"); // Set spindle speed and start spindle
    buffer.writeln("G54");     // Use work coordinate system 1
    buffer.writeln("");
  }

  /// Calculate the bounding box of a contour
  Map<String, double> _calculateBoundingBox(List<Point> contour) {
    if (contour.isEmpty) {
      return {
        'minX': 0.0, 'minY': 0.0, 'maxX': 0.0, 'maxY': 0.0,
        'width': 0.0, 'height': 0.0, 'centerX': 0.0, 'centerY': 0.0
      };
    }
    
    double minX = contour[0].x;
    double minY = contour[0].y;
    double maxX = contour[0].x;
    double maxY = contour[0].y;
    
    for (int i = 1; i < contour.length; i++) {
      if (contour[i].x < minX) minX = contour[i].x;
      if (contour[i].y < minY) minY = contour[i].y;
      if (contour[i].x > maxX) maxX = contour[i].x;
      if (contour[i].y > maxY) maxY = contour[i].y;
    }
    
    final width = maxX - minX;
    final height = maxY - minY;
    final centerX = minX + width / 2;
    final centerY = minY + height / 2;
    
    return {
      'minX': minX, 'minY': minY, 'maxX': maxX, 'maxY': maxY,
      'width': width, 'height': height, 'centerX': centerX, 'centerY': centerY
    };
  }
  
  /// Generate toolpath for zigzag surfacing pattern
  List<List<Point>> _generateSurfacingToolpath(List<Point> contour, Map<String, double> boundingBox) {
    // Determine the primary direction based on the shape's dimensions
    final isHorizontal = boundingBox['width']! >= boundingBox['height']!;
    
    // Calculate the number of passes needed
    final double passDistance = stepover * toolDiameter;
    final int numPasses = isHorizontal 
        ? (boundingBox['height']! / passDistance).ceil()
        : (boundingBox['width']! / passDistance).ceil();
    
    // Create paths for each pass
    final List<List<Point>> allPaths = [];
    
    for (int i = 0; i < numPasses; i++) {
      final List<Point> path = [];
      
      if (isHorizontal) {
        // Horizontal zigzag
        final y = boundingBox['minY']! + i * passDistance;
        
        // Skip if this y value is outside the bounding box
        if (y > boundingBox['maxY']!) continue;
        
        // Determine start and end points (alternate direction for each pass)
        final startX = (i % 2 == 0) ? boundingBox['minX']! : boundingBox['maxX']!;
        final endX = (i % 2 == 0) ? boundingBox['maxX']! : boundingBox['minX']!;
        
        // Calculate intersection points with the contour
        final intersections = _findIntersectionsAtY(contour, y);
        
        // Sort the intersections
        if (i % 2 == 0) {
          // Left to right
          intersections.sort((a, b) => a.x.compareTo(b.x));
        } else {
          // Right to left
          intersections.sort((a, b) => b.x.compareTo(a.x));
        }
        
        // Create a path between each pair of intersections
        if (intersections.length >= 2) {
          for (int j = 0; j < intersections.length; j += 2) {
            if (j + 1 < intersections.length) {
              if (i % 2 == 0) {
                // Left to right
                path.add(Point(intersections[j].x, y));
                path.add(Point(intersections[j + 1].x, y));
              } else {
                // Right to left
                path.add(Point(intersections[j].x, y));
                path.add(Point(intersections[j + 1].x, y));
              }
            }
          }
        }
      } else {
        // Vertical zigzag
        final x = boundingBox['minX']! + i * passDistance;
        
        // Skip if this x value is outside the bounding box
        if (x > boundingBox['maxX']!) continue;
        
        // Determine start and end points (alternate direction for each pass)
        final startY = (i % 2 == 0) ? boundingBox['minY']! : boundingBox['maxY']!;
        final endY = (i % 2 == 0) ? boundingBox['maxY']! : boundingBox['minY']!;
        
        // Calculate intersection points with the contour
        final intersections = _findIntersectionsAtX(contour, x);
        
        // Sort the intersections
        if (i % 2 == 0) {
          // Bottom to top
          intersections.sort((a, b) => a.y.compareTo(b.y));
        } else {
          // Top to bottom
          intersections.sort((a, b) => b.y.compareTo(a.y));
        }
        
        // Create a path between each pair of intersections
        if (intersections.length >= 2) {
          for (int j = 0; j < intersections.length; j += 2) {
            if (j + 1 < intersections.length) {
              if (i % 2 == 0) {
                // Bottom to top
                path.add(Point(x, intersections[j].y));
                path.add(Point(x, intersections[j + 1].y));
              } else {
                // Top to bottom
                path.add(Point(x, intersections[j].y));
                path.add(Point(x, intersections[j + 1].y));
              }
            }
          }
        }
      }
      
      if (path.isNotEmpty) {
        allPaths.add(path);
      }
    }
    
    return allPaths;
  }
  
  /// Find all intersections of a horizontal line with a polygon at a specific y coordinate
  List<Point> _findIntersectionsAtY(List<Point> polygon, double y) {
    final intersections = <Point>[];
    
    for (int i = 0; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      
      // Skip horizontal segments (they would create duplicate intersections)
      if (p1.y == p2.y) continue;
      
      // Check if the y value is within the range of the segment
      if ((y >= p1.y && y <= p2.y) || (y >= p2.y && y <= p1.y)) {
        // Calculate the intersection x value using linear interpolation
        final t = (y - p1.y) / (p2.y - p1.y);
        final x = p1.x + t * (p2.x - p1.x);
        
        // Add the intersection point
        intersections.add(Point(x, y));
      }
    }
    
    return intersections;
  }
  
  /// Find all intersections of a vertical line with a polygon at a specific x coordinate
  List<Point> _findIntersectionsAtX(List<Point> polygon, double x) {
    final intersections = <Point>[];
    
    for (int i = 0; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      
      // Skip vertical segments (they would create duplicate intersections)
      if (p1.x == p2.x) continue;
      
      // Check if the x value is within the range of the segment
      if ((x >= p1.x && x <= p2.x) || (x >= p2.x && x <= p1.x)) {
        // Calculate the intersection y value using linear interpolation
        final t = (x - p1.x) / (p2.x - p1.x);
        final y = p1.y + t * (p2.y - p1.y);
        
        // Add the intersection point
        intersections.add(Point(x, y));
      }
    }
    
    return intersections;
  }
  
  /// Write surfacing toolpath commands
  void _writeSurfacingToolpath(StringBuffer buffer, List<List<Point>> toolpaths, Map<String, double> boundingBox) {
    if (toolpaths.isEmpty) {
      buffer.writeln("(No valid toolpath generated)");
      return;
    }
    
    // Move to safe height first
    buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(4)}");
    
    // Process each path
    for (int i = 0; i < toolpaths.length; i++) {
      final path = toolpaths[i];
      
      if (path.isEmpty) continue;
      
      // Move to the start of this path
      buffer.writeln("G0 X${path[0].x.toStringAsFixed(4)} Y${path[0].y.toStringAsFixed(4)}");
      
      // First path: plunge to cutting depth
      if (i == 0) {
        buffer.writeln("G1 Z${safetyHeight.toStringAsFixed(4)} F${feedRate.toStringAsFixed(1)}");
        buffer.writeln("Z0 F${plungeRate.toStringAsFixed(1)}");  // Move to surface level first
        buffer.writeln("Z${cuttingDepth.toStringAsFixed(4)} F${plungeRate.toStringAsFixed(1)}");  // Plunge to cutting depth
      }
      
      // Process each segment in this path
      for (int j = 1; j < path.length; j++) {
        final point = path[j];
        buffer.writeln("G1 X${point.x.toStringAsFixed(4)} Y${point.y.toStringAsFixed(4)} F${feedRate.toStringAsFixed(1)}");
      }
      
      // If not the last path, move to safe height to avoid any protrusions
      if (i < toolpaths.length - 1) {
        buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(4)}");
      }
    }
  }
  
  /// Write G-code footer with end program commands
  void _writeFooter(StringBuffer buffer) {
    buffer.writeln("");
    buffer.writeln("(End operation)");
    buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(4)}"); // Retract to safe height
    buffer.writeln("G0 X0 Y0"); // Return to home position
    buffer.writeln("M5"); // Spindle off
    buffer.writeln("M30"); // End program
  }

  /// Legacy methods for backward compatibility

  /// Generate G-code from a toolpath
  String generateGcode(List<Point> toolpath) {
    final buffer = StringBuffer();
    
    _writeHeader(buffer);
    _writeToolpath(buffer, toolpath);
    _writeFooter(buffer);
    
    return buffer.toString();
  }

  /// Write toolpath movements (legacy method)
  void _writeToolpath(StringBuffer buffer, List<Point> toolpath) {
    if (toolpath.isEmpty) {
      buffer.writeln("(Warning: Empty toolpath)");
      return;
    }
    
    // First point: rapid move to position
    final startPoint = toolpath.first;
    buffer.writeln("G0 X${startPoint.x.toStringAsFixed(4)} Y${startPoint.y.toStringAsFixed(4)}"); // Rapid to start position
    
    // Plunge to cutting depth
    buffer.writeln("G1 Z0 F${plungeRate.toStringAsFixed(1)}"); // Go to surface
    buffer.writeln("G1 Z${cuttingDepth.toStringAsFixed(4)} F${plungeRate.toStringAsFixed(1)}"); // Plunge to cutting depth
    
    // Process remaining points with feed moves
    for (int i = 1; i < toolpath.length; i++) {
      final point = toolpath[i];
      buffer.writeln("G1 X${point.x.toStringAsFixed(4)} Y${point.y.toStringAsFixed(4)} F${feedRate.toStringAsFixed(1)}");
    }
  }

  /// Generate G-code for a contour following operation (legacy method)
  String generateContourGcode(List<Point> contour) {
    final buffer = StringBuffer();
    
    _writeHeader(buffer);
    
    // First follow the contour completely at cutting depth
    if (contour.isNotEmpty) {
      // Move to first point
      final startPoint = contour.first;
      buffer.writeln("G0 X${startPoint.x.toStringAsFixed(4)} Y${startPoint.y.toStringAsFixed(4)}"); // Rapid to contour start
      
      // Plunge to cutting depth
      buffer.writeln("G1 Z0 F${plungeRate.toStringAsFixed(1)}"); // Go to surface
      buffer.writeln("G1 Z${cuttingDepth.toStringAsFixed(4)} F${plungeRate.toStringAsFixed(1)}"); // Plunge to cutting depth
      
      // Follow the contour
      for (int i = 1; i < contour.length; i++) {
        final point = contour[i];
        buffer.writeln("G1 X${point.x.toStringAsFixed(4)} Y${point.y.toStringAsFixed(4)} F${feedRate.toStringAsFixed(1)}");
      }
      
      // Close the contour by returning to the first point
      buffer.writeln("G1 X${startPoint.x.toStringAsFixed(4)} Y${startPoint.y.toStringAsFixed(4)} F${feedRate.toStringAsFixed(1)}"); // Close contour
    }
    
    _writeFooter(buffer);
    
    return buffer.toString();
  }
}