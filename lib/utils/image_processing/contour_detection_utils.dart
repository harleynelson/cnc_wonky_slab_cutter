// lib/utils/image_processing/contour_detection_utils.dart
// Utilities for contour detection and processing

import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../general/machine_coordinates.dart';
import 'geometry_utils.dart';
import 'base_image_utils.dart';

/// Utilities for contour detection and processing
class ContourDetectionUtils {
  /// Find the outer contour of a binary mask using boundary tracing
  static List<Point> findOuterContour(List<List<bool>> mask) {
  var contourPoints = <Point>[];
  final height = mask.length;
  final width = mask[0].length;
  
  print('DEBUG: Finding contour for mask of size ${width}x${height}');

  // Define parameters for gap handling
  final maxGapToFill = 15; // Maximum gap size to attempt to fill
  
  // First find the boundary points - points where true meets false
  final boundaryPoints = <Point>[];
  
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      if (mask[y][x]) {
        // Check if this is a boundary pixel (has at least one false neighbor)
        bool isBoundary = false;
        
        // Check 8-connected neighbors
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue; // Skip self
            
            final nx = x + dx;
            final ny = y + dy;
            
            if (nx < 0 || nx >= width || ny < 0 || ny >= height || !mask[ny][nx]) {
              isBoundary = true;
              break;
            }
          }
          if (isBoundary) break;
        }
        
        if (isBoundary) {
          boundaryPoints.add(Point(x.toDouble(), y.toDouble()));
        }
      }
    }
  }
  
  if (boundaryPoints.isEmpty) {
    print('DEBUG: No boundary points found, using fallback');
    return _createFallbackContour(width, height);
  }
  
  // Find the center of the shape
  double sumX = 0, sumY = 0;
  for (final point in boundaryPoints) {
    sumX += point.x;
    sumY += point.y;
  }
  final centerX = sumX / boundaryPoints.length;
  final centerY = sumY / boundaryPoints.length;
  final center = Point(centerX, centerY);
  
  // Sort boundary points by angle from center
  boundaryPoints.sort((a, b) {
    final angleA = math.atan2(a.y - centerY, a.x - centerX);
    final angleB = math.atan2(b.y - centerY, b.x - centerX);
    return angleA.compareTo(angleB);
  });
  
  // Process boundary points, filling gaps
  contourPoints.add(boundaryPoints.first);
  for (int i = 1; i < boundaryPoints.length; i++) {
    final prev = contourPoints.last;
    final current = boundaryPoints[i];
    
    // Check if there's a gap
    final distance = _distance(prev, current);
    
    if (distance > maxGapToFill) {
      // Large gap - skip this point
      continue;
    } else if (distance > 2.0) {
      // Small gap - add intermediate points
      final steps = distance.ceil();
      for (int j = 1; j < steps; j++) {
        final t = j / steps;
        final interpX = prev.x + (current.x - prev.x) * t;
        final interpY = prev.y + (current.y - prev.y) * t;
        contourPoints.add(Point(interpX, interpY));
      }
    }
    
    contourPoints.add(current);
  }
  
  // Close the contour
  if (contourPoints.length > 2) {
    final first = contourPoints.first;
    final last = contourPoints.last;
    
    if (first.x != last.x || first.y != last.y) {
      contourPoints.add(first);
    }
  }
  
  print('DEBUG: Found ${contourPoints.length} contour points');
  return contourPoints;
}

