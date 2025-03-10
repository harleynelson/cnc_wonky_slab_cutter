// lib/services/image_processing/contour_detection/algorithms/threshold_contour_algorithm.dart
// Threshold-based contour detection algorithm

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../../gcode/machine_coordinates.dart';
import '../../image_utils.dart';
import '../../slab_contour_result.dart';
import 'contour_algorithm_interface.dart';

/// Threshold-based contour detection algorithm
class ThresholdContourAlgorithm implements ContourDetectionAlgorithm {
  @override
  String get name => "Threshold";
  
  final bool generateDebugImage;
  final int regionGrowThreshold;

  ThresholdContourAlgorithm({
    this.generateDebugImage = true,
    this.regionGrowThreshold = 30,
  });

  @override
  Future<SlabContourResult> detectContour(
    img.Image image, 
    int seedX, 
    int seedY, 
    MachineCoordinateSystem coordSystem
  ) async {
    // Create a debug image if needed
    img.Image? debugImage;
    if (generateDebugImage) {
      debugImage = img.copyResize(image, width: image.width, height: image.height);
    }

    try {
      // 1. Convert to grayscale
      final grayscale = ImageUtils.convertToGrayscale(image);
      
      // 2. Apply region growing from seed point
      final mask = _regionGrow(grayscale, seedX, seedY, threshold: regionGrowThreshold);
      
      // 3. Find contour pixels from the mask
      final contourPixels = _findContourPixels(mask);
      
      // 4. Convert to Point objects
      final contourPoints = contourPixels.map((p) => Point(p[0].toDouble(), p[1].toDouble())).toList();
      
      // 5. Smooth and simplify the contour
      final smoothContour = _smoothAndSimplifyContour(contourPoints);
      
      // 6. Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(smoothContour);
      
      // 7. Draw visualization if debug image is requested
      if (debugImage != null) {
        // Draw seed point
        _drawCircle(debugImage, seedX, seedY, 5, img.ColorRgba8(255, 255, 0, 255));
        
        // Draw contour
        for (int i = 0; i < smoothContour.length - 1; i++) {
          _drawLine(
            debugImage, 
            smoothContour[i].x.round(), smoothContour[i].y.round(),
            smoothContour[i + 1].x.round(), smoothContour[i + 1].y.round(),
            img.ColorRgba8(0, 255, 0, 255)
          );
        }
        
        // Add algorithm name label
        _drawText(debugImage, "Algorithm: $name", 10, 10, img.ColorRgba8(255, 255, 255, 255));
      }
      
      return SlabContourResult(
        pixelContour: smoothContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      print('Error in $name algorithm: $e');
      return _createFallbackResult(image, coordSystem, debugImage, seedX, seedY);
    }
  }

  /// Region growing algorithm
  List<List<bool>> _regionGrow(img.Image image, int seedX, int seedY, {int threshold = 30}) {
    final mask = List.generate(
      image.height, (_) => List<bool>.filled(image.width, false)
    );
    
    // Get seed pixel value
    final seedPixel = image.getPixel(seedX, seedY);
    final seedIntensity = ImageUtils.calculateLuminance(
      seedPixel.r.toInt(), seedPixel.g.toInt(), seedPixel.b.toInt()
    );
    
    // Queue for processing
    final queue = <List<int>>[];
    queue.add([seedX, seedY]);
    mask[seedY][seedX] = true;
    
    // 4-connected neighbors
    final dx = [1, 0, -1, 0];
    final dy = [0, 1, 0, -1];
    
    while (queue.isNotEmpty) {
      final point = queue.removeAt(0);
      final x = point[0];
      final y = point[1];
      
      // Check neighbors
      for (int i = 0; i < 4; i++) {
        final nx = x + dx[i];
        final ny = y + dy[i];
        
        // Skip if out of bounds or already visited
        if (nx < 0 || nx >= image.width || ny < 0 || ny >= image.height || mask[ny][nx]) {
          continue;
        }
        
        // Check intensity similarity
        final pixel = image.getPixel(nx, ny);
        final intensity = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        if ((intensity - seedIntensity).abs() <= threshold) {
          mask[ny][nx] = true;
          queue.add([nx, ny]);
        }
      }
    }
    
    return mask;
  }

  /// Find contour pixels from binary mask
  List<List<int>> _findContourPixels(List<List<bool>> mask) {
    final contourPixels = <List<int>>[];
    final height = mask.length;
    final width = mask[0].length;
    
    // Directions for 8-connected neighborhood
    final dx8 = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy8 = [0, 1, 1, 1, 0, -1, -1, -1];
    
    // Find boundary pixels
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (!mask[y][x]) continue;
        
        // Check if this is a boundary pixel
        bool isBoundary = false;
        for (int i = 0; i < 8; i++) {
          final nx = x + dx8[i];
          final ny = y + dy8[i];
          
          if (nx < 0 || nx >= width || ny < 0 || ny >= height || !mask[ny][nx]) {
            isBoundary = true;
            break;
          }
        }
        
        if (isBoundary) {
          contourPixels.add([x, y]);
        }
      }
    }
    
