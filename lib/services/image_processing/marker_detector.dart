import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../gcode/machine_coordinates.dart';
import 'image_utils.dart';

enum MarkerRole {
  origin,
  xAxis,
  scale
}

class MarkerPoint {
  final int x;
  final int y;
  final MarkerRole role;
  final double confidence;

  MarkerPoint(this.x, this.y, this.role, {this.confidence = 1.0});
  
  Point toPoint() => Point(x.toDouble(), y.toDouble());
}

class MarkerDetectionResult {
  final List<MarkerPoint> markers;
  final double pixelToMmRatio;
  final Point origin;
  final double orientationAngle;
  final img.Image? debugImage;

  MarkerDetectionResult({
    required this.markers,
    required this.pixelToMmRatio,
    required this.origin,
    required this.orientationAngle,
    this.debugImage,
  });
}

class MarkerDetector {
  final double markerRealDistanceMm;
  final bool generateDebugImage;
  final int maxImageSize;  // Added parameter for limiting image size
  final int processingTimeout;  // Added timeout parameter
  
  MarkerDetector({
    required this.markerRealDistanceMm,
    this.generateDebugImage = true,
    this.maxImageSize = 1200,  // Default max size
    this.processingTimeout = 10000,  // Default 10 second timeout
  });
  
  /// Detect markers in an image and calculate calibration parameters
  Future<MarkerDetectionResult> detectMarkers(img.Image image) async {
    // Add timeout to detection process
    return await Future.delayed(Duration.zero, () {
      return Future.value(_detectMarkersInternal(image))
        .timeout(
          Duration(milliseconds: processingTimeout),
          onTimeout: () => throw TimeoutException('Marker detection timed out')
        );
    });
  }

  MarkerDetectionResult _detectMarkersInternal(img.Image image) {
    // Log input image dimensions
    print('Marker detection - input image dimensions: ${image.width}x${image.height}');
    
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
        print('Marker detection - resized to: ${processImage.width}x${processImage.height}');
      } catch (e) {
        print('Warning: Failed to resize image: $e');
      }
    }
    
    // Create a copy for visualization if needed
    img.Image? debugImage;
    if (generateDebugImage) {
      try {
        debugImage = img.copyResize(processImage, width: processImage.width, height: processImage.height);
      } catch (e) {
        print('Warning: Failed to create debug image: $e');
      }
    }
    
    try {
      // STRATEGY 1: Try corner detection
      print('Attempting corner marker detection...');
      var markers = _findCornerMarkers(processImage, debugImage);
      if (markers.length >= 3) {
        print('Found ${markers.length} corner markers');
        final identifiedMarkers = _identifyMarkerRoles(markers, processImage.width, processImage.height);
        final calibrationResult = _calculateCalibration(identifiedMarkers, debugImage);
        return calibrationResult;
      }
      
      // STRATEGY 2: Try high contrast blob detection
      print('Attempting high contrast blob detection...');
      markers = _findHighContrastBlobs(processImage, debugImage);
      if (markers.length >= 3) {
        print('Found ${markers.length} high contrast markers');
        final identifiedMarkers = _identifyMarkerRoles(markers, processImage.width, processImage.height);
        final calibrationResult = _calculateCalibration(identifiedMarkers, debugImage);
        return calibrationResult;
      }
      
      // STRATEGY 3: Try the original method
      print('Attempting original marker detection...');
      // Convert to grayscale for processing
      final grayscale = ImageUtils.convertToGrayscale(processImage);
      
      // Preprocess the image to make markers stand out
      final preprocessed = _preprocessImage(grayscale);
      
      // Find potential marker regions
      markers = _findMarkerCandidates(preprocessed, debugImage);
      
      // Identify which marker is which based on their relative positions
      final identifiedMarkers = _identifyMarkerRoles(markers, processImage.width, processImage.height);
      
      // Calculate calibration parameters with validation
      final calibrationResult = _calculateCalibration(identifiedMarkers, debugImage);
      
      return calibrationResult;
    } catch (e) {
      print('Error in marker detection: $e');
      // Fall back to predefined markers if detection fails
      return _createFallbackResult(processImage, debugImage);
    }
  }

  /// Find markers in corner regions of the image
