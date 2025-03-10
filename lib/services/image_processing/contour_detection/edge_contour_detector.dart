import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../gcode/machine_coordinates.dart';
import '../image_utils.dart';
import '../slab_contour_result.dart';
import 'contour_detector_interface.dart';

/// Edge-based contour detector using Canny edge detection
class EdgeContourDetector implements ContourDetectorStrategy {
  final bool generateDebugImage;
  final int processingTimeout;

  EdgeContourDetector({
    this.generateDebugImage = true,
    this.processingTimeout = 5000,
  });

  @override
  String get name => "Edge-Based";

  @override
  Future<SlabContourResult> detectContour(
    img.Image image,
    MachineCoordinateSystem coordSystem
  ) async {
    // Add timeout to detection process
    return await Future.delayed(Duration.zero, () {
      return Future.value(_detectContourInternal(image, coordSystem))
        .timeout(
          Duration(milliseconds: processingTimeout),
          onTimeout: () => throw TimeoutException('Edge contour detection timed out')
        );
    });
  }

  SlabContourResult _detectContourInternal(img.Image image, MachineCoordinateSystem coordSystem) {
    // Create a debug image if needed
    img.Image? debugImage;
    if (generateDebugImage) {
      debugImage = img.copyResize(image, width: image.width, height: image.height);
    }

    try {
      // 1. Convert to grayscale
      final grayscale = ImageUtils.convertToGrayscale(image);
      
      // 2. Apply Gaussian blur to reduce noise
      final blurred = img.gaussianBlur(grayscale, radius: 2);
      
      // 3. Apply Canny edge detection
      final edges = ImageUtils.applyCannyEdgeDetection(blurred, 
        lowThreshold: 30, highThreshold: 100);
      
      // 4. Apply dilation to connect edges
      final dilated = _applyDilation(edges, 2);
      
      // 5. Find contours in the edge image
      final contours = _findContours(dilated);
      
      if (contours.isEmpty) {
        return _createFallbackResult(image, coordSystem, debugImage);
      }
      
      // 6. Select the best contour (largest that fits within the image)
      final bestContour = _selectBestContour(contours, image.width, image.height);
      
      if (bestContour.isEmpty) {
        return _createFallbackResult(image, coordSystem, debugImage);
      }
      
      // 7. Apply smoothing and simplification
      final simplifiedContour = _smoothAndSimplifyContour(bestContour);
      
      // Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(simplifiedContour);
      
      // Visualize on debug image if available
      if (debugImage != null) {
        _visualizeContourOnDebug(debugImage, simplifiedContour, img.ColorRgba8(0, 255, 0, 255), "Edge");
      }
      
      return SlabContourResult(
        pixelContour: simplifiedContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      print('Edge contour detection failed: $e');
      return _createFallbackResult(image, coordSystem, debugImage);
    }
  }

  /// Apply dilation morphological operation
  img.Image _applyDilation(img.Image binary, int kernelSize) {
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
        final intensity = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        // If this is a black pixel (edge)
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

  /// Find contours in a binary edge image
  List<List<Point>> _findContours(img.Image edgeImage) {
    final List<List<Point>> contours = [];
    
    // Create visited map
    final visited = List.generate(
      edgeImage.height, 
      (_) => List.filled(edgeImage.width, false)
    );
    
    // Scan image for edge pixels
    for (int y = 0; y < edgeImage.height; y++) {
      for (int x = 0; x < edgeImage.width; x++) {
        if (visited[y][x]) continue;
        
        final pixel = edgeImage.getPixel(x, y);
        final isEdge = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        ) < 128;
        
        if (isEdge) {
          // Found an edge pixel, trace the contour
          final contour = <Point>[];
          _traceContour(edgeImage, x, y, visited, contour);
          
          if (contour.length > 20) {  // Filter out tiny contours
            contours.add(contour);
          }
        } else {
          visited[y][x] = true;
        }
      }
    }
    
    return contours;
  }

  /// Trace a contour from a starting point using Moore-Neighbor tracing
  void _traceContour(img.Image edgeImage, int startX, int startY, List<List<bool>> visited, List<Point> contour) {
    // 8-connected neighbors direction: E, SE, S, SW, W, NW, N, NE
    final dx = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy = [0, 1, 1, 1, 0, -1, -1, -1];
    
    int x = startX;
    int y = startY;
    int dir = 7; // Start by looking NE
    
    final maxSteps = 5000; // Safety limit
    int steps = 0;
    
    do {
      // Add current point to contour
      if (!visited[y][x]) {
        contour.add(Point(x.toDouble(), y.toDouble()));
        visited[y][x] = true;
      }
      
      // Look for next edge pixel
      bool found = false;
      for (int i = 0; i < 8 && !found; i++) {
        int checkDir = (dir + i) % 8;
        int nx = x + dx[checkDir];
        int ny = y + dy[checkDir];
        
        if (nx < 0 || nx >= edgeImage.width || ny < 0 || ny >= edgeImage.height) continue;
        
        final pixel = edgeImage.getPixel(nx, ny);
        final isEdge = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        ) < 128;
        
        if (isEdge) {
          x = nx;
          y = ny;
          dir = (checkDir + 5) % 8; // Backtrack direction + 1
          found = true;
        }
      }
      
      if (!found) break;
      
      steps++;
      if (steps >= maxSteps) break; // Safety check
      
    } while (x != startX || y != startY);
  }

