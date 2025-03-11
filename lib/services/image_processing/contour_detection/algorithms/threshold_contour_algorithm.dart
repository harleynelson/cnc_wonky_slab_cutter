// lib/services/image_processing/contour_detection/algorithms/threshold_contour_algorithm.dart
// Threshold-based contour detection algorithm

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../../gcode/machine_coordinates.dart';
import '../../image_processing_utils/threshold_utils.dart';
import '../../image_processing_utils/drawing_utils.dart';
import '../../image_processing_utils/contour_utils.dart';
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
      // 1. Find optimal threshold automatically
      final threshold = ThresholdUtils.findOptimalThreshold(image);
      
      // 2. Apply binary thresholding
      final binaryImage = ThresholdUtils.applyThreshold(image, threshold);
      
      // 3. Apply region growing from seed point
      final List<List<bool>> mask = _applyRegionGrowing(
        binaryImage, 
        seedX, 
        seedY, 
        threshold: regionGrowThreshold
      );
      
      // 4. Find contour from the mask
      final List<Point> contourPoints = ContourUtils.findOuterContour(mask);
      
      // 5. Smooth and simplify the contour
      final List<Point> smoothContour = ContourUtils.smoothAndSimplifyContour(
        contourPoints,
        5.0 // epsilon for simplification
      );
      
      // 6. Convert to machine coordinates
      final List<Point> machineContour = coordSystem.convertPointListToMachineCoords(smoothContour);
      
      // 7. Draw debug visualization if requested
      if (debugImage != null) {
        // Draw seed point
        DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
        
        // Draw contour
        DrawingUtils.drawContour(debugImage, smoothContour, img.ColorRgba8(0, 255, 0, 255), thickness: 2);
        
        // Add algorithm name label
        DrawingUtils.drawText(debugImage, "Algorithm: $name", 10, 10, img.ColorRgba8(255, 255, 255, 255));
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

  /// Apply region growing from seed point
  List<List<bool>> _applyRegionGrowing(img.Image image, int seedX, int seedY, {int threshold = 30}) {
    final List<List<bool>> mask = List.generate(
      image.height, (_) => List<bool>.filled(image.width, false)
    );
    
    // Get seed pixel value
    final seedPixel = image.getPixel(seedX, seedY);
    final seedIntensity = (seedPixel.r.toInt() + seedPixel.g.toInt() + seedPixel.b.toInt()) ~/ 3;
    
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
        final intensity = (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) ~/ 3;
        
        if ((intensity - seedIntensity).abs() <= threshold) {
          mask[ny][nx] = true;
          queue.add([nx, ny]);
        }
      }
    }
    
    return mask;
  }
  
  /// Create a fallback result when detection fails
  SlabContourResult _createFallbackResult(
    img.Image image, 
    MachineCoordinateSystem coordSystem,
    img.Image? debugImage,
    int seedX,
    int seedY
  ) {
    // Create a circular contour around the seed point
    final List<Point> contour = [];
    final radius = math.min(image.width, image.height) * 0.3;
    
    // Generate circular contour
    for (int i = 0; i <= 36; i++) {
      final angle = i * math.pi / 18; // 10 degrees in radians
      final x = seedX + radius * math.cos(angle);
      final y = seedY + radius * math.sin(angle);
      contour.add(Point(x, y));
    }
    
    // Convert to machine coordinates
    final machineContour = coordSystem.convertPointListToMachineCoords(contour);
    
    // Draw on debug image if available
    if (debugImage != null) {
      // Draw the fallback contour
      DrawingUtils.drawContour(debugImage, contour, img.ColorRgba8(255, 0, 0, 255));
      
      // Draw seed point
      DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
      
      // Add fallback label
      DrawingUtils.drawText(debugImage, "FALLBACK: $name algorithm", 10, 10, img.ColorRgba8(255, 0, 0, 255));
    }
    
    return SlabContourResult(
      pixelContour: contour,
      machineContour: machineContour,
      debugImage: debugImage,
    );
  }
}