// Helper to calculate distance between points
static double _distance(Point a, Point b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

// Create fallback contour
static List<Point> _createFallbackContour(int width, int height) {
  final contour = <Point>[];
  final centerX = width / 2;
  final centerY = height / 2;
  final radius = math.min(width, height) * 0.3;
  
  for (int i = 0; i <= 36; i++) {
    final angle = i * math.pi / 18; // 10 degrees in radians
    final x = centerX + radius * math.cos(angle);
    final y = centerY + radius * math.sin(angle);
    contour.add(Point(x, y));
  }
  
  return contour;
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

  /// Find contour using ray casting from a seed point
static List<Point> findContourByRayCasting(
  img.Image binaryImage, 
  int seedX, 
  int seedY,
  {
    int minSlabSize = 1000, 
    int gapAllowedMin = 5, 
    int gapAllowedMax = 20,
    int continueSearchDistance = 30
  }
) {
  final width = binaryImage.width;
  final height = binaryImage.height;
  var contourPoints = <Point>[];
  final visited = Set<String>();
  
  // For each angle, store the farthest edge point
  final Map<int, Point> farthestEdgePoints = {};
  
  // Cast rays in all directions (every 5 degrees)
  for (int angle = 0; angle < 360; angle += 5) {
    final radians = angle * math.pi / 180;
    final dirX = math.cos(radians);
    final dirY = math.sin(radians);
    
    // Start from seed point
    double x = seedX.toDouble();
    double y = seedY.toDouble();
    
    // Tracks if we're in a gap
    int gapSize = 0;
    bool foundEdge = false;
    Point? lastEdgePoint;
    double lastEdgeDistance = 0;
    double currentDistance = 0;
    
    // Cast ray until we hit the image boundary
    while (x >= 0 && x < width && y >= 0 && y < height) {
      final px = x.round();
      final py = y.round();
      final key = "$px,$py";
      
      // Calculate distance from seed
      final dx = x - seedX;
      final dy = y - seedY;
      currentDistance = math.sqrt(dx * dx + dy * dy);
      
      // Skip if we've already visited this pixel
      if (!visited.contains(key)) {
        visited.add(key);
        
        // Check if this is an edge pixel (white/bright in binary image)
        final pixel = binaryImage.getPixel(px, py);
        final luminance = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        final isEdge = luminance > 128;
        
        if (isEdge) {
          // We found an edge pixel
          lastEdgePoint = Point(x, y);
          lastEdgeDistance = currentDistance;
          gapSize = 0;
          foundEdge = true;
          
          // Keep track of the farthest edge point at this angle
          if (!farthestEdgePoints.containsKey(angle) || 
              lastEdgeDistance > _distanceFromSeed(farthestEdgePoints[angle]!, seedX, seedY)) {
            farthestEdgePoints[angle] = lastEdgePoint;
          }
        } else if (foundEdge) {
          // We're in a gap after finding an edge
          gapSize++;
          
          // If gap is too large, we've reached the end of this contour
          if (gapSize > gapAllowedMax && 
              currentDistance > lastEdgeDistance + continueSearchDistance) {
            break;
          }
        }
      }
      
      // Move along the ray
      x += dirX;
      y += dirY;
    }
  }
  
  // Use the farthest edge points to form the contour
  contourPoints = farthestEdgePoints.values.toList();
  
  // Post-process contour points
  if (contourPoints.length < 10 || _calculateArea(contourPoints) < minSlabSize) {
    return createFallbackContour(width, height, seedX, seedY);
  }
  
  // Sort contour points by their angle from the center for a consistent order
  sortPointsByAngle(contourPoints, Point(seedX.toDouble(), seedY.toDouble()));
  
  return contourPoints;
}

// Add helper method to calculate distance from seed
static double _distanceFromSeed(Point point, int seedX, int seedY) {
  final dx = point.x - seedX;
  final dy = point.y - seedY;
  return math.sqrt(dx * dx + dy * dy);
}

// Add helper method to calculate contour area
static double _calculateArea(List<Point> points) {
  if (points.length < 3) return 0.0;
  
  double area = 0.0;
  for (int i = 0; i < points.length; i++) {
    int j = (i + 1) % points.length;
    area += points[i].x * points[j].y;
    area -= points[j].x * points[i].y;
  }
  
  return area.abs() / 2.0;
}

/// Create a fallback contour around a seed point
static List<Point> createFallbackContour(
  int width, 
  int height, 
  [int? seedX, int? seedY]  // Optional parameters with default values
) {
  // Use center of image if no seed point provided
  final centerX = seedX ?? (width / 2).round();
  final centerY = seedY ?? (height / 2).round();
  
  final contour = <Point>[];
  final radius = math.min(width, height) * 0.3;
  
  // Create a circular contour around the seed point
  for (int angle = 0; angle < 360; angle += 10) {
    final radians = angle * math.pi / 180;
    final x = centerX + radius * math.cos(radians);
    final y = centerY + radius * math.sin(radians);
    contour.add(Point(x, y));
  }
  
  return contour;
}

/// Sort points by angle around center
static void sortPointsByAngle(List<Point> points, Point center) {
  points.sort((a, b) {
    final angleA = math.atan2(a.y - center.y, a.x - center.x);
    final angleB = math.atan2(b.y - center.y, b.x - center.x);
    return angleA.compareTo(angleB);
  });
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