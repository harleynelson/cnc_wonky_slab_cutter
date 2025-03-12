// lib/services/image_processing/contour_algorithms/color_contour_algorithm.dart
// Color-based contour detection algorithm with improved consistency

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../gcode/machine_coordinates.dart';
import '../../../utils/image_processing/color_utils.dart';
import '../../../utils/image_processing/drawing_utils.dart';
import '../../../utils/image_processing/contour_detection_utils.dart';
import '../../../utils/image_processing/filter_utils.dart';
import '../../../utils/image_processing/base_image_utils.dart';
import '../../../utils/image_processing/geometry_utils.dart';
import '../slab_contour_result.dart';
import 'contour_algorithm_interface.dart';

/// Color-based contour detection algorithm with improved consistency
class ColorContourAlgorithm implements ContourDetectionAlgorithm {
  @override
  String get name => "Color";
  
  final bool generateDebugImage;
  final double colorThreshold;
  final bool useConvexHull;
  final double simplificationEpsilon;

  ColorContourAlgorithm({
    this.generateDebugImage = true,
    this.colorThreshold = 30.0,
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
      // 1. Get the seed pixel color
      final seedPixel = workingImage.getPixel(seedX, seedY);
      final seedColor = {
        'r': seedPixel.r.toInt(),
        'g': seedPixel.g.toInt(),
        'b': seedPixel.b.toInt()
      };
      
      // 2. Convert to HSV color space for better color comparison
      final seedHsv = ColorUtils.rgbToHsv(seedColor['r']!, seedColor['g']!, seedColor['b']!);
      
      // 3. Create binary mask using color-based region growing
      final mask = _colorBasedRegionGrowing(workingImage, seedX, seedY, seedHsv);
      
      // 4. Apply morphological closing to fill gaps
      final closedMask = ContourDetectionUtils.applyMorphologicalClosing(mask, 5);
      
      // 5. Find contour points
      List<Point> contourPoints = ContourDetectionUtils.findOuterContour(closedMask);
      
      // 6. If contour is too small, try with more permissive settings
      if (contourPoints.length < 20) {
        final largeMask = _colorBasedRegionGrowing(
          workingImage, 
          seedX, 
          seedY, 
          seedHsv,
          threshold: colorThreshold * 2.0
        );
        final processedMask = ContourDetectionUtils.applyMorphologicalClosing(largeMask, 7);
        contourPoints = ContourDetectionUtils.findOuterContour(processedMask);
      }
      
      // 7. Apply convex hull if specified
      List<Point> processedContour = contourPoints;
      if (useConvexHull && contourPoints.length >= 10) {
        processedContour = GeometryUtils.convexHull(contourPoints);
      }
      
      // 8. Simplify and smooth contour
      final smoothContour = ContourDetectionUtils.smoothAndSimplifyContour(
        processedContour,
        simplificationEpsilon
      );
      
      // 9. Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(smoothContour);
      
      // 10. Create visualization if debug image is requested
      if (debugImage != null) {
        // Create high contrast visualization
        _createHighContrastDebugImage(debugImage, workingImage, seedX, seedY, seedHsv);
        
        // Draw seed point
        DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
        
        // Draw contour
        DrawingUtils.drawContour(debugImage, smoothContour, img.ColorRgba8(0, 255, 0, 255), thickness: 3);
        
        // Add algorithm name label
        DrawingUtils.drawText(debugImage, "Algorithm: $name", 10, 10, img.ColorRgba8(255, 255, 255, 255));
        
        // Show seed color info
        DrawingUtils.drawText(
          debugImage, 
          "Seed HSV: H=${seedHsv['h']!.toStringAsFixed(1)}° S=${(seedHsv['s']! * 100).toStringAsFixed(1)}% V=${(seedHsv['v']! * 100).toStringAsFixed(1)}%", 
          10, 
          30, 
          img.ColorRgba8(255, 255, 255, 255)
        );
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
  
  /// Color-based region growing with improved stability
  List<List<bool>> _colorBasedRegionGrowing(
    img.Image image,
    int seedX,
    int seedY,
    Map<String, double> seedHsv,
    {double? threshold}
  ) {
    final actualThreshold = threshold ?? colorThreshold;
    
    final mask = List.generate(
      image.height, 
      (_) => List<bool>.filled(image.width, false)
    );
    
    // Queue for processing
    final queue = <List<int>>[];
    queue.add([seedX, seedY]);
    mask[seedY][seedX] = true;
    
    // 8-connected neighbors for better connectivity
    final dx = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy = [0, 1, 1, 1, 0, -1, -1, -1];
    
    // Maximum number of pixels to process
    final maxPixels = image.width * image.height / 4;
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
        
        // Get pixel color
        final pixel = image.getPixel(nx, ny);
        final pixelRgb = {
          'r': pixel.r.toInt(),
          'g': pixel.g.toInt(),
          'b': pixel.b.toInt()
        };
        
        // Convert to HSV
        final pixelHsv = ColorUtils.rgbToHsv(pixelRgb['r']!, pixelRgb['g']!, pixelRgb['b']!);
        
        // Calculate color difference in HSV space
        double hueDiff = ColorUtils.getHueDifference(seedHsv['h']!, pixelHsv['h']!);
        double satDiff = (seedHsv['s']! - pixelHsv['s']!).abs();
        double valDiff = (seedHsv['v']! - pixelHsv['v']!).abs();
        
        // Combined color difference with weights
        double colorDiff = (hueDiff / 360 * 50) + (satDiff * 30) + (valDiff * 20);
        
        // If color is similar enough, add to region
        if (colorDiff < actualThreshold) {
          mask[ny][nx] = true;
          queue.add([nx, ny]);
        }
      }
    }
    
    // If we didn't grow enough, use a simple distance-based approach
    if (processedPixels < 100) {
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
  
  /// Create a high-contrast debug image for better visualization
  void _createHighContrastDebugImage(
    img.Image debugImage, 
    img.Image originalImage,
    int seedX,
    int seedY,
    Map<String, double> seedHsv
  ) {
    // Apply edge detection to highlight boundaries
    final edges = FilterUtils.applyEdgeDetection(originalImage, threshold: 30);
    
    // Create a color similarity map relative to seed color
    for (int y = 0; y < debugImage.height; y++) {
      for (int x = 0; x < debugImage.width; x++) {
        final originalPixel = originalImage.getPixel(x, y);
        final edgePixel = edges.getPixel(x, y);
        
        // Check if this is an edge pixel
        final edgeIntensity = BaseImageUtils.calculateLuminance(
          edgePixel.r.toInt(), edgePixel.g.toInt(), edgePixel.b.toInt()
        );
        
        if (edgeIntensity < 100) {
          // Edge pixel - make it white
          debugImage.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
          continue;
        }
        
        // Calculate color similarity to seed
        final r = originalPixel.r.toInt();
        final g = originalPixel.g.toInt();
        final b = originalPixel.b.toInt();
        
        final pixelHsv = ColorUtils.rgbToHsv(r, g, b);
        double hueDiff = ColorUtils.getHueDifference(seedHsv['h']!, pixelHsv['h']!);
        double satDiff = (seedHsv['s']! - pixelHsv['s']!).abs();
        double valDiff = (seedHsv['v']! - pixelHsv['v']!).abs();
        
        // Combined color difference
        double colorDiff = (hueDiff / 360 * 50) + (satDiff * 30) + (valDiff * 20);
        
        // Highlight similar colors, darken different ones
        if (colorDiff < colorThreshold * 2) {
          // Similar color - make it brighter
          int brightness = 180 + ((colorThreshold * 2 - colorDiff) / (colorThreshold * 2) * 75).toInt();
          brightness = brightness.clamp(0, 255);
          debugImage.setPixel(x, y, img.ColorRgba8(brightness, brightness, brightness, 255));
        } else {
          // Different color - make it darker
          int brightness = (originalPixel.r.toInt() * 0.4).round().clamp(0, 255);
          debugImage.setPixel(x, y, img.ColorRgba8(brightness, brightness, brightness, 255));
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
      
      for (int y = 0; y < debugImage.height; y++) {
        for (int x = 0; x < debugImage.width; x++) {
          final edgePixel = edges.getPixel(x, y);
          final intensity = BaseImageUtils.calculateLuminance(
            edgePixel.r.toInt(), edgePixel.g.toInt(), edgePixel.b.toInt()
          );
          
          if (intensity < 100) {
            debugImage.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
          } else {
            final originalPixel = image.getPixel(x, y);
            final r = (originalPixel.r.toInt() * 0.5).round().clamp(0, 255);
            final g = (originalPixel.g.toInt() * 0.5).round().clamp(0, 255);
            final b = (originalPixel.b.toInt() * 0.5).round().clamp(0, 255);
            debugImage.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
          }
        }
      }
      
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