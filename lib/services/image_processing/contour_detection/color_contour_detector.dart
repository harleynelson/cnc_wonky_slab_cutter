import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../gcode/machine_coordinates.dart';
import '../image_utils.dart';
import '../slab_contour_result.dart';
import 'contour_detector_interface.dart';

/// Color-based contour detector using HSV color space segmentation
class ColorContourDetector implements ContourDetectorStrategy {
  final bool generateDebugImage;
  final int processingTimeout;

  ColorContourDetector({
    this.generateDebugImage = true,
    this.processingTimeout = 5000,
  });

  @override
  String get name => "Color-Based";

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
          onTimeout: () => throw TimeoutException('Color contour detection timed out')
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
      // 1. Convert to color mask using HSV-based segmentation
      final colorMask = _createWoodColorMask(image);
      
      // 2. Apply morphological operations to clean up the mask
      final cleaned = _applyMorphologicalOperations(colorMask);
      
      // 3. Find the largest connected component (blob)
      final blobs = _findConnectedComponents(cleaned);
      
      if (blobs.isEmpty) {
        return _createFallbackResult(image, coordSystem, debugImage);
      }
      
      // Sort by size and take the largest
      blobs.sort((a, b) => b.length.compareTo(a.length));
      final largestBlob = blobs.first;
      
      // Convert blob to points
      final List<Point> contourPoints = [];
      for (int i = 0; i < largestBlob.length; i += 2) {
        if (i + 1 < largestBlob.length) {
          contourPoints.add(Point(
            largestBlob[i].toDouble(), 
            largestBlob[i + 1].toDouble()
          ));
        }
      }
      
      // Compute convex hull to get a clean contour
      final hullPoints = _computeConvexHull(contourPoints);
      
      // Apply smoothing to create a natural-looking contour
      final smoothedContour = _smoothContour(hullPoints);
      
      // Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(smoothedContour);
      
      // Visualize on debug image if available
      if (debugImage != null) {
        _visualizeContourOnDebug(debugImage, smoothedContour, img.ColorRgba8(0, 255, 0, 255), "Color");
      }
      
