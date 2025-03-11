// lib/services/image_processing/contour_detection/algorithms/color_contour_algorithm.dart
// Color-based contour detection algorithm

import 'dart:async';
import 'dart:math' as math;
import 'package:cnc_wonky_slab_cutter/services/image_processing/image_processing_utils/contour_detection_utils.dart';
import 'package:image/image.dart' as img;

import '../../../gcode/machine_coordinates.dart';
import '../../image_processing_utils/color_utils.dart';
import '../../image_processing_utils/drawing_utils.dart';
import '../../image_processing_utils/geometry_utils.dart';
import '../../image_processing_utils/threshold_utils.dart';
import '../../slab_contour_result.dart';
import 'contour_algorithm_interface.dart';

/// Color-based contour detection algorithm that analyzes color distribution
class ColorContourAlgorithm implements ContourDetectionAlgorithm {
  @override
  String get name => "Color";
  
  final bool generateDebugImage;
  final double colorThreshold;

  ColorContourAlgorithm({
    this.generateDebugImage = true,
    this.colorThreshold = 30.0,
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
      // 1. Get the seed pixel color
      final seedPixel = image.getPixel(seedX, seedY);
      final seedColor = {
        'r': seedPixel.r.toInt(),
        'g': seedPixel.g.toInt(),
        'b': seedPixel.b.toInt()
      };
      
      // 2. Convert to HSV color space for better color comparison
      final seedHsv = ColorUtils.rgbToHsv(seedColor['r']!, seedColor['g']!, seedColor['b']!);
      
      // 3. Create binary mask using color-based region growing
      final mask = _colorBasedRegionGrowing(image, seedX, seedY, seedHsv);
      
      // 4. Apply morphological closing to fill gaps
      final closedMask = _applyMorphologicalClosing(mask);
      
      // 5. Find contour points
      final contourPoints = ContourDetectionUtils.findOuterContour(closedMask);
      
      // 6. Simplify and smooth contour
      final smoothedContour = ContourDetectionUtils.smoothAndSimplifyContour(contourPoints, 3.0);
      
      // 7. Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(smoothedContour);
      
      // 8. Draw visualization if debug image is requested
      if (debugImage != null) {
        // Draw seed point
        DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
        
        // Draw contour
        DrawingUtils.drawContour(debugImage, smoothedContour, img.ColorRgba8(0, 255, 0, 255), thickness: 2);
        
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
        pixelContour: smoothedContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
      
    } catch (e) {
      print('Error in $name algorithm: $e');
      return _createFallbackResult(image, coordSystem, debugImage, seedX, seedY);
    }
  }
  
  /// Region growing based on color similarity in HSV space
  List<List<bool>> _colorBasedRegionGrowing(
    img.Image image, 
    int seedX, 
    int seedY, 
    Map<String, double> seedHsv
  ) {
    final mask = List.generate(
      image.height, 
      (_) => List<bool>.filled(image.width, false)
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
        // Weight hue more than saturation or value
        double hueDiff = _getHueDifference(seedHsv['h']!, pixelHsv['h']!);
        double satDiff = (seedHsv['s']! - pixelHsv['s']!).abs();
        double valDiff = (seedHsv['v']! - pixelHsv['v']!).abs();
        
        // Combined color difference with weights
        double colorDiff = (hueDiff * 0.5) + (satDiff * 0.3) + (valDiff * 0.2);
        
        // If color is similar enough, add to region
        if (colorDiff < colorThreshold / 100.0) {
          mask[ny][nx] = true;
          queue.add([nx, ny]);
        }
      }
    }
    
    return mask;
  }
  
  /// Calculate the smallest angular difference between two hues
  double _getHueDifference(double hue1, double hue2) {
    double diff = (hue1 - hue2).abs();
    return diff > 180 ? 360 - diff : diff;
  }
  
  /// Apply morphological closing to fill gaps
  List<List<bool>> _applyMorphologicalClosing(List<List<bool>> mask) {
    // First apply dilation
    final dilated = _applyDilation(mask, 3);
    
    // Then apply erosion
    return _applyErosion(dilated, 3);
  }
  
  /// Apply dilation morphological operation
  List<List<bool>> _applyDilation(List<List<bool>> mask, int kernelSize) {
    final height = mask.length;
    final width = mask[0].length;
    final result = List.generate(height, (_) => List<bool>.filled(width, false));
    
    final halfKernel = kernelSize ~/ 2;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Check kernel neighborhood
        bool shouldDilate = false;
        
        for (int ky = -halfKernel; ky <= halfKernel && !shouldDilate; ky++) {
          for (int kx = -halfKernel; kx <= halfKernel && !shouldDilate; kx++) {
            final ny = y + ky;
            final nx = x + kx;
            
            if (nx >= 0 && nx < width && ny >= 0 && ny < height && mask[ny][nx]) {
              shouldDilate = true;
            }
          }
        }
        
        result[y][x] = shouldDilate;
      }
    }
    
    return result;
  }
  
  /// Apply erosion morphological operation
  List<List<bool>> _applyErosion(List<List<bool>> mask, int kernelSize) {
    final height = mask.length;
    final width = mask[0].length;
    final result = List.generate(height, (_) => List<bool>.filled(width, false));
    
    final halfKernel = kernelSize ~/ 2;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Assume should erode
        bool shouldErode = true;
        
        // Check if all pixels in kernel are true
        for (int ky = -halfKernel; ky <= halfKernel && shouldErode; ky++) {
          for (int kx = -halfKernel; kx <= halfKernel && shouldErode; kx++) {
            final ny = y + ky;
            final nx = x + kx;
            
            if (nx < 0 || nx >= width || ny < 0 || ny >= height || !mask[ny][nx]) {
              shouldErode = false;
            }
          }
        }
        
        result[y][x] = shouldErode;
      }
    }
    
    return result;
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