import 'package:image/image.dart' as img;
import '../gcode/machine_coordinates.dart';

/// Result of slab contour detection
class SlabContourResult {
  /// Contour in image pixel coordinates
  final List<Point> pixelContour;
  
  /// Contour in machine (mm) coordinates
  final List<Point> machineContour;
  
  /// Optional debug image with visualizations
  final img.Image? debugImage;
  
  SlabContourResult({
    required this.pixelContour,
    required this.machineContour,
    this.debugImage,
  });
  
  /// Check if the contour is valid
  bool get isValid => pixelContour.length >= 10;
  
  /// Get number of points in the contour
  int get pointCount => pixelContour.length;
  
  /// Calculate approximate area of the contour in square pixels
  double get pixelArea {
    if (pixelContour.length < 3) return 0.0;
    
    double area = 0.0;
    for (int i = 0; i < pixelContour.length - 1; i++) {
      area += pixelContour[i].x * pixelContour[i + 1].y;
      area -= pixelContour[i + 1].x * pixelContour[i].y;
    }
    
    return area.abs() / 2.0;
  }
  
  /// Calculate approximate area of the contour in square mm
  double get machineArea {
    if (machineContour.length < 3) return 0.0;
    
    double area = 0.0;
    for (int i = 0; i < machineContour.length - 1; i++) {
      area += machineContour[i].x * machineContour[i + 1].y;
      area -= machineContour[i + 1].x * machineContour[i].y;
    }
    
    return area.abs() / 2.0;
  }
}