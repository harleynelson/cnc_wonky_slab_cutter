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
  final int depthPasses;
  final double margin;
  final bool forceHorizontal;
  final bool returnToHome; // return to home position
  
  GcodeGenerator({
    required this.safetyHeight,
    required this.feedRate,
    required this.plungeRate,
    required this.cuttingDepth,
    required this.stepover,
    required this.toolDiameter,
    this.spindleSpeed = 18000,
    this.depthPasses = 1,
    this.margin = 5.0,
    this.forceHorizontal = true, // Default to horizontal paths
    this.returnToHome = true, // return to home position
  });

  /// Generate G-code for a surfacing operation within a contour
  String generateSurfacingGcode(List<CoordinatePointXY> contour, {String filename = ''}) {
  final buffer = StringBuffer();
  
  // Write G-code header with initialization commands
  _writeHeader(buffer, filename: filename);
  
  // Calculate bounding box of the contour
  final boundingBox = _calculateBoundingBox(contour);
  
  // Generate toolpath for surfacing
  final toolpath = _generateSurfacingToolpath(contour, boundingBox);
  
  // Write the toolpath commands
  _writeSurfacingToolpath(buffer, toolpath, boundingBox, contour);
  
  // Add footer
  _writeFooter(buffer);
  
  return buffer.toString();
}

  /// Write G-code header with initialization commands
  void _writeHeader(StringBuffer buffer, {String filename = ''}) {
    buffer.writeln("(CNC Slab Scanner - Surfacing Operation)");
    buffer.writeln("(Generated on ${DateTime.now().toString()})");
    if (filename.isNotEmpty) {
      buffer.writeln("(Filename: $filename)");
    }
    buffer.writeln("(Tool Diameter: ${toolDiameter}mm)");
    buffer.writeln("(Stepover: ${stepover}mm)");
    buffer.writeln("(Cutting Depth: ${cuttingDepth}mm in $depthPasses passes)");
    buffer.writeln("(Feed Rate: ${feedRate}mm/min)");
    buffer.writeln("(Plunge Rate: ${plungeRate}mm/min)");
    buffer.writeln("(Path Direction: ${forceHorizontal ? 'Horizontal' : 'Vertical'})");
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
  Map<String, double> _calculateBoundingBox(List<CoordinatePointXY> contour) {
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
    
    // Apply margin to the bounding box
    minX -= margin;
    minY -= margin;
    maxX += margin;
    maxY += margin;
    
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
  List<List<CoordinatePointXY>> _generateSurfacingToolpath(List<CoordinatePointXY> contour, Map<String, double> boundingBox) {
    // Get boundary values
    final minX = boundingBox['minX']!;
    final minY = boundingBox['minY']!;
    final maxX = boundingBox['maxX']!;
    final maxY = boundingBox['maxY']!;
    final width = boundingBox['width']!;
    final height = boundingBox['height']!;
    
    // Determine the primary direction based on settings or shape dimensions
    bool isHorizontal = forceHorizontal || width >= height;
    
    // Calculate stepover distance based on tool diameter
    final double effectiveStepover = stepover <= 0 ? toolDiameter * 0.75 : stepover;
    
    // Calculate number of passes
    final int numPasses = isHorizontal 
        ? (height / effectiveStepover).ceil() + 1
        : (width / effectiveStepover).ceil() + 1;
    
    // Create toolpaths array
    final List<List<CoordinatePointXY>> toolpaths = [];
    
    // Optimize for U-shaped pieces - determine if we should bridge gaps
    final shouldBridgeGaps = true; // This could be a setting parameter
    
    // Generate parallel toolpaths
    for (int i = 0; i < numPasses; i++) {
      List<CoordinatePointXY> currentPath = [];
      
      if (isHorizontal) {
        // Horizontal passes (fixed Y)
        double y = minY + i * effectiveStepover;
        
        // Ensure we don't exceed the maximum Y
        if (y > maxY) continue;
        
        // Generate line segments that intersect with the contour
        List<CoordinatePointXY> intersections = _findLineContourIntersections(
          minX, y, maxX, y, contour
        );
        
        // Skip if no intersections found
        if (intersections.isEmpty) continue;
        
        // Sort intersections by X coordinate
        intersections.sort((a, b) => a.x.compareTo(b.x));
        
        // Determine direction (alternate for zig-zag)
        bool leftToRight = (i % 2 == 0);
        
        if (shouldBridgeGaps) {
          // Efficient path - bridge gaps for U-shaped pieces
          if (leftToRight) {
            currentPath.add(intersections.first);
            currentPath.add(intersections.last);
          } else {
            currentPath.add(intersections.last);
            currentPath.add(intersections.first);
          }
        } else {
          // Strictly follow contour - move through each pair of intersections
          for (int j = 0; j < intersections.length - 1; j += 2) {
            if (j + 1 < intersections.length) {
              if (leftToRight) {
                currentPath.add(intersections[j]);
                currentPath.add(intersections[j + 1]);
              } else {
                currentPath.add(intersections[j + 1]);
                currentPath.add(intersections[j]);
              }
            }
          }
        }
      } else {
        // Vertical passes (fixed X)
        double x = minX + i * effectiveStepover;
        
        // Ensure we don't exceed the maximum X
        if (x > maxX) continue;
        
        // Generate line segments that intersect with the contour
        List<CoordinatePointXY> intersections = _findLineContourIntersections(
          x, minY, x, maxY, contour
        );
        
        // Skip if no intersections found
        if (intersections.isEmpty) continue;
        
        // Sort intersections by Y coordinate
        intersections.sort((a, b) => a.y.compareTo(b.y));
        
        // Determine direction (alternate for zig-zag)
        bool bottomToTop = (i % 2 == 0);
        
        if (shouldBridgeGaps) {
          // Efficient path - bridge gaps
          if (bottomToTop) {
            currentPath.add(intersections.first);
            currentPath.add(intersections.last);
          } else {
            currentPath.add(intersections.last);
            currentPath.add(intersections.first);
          }
        } else {
          // Strictly follow contour
          for (int j = 0; j < intersections.length - 1; j += 2) {
            if (j + 1 < intersections.length) {
              if (bottomToTop) {
                currentPath.add(intersections[j]);
                currentPath.add(intersections[j + 1]);
              } else {
                currentPath.add(intersections[j + 1]);
                currentPath.add(intersections[j]);
              }
            }
          }
        }
      }
      
      // Add path segments to toolpaths
      if (currentPath.isNotEmpty) {
        toolpaths.add(currentPath);
      }
    }
    
    return toolpaths;
  }

  /// Find intersections between a line and a contour
  List<CoordinatePointXY> _findLineContourIntersections(
    double x1, double y1, double x2, double y2, List<CoordinatePointXY> contour
  ) {
    final intersections = <CoordinatePointXY>[];
    
    // Ensure contour is closed
    if (contour.length < 3) return [];
    
    List<CoordinatePointXY> closedContour = List.from(contour);
    if (closedContour.first.x != closedContour.last.x || 
        closedContour.first.y != closedContour.last.y) {
      closedContour.add(closedContour.first);
    }
    
    // Check for intersections with each segment of the contour
    for (int i = 0; i < closedContour.length - 1; i++) {
      final p3 = closedContour[i];
      final p4 = closedContour[i + 1];
      
      final intersection = _lineIntersection(
        x1, y1, x2, y2, p3.x, p3.y, p4.x, p4.y
      );
      
      if (intersection != null) {
        intersections.add(intersection);
      }
    }
    
    return intersections;
  }

  /// Calculate the intersection point between two line segments
  CoordinatePointXY? _lineIntersection(
    double x1, double y1, double x2, double y2,
    double x3, double y3, double x4, double y4
  ) {
    // Calculate denominators
    double den = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1);
    
    // Lines are parallel if denominator is zero
    if (den.abs() < 1e-10) return null;
    
    // Calculate ua and ub
    double ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / den;
    double ub = ((x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3)) / den;
    
    // Return intersection point if segments intersect
    if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
      double x = x1 + ua * (x2 - x1);
      double y = y1 + ua * (y2 - y1);
      return CoordinatePointXY(x, y);
    }
    
    return null;
  }
  
  /// Find all intersections of a horizontal line with a polygon at a specific y coordinate
  List<CoordinatePointXY> _findIntersectionsAtY(List<CoordinatePointXY> polygon, double y) {
    final intersections = <CoordinatePointXY>[];
    final double epsilon = 1e-10; // Small value for floating point comparison
    
    for (int i = 0; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      
      // Handle horizontal segments specially
      if ((p1.y - p2.y).abs() < epsilon) {
        // If the segment is at exactly the y value we're looking for,
        // add both endpoints as intersections
        if ((p1.y - y).abs() < epsilon) {
          intersections.add(CoordinatePointXY(p1.x, y));
          intersections.add(CoordinatePointXY(p2.x, y));
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
          intersections.add(CoordinatePointXY(x, y));
        }
      }
    }
    
    // Remove duplicates
    final uniqueIntersections = <CoordinatePointXY>[];
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
  List<CoordinatePointXY> _findIntersectionsAtX(List<CoordinatePointXY> polygon, double x) {
    final intersections = <CoordinatePointXY>[];
    final double epsilon = 1e-10; // Small value for floating point comparison
    
    for (int i = 0; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      
      // Handle vertical segments specially
      if ((p1.x - p2.x).abs() < epsilon) {
        // If the segment is at exactly the x value we're looking for,
        // add both endpoints as intersections
        if ((p1.x - x).abs() < epsilon) {
          intersections.add(CoordinatePointXY(x, p1.y));
          intersections.add(CoordinatePointXY(x, p2.y));
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
          intersections.add(CoordinatePointXY(x, y));
        }
      }
    }
    
    // Remove duplicates
    final uniqueIntersections = <CoordinatePointXY>[];
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
  
  /// Write surfacing toolpath commands with multiple depth passes
  void _writeSurfacingToolpath(
    StringBuffer buffer, 
    List<List<CoordinatePointXY>> toolpaths, 
    Map<String, double> boundingBox,
    List<CoordinatePointXY> contour
  ) {
    if (toolpaths.isEmpty) {
      buffer.writeln("(No valid toolpath generated)");
      return;
    }
    
    // Get direction information for debug output
    final width = boundingBox['width']!;
    final height = boundingBox['height']!;
    final isHorizontal = forceHorizontal || width >= height;
    
    // Add debug info
    buffer.writeln("(Toolpath: ${isHorizontal ? 'Horizontal' : 'Vertical'} pattern with ${toolpaths.length} passes)");
    buffer.writeln("(Bounding box: X=${boundingBox['minX']!.toStringAsFixed(2)} to ${boundingBox['maxX']!.toStringAsFixed(2)}, Y=${boundingBox['minY']!.toStringAsFixed(2)} to ${boundingBox['maxY']!.toStringAsFixed(2)})");
    buffer.writeln("(Optimized to only cut within contour + ${margin}mm margin)");
    buffer.writeln("(Keeping tool down when connecting passes)");
    
    // Move to safe height first
    buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(4)}");
    
    // Calculate pass depth increment if multiple passes are needed
    final passDepthIncrement = cuttingDepth / depthPasses;
    buffer.writeln("(Total cutting depth: ${cuttingDepth}mm in $depthPasses passes)");
    
    // For each depth pass
    for (int depthPass = 1; depthPass <= depthPasses; depthPass++) {
      final currentDepth = passDepthIncrement * depthPass;
      // Handle negative values properly by formatting after calculation
      final depthString = (currentDepth > 0 ? "-" : "") + currentDepth.abs().toStringAsFixed(4);
      
      buffer.writeln("");
      buffer.writeln("(Depth pass $depthPass of $depthPasses - depth: ${depthString}mm)");
      
      // Process each path
      CoordinatePointXY? lastEndPoint;
      
      for (int i = 0; i < toolpaths.length; i++) {
        final path = toolpaths[i];
        
        if (path.isEmpty || path.length < 2) {
          buffer.writeln("(Skipping empty path ${i})");
          continue;
        }
        
        buffer.writeln("(Path ${i} - ${path.length} points)");
        
        // First point of this path
        final startPoint = path[0];
        
        if (lastEndPoint == null || i == 0) {
          // First path or after a skipped path - move to position and plunge
          buffer.writeln("G0 X${startPoint.x.toStringAsFixed(4)} Y${startPoint.y.toStringAsFixed(4)}");
          
          if (i == 0) {
            // First path of depth pass
            buffer.writeln("G1 Z0 F${plungeRate.toStringAsFixed(1)}");  // Move to surface level first
            buffer.writeln("Z${depthString} F${plungeRate.toStringAsFixed(1)}");  // Plunge to current depth
          } else {
            // Subsequent path but no previous valid end point
            buffer.writeln("G1 Z${depthString} F${plungeRate.toStringAsFixed(1)}");
          }
        } else {
          // Connect to the start of this path with a direct line move
          buffer.writeln("G1 X${startPoint.x.toStringAsFixed(4)} Y${startPoint.y.toStringAsFixed(4)} F${feedRate.toStringAsFixed(1)}");
        }
        
        // Cut along the path
        for (int j = 1; j < path.length; j++) {
          final point = path[j];
          buffer.writeln("G1 X${point.x.toStringAsFixed(4)} Y${point.y.toStringAsFixed(4)} F${feedRate.toStringAsFixed(1)}");
        }
        
        // Remember the last point of this path
        lastEndPoint = path.last;
      }
      
      // At the end of each depth pass (except the last), move to safety height
      if (depthPass < depthPasses) {
        buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(4)}");
      }
    }
  }
  
  /// Write G-code footer with end program commands
  void _writeFooter(StringBuffer buffer) {
    buffer.writeln("");
    buffer.writeln("(End operation)");
    buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(4)}"); // Retract to safe height
    
    // Optionally return to home position
    if (returnToHome) {
      buffer.writeln("G0 X0 Y0"); // Return to home position
    }
    
    buffer.writeln("M5"); // Spindle off
    buffer.writeln("M30"); // End program
  }


  /// Legacy methods for backward compatibility

  /// Generate G-code from a toolpath
  String generateGcode(List<CoordinatePointXY> toolpath) {
    final buffer = StringBuffer();
    
    _writeHeader(buffer);
    _writeToolpath(buffer, toolpath);
    _writeFooter(buffer);
    
    return buffer.toString();
  }

  /// Write toolpath movements (legacy method)
  void _writeToolpath(StringBuffer buffer, List<CoordinatePointXY> toolpath) {
    if (toolpath.isEmpty) {
      buffer.writeln("(Warning: Empty toolpath)");
      return;
    }
    
    // First point: rapid move to position
    final startPoint = toolpath.first;
    buffer.writeln("G0 X${startPoint.x.toStringAsFixed(4)} Y${startPoint.y.toStringAsFixed(4)}"); // Rapid to start position
    
    // Plunge to cutting depth
    buffer.writeln("G1 Z0 F${plungeRate.toStringAsFixed(1)}"); // Go to surface
    buffer.writeln("G1 Z${(-cuttingDepth).toStringAsFixed(4)} F${plungeRate.toStringAsFixed(1)}"); // Plunge to cutting depth
    
    // Process remaining points with feed moves
    for (int i = 1; i < toolpath.length; i++) {
      final point = toolpath[i];
      buffer.writeln("G1 X${point.x.toStringAsFixed(4)} Y${point.y.toStringAsFixed(4)} F${feedRate.toStringAsFixed(1)}");
    }
  }

  /// Generate G-code for a contour following operation (legacy method)
  String generateContourGcode(List<CoordinatePointXY> contour) {
    final buffer = StringBuffer();
    
    _writeHeader(buffer);
    
    // First follow the contour completely at cutting depth
    if (contour.isNotEmpty) {
      // Move to first point
      final startPoint = contour.first;
      buffer.writeln("G0 X${startPoint.x.toStringAsFixed(4)} Y${startPoint.y.toStringAsFixed(4)}"); // Rapid to contour start
      
      // Plunge to cutting depth
      buffer.writeln("G1 Z0 F${plungeRate.toStringAsFixed(1)}"); // Go to surface
      buffer.writeln("G1 Z${(-cuttingDepth).toStringAsFixed(4)} F${plungeRate.toStringAsFixed(1)}"); // Plunge to cutting depth
      
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