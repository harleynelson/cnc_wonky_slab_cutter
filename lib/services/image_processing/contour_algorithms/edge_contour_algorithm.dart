// lib/services/image_processing/contour_algorithms/edge_contour_algorithm.dart
// Edge-based contour detection algorithm with improved consistency

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../gcode/machine_coordinates.dart';
import '../../../utils/image_processing/contour_detection_utils.dart';
import '../../../utils/image_processing/filter_utils.dart';
import '../../../utils/image_processing/drawing_utils.dart';
import '../../../utils/image_processing/base_image_utils.dart';
import '../../../utils/image_processing/geometry_utils.dart';
import '../slab_contour_result.dart';
import 'contour_algorithm_interface.dart';

/// Edge-based contour detection algorithm with improved consistency
class EdgeContourAlgorithm implements ContourDetectionAlgorithm {
  @override
  String get name => "Edge";
  
  final bool generateDebugImage;
  final double edgeThreshold;
  final bool useConvexHull;
  final double simplificationEpsilon;

  EdgeContourAlgorithm({
    this.generateDebugImage = true,
    this.edgeThreshold = 50,
    this.useConvexHull = true,
    this.simplificationEpsilon = 5.0,
  });

  @override
  Future<SlabContourResult> detectContour(
    img.Image image, 
    int seedX, 
    int seedY, 
    MachineCoordinateSystem coordSystem
  ) async {
    // Create a fresh copy of the image to avoid state persistence issues
    img.Image workingImage = img.copyResize(image, width: image.width, height: image.height);
    
    // Create a debug image if needed
    img.Image? debugImage;
    if (generateDebugImage) {
      debugImage = img.copyResize(image, width: image.width, height: image.height);
    }

    try {
      // 1. Apply Gaussian blur to reduce noise with fixed parameters
      final blurred = FilterUtils.applyGaussianBlur(workingImage, 3);
      
      // 2. Apply edge detection with fixed threshold
      final edges = FilterUtils.applyEdgeDetection(blurred, threshold: edgeThreshold.toInt());
      
      // 3. Create binary mask from edge detection result
      final mask = _createMaskFromEdges(edges, seedX, seedY);
      
      // 4. Extract contour points from mask
      List<Point> contourPoints = ContourDetectionUtils.findOuterContour(mask);
      
      // 5. If we don't have enough points, try with lower threshold
      if (contourPoints.length < 20) {
        final edgesLow = FilterUtils.applyEdgeDetection(blurred, threshold: (edgeThreshold * 0.6).toInt());
        final maskLow = _createMaskFromEdges(edgesLow, seedX, seedY);
        contourPoints = ContourDetectionUtils.findOuterContour(maskLow);
      }
      
      // 6. Apply convex hull if specified
      List<Point> processedContour = contourPoints;
      if (useConvexHull && contourPoints.length >= 10) {
        processedContour = GeometryUtils.convexHull(contourPoints);
      }
      
      // 7. Simplify and smooth contour
      final smoothContour = ContourDetectionUtils.smoothAndSimplifyContour(
        processedContour, 
        simplificationEpsilon
      );
      
      // 8. Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(smoothContour);
      
      // 9. Draw visualization if debug image is requested
      if (debugImage != null) {
        // Create high contrast visualization
        _createHighContrastDebugImage(debugImage, edges);
        
        // Draw seed point
        DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
        
        // Draw contour
        DrawingUtils.drawContour(debugImage, smoothContour, img.ColorRgba8(0, 255, 0, 255), thickness: 3);
        
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
    
    // Maximum number of pixels to process
    final maxPixels = edges.width * edges.height / 4;
    int processedPixels = 0;
    
    while (queue.isNotEmpty && processedPixels < maxPixels) {
      final point = queue.removeAt(0);
      final x = point[0];
      final y = point[1];
      processedPixels++;
      
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
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        // If pixel is bright (not an edge), add to mask
        if (intensity > 128) {
          mask[ny][nx] = true;
          queue.add([nx, ny]);
        }
      }
    }
    
    // If we didn't grow enough, use a simpler distance-based approach
    if (processedPixels < 100) {
      final radius = math.min(edges.width, edges.height) / 6;
      for (int y = 0; y < edges.height; y++) {
        for (int x = 0; x < edges.width; x++) {
          final dx = x - seedX;
          final dy = y - seedY;
          final distance = math.sqrt(dx * dx + dy * dy);
          
          if (distance <= radius) {
            mask[y][x] = true;
          }
        }
      }
    }
    
    return mask;
  }
  
  /// Create a high-contrast visualization focusing on edge boundaries
  void _createHighContrastDebugImage(img.Image image, img.Image edges) {
    // Overlay edges on original image with high contrast
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final originalPixel = image.getPixel(x, y);
        final edgePixel = edges.getPixel(x, y);
        
        final intensity = BaseImageUtils.calculateLuminance(
          edgePixel.r.toInt(), edgePixel.g.toInt(), edgePixel.b.toInt()
        );
        
        // Keep bright edges but darken other areas
        if (intensity < 100) {
          // Edge pixel - make it white
          image.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        } else {
          // Non-edge pixel - darken original
          final r = (originalPixel.r.toInt() * 0.5).round().clamp(0, 255);
          final g = (originalPixel.g.toInt() * 0.5).round().clamp(0, 255);
          final b = (originalPixel.b.toInt() * 0.5).round().clamp(0, 255);
          image.setPixel(x, y, img.ColorRgba8(r, g, b, originalPixel.a.toInt()));
        }
      }
    }
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
      // Apply high contrast effect
      final edges = FilterUtils.applyEdgeDetection(image, threshold: 30);
      _createHighContrastDebugImage(debugImage, edges);
      
      // Draw the fallback contour
      DrawingUtils.drawContour(debugImage, contour, img.ColorRgba8(255, 0, 0, 255), thickness: 3);
      
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