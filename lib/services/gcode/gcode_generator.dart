import '../../utils/general/machine_coordinates.dart';
import 'dart:math' as math;

/// Class to generate G-code for CNC operations
class GcodeGenerator {
  final double safetyHeight;
  final double feedRate;
  final double plungeRate;
  final double cuttingDepth;

  GcodeGenerator({
    required this.safetyHeight,
    required this.feedRate,
    required this.plungeRate,
    this.cuttingDepth = 0.0,
  });

  /// Generate G-code from a toolpath
  String generateGcode(List<Point> toolpath) {
    final buffer = StringBuffer();
    
    _writeHeader(buffer);
    _writeToolpath(buffer, toolpath);
    _writeFooter(buffer);
    
    return buffer.toString();
  }

  /// Write G-code header with initialization commands
  void _writeHeader(StringBuffer buffer) {
    buffer.writeln("; G-code generated for CNC slab surfacing");
    buffer.writeln("; Generated by CNC Slab Scanner App");
    buffer.writeln("");
    buffer.writeln("G21 ; Set units to millimeters");
    buffer.writeln("G90 ; Set to absolute positioning");
    buffer.writeln("G94 ; Feed rate mode: units per minute");
    buffer.writeln("");
    buffer.writeln("; Begin operation");
    buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(3)} ; Move to safe height");
  }

  /// Write toolpath movements
  void _writeToolpath(StringBuffer buffer, List<Point> toolpath) {
    if (toolpath.isEmpty) {
      buffer.writeln("; Warning: Empty toolpath");
      return;
    }
    
    // First point: rapid move to position
    final startPoint = toolpath.first;
    buffer.writeln("G0 X${startPoint.x.toStringAsFixed(3)} Y${startPoint.y.toStringAsFixed(3)} ; Rapid to start position");
    
    // Plunge to cutting depth
    buffer.writeln("G1 Z${cuttingDepth.toStringAsFixed(3)} F${plungeRate.toStringAsFixed(1)} ; Plunge to cutting depth");
    
    // Process remaining points with feed moves
    for (int i = 1; i < toolpath.length; i++) {
      final point = toolpath[i];
      buffer.writeln("G1 X${point.x.toStringAsFixed(3)} Y${point.y.toStringAsFixed(3)} F${feedRate.toStringAsFixed(1)}");
    }
  }

  /// Write G-code footer with end program commands
  void _writeFooter(StringBuffer buffer) {
    buffer.writeln("");
    buffer.writeln("; End operation");
    buffer.writeln("G0 Z${safetyHeight.toStringAsFixed(3)} ; Retract to safe height");
    buffer.writeln("M5 ; Spindle off");
    buffer.writeln("M30 ; End program");
  }

  /// Generate G-code for a contour following operation
  String generateContourGcode(List<Point> contour) {
    final buffer = StringBuffer();
    
    _writeHeader(buffer);
    
    // First follow the contour completely at cutting depth
    if (contour.isNotEmpty) {
      // Move to first point
      final startPoint = contour.first;
      buffer.writeln("G0 X${startPoint.x.toStringAsFixed(3)} Y${startPoint.y.toStringAsFixed(3)} ; Rapid to contour start");
      
      // Plunge to cutting depth
      buffer.writeln("G1 Z${cuttingDepth.toStringAsFixed(3)} F${plungeRate.toStringAsFixed(1)} ; Plunge to cutting depth");
      
      // Follow the contour
      for (int i = 1; i < contour.length; i++) {
        final point = contour[i];
        buffer.writeln("G1 X${point.x.toStringAsFixed(3)} Y${point.y.toStringAsFixed(3)} F${feedRate.toStringAsFixed(1)}");
      }
      
      // Close the contour by returning to the first point
      buffer.writeln("G1 X${startPoint.x.toStringAsFixed(3)} Y${startPoint.y.toStringAsFixed(3)} F${feedRate.toStringAsFixed(1)} ; Close contour");
    }
    
    _writeFooter(buffer);
    
    return buffer.toString();
  }

  /// Generate G-code for a pocketing operation inside a contour
  String generatePocketingGcode(List<Point> contour, double toolDiameter, double stepover) {
    final toolpath = ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
    return generateGcode(toolpath);
  }
}

/// Helper class for generating different types of toolpaths
class ToolpathGenerator {
  /// Generate a zigzag toolpath to surface a rectangular area
  static List<Point> generateZigzagToolpath(
    double minX, double minY, double maxX, double maxY, 
    double stepover, bool startFromMin
  ) {
    final toolpath = <Point>[];
    
    double y = startFromMin ? minY : maxY;
    final yEnd = startFromMin ? maxY : minY;
    final yStep = startFromMin ? stepover : -stepover;
    bool goingRight = true;
    
    while (startFromMin ? y <= yEnd : y >= yEnd) {
      if (goingRight) {
        toolpath.add(Point(minX, y));
        toolpath.add(Point(maxX, y));
      } else {
        toolpath.add(Point(maxX, y));
        toolpath.add(Point(minX, y));
      }
      
      y += yStep;
      goingRight = !goingRight;
    }
    
    return toolpath;
  }
  
  /// Generate a toolpath to surface the area within a contour
  /// This is a simplified version - a real implementation would do more complex
  /// calculations to optimize the toolpath based on the contour shape
  static List<Point> generatePocketToolpath(
    List<Point> contour, double toolDiameter, double stepover
  ) {
    // Find bounding box of contour
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    
    for (final point in contour) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    
    // Inset by half tool diameter
    final inset = toolDiameter / 2;
    minX += inset;
    minY += inset;
    maxX -= inset;
    maxY -= inset;
    
    // Generate zigzag pattern within the bounds
    return generateZigzagToolpath(minX, minY, maxX, maxY, stepover, true);
  }
  
  /// Generate a contour-parallel toolpath (offset from the original contour)
  static List<Point> generateContourParallelToolpath(
    List<Point> contour, double toolDiameter, double stepover, int numPasses
  ) {
    // This would require a more complex implementation to offset the contour inward
    // For now, we'll return a simplified approach
    
    // Just use the contour itself as the toolpath
    return List<Point>.from(contour);
  }
}

