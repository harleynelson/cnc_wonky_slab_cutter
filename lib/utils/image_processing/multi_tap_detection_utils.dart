// lib/utils/image_processing/multi_tap_detection_utils.dart
// Utilities for multi-tap based detection to differentiate between similar colored materials

import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../general/machine_coordinates.dart';
import 'image_utils.dart';
import 'base_image_utils.dart';
import 'threshold_utils.dart';
import 'contour_detection_utils.dart';

/// Represents a region sample with position and color information
class RegionSample {
  final PointOfCoordinates position;
  final List<int> colorSample; // [r, g, b]
  final String label;
  
  RegionSample(this.position, this.colorSample, this.label);
  
  // Calculate color distance to another color
  double colorDistanceTo(List<int> otherColor) {
    double dr = (colorSample[0] - otherColor[0]) as double;
    double dg = (colorSample[1] - otherColor[1]) as double;
    double db = (colorSample[2] - otherColor[2]) as double;
    
    return math.sqrt(dr * dr + dg * dg + db * db);
  }
}

/// Utilities for multi-tap based contour detection
class MultiTapDetectionUtils {
  
  /// Detect contour using region samples for wood slabs on similar backgrounds
  static List<PointOfCoordinates> findContourWithRegionSamples(
    img.Image image,
    RegionSample slabSample,
    RegionSample spillboardSample,
    {
      int sampleRadius = 5,
      double colorThresholdMultiplier = 1.5,
      int minSlabSize = 1000,
      int seedX = -1,
      int seedY = -1,
    }
  ) {
    // Create enhanced difference map between regions
    final diffMap = _createEnhancedDifferenceMap(
      image, 
      slabSample, 
      spillboardSample, 
      colorThresholdMultiplier
    );
    
    // Get seed point if not provided
    if (seedX < 0 || seedY < 0) {
      seedX = slabSample.position.x.toInt();
      seedY = slabSample.position.y.toInt();
    }
    
    // Use standard contour detection on the enhanced difference map
    final contourPoints = ContourDetectionUtils.findContourByRayCasting(
      diffMap,
      seedX,
      seedY,
      minSlabSize: minSlabSize,
      gapAllowedMin: 5,
      gapAllowedMax: 20,
      continueSearchDistance: 30
    );
    
    // Apply standard post-processing
    final smoothedContour = ContourDetectionUtils.smoothAndSimplifyContour(
      contourPoints, 
      5.0, 
      windowSize: 7
    );
    
    return smoothedContour;
  }
  
  /// Create an enhanced difference map based on region samples
  static img.Image _createEnhancedDifferenceMap(
    img.Image image,
    RegionSample slabSample,
    RegionSample spillboardSample,
    double colorThresholdMultiplier
  ) {
    // Extract color samples from larger regions
    final slabColors = _extractRegionColors(image, slabSample.position, 5);
    final spillboardColors = _extractRegionColors(image, spillboardSample.position, 5);
    
    // Calculate average colors
    final slabAvgColor = _calculateAverageColor(slabColors);
    final spillboardAvgColor = _calculateAverageColor(spillboardColors);
    
    // Calculate color variances to understand the "spread" of colors in each region
    final slabVariance = _calculateColorVariance(slabColors, slabAvgColor);
    final spillboardVariance = _calculateColorVariance(spillboardColors, spillboardAvgColor);
    
    // Determine the color threshold from variances
    final colorDistanceThreshold = _calculateColorDistanceThreshold(
      slabAvgColor, 
      spillboardAvgColor, 
      slabVariance, 
      spillboardVariance, 
      colorThresholdMultiplier
    );
    
    // Create difference map
    final diffMap = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final pixelColor = [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
        
        // Calculate distances to both samples
        final distToSlab = _colorDistance(pixelColor, slabAvgColor);
        final distToSpillboard = _colorDistance(pixelColor, spillboardAvgColor);
        
        // Enhance contrast in the difference map
        if (distToSlab < distToSpillboard && distToSlab < colorDistanceThreshold) {
          // Likely part of the slab - mark as black (object)
          diffMap.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        } else {
          // Likely part of the spillboard - mark as white (background)
          diffMap.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        }
      }
    }
    