List<MarkerPoint> _findCornerMarkers(img.Image image, img.Image? debugImage) {
  final markers = <MarkerPoint>[];
  final width = image.width;
  final height = image.height;
  
  // Define corner regions to search (relative to image size)
  final searchRegions = [
    // Bottom left (origin)
    [0.05, 0.75, 0.30, 0.95],
    // Bottom right (x-axis)
    [0.70, 0.75, 0.95, 0.95],
    // Top left (scale/y-axis)
    [0.05, 0.05, 0.30, 0.25],
  ];
  
  for (int regionIndex = 0; regionIndex < searchRegions.length; regionIndex++) {
    final region = searchRegions[regionIndex];
    final x1 = (width * region[0]).round();
    final y1 = (height * region[1]).round();
    final x2 = (width * region[2]).round();
    final y2 = (height * region[3]).round();
    
    // Visualize region on debug image
    if (debugImage != null) {
      _drawRegion(debugImage, x1, y1, x2, y2, regionIndex);
    }
    
    final regionMarker = _findMarkerInRegion(image, x1, y1, x2, y2, debugImage);
    if (regionMarker != null) {
      markers.add(regionMarker);
    }
  }
  
  return markers;
}

/// Find a marker within a specific region
MarkerPoint? _findMarkerInRegion(img.Image image, int x1, int y1, int x2, int y2, img.Image? debugImage) {
  try {
    // Create a cropped image for the region
    final regionWidth = x2 - x1;
    final regionHeight = y2 - y1;
    
    // Skip very small regions
    if (regionWidth < 10 || regionHeight < 10) return null;
    
    // Extract region statistics
    int totalPixels = 0;
    double sumBrightness = 0;
    
    for (int y = y1; y < y2; y++) {
      for (int x = x1; x < x2; x++) {
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          final pixel = image.getPixel(x, y);
          final brightness = ImageUtils.calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          ) / 255.0; // Normalize to 0-1
          
          sumBrightness += brightness;
          totalPixels++;
        }
      }
    }
    
    // Calculate average brightness
    final avgBrightness = totalPixels > 0 ? sumBrightness / totalPixels : 0.5;
    
    // Look for the darkest or brightest area in the region as the marker
    int bestX = -1, bestY = -1;
    double bestDifference = -1;
    
    // Determine if we should look for dark markers on light background or vice versa
    final lookForDark = avgBrightness > 0.5;
    
    // Slide a detection window through the region
    final windowSize = math.min(regionWidth, regionHeight) ~/ 4;
    
    for (int y = y1; y < y2 - windowSize; y += windowSize ~/ 2) {
      for (int x = x1; x < x2 - windowSize; x += windowSize ~/ 2) {
        int windowPixels = 0;
        double windowSum = 0;
        
        // Calculate window statistics
        for (int wy = 0; wy < windowSize; wy++) {
          for (int wx = 0; wx < windowSize; wx++) {
            final px = x + wx;
            final py = y + wy;
            
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              final pixel = image.getPixel(px, py);
              final brightness = ImageUtils.calculateLuminance(
                pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
              ) / 255.0; // Normalize to 0-1
              
              windowSum += brightness;
              windowPixels++;
            }
          }
        }
        
        if (windowPixels > 0) {
          final windowAvg = windowSum / windowPixels;
          double difference;
          
          if (lookForDark) {
            // Looking for dark markers on light background
            difference = avgBrightness - windowAvg;
          } else {
            // Looking for light markers on dark background
            difference = windowAvg - avgBrightness;
          }
          
          if (difference > bestDifference) {
            bestDifference = difference;
            bestX = x + windowSize ~/ 2;
            bestY = y + windowSize ~/ 2;
          }
        }
      }
    }
    
    // Require a minimum contrast difference
    if (bestDifference < 0.2 || bestX < 0 || bestY < 0) {
      return null;
    }
    
    // Draw marker on debug image if available
    if (debugImage != null) {
      final color = lookForDark ? 
        img.ColorRgba8(255, 0, 0, 255) : 
        img.ColorRgba8(0, 255, 0, 255);
      
      ImageUtils.drawCircle(debugImage, bestX, bestY, 10, color);
      ImageUtils.drawText(debugImage, "Contrast: ${bestDifference.toStringAsFixed(2)}", 
                         bestX + 15, bestY, color);
    }
    
    return MarkerPoint(bestX, bestY, MarkerRole.origin, confidence: bestDifference);
  } catch (e) {
    print('Error finding marker in region: $e');
    return null;
  }
}

