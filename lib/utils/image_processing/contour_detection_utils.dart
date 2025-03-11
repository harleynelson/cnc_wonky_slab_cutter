// lib/services/image_processing/image_processing_utils/contour_detection_utils.dart
// Utilities for contour detection and processing

import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../services/gcode/machine_coordinates.dart';
import 'geometry_utils.dart';
import 'base_image_utils.dart';

/// Utilities for contour detection and processing
class ContourDetectionUtils {
  /// Find contours in a binary image
  static List<List<Point>> findContours(img.Image binaryImage, {
    int minSize = 10,
    int maxSize = 100000,
    int maxDepth = 1000,
  }) {
    final List<List<Point>> contours = [];
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
            // Extract boundary points
            final contour = _extractContourFromComponent(component, binaryImage);
            contours.add(contour);
          }
        } else {
          visited[y][x] = true;
        }
      }
    }
    
    return contours;
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
  
  /// Extract contour boundary points from a component using boundary tracing
  static List<Point> _extractContourFromComponent(List<Point> component, img.Image binaryImage) {
    if (component.isEmpty) return [];
    
    // Find the leftmost point (which is guaranteed to be on the boundary)
    int minXIndex = 0;
    double minX = component[0].x;
    
    for (int i = 1; i < component.length; i++) {
      if (component[i].x < minX) {
        minX = component[i].x;
        minXIndex = i;
      }
    }
    
    final startPoint = component[minXIndex];
    
    // Use Moore boundary tracing algorithm
    return _traceBoundary(binaryImage, startPoint);
  }
  
  /// Trace the boundary of an object using Moore boundary tracing
  static List<Point> _traceBoundary(img.Image binaryImage, Point startPoint) {
    final boundary = <Point>[];
    final width = binaryImage.width;
    final height = binaryImage.height;
    
    // Direction codes: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
    final dx = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy = [0, 1, 1, 1, 0, -1, -1, -1];
    
    int x = startPoint.x.round();
    int y = startPoint.y.round();
    int dir = 7;  // Start by looking in the NE direction
    
    final visited = <String>{};
    const maxSteps = 10000;  // Safety limit
    int steps = 0;
    
    do {
      // Add current point to boundary
      boundary.add(Point(x.toDouble(), y.toDouble()));
      
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
        
        final pixel = binaryImage.getPixel(nx, ny);
        final isObject = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        ) < 128;
        
        if (isObject) {  // Found an object pixel
          x = nx;
          y = ny;
          dir = (checkDir + 5) % 8;  // Backtrack direction
          found = true;
        }
      }
      
      if (!found) break;
      
      steps++;
      if (steps >= maxSteps) break;  // Safety check
      
    } while (!(x == startPoint.x.round() && y == startPoint.y.round()) || boundary.length <= 1);
    
    return boundary;
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
    final List<int> largestBlob = blobs[largestBlobIndex].cast<int>();
    
    // Convert to Point objects
    final points = <Point>[];
    for (int i = 0; i < largestBlob.length; i += 2) {
      if (i + 1 < largestBlob.length) {
        final int x = largestBlob[i];
        final int y = largestBlob[i+1];
        points.add(Point(x.toDouble(), y.toDouble()));
      }
    }
    
    // If we have enough points, compute the convex hull
    if (points.length >= 3) {
      return GeometryUtils.convexHull(points);
    }
    
    return points;
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
  
  /// Apply an adaptive threshold to an image
  static img.Image applyAdaptiveThreshold(img.Image grayscale, int blockSize, int constant) {
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    final halfBlock = blockSize ~/ 2;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        // Calculate local mean
        int sum = 0;
        int count = 0;
        
        for (int j = math.max(0, y - halfBlock); j <= math.min(grayscale.height - 1, y + halfBlock); j++) {
          for (int i = math.max(0, x - halfBlock); i <= math.min(grayscale.width - 1, x + halfBlock); i++) {
            final pixel = grayscale.getPixel(i, j);
            sum += BaseImageUtils.calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            );
            count++;
          }
        }
        
        final mean = count > 0 ? sum / count : 128;
        final pixel = grayscale.getPixel(x, y);
        final pixelValue = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        // Apply threshold
        if (pixelValue < mean - constant) {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255)); // Object
        } else {
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // Background
        }
      }
    }
    
    return result;
  }
  
  /// Apply morphological closing (dilation followed by erosion)
  static img.Image applyMorphologicalClosing(img.Image binary, int kernelSize) {
    // First dilate
    final dilated = _applyDilation(binary, kernelSize);
    
    // Then erode
    return _applyErosion(dilated, kernelSize);
  }
  
  /// Apply morphological opening (erosion followed by dilation)
  static img.Image applyMorphologicalOpening(img.Image binary, int kernelSize) {
    // First erode
    final eroded = _applyErosion(binary, kernelSize);
    
    // Then dilate
    return _applyDilation(eroded, kernelSize);
  }
  
  /// Apply dilation morphological operation
  static img.Image _applyDilation(img.Image binary, int kernelSize) {
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
  
  /// Apply erosion morphological operation
  static img.Image _applyErosion(img.Image binary, int kernelSize) {
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
  
  /// Smooth and simplify a contour
  static List<Point> smoothAndSimplifyContour(List<Point> contour, double epsilon, 
      {int windowSize = 5, double sigma = 1.0}) {
    if (contour.length <= 3) return contour;
    
    // 1. Apply Douglas-Peucker simplification
    final simplified = GeometryUtils.simplifyPolygon(contour, epsilon);
    
    // 2. Apply Gaussian smoothing
    return applyGaussianSmoothing(simplified, windowSize, sigma);
  }
  
  /// Apply Gaussian smoothing to contour points
  static List<Point> applyGaussianSmoothing(List<Point> contour, int windowSize, double sigma) {
    if (contour.length <= windowSize) return contour;
    
    final result = <Point>[];
    final halfWindow = windowSize ~/ 2;
    
    // Generate Gaussian kernel
    final kernel = _generateGaussianKernel(windowSize, sigma);
    
    // Apply smoothing
    for (int i = 0; i < contour.length; i++) {
      double sumX = 0;
      double sumY = 0;
      double sumWeight = 0;
      
      for (int j = -halfWindow; j <= halfWindow; j++) {
        final idx = (i + j + contour.length) % contour.length;
        final weight = kernel[j + halfWindow];
        
        sumX += contour[idx].x * weight;
        sumY += contour[idx].y * weight;
        sumWeight += weight;
      }
      
      if (sumWeight > 0) {
        result.add(Point(sumX / sumWeight, sumY / sumWeight));
      } else {
        result.add(contour[i]);
      }
    }
    
    return result;
  }
  
  /// Generate a Gaussian kernel for smoothing
  static List<double> _generateGaussianKernel(int size, double sigma) {
    final kernel = List<double>.filled(size, 0);
    final halfSize = size ~/ 2;
    
    double sum = 0;
    for (int i = 0; i < size; i++) {
      final x = i - halfSize;
      kernel[i] = math.exp(-(x * x) / (2 * sigma * sigma));
      sum += kernel[i];
    }
    
    // Normalize kernel
    for (int i = 0; i < size; i++) {
      kernel[i] /= sum;
    }
    
    return kernel;
  }
  
  /// Ensure contour is closed (last point equals first point)
  static List<Point> ensureClosedContour(List<Point> contour) {
    if (contour.length < 3) return contour;
    
    // Check if already closed
    if (contour.first.x == contour.last.x && contour.first.y == contour.last.y) {
      return contour;
    }
    
    // Add first point to the end
    final result = List<Point>.from(contour);
    result.add(result.first);
    
    return result;
  }
  
  /// Interpolate contour to achieve even spacing
  static List<Point> interpolateContour(List<Point> contour, int desiredPointCount) {
    if (contour.length >= desiredPointCount) return contour;
    
    final result = <Point>[];
    
    // Calculate total contour length
    double totalLength = 0.0;
    for (int i = 0; i < contour.length - 1; i++) {
      totalLength += GeometryUtils.distanceBetween(contour[i], contour[i + 1]);
    }
    
    // Desired segment length
    final desiredSpacing = totalLength / desiredPointCount;
    
    // Add first point
    result.add(contour.first);
    
    double accumulatedLength = 0.0;
    int currentSegment = 0;
    
    // Interpolate points
    for (int i = 1; i < desiredPointCount - 1; i++) {
      final targetDistance = i * desiredSpacing;
      
      // Find the segment containing target distance
      while (currentSegment < contour.length - 1) {
        final segmentLength = GeometryUtils.distanceBetween(
          contour[currentSegment], 
          contour[currentSegment + 1]
        );
        
        if (accumulatedLength + segmentLength >= targetDistance) {
          // Interpolate within this segment
          final t = (targetDistance - accumulatedLength) / segmentLength;
          
          final x = contour[currentSegment].x + 
                   t * (contour[currentSegment + 1].x - contour[currentSegment].x);
          final y = contour[currentSegment].y + 
                   t * (contour[currentSegment + 1].y - contour[currentSegment].y);
          
          result.add(Point(x, y));
          break;
        } else {
          accumulatedLength += segmentLength;
          currentSegment++;
        }
      }
    }
    
    // Add last point
    result.add(contour.last);
    
    return result;
  }

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

}