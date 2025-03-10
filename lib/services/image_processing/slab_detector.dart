import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';

import '../gcode/machine_coordinates.dart';
import '../gcode/gcode_generator.dart';
import 'marker_detector.dart';
import 'slab_contour_detector.dart';
import 'slab_contour_result.dart';
import '../../models/settings_model.dart';

/// Result of the slab processing operation
class SlabProcessingResult {
  final File processedImage;
  final File gcodeFile;
  final List<Point> slabContour;
  final List<Point> toolpath;
  final double? contourAreaMm2;

  SlabProcessingResult({
    required this.processedImage,
    required this.gcodeFile,
    required this.slabContour,
    required this.toolpath,
    this.contourAreaMm2,
  });
  
  /// Dispose of resources when no longer needed
  Future<void> dispose() async {
    // Close file handles if they're still open
    try {
      await processedImage.exists().then((exists) {
        if (exists) {
          // The file exists and can be safely used
        }
      });
      
      await gcodeFile.exists().then((exists) {
        if (exists) {
          // The file exists and can be safely used
        }
      });
    } catch (e) {
      print('Error disposing SlabProcessingResult: $e');
    }
  }
}

/// Class for detecting slab outlines in images and generating toolpaths
class SlabDetector {
  final SettingsModel settings;
  final int processingTimeout;
  final int maxImageSize;
  
  SlabDetector({
    required this.settings,
    this.processingTimeout = 30000,  // 30 second timeout
    this.maxImageSize = 1200,        // Max image dimension
  });
  
  /// Process an image to detect slab outline and generate G-code
  Future<SlabProcessingResult> processImage(File imageFile) async {
    // Create a timeout for the entire processing operation
    return await Future.delayed(Duration.zero, () {
      return Future.value(_processImageWithTimeout(imageFile))
        .timeout(
          Duration(milliseconds: processingTimeout),
          onTimeout: () => throw TimeoutException('Processing timed out after ${processingTimeout}ms')
        );
    });
  }
  
  Future<SlabProcessingResult> _processImageWithTimeout(File imageFile) async {
    try {
      // Read image data before passing to isolate
      final bytes = await imageFile.readAsBytes();
      
      // Don't use compute for web platform since isolates work differently there
      if (kIsWeb) {
        return _processImageDirect(bytes, settings);
      }
      
      // On mobile, try to use an isolate but with error handling
      try {
        return await compute(_processImageIsolate, {
          'imageBytes': bytes,
          'settings': {
            'cncWidth': settings.cncWidth,
            'cncHeight': settings.cncHeight,
            'markerXDistance': settings.markerXDistance,
            'markerYDistance': settings.markerYDistance,
            'toolDiameter': settings.toolDiameter,
            'stepover': settings.stepover,
            'safetyHeight': settings.safetyHeight,
            'feedRate': settings.feedRate,
            'plungeRate': settings.plungeRate,
            'cuttingDepth': settings.cuttingDepth,
          },
          'maxImageSize': maxImageSize,
        });
      } catch (isolateError) {
        // If isolate fails, log the error and fall back to direct processing
        print('Isolate processing failed: $isolateError');
        return _processImageDirect(bytes, settings);
      }
    } catch (e, stackTrace) {
      // Create a user-friendly error message that can be copied
      final errorMessage = 'Error processing image: ${e.toString()}\n$stackTrace';
      print(errorMessage);
      
      // Rethrow with a more detailed message
      throw Exception(errorMessage);
    }
  }
  
  /// Process the image directly in the main isolate (fallback method)
  Future<SlabProcessingResult> _processImageDirect(List<int> bytes, SettingsModel settings) async {
    print('Processing image directly (no isolate)');
    
    // Decode the image
    final image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) {
      throw Exception('Failed to decode image - invalid format or corrupted file');
    }

    print('Image dimensions: ${image.width}x${image.height}');
    
