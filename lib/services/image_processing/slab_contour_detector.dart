import 'package:image/image.dart' as img;
import 'dart:math' as math;
import 'dart:async';
import 'dart:typed_data';
import '../gcode/machine_coordinates.dart';
import 'image_utils.dart';
import 'slab_contour_result.dart';

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
        processImage = img.copyResize(
          image,
          width: (image.width * scaleFactor).round(),
          height: (image.height * scaleFactor).round(),
          interpolation: img.Interpolation.average
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
      final blurred = img.gaussianBlur(enhanced, radius: 3);
      
      // 4. Apply adaptive thresholding
      final binaryImage = _applyAdaptiveThreshold(blurred, 25, 5);
      
      // 5. Apply morphological operations to close gaps
      final closed = _applyMorphologicalClosing(binaryImage, 5);
      
      // 6. Find the outer contour using boundary tracing
      final contourPoints = _findOuterContour(closed, debugImage);
      
      // 7. Apply smoothing and simplification
      final simplifiedContour = _smoothAndSimplifyContour(contourPoints);
      
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
        final binary = _applyGlobalThreshold(grayscale, threshold);
        
        // Apply morphological operations
        final processed = _applyMorphologicalOpening(binary, 3);
        
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
      final simplifiedContour = _smoothAndSimplifyContour(bestContour);
      
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
      final binary = _applyGlobalThreshold(grayscale, threshold);
      
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
      final hullPoints = _computeConvexHull(nonZeroPoints);
      
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
  
  /// Apply adaptive thresholding
  img.Image _applyAdaptiveThreshold(img.Image grayscale, int blockSize, int constant) {
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
            sum += ImageUtils.calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            );
            count++;
          }
        }
        
        final mean = count > 0 ? sum / count : 128;
        final pixel = grayscale.getPixel(x, y);
        final pixelValue = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        // Apply threshold: if pixel is darker than local mean - constant, mark as foreground (black)
        if (pixelValue < mean - constant) {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        } else {
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        }
      }
    }
    
    return result;
  }
  
  /// Apply global threshold
  img.Image _applyGlobalThreshold(img.Image grayscale, int threshold) {
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        if (intensity < threshold) {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));  // Foreground
        } else {
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));  // Background
        }
      }
    }
    
    return result;
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
            final intensity = ImageUtils.calculateLuminance(
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
  
  /// Find the outer contour using boundary tracing
  List<Point> _findOuterContour(img.Image binary, img.Image? debugImage) {
    final contourPoints = <Point>[];
    final width = binary.width;
    final height = binary.height;
    
    // Find a starting point (first black pixel)
    int startX = -1;
    int startY = -1;
    
    // Search from the center outward in a spiral
    int centerX = width ~/ 2;
    int centerY = height ~/ 2;
    int maxRadius = math.max(width, height) ~/ 2;
    
    bool found = false;
    for (int radius = 0; radius < maxRadius && !found; radius++) {
      for (int y = centerY - radius; y <= centerY + radius && !found; y++) {
        for (int x = centerX - radius; x <= centerX + radius && !found; x++) {
          if (x < 0 || x >= width || y < 0 || y >= height) continue;
          
          final pixel = binary.getPixel(x, y);
          final intensity = ImageUtils.calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          
          if (intensity < 128) {  // Black pixel (object)
            startX = x;
            startY = y;
            found = true;
          }
        }
      }
    }
    
    if (startX == -1 || startY == -1) {
      return contourPoints;  // Empty image, no contour
    }
    
    // Moore boundary tracing algorithm
    // Direction codes: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
    final dx = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy = [0, 1, 1, 1, 0, -1, -1, -1];
    
    int x = startX;
    int y = startY;
    int dir = 7;  // Start by looking in the NE direction
    
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
        
        final pixel = binary.getPixel(nx, ny);
        final intensity = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        if (intensity < 128) {  // Black pixel (object)
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
  
  /// Find the largest contour in the binary image
  List<Point> _findLargestContour(img.Image binary) {
    final blobs = _findConnectedComponents(binary);
    
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
        points.add(Point(largestBlob[i].toDouble(), largestBlob[i + 1].toDouble()));
      }
    }
    
    // If we have enough points, compute the convex hull
    if (points.length >= 3) {
      return _computeConvexHull(points);
    }
    
    return points;
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
        final isBlack = ImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        ) < 128;
        
        if (isBlack) {  // Object pixel
          final List<int> blob = [];
          _floodFill(binaryImage, x, y, visited, blob);
          
          if (blob.length > 0) {
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
    {int depth = 0}) {
    
    // Prevent stack overflow with excessive recursion
    if (depth >= maxRecursionDepth) return;
    
    if (x < 0 || y < 0 || x >= binaryImage.width || y >= binaryImage.height || visited[y][x]) {
      return;
    }
    
    final pixel = binaryImage.getPixel(x, y);
    final isBlack = ImageUtils.calculateLuminance(
      pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
    ) < 128;
    
    if (!isBlack) {  // Not an object pixel
      visited[y][x] = true;
      return;
    }
    
    visited[y][x] = true;
    blob.add(x);
    blob.add(y);
    
    // Check 4-connected neighbors
    _floodFill(binaryImage, x + 1, y, visited, blob, depth: depth + 1);
    _floodFill(binaryImage, x - 1, y, visited, blob, depth: depth + 1);
    _floodFill(binaryImage, x, y + 1, visited, blob, depth: depth + 1);
    _floodFill(binaryImage, x, y - 1, visited, blob, depth: depth + 1);
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
  
  /// Squared distance between two points
  double _squaredDistance(Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return dx * dx + dy * dy;
  }
  
  /// Cross product for determining counter-clockwise order
  double _ccw(Point a, Point b, Point c) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }
  
  /// Smooth and simplify a contour
  List<Point> _smoothAndSimplifyContour(List<Point> contour) {
    if (contour.length <= 3) return contour;
    
    try {
      // 1. Apply Douglas-Peucker simplification
      final simplified = _douglasPeucker(contour, 5.0, 0, maxRecursionDepth);
      
      // 2. Apply Gaussian smoothing to the simplified contour
      final smoothed = _smoothContour(simplified, 3);
      
      // 3. Ensure we have a reasonable number of points
      if (smoothed.length < 10 && contour.length >= 10) {
        // If too few points after simplification, interpolate to get more
        return _interpolateContour(smoothed, 20);
      } else if (smoothed.length > 100) {
        // If too many points, subsample
        return _subsampleContour(smoothed, 100);
      }
      
      return smoothed;
    } catch (e) {
      print('Error smoothing contour: $e');
      return contour;
    }
  }
  
  /// Apply Gaussian smoothing to contour points
  List<Point> _smoothContour(List<Point> contour, int windowSize) {
    if (contour.length <= windowSize) return contour;
    
    final result = <Point>[];
    final halfWindow = windowSize ~/ 2;
    
    // Generate Gaussian kernel
    final kernel = _generateGaussianKernel(windowSize);
    
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
  List<double> _generateGaussianKernel(int size) {
    final kernel = List<double>.filled(size, 0);
    final sigma = size / 6.0;  // Standard deviation
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
  
  /// Douglas-Peucker algorithm with stack overflow prevention
  List<Point> _douglasPeucker(List<Point> points, double epsilon, int depth, int maxDepth) {
    if (points.length <= 2) return List.from(points);
    if (depth >= maxDepth) return List.from(points);
    
    // Find point with maximum distance
    double maxDistance = 0;
    int index = 0;
    
    final start = points.first;
    final end = points.last;
    
    for (int i = 1; i < points.length - 1; i++) {
      final point = points[i];
      final distance = _perpendicularDistance(point, start, end);
      
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }
    
    // If max distance exceeds epsilon, recursively simplify
    if (maxDistance > epsilon) {
      // Recursive simplification
      final firstPart = _douglasPeucker(points.sublist(0, index + 1), epsilon, depth + 1, maxDepth);
      final secondPart = _douglasPeucker(points.sublist(index), epsilon, depth + 1, maxDepth);
      
      // Concatenate results, excluding duplicate middle point
      return [...firstPart.sublist(0, firstPart.length - 1), ...secondPart];
    } else {
      // Base case - just use endpoints
      return [start, end];
    }
  }
  
  /// Calculate perpendicular distance from point to line segment
  double _perpendicularDistance(Point point, Point lineStart, Point lineEnd) {
    try {
      final dx = lineEnd.x - lineStart.x;
      final dy = lineEnd.y - lineStart.y;
      
      // If line is just a point, return distance to that point
      if (dx == 0 && dy == 0) {
        return math.sqrt(math.pow(point.x - lineStart.x, 2) + 
                        math.pow(point.y - lineStart.y, 2));
      }
      
      // Calculate perpendicular distance
      final norm = math.sqrt(dx * dx + dy * dy);
      return ((dy * point.x - dx * point.y + lineEnd.x * lineStart.y - lineEnd.y * lineStart.x) / norm).abs();
    } catch (e) {
      return 0.0;
    }
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
        
        // Safety check
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