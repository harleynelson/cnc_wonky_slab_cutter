// lib/services/gcode/gcode_generator.dart
// Enhanced G-code generator for CNC operations

import '../../utils/general/machine_coordinates.dart';

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
    // Add a small safety margin to ensure we don't miss any intersections
    final safetyMargin = 0.1;
    final minX = boundingBox['minX']! - safetyMargin;
    final maxX = boundingBox['maxX']! + safetyMargin;
    final minY = boundingBox['minY']! - safetyMargin;
    final maxY = boundingBox['maxY']! + safetyMargin;
    final width = maxX - minX;
    final height = maxY - minY;
    
    // Determine the primary direction based on the shape's dimensions
    final isHorizontal = width >= height;
    
    // Calculate the number of passes needed
    final double passDistance = stepover * toolDiameter;
    final int numPasses = isHorizontal 
        ? (height / passDistance).ceil() + 1
        : (width / passDistance).ceil() + 1;
    
    // Create paths for each pass
    final List<List<Point>> allPaths = [];
    
    // Ensure contour is closed
    List<Point> workingContour = List<Point>.from(contour);
    if (workingContour.isEmpty || 
        (workingContour.first.x != workingContour.last.x || 
         workingContour.first.y != workingContour.last.y)) {
      if (workingContour.isNotEmpty) {
        workingContour.add(workingContour.first);
      }
    }
    
    for (int i = 0; i < numPasses; i++) {
      final List<Point> path = [];
      
      if (isHorizontal) {
        // Horizontal zigzag (constant y)
        final y = minY + i * passDistance;
        
        // Skip if this y value is outside the bounding box
        if (y > maxY) continue;
        
        // Calculate intersection points with the contour
        final intersections = _findIntersectionsAtY(workingContour, y);
        
        // Need at least 2 intersections to create a path
        if (intersections.length < 2) continue;
        
        // Sort the intersections by x-coordinate
        intersections.sort((a, b) => a.x.compareTo(b.x));
        
        // For even passes go left-to-right, for odd passes go right-to-left
        if (i % 2 != 0) {
          intersections.reversed.toList();
        }
        
        // Combine intersections into pairs
        for (int j = 0; j < intersections.length - 1; j += 2) {
          if (j + 1 < intersections.length) {
            // Add this segment to the path
            if (i % 2 == 0) {
              // Left to right
              path.add(Point(intersections[j].x, y));
              path.add(Point(intersections[j + 1].x, y));
            } else {
              // Right to left
              path.add(Point(intersections[j + 1].x, y));
              path.add(Point(intersections[j].x, y));
            }
          }
        }
      } else {
        // Vertical zigzag (constant x)
        final x = minX + i * passDistance;
        
        // Skip if this x value is outside the bounding box
        if (x > maxX) continue;
        
        // Calculate intersection points with the contour
        final intersections = _findIntersectionsAtX(workingContour, x);
        
        // Need at least 2 intersections to create a path
        if (intersections.length < 2) continue;
        
        // Sort the intersections by y-coordinate
        intersections.sort((a, b) => a.y.compareTo(b.y));
        
        // Create path depending on direction
        if (i % 2 == 0) {
          // Bottom to top - y coordinates in ascending order
          for (int j = 0; j < intersections.length - 1; j += 2) {
            if (j + 1 < intersections.length) {
              path.add(Point(x, intersections[j].y));
              path.add(Point(x, intersections[j + 1].y));
            }
          }
        } else {
          // Top to bottom - y coordinates in descending order
          for (int j = intersections.length - 1; j > 0; j -= 2) {
            if (j - 1 >= 0) {
              path.add(Point(x, intersections[j].y));
              path.add(Point(x, intersections[j - 1].y));
            }
          }
        }
      }
      
      if (path.length >= 2) {
        allPaths.add(path);
      }
    }
    
    return allPaths;
  }
  
  /// Find all intersections of a horizontal line with a polygon at a specific y coordinate
  List<Point> _findIntersectionsAtY(List<Point> polygon, double y) {
    final intersections = <Point>[];
    final double epsilon = 1e-10; // Small value for floating point comparison
    
    for (int i = 0; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      
      // Handle horizontal segments specially
      if ((p1.y - p2.y).abs() < epsilon) {
        // If the segment is at exactly the y value we're looking for,
        // add both endpoints as intersections
        if ((p1.y - y).abs() < epsilon) {
          intersections.add(Point(p1.x, y));
          intersections.add(Point(p2.x, y));
        }
        continue;
      }
      
      // Check if the y value is within the range of the segment
      if ((y >= p1.y - epsilon && y <= p2.y + epsilon) || 
          (y >= p2.y - epsilon && y <= p1.y + epsilon)) {
        // Calculate the intersection x value using linear interpolation
        final t = (y - p1.y) / (p2.y - p1.y);
        
        // Avoid out of range t values due to floating point issues
        if (t >= 0 - epsilon && t <= 1 + epsilon) {
          final x = p1.x + t * (p2.x - p1.x);
          
          // Add the intersection point
          intersections.add(Point(x, y));
        }
      }
    }
    
    // Remove duplicates
    final uniqueIntersections = <Point>[];
    for (var point in intersections) {
      bool isDuplicate = false;
      for (var unique in uniqueIntersections) {
        if ((point.x - unique.x).abs() < epsilon && 
            (point.y - unique.y).abs() < epsilon) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        uniqueIntersections.add(point);
      }
    }
    
    return uniqueIntersections;
  }
  
  /// Find all intersections of a vertical line with a polygon at a specific x coordinate
  List<Point> _findIntersectionsAtX(List<Point> polygon, double x) {
    final intersections = <Point>[];
    final double epsilon = 1e-10; // Small value for floating point comparison
    
    for (int i = 0; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      
      // Handle vertical segments specially
      if ((p1.x - p2.x).abs() < epsilon) {
        // If the segment is at exactly the x value we're looking for,
        // add both endpoints as intersections
        if ((p1.x - x).abs() < epsilon) {
          intersections.add(Point(x, p1.y));
          intersections.add(Point(x, p2.y));
        }
        continue;
      }
      
      // Check if the x value is within the range of the segment
      if ((x >= p1.x - epsilon && x <= p2.x + epsilon) || 
          (x >= p2.x - epsilon && x <= p1.x + epsilon)) {
        // Calculate the intersection y value using linear interpolation
        final t = (x - p1.x) / (p2.x - p1.x);
        
        // Avoid out of range t values due to floating point issues
        if (t >= 0 - epsilon && t <= 1 + epsilon) {
          final y = p1.y + t * (p2.y - p1.y);
          
          // Add the intersection point
          intersections.add(Point(x, y));
        }
      }
    }
    
    // Remove duplicates
    final uniqueIntersections = <Point>[];
    for (var point in intersections) {
      bool isDuplicate = false;
      for (var unique in uniqueIntersections) {
        if ((point.x - unique.x).abs() < epsilon && 
            (point.y - unique.y).abs() < epsilon) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        uniqueIntersections.add(point);
      }
    }
    
    return uniqueIntersections;
  }
  
  /// Write surfacing toolpath commands
  void _writeSurfacingToolpath(StringBuffer buffer, List<List<Point>> toolpaths, Map<String, double> boundingBox) {
    if (toolpaths.isEmpty) {
      buffer.writeln("(No valid toolpath generated)");
      return;
    }
    
    // Move to safe height first
    buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(4)}");
    
    // Add debug info
    buffer.writeln("(Generated ${toolpaths.length} toolpaths)");
    
    // Process each path
    for (int i = 0; i < toolpaths.length; i++) {
      final path = toolpaths[i];
      
      if (path.isEmpty || path.length < 2) {
        buffer.writeln("(Skipping empty path ${i})");
        continue;
      }
      
      buffer.writeln("(Path ${i} - ${path.length} points)");
      
      // Move to the start of this path
      buffer.writeln("G0 X${path[0].x.toStringAsFixed(4)} Y${path[0].y.toStringAsFixed(4)}");
      
      // First point of first path: plunge to cutting depth
      if (i == 0) {
        buffer.writeln("G1 Z0 F${plungeRate.toStringAsFixed(1)}");  // Move to surface level first
        buffer.writeln("Z${cuttingDepth.toStringAsFixed(4)} F${plungeRate.toStringAsFixed(1)}");  // Plunge to cutting depth
      } else {
        // For subsequent paths, we're already at cutting depth
        buffer.writeln("G1 Z${cuttingDepth.toStringAsFixed(4)} F${plungeRate.toStringAsFixed(1)}");
      }
      
      // Cut along the path
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