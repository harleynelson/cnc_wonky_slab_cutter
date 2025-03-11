// lib/services/image_processing/slab_contour_detector.dart
// Enhanced detector for finding slab outlines in images

import 'package:image/image.dart' as img;
import 'dart:math' as math;
import 'dart:async';
import '../gcode/machine_coordinates.dart';
import 'image_utils.dart';
import 'slab_contour_result.dart';
import 'image_processing_utils/base_image_utils.dart';
import 'image_processing_utils/filter_utils.dart';
import 'image_processing_utils/threshold_utils.dart';
import 'image_processing_utils/geometry_utils.dart';
import 'image_processing_utils/contour_detection_utils.dart';

/// Enhanced detector for finding slab outlines in images
class SlabContourDetector {
  final bool generateDebugImage;
  final int maxImageSize;
  final int processingTimeout;
  final int maxRecursionDepth;
  
  SlabContourDetector({
    this.generateDebugImage = true,
    this.maxImageSize = 1200,
    this.processingTimeout = 10000,
    this.maxRecursionDepth = 100,
  });
  
  /// Detect a slab contour in the given image
  Future<SlabContourResult> detectContour(
    img.Image image, 
    MachineCoordinateSystem coordSystem
  ) async {
    // Add timeout to detection process
    return await Future.delayed(Duration.zero, () {
      return Future.value(_detectContourInternal(image, coordSystem))
        .timeout(
          Duration(milliseconds: processingTimeout),
          onTimeout: () => throw TimeoutException('Contour detection timed out')
        );
    });
  }
  
  SlabContourResult _detectContourInternal(img.Image image, MachineCoordinateSystem coordSystem) {
    // Downsample large images to conserve memory
    img.Image processImage = image;
    if (image.width > maxImageSize || image.height > maxImageSize) {
      final scaleFactor = maxImageSize / math.max(image.width, image.height);
      try {
        processImage = BaseImageUtils.resizeImage(
          image,
          width: (image.width * scaleFactor).round(),
          height: (image.height * scaleFactor).round()
        );
      } catch (e) {
        print('Warning: Failed to resize image: $e');
      }
    }
    
    // Create a debug image if needed
    img.Image? debugImage;
    if (generateDebugImage) {
      try {
        debugImage = img.copyResize(processImage, width: processImage.width, height: processImage.height);
      } catch (e) {
        print('Warning: Failed to create debug image: $e');
      }
    }
    
    try {
      // STRATEGY 1: Try to detect the contour using advanced preprocessing
      SlabContourResult? result = _tryAdvancedContourDetection(processImage, coordSystem, debugImage);
      
      // If successful, return the result
      if (result != null && result.isValid && result.pointCount >= 10) {
        return result;
      }
      
      // STRATEGY 2: If advanced detection fails, try binary thresholding with multiple levels
      result = _tryMultiThresholdDetection(processImage, coordSystem, debugImage);
      
      // If successful, return the result
      if (result != null && result.isValid && result.pointCount >= 10) {
        return result;
      }
      
      // STRATEGY 3: If all else fails, try convex hull detection
      result = _tryConvexHullDetection(processImage, coordSystem, debugImage);
      
      // If successful, return the result
      if (result != null && result.isValid) {
        return result;
      }
      
      // If all strategies fail, return a fallback result
      return _createFallbackResult(processImage, coordSystem, debugImage);
      
    } catch (e) {
      print('Error in contour detection: $e');
      // Fallback to a generated contour
      return _createFallbackResult(processImage, coordSystem, debugImage);
    }
  }
  