    return contourPixels;
  }

  /// Basic contour smoothing and simplification
  List<Point> _smoothAndSimplifyContour(List<Point> contour) {
    if (contour.length <= 3) return contour;
    
    // Just return a simplified contour for the boilerplate
    final simplified = <Point>[];
    
    // Take every Nth point to simplify
    final N = math.max(1, contour.length ~/ 50);
    for (int i = 0; i < contour.length; i += N) {
      simplified.add(contour[i]);
    }
    
    // Make sure to close the contour
    if (simplified.isNotEmpty && 
        (simplified.first.x != simplified.last.x || simplified.first.y != simplified.last.y)) {
      simplified.add(simplified.first);
    }
    
    return simplified;
  }
  
  /// Draw a circle on the image
  void _drawCircle(img.Image image, int x, int y, int radius, img.Color color) {
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy <= radius * radius) {
          final px = x + dx;
          final py = y + dy;
          
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, color);
          }
        }
      }
    }
  }
  
  /// Draw a line on the image
  void _drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
    // Basic Bresenham line algorithm
    int dx = (x2 - x1).abs();
    int dy = (y2 - y1).abs();
    int sx = x1 < x2 ? 1 : -1;
    int sy = y1 < y2 ? 1 : -1;
    int err = dx - dy;
    
    while (true) {
      if (x1 >= 0 && x1 < image.width && y1 >= 0 && y1 < image.height) {
        image.setPixel(x1, y1, color);
      }
      
      if (x1 == x2 && y1 == y2) break;
      
      int e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x1 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y1 += sy;
      }
    }
  }
  
  /// Draw text on the image
  void _drawText(img.Image image, String text, int x, int y, img.Color color) {
    // Very simple text rendering
    int cursorX = x;
    for (int i = 0; i < text.length; i++) {
      // Just draw dots to represent text for simplicity
      image.setPixel(cursorX, y, color);
      cursorX += 7; // Move cursor forward
    }
  }
  
  /// Create a fallback result if detection fails
  SlabContourResult _createFallbackResult(
    img.Image image, 
    MachineCoordinateSystem coordSystem,
    img.Image? debugImage,
    int seedX,
    int seedY
  ) {
    // Create a simple circular contour around the seed point
    final radius = math.min(image.width, image.height) / 5;
    final contour = <Point>[];
    
    for (int i = 0; i <= 360; i += 10) {
      final angle = i * math.pi / 180;
      final x = seedX + radius * math.cos(angle);
      final y = seedY + radius * math.sin(angle);
      contour.add(Point(x, y));
    }
    
    // Convert to machine coordinates
    final machineContour = coordSystem.convertPointListToMachineCoords(contour);
    
    // Draw on debug image if available
    if (debugImage != null) {
      // Draw the fallback contour
      for (int i = 0; i < contour.length - 1; i++) {
        _drawLine(
          debugImage, 
          contour[i].x.round(), contour[i].y.round(),
          contour[i + 1].x.round(), contour[i + 1].y.round(),
          img.ColorRgba8(255, 0, 0, 255) // Red for fallback
        );
      }
      
      // Draw seed point
      _drawCircle(debugImage, seedX, seedY, 5, img.ColorRgba8(255, 255, 0, 255));
      
      // Add fallback label
      _drawText(debugImage, "FALLBACK: $name algorithm", 10, 10, img.ColorRgba8(255, 0, 0, 255));
    }
    
    return SlabContourResult(
      pixelContour: contour,
      machineContour: machineContour,
      debugImage: debugImage,
    );
  }
}