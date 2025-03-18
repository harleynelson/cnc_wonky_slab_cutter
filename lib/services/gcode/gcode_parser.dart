// lib/services/gcode/gcode_parser.dart
// Parser for G-code files to extract toolpaths for visualization

import '../../utils/general/machine_coordinates.dart';
import 'dart:math' as math;

class GcodeParser {
  /// Parse G-code content into a list of toolpaths (points)
  /// Each toolpath represents a cutting layer or section
  List<List<Point>> parseGcode(String gcodeContent) {
  final List<List<Point>> toolpaths = [];
  final List<Point> traversePaths = []; // For rapid positioning moves
  List<Point> currentPath = [];
  
  // Split G-code into lines
  final lines = gcodeContent.split('\n');
  
  // Track current position and state
  double? currentX;
  double? currentY;
  double? currentZ;
  bool isRapid = false;
  bool inCuttingMove = false;
  
  // Process each line
  for (final line in lines) {
    final trimmedLine = line.trim();
    
    // Skip comments and empty lines
    if (trimmedLine.isEmpty || trimmedLine.startsWith('(') || trimmedLine.startsWith(';')) {
      // If we find a comment indicating a new depth pass, start a new toolpath
      if (trimmedLine.contains('Depth pass') || trimmedLine.contains('pass of')) {
        if (currentPath.isNotEmpty) {
          toolpaths.add(List.from(currentPath));
          currentPath = [];
        }
      }
      continue;
    }
    
    // Split the line into components
    final parts = trimmedLine.split(' ');
    
    // First component is usually the G-code command
    final command = parts.isNotEmpty ? parts[0] : '';
    
    // Process commands
    if (command == 'G0' || command == 'G00') {
      isRapid = true;
      
      // Get new coordinates
      final Map<String, double?> coords = _extractCoordinates(parts);
      
      // Update current position
      if (coords['X'] != null) currentX = coords['X']!;
      if (coords['Y'] != null) currentY = coords['Y']!;
      if (coords['Z'] != null) currentZ = coords['Z']!;
      
      // Add to traverse path if X/Y movement
      if ((coords['X'] != null || coords['Y'] != null) && 
          currentX != null && currentY != null && 
          currentZ != null && currentZ >= 0) { // Only above the surface
        traversePaths.add(Point(currentX, currentY));
      }
    } else if (command == 'G1' || command == 'G01') {
      isRapid = false;
      
      // Get new coordinates
      final Map<String, double?> coords = _extractCoordinates(parts);
      
      // If Z coordinate changes to cutting depth, we're entering a cutting move
      if (coords['Z'] != null && coords['Z']! <= 0) {
        inCuttingMove = true;
      }
      
      // Update current position
      if (coords['X'] != null) currentX = coords['X']!;
      if (coords['Y'] != null) currentY = coords['Y']!;
      if (coords['Z'] != null) currentZ = coords['Z']!;
      
      // Add the point to our path if we have X and Y
      if (currentX != null && currentY != null) {
        if (inCuttingMove) {
          currentPath.add(Point(currentX, currentY));
        } else {
          // This is a non-cutting move (e.g., positioning)
          traversePaths.add(Point(currentX, currentY));
        }
      }
    }
    // [Processing for G2/G3 arc commands would go here]
  }
  
  // Add the last toolpath if not empty
  if (currentPath.isNotEmpty) {
    toolpaths.add(currentPath);
  }
  
  // Add traverse paths as the first path with a special flag
  if (traversePaths.isNotEmpty) {
    toolpaths.insert(0, traversePaths);
  }
  
  return toolpaths;
}
  
  /// Extract X, Y, Z, I, J coordinates from parts
  Map<String, double?> _extractCoordinates(List<String> parts) {
    double? x, y, z, i, j;
    
    for (final part in parts) {
      if (part.startsWith('X')) {
        x = double.tryParse(part.substring(1));
      } else if (part.startsWith('Y')) {
        y = double.tryParse(part.substring(1));
      } else if (part.startsWith('Z')) {
        z = double.tryParse(part.substring(1));
      } else if (part.startsWith('I')) {
        i = double.tryParse(part.substring(1));
      } else if (part.startsWith('J')) {
        j = double.tryParse(part.substring(1));
      }
    }
    
    return {'X': x, 'Y': y, 'Z': z, 'I': i, 'J': j};
  }
  
  /// Process coordinates and update current position
  void _processCoordinates(List<String> parts, double? currentX, double? currentY, double? currentZ) {
    final Map<String, double?> coords = _extractCoordinates(parts);
    
    if (coords['X'] != null) currentX = coords['X']!;
    if (coords['Y'] != null) currentY = coords['Y']!;
    if (coords['Z'] != null) currentZ = coords['Z']!;
  }
  
  /// Interpolate points along an arc
  void _interpolateArc(
    List<Point> path,
    double startX, double startY,
    double endX, double endY,
    double centerX, double centerY,
    double radius,
    double startAngle, double endAngle,
    bool clockwise,
    bool inCuttingMove
  ) {
    if (!inCuttingMove) return;
    
    // Ensure end angle is always greater than start angle for proper interpolation
    if (clockwise) {
      if (endAngle > startAngle) endAngle -= 2 * math.pi;
    } else {
      if (startAngle > endAngle) endAngle += 2 * math.pi;
    }
    
    // Calculate angle increment (higher resolution for larger arcs)
    final arcLength = radius * (clockwise ? startAngle - endAngle : endAngle - startAngle).abs();
    final steps = math.max(10, (arcLength / 5).round()); // One point per 5mm of arc length, minimum 10 points
    final angleIncrement = (endAngle - startAngle) / steps;
    
    // Add intermediate points
    for (int i = 0; i <= steps; i++) {
      final angle = startAngle + i * angleIncrement;
      final x = centerX + radius * math.cos(angle);
      final y = centerY + radius * math.sin(angle);
      path.add(Point(x, y));
    }
  }
}