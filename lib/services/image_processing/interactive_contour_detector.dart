// lib/services/image_processing/interactive_contour_detector.dart
// Interactive contour detection service with user-guided seed point

import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../gcode/machine_coordinates.dart';
import 'slab_contour_result.dart';

/// Service class for interactive contour detection based on a user-selected seed point
class InteractiveContourDetector {
  /// Parameters for contour detection
  final int threshold;
  final double simplificationEpsilon;
  final bool generateDebugImage;
  
  InteractiveContourDetector({
    this.threshold = 30,
    this.simplificationEpsilon = 2.0,
    this.generateDebugImage = true,
  });
  
  /// Detect contour starting from a user-provided seed point
  Future<SlabContourResult> detectContour(
    img.Image image,
    int seedX,
    int seedY,
    MachineCoordinateSystem coordSystem
  ) async {
    try {
      // Create a working copy of the image
      final workingImage = img.copyResize(image, width: image.width, height: image.height);
      
      // Perform region growing from the seed point
      final mask = _regionGrow(image, seedX, seedY, threshold: threshold);
      
      // Find contour pixels from the mask
      final contourPixels = _findContourPixels(mask);
      
      // Convert to Point objects
      final contourPoints = contourPixels.map((p) => Point(p[0].toDouble(), p[1].toDouble())).toList();
      
      // Smooth and simplify contour
      final smoothedContour = _smoothAndSimplifyContour(contourPoints);
      
      // Make sure the contour is closed
      if (smoothedContour.isNotEmpty && 
          (smoothedContour.first.x != smoothedContour.last.x || 
           smoothedContour.first.y != smoothedContour.last.y)) {
        smoothedContour.add(smoothedContour.first);
      }
      
      // Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(smoothedContour);
      
      // Create debug image if requested
      img.Image? debugImage;
      if (generateDebugImage) {
        debugImage = _createDebugImage(workingImage, smoothedContour, seedX, seedY);
      }
      
      // Create and return the result
      return SlabContourResult(
        pixelContour: smoothedContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      // Re-throw with a more descriptive message
      throw Exception('Interactive contour detection failed: $e');
    }
  }
  
  /// Region growing algorithm for segmentation
  List<List<bool>> _regionGrow(img.Image image, int seedX, int seedY, {int threshold = 30}) {
    final width = image.width;
    final height = image.height;
    
    // Create empty mask
    final mask = List.generate(height, (_) => List.filled(width, false));
    
    // Get seed pixel color
    final seedPixel = image.getPixel(seedX, seedY);
    final seedR = seedPixel.r.toInt();
    final seedG = seedPixel.g.toInt();
    final seedB = seedPixel.b.toInt();
    
    // Queue for breadth-first traversal
    final queue = <List<int>>[];
    queue.add([seedX, seedY]);
    mask[seedY][seedX] = true;
    
    // Directions for 4-connectivity
    final dx = [0, 1, 0, -1];
    final dy = [-1, 0, 1, 0];
    
    while (queue.isNotEmpty) {
      final point = queue.removeAt(0);
      final x = point[0];
      final y = point[1];
      
      // Check neighbors
      for (int i = 0; i < 4; i++) {
        final nx = x + dx[i];
        final ny = y + dy[i];
        
        // Skip if out of bounds or already visited
        if (nx < 0 || nx >= width || ny < 0 || ny >= height || mask[ny][nx]) {
          continue;
        }
        
        // Check color similarity
        final pixel = image.getPixel(nx, ny);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        final colorDiff = _colorDistance(seedR, seedG, seedB, r, g, b);
        
        if (colorDiff <= threshold) {
          mask[ny][nx] = true;
          queue.add([nx, ny]);
        }
      }
    }
    
    return mask;
  }

  /// Calculate color distance (simplified version using average of RGB differences)
  int _colorDistance(int r1, int g1, int b1, int r2, int g2, int b2) {
    return ((r1 - r2).abs() + (g1 - g2).abs() + (b1 - b2).abs()) ~/ 3;
  }

  /// Find contour pixels from a binary mask
  List<List<int>> _findContourPixels(List<List<bool>> mask) {
    final height = mask.length;
    final width = mask[0].length;
    final contour = <List<int>>[];
    
    // Direction arrays for 8-connectivity
    final dx = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy = [0, 1, 1, 1, 0, -1, -1, -1];
    
    // Find boundary pixels
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (!mask[y][x]) continue;
        
        // Check if this is a boundary pixel
        bool isBoundary = false;
        for (int i = 0; i < 8; i++) {
          final nx = x + dx[i];
          final ny = y + dy[i];
          
          if (nx < 0 || nx >= width || ny < 0 || ny >= height || !mask[ny][nx]) {
            isBoundary = true;
            break;
          }
        }
        
        if (isBoundary) {
          contour.add([x, y]);
        }
      }
    }
    
