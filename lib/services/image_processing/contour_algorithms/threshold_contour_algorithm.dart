// lib/services/image_processing/contour_algorithms/threshold_contour_algorithm.dart
// Threshold-based contour detection algorithm that focuses on outer boundary only

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../../utils/image_processing/filter_utils.dart';
import '../../gcode/machine_coordinates.dart';
import '../../../utils/image_processing/contour_detection_utils.dart';
import '../../../utils/image_processing/threshold_utils.dart';
import '../../../utils/image_processing/drawing_utils.dart';
import '../../../utils/image_processing/base_image_utils.dart';
import '../../../utils/image_processing/geometry_utils.dart';
import '../slab_contour_result.dart';
import 'contour_algorithm_interface.dart';

/// Threshold-based contour detection algorithm with focus on outer boundary only
class ThresholdContourAlgorithm implements ContourDetectionAlgorithm {
  @override
  String get name => "Threshold";
  
  final bool generateDebugImage;
  final int regionGrowThreshold;
  final bool useConvexHull;
  final double simplificationEpsilon;
  final bool removeHoles;

  ThresholdContourAlgorithm({
    this.generateDebugImage = true,
    this.regionGrowThreshold = 30,
    this.useConvexHull = true,
    this.simplificationEpsilon = 5.0,
    this.removeHoles = true,
  });