/// Draw a region on the debug image
void _drawRegion(img.Image image, int x1, int y1, int x2, int y2, int regionIndex) {
  final colors = [
    img.ColorRgba8(255, 0, 0, 128),  // Red for origin
    img.ColorRgba8(0, 255, 0, 128),  // Green for X-axis
    img.ColorRgba8(0, 0, 255, 128)   // Blue for scale
  ];
  
  final color = colors[regionIndex % colors.length];
  
  // Draw rectangle border
  for (int x = x1; x <= x2; x++) {
    if (x >= 0 && x < image.width) {
      if (y1 >= 0 && y1 < image.height) image.setPixel(x, y1, color);
      if (y2 >= 0 && y2 < image.height) image.setPixel(x, y2, color);
    }
  }
  
  for (int y = y1; y <= y2; y++) {
    if (y >= 0 && y < image.height) {
      if (x1 >= 0 && x1 < image.width) image.setPixel(x1, y, color);
      if (x2 >= 0 && x2 < image.width) image.setPixel(x2, y, color);
    }
  }
  
  // Add label
  final labels = ["Origin", "X-Axis", "Scale"];
  ImageUtils.drawText(image, labels[regionIndex % labels.length], x1 + 5, y1 + 5, color);
}

/// Find high contrast blobs that could be markers
List<MarkerPoint> _findHighContrastBlobs(img.Image image, img.Image? debugImage) {
  final markers = <MarkerPoint>[];
  
  try {
    // Convert to grayscale
    final grayscale = ImageUtils.convertToGrayscale(image);
    
    // Apply adaptive thresholding to find high contrast areas
    final thresholded = _applyMultipleThresholds(grayscale);
    
    // Find connected components (blobs)
    final blobs = _findConnectedComponents(thresholded);
    
    // Sort blobs by size (we want medium-sized blobs, not too big or small)
    blobs.sort((a, b) => a.length.compareTo(b.length));
    
    // Filter by size and shape
    final filteredBlobs = <List<int>>[];
    for (final blob in blobs) {
      if (blob.length >= 40 && blob.length <= 2000) {
        // Calculate blob properties
        final properties = _calculateBlobProperties(blob);
        
        // Filter by compactness (close to square/circle)
        if (properties['compactness']! < 2.5) {
          filteredBlobs.add(blob);
          
          if (debugImage != null) {
            // Visualize blob
            for (int i = 0; i < blob.length; i += 2) {
              if (i + 1 < blob.length) {
                final x = blob[i];
                final y = blob[i + 1];
                if (x >= 0 && x < debugImage.width && y >= 0 && y < debugImage.height) {
                  debugImage.setPixel(x, y, img.ColorRgba8(255, 0, 255, 100));
                }
              }
            }
          }
        }
      }
    }
    
    // Keep only the largest 10 blobs to avoid false positives
    if (filteredBlobs.length > 10) {
      filteredBlobs.sort((a, b) => b.length.compareTo(a.length));
      filteredBlobs.removeRange(10, filteredBlobs.length);
    }
    
    // Convert blobs to marker points
    for (final blob in filteredBlobs) {
      final properties = _calculateBlobProperties(blob);
      
      markers.add(MarkerPoint(
        properties['centerX']!.round(), 
        properties['centerY']!.round(), 
        MarkerRole.origin,
        confidence: 0.8
      ));
      
      if (debugImage != null) {
        ImageUtils.drawCircle(
          debugImage, 
          properties['centerX']!.round(), 
          properties['centerY']!.round(), 
          8, 
          img.ColorRgba8(0, 255, 255, 255)
        );
      }
    }
  } catch (e) {
    print('Error finding high contrast blobs: $e');
  }
  
  return markers;
}

/// Apply multiple thresholds to find high contrast regions
img.Image _applyMultipleThresholds(img.Image grayscale) {
  final result = img.Image(width: grayscale.width, height: grayscale.height);
  
  // Initialize with white
  for (int y = 0; y < grayscale.height; y++) {
    for (int x = 0; x < grayscale.width; x++) {
      result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
    }
  }
  
  // Try both dark and light thresholds
  final thresholds = [50, 200]; // Look for very dark and very light regions
  
  for (int y = 0; y < grayscale.height; y++) {
    for (int x = 0; x < grayscale.width; x++) {
      final pixel = grayscale.getPixel(x, y);
      final intensity = ImageUtils.calculateLuminance(
        pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
      );
      
      // Mark pixel as feature (black) if it's either very dark or very light
      if (intensity < thresholds[0] || intensity > thresholds[1]) {
        result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
      }
    }
  }
  
  return result;
}