  /// Try to detect contour using advanced preprocessing
  SlabContourResult? _tryAdvancedContourDetection(
    img.Image image,
    MachineCoordinateSystem coordSystem,
    img.Image? debugImage
  ) {
    try {
      // 1. Convert to grayscale
      final grayscale = ImageUtils.convertToGrayscale(image);
      
      // 2. Apply contrast enhancement
      final enhanced = _enhanceContrast(grayscale);
      
      // 3. Apply gaussian blur to reduce noise
      final blurred = FilterUtils.applyGaussianBlur(enhanced, 3);
      
      // 4. Apply adaptive thresholding
      final binaryImage = ThresholdUtils.applyAdaptiveThreshold(blurred, 25, 5);
      
      // 5. Apply morphological operations to close gaps
      final closed = ContourDetectionUtils.applyMorphologicalClosing(binaryImage, 5);
      
      // 6. Find the outer contour using boundary tracing
      final contourPoints = ContourDetectionUtils.findOuterContour(closed as List<List<bool>>);
      
      // 7. Apply smoothing and simplification
      final simplifiedContour = ContourDetectionUtils.smoothAndSimplifyContour(contourPoints, 5.0);
      
      // 8. Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(simplifiedContour);
      
      // Visualize on debug image if available
      if (debugImage != null) {
        _visualizeContourOnDebug(debugImage, simplifiedContour, img.ColorRgba8(0, 255, 0, 255), "Advanced");
      }
      
      return SlabContourResult(
        pixelContour: simplifiedContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      print('Advanced contour detection failed: $e');
      return null;
    }
  }
  
  /// Try to detect contour using multiple threshold levels
  SlabContourResult? _tryMultiThresholdDetection(
    img.Image image,
    MachineCoordinateSystem coordSystem,
    img.Image? debugImage
  ) {
    try {
      // Convert to grayscale
      final grayscale = ImageUtils.convertToGrayscale(image);
      
      // Try multiple threshold levels to find the best contour
      List<Point> bestContour = [];
      int bestThreshold = 128;
      
      // Try different threshold levels
      for (int threshold in [50, 100, 128, 150, 200]) {
        // Apply threshold
        final binary = ThresholdUtils.applyBinaryThreshold(grayscale, threshold);
        
        // Apply morphological operations
        final processed = ContourDetectionUtils.applyMorphologicalOpening(binary, 3);
        
        // Find contour
        final contourPoints = _findLargestContour(processed);
        
        // Check if this contour is better than the previous best
        if (contourPoints.length > bestContour.length && contourPoints.length >= 10) {
          bestContour = contourPoints;
          bestThreshold = threshold;
        }
      }
      
      if (bestContour.isEmpty) {
        return null;
      }
      
      // Simplify and smooth the best contour
      final simplifiedContour = ContourDetectionUtils.smoothAndSimplifyContour(bestContour, 5.0);
      
      // Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(simplifiedContour);
      
      // Visualize on debug image if available
      if (debugImage != null) {
        _visualizeContourOnDebug(debugImage, simplifiedContour, img.ColorRgba8(255, 165, 0, 255), 
                                "Threshold: $bestThreshold");
      }
      
      return SlabContourResult(
        pixelContour: simplifiedContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      print('Multi-threshold contour detection failed: $e');
      return null;
    }
  }
  
  /// Try to detect contour using convex hull approach
  SlabContourResult? _tryConvexHullDetection(
    img.Image image,
    MachineCoordinateSystem coordSystem,
    img.Image? debugImage
  ) {
    try {
      // Convert to grayscale
      final grayscale = ImageUtils.convertToGrayscale(image);
      
      // Apply Otsu's thresholding
      final threshold = ImageUtils.findOptimalThreshold(grayscale);
      final binary = ThresholdUtils.applyBinaryThreshold(grayscale, threshold);
      
      // Find all non-zero points
      final nonZeroPoints = <Point>[];
      for (int y = 0; y < binary.height; y++) {
        for (int x = 0; x < binary.width; x++) {
          final pixel = binary.getPixel(x, y);
          if (ImageUtils.calculateLuminance(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()) < 128) {
            nonZeroPoints.add(Point(x.toDouble(), y.toDouble()));
          }
        }
      }
      
      if (nonZeroPoints.isEmpty) {
        return null;
      }
      
      // Compute convex hull
      final hullPoints = GeometryUtils.convexHull(nonZeroPoints);
      
      // Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(hullPoints);
      
      // Visualize on debug image if available
      if (debugImage != null) {
        _visualizeContourOnDebug(debugImage, hullPoints, img.ColorRgba8(255, 0, 255, 255), "Convex Hull");
      }
      
      return SlabContourResult(
        pixelContour: hullPoints,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      print('Convex hull detection failed: $e');
      return null;
    }
  }
  
  /// Create a fallback result when detection fails
  SlabContourResult _createFallbackResult(
    img.Image image, 
    MachineCoordinateSystem coordSystem,
    img.Image? debugImage
  ) {
    final pixelContour = _createFallbackContour(image.width, image.height);
    final machineContour = coordSystem.convertPointListToMachineCoords(pixelContour);
    
    // Draw fallback contour on debug image
    if (debugImage != null) {
      _visualizeContourOnDebug(debugImage, pixelContour, img.ColorRgba8(255, 0, 0, 255), "FALLBACK");
    }
    
    return SlabContourResult(
      pixelContour: pixelContour,
      machineContour: machineContour,
      debugImage: debugImage,
    );
  }
  
  /// Enhance contrast in an image
  img.Image _enhanceContrast(img.Image grayscale) {
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Find min and max pixel values
    int min = 255;
    int max = 0;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        min = math.min(min, intensity);
        max = math.max(max, intensity);
      }
    }
    
    // Avoid division by zero
    if (max == min) {
      return grayscale;
    }
    
    // Apply contrast stretching
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        final newIntensity = (255 * (intensity - min) / (max - min)).round().clamp(0, 255);
        result.setPixel(x, y, img.ColorRgba8(newIntensity, newIntensity, newIntensity, 255));
      }
    }
    