  @override
  Future<SlabContourResult> detectContour(
    img.Image image, 
    int seedX, 
    int seedY, 
    MachineCoordinateSystem coordSystem
  ) async {
    // Create a fresh debug image to avoid any persistence issues
    // This ensures we're starting with a clean copy of the original image
    img.Image? debugImage;
    img.Image workingImage = img.copyResize(image, width: image.width, height: image.height);
    
    if (generateDebugImage) {
      debugImage = img.copyResize(image, width: image.width, height: image.height);
    }

    try {
      // Run edge enhancement to emphasize the boundaries
      workingImage = _enhanceEdges(workingImage);
      
      // 1. Apply binary thresholding to separate foreground from background
      // Use a consistent method rather than adaptive thresholding which might vary between runs
      final binaryImage = ThresholdUtils.applyThreshold(workingImage, 128);
      
      // 2. Apply region growing from seed point
      final List<List<bool>> regionMask = _applyRegionGrowing(
        workingImage,
        seedX, 
        seedY, 
        threshold: 40 // Fixed threshold for consistency
      );
      
      // 3. Fill holes in the mask to ensure a solid shape
      final filledMask = ContourDetectionUtils.applyMorphologicalClosing(regionMask, 5);
      
      // 4. Find contour from the mask
      final List<Point> contourPoints = ContourDetectionUtils.findOuterContour(filledMask);
      
      // 5. If the contour is too small, try edge-based detection
      List<Point> workingContour = contourPoints;
      if (contourPoints.length < 20) {
        // Try a more aggressive approach
        workingContour = _detectContourWithEdges(workingImage, seedX, seedY);
      }
      
      // 6. Apply convex hull if needed
      List<Point> hullContour = workingContour;
      if (useConvexHull && workingContour.length > 3) {
        hullContour = GeometryUtils.convexHull(workingContour);
      }
      
      // 7. Smooth and simplify the contour
      final List<Point> smoothContour = ContourDetectionUtils.smoothAndSimplifyContour(
        hullContour,
        simplificationEpsilon
      );
      
      // 8. Convert to machine coordinates
      final List<Point> machineContour = coordSystem.convertPointListToMachineCoords(smoothContour);
      
      // 9. Draw debug visualization if requested
      if (debugImage != null) {
        // First, create a high contrast version to make boundaries visible
        _createHighContrastDebugImage(debugImage);
        
        // Draw seed point
        DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
        
        // Draw final contour with high visibility
        DrawingUtils.drawContour(debugImage, smoothContour, img.ColorRgba8(0, 255, 0, 255), thickness: 3);
        
        // Add algorithm name label
        DrawingUtils.drawText(debugImage, "Algorithm: $name (Outline)", 10, 10, img.ColorRgba8(255, 255, 255, 255));
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

  /// Create a binary mask from an image
  List<List<bool>> _createBinaryMask(img.Image image) {
    final mask = List.generate(
      image.height, 
      (_) => List<bool>.filled(image.width, false)
    );
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        // Create binary mask where slab pixels are true
        mask[y][x] = intensity < 128;
      }
    }
    
    return mask;
  }

  /// Apply morphological operations to clean up the mask
  List<List<bool>> _applyMorphologicalOperations(List<List<bool>> mask) {
    // First apply closing to fill small holes
    final closed = ContourDetectionUtils.applyMorphologicalClosing(mask, 5);
    
    // Then apply opening to remove small noise
    return ContourDetectionUtils.applyMorphologicalOpening(closed, 3);
  }

  /// Enhanced region growing algorithm to better capture the slab
  List<List<bool>> _applyRegionGrowing(img.Image image, int seedX, int seedY, {int threshold = 30}) {
    final List<List<bool>> mask = List.generate(
      image.height, (_) => List<bool>.filled(image.width, false)
    );
    
    // Get seed pixel value
    final seedPixel = image.getPixel(seedX, seedY);
    final seedR = seedPixel.r.toInt();
    final seedG = seedPixel.g.toInt(); 
    final seedB = seedPixel.b.toInt();
    
    // Calculate both luminance and RGB components for better matching
    final seedIntensity = BaseImageUtils.calculateLuminance(seedR, seedG, seedB);
    
    // Queue for processing
    final queue = <List<int>>[];
    queue.add([seedX, seedY]);
    mask[seedY][seedX] = true;
    
    // 8-connected neighbors for better connectivity
    final dx = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy = [0, 1, 1, 1, 0, -1, -1, -1];
    
    // Maximum number of pixels to process to prevent excessive growth
    final maxPixels = image.width * image.height / 4; // Up to 1/4 of the image
    int processedPixels = 0;
    
    while (queue.isNotEmpty && processedPixels < maxPixels) {
      final point = queue.removeAt(0);
      final x = point[0];
      final y = point[1];
      processedPixels++;
      
      // Check neighbors
      for (int i = 0; i < 8; i++) {
        final nx = x + dx[i];
        final ny = y + dy[i];
        
        // Skip if out of bounds or already visited
        if (nx < 0 || nx >= image.width || ny < 0 || ny >= image.height || mask[ny][nx]) {
          continue;
        }
        
        // Check intensity and color similarity with multiple metrics
        final pixel = image.getPixel(nx, ny);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // Calculate intensity difference
        final intensity = BaseImageUtils.calculateLuminance(r, g, b);
        final intensityDiff = (intensity - seedIntensity).abs();
        
        // Calculate color difference using RGB distance
        final colorDiff = math.sqrt(
          math.pow(r - seedR, 2) + 
          math.pow(g - seedG, 2) + 
          math.pow(b - seedB, 2)
        );
        
        // Using an adaptive approach - either intensity OR color similarity can qualify a pixel
        if (intensityDiff <= threshold * 2 || colorDiff <= threshold * 3.5) {
          mask[ny][nx] = true;
          queue.add([nx, ny]);
        }
      }
    }
    
    // If we didn't grow enough, try a simple distance-from-seed approach
    if (processedPixels < 100) {
      // Mark pixels within a reasonable distance from seed
      final radius = math.min(image.width, image.height) / 6;
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
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

  /// Remove internal details from contour by using only the outermost points
  List<Point> _removeInternalDetails(List<Point> contour) {
    if (contour.length < 10) return contour;
    
    try {
      // Calculate bounding box
      final boundingBox = GeometryUtils.calculateBoundingBox(contour);
      double minX = boundingBox['minX']!;
      double minY = boundingBox['minY']!;
      double maxX = boundingBox['maxX']!;
      double maxY = boundingBox['maxY']!;
      
      // Create a set of angles and find the furthest point in each direction
      final int angleSteps = 72; // Every 5 degrees
      final outerPoints = <Point>[];
      
      // Find center of contour
      final center = GeometryUtils.polygonCentroid(contour);
      
      for (int i = 0; i < angleSteps; i++) {
        double angle = 2 * math.pi * i / angleSteps;
        double maxDistance = 0;
        Point? furthestPoint;
        
        // Find furthest point in this direction
        for (final point in contour) {
          final dx = point.x - center.x;
          final dy = point.y - center.y;
          final pointAngle = math.atan2(dy, dx);
          
          // Check if point is in current angle sector
          final angleDiff = (pointAngle - angle).abs();
          if (angleDiff < math.pi / angleSteps || angleDiff > 2 * math.pi - math.pi / angleSteps) {
            final distance = math.sqrt(dx * dx + dy * dy);
            if (distance > maxDistance) {
              maxDistance = distance;
              furthestPoint = point;
            }
          }
        }
        
        if (furthestPoint != null) {
          outerPoints.add(furthestPoint);
        }
      }
      
      // Add points to ensure we capture the extremes of the shape
      outerPoints.add(Point(minX, minY)); // Top-left
      outerPoints.add(Point(maxX, minY)); // Top-right
      outerPoints.add(Point(maxX, maxY)); // Bottom-right
      outerPoints.add(Point(minX, maxY)); // Bottom-left
      
      // Remove duplicates
      final uniquePoints = <Point>[];
      for (final point in outerPoints) {
        bool isDuplicate = false;
        for (final uniquePoint in uniquePoints) {
          if ((point.x - uniquePoint.x).abs() < 2 && (point.y - uniquePoint.y).abs() < 2) {
            isDuplicate = true;
            break;
          }
        }
        if (!isDuplicate) {
          uniquePoints.add(point);
        }
      }
      
      return uniquePoints;
    } catch (e) {
      print('Error removing internal details: $e');
      return contour;
    }
  }

  /// Create a high-contrast debug image that makes the boundaries visible
  void _createHighContrastDebugImage(img.Image image) {
    // First, create a copy with enhanced edges
    final edgeEnhanced = _enhanceEdges(image);
    
    // Apply the enhanced edges to the original image to make boundaries visible
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final originalPixel = image.getPixel(x, y);
        final enhancedPixel = edgeEnhanced.getPixel(x, y);
        
        // Keep bright edges but make dark areas darker
        final intensity = BaseImageUtils.calculateLuminance(
          enhancedPixel.r.toInt(), enhancedPixel.g.toInt(), enhancedPixel.b.toInt()
        );
        
        if (intensity > 200) {
          // Keep bright edges
          image.setPixel(x, y, enhancedPixel);
        } else {
          // Darken other areas slightly
          final r = (originalPixel.r.toInt() * 0.6).round();
          final g = (originalPixel.g.toInt() * 0.6).round();
          final b = (originalPixel.b.toInt() * 0.6).round();
          image.setPixel(x, y, img.ColorRgba8(r, g, b, originalPixel.a.toInt()));
        }
      }
    }
  }
  
  /// Enhance edges in an image
  img.Image _enhanceEdges(img.Image image) {
    // Make a copy of the image
    final result = img.copyResize(image, width: image.width, height: image.height);
    
    // Apply Sobel edge detection
    final edges = FilterUtils.applyEdgeDetection(image, threshold: 30);
    
    // Overlay the edges onto the original image
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final edgePixel = edges.getPixel(x, y);
        final edgeIntensity = BaseImageUtils.calculateLuminance(
          edgePixel.r.toInt(), edgePixel.g.toInt(), edgePixel.b.toInt()
        );
        
        // If this is an edge pixel
        if (edgeIntensity > 200) {
          // Make it white to highlight the edge
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        }
      }
    }
    
