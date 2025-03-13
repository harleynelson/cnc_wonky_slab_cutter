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
import '../../../utils/image_processing/color_utils.dart';
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
   this.edgeThreshold = 50.0,
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
   // Create a fresh copy of the image
   img.Image workingImage = img.copyResize(image, width: image.width, height: image.height);
   
   // Create a debug image if needed
   img.Image? debugImage;
   if (generateDebugImage) {
     debugImage = img.copyResize(image, width: image.width, height: image.height);
   }

   try {
     // 1. Use much more aggressive preprocessing
     final grayscale = BaseImageUtils.convertToGrayscale(workingImage);
     
     // Apply histogram equalization for better contrast
     final equalized = ImageUtils.applyHistogramEqualization(grayscale);
     
     // Apply Gaussian blur with controlled radius
     final blurred = FilterUtils.applyGaussianBlur(equalized, blurRadius);
     
     // 2. Apply multiple edge detection approaches and combine results
     final sobelEdges = FilterUtils.applyEdgeDetection(blurred, threshold: edgeThreshold.toInt() ~/ 2);
     
     // Create a very high contrast binary image
     final binaryEdges = ThresholdUtils.applyBinaryThreshold(sobelEdges, edgeThreshold.toInt());
     
     // 3. Copy to debug image - what you'll see
     if (debugImage != null) {
       for (int y = 0; y < debugImage.height; y++) {
         for (int x = 0; x < debugImage.width; x++) {
           if (x >= binaryEdges.width || y >= binaryEdges.height) continue;
           debugImage.setPixel(x, y, binaryEdges.getPixel(x, y));
         }
       }
     }
     
     // 4. Create and invert binary mask - treat white as background, black as edges
     final edgeMask = List.generate(
       binaryEdges.height, 
       (y) => List.generate(binaryEdges.width, 
         (x) {
           final pixel = binaryEdges.getPixel(x, y);
           final intensity = BaseImageUtils.calculateLuminance(
             pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
           );
           // Invert: true for non-edge pixels
           return intensity > 128;
         }
       )
     );
     
     // 5. Region grow from seed
     final regionMask = _floodFillRegion(edgeMask, seedX, seedY);
     
     // 6. Apply morphological operations for smoother results
     final closedMask = ContourDetectionUtils.applyMorphologicalClosing(regionMask, 7);

     // Debug info about the region mask
      int regionPixelCount = 0;
      for (int y = 0; y < regionMask.length; y++) {
        for (int x = 0; x < regionMask[y].length; x++) {
          if (regionMask[y][x]) regionPixelCount++;
        }
      }
      print('DEBUG: Region mask contains $regionPixelCount pixels');

      // Around line 94 after creating closedMask:
      int closedPixelCount = 0;
      for (int y = 0; y < closedMask.length; y++) {
        for (int x = 0; x < closedMask[y].length; x++) {
          if (closedMask[y][x]) closedPixelCount++;
        }
      }
      print('DEBUG: Closed mask contains $closedPixelCount pixels');
     
     // 7. Find contour - MODIFIED WITH EXTRA CHECKS
      List<Point> contourPoints = ContourDetectionUtils.findOuterContour(closedMask);
      print('DEBUG: Found ${contourPoints.length} initial contour points');

      // If contour is too small, try with larger morphological operations
      if (contourPoints.length < 20) {
        print('DEBUG: Initial contour too small, trying with larger morphological operations');
        final expandedMask = ContourDetectionUtils.applyMorphologicalClosing(regionMask, 12);
        contourPoints = ContourDetectionUtils.findOuterContour(expandedMask);
        print('DEBUG: After expansion, found ${contourPoints.length} contour points');
      }
     
     // 8. Apply convex hull if specified - helps with missing edges
      List<Point> processedContour = contourPoints;
      if (useConvexHull && contourPoints.length >= 3) {
        processedContour = GeometryUtils.convexHull(contourPoints);
        print('DEBUG: After convex hull, have ${processedContour.length} contour points');
      }
     
     // 9. Simplify and smooth contour with larger window
     final smoothContour = ContourDetectionUtils.smoothAndSimplifyContour(
       processedContour,
       simplificationEpsilon,
       windowSize: smoothingWindowSize
     );
     
     // 10. Convert to machine coordinates
     final machineContour = coordSystem.convertPointListToMachineCoords(smoothContour);
     
     // 11. Draw visualization on debug image - ENHANCED
     if (debugImage != null) {
       // Keep binary image in background but make it semi-transparent
       for (int y = 0; y < debugImage.height; y++) {
         for (int x = 0; x < debugImage.width; x++) {
           if (x >= binaryEdges.width || y >= binaryEdges.height) continue;
           
           final pixel = binaryEdges.getPixel(x, y);
           final intensity = BaseImageUtils.calculateLuminance(
             pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
           );
           
           // Make binary image semi-transparent
           final originalPixel = image.getPixel(x, y);
           if (intensity < 128) {
             // Edge pixels - make visible but semi-transparent
             debugImage.setPixel(x, y, img.ColorRgba8(
               (originalPixel.r.toInt() * 0.3 + 200 * 0.7).round(),
               (originalPixel.g.toInt() * 0.3 + 200 * 0.7).round(),
               (originalPixel.b.toInt() * 0.3 + 200 * 0.7).round(),
               255
             ));
           } else {
             // Background pixels - darken
             debugImage.setPixel(x, y, img.ColorRgba8(
               (originalPixel.r.toInt() * 0.5).round(),
               (originalPixel.g.toInt() * 0.5).round(),
               (originalPixel.b.toInt() * 0.5).round(),
               255
             ));
           }
         }
       }
       
       // Draw a high-visibility contour with fill effect
       _drawHighlightedContourWithFill(debugImage, smoothContour);
       
       // Draw seed point
       DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
       
       // Add algorithm name and info
       DrawingUtils.drawText(debugImage, "Algorithm: $name", 10, 10, img.ColorRgba8(255, 255, 255, 255));
       
       // Add area information
       final area = GeometryUtils.polygonArea(machineContour);
       DrawingUtils.drawText(
         debugImage, 
         "Area: ${area.toStringAsFixed(0)} mm²", 
         10, 30, 
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
 
 /// Greatly expanded flood fill region that better handles wood slabs
List<List<bool>> _floodFillRegion(List<List<bool>> mask, int seedX, int seedY) {
  final height = mask.length;
  final width = mask[0].length;
  
  print('DEBUG: Starting flood fill from seed point ($seedX, $seedY)');
  
  // Create a result mask
  final result = List.generate(height, (_) => List<bool>.filled(width, false));
  
  // Min size for the slab (configurable)
  final minSlabSize = math.min(width, height) ~/ 4; // At least 1/4 of the image dimension
  
  // Count edge pixels in entire image
  int totalEdgePixels = 0;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      if (!mask[y][x]) {
        totalEdgePixels++;
      }
    }
  }
  
  print('DEBUG: Total edge pixels: $totalEdgePixels');
  
  // If very few edges, we need to be more aggressive
  final bool sparseEdges = totalEdgePixels < (width * height * 0.01); // Less than 1% of pixels
  
  // Start flood fill from seed point
  final queue = <List<int>>[];
  final visited = List.generate(height, (_) => List<bool>.filled(width, false));
  
  // Add seed point to queue
  queue.add([seedX, seedY]);
  visited[seedY][seedX] = true;
  result[seedY][seedX] = true;
  
  // Ensure seed is within non-edge region
  if (!mask[seedY][seedX]) {
    // Find closest non-edge pixel to seed
    int closestX = seedX;
    int closestY = seedY;
    double minDist = double.infinity;
    
    // Search in expanding circles
    for (int radius = 1; radius < minSlabSize; radius++) {
      bool found = false;
      
      for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
          // Only check points on the circle perimeter
          if (dx.abs() + dy.abs() != radius) continue;
          
          final ny = seedY + dy;
          final nx = seedX + dx;
          
          if (nx >= 0 && nx < width && ny >= 0 && ny < height && mask[ny][nx]) {
            final dist = dx * dx + dy * dy;
            if (dist < minDist) {
              closestX = nx;
              closestY = ny;
              minDist = dist as double;
              found = true;
            }
          }
        }
      }
      
      if (found) {
        print('DEBUG: Adjusted seed point from ($seedX, $seedY) to ($closestX, $closestY)');
        queue.clear();
        queue.add([closestX, closestY]);
        visited[closestY][closestX] = true;
        result[closestY][closestX] = true;
        break;
      }
    }
  }
  
  // 8-connected neighbors for better connectivity
  final dx = [1, 1, 0, -1, -1, -1, 0, 1];
  final dy = [0, 1, 1, 1, 0, -1, -1, -1];
  
  // Flood fill
  int filledPixels = 0;
  final int maxPixels = width * height; // Cap to prevent excessive growth
  
  while (queue.isNotEmpty && filledPixels < maxPixels) {
    final point = queue.removeAt(0);
    final x = point[0];
    final y = point[1];
    
    // Mark as filled
    result[y][x] = true;
    filledPixels++;
    
    // Check neighbors
    for (int i = 0; i < 8; i++) {
      final nx = x + dx[i];
      final ny = y + dy[i];
      
      if (nx < 0 || nx >= width || ny < 0 || ny >= height || visited[ny][nx]) {
        continue;
      }
      
      // In sparse edge cases, be more lenient with what we consider part of the slab
      if (mask[ny][nx] || sparseEdges) {
        visited[ny][nx] = true;
        queue.add([nx, ny]);
      }
    }
  }
  
  print('DEBUG: Flood filled $filledPixels pixels');
  
  // Check if we found a large enough region
  if (filledPixels < minSlabSize * minSlabSize) {
    print('DEBUG: Flood fill region too small, using box around seed point');
    
    // Create a box around the seed point
    final boxSize = minSlabSize;
    final left = math.max(0, seedX - boxSize);
    final right = math.min(width - 1, seedX + boxSize);
    final top = math.max(0, seedY - boxSize);
    final bottom = math.min(height - 1, seedY + boxSize);
    
    // Reset result to all false
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        result[y][x] = false;
      }
    }
    
    // Set box area to true
    for (int y = top; y <= bottom; y++) {
      for (int x = left; x <= right; x++) {
        result[y][x] = true;
      }
    }
  }
  
  return result;
}

 void _drawHighlightedContourWithFill(img.Image image, List<Point> contour) {
  if (contour.isEmpty) return;
  
  // Print debug info
  print('DEBUG: Drawing contour with ${contour.length} points');
  
  // 1. First make contour visible with thick lines
  try {
    // Draw bright outline for visibility
    DrawingUtils.drawContour(image, contour, img.ColorRgba8(0, 255, 0, 255), thickness: 5);
    
    // Draw additional yellow outline for better contrast
    DrawingUtils.drawContour(image, contour, img.ColorRgba8(255, 255, 0, 180), thickness: 2);
    
    // Add corner points with larger markers
    for (int i = 0; i < contour.length; i += math.max(1, contour.length ~/ 20)) {
      final point = contour[i];
      // Draw a larger circle
      DrawingUtils.drawCircle(
        image, 
        point.x.round(), 
        point.y.round(), 
        6, 
        img.ColorRgba8(255, 0, 0, 255),
        fill: true
      );
    }
    
    // Print the first few contour points for debugging
    for (int i = 0; i < math.min(5, contour.length); i++) {
      print('DEBUG: Contour point $i: (${contour[i].x.round()}, ${contour[i].y.round()})');
    }
  } catch (e) {
    print('ERROR in drawing contour: $e');
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