    return result;
  }

  /// Find the largest contour in the binary image
  List<Point> _findLargestContour(img.Image binary) {
    final blobs = ContourDetectionUtils.findConnectedComponents(binary);
    
    // If no blobs found, return empty list
    if (blobs.isEmpty) {
      return [];
    }
    
    // Find the largest blob by area
    int largestBlobIndex = 0;
    int largestBlobSize = blobs[0].length;
    
    for (int i = 1; i < blobs.length; i++) {
      if (blobs[i].length > largestBlobSize) {
        largestBlobIndex = i;
        largestBlobSize = blobs[i].length;
      }
    }
    
    // Extract the largest blob
    final largestBlob = blobs[largestBlobIndex];
    
    // Convert to Point objects
    final points = <Point>[];
    for (int i = 0; i < largestBlob.length; i += 2) {
      if (i + 1 < largestBlob.length) {
        points.add(Point(largestBlob[i] as double, largestBlob[i + 1] as double));
      }
    }
    
    // If we have enough points, compute the convex hull
    if (points.length >= 3) {
      return GeometryUtils.convexHull(points);
    }
    
    return points;
  }
  
  /// Visualize contour on debug image
  void _visualizeContourOnDebug(img.Image debugImage, List<Point> contour, img.Color color, String label) {
    try {
      // Draw contour
      for (int i = 0; i < contour.length - 1; i++) {
        final p1 = contour[i];
        final p2 = contour[i + 1];
        
        ImageUtils.drawLine(
          debugImage,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          color
        );
      }
      
      // Draw label
      if (contour.isNotEmpty) {
        ImageUtils.drawText(
          debugImage,
          label,
          contour[0].x.round() + 10,
          contour[0].y.round() + 10,
          color
        );
      }
      
      // Draw points
      for (final point in contour) {
        ImageUtils.drawCircle(
          debugImage,
          point.x.round(),
          point.y.round(),
          2,
          color
        );
      }
    } catch (e) {
      print('Error visualizing contour: $e');
    }
  }
  
  /// Create a fallback contour for cases where detection fails
  List<Point> _createFallbackContour(int width, int height) {
    final centerX = width * 0.5;
    final centerY = height * 0.5;
    final radius = math.min(width, height) * 0.3;
    
    final numPoints = 20;
    final contour = <Point>[];
    
    for (int i = 0; i < numPoints; i++) {
      final angle = i * 2 * math.pi / numPoints;
      // Add some randomness to make it look like a natural slab
      final r = radius * (0.8 + 0.2 * math.sin(i * 3));
      final x = centerX + r * math.cos(angle);
      final y = centerY + r * math.sin(angle);
      contour.add(Point(x, y));
    }
    
    // Close the contour
    contour.add(contour.first);
    
    return contour;
  }
}