      return SlabContourResult(
        pixelContour: smoothedContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      print('Color contour detection failed: $e');
      return _createFallbackResult(image, coordSystem, debugImage);
    }
  }

  /// Create a wood color mask using HSV color space
  img.Image _createWoodColorMask(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);
    
    // Initialize with black (non-wood)
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
      }
    }
    
    // Define color ranges for common wood tones in HSV
    // Ranges from light to dark wood tones
    final List<_HSVRange> woodRanges = [
      // Light woods (maple, birch, ash)
      _HSVRange(hueMin: 15, hueMax: 40, satMin: 0.1, satMax: 0.5, valMin: 0.5, valMax: 1.0),
      
      // Medium woods (oak, cherry)
      _HSVRange(hueMin: 10, hueMax: 30, satMin: 0.2, satMax: 0.7, valMin: 0.3, valMax: 0.7),
      
      // Dark woods (walnut, mahogany)
      _HSVRange(hueMin: 5, hueMax: 25, satMin: 0.2, satMax: 0.8, valMin: 0.1, valMax: 0.5),
      
      // Handle desaturated woods (very light or weathered)
      _HSVRange(hueMin: 0, hueMax: 60, satMin: 0.0, satMax: 0.2, valMin: 0.4, valMax: 0.9),
    ];
    
    // Check each pixel against wood color ranges
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        
        // Convert RGB to HSV
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        final hsv = rgbToHsv(r, g, b);
        final h = hsv[0];
        final s = hsv[1];
        final v = hsv[2];
        
        bool isWood = false;
        for (final range in woodRanges) {
          if (range.contains(h, s, v)) {
            isWood = true;
            break;
          }
        }
        
        if (isWood) {
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // White for wood
        }
      }
    }
    
    return result;
  }

  /// Apply morphological operations to clean up mask
  img.Image _applyMorphologicalOperations(img.Image mask) {
    // First apply closing to fill gaps
    final closed = _applyMorphologicalClosing(mask, 5);
    
    // Then apply opening to remove small noise
    return _applyMorphologicalOpening(closed, 7);
  }

  /// Apply morphological closing (dilation followed by erosion)
  img.Image _applyMorphologicalClosing(img.Image binary, int kernelSize) {
    // First dilate
    final dilated = _applyDilation(binary, kernelSize);
    
    // Then erode
    return _applyErosion(dilated, kernelSize);
  }
  
  /// Apply morphological opening (erosion followed by dilation)
  img.Image _applyMorphologicalOpening(img.Image binary, int kernelSize) {
    // First erode
    final eroded = _applyErosion(binary, kernelSize);
    
    // Then dilate
    return _applyDilation(eroded, kernelSize);
  }
  
  /// Apply dilation morphological operation
  img.Image _applyDilation(img.Image binary, int kernelSize) {
    final result = img.Image(width: binary.width, height: binary.height);
    final halfKernel = kernelSize ~/ 2;
    
    // Initialize with black
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
      }
    }
    
    // Apply dilation
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        final pixel = binary.getPixel(x, y);
        final intensity = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        // If this is a white pixel (wood)
        if (intensity > 128) {
          // Dilate by setting neighbors to white
          for (int j = -halfKernel; j <= halfKernel; j++) {
            for (int i = -halfKernel; i <= halfKernel; i++) {
              final nx = x + i;
              final ny = y + j;
              
              if (nx >= 0 && nx < binary.width && ny >= 0 && ny < binary.height) {
                result.setPixel(nx, ny, img.ColorRgba8(255, 255, 255, 255));
              }
            }
          }
        }
      }
    }
    
    return result;
  }
  
  /// Apply erosion morphological operation
  img.Image _applyErosion(img.Image binary, int kernelSize) {
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
        bool allWhite = true;
        
        // Check if all pixels in kernel are white
        for (int j = -halfKernel; j <= halfKernel && allWhite; j++) {
          for (int i = -halfKernel; i <= halfKernel && allWhite; i++) {
            final nx = x + i;
            final ny = y + j;
            
            if (nx < 0 || nx >= binary.width || ny < 0 || ny >= binary.height) {
              allWhite = false;
              continue;
            }
            
            final pixel = binary.getPixel(nx, ny);
            final intensity = ImageUtils.calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            );
            
            if (intensity <= 128) {  // If any pixel is black (background)
              allWhite = false;
            }
          }
        }
        
        if (!allWhite) {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        }
      }
    }
    
    return result;
  }

  /// Find connected components in binary image
  List<List<int>> _findConnectedComponents(img.Image binaryImage) {
    final List<List<int>> blobs = [];
    
    final visited = List.generate(
      binaryImage.height, 
      (_) => List.filled(binaryImage.width, false)
    );
    
    for (int y = 0; y < binaryImage.height; y++) {
      for (int x = 0; x < binaryImage.width; x++) {
        if (visited[y][x]) continue;
        
        final pixel = binaryImage.getPixel(x, y);
        final isWhite = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        ) > 128;
        
        if (isWhite) {  // Wood pixel
          final List<int> blob = [];
          _floodFill(binaryImage, x, y, visited, blob);
          
          if (blob.length > 20) {  // Filter out tiny blobs
            blobs.add(blob);
          }
        } else {
          visited[y][x] = true;
        }
      }
    }
    
    return blobs;
  }

  /// Flood fill to find connected pixels
  void _floodFill(img.Image binaryImage, int x, int y, List<List<bool>> visited, List<int> blob, 
    {int depth = 0, int maxDepth = 1000}) {
    
    // Prevent stack overflow with excessive recursion
    if (depth >= maxDepth) return;
    
    if (x < 0 || y < 0 || x >= binaryImage.width || y >= binaryImage.height || visited[y][x]) {
      return;
    }
    
    final pixel = binaryImage.getPixel(x, y);
    final isWhite = ImageUtils.calculateLuminance(
      pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
    ) > 128;
    
    if (!isWhite) {  // Not a wood pixel
      visited[y][x] = true;
      return;
    }
    
    visited[y][x] = true;
    blob.add(x);
    blob.add(y);
    
    // Check 4-connected neighbors
    _floodFill(binaryImage, x + 1, y, visited, blob, depth: depth + 1, maxDepth: maxDepth);
    _floodFill(binaryImage, x - 1, y, visited, blob, depth: depth + 1, maxDepth: maxDepth);
    _floodFill(binaryImage, x, y + 1, visited, blob, depth: depth + 1, maxDepth: maxDepth);
    _floodFill(binaryImage, x, y - 1, visited, blob, depth: depth + 1, maxDepth: maxDepth);
  }

  /// Compute convex hull using Graham scan algorithm
  List<Point> _computeConvexHull(List<Point> points) {
    if (points.length <= 3) return List.from(points);
    
    // Find point with lowest y-coordinate (and leftmost if tied)
    int lowestIndex = 0;
    for (int i = 1; i < points.length; i++) {
      if (points[i].y < points[lowestIndex].y || 
          (points[i].y == points[lowestIndex].y && points[i].x < points[lowestIndex].x)) {
        lowestIndex = i;
      }
    }
    
    // Swap lowest point to first position
    final temp = points[0];
    points[0] = points[lowestIndex];
    points[lowestIndex] = temp;
    
    // Sort points by polar angle with respect to the lowest point
    final p0 = points[0];
    points.sort((a, b) {
      if (a == p0) return -1;
      if (b == p0) return 1;
      
      final angleA = math.atan2(a.y - p0.y, a.x - p0.x);
      final angleB = math.atan2(b.y - p0.y, b.x - p0.x);
      
      if (angleA < angleB) return -1;
      if (angleA > angleB) return 1;
      
      // If angles are the same, pick the closer point
      final distA = _squaredDistance(p0, a);
      final distB = _squaredDistance(p0, b);
      return distA.compareTo(distB);
    });
    
    // Build convex hull
    final hull = <Point>[];
    hull.add(points[0]);
    hull.add(points[1]);
    
    for (int i = 2; i < points.length; i++) {
      while (hull.length > 1 && _ccw(hull[hull.length - 2], hull[hull.length - 1], points[i]) <= 0) {
        hull.removeLast();
      }
      hull.add(points[i]);
    }
    
    // Ensure hull is closed
    if (hull.length > 2 && (hull.first.x != hull.last.x || hull.first.y != hull.last.y)) {
      hull.add(hull.first);
    }
    
    return hull;
  }

  /// Smooth a contour with Gaussian kernel
  List<Point> _smoothContour(List<Point> contour) {
    if (contour.length <= 3) return contour;
    
    // Apply Gaussian smoothing
    final smoothed = _applyGaussianSmoothing(contour, 5);
    
    // Simplify with Douglas-Peucker algorithm
    final simplified = _simplifyContour(smoothed, 5.0);
    
    // Ensure reasonable number of points
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

  /// Convert RGB to HSV color space
  List<double> rgbToHsv(int r, int g, int b) {
  // Normalize RGB values to 0-1 range
  final rd = r / 255.0;
  final gd = g / 255.0;
  final bd = b / 255.0;
 
  final max = [rd, gd, bd].reduce(math.max);
  final min = [rd, gd, bd].reduce(math.min);
  final delta = max - min;
 
  // Calculate hue (0-360)
  double h = 0;
  if (delta > 0) {
    if (max == rd) {
      h = ((gd - bd) / delta) % 6;
    } else if (max == gd) {
      h = (bd - rd) / delta + 2;
    } else {
      h = (rd - gd) / delta + 4;
    }
   
    h *= 60;
    if (h < 0) h += 360;
  }
 
  // Calculate saturation (0-1)
  final s = max == 0 ? 0.0 : delta / max;
 
  // Value (0-1)
  final v = max;
 
  return [h, s, v];
}

  /// Calculate distance between two points
  double _distanceBetween(Point a, Point b) {
    return math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
  }

  /// Calculate squared distance between two points
  double _squaredDistance(Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return dx * dx + dy * dy;
  }

  /// Cross product for determining counter-clockwise order
  double _ccw(Point a, Point b, Point c) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
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

/// Helper class for HSV color range checking
class _HSVRange {
  final double hueMin;
  final double hueMax;
  final double satMin;
  final double satMax;
  final double valMin;
  final double valMax;
  
  _HSVRange({
    required this.hueMin,
    required this.hueMax, 
    required this.satMin, 
    required this.satMax, 
    required this.valMin, 
    required this.valMax
  });
  
  bool contains(double h, double s, double v) {
    // Handle hue wrap-around
    bool hueInRange = false;
    if (hueMin <= hueMax) {
      hueInRange = h >= hueMin && h <= hueMax;
    } else {
      hueInRange = h >= hueMin || h <= hueMax;
    }
    
    return hueInRange && 
           s >= satMin && s <= satMax && 
           v >= valMin && v <= valMax;
  }
}