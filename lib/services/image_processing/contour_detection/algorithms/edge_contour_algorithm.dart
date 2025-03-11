// lib/services/image_processing/contour_detection/algorithms/edge_contour_algorithm.dart
// Edge-based contour detection algorithm

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../../gcode/machine_coordinates.dart';
import '../../image_processing_utils/filter_utils.dart';
import '../../image_processing_utils/drawing_utils.dart';
import '../../image_processing_utils/contour_utils.dart';
import '../../image_processing_utils/geometry_utils.dart';
import '../../slab_contour_result.dart';
import 'contour_algorithm_interface.dart';

/// Edge-based contour detection algorithm
class EdgeContourAlgorithm implements ContourDetectionAlgorithm {
  @override
  String get name => "Edge";
  
  final bool generateDebugImage;
  final double edgeThreshold;

  EdgeContourAlgorithm({
    this.generateDebugImage = true,
    this.edgeThreshold = 50,
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
      // 1. Apply Gaussian blur to reduce noise
      final blurred = FilterUtils.applyGaussianBlur(image, 3);
      
      // 2. Apply edge detection
      final edges = FilterUtils.applyEdgeDetection(blurred, threshold: edgeThreshold.toInt());
      
      // 3. Create binary mask from edge detection result
      final mask = _createMaskFromEdges(edges, seedX, seedY);
      
      // 4. Extract contour points from mask
      final List<Point> contourPoints = ContourUtils.findOuterContour(mask);
      
      // 5. Simplify and smooth contour
      List<Point> processedContour = contourPoints;
      
      if (contourPoints.length > 10) {
        // Apply Douglas-Peucker simplification
        processedContour = GeometryUtils.simplifyPolygon(contourPoints, 2.0);
        
        // Apply Gaussian smoothing
        processedContour = ContourUtils.smoothContour(processedContour, windowSize: 5);
      }
      
      // 6. Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(processedContour);
      
      // 7. Draw visualization if debug image is requested
      if (debugImage != null) {
        // Draw seed point
        DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
        
        // Draw contour
        DrawingUtils.drawContour(debugImage, processedContour, img.ColorRgba8(0, 255, 0, 255), thickness: 2);
        
        // Add algorithm name label
        DrawingUtils.drawText(debugImage, "Algorithm: $name", 10, 10, img.ColorRgba8(255, 255, 255, 255));
      }
      
      return SlabContourResult(
        pixelContour: processedContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      print('Error in $name algorithm: $e');
      return _createFallbackResult(image, coordSystem, debugImage, seedX, seedY);
    }
  }
  
  /// Create a binary mask from edge detection result using flood fill from seed
  List<List<bool>> _createMaskFromEdges(img.Image edges, int seedX, int seedY) {
    final mask = List.generate(
      edges.height, 
      (_) => List<bool>.filled(edges.width, false)
    );
    
    // Queue for flood fill
    final queue = <List<int>>[];
    queue.add([seedX, seedY]);
    mask[seedY][seedX] = true;
    
    // 4-connected directions
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
        if (nx < 0 || nx >= edges.width || ny < 0 || ny >= edges.height || mask[ny][nx]) {
          continue;
        }
        
        // Check if pixel is not an edge (edges are dark)
        final pixel = edges.getPixel(nx, ny);
        final intensity = (pixel.r.toInt() + pixel.g.toInt() + pixel.b.toInt()) ~/ 3;
        
        // If pixel is bright (not an edge), add to mask
        if (intensity > 128) {
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