  /// Select best contour from a list of contours
  List<Point> _selectBestContour(List<List<Point>> contours, int width, int height) {
    if (contours.isEmpty) return [];
    
    // Calculate center of the image
    final centerX = width / 2;
    final centerY = height / 2;
    
    // Sort contours by area size (largest first)
    contours.sort((a, b) => _calculateContourArea(b).compareTo(_calculateContourArea(a)));
    
    // Take the largest contour that contains the center point
    for (final contour in contours) {
      if (_isPointInPolygon(Point(centerX, centerY), contour)) {
        return contour;
      }
    }
    
    // If no contour contains center, take the largest one
    return contours.first;
  }

  /// Calculate approximate area of a contour
  double _calculateContourArea(List<Point> contour) {
    if (contour.length < 3) return 0.0;
    
    double area = 0.0;
    for (int i = 0; i < contour.length - 1; i++) {
      area += contour[i].x * contour[i + 1].y;
      area -= contour[i + 1].x * contour[i].y;
    }
    
    // Add the last segment
    int lastIdx = contour.length - 1;
    area += contour[lastIdx].x * contour[0].y;
    area -= contour[0].x * contour[lastIdx].y;
    
    return area.abs() / 2.0;
  }

  /// Check if a point is inside a polygon
  bool _isPointInPolygon(Point point, List<Point> polygon) {
    bool inside = false;
    int j = polygon.length - 1;
    
    for (int i = 0; i < polygon.length; i++) {
      if (((polygon[i].y > point.y) != (polygon[j].y > point.y)) &&
          (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / 
          (polygon[j].y - polygon[i].y) + polygon[i].x)) {
        inside = !inside;
      }
      j = i;
    }
    
    return inside;
  }

  /// Smooth and simplify a contour
  List<Point> _smoothAndSimplifyContour(List<Point> contour) {
    if (contour.length <= 3) return contour;
    
    // 1. Apply Gaussian smoothing
    final smoothed = _applyGaussianSmoothing(contour, 3);
    
    // 2. Simplify with Douglas-Peucker algorithm
    final simplified = _simplifyContour(smoothed, 5.0);
    
    // 3. Ensure reasonable number of points
    if (simplified.length < 10 && contour.length >= 10) {
      return _interpolateContour(simplified, 20);
    } else if (simplified.length > 100) {
      return _subsampleContour(simplified, 100);
    }
    
    return simplified;
  }

