// lib/services/image_processing/slab_contour_detector.dart
// Detector responsible for finding slab contours in images

import 'dart:async';
import 'package:image/image.dart' as img;

import '../../utils/image_processing/drawing_utils.dart';
import '../gcode/machine_coordinates.dart';
import 'slab_contour_result.dart';
import '../../utils/image_processing/contour_detection_utils.dart';
import '../../utils/image_processing/filter_utils.dart';
import '../../utils/image_processing/image_utils.dart';
import '../../utils/image_processing/threshold_utils.dart';
import '../../utils/image_processing/geometry_utils.dart';

/// Detector for finding slab outlines in images
class SlabContourDetector {
  final bool generateDebugImage;
  final int maxImageSize;
  final int processingTimeout;
  
  SlabContourDetector({
    this.generateDebugImage = true,
    this.maxImageSize = 1200,
    this.processingTimeout = 10000,
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
    // Downsample large images if needed
    img.Image processImage = image;
    if (image.width > maxImageSize || image.height > maxImageSize) {
      processImage = ImageUtils.safeResize(image, maxSize: maxImageSize);
    }
    
    // Create a debug image if needed
    img.Image? debugImage;
    if (generateDebugImage) {
      debugImage = img.copyResize(processImage, width: processImage.width, height: processImage.height);
    }
    
    try {
      // Try each detection strategy in order of preference
      
      // STRATEGY 1: Advanced preprocessing with adaptive thresholding
      SlabContourResult? result = _tryAdvancedContourDetection(processImage, coordSystem, debugImage);
      if (_isValidResult(result)) {
        return result!;
      }
      
      // STRATEGY 2: Multi-threshold approach
      result = _tryMultiThresholdDetection(processImage, coordSystem, debugImage);
      if (_isValidResult(result)) {
        return result!;
      }
      
      // STRATEGY 3: Convex hull detection
      result = _tryConvexHullDetection(processImage, coordSystem, debugImage);
      if (_isValidResult(result)) {
        return result!;
      }
      
      // Fallback: Generate a basic shape
      return _createFallbackResult(processImage, coordSystem, debugImage);
      
    } catch (e) {
      print('Error in contour detection: $e');
      // Fallback to a generated contour
      return _createFallbackResult(processImage, coordSystem, debugImage);
    }
  }
  
  bool _isValidResult(SlabContourResult? result) {
    return result != null && result.isValid && result.pointCount >= 10;
  }
  
  /// Strategy 1: Advanced preprocessing with adaptive thresholding
  SlabContourResult? _tryAdvancedContourDetection(
    img.Image image,
    MachineCoordinateSystem coordSystem,
    img.Image? debugImage
  ) {
    try {
      // 1. Convert to grayscale
      final grayscale = ImageUtils.convertToGrayscale(image);
      
      // 2. Apply contrast enhancement
      final enhanced = ImageUtils.enhanceContrast(grayscale);
      
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
  
  /// Strategy 2: Multi-threshold approach
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
        final contourPoints = ContourDetectionUtils.findLargestContour(processed);
        
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
  
  /// Strategy 3: Convex hull detection
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
    final pixelContour = ContourDetectionUtils.createFallbackContour(image.width, image.height);
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
  
  /// Visualize contour on debug image
  void _visualizeContourOnDebug(img.Image debugImage, List<Point> contour, img.Color color, String label) {
    try {
      // Draw contour
      for (int i = 0; i < contour.length - 1; i++) {
        final p1 = contour[i];
        final p2 = contour[i + 1];
        
        DrawingUtils.drawLine(
          debugImage,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          color
        );
      }
      
      // Draw label
      if (contour.isNotEmpty) {
        DrawingUtils.drawText(
          debugImage,
          label,
          contour[0].x.round() + 10,
          contour[0].y.round() + 10,
          color
        );
      }
      
      // Draw points
      for (final point in contour) {
        DrawingUtils.drawCircle(
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
}