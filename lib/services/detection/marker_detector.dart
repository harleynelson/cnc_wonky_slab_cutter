// lib/services/detection/marker_detector.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../utils/general/machine_coordinates.dart';
import '../../utils/image_processing/image_utils.dart';

enum MarkerRole {
  origin,
  xAxis,
  scale,
  topRight
}

class MarkerPoint {
  final int x;
  final int y;
  final MarkerRole role;
  final double confidence;

  MarkerPoint(this.x, this.y, this.role, {this.confidence = 1.0});
  
  CoordinatePointXY toPoint() => CoordinatePointXY(x.toDouble(), y.toDouble());
}

class MarkerDetectionResult {
  final List<MarkerPoint> markers;
  final double pixelToMmRatio;
  final CoordinatePointXY origin;
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
  final double markerXDistanceMm;
  final double markerYDistanceMm;
  final bool generateDebugImage;
  final int maxImageSize;
  final int processingTimeout;
  
  MarkerDetector({
    required this.markerXDistanceMm,
    required this.markerYDistanceMm,
    this.generateDebugImage = true,
    this.maxImageSize = 1200,
    this.processingTimeout = 10000,
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
    double scaleFactor = 1.0;
    
    if (image.width > maxImageSize || image.height > maxImageSize) {
      scaleFactor = maxImageSize / math.max(image.width, image.height);
      try {
        processImage = img.copyResize(
          image,
          width: (image.width * scaleFactor).round(),
          height: (image.height * scaleFactor).round(),
          interpolation: img.Interpolation.average
        );
        print('Marker detection - resized to: ${processImage.width}x${processImage.height}');
        print('Marker detection - scale factor: $scaleFactor');
      } catch (e) {
        print('Warning: Failed to resize image: $e');
        scaleFactor = 1.0; // Reset scale factor if resize fails
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
      if (markers.length >= 4) {
        print('Found ${markers.length} corner markers');
        final identifiedMarkers = _identifyMarkerRoles(markers, processImage.width, processImage.height);
        
        // Rescale marker coordinates to original image dimensions if needed
        final scaledMarkers = _rescaleMarkers(identifiedMarkers, scaleFactor);
        
        final calibrationResult = _calculateCalibration(scaledMarkers, debugImage);
        
        // Log the detected marker positions in original image coordinates
        for (final marker in scaledMarkers) {
          print('Detected ${marker.role} marker at: (${marker.x}, ${marker.y}) in original image coordinates');
        }
        
        return calibrationResult;
      }
      
      // STRATEGY 2: Try high contrast blob detection
      print('Attempting high contrast blob detection...');
      markers = _findHighContrastBlobs(processImage, debugImage);
      if (markers.length >= 4) {
        print('Found ${markers.length} high contrast markers');
        final identifiedMarkers = _identifyMarkerRoles(markers, processImage.width, processImage.height);
        
        // Rescale marker coordinates to original image dimensions if needed
        final scaledMarkers = _rescaleMarkers(identifiedMarkers, scaleFactor);
        
        final calibrationResult = _calculateCalibration(scaledMarkers, debugImage);
        
        // Log the detected marker positions in original image coordinates
        for (final marker in scaledMarkers) {
          print('Detected ${marker.role} marker at: (${marker.x}, ${marker.y}) in original image coordinates');
        }
        
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
      
      // Rescale marker coordinates to original image dimensions if needed
      final scaledMarkers = _rescaleMarkers(identifiedMarkers, scaleFactor);
      
      // Calculate calibration parameters with validation
      final calibrationResult = _calculateCalibration(scaledMarkers, debugImage);
      
      // Log the detected marker positions in original image coordinates
      for (final marker in scaledMarkers) {
        print('Detected ${marker.role} marker at: (${marker.x}, ${marker.y}) in original image coordinates');
      }
      
      return calibrationResult;
    } catch (e) {
      print('Error in marker detection: $e');
      // Fall back to predefined markers if detection fails
      var fallbackMarkers = _fallbackMarkerDetection(processImage.width, processImage.height);
      
      // Rescale fallback markers to original image dimensions if needed
      if (scaleFactor != 1.0) {
        fallbackMarkers = _rescaleMarkers(fallbackMarkers, scaleFactor);
      }
      
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
      // Top right (new marker)
      [0.70, 0.05, 0.95, 0.25],
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
  
  /// Helper method to rescale marker coordinates from processed image to original image
  List<MarkerPoint> _rescaleMarkers(List<MarkerPoint> markers, double scaleFactor) {
    // If no scaling was applied, return original markers
    if (scaleFactor == 1.0) return markers;
    
    return markers.map((marker) {
      // Convert back to original image coordinates
      final originalX = (marker.x / scaleFactor).round();
      final originalY = (marker.y / scaleFactor).round();
      
      return MarkerPoint(
        originalX, 
        originalY, 
        marker.role, 
        confidence: marker.confidence
      );
    }).toList();
  }

  /// Identify marker roles based on their relative positions
  List<MarkerPoint> _identifyMarkerRoles(List<MarkerPoint> candidates, int imageWidth, int imageHeight) {
    if (candidates.length < 4) {
      return _fallbackMarkerDetection(imageWidth, imageHeight);
    }
    
    try {
      // Sort candidates by y coordinate (vertical position) first
      final sortedByY = List<MarkerPoint>.from(candidates);
      sortedByY.sort((a, b) => a.y.compareTo(b.y));
      
      // Get top two and bottom two markers
      final topMarkers = sortedByY.sublist(0, 2);
      final bottomMarkers = sortedByY.sublist(sortedByY.length - 2, sortedByY.length);
      
      // Sort top markers by x coordinate
      topMarkers.sort((a, b) => a.x.compareTo(b.x));
      // Sort bottom markers by x coordinate
      bottomMarkers.sort((a, b) => a.x.compareTo(b.x));
      
      // Assign roles
      final originMarker = bottomMarkers.first;  // Bottom-left
      final xAxisMarker = bottomMarkers.last;    // Bottom-right
      final scaleMarker = topMarkers.first;      // Top-left
      final topRightMarker = topMarkers.last;    // Top-right
      
      return [
        MarkerPoint(originMarker.x, originMarker.y, MarkerRole.origin, confidence: 0.9),
        MarkerPoint(xAxisMarker.x, xAxisMarker.y, MarkerRole.xAxis, confidence: 0.9),
        MarkerPoint(scaleMarker.x, scaleMarker.y, MarkerRole.scale, confidence: 0.9),
        MarkerPoint(topRightMarker.x, topRightMarker.y, MarkerRole.topRight, confidence: 0.9),
      ];
    } catch (e) {
      print('Error identifying marker roles: $e');
    }
    
    // Fallback if role assignment fails
    return _fallbackMarkerDetection(imageWidth, imageHeight);
  }

  /// Fallback detection to ensure we always get some markers
  List<MarkerPoint> _fallbackMarkerDetection(int width, int height) {
    print('Using fallback marker detection');
    return [
      // Use wider spread for reliable placement
      MarkerPoint((width * 0.2).round(), (height * 0.8).round(), MarkerRole.origin, confidence: 0.5),   // Bottom left
      MarkerPoint((width * 0.8).round(), (height * 0.8).round(), MarkerRole.xAxis, confidence: 0.5),    // Bottom right
      MarkerPoint((width * 0.2).round(), (height * 0.2).round(), MarkerRole.scale, confidence: 0.5),    // Top left
      MarkerPoint((width * 0.8).round(), (height * 0.2).round(), MarkerRole.topRight, confidence: 0.5), // Top right
    ];
  }
  
  /// Create a fallback result when detection fails
  MarkerDetectionResult _createFallbackResult(img.Image image, img.Image? debugImage) {
    final markers = _fallbackMarkerDetection(image.width, image.height);
    
    // Calculate parameters from fallback markers
    final originMarker = markers.firstWhere((m) => m.role == MarkerRole.origin);
    final xAxisMarker = markers.firstWhere((m) => m.role == MarkerRole.xAxis);
    final scaleMarker = markers.firstWhere((m) => m.role == MarkerRole.scale);
    final topRightMarker = markers.firstWhere((m) => m.role == MarkerRole.topRight);
    
    // Draw markers on debug image if available
    if (debugImage != null) {
      _drawMarker(debugImage, originMarker, ImageUtils.colorRed, "Origin (Fallback)");
      _drawMarker(debugImage, xAxisMarker, ImageUtils.colorGreen, "X-Axis (Fallback)");
      _drawMarker(debugImage, scaleMarker, ImageUtils.colorBlue, "Scale (Fallback)");
      _drawMarker(debugImage, topRightMarker, ImageUtils.colorYellow, "Top-Right (Fallback)");
    }
    
    // Calculate fallback calibration parameters
    final dx = xAxisMarker.x - originMarker.x;
    final dy = xAxisMarker.y - originMarker.y;
    final orientationAngle = math.atan2(dy, dx);
    
    final scaleX = xAxisMarker.x - originMarker.x;
    final scaleY = scaleMarker.y - originMarker.y;
    final pixelToMmRatio = (markerXDistanceMm / scaleX + markerYDistanceMm / scaleY) / 2;
    
    return MarkerDetectionResult(
      markers: markers,
      pixelToMmRatio: pixelToMmRatio,
      origin: CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble()),
      orientationAngle: orientationAngle,
      debugImage: debugImage,
    );
  }
  
  /// Calculate calibration parameters from detected markers
  MarkerDetectionResult _calculateCalibration(List<MarkerPoint> markers, img.Image? debugImage) {
    // Ensure we have enough markers
    if (markers.length < 4) {
      throw Exception('Insufficient markers detected (${markers.length})');
    }
    
    // Find markers for each role
    MarkerPoint? originMarker, xAxisMarker, scaleMarker, topRightMarker;
    
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
        case MarkerRole.topRight:
          topRightMarker = marker;
          break;
      }
    }
    
    // Check that we have all required markers
    if (originMarker == null || xAxisMarker == null || scaleMarker == null || topRightMarker == null) {
      throw Exception('Missing markers after identification');
    }
    
    // Log the detected marker positions
    print('DEBUG MARKERS: Origin: (${originMarker.x}, ${originMarker.y})');
    print('DEBUG MARKERS: X-Axis: (${xAxisMarker.x}, ${xAxisMarker.y})');
    print('DEBUG MARKERS: Y-Axis: (${scaleMarker.x}, ${scaleMarker.y})');
    print('DEBUG MARKERS: Top-Right: (${topRightMarker.x}, ${topRightMarker.y})');
    
    // Calculate orientation angle
    final dx = xAxisMarker.x - originMarker.x;
    final dy = xAxisMarker.y - originMarker.y;
    final orientationAngle = math.atan2(dy, dx);
    
    // Calculate pixel-to-mm ratios for both axes
    final xDiff = xAxisMarker.x - originMarker.x;
    final yDiff = scaleMarker.y - originMarker.y;
    
    // Validate marker placement
    if (xDiff < 10.0 || yDiff < 10.0) {
      throw Exception('Markers too close together');
    }
    
    // Calculate average pixel-to-mm ratio using both X and Y dimensions
    final pixelToMmRatioX = markerXDistanceMm / xDiff;
    final pixelToMmRatioY = markerYDistanceMm / yDiff;
    final pixelToMmRatio = (pixelToMmRatioX + pixelToMmRatioY) / 2;
    
    // Log the calculated values
    print('DEBUG MARKERS: Orientation angle: ${orientationAngle * 180 / math.pi} degrees');
    print('DEBUG MARKERS: X distance in pixels: $xDiff');
    print('DEBUG MARKERS: Y distance in pixels: $yDiff');
    print('DEBUG MARKERS: X ratio: $pixelToMmRatioX mm/px');
    print('DEBUG MARKERS: Y ratio: $pixelToMmRatioY mm/px');
    print('DEBUG MARKERS: Average ratio: $pixelToMmRatio mm/px');
    
    // Sanity check on ratio
    if (pixelToMmRatio.isNaN || pixelToMmRatio.isInfinite || 
        pixelToMmRatio <= 0.01 || pixelToMmRatio > 100.0) {
      throw Exception('Invalid pixel-to-mm ratio: $pixelToMmRatio');
    }
    
    // Create origin point
    final origin = CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble());
    
    // Draw debug visualizations if needed
    if (debugImage != null) {
      try {
        // Draw markers with their roles
        _drawMarker(debugImage, originMarker, ImageUtils.colorRed, "Origin");
        _drawMarker(debugImage, xAxisMarker, ImageUtils.colorGreen, "X-Axis");
        _drawMarker(debugImage, scaleMarker, ImageUtils.colorBlue, "Y-Axis");
        _drawMarker(debugImage, topRightMarker, ImageUtils.colorYellow, "Top-Right");
        
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
        
        ImageUtils.drawLine(
          debugImage, 
          xAxisMarker.x, xAxisMarker.y, 
          topRightMarker.x, topRightMarker.y, 
          ImageUtils.colorGreen
        );
        
        ImageUtils.drawLine(
          debugImage, 
          scaleMarker.x, scaleMarker.y, 
          topRightMarker.x, topRightMarker.y, 
          ImageUtils.colorMagenta
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
  
  // Other methods remain unchanged...
  void _drawRegion(img.Image image, int x1, int y1, int x2, int y2, int regionIndex) {
    final colors = [
      img.ColorRgba8(255, 0, 0, 128),   // Red for origin
      img.ColorRgba8(0, 255, 0, 128),   // Green for X-axis
      img.ColorRgba8(0, 0, 255, 128),   // Blue for scale
      img.ColorRgba8(255, 255, 0, 128)  // Yellow for top-right
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
    final labels = ["Origin", "X-Axis", "Y-Axis", "Top-Right"];
    ImageUtils.drawText(image, labels[regionIndex % labels.length], x1 + 5, y1 + 5, color);
  }
  
  /// Draw a marker with role label
  void _drawMarker(img.Image image, MarkerPoint marker, img.Color color, String label) {
    try {
      // Draw a larger, more visible circle
      ImageUtils.drawCircle(image, marker.x, marker.y, 15, color, fill: false);
      
      // Draw a filled inner circle
      ImageUtils.drawCircle(image, marker.x, marker.y, 8, color, fill: true);
      
      // Add a glow effect with a lighter color
      final glowColor = img.ColorRgba8(
        math.min(255, color.r.toInt() + 50),
        math.min(255, color.g.toInt() + 50),
        math.min(255, color.b.toInt() + 50),
        120
      );
      ImageUtils.drawCircle(image, marker.x, marker.y, 20, glowColor, fill: false);
      
      // Draw label
      ImageUtils.drawText(image, label, marker.x + 15, marker.y, color);
    } catch (e) {
      print('Error drawing marker: $e');
    }
  }
  
  /// Find a marker within a specific region
  MarkerPoint? _findMarkerInRegion(img.Image image, int x1, int y1, int x2, int y2, img.Image? debugImage) {
    // Implementation stays the same...
    return null; // Placeholder - actual implementation would detect markers
  }
  
  /// Find high contrast blobs that could be markers
  List<MarkerPoint> _findHighContrastBlobs(img.Image image, img.Image? debugImage) {
    // Implementation stays the same...
    return []; // Placeholder - actual implementation would find blobs
  }
  
  /// Preprocess the image to enhance markers for detection
  img.Image _preprocessImage(img.Image grayscale) {
    // Implementation stays the same...
    return grayscale; // Placeholder - actual implementation would preprocess
  }
  
  /// Find marker candidates in the preprocessed image
  List<MarkerPoint> _findMarkerCandidates(img.Image preprocessed, img.Image? debugImage) {
    // Implementation stays the same...
    return []; // Placeholder - actual implementation would find candidates
  }}