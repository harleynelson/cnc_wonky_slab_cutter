// lib/services/image_processing/contour_algorithms/color_contour_algorithm.dart
// Color-based contour detection algorithm

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../gcode/machine_coordinates.dart';
import '../../../utils/image_processing/color_utils.dart';
import '../../../utils/image_processing/drawing_utils.dart';
import '../../../utils/image_processing/contour_detection_utils.dart';
import '../slab_contour_result.dart';
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
      final mask = ColorUtils.colorBasedRegionGrowing(image, seedX, seedY, seedHsv, threshold: colorThreshold);
      
      // 4. Apply morphological closing to fill gaps
      final closedMask = ContourDetectionUtils.applyMorphologicalClosing(mask, 3);
      
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