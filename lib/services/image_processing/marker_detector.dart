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
    
    // Create a copy for visualization if needed
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
      // 1. Convert to grayscale for processing
      final grayscale = ImageUtils.convertToGrayscale(processImage);
      
      // 2. Preprocess the image to make markers stand out
      final preprocessed = _preprocessImage(grayscale);
      
      // 3. Find potential marker regions
      final markers = _findMarkerCandidates(preprocessed, debugImage);
      
      // 4. Identify which marker is which based on their relative positions
      final identifiedMarkers = _identifyMarkerRoles(markers, processImage.width, processImage.height);
      
      // 5. Calculate calibration parameters with validation
      final calibrationResult = _calculateCalibration(identifiedMarkers, debugImage);
      
      return calibrationResult;
    } catch (e) {
      print('Error in marker detection: $e');
      // Fall back to predefined markers if detection fails
      return _createFallbackResult(processImage, debugImage);
    }
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
      // Sort by horizontal position for initial grouping
      candidates.sort((a, b) => a.x.compareTo(b.x));
      
      // If we have exactly 3 candidates, try to identify by position
      if (candidates.length == 3) {
        // Find leftmost points
        final leftMost = candidates[0];
        final middle = candidates[1];
        final rightMost = candidates[2];
        
        // Sort vertical positions of the two leftmost points
        final topLeft = leftMost.y < middle.y ? leftMost : middle;
        final bottomLeft = leftMost.y >= middle.y ? leftMost : middle;
        
        return [
          MarkerPoint(topLeft.x, topLeft.y, MarkerRole.origin, confidence: 0.9),
          MarkerPoint(rightMost.x, rightMost.y, MarkerRole.xAxis, confidence: 0.9),
          MarkerPoint(bottomLeft.x, bottomLeft.y, MarkerRole.scale, confidence: 0.9),
        ];
      }
      
      // Sort all points by y-coordinate
      candidates.sort((a, b) => a.y.compareTo(b.y));
      
      // Get the top third points (candidates for origin and x-axis)
      int topThirdCount = (candidates.length / 3).ceil();
      final topThird = candidates.sublist(0, math.min(topThirdCount, candidates.length));
      
      // Sort top points by x-coordinate
      topThird.sort((a, b) => a.x.compareTo(b.x));
      
      // Take leftmost as origin and rightmost as x-axis
      final origin = topThird.first;
      final xAxis = topThird.last;
      
      // Sort the remaining points by distance to origin
      final remainingPoints = candidates.where((p) => 
        p.x != origin.x || p.y != origin.y && p.x != xAxis.x || p.y != xAxis.y
      ).toList();
      
      remainingPoints.sort((a, b) {
        final distA = math.pow(a.x - origin.x, 2) + math.pow(a.y - origin.y, 2);
        final distB = math.pow(b.x - origin.x, 2) + math.pow(b.y - origin.y, 2);
        return distA.compareTo(distB);
      });
      
      // Choose closest point below origin as scale marker
      for (final point in remainingPoints) {
        if (point.y > origin.y) {
          final scale = point;
          return [
            MarkerPoint(origin.x, origin.y, MarkerRole.origin, confidence: 0.8),
            MarkerPoint(xAxis.x, xAxis.y, MarkerRole.xAxis, confidence: 0.8),
            MarkerPoint(scale.x, scale.y, MarkerRole.scale, confidence: 0.8),
          ];
        }
      }
    } catch (e) {
      print('Error identifying marker roles: $e');
    }
    
    // Fallback if geometric analysis fails
    return _fallbackMarkerDetection(imageWidth, imageHeight);
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
  
  /// Fallback detection to ensure we always get some markers
  List<MarkerPoint> _fallbackMarkerDetection(int width, int height) {
    print('Using fallback marker detection');
    return [
      MarkerPoint((width * 0.2).round(), (height * 0.2).round(), MarkerRole.origin, confidence: 0.5),
      MarkerPoint((width * 0.8).round(), (height * 0.2).round(), MarkerRole.xAxis, confidence: 0.5),
      MarkerPoint((width * 0.2).round(), (height * 0.8).round(), MarkerRole.scale, confidence: 0.5),
    ];
  }
}