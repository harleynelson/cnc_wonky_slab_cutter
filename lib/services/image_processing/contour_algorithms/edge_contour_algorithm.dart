// lib/services/image_processing/contour_algorithms/edge_contour_algorithm.dart
// Edge-based contour detection algorithm with improved consistency and visualization

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../../utils/general/machine_coordinates.dart';
import '../../../utils/image_processing/contour_detection_utils.dart';
import '../../../utils/image_processing/filter_utils.dart';
import '../../../utils/image_processing/drawing_utils.dart';
import '../../../utils/image_processing/base_image_utils.dart';
import '../../../utils/image_processing/geometry_utils.dart';
import '../../../utils/image_processing/threshold_utils.dart';
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
  final int smoothingWindowSize;
  final bool enhanceContrast;
  final int blurRadius;
  final bool removeNoise;

  EdgeContourAlgorithm({
    this.generateDebugImage = true,
    this.edgeThreshold = 50,
    this.useConvexHull = true,
    this.simplificationEpsilon = 5.0,
    this.smoothingWindowSize = 5,
    this.enhanceContrast = true,
    this.blurRadius = 3,
    this.removeNoise = true,
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
        simplificationEpsilon,
        windowSize: smoothingWindowSize
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
  
  /// Enhanced contrast function that performs adaptive contrast enhancement
  img.Image _enhanceContrastAdaptive(img.Image grayscale) {
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Find min and max pixel values
    int min = 255;
    int max = 0;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        min = math.min(min, intensity);
        max = math.max(max, intensity);
      }
    }
    
    // Calculate histogram to find optimal stretching parameters
    final histogram = List<int>.filled(256, 0);
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        histogram[intensity]++;
      }
    }
    
    // Find better min/max using histogram percentiles (5% and 95%)
    int pixelCount = 0;
    final totalPixels = grayscale.width * grayscale.height;
    final lowPercentile = totalPixels * 0.05;
    final highPercentile = totalPixels * 0.95;
    
    int minThreshold = min;
    for (int i = min; i <= max; i++) {
      pixelCount += histogram[i];
      if (pixelCount > lowPercentile) {
        minThreshold = i;
        break;
      }
    }
    
    pixelCount = 0;
    int maxThreshold = max;
    for (int i = max; i >= min; i--) {
      pixelCount += histogram[i];
      if (pixelCount > lowPercentile) {
        maxThreshold = i;
        break;
      }
    }
    
    // Ensure we have a meaningful range
    if (maxThreshold - minThreshold < 10) {
      minThreshold = min;
      maxThreshold = max;
    }
    
    // Apply enhanced contrast
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        int newIntensity;
        if (intensity < minThreshold) {
          newIntensity = 0;
        } else if (intensity > maxThreshold) {
          newIntensity = 255;
        } else {
          newIntensity = ((intensity - minThreshold) * 255 / (maxThreshold - minThreshold)).round().clamp(0, 255);
        }
        
        result.setPixel(x, y, img.ColorRgba8(newIntensity, newIntensity, newIntensity, 255));
      }
    }
    
    return result;
  }
  
  /// Remove small noise blobs from edge image
  img.Image _removeNoiseBlobs(img.Image edges, int minSize) {
    final result = img.Image(width: edges.width, height: edges.height);
    
    // Initialize with white
    for (int y = 0; y < edges.height; y++) {
      for (int x = 0; x < edges.width; x++) {
        result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
      }
    }
    
    // Find connected components
    final blobs = ContourDetectionUtils.findConnectedComponents(edges, minSize: minSize, maxSize: 10000);
    
    // Draw only the significant blobs
    for (final blob in blobs) {
      for (int i = 0; i < blob.length; i += 2) {
        if (i + 1 < blob.length) {
          final x = blob[i] as int;
          final y = blob[i + 1] as int;
          if (x >= 0 && x < result.width && y >= 0 && y < result.height) {
            result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
          }
        }
      }
    }
    
    return result;
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
    // Create a rectangular or circular contour around the seed point
    final List<Point> contour = [];
    
    // Determine size based on image dimensions, centered around seed point
    final width = image.width;
    final height = image.height;
    
    final size = math.min(width, height) * 0.3;
    final left = math.max(seedX - size / 2, 0.0);
    final right = math.min(seedX + size / 2, width.toDouble());
    final top = math.max(seedY - size / 2, 0.0);
    final bottom = math.min(seedY + size / 2, height.toDouble());
    
    // Create a rounded rectangle as fallback shape
    final cornerRadius = size / 5;
    
    // Top edge with rounded corners
    for (double x = left + cornerRadius; x <= right - cornerRadius; x += 5) {
      contour.add(Point(x, top));
    }
    
    // Top-right corner
    for (double angle = 270; angle <= 360; angle += 10) {
      final rads = angle * math.pi / 180;
      final x = right - cornerRadius + cornerRadius * math.cos(rads);
      final y = top + cornerRadius + cornerRadius * math.sin(rads);
      contour.add(Point(x, y));
    }
    
    // Right edge
    for (double y = top + cornerRadius; y <= bottom - cornerRadius; y += 5) {
      contour.add(Point(right, y));
    }
    
    // Bottom-right corner
    for (double angle = 0; angle <= 90; angle += 10) {
      final rads = angle * math.pi / 180;
      final x = right - cornerRadius + cornerRadius * math.cos(rads);
      final y = bottom - cornerRadius + cornerRadius * math.sin(rads);
      contour.add(Point(x, y));
    }
    
    // Bottom edge
    for (double x = right - cornerRadius; x >= left + cornerRadius; x -= 5) {
      contour.add(Point(x, bottom));
    }
    
    // Bottom-left corner
    for (double angle = 90; angle <= 180; angle += 10) {
      final rads = angle * math.pi / 180;
      final x = left + cornerRadius + cornerRadius * math.cos(rads);
      final y = bottom - cornerRadius + cornerRadius * math.sin(rads);
      contour.add(Point(x, y));
    }
    
    // Left edge
    for (double y = bottom - cornerRadius; y >= top + cornerRadius; y -= 5) {
      contour.add(Point(left, y));
    }
    
    // Top-left corner
    for (double angle = 180; angle <= 270; angle += 10) {
      final rads = angle * math.pi / 180;
      final x = left + cornerRadius + cornerRadius * math.cos(rads);
      final y = top + cornerRadius + cornerRadius * math.sin(rads);
      contour.add(Point(x, y));
    }
    
    // Close the contour
    contour.add(contour.first);
    
    // Convert to machine coordinates
    final machineContour = coordSystem.convertPointListToMachineCoords(contour);
    
    // Draw on debug image if available
    if (debugImage != null) {
      // Draw the fallback contour
      DrawingUtils.drawContour(debugImage, contour, img.ColorRgba8(255, 0, 0, 255), thickness: 3);
      
      // Draw seed point
      DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
      
      // Add fallback label
      DrawingUtils.drawText(debugImage, "FALLBACK: $name algorithm", 10, 10, img.ColorRgba8(255, 0, 0, 255));
      DrawingUtils.drawText(debugImage, "No contour detected - using fallback shape", 10, 30, img.ColorRgba8(255, 0, 0, 255));
    }
    
    return SlabContourResult(
      pixelContour: contour,
      machineContour: machineContour,
      debugImage: debugImage,
    );
  }
}