    // Resize large images to conserve memory
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
        print('Resized Image dimensions: ${image.width}x${image.height}');
      } catch (e) {
        print('Warning: Failed to resize image: $e');
        processImage = image;
      }
      
    }
    
    // Create a copy for visualization
    final outputImage = img.copyResize(processImage, width: processImage.width, height: processImage.height);
    
    // 1. Detect markers with the improved marker detector
    final markerDetector = MarkerDetector(
      markerRealDistanceMm: settings.markerXDistance,
      generateDebugImage: true,
      maxImageSize: maxImageSize,
    );
    
    print('Detecting markers...');
    final markerResult = await markerDetector.detectMarkers(processImage);
    
    // Create coordinate system from marker detection
    final coordinateSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
      markerResult.markers[0].toPoint(),  // Origin
      markerResult.markers[1].toPoint(),  // X-axis
      markerResult.markers[2].toPoint(),  // Scale/Y-axis
      settings.markerXDistance,
      settings.markerYDistance
    );
    
    
    // If we have debug information from marker detection, copy to output
    if (markerResult.debugImage != null) {
      try {
        // Overlay marker detection debug info on the output image
        _overlayDebugImage(outputImage, markerResult.debugImage!);
      } catch (e) {
        print('Error overlaying marker debug image: $e');
      }
    }
    
    // 2. Detect slab contour with the improved contour detector
    final contourDetector = SlabContourDetector(
      generateDebugImage: true,
      maxImageSize: maxImageSize,
      processingTimeout: 20000, // Extended timeout for more thorough processing
    );
    
    print('Detecting slab contour...');
    final contourResult = await contourDetector.detectContour(processImage, coordinateSystem);
    
    // Post-process the contour to ensure we get a clean outline
    final cleanedContour = _ensureCleanOuterContour(contourResult.machineContour);

    
    
    // If we have debug information from contour detection, copy to output
    if (contourResult.debugImage != null) {
      try {
        // Overlay contour detection debug info
        _overlayDebugImage(outputImage, contourResult.debugImage!, greenOnly: true);
      } catch (e) {
        print('Error overlaying contour debug image: $e');
      }
    }
    
    // Draw machine contour on output image
    final machineContourPixels = coordinateSystem.convertPointListToPixelCoords(cleanedContour);
    
    try {
      for (int i = 0; i < machineContourPixels.length - 1; i++) {
        final p1 = machineContourPixels[i];
        final p2 = machineContourPixels[i + 1];
        
        _drawLine(
          outputImage,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          img.ColorRgba8(0, 255, 0, 255) // Green
        );
      }
    } catch (e) {
      print('Error drawing machine contour: $e');
    }
    
    // 3. Generate toolpath - use the cleaned contour
    print('Generating toolpath...');
    final toolpath = _generateOptimizedToolpath(
      cleanedContour,
      settings.toolDiameter,
      settings.stepover,
    );
    
    try {
      // Draw toolpath on output image
      final toolpathPixels = coordinateSystem.convertPointListToPixelCoords(toolpath);
      
      for (int i = 0; i < toolpathPixels.length - 1; i++) {
        final p1 = toolpathPixels[i];
        final p2 = toolpathPixels[i + 1];
        
        _drawLine(
          outputImage,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          img.ColorRgba8(0, 0, 255, 255) // Blue
        );
      }
    } catch (e) {
      print('Error drawing toolpath: $e');
    }

    print('Contour points: ${cleanedContour.length}');
    print('Toolpath points: ${toolpath.length}');
    
    // 4. Generate G-code
    print('Generating G-code...');
    final gcodeGenerator = GcodeGenerator(
      safetyHeight: settings.safetyHeight,
      feedRate: settings.feedRate,
      plungeRate: settings.plungeRate,
      cuttingDepth: settings.cuttingDepth,
    );
    
    final gcodeContent = gcodeGenerator.generateGcode(toolpath);
    
    try {
      // Add metadata and statistics to output image
      _drawText(
        outputImage, 
        "Area: ${_calculatePolygonArea(cleanedContour).toStringAsFixed(2)} sq mm", 
        10, 
        10, 
        img.ColorRgba8(255, 255, 255, 255)
      );
      
      _drawText(
        outputImage, 
        "Toolpath length: ${_calculatePathLength(toolpath).toStringAsFixed(2)} mm", 
        10, 
        30, 
        img.ColorRgba8(255, 255, 255, 255)
      );
    } catch (e) {
      print('Error drawing metadata: $e');
    }
    
    // Save processed image
    File processedImageFile;
    File gcodeFile;
    
    try {
      final tempDir = await getTemporaryDirectory();
      final processedImagePath = path.join(tempDir.path, 'processed_image.png');
      processedImageFile = File(processedImagePath);
      
      // Use try-with-resources pattern for file operations
      final imageData = img.encodePng(outputImage);
      await processedImageFile.writeAsBytes(imageData);
      
      // Save G-code to file
      final gcodePath = path.join(tempDir.path, 'slab_surfacing.gcode');
      gcodeFile = File(gcodePath);
      await gcodeFile.writeAsString(gcodeContent);
    } catch (e) {
      throw Exception('Error saving output files: $e');
    }
    
    return SlabProcessingResult(
      processedImage: processedImageFile,
      gcodeFile: gcodeFile,
      slabContour: cleanedContour,
      toolpath: toolpath,
      contourAreaMm2: _calculatePolygonArea(cleanedContour),
    );
  }
  
  /// Overlay debug visualization from one image onto another
  void _overlayDebugImage(img.Image target, img.Image source, {bool greenOnly = false}) {
    if (target.width != source.width || target.height != source.height) {
      print('Warning: Debug image dimensions do not match output image');
      return;
    }
    
    for (int y = 0; y < source.height; y++) {
      for (int x = 0; x < source.width; x++) {
        if (x >= 0 && x < target.width && y >= 0 && y < target.height) {
          try {
            final debugPixel = source.getPixel(x, y);
            
            if (greenOnly) {
              // Only copy green pixels (contour visualization)
              if (debugPixel.g > 100 && debugPixel.r < 100 && debugPixel.b < 100) {
                target.setPixel(x, y, debugPixel);
              }
            } else {
              // Only copy non-black pixels (markers and visualizations)
              final intensity = (debugPixel.r + debugPixel.g + debugPixel.b) ~/ 3;
              if (intensity > 20) {
                target.setPixel(x, y, debugPixel);
              }
            }
          } catch (e) {
            // Skip this pixel if there's an error
            continue;
          }
        }
      }
    }
  }
  
  /// Calculate total length of a toolpath
  double _calculatePathLength(List<Point> path) {
    double length = 0.0;
    
    try {
      for (int i = 0; i < path.length - 1; i++) {
        final dx = path[i + 1].x - path[i].x;
        final dy = path[i + 1].y - path[i].y;
        length += math.sqrt(dx * dx + dy * dy);
      }
    } catch (e) {
      print('Error calculating path length: $e');
    }
    
    return length;
  }
  
  /// Draw a line between two points
  void _drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
    // Validate coordinates
    if (x1 < 0 || x1 >= image.width || y1 < 0 || y1 >= image.height ||
        x2 < 0 || x2 >= image.width || y2 < 0 || y2 >= image.height) {
      // Clip line to image boundaries
      // Simple approach: just return if any coordinate is outside
      // A more sophisticated approach would clip the line, but that's more complex
      return;
    }
    
    try {
      // Bresenham's line algorithm
      int dx = (x2 - x1).abs();
      int dy = (y2 - y1).abs();
      int sx = x1 < x2 ? 1 : -1;
      int sy = y1 < y2 ? 1 : -1;
      int err = dx - dy;
      
      while (true) {
        if (x1 >= 0 && x1 < image.width && y1 >= 0 && y1 < image.height) {
          image.setPixel(x1, y1, color);
        }
        
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
    } catch (e) {
      print('Error drawing line: $e');
    }
  }
  
  /// Draw text on the image (simplified implementation)
  void _drawText(img.Image image, String text, int x, int y, img.Color color) {
    // A basic implementation of text rendering
    // In a real app, you would use a proper font renderer
    final textWidth = text.length * 6;
    final textHeight = 12;
    
    try {
      // Draw a background for better readability
      for (int py = y - 1; py < y + textHeight + 1; py++) {
        for (int px = x - 1; px < x + textWidth + 1; px++) {
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, img.ColorRgba8(0, 0, 0, 200));
          }
        }
      }
      
      // Simple pixel-based font (just a proof of concept)
      for (int i = 0; i < text.length; i++) {
        final char = text.codeUnitAt(i);
        
        // Draw a simple pixel representation of the character
        final charX = x + i * 6;
        
        if (charX + 5 >= image.width) break;
        
        for (int py = 0; py < 8; py++) {
          for (int px = 0; px < 5; px++) {
            if (_getCharPixel(char, px, py)) {
              final screenX = charX + px;
              final screenY = y + py;
              
              if (screenX >= 0 && screenX < image.width && 
                  screenY >= 0 && screenY < image.height) {
                image.setPixel(screenX, screenY, color);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error drawing text: $e');
    }
  }
  
  /// Simple bitmap font implementation (very basic)
  bool _getCharPixel(int charCode, int x, int y) {
    if (x < 0 || y < 0 || x >= 5 || y >= 8) return false;
    
    // Show only for certain characters like numbers and letters
    if (charCode >= 48 && charCode <= 57) { // 0-9
      if (x == 0 || x == 4 || y == 0 || y == 7) return true;
      return charCode == 56; // 8 is filled
    } else if (charCode >= 65 && charCode <= 90) { // A-Z
      return (x == 0 || x == 4 || y == 0 || y == 3);
    } else if (charCode >= 97 && charCode <= 122) { // a-z
      return (x == 0 || x == 4 || y == 3 || y == 7);
    } else if (charCode == 46) { // .
      return (x == 2 && y == 7);
    } else if (charCode == 58) { // :
      return (x == 2 && (y == 2 || y == 6));
    } else if (charCode == 32) { // space
      return false;
    }
    
    // Default pattern for other chars
    return (x % 2 == 0 && y % 2 == 0);
  }

  /// Ensure we have a clean outer contour without internal details
  List<Point> _ensureCleanOuterContour(List<Point> contour) {
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
      if (_isContourSelfIntersecting(workingContour)) {
        // If self-intersecting, compute convex hull instead
        final points = List<Point>.from(workingContour);
        return _computeConvexHull(points);
      }
      
      // 3. Eliminate concave sections that are too deep
      workingContour = _simplifyDeepConcavities(workingContour);
      
      // 4. Apply smoothing to get rid of jagged edges
      workingContour = _applyGaussianSmoothing(workingContour, 5);
      
      return workingContour;
    } catch (e) {
      print('Error cleaning contour: $e');
      return contour;
    }
  }

  /// Check if a contour is self-intersecting
  bool _isContourSelfIntersecting(List<Point> contour) {
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
        
        if (_doLinesIntersect(p1, p2, p3, p4)) {
          return true;
        }
      }
    }
    
    return false;
  }

  /// Check if two line segments intersect
  bool _doLinesIntersect(Point p1, Point p2, Point p3, Point p4) {
    // Calculate the direction of the lines
    final d1x = p2.x - p1.x;
    final d1y = p2.y - p1.y;
    final d2x = p4.x - p3.x;
    final d2y = p4.y - p3.y;
    
    // Calculate the determinant
    final det = d1x * d2y - d1y * d2x;
    
    // If lines are parallel, they don't intersect
    if (det.abs() < 1e-10) return false;
    
    // Calculate the parameters of intersection
    final dx = p3.x - p1.x;
    final dy = p3.y - p1.y;
    
    final t = (dx * d2y - dy * d2x) / det;
    final u = (dx * d1y - dy * d1x) / det;
    
    // Check if intersection point is within both line segments
    return (t >= 0 && t <= 1 && u >= 0 && u <= 1);
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

  /// Cross product for determining counter-clockwise order
  double _ccw(Point a, Point b, Point c) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }

  /// Squared distance between two points
  double _squaredDistance(Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return dx * dx + dy * dy;
  }

  /// Simplify deep concavities in the contour
  List<Point> _simplifyDeepConcavities(List<Point> contour) {
    if (contour.length < 4) return contour;
    
    final result = <Point>[];
    final thresholdRatio = 0.2;  // Concavity must be at least 20% of perimeter
    
    // Calculate perimeter
    double perimeter = 0;
    for (int i = 0; i < contour.length - 1; i++) {
      perimeter += _distanceBetween(contour[i], contour[i + 1]);
    }
    
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
      final direct = _distanceBetween(prev, next);
      final detour = _distanceBetween(prev, current) + _distanceBetween(current, next);
      
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

  /// Apply Gaussian smoothing to contour points
  List<Point> _applyGaussianSmoothing(List<Point> contour, int windowSize) {
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

  /// Calculate distance between two points
  double _distanceBetween(Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Calculate area of a polygon
  double _calculatePolygonArea(List<Point> points) {
    if (points.length < 3) return 0.0;
    
    double area = 0.0;
    
    // Apply the Shoelace formula (Gauss's area formula)
    for (int i = 0; i < points.length - 1; i++) {
      area += points[i].x * points[i + 1].y;
      area -= points[i + 1].x * points[i].y;
    }
    
    return area.abs() / 2.0;
  }

  /// Generate an optimized toolpath for the given contour
  List<Point> _generateOptimizedToolpath(
    List<Point> contour, 
    double toolDiameter, 
    double stepover
  ) {
    // If the contour is too small or invalid, use the basic toolpath generator
    if (contour.length < 10) {
      return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
    }
    
    try {
      // Find the bounding box of the contour
      double minX = double.infinity;
      double minY = double.infinity;
      double maxX = double.negativeInfinity;
      double maxY = double.negativeInfinity;
      
      for (final point in contour) {
        minX = math.min(minX, point.x);
        minY = math.min(minY, point.y);
        maxX = math.max(maxX, point.x);
        maxY = math.max(maxY, point.y);
      }
      
      // Inset by half tool diameter to account for tool radius
      final inset = toolDiameter / 2;
      minX += inset;
      minY += inset;
      maxX -= inset;
      maxY -= inset;
      
      // Check if bounding box is valid after inset
      if (minX >= maxX || minY >= maxY) {
        // Contour is too small for the tool, use a simpler approach
        return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
      }
      
      // Generate zigzag pattern for efficient material removal
      // Calculate direction based on longest dimension
      final width = maxX - minX;
      final height = maxY - minY;
      final horizontal = width > height;
      
      final toolpath = <Point>[];
      
      if (horizontal) {
        // Generate horizontal zigzag (moving along Y)
        double y = minY;
        bool movingRight = true;
        
        while (y <= maxY) {
          if (movingRight) {
            toolpath.add(Point(minX, y));
            toolpath.add(Point(maxX, y));
          } else {
            toolpath.add(Point(maxX, y));
            toolpath.add(Point(minX, y));
          }
          
          y += stepover;
          movingRight = !movingRight;
        }
      } else {
        // Generate vertical zigzag (moving along X)
        double x = minX;
        bool movingDown = true;
        
        while (x <= maxX) {
          if (movingDown) {
            toolpath.add(Point(x, minY));
            toolpath.add(Point(x, maxY));
          } else {
            toolpath.add(Point(x, maxY));
            toolpath.add(Point(x, minY));
          }
          
          x += stepover;
          movingDown = !movingDown;
        }
      }
      
      // Post-process the toolpath to ensure it stays within the contour
      return _clipToolpathToContour(toolpath, contour);
    } catch (e) {
      print('Error generating optimized toolpath: $e');
      // Fall back to basic toolpath generation
      return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
    }
  }

  /// Clip a toolpath to ensure it stays within the contour
  List<Point> _clipToolpathToContour(List<Point> toolpath, List<Point> contour) {
    if (toolpath.isEmpty || contour.length < 3) {
      return toolpath;
    }
    
    final result = <Point>[];
    
    // For each segment in the toolpath
    for (int i = 0; i < toolpath.length - 1; i++) {
      final p1 = toolpath[i];
      final p2 = toolpath[i + 1];
      
      // Check if both points are inside the contour
      final p1Inside = _isPointInPolygon(p1, contour);
      final p2Inside = _isPointInPolygon(p2, contour);
      
      if (p1Inside && p2Inside) {
        // Both points inside, add the entire segment
        result.add(p1);
        result.add(p2);
      } else if (p1Inside || p2Inside) {
        // One point inside, one outside - find intersection with contour
        final intersections = _findLinePolygonIntersections(p1, p2, contour);
        
        if (intersections.isNotEmpty) {
          // Sort intersections by distance from p1
          intersections.sort((a, b) {
            final distA = _squaredDistance(p1, a);
            final distB = _squaredDistance(p1, b);
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
        final intersections = _findLinePolygonIntersections(p1, p2, contour);
        
        if (intersections.length >= 2) {
          // If multiple intersections, add the segment between first and last
          intersections.sort((a, b) {
            final distA = _squaredDistance(p1, a);
            final distB = _squaredDistance(p1, b);
            return distA.compareTo(distB);
          });
          
          result.add(intersections.first);
          result.add(intersections.last);
        }
      }
    }
    
    return result;
  }

  /// Check if a point is inside a polygon
  bool _isPointInPolygon(Point point, List<Point> polygon) {
    bool inside = false;
    int j = polygon.length - 1;
    
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].y > point.y) != (polygon[j].y > point.y) &&
          point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / 
          (polygon[j].y - polygon[i].y) + polygon[i].x) {
        inside = !inside;
      }
      j = i;
    }
    
    return inside;
  }

  /// Find intersections between a line segment and a polygon
  List<Point> _findLinePolygonIntersections(Point p1, Point p2, List<Point> polygon) {
    final intersections = <Point>[];
    
    for (int i = 0; i < polygon.length - 1; i++) {
      final q1 = polygon[i];
      final q2 = polygon[i + 1];
      
      final intersection = _lineLineIntersection(p1, p2, q1, q2);
      if (intersection != null) {
        intersections.add(intersection);
      }
    }
    
    return intersections;
  }

  /// Calculate intersection point between two line segments
  Point? _lineLineIntersection(Point p1, Point p2, Point q1, Point q2) {
    // Calculate the direction of the lines
    final d1x = p2.x - p1.x;
    final d1y = p2.y - p1.y;
    final d2x = q2.x - q1.x;
    final d2y = q2.y - q1.y;
    
    // Calculate the determinant
    final det = d1x * d2y - d1y * d2x;
    
    // If lines are parallel, they don't intersect
    if (det.abs() < 1e-10) return null;
    
    // Calculate the parameters of intersection
    final dx = q1.x - p1.x;
    final dy = q1.y - p1.y;
    
    final t = (dx * d2y - dy * d2x) / det;
    final u = (dx * d1y - dy * d1x) / det;
    
    // Check if intersection point is within both line segments
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
      return Point(
        p1.x + t * d1x,
        p1.y + t * d1y
      );
    }
    
    return null;
  }
}