    // Sort contour points for a coherent path
    return _sortContourPoints(contour);
  }

  /// Sort contour points to form a coherent path
  List<List<int>> _sortContourPoints(List<List<int>> points) {
    if (points.length <= 1) return points;
    
    final result = <List<int>>[];
    final visited = List.filled(points.length, false);
    
    // Start with the first point
    result.add(points[0]);
    visited[0] = true;
    
    // Find the next closest point repeatedly
    for (int i = 0; i < points.length - 1; i++) {
      final current = result.last;
      int bestIdx = -1;
      int bestDistance = 0x7FFFFFFF;
      
      for (int j = 0; j < points.length; j++) {
        if (visited[j]) continue;
        
        final dx = current[0] - points[j][0];
        final dy = current[1] - points[j][1];
        final distance = dx * dx + dy * dy;
        
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIdx = j;
        }
      }
      
      if (bestIdx != -1) {
        result.add(points[bestIdx]);
        visited[bestIdx] = true;
      }
    }
    
    return result;
  }

  /// Smooth and simplify the contour points
  List<Point> _smoothAndSimplifyContour(List<Point> contour) {
    if (contour.length <= 3) return contour;
    
    // 1. Apply Douglas-Peucker algorithm for simplification
    final simplified = _douglasPeucker(contour, simplificationEpsilon);
    
    // 2. Apply Gaussian smoothing to the simplified contour
    final smoothed = _applyGaussianSmoothing(simplified, 3);
    
    // 3. Ensure reasonable number of points
    if (smoothed.length < 10 && contour.length >= 10) {
      return _interpolateContour(smoothed, 20);
    } else if (smoothed.length > 100) {
      return _subsampleContour(smoothed, 100);
    }
    
    return smoothed;
  }

  /// Douglas-Peucker line simplification algorithm
  List<Point> _douglasPeucker(List<Point> points, double epsilon, {int startIdx = 0, int endIdx = -1}) {
    if (endIdx == -1) endIdx = points.length - 1;
    
    if (endIdx - startIdx <= 1) {
      return [points[startIdx], points[endIdx]];
    }
    
    // Find the point with the maximum distance
    double maxDist = 0;
    int maxIdx = startIdx;
    
    final startPoint = points[startIdx];
    final endPoint = points[endIdx];
    
    for (int i = startIdx + 1; i < endIdx; i++) {
      final dist = _perpendicularDistance(points[i], startPoint, endPoint);
      
      if (dist > maxDist) {
        maxDist = dist;
        maxIdx = i;
      }
    }
    
    // If max distance is greater than epsilon, recursively simplify
    if (maxDist > epsilon) {
      // Recursively simplify the two segments
      final firstPart = _douglasPeucker(points, epsilon, startIdx: startIdx, endIdx: maxIdx);
      final secondPart = _douglasPeucker(points, epsilon, startIdx: maxIdx, endIdx: endIdx);
      
      // Combine the results, removing the duplicate point
      return [...firstPart.sublist(0, firstPart.length - 1), ...secondPart];
    } else {
      // Otherwise, just use the endpoints
      return [startPoint, endPoint];
    }
  }

  /// Calculate perpendicular distance from a point to a line segment
  double _perpendicularDistance(Point point, Point lineStart, Point lineEnd) {
    if (lineStart.x == lineEnd.x && lineStart.y == lineEnd.y) {
      return math.sqrt(
        math.pow(point.x - lineStart.x, 2) + math.pow(point.y - lineStart.y, 2)
      );
    }
    
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;
    final mag = math.sqrt(dx * dx + dy * dy);
    
    return ((dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / mag).abs();
  }

  /// Apply Gaussian smoothing to contour points
  List<Point> _applyGaussianSmoothing(List<Point> contour, int windowSize) {
    if (contour.length <= windowSize) return contour;
    
    final result = <Point>[];
    final halfWindow = windowSize ~/ 2;
    
    // Gaussian kernel weights
    final kernel = <double>[];
    final sigma = windowSize / 6.0;
    double sum = 0.0;
    
    for (int i = -halfWindow; i <= halfWindow; i++) {
      final weight = math.exp(-(i * i) / (2 * sigma * sigma));
      kernel.add(weight);
      sum += weight;
    }
    
    // Normalize weights
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

  /// Interpolate points along the contour to increase density
  List<Point> _interpolateContour(List<Point> contour, int targetCount) {
    if (contour.length >= targetCount) return contour;
    
    final result = <Point>[];
    
    // Calculate total path length
    double totalLength = 0;
    for (int i = 0; i < contour.length - 1; i++) {
      totalLength += _distanceBetween(contour[i], contour[i + 1]);
    }
    
    // Close the loop if needed
    if (contour.first.x != contour.last.x || contour.first.y != contour.last.y) {
      totalLength += _distanceBetween(contour.last, contour.first);
    }
    
    // Calculate segment length for even distribution
    final segmentLength = totalLength / targetCount;
    
    double currentDistance = 0;
    result.add(contour[0]);
    
    for (int i = 1; i < contour.length; i++) {
      final prevPoint = contour[i - 1];
      final currentPoint = contour[i];
      final segmentDistance = _distanceBetween(prevPoint, currentPoint);
      
      // Add interpolated points within this segment
      double distanceAlongSegment = 0;
      while (currentDistance + distanceAlongSegment + segmentLength < segmentDistance) {
        distanceAlongSegment += segmentLength;
        
        // Interpolate a new point
        final t = distanceAlongSegment / segmentDistance;
        final x = prevPoint.x + t * (currentPoint.x - prevPoint.x);
        final y = prevPoint.y + t * (currentPoint.y - prevPoint.y);
        
        result.add(Point(x, y));
      }
      
      // Add the current point
      result.add(currentPoint);
      
      // Update the distance
      currentDistance = (currentDistance + segmentDistance) % segmentLength;
    }
    
    return result;
  }

  /// Subsample points to reduce density
  List<Point> _subsampleContour(List<Point> contour, int targetCount) {
    if (contour.length <= targetCount) return contour;
    
    final result = <Point>[];
    final step = contour.length / targetCount;
    
    for (int i = 0; i < targetCount; i++) {
      final idx = (i * step).floor();
      result.add(contour[idx]);
    }
    
    // Ensure the last point connects back to the first for a closed contour
    if (result.isNotEmpty && result.first != result.last) {
      result.add(result.first);
    }
    
    return result;
  }

  /// Calculate distance between two points
  double _distanceBetween(Point a, Point b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Create a debug image with contour and seed point visualization
  img.Image _createDebugImage(img.Image original, List<Point> contour, int seedX, int seedY) {
    // Create a copy of the original image
    final debugImage = img.copyResize(original, width: original.width, height: original.height);
    
    // Draw the contour
    _drawContourOnImage(debugImage, contour);
    
    // Draw the seed point
    _drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255)); // Yellow
    
    return debugImage;
  }

  /// Draw contour on the image
  void _drawContourOnImage(img.Image image, List<Point> contour) {
    if (contour.isEmpty) return;
    
    for (int i = 0; i < contour.length - 1; i++) {
      _drawLine(
        image, 
        contour[i].x.round(), contour[i].y.round(), 
        contour[i + 1].x.round(), contour[i + 1].y.round(), 
        img.ColorRgba8(0, 255, 0, 255) // Green
      );
    }
    
    // Close the contour if needed
    if (contour.length > 1 && (contour.first.x != contour.last.x || contour.first.y != contour.last.y)) {
      _drawLine(
        image, 
        contour.last.x.round(), contour.last.y.round(), 
        contour.first.x.round(), contour.first.y.round(), 
        img.ColorRgba8(0, 255, 0, 255) // Green
      );
    }
  }

  /// Draw a line on the image
  void _drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
    // Bresenham's line algorithm
    int dx = (x2 - x1).abs();
    int dy = (y2 - y1).abs();
    int sx = (x1 < x2) ? 1 : -1;
    int sy = (y1 < y2) ? 1 : -1;
    int err = dx - dy;
    
    while (true) {
      // Set pixel if within bounds
      if (x1 >= 0 && x1 < image.width && y1 >= 0 && y1 < image.height) {
        image.setPixel(x1, y1, color);
      }
      
      // Break if we've reached the end point
      if (x1 == x2 && y1 == y2) break;
      
      // Calculate next pixel
      int e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x1 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y1 += sy;
      }
    }
  }

  /// Draw a circle on the image
  void _drawCircle(img.Image image, int x, int y, int radius, img.Color color) {
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy <= radius * radius) {
          final px = x + dx;
          final py = y + dy;
          
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, color);
          }
        }
      }
    }
  }
}