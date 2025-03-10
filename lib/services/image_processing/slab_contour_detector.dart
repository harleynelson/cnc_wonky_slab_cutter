import 'package:image/image.dart' as img;
import 'dart:math' as math;
import '../gcode/machine_coordinates.dart';
import 'image_utils.dart';
import 'slab_contour_result.dart';
import 'dart:async';

/// Detects slab contours in images
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
        // Continue with original image if resize fails
      }
    }
    
    // Create a debug image if needed
    img.Image? debugImage;
    if (generateDebugImage) {
      try {
        debugImage = img.copyResize(processImage, width: processImage.width, height: processImage.height);
      } catch (e) {
        print('Warning: Failed to create debug image: $e');
        // Continue without debug image if creation fails
      }
    }
    
    try {
      // 1. Preprocess the image to enhance the slab edges
      final preprocessed = _preprocessImage(processImage);
      
      // 2. Detect edges
      final edges = _detectEdges(preprocessed);
      
      // 3. Extract contour points
      final pixelContour = _extractContour(edges, debugImage);
      
      // 4. Simplify and smooth the contour
      final simplifiedContour = _simplifyContour(pixelContour);
      
      // 5. Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(simplifiedContour);
      
      return SlabContourResult(
        pixelContour: simplifiedContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
    } catch (e) {
      print('Error in contour detection: $e');
      // Fallback to a generated contour
      return _createFallbackResult(processImage, coordSystem, debugImage);
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
      try {
        for (int i = 0; i < pixelContour.length - 1; i++) {
          final p1 = pixelContour[i];
          final p2 = pixelContour[i + 1];
          
          ImageUtils.drawLine(
            debugImage,
            p1.x.round(), p1.y.round(),
            p2.x.round(), p2.y.round(),
            img.ColorRgba8(255, 0, 0, 255) // Red for fallback
          );
        }
        
        ImageUtils.drawText(
          debugImage,
          "FALLBACK CONTOUR",
          10, 30,
          img.ColorRgba8(255, 0, 0, 255)
        );
      } catch (e) {
        print('Error drawing fallback contour: $e');
      }
    }
    
    return SlabContourResult(
      pixelContour: pixelContour,
      machineContour: machineContour,
      debugImage: debugImage,
    );
  }
  
  /// Preprocess the image to enhance slab detection
  img.Image _preprocessImage(img.Image originalImage) {
    try {
      // Convert to grayscale
      final grayscale = ImageUtils.convertToGrayscale(originalImage);
      
      // Apply gaussian blur to reduce noise
      final blurred = img.gaussianBlur(grayscale, radius: 5);
      
      // Apply histogram equalization to enhance contrast
      return _histogramEqualization(blurred);
    } catch (e) {
      print('Error in preprocessing: $e');
      return ImageUtils.convertToGrayscale(originalImage);
    }
  }
  
  /// Apply histogram equalization to enhance contrast
  img.Image _histogramEqualization(img.Image grayscale) {
    // Create histogram
    final histogram = List<int>.filled(256, 0);
    final equalized = img.Image(width: grayscale.width, height: grayscale.height);
    
    try {
      // Count pixel intensities
      for (int y = 0; y < grayscale.height; y++) {
        for (int x = 0; x < grayscale.width; x++) {
          final pixel = grayscale.getPixel(x, y);
          final intensity = ImageUtils.calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          histogram[intensity.clamp(0, 255)]++;
        }
      }
      
      // Calculate cumulative distribution function (CDF)
      final cdf = List<int>.filled(256, 0);
      cdf[0] = histogram[0];
      for (int i = 1; i < 256; i++) {
        cdf[i] = cdf[i - 1] + histogram[i];
      }
      
      // Normalize CDF to create lookup table
      final totalPixels = grayscale.width * grayscale.height;
      if (totalPixels <= 0 || cdf[255] <= 0) {
        throw Exception('Invalid histogram data');
      }
      
      final lookup = List<int>.filled(256, 0);
      for (int i = 0; i < 256; i++) {
        lookup[i] = ((cdf[i] / cdf[255]) * 255).round().clamp(0, 255);
      }
      
      // Apply lookup to create equalized image
      for (int y = 0; y < grayscale.height; y++) {
        for (int x = 0; x < grayscale.width; x++) {
          final pixel = grayscale.getPixel(x, y);
          final intensity = ImageUtils.calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          ).clamp(0, 255);
          final newIntensity = lookup[intensity];
          equalized.setPixel(x, y, img.ColorRgba8(
            newIntensity, newIntensity, newIntensity, 255
          ));
        }
      }
      
      return equalized;
    } catch (e) {
      print('Error in histogram equalization: $e');
      return grayscale;
    }
  }
  
  /// Detect edges in the preprocessed image
  img.Image _detectEdges(img.Image preprocessed) {
    try {
      // Use Sobel edge detection
      final edges = img.sobel(preprocessed);
      
      // Apply threshold to create binary edge image
      final binaryEdges = img.Image(width: edges.width, height: edges.height);
      
      // Calculate appropriate threshold (Otsu's method would be ideal)
      // For simplicity, we'll use a fixed threshold
      final threshold = 50;
      
      for (int y = 0; y < edges.height; y++) {
        for (int x = 0; x < edges.width; x++) {
          final pixel = edges.getPixel(x, y);
          final intensity = ImageUtils.calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          
          if (intensity > threshold) {
            binaryEdges.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // Edge
          } else {
            binaryEdges.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255)); // Non-edge
          }
        }
      }
      
      return binaryEdges;
    } catch (e) {
      print('Error in edge detection: $e');
      return preprocessed; // Return original if edge detection fails
    }
  }
  
  /// Extract contour points from the edge image
  List<Point> _extractContour(img.Image edgeImage, img.Image? debugImage) {
    try {
      // Find the largest connected component (blob) in the edge image
      final blobs = _findContourBlobs(edgeImage);
      
      // Sort blobs by size (number of pixels)
      blobs.sort((a, b) => b.length.compareTo(a.length));
      
      // If no blobs found, return fallback contour
      if (blobs.isEmpty) {
        return _createFallbackContour(edgeImage.width, edgeImage.height);
      }
      
      // Get the largest blob (likely the slab contour)
      final largestBlob = blobs.first;
      
      // Convert blob pixels to Point objects
      final contourPoints = <Point>[];
      for (int i = 0; i < largestBlob.length; i += 2) {
        if (i + 1 < largestBlob.length) {
          final x = largestBlob[i].toDouble();
          final y = largestBlob[i + 1].toDouble();
          contourPoints.add(Point(x, y));
          
          // Draw detected points on debug image
          if (debugImage != null) {
            try {
              if (x >= 0 && x < debugImage.width && y >= 0 && y < debugImage.height) {
                debugImage.setPixel(x.toInt(), y.toInt(), ImageUtils.colorGreen);
              }
            } catch (e) {
              // Skip visualization on error
            }
          }
        }
      }
      
      // If we didn't find enough points, return fallback
      if (contourPoints.length < 10) {
        return _createFallbackContour(edgeImage.width, edgeImage.height);
      }
      
      return contourPoints;
    } catch (e) {
      print('Error extracting contour: $e');
      return _createFallbackContour(edgeImage.width, edgeImage.height);
    }
  }
  
  /// Find contour blobs in the edge image
  List<List<int>> _findContourBlobs(img.Image edgeImage) {
    final List<List<int>> blobs = [];
    
    try {
      final visited = List.generate(
        edgeImage.height, 
        (_) => List.filled(edgeImage.width, false)
      );
      
      // Find outer contour (white pixels)
      for (int y = 0; y < edgeImage.height; y++) {
        for (int x = 0; x < edgeImage.width; x++) {
          if (visited[y][x]) continue;
          
          try {
            final pixel = edgeImage.getPixel(x, y);
            final isEdge = ImageUtils.calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            ) > 127;
            
            if (isEdge) {
              final List<int> blob = [];
              _floodFill(edgeImage, x, y, visited, blob);
              if (blob.isNotEmpty) {
                blobs.add(blob);
              }
            } else {
              visited[y][x] = true;
            }
          } catch (e) {
            visited[y][x] = true;
          }
        }
      }
    } catch (e) {
      print('Error finding contour blobs: $e');
    }
    
    return blobs;
  }
  
  /// Flood fill to find connected edge pixels
  void _floodFill(img.Image edgeImage, int x, int y, List<List<bool>> visited, List<int> blob, 
    {int depth = 0}) {
    
    // Prevent stack overflow with excessive recursion
    if (depth >= maxRecursionDepth) return;
    
    if (x < 0 || y < 0 || x >= edgeImage.width || y >= edgeImage.height || visited[y][x]) {
      return;
    }
    
    try {
      final pixel = edgeImage.getPixel(x, y);
      final isEdge = ImageUtils.calculateLuminance(
        pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
      ) > 127;
      
      if (!isEdge) {
        visited[y][x] = true;
        return;
      }
    } catch (e) {
      visited[y][x] = true;
      return;
    }
    
    visited[y][x] = true;
    blob.add(x);
    blob.add(y);
    
    // Check 4-connected neighbors (reduced from 8 to prevent stack overflow)
    _floodFill(edgeImage, x + 1, y, visited, blob, depth: depth + 1);
    _floodFill(edgeImage, x - 1, y, visited, blob, depth: depth + 1);
    _floodFill(edgeImage, x, y + 1, visited, blob, depth: depth + 1);
    _floodFill(edgeImage, x, y - 1, visited, blob, depth: depth + 1);
  }
  
  /// Simplify contour using Douglas-Peucker algorithm
  List<Point> _simplifyContour(List<Point> contour) {
    if (contour.length <= 2) return contour;
    
    try {
      // Apply Douglas-Peucker simplification
      final simplified = _douglasPeucker(contour, 5.0, 0); // Epsilon=5.0 pixels
      
      // Ensure we have a reasonable number of points
      if (simplified.length < 10) {
        // If too few points, interpolate to get smoother contour
        return _interpolateContour(simplified, 20);
      } else if (simplified.length > 100) {
        // If too many points, subsample
        return _subsampleContour(simplified, 100);
      }
      
      return simplified;
    } catch (e) {
      print('Error simplifying contour: $e');
      // Return original contour if simplification fails
      return contour;
    }
  }
  
  /// Douglas-Peucker algorithm with stack overflow prevention
  List<Point> _douglasPeucker(List<Point> points, double epsilon, int depth) {
    if (points.length <= 2) return List.from(points);
    if (depth >= maxRecursionDepth) return List.from(points);
    
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
      final firstPart = _douglasPeucker(points.sublist(0, index + 1), epsilon, depth + 1);
      final secondPart = _douglasPeucker(points.sublist(index), epsilon, depth + 1);
      
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
      print('Error calculating perpendicular distance: $e');
      return 0.0;
    }
  }
  
  /// Interpolate contour to increase point count
  List<Point> _interpolateContour(List<Point> contour, int targetCount) {
    if (contour.length >= targetCount) return contour;
    
    try {
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
    } catch (e) {
      print('Error interpolating contour: $e');
      return contour;
    }
  }
  
  /// Subsample contour to reduce point count
  List<Point> _subsampleContour(List<Point> contour, int targetCount) {
    if (contour.length <= targetCount) return contour;
    
    try {
      final result = <Point>[];
      final step = contour.length / targetCount;
      
      for (int i = 0; i < targetCount; i++) {
        final index = (i * step).floor();
        result.add(contour[math.min(index, contour.length - 1)]);
      }
      
      return result;
    } catch (e) {
      print('Error subsampling contour: $e');
      return contour;
    }
  }
  
  /// Calculate distance between two points
  double _distanceBetween(Point a, Point b) {
    return math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
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