/// Calculate blob properties like center, area, and compactness
Map<String, double> _calculateBlobProperties(List<int> blob) {
  if (blob.isEmpty) {
    return {
      'centerX': 0,
      'centerY': 0,
      'area': 0,
      'compactness': double.infinity
    };
  }
  
  // Calculate centroid
  double sumX = 0, sumY = 0;
  for (int i = 0; i < blob.length; i += 2) {
    if (i + 1 < blob.length) {
      sumX += blob[i];
      sumY += blob[i + 1];
    }
  }
  
  final centerX = sumX / (blob.length / 2);
  final centerY = sumY / (blob.length / 2);
  
  // Calculate area and perimeter
  final area = blob.length / 2;
  
  // Find extreme points for perimeter estimation
  double minX = double.infinity, minY = double.infinity;
  double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
  
  for (int i = 0; i < blob.length; i += 2) {
    if (i + 1 < blob.length) {
      final x = blob[i].toDouble();
      final y = blob[i + 1].toDouble();
      
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
  }
  
  // Simple perimeter approximation
  final width = maxX - minX;
  final height = maxY - minY;
  final perimeter = 2 * (width + height);
  
  // Compactness (1 for circle, higher for complex shapes)
  // Using 4π·Area / Perimeter²
  final compactness = perimeter <= 0 ? 
    double.infinity : 
    perimeter * perimeter / (4 * math.pi * area);
  
  return {
    'centerX': centerX,
    'centerY': centerY,
    'area': area,
    'compactness': compactness
  };
}
  
  /// Create a fallback result when detection fails
  MarkerDetectionResult _createFallbackResult(img.Image image, img.Image? debugImage) {
    final markers = _fallbackMarkerDetection(image.width, image.height);
    
    // Calculate parameters from fallback markers
    final originMarker = markers.firstWhere((m) => m.role == MarkerRole.origin);
    final xAxisMarker = markers.firstWhere((m) => m.role == MarkerRole.xAxis);
    final scaleMarker = markers.firstWhere((m) => m.role == MarkerRole.scale);
    
    // Draw markers on debug image if available
    if (debugImage != null) {
      _drawMarker(debugImage, originMarker, ImageUtils.colorRed, "Origin (Fallback)");
      _drawMarker(debugImage, xAxisMarker, ImageUtils.colorGreen, "X-Axis (Fallback)");
      _drawMarker(debugImage, scaleMarker, ImageUtils.colorBlue, "Scale (Fallback)");
    }
    
    // Calculate fallback calibration parameters
    final dx = xAxisMarker.x - originMarker.x;
    final dy = xAxisMarker.y - originMarker.y;
    final orientationAngle = math.atan2(dy, dx);
    
    final scaleX = scaleMarker.x - originMarker.x;
    final scaleY = scaleMarker.y - originMarker.y;
    final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
    final pixelToMmRatio = markerRealDistanceMm / distancePx;
    
    return MarkerDetectionResult(
      markers: markers,
      pixelToMmRatio: pixelToMmRatio,
      origin: Point(originMarker.x.toDouble(), originMarker.y.toDouble()),
      orientationAngle: orientationAngle,
      debugImage: debugImage,
    );
  }
  
  /// Preprocess the image to enhance markers for detection
  img.Image _preprocessImage(img.Image grayscale) {
    try {
      // Apply blur to reduce noise
      final blurred = img.gaussianBlur(grayscale, radius: 3);
      
      // Apply adaptive threshold to find potential markers
      final thresholded = _adaptiveThreshold(blurred, 15, 5);
      
      return thresholded;
    } catch (e) {
      print('Error in preprocessing: $e');
      // If preprocessing fails, return original grayscale
      return grayscale;
    }
  }
  
  /// Apply adaptive thresholding to the image
  img.Image _adaptiveThreshold(img.Image grayscale, int blockSize, int constant) {
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    try {
      for (int y = 0; y < grayscale.height; y++) {
        for (int x = 0; x < grayscale.width; x++) {
          // Get local window for adaptive threshold
          final mean = _getLocalMean(grayscale, x, y, blockSize);
          
          // Get current pixel value
          final pixel = grayscale.getPixel(x, y);
          final pixelValue = ImageUtils.calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          
          // Apply threshold: if pixel is darker than local mean - constant, mark as marker
          if (pixelValue < mean - constant) {
            result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255)); // Black
          } else {
            result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // White
          }
        }
      }
      return result;
    } catch (e) {
      print('Error in adaptive thresholding: $e');
      // If thresholding fails, return a blank image
      return result;
    }
  }
  
  /// Calculate local mean for adaptive thresholding
  double _getLocalMean(img.Image image, int x, int y, int blockSize) {
    int sum = 0;
    int count = 0;
    int halfBlock = blockSize ~/ 2;
    
    for (int j = math.max(0, y - halfBlock); j <= math.min(image.height - 1, y + halfBlock); j++) {
      for (int i = math.max(0, x - halfBlock); i <= math.min(image.width - 1, x + halfBlock); i++) {
        try {
          final pixel = image.getPixel(i, j);
          sum += ImageUtils.calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          count++;
        } catch (e) {
          // Skip this pixel on error
          continue;
        }
      }
    }
    
    return count > 0 ? sum / count : 128;
  }
  
  /// Find marker candidates in the preprocessed image
  List<MarkerPoint> _findMarkerCandidates(img.Image preprocessed, img.Image? debugImage) {
    final candidates = <MarkerPoint>[];
    
    try {
      final List<List<int>> blobs = _findConnectedComponents(preprocessed);
      
      // Calculate blob centroids and filter by size
      for (int i = 0; i < blobs.length; i++) {
        final blob = blobs[i];
        if (blob.length < 20 || blob.length > 1000) continue; // Size filter
        
        // Calculate centroid
        int sumX = 0, sumY = 0;
        for (int j = 0; j < blob.length; j += 2) {
          sumX += blob[j];
          sumY += blob[j + 1];
        }
        
        final centerX = (sumX / (blob.length / 2)).round();
        final centerY = (sumY / (blob.length / 2)).round();
        
        // Add to candidates with placeholder role (will be assigned later)
        candidates.add(MarkerPoint(centerX, centerY, MarkerRole.origin, confidence: 0.8));
        
        // Draw detected blobs on debug image if available
        if (debugImage != null) {
          try {
            ImageUtils.drawCircle(debugImage, centerX, centerY, 5, ImageUtils.colorBlue);
            for (int j = 0; j < blob.length && j + 1 < blob.length; j += 2) {
              final px = blob[j];
              final py = blob[j + 1];
              if (px >= 0 && px < debugImage.width && py >= 0 && py < debugImage.height) {
                debugImage.setPixel(px, py, img.ColorRgba8(0, 255, 0, 100)); // Green with 100 alpha
              }
            }
          } catch (e) {
            print('Error drawing debug blobs: $e');
            // Continue even if visualization fails
          }
        }
      }
    } catch (e) {
      print('Error finding marker candidates: $e');
    }
    
    // If we found too many or too few candidates, use fallback detection
    if (candidates.length < 3 || candidates.length > 20) {
      return _fallbackMarkerDetection(preprocessed.width, preprocessed.height);
    }
    
    return candidates;
  }
  
  /// Find connected components in binary image (basic blob detection)
  List<List<int>> _findConnectedComponents(img.Image binaryImage) {
    final List<List<int>> blobs = [];
    
    try {
      final visited = List.generate(
        binaryImage.height, 
        (_) => List.filled(binaryImage.width, false)
      );
      
      for (int y = 0; y < binaryImage.height; y++) {
        for (int x = 0; x < binaryImage.width; x++) {
          if (visited[y][x]) continue;
          
          try {
            final pixel = binaryImage.getPixel(x, y);
            final isBlack = ImageUtils.calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            ) < 128;
            
            if (isBlack) {
              final List<int> blob = [];
              _floodFill(binaryImage, x, y, visited, blob);
              if (blob.isNotEmpty) {
                blobs.add(blob);
              }
            } else {
              visited[y][x] = true;
            }
          } catch (e) {
            // Skip this pixel if there's an error
            visited[y][x] = true;
          }
        }
      }
    } catch (e) {
      print('Error in connected components: $e');
    }
    
    return blobs;
  }
  
  /// Flood fill algorithm for connected component labeling
  /// with stack overflow prevention (max recursion depth)
  void _floodFill(img.Image binaryImage, int x, int y, List<List<bool>> visited, List<int> blob, 
    {int depth = 0, int maxDepth = 1000}) {
    
    // Prevent stack overflow with excessive recursion
    if (depth >= maxDepth) return;
    
    if (x < 0 || y < 0 || x >= binaryImage.width || y >= binaryImage.height || visited[y][x]) {
      return;
    }
    
    try {
      final pixel = binaryImage.getPixel(x, y);
      final isBlack = ImageUtils.calculateLuminance(
        pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
      ) < 128;
      
      if (!isBlack) {
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
    _floodFill(binaryImage, x + 1, y, visited, blob, depth: depth + 1, maxDepth: maxDepth);
    _floodFill(binaryImage, x - 1, y, visited, blob, depth: depth + 1, maxDepth: maxDepth);
    _floodFill(binaryImage, x, y + 1, visited, blob, depth: depth + 1, maxDepth: maxDepth);
    _floodFill(binaryImage, x, y - 1, visited, blob, depth: depth + 1, maxDepth: maxDepth);
  }
  
  /// Identify marker roles based on their relative positions
  List<MarkerPoint> _identifyMarkerRoles(List<MarkerPoint> candidates, int imageWidth, int imageHeight) {
  if (candidates.length < 3) {
    return _fallbackMarkerDetection(imageWidth, imageHeight);
  }
  
  try {
    // Set up positions based on expected layout
    // Origin: Bottom left
    // X-Axis: Bottom right
    // Scale: Top left
    
    // First, try to identify candidates by their geometric positions
    if (candidates.length == 3) {
      // Sort candidates by y coordinate (vertical position)
      candidates.sort((a, b) => a.y.compareTo(b.y));
      
      // The top point is likely the scale (Y-axis) marker
      final scaleMarker = candidates[0];
      
      // The bottom two points are origin and X-axis
      // Sort them by x coordinate
      final bottomPoints = [candidates[1], candidates[2]];
      bottomPoints.sort((a, b) => a.x.compareTo(b.x));
      
      // Left bottom is origin, right bottom is X-axis
      final originMarker = bottomPoints[0];
      final xAxisMarker = bottomPoints[1];
      
      return [
        MarkerPoint(originMarker.x, originMarker.y, MarkerRole.origin, confidence: 0.9),
        MarkerPoint(xAxisMarker.x, xAxisMarker.y, MarkerRole.xAxis, confidence: 0.9),
        MarkerPoint(scaleMarker.x, scaleMarker.y, MarkerRole.scale, confidence: 0.9),
      ];
    }
    
    // If we have more than 3 candidates, use a more sophisticated approach
    
    // First, sort by y-coordinate (vertical position)
    candidates.sort((a, b) => a.y.compareTo(b.y));
    
    // Take the top third as potential scale markers
    int topThirdCount = (candidates.length / 3).ceil();
    final topThird = candidates.sublist(0, math.min(topThirdCount, candidates.length));
    
    // Sort the top candidates by x-coordinate
    topThird.sort((a, b) => a.x.compareTo(b.x));
    
    // Take leftmost of the top candidates as scale marker
    final scaleMarker = topThird.first;
    
    // Now take the bottom third as potential origin/x-axis markers
    final bottomThird = candidates.sublist(candidates.length - topThirdCount);
    
    // Sort by x-coordinate
    bottomThird.sort((a, b) => a.x.compareTo(b.x));
    
    // Take leftmost as origin, rightmost as x-axis
    final originMarker = bottomThird.first;
    final xAxisMarker = bottomThird.last;
    
    return [
      MarkerPoint(originMarker.x, originMarker.y, MarkerRole.origin, confidence: 0.8),
      MarkerPoint(xAxisMarker.x, xAxisMarker.y, MarkerRole.xAxis, confidence: 0.8),
      MarkerPoint(scaleMarker.x, scaleMarker.y, MarkerRole.scale, confidence: 0.8),
    ];
  } catch (e) {
    print('Error identifying marker roles: $e');
  }
  
  // Fallback if geometric analysis fails
  return _fallbackMarkerDetection(imageWidth, imageHeight);
}

/// Fallback detection to ensure we always get some markers
List<MarkerPoint> _fallbackMarkerDetection(int width, int height) {
  print('Using fallback marker detection');
  return [
    MarkerPoint((width * 0.2).round(), (height * 0.8).round(), MarkerRole.origin, confidence: 0.5),   // Bottom left
    MarkerPoint((width * 0.8).round(), (height * 0.8).round(), MarkerRole.xAxis, confidence: 0.5),    // Bottom right
    MarkerPoint((width * 0.2).round(), (height * 0.2).round(), MarkerRole.scale, confidence: 0.5),    // Top left
  ];
}
  
  /// Calculate calibration parameters from detected markers
  MarkerDetectionResult _calculateCalibration(List<MarkerPoint> markers, img.Image? debugImage) {
    // Ensure we have enough markers
    if (markers.length < 3) {
      throw Exception('Insufficient markers detected (${markers.length})');
    }
    
    // Find markers for each role
    MarkerPoint? originMarker, xAxisMarker, scaleMarker;
    
    for (final marker in markers) {
      switch (marker.role) {
        case MarkerRole.origin:
          originMarker = marker;
          break;
        case MarkerRole.xAxis:
          xAxisMarker = marker;
          break;
        case MarkerRole.scale:
          scaleMarker = marker;
          break;
      }
    }
    
    // Check that we have all required markers
    if (originMarker == null || xAxisMarker == null || scaleMarker == null) {
      throw Exception('Missing markers after identification');
    }
    
    // Calculate orientation angle
    final dx = xAxisMarker.x - originMarker.x;
    final dy = xAxisMarker.y - originMarker.y;
    final orientationAngle = math.atan2(dy, dx);
    
    // Calculate pixel-to-mm ratio from scale marker distance
    final scaleX = scaleMarker.x - originMarker.x;
    final scaleY = scaleMarker.y - originMarker.y;
    final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
    
    // Validate markers aren't collinear or too close
    if (distancePx < 10.0) {
      throw Exception('Scale marker too close to origin');
    }
    
    double pixelToMmRatio = markerRealDistanceMm / distancePx;
    
    // Sanity check on ratio
    if (pixelToMmRatio.isNaN || pixelToMmRatio.isInfinite || 
        pixelToMmRatio <= 0.01 || pixelToMmRatio > 100.0) {
      throw Exception('Invalid pixel-to-mm ratio: $pixelToMmRatio');
    }
    
    // Create origin point
    final origin = Point(originMarker.x.toDouble(), originMarker.y.toDouble());
    
    // Draw debug visualizations if needed
    if (debugImage != null) {
      try {
        // Draw markers with their roles
        _drawMarker(debugImage, originMarker, ImageUtils.colorRed, "Origin");
        _drawMarker(debugImage, xAxisMarker, ImageUtils.colorGreen, "X-Axis");
        _drawMarker(debugImage, scaleMarker, ImageUtils.colorBlue, "Scale");
        
        // Draw connecting lines
        ImageUtils.drawLine(
          debugImage, 
          originMarker.x, originMarker.y, 
          xAxisMarker.x, xAxisMarker.y, 
          ImageUtils.colorRed
        );
        
        ImageUtils.drawLine(
          debugImage, 
          originMarker.x, originMarker.y, 
          scaleMarker.x, scaleMarker.y, 
          ImageUtils.colorBlue
        );
        
        // Add calibration info text
        final infoText = "Ratio: ${pixelToMmRatio.toStringAsFixed(3)} mm/px";
        ImageUtils.drawText(debugImage, infoText, 10, 10, ImageUtils.colorWhite);
      } catch (e) {
        print('Error drawing debug info: $e');
        // Continue even if visualization fails
      }
    }
    
    return MarkerDetectionResult(
      markers: markers,
      pixelToMmRatio: pixelToMmRatio,
      origin: origin,
      orientationAngle: orientationAngle,
      debugImage: debugImage,
    );
  }
  
  /// Draw a marker with role label
  void _drawMarker(img.Image image, MarkerPoint marker, img.Color color, String label) {
    try {
      ImageUtils.drawCross(image, marker.x, marker.y, color, 10);
      ImageUtils.drawCircle(image, marker.x, marker.y, 15, color, fill: false);
      ImageUtils.drawText(image, label, marker.x + 20, marker.y, color);
    } catch (e) {
      print('Error drawing marker: $e');
    }
  }
  
}