/// Function to process the image in an isolate (separate thread)
Future<SlabProcessingResult> _processImageIsolate(Map<String, dynamic> data) async {
  // Initialize the compute isolate's Flutter binary messenger
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Extract data passed to the isolate
    final List<int> imageBytes = data['imageBytes'] as List<int>;
    final Map<String, dynamic> settingsMap = data['settings'] as Map<String, dynamic>;
    final int? maxImageSize = data['maxImageSize'] as int?;
    
    // Convert settings map to SettingsModel
    final settings = SettingsModel(
      cncWidth: settingsMap['cncWidth'],
      cncHeight: settingsMap['cncHeight'],
      markerXDistance: settingsMap['markerXDistance'],
      markerYDistance: settingsMap['markerYDistance'],
      toolDiameter: settingsMap['toolDiameter'],
      stepover: settingsMap['stepover'],
      safetyHeight: settingsMap['safetyHeight'],
      feedRate: settingsMap['feedRate'],
      plungeRate: settingsMap['plungeRate'],
      cuttingDepth: settingsMap['cuttingDepth'],
    );
    
    // Create temporary detector instance for this isolate
    final detector = SlabDetector(
      settings: settings,
      maxImageSize: maxImageSize ?? 1200,
    );
    
    // Process using the direct method
    return await detector._processImageDirect(imageBytes, settings);
  } catch (e, stackTrace) {
    print('Error in isolate: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}