    return result;
  }
  
  /// Detect contour using edge-based approach - useful when region growing fails
  List<Point> _detectContourWithEdges(img.Image image, int seedX, int seedY) {
    // Detect edges in the image
    final edges = FilterUtils.applyEdgeDetection(image, threshold: 50);
    
    // Convert to binary mask
    final mask = List.generate(
      edges.height, 
      (y) => List.generate(edges.width, 
        (x) {
          final pixel = edges.getPixel(x, y);
          final intensity = BaseImageUtils.calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          return intensity > 128; // True for edge pixels
        }
      )
    );
    
    // Find the largest connected component that contains or is near the seed point
    final connectedComponents = _findConnectedComponents(mask);
    
    // Find component closest to seed
    int bestIndex = -1;
    double minDistance = double.infinity;
    
    for (int i = 0; i < connectedComponents.length; i++) {
      final component = connectedComponents[i];
      
      // Check if seed is inside or calculate minimum distance
      bool containsSeed = false;
      double minDist = double.infinity;
      
      for (int j = 0; j < component.length; j += 2) {
        final x = component[j];
        final y = component[j + 1];
        
        if (x == seedX && y == seedY) {
          containsSeed = true;
          break;
        }
        
        final dx = x - seedX;
        final dy = y - seedY;
        final dist = math.sqrt(dx * dx + dy * dy);
        minDist = math.min(minDist, dist);
      }
      
      if (containsSeed) {
        bestIndex = i;
        break;
      }
      
      if (minDist < minDistance) {
        minDistance = minDist;
        bestIndex = i;
      }
    }
    
    // Convert component to points
    List<Point> points = [];
    if (bestIndex >= 0) {
      final component = connectedComponents[bestIndex];
      for (int i = 0; i < component.length; i += 2) {
        if (i + 1 < component.length) {
          points.add(Point(component[i].toDouble(), component[i + 1].toDouble()));
        }
      }
    }
    
    // If we still don't have enough points, create a basic shape
    if (points.length < 10) {
      final radius = math.min(image.width, image.height) / 5;
      points = [];
      for (int i = 0; i < 36; i++) {
        final angle = i * math.pi / 18;
        points.add(Point(
          seedX + radius * math.cos(angle),
          seedY + radius * math.sin(angle)
        ));
      }
    }
    
    return points;
  }
  
  /// Find connected components in a binary mask
  List<List<int>> _findConnectedComponents(List<List<bool>> mask) {
    final components = <List<int>>[];
    final visited = List.generate(
      mask.length, 
      (y) => List.filled(mask[y].length, false)
    );
    
    for (int y = 0; y < mask.length; y++) {
      for (int x = 0; x < mask[y].length; x++) {
        if (!visited[y][x] && mask[y][x]) {
          final component = <int>[];
          _floodFill(mask, visited, x, y, component);
          
          if (component.length > 10) { // Filter tiny components
            components.add(component);
          }
        }
      }
    }
    
    // Sort by size (largest first)
    components.sort((a, b) => b.length.compareTo(a.length));
    return components;
  }
  
  /// Flood fill helper for connected components
  void _floodFill(List<List<bool>> mask, List<List<bool>> visited, int x, int y, List<int> component) {
    if (x < 0 || y < 0 || x >= mask[0].length || y >= mask.length || visited[y][x] || !mask[y][x]) {
      return;
    }
    
    visited[y][x] = true;
    component.add(x);
    component.add(y);
    
    // Check 4-connected neighbors
    _floodFill(mask, visited, x+1, y, component);
    _floodFill(mask, visited, x-1, y, component);
    _floodFill(mask, visited, x, y+1, component);
    _floodFill(mask, visited, x, y-1, component);
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
      // Create high contrast version
      _createHighContrastDebugImage(debugImage);
      
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