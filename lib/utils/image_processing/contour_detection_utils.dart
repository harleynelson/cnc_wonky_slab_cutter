// lib/utils/image_processing/contour_detection_utils.dart
// Utilities for contour detection and processing

import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../services/gcode/machine_coordinates.dart';
import 'geometry_utils.dart';
import 'base_image_utils.dart';

/// Utilities for contour detection and processing
class ContourDetectionUtils {
  /// Find the outer contour of a binary mask using boundary tracing
  static List<Point> findOuterContour(List<List<bool>> mask) {
    final contourPoints = <Point>[];
    final height = mask.length;
    final width = mask[0].length;
    
    // Find a starting point (first true pixel)
    int startX = -1, startY = -1;
    
    // Start search from the center and spiral outward
    final centerX = width ~/ 2;
    final centerY = height ~/ 2;
    
    // First try to find a starting point near the center
    for (int radius = 0; radius < math.max(width, height) / 2; radius++) {
      // Check in spiral pattern
      for (int y = centerY - radius; y <= centerY + radius; y++) {
        for (int x = centerX - radius; x <= centerX + radius; x++) {
          // Only check perimeter of spiral
          if ((y == centerY - radius || y == centerY + radius) ||
              (x == centerX - radius || x == centerX + radius)) {
            if (x >= 0 && x < width && y >= 0 && y < height && mask[y][x]) {
              startX = x;
              startY = y;
              break;
            }
          }
        }
        if (startX != -1) break;
      }
      if (startX != -1) break;
    }
    
    // If no starting point was found, try scanning entire image
    if (startX == -1) {
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          if (mask[y][x]) {
            startX = x;
            startY = y;
            break;
          }
        }
        if (startX != -1) break;
      }
    }
    
    // No contour found
    if (startX == -1 || startY == -1) {
      return contourPoints;
    }
    
    // Moore boundary tracing algorithm
    // Direction codes: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
    final dx = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy = [0, 1, 1, 1, 0, -1, -1, -1];
    
    int x = startX;
    int y = startY;
    int dir = 7;  // Start looking in the NE direction
    
    final visited = <String>{};
    const maxSteps = 10000;  // Safety limit
    int steps = 0;
    
    do {
      // Add current point to contour
      contourPoints.add(Point(x.toDouble(), y.toDouble()));
      
      // Mark as visited
      final key = "$x,$y";
      visited.add(key);
      
      // Look for next boundary pixel
      bool found = false;
      for (int i = 0; i < 8 && !found; i++) {
        // Check in a counter-clockwise direction starting from dir
        int checkDir = (dir + i) % 8;
        int nx = x + dx[checkDir];
        int ny = y + dy[checkDir];
        
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        
        // If this is an object pixel (true in mask)
        if (mask[ny][nx]) {
          x = nx;
          y = ny;
          dir = (checkDir + 5) % 8;  // Backtrack direction
          found = true;
        }
      }
      
      if (!found) break;
      
      steps++;
      if (steps >= maxSteps) break;  // Safety check
      
    } while (!(x == startX && y == startY) || contourPoints.length <= 1);
    
    return contourPoints;
  }

  /// Apply morphological closing (dilation followed by erosion)
  static List<List<bool>> applyMorphologicalClosing(List<List<bool>> mask, int kernelSize) {
    // First apply dilation
    final dilated = applyDilation(mask, kernelSize);
    
    // Then apply erosion
    return applyErosion(dilated, kernelSize);
  }
  
  /// Apply morphological opening (erosion followed by dilation)
  static List<List<bool>> applyMorphologicalOpening(List<List<bool>> mask, int kernelSize) {
    // First apply erosion
    final eroded = applyErosion(mask, kernelSize);
    
    // Then apply dilation
    return applyDilation(eroded, kernelSize);
  }

  /// Apply morphological dilation to a binary mask
  static List<List<bool>> applyDilation(List<List<bool>> mask, int kernelSize) {
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
  
  /// Apply morphological erosion to a binary mask
  static List<List<bool>> applyErosion(List<List<bool>> mask, int kernelSize) {
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

  /// Apply dilation morphological operation to an image
  static img.Image applyDilationToImage(img.Image binary, int kernelSize) {
    final result = img.Image(width: binary.width, height: binary.height);
    final halfKernel = kernelSize ~/ 2;
   
    // Initialize with white
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
      }
    }
   
    // Apply dilation
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        final pixel = binary.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
       
        // If this is a black pixel (foreground)
        if (intensity < 128) {
          // Dilate by setting neighbors to black
          for (int j = -halfKernel; j <= halfKernel; j++) {
            for (int i = -halfKernel; i <= halfKernel; i++) {
              final nx = x + i;
              final ny = y + j;
             
              if (nx >= 0 && nx < binary.width && ny >= 0 && ny < binary.height) {
                result.setPixel(nx, ny, img.ColorRgba8(0, 0, 0, 255));
              }
            }
          }
        }
      }
    }
   
    return result;
  }
 
  /// Apply erosion morphological operation to an image
  static img.Image applyErosionToImage(img.Image binary, int kernelSize) {
    final result = img.Image(width: binary.width, height: binary.height);
    final halfKernel = kernelSize ~/ 2;
   
    // Initialize with white
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
      }
    }
   
    // Apply erosion
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        bool allBlack = true;
       
        // Check if all pixels in kernel are black
        for (int j = -halfKernel; j <= halfKernel && allBlack; j++) {
          for (int i = -halfKernel; i <= halfKernel && allBlack; i++) {
            final nx = x + i;
            final ny = y + j;
           
            if (nx < 0 || nx >= binary.width || ny < 0 || ny >= binary.height) {
              allBlack = false;
              continue;
            }
           
            final pixel = binary.getPixel(nx, ny);
            final intensity = BaseImageUtils.calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            );
           
            if (intensity >= 128) {  // If any pixel is white (background)
              allBlack = false;
            }
          }
        }
       
        if (allBlack) {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        }
      }
    }
   
    return result;
  }

  /// Apply morphological closing (dilation followed by erosion) to an image
  static img.Image applyMorphologicalClosingToImage(img.Image binary, int kernelSize) {
    // First dilate
    final dilated = applyDilationToImage(binary, kernelSize);
    
    // Then erode
    return applyErosionToImage(dilated, kernelSize);
  }
  
  /// Apply morphological opening (erosion followed by dilation) to an image
  static img.Image applyMorphologicalOpeningToImage(img.Image binary, int kernelSize) {
    // First erode
    final eroded = applyErosionToImage(binary, kernelSize);
    
    // Then dilate
    return applyDilationToImage(eroded, kernelSize);
  }

  /// Create a binary mask from an image
  static List<List<bool>> createBinaryMask(img.Image image, int threshold) {
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
        
        mask[y][x] = intensity < threshold;
      }
    }
    
    return mask;
  }

  /// Smooth and simplify a contour
  static List<Point> smoothAndSimplifyContour(List<Point> contour, double epsilon, 
      {int windowSize = 5, double sigma = 1.0}) {
    if (contour.length <= 3) return contour;
    
    // 1. Apply Douglas-Peucker simplification
    final simplified = GeometryUtils.simplifyPolygon(contour, epsilon);
    
    // 2. Apply Gaussian smoothing
    return smoothContour(simplified, windowSize: windowSize);
  }

  /// Smooth contour using Gaussian smoothing
  static List<Point> smoothContour(List<Point> contour, {int windowSize = 5, double sigma = 1.0}) {
    if (contour.length <= 3) return contour;
    
    final result = <Point>[];
    final halfWindow = windowSize ~/ 2;
    
    // Generate Gaussian kernel
    final kernel = <double>[];
    double sum = 0.0;
    
    for (int i = -halfWindow; i <= halfWindow; i++) {
      final weight = math.exp(-(i * i) / (2 * sigma * sigma));
      kernel.add(weight);
      sum += weight;
    }
    
    // Normalize kernel
    for (int i = 0; i < kernel.length; i++) {
      kernel[i] /= sum;
    }
    
    // Apply smoothing
    for (int i = 0; i < contour.length; i++) {
      double sumX = 0.0;
      double sumY = 0.0;
      
      for (int j = -halfWindow; j <= halfWindow; j++) {
        final idx = (i + j + contour.length) % contour.length;
        final weight = kernel[j + halfWindow];
        
        sumX += contour[idx].x * weight;
        sumY += contour[idx].y * weight;
      }
      
      result.add(Point(sumX, sumY));
    }
    
    return result;
  }

  /// Create a fallback contour shape for cases where detection fails
  static List<Point> createFallbackContour(int width, int height) {
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
  
  /// Find connected components in a binary image
  static List<List<Point>> findConnectedComponents(img.Image binaryImage, {
    int minSize = 20,
    int maxSize = 100000,
    int maxDepth = 1000,
  }) {
    final List<List<Point>> components = [];
    final width = binaryImage.width;
    final height = binaryImage.height;
    
    // Create visited array
    final visited = List.generate(
      height,
      (y) => List.filled(width, false),
    );
    
    // Find connected components
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (visited[y][x]) continue;
        
        final pixel = binaryImage.getPixel(x, y);
        final isObject = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        ) < 128; // Object is dark in binary image
        
        if (isObject) {
          final List<Point> component = [];
          _floodFill(binaryImage, x, y, visited, component, maxDepth);
          
          // Filter by size
          if (component.length >= minSize && component.length <= maxSize) {
            components.add(component);
          }
        } else {
          visited[y][x] = true;
        }
      }
    }
    
    return components;
  }
  
  /// Find the largest contour in a binary image
  static List<Point> findLargestContour(img.Image binary) {
    final blobs = findConnectedComponents(binary);
    
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
    final List<Point> largestBlob = blobs[largestBlobIndex];
    
    // If we have enough points, compute the convex hull
    if (largestBlob.length >= 3) {
      return GeometryUtils.convexHull(largestBlob);
    }
    
    return largestBlob;
  }
  
  /// Flood fill algorithm for connected component labeling
  static void _floodFill(
    img.Image image,
    int x,
    int y,
    List<List<bool>> visited,
    List<Point> component,
    int maxDepth,
    {int depth = 0}
  ) {
    // Prevent stack overflow
    if (depth >= maxDepth) return;
    
    if (x < 0 || y < 0 || x >= image.width || y >= image.height || visited[y][x]) {
      return;
    }
    
    final pixel = image.getPixel(x, y);
    final isObject = BaseImageUtils.calculateLuminance(
      pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
    ) < 128; // Object is dark
    
    if (!isObject) {
      visited[y][x] = true;
      return;
    }
    
    visited[y][x] = true;
    component.add(Point(x.toDouble(), y.toDouble()));
    
    // Check 4-connected neighbors
    _floodFill(image, x + 1, y, visited, component, maxDepth, depth: depth + 1);
    _floodFill(image, x - 1, y, visited, component, maxDepth, depth: depth + 1);
    _floodFill(image, x, y + 1, visited, component, maxDepth, depth: depth + 1);
    _floodFill(image, x, y - 1, visited, component, maxDepth, depth: depth + 1);
  }
  
  /// Check if a contour is self-intersecting
  static bool isContourSelfIntersecting(List<Point> contour) {
    if (contour.length < 4) return false;
    
    // Check each pair of non-adjacent line segments for intersection
    for (int i = 0; i < contour.length - 1; i++) {
      final p1 = contour[i];
      final p2 = contour[i + 1];
      
      for (int j = i + 2; j < contour.length - 1; j++) {
        // Skip adjacent segments
        if (i == 0 && j == contour.length - 2) continue;
        
        final p3 = contour[j];
        final p4 = contour[j + 1];
        
        if (GeometryUtils.lineSegmentIntersection(p1, p2, p3, p4) != null) {
          return true;
        }
      }
    }
    
    return false;
  }

  /// Ensure we have a clean outer contour without internal details
  static List<Point> ensureCleanOuterContour(List<Point> contour) {
    // If the contour is too small or invalid, return as is
    if (contour.length < 10) {
      return contour;
    }
    
    try {
      // 1. Make sure the contour is closed
      List<Point> workingContour = List.from(contour);
      if (workingContour.first.x != workingContour.last.x || 
          workingContour.first.y != workingContour.last.y) {
        workingContour.add(workingContour.first);
      }
      
      // 2. Check if the contour is self-intersecting
      if (isContourSelfIntersecting(workingContour)) {
        // If self-intersecting, compute convex hull instead
        final points = List<Point>.from(workingContour);
        return GeometryUtils.convexHull(points);
      }
      
      // 3. Eliminate concave sections that are too deep
      workingContour = simplifyDeepConcavities(workingContour);
      
      // 4. Apply smoothing to get rid of jagged edges
      workingContour = smoothContour(workingContour, windowSize: 5);
      
      return workingContour;
    } catch (e) {
      print('Error cleaning contour: $e');
      return contour;
    }
  }

  /// Simplify deep concavities in the contour
  static List<Point> simplifyDeepConcavities(List<Point> contour, [double thresholdRatio = 0.2]) {
    if (contour.length < 4) return contour;
    
    final result = <Point>[];
    
    // Calculate perimeter
    double perimeter = GeometryUtils.polygonPerimeter(contour);
    
    // Calculate threshold distance
    final threshold = perimeter * thresholdRatio;
    
    // Add first point
    result.add(contour.first);
    
    // Process internal points
    for (int i = 1; i < contour.length - 1; i++) {
      final prev = result.last;
      final current = contour[i];
      final next = contour[i + 1];
      
      // Check if this forms a deep concavity
      final direct = GeometryUtils.distanceBetween(prev, next);
      final detour = GeometryUtils.distanceBetween(prev, current) + GeometryUtils.distanceBetween(current, next);
      
      // If detour is much longer than direct path, skip this point
      if (detour > direct + threshold) {
        // Skip this point as it forms a deep concavity
        continue;
      }
      
      result.add(current);
    }
    
    // Add last point
    result.add(contour.last);
    
    return result;
  }

  /// Clip a toolpath to ensure it stays within the contour
  static List<Point> clipToolpathToContour(List<Point> toolpath, List<Point> contour) {
    if (toolpath.isEmpty || contour.length < 3) {
      return toolpath;
    }
    
    final result = <Point>[];
    
    // For each segment in the toolpath
    for (int i = 0; i < toolpath.length - 1; i++) {
      final p1 = toolpath[i];
      final p2 = toolpath[i + 1];
      
      // Check if both points are inside the contour
      final p1Inside = GeometryUtils.isPointInPolygon(p1, contour);
      final p2Inside = GeometryUtils.isPointInPolygon(p2, contour);
      
      if (p1Inside && p2Inside) {
        // Both points inside, add the entire segment
        result.add(p1);
        result.add(p2);
      } else if (p1Inside || p2Inside) {
        // One point inside, one outside - find intersection with contour
        final intersections = GeometryUtils.findLinePolygonIntersections(p1, p2, contour);
        
        if (intersections.isNotEmpty) {
          // Sort intersections by distance from p1
          intersections.sort((a, b) {
            final distA = GeometryUtils.squaredDistance(p1, a);
            final distB = GeometryUtils.squaredDistance(p1, b);
            return distA.compareTo(distB);
          });
          
          if (p1Inside) {
            // p1 inside, p2 outside
            result.add(p1);
            result.add(intersections.first);
          } else {
            // p2 inside, p1 outside
            result.add(intersections.last);
            result.add(p2);
          }
        }
      } else {
        // Both points outside, check if the line segment intersects the contour
        final intersections = GeometryUtils.findLinePolygonIntersections(p1, p2, contour);
        
        if (intersections.length >= 2) {
          // If multiple intersections, add the segment between first and last
          intersections.sort((a, b) {
            final distA = GeometryUtils.squaredDistance(p1, a);
            final distB = GeometryUtils.squaredDistance(p1, b);
            return distA.compareTo(distB);
          });
          
          result.add(intersections.first);
          result.add(intersections.last);
        }
      }
    }
    
    return result;
  }
}