    // Apply additional processing to improve the difference map
    return _enhanceDifferenceMap(diffMap);
  }
  
  /// Extract color samples from a region around a point
  static List<List<int>> _extractRegionColors(img.Image image, PointOfCoordinates center, int radius) {
    final colors = <List<int>>[];
    final cx = center.x.toInt();
    final cy = center.y.toInt();
    
    for (int y = cy - radius; y <= cy + radius; y++) {
      for (int x = cx - radius; x <= cx + radius; x++) {
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          final pixel = image.getPixel(x, y);
          colors.add([pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()]);
        }
      }
    }
    
    return colors;
  }
  
  /// Calculate average color from a list of colors
  static List<int> _calculateAverageColor(List<List<int>> colors) {
    if (colors.isEmpty) return [0, 0, 0];
    
    int sumR = 0, sumG = 0, sumB = 0;
    
    for (final color in colors) {
      sumR += color[0];
      sumG += color[1];
      sumB += color[2];
    }
    
    return [
      (sumR / colors.length).round(),
      (sumG / colors.length).round(),
      (sumB / colors.length).round()
    ];
  }
  
  /// Calculate variance of colors from their average
  static double _calculateColorVariance(List<List<int>> colors, List<int> average) {
    if (colors.isEmpty) return 0.0;
    
    double sumSquaredDist = 0.0;
    
    for (final color in colors) {
      final dist = _colorDistance(color, average);
      sumSquaredDist += dist * dist;
    }
    
    return math.sqrt(sumSquaredDist / colors.length);
  }
  
  /// Calculate a suitable color distance threshold based on sample statistics
  static double _calculateColorDistanceThreshold(
    List<int> slabColor,
    List<int> spillboardColor,
    double slabVariance,
    double spillboardVariance,
    double multiplier
  ) {
    // Base threshold on distance between average colors
    final baseDist = _colorDistance(slabColor, spillboardColor);
    
    // Adjust threshold based on color variances
    final varianceAdjustment = (slabVariance + spillboardVariance) / 2;
    
    // Apply multiplier for tuning
    return (baseDist * 0.5 + varianceAdjustment) * multiplier;
  }
  
  /// Calculate color distance in RGB space
  static double _colorDistance(List<int> color1, List<int> color2) {
    final dr = color1[0] - color2[0];
    final dg = color1[1] - color2[1];
    final db = color1[2] - color2[2];
    
    return math.sqrt(dr * dr + dg * dg + db * db);
  }
  
  /// Enhance the difference map with morphological operations
  static img.Image _enhanceDifferenceMap(img.Image diffMap) {
    // Convert to binary mask for morphological operations
    final mask = ThresholdUtils.createBinaryMask(diffMap, 128);
    
    // Apply closing to fill small gaps
    final closed = ContourDetectionUtils.applyMorphologicalClosing(mask, 3);
    
    // Apply opening to remove small noise
    final opened = ContourDetectionUtils.applyMorphologicalOpening(closed, 2);
    
    // Convert back to image
    final result = img.Image(width: diffMap.width, height: diffMap.height);
    
    for (int y = 0; y < diffMap.height; y++) {
      for (int x = 0; x < diffMap.width; x++) {
        if (opened[y][x]) {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        } else {
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        }
      }
    }
    
    return result;
  }
  
  /// Create a visualization of the differences for debugging
  static img.Image createVisualization(
    img.Image original,
    RegionSample slabSample,
    RegionSample spillboardSample,
    List<PointOfCoordinates> contour
  ) {
    // Create a copy of the original image
    final visualization = img.copyResize(original, width: original.width, height: original.height);
    
    // Draw the contour
    for (int i = 0; i < contour.length - 1; i++) {
      final p1 = contour[i];
      final p2 = contour[i + 1];
      
      ImageUtils.drawLine(
        visualization,
        p1.x.round(), p1.y.round(),
        p2.x.round(), p2.y.round(),
        ImageUtils.colorGreen
      );
    }
    
    // Close the contour if needed
    if (contour.isNotEmpty && 
        (contour.first.x != contour.last.x || contour.first.y != contour.last.y)) {
      final p1 = contour.last;
      final p2 = contour.first;
      
      ImageUtils.drawLine(
        visualization,
        p1.x.round(), p1.y.round(),
        p2.x.round(), p2.y.round(),
        ImageUtils.colorGreen
      );
    }
    
    // Draw sample points
    ImageUtils.drawCircle(
      visualization,
      slabSample.position.x.round(),
      slabSample.position.y.round(),
      8,
      ImageUtils.colorRed,
      fill: true
    );
    
    ImageUtils.drawText(
      visualization,
      "Slab",
      slabSample.position.x.round() + 10,
      slabSample.position.y.round() - 10,
      ImageUtils.colorRed
    );
    
    ImageUtils.drawCircle(
      visualization,
      spillboardSample.position.x.round(),
      spillboardSample.position.y.round(),
      8,
      ImageUtils.colorBlue,
      fill: true
    );
    
    ImageUtils.drawText(
      visualization,
      "Spillboard",
      spillboardSample.position.x.round() + 10,
      spillboardSample.position.y.round() - 10,
      ImageUtils.colorBlue
    );
    
    return visualization;
  }
}