  /// Apply Gaussian smoothing to contour points
  List<Point> _applyGaussianSmoothing(List<Point> contour, int windowSize) {
    if (contour.length <= windowSize) return contour;
    
    final result = <Point>[];
    final halfWindow = windowSize ~/ 2;
    
    // Generate Gaussian kernel
    final kernel = List<double>.filled(windowSize, 0);
    final sigma = windowSize / 6.0;
    
    double sum = 0;
    for (int i = 0; i < windowSize; i++) {
      final x = i - halfWindow;
      kernel[i] = math.exp(-(x * x) / (2 * sigma * sigma));
      sum += kernel[i];
    }
    
    // Normalize kernel
    for (int i = 0; i < windowSize; i++) {
      kernel[i] /= sum;
    }
    
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

  /// Simplify contour using Douglas-Peucker algorithm
  List<Point> _simplifyContour(List<Point> points, double epsilon) {
    if (points.length <= 2) return List.from(points);
    
    double maxDistance = 0;
    int index = 0;
    
    final start = points.first;
    final end = points.last;
    
    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], start, end);
      
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }
    
    if (maxDistance > epsilon) {
      final firstPart = _simplifyContour(points.sublist(0, index + 1), epsilon);
      final secondPart = _simplifyContour(points.sublist(index), epsilon);
      
      return [...firstPart.sublist(0, firstPart.length - 1), ...secondPart];
    } else {
      return [start, end];
    }
  }

  /// Calculate perpendicular distance from point to line segment
  double _perpendicularDistance(Point point, Point lineStart, Point lineEnd) {
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;
    
    if (dx == 0 && dy == 0) {
      return math.sqrt(math.pow(point.x - lineStart.x, 2) + 
                     math.pow(point.y - lineStart.y, 2));
    }
    
    final norm = math.sqrt(dx * dx + dy * dy);
    return ((dy * point.x - dx * point.y + lineEnd.x * lineStart.y - 
                  lineEnd.y * lineStart.x) / norm).abs();
  }

  /// Interpolate contour to increase point count
  List<Point> _interpolateContour(List<Point> contour, int targetCount) {
    if (contour.length >= targetCount) return contour;
    
    final result = <Point>[];
    
    // Close the contour if not already closed
    final isClosed = (contour.length >= 2 && 
      contour.first.x == contour.last.x && contour.first.y == contour.last.y);
    final workingContour = isClosed ? contour : [...contour, contour.first];
    
    // Calculate total perimeter length
    double totalLength = 0;
    for (int i = 0; i < workingContour.length - 1; i++) {
      totalLength += _distanceBetween(workingContour[i], workingContour[i + 1]);
    }
    
    if (totalLength <= 0) {
      return contour; // Can't interpolate
    }
    
    // Calculate segment length for even distribution
    final segmentLength = totalLength / targetCount;
    
    // Start with first point
    result.add(workingContour.first);
    
    double accumulatedLength = 0;
    int currentPoint = 0;
    
    // Interpolate points
    for (int i = 1; i < targetCount; i++) {
      double targetLength = i * segmentLength;
      
      // Find segment containing target length
      while (currentPoint < workingContour.length - 1) {
        double nextLength = accumulatedLength + 
            _distanceBetween(workingContour[currentPoint], workingContour[currentPoint + 1]);
        
        if (nextLength >= targetLength) {
          // Interpolate within this segment
          double t = (targetLength - accumulatedLength) / 
              (nextLength - accumulatedLength);
          
          t = t.clamp(0.0, 1.0); // Ensure t is within valid range
          
          double x = workingContour[currentPoint].x + 
              t * (workingContour[currentPoint + 1].x - workingContour[currentPoint].x);
          double y = workingContour[currentPoint].y + 
              t * (workingContour[currentPoint + 1].y - workingContour[currentPoint].y);
          
          result.add(Point(x, y));
          break;
        }
        
        accumulatedLength = nextLength;
        currentPoint++;
        
        if (currentPoint >= workingContour.length - 1) {
          result.add(workingContour.last);
          break;
        }
      }
    }
    
    return result;
  }

  /// Subsample contour to reduce point count
  List<Point> _subsampleContour(List<Point> contour, int targetCount) {
    if (contour.length <= targetCount) return contour;
    
    final result = <Point>[];
    final step = contour.length / targetCount;
    
    for (int i = 0; i < targetCount; i++) {
      final index = (i * step).floor();
      result.add(contour[math.min(index, contour.length - 1)]);
    }
    
    return result;
  }

  /// Calculate distance between two points
  double _distanceBetween(Point a, Point b) {
    return math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
  }

  /// Visualize contour on debug image
  void _visualizeContourOnDebug(img.Image debugImage, List<Point> contour, img.Color color, String label) {
    // Draw contour
    for (int i = 0; i < contour.length - 1; i++) {
      final p1 = contour[i];
      final p2 = contour[i + 1];
      
      _drawLine(
        debugImage,
        p1.x.round(), p1.y.round(),
        p2.x.round(), p2.y.round(),
        color
      );
    }
    
    // Draw label
    if (contour.isNotEmpty) {
      _drawText(
        debugImage,
        label,
        contour[0].x.round() + 10,
        contour[0].y.round() + 10,
        color
      );
    }
  }

  /// Draw a line between two points
  void _drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
    // Clamp coordinates to image boundaries
    x1 = x1.clamp(0, image.width - 1);
    y1 = y1.clamp(0, image.height - 1);
    x2 = x2.clamp(0, image.width - 1);
    y2 = y2.clamp(0, image.height - 1);
    
    // Bresenham's line algorithm
    int dx = (x2 - x1).abs();
    int dy = (y2 - y1).abs();
    int sx = x1 < x2 ? 1 : -1;
    int sy = y1 < y2 ? 1 : -1;
    int err = dx - dy;
    
    while (true) {
      image.setPixel(x1, y1, color);
      
      if (x1 == x2 && y1 == y2) break;
      
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

  /// Draw text on the image
  void _drawText(img.Image image, String text, int x, int y, img.Color color) {
    // Simple implementation
    for (int i = 0; i < text.length; i++) {
      image.setPixel(x + i * 8, y, color);
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

  /// Create a fallback contour for cases where detection fails
  List<Point> _createFallbackContour(int width, int height) {
    final centerX = width * 0.5;
    final centerY = height * 0.5;
    final radius = math.min(width, height) * 0.3;
    
    final numPoints = 20;
    final contour = <Point>[];
    
    for (int i = 0; i < numPoints; i++) {
      final angle = i * 2 * math.pi / numPoints;
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