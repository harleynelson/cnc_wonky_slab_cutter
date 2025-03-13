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
import '../../../utils/image_processing/image_utils.dart';
import '../slab_contour_result.dart';
import 'contour_algorithm_interface.dart';

/// Edge-based contour detection algorithm with improved consistency
class EdgeContourAlgorithm implements ContourDetectionAlgorithm {

  final int continueSearchDistance;

 @override
 String get name => "Edge";
 
 final bool generateDebugImage;
 final double edgeThreshold;
 final bool useConvexHull;
 final double simplificationEpsilon;
 final int smoothingWindowSize;
 final int blurRadius;
 final int minSlabSize;
 final int gapAllowedMin;
 final int gapAllowedMax;

 EdgeContourAlgorithm({
   this.generateDebugImage = true,
   this.edgeThreshold = 50.0,
   this.useConvexHull = true,
   this.simplificationEpsilon = 5.0,
   this.smoothingWindowSize = 5,
   this.blurRadius = 3,
   this.minSlabSize = 1000,
   this.gapAllowedMin = 5,
   this.gapAllowedMax = 20,
   this.continueSearchDistance = 30,
 });

 @override
 Future<SlabContourResult> detectContour(
   img.Image image, 
   int seedX, 
   int seedY, 
   MachineCoordinateSystem coordSystem
 ) async {
  // Create a fresh copy of the image
  img.Image workingImage = img.copyResize(image, width: image.width, height: image.height);
  
  // Create a debug image if needed
  img.Image? debugImage;
  if (generateDebugImage) {
    debugImage = img.copyResize(image, width: image.width, height: image.height);
  }

  try {
    // 1. Apply preprocessing to enhance edges
    final grayscale = BaseImageUtils.convertToGrayscale(workingImage);
    final equalized = ImageUtils.applyHistogramEqualization(grayscale);
    final blurred = FilterUtils.applyGaussianBlur(equalized, blurRadius);
    
    // 2. Apply edge detection
    final sobelEdges = FilterUtils.applyEdgeDetection(blurred, threshold: edgeThreshold.toInt() ~/ 2);
    final binaryEdges = ThresholdUtils.applyBinaryThreshold(sobelEdges, edgeThreshold.toInt());
    
    // 3. Copy to debug image if needed
    if (debugImage != null) {
      for (int y = 0; y < debugImage.height; y++) {
        for (int x = 0; x < debugImage.width; x++) {
          if (x >= binaryEdges.width || y >= binaryEdges.height) continue;
          debugImage.setPixel(x, y, binaryEdges.getPixel(x, y));
        }
      }
    }
    
    // 4. Find contour using ray casting (now from utility)
    final contourPoints = ContourDetectionUtils.findContourByRayCasting(
      binaryEdges, 
      seedX, 
      seedY,
      minSlabSize: minSlabSize,
      gapAllowedMin: gapAllowedMin,
      gapAllowedMax: gapAllowedMax,
      continueSearchDistance: continueSearchDistance
    );
    
    // 5. Apply convex hull if specified
    List<Point> processedContour = contourPoints;
    if (useConvexHull && contourPoints.length >= 3) {
      processedContour = GeometryUtils.convexHull(contourPoints);
    }
    
    // 6. Simplify and smooth contour
    final smoothContour = ContourDetectionUtils.smoothAndSimplifyContour(
      processedContour,
      simplificationEpsilon,
      windowSize: smoothingWindowSize
    );
    
    // 7. Convert to machine coordinates
    final machineContour = coordSystem.convertPointListToMachineCoords(smoothContour);
    
    // 8. Draw visualization on debug image if requested
    if (debugImage != null) {
      DrawingUtils.visualizeContourWithInfo(
        debugImage, 
        smoothContour, 
        seedX, 
        seedY,
        "Ray Casting Edge Detection"
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