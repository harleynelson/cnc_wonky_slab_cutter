// lib/services/image_processing/slab_contour_result.dart
// Result model for slab contour detection with enhanced area measurements

import 'dart:math' as math;

import 'package:image/image.dart' as img;
import '../utils/general/machine_coordinates.dart';

/// Result of slab contour detection
class SlabContourResult {
  /// Contour in image pixel coordinates
  final List<CoordinatePointXY> pixelContour;
  
  /// Contour in machine (mm) coordinates
  final List<CoordinatePointXY> machineContour;
  
  /// Optional debug image with visualizations
  final img.Image? debugImage;
  
  /// Area in pixels squared (optional)
  final double pixelArea;
  
  /// Area in millimeters squared (optional)
  final double machineArea;
  
  SlabContourResult({
    required this.pixelContour,
    required this.machineContour,
    this.debugImage,
    this.pixelArea = 0.0,
    this.machineArea = 0.0,
  });
  
  /// Check if the contour is valid
  bool get isValid => pixelContour.length >= 10;
  
  /// Get number of points in the contour
  int get pointCount => pixelContour.length;
  
  /// Calculate perimeter of the contour in millimeters
  double get machinePerimeter {
    if (machineContour.length < 2) return 0.0;
    
    double perimeter = 0.0;
    for (int i = 0; i < machineContour.length - 1; i++) {
      final p1 = machineContour[i];
      final p2 = machineContour[i + 1];
      
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      perimeter += Math.sqrt(dx * dx + dy * dy);
    }
    
    // Add last segment to close the loop if not already closed
    if (machineContour.first.x != machineContour.last.x || 
        machineContour.first.y != machineContour.last.y) {
      final p1 = machineContour.last;
      final p2 = machineContour.first;
      
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      perimeter += Math.sqrt(dx * dx + dy * dy);
    }
    
    return perimeter;
  }
  
  /// Calculate bounding box in machine coordinates
  Map<String, double> get boundingBox {
    if (machineContour.isEmpty) {
      return {
        'minX': 0.0,
        'minY': 0.0, 
        'maxX': 0.0, 
        'maxY': 0.0,
        'width': 0.0,
        'height': 0.0,
      };
    }
    
    double minX = machineContour.first.x;
    double minY = machineContour.first.y;
    double maxX = machineContour.first.x;
    double maxY = machineContour.first.y;
    
    for (final point in machineContour) {
      minX = Math.min(minX, point.x);
      minY = Math.min(minY, point.y);
      maxX = Math.max(maxX, point.x);
      maxY = Math.max(maxY, point.y);
    }
    
    return {
      'minX': minX,
      'minY': minY,
      'maxX': maxX,
      'maxY': maxY,
      'width': maxX - minX,
      'height': maxY - minY,
    };
  }
}

/// Helper class to avoid importing dart:math directly
class Math {
  static double min(double a, double b) => a < b ? a : b;
  static double max(double a, double b) => a > b ? a : b;
  static double sqrt(double x) => math.sqrt(x);
}