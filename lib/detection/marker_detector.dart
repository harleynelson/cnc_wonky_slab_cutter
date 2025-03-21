import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:cnc_wonky_slab_cutter/utils/image_processing/color_utils.dart';
import 'package:cnc_wonky_slab_cutter/utils/image_processing/filter_utils.dart';
import 'package:image/image.dart' as img;
import '../flow_of_app/flow_manager.dart';
import '../utils/drawing/drawing_utils.dart';
import '../utils/general/error_utils.dart';
import '../utils/general/machine_coordinates.dart';

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
  
  // IMPORTANT: Store original image dimensions before any resizing
  final origWidth = image.width;
  final origHeight = image.height;
  
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
    // Since we're requiring user-provided marker locations, 
    // fall back to predefined markers immediately
    return _createFallbackResult(processImage, debugImage);
  } catch (e) {
    print('Error in marker detection: $e');
    return _createFallbackResult(processImage, debugImage);
  }
}

// TODO: let's build off this one

/// Find markers from user tap points
List<MarkerPoint> findMarkersFromUserTaps(
  img.Image image, 
  List<Map<String, dynamic>> userTapRegions,  // List of {x, y, role} maps
  {img.Image? debugImage}
) {
  final markers = <MarkerPoint>[];
  final searchRadius = math.min(image.width, image.height) ~/ 10;  // Reasonable search area
  
  for (final tap in userTapRegions) {
    final int tapX = tap['x'];
    final int tapY = tap['y'];
    final MarkerRole role = tap['role'];
    
    // Find a marker near this tap point
    final marker = findMarkerNearPoint(
      image, 
      tapX, 
      tapY, 
      searchRadius,
      role
    );
    
    markers.add(marker);
    
    // Draw the marker on debug image if available
    if (debugImage != null) {
      final color = role == MarkerRole.origin ? 
        img.ColorRgba8(255, 0, 0, 255) : 
        (role == MarkerRole.xAxis ? 
          img.ColorRgba8(0, 255, 0, 255) : 
          img.ColorRgba8(0, 0, 255, 255));
      
      DrawingUtils.drawCircle(debugImage, marker.x, marker.y, 10, color);
      DrawingUtils.drawText(debugImage, "${role.toString()}: ${marker.confidence.toStringAsFixed(2)}", 
                       marker.x + 15, marker.y, color);
      
      // Draw the search region on the debug image
      final x1 = math.max(0, tapX - searchRadius);
      final y1 = math.max(0, tapY - searchRadius);
      final x2 = math.min(image.width - 1, tapX + searchRadius);
      final y2 = math.min(image.height - 1, tapY + searchRadius);
      DrawingUtils.drawRectangle(debugImage, x1, y1, x2, y2, ColorUtils.colorYellow, fill: false);
    }
  }
  
  return markers;
}


/// Find a marker near a specified location
MarkerPoint? findMarkerNearLocation(
  img.Image image, 
  int x1, int y1, int x2, int y2,  // Search region bounds
  MarkerRole role,                 // Which marker role we're looking for
  {img.Image? debugImage}          // Optional debug image
) {
  // Log the search region
  print('Searching for ${role.toString()} marker in region: ($x1,$y1) to ($x2,$y2)');
  
  // Ensure coordinates are within image bounds
  x1 = math.max(0, x1);
  y1 = math.max(0, y1);
  x2 = math.min(image.width - 1, x2);
  y2 = math.min(image.height - 1, y2);
  
  // Skip very small regions
  if (x2 - x1 < 10 || y2 - y1 < 10) {
    print('Search region too small');
    return null;
  }
  
  try {
    // Extract region statistics (calculate average brightness)
    int totalPixels = 0;
    double sumBrightness = 0;
    
    for (int y = y1; y < y2; y++) {
      for (int x = x1; x < x2; x++) {
        final pixel = image.getPixel(x, y);
        final brightness = FilterUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        ) / 255.0; // Normalize to 0-1
        
        sumBrightness += brightness;
        totalPixels++;
      }
    }
    
    // Calculate average brightness
    final avgBrightness = totalPixels > 0 ? sumBrightness / totalPixels : 0.5;
    
    // Look for the darkest or brightest area in the region as the marker
    int bestX = -1, bestY = -1;
    double bestDifference = -1;
    
    // Determine if we should look for dark markers on light background or vice versa
    final lookForDark = avgBrightness > 0.5;
    
    // Slide a smaller window through the region to find the distinctive marker
    final windowSize = math.max(5, math.min(x2 - x1, y2 - y1) ~/ 6);
    
    for (int y = y1; y < y2 - windowSize; y += windowSize ~/ 3) {
      for (int x = x1; x < x2 - windowSize; x += windowSize ~/ 3) {
        int windowPixels = 0;
        double windowSum = 0;
        
        // Calculate window statistics
        for (int wy = 0; wy < windowSize; wy++) {
          for (int wx = 0; wx < windowSize; wx++) {
            final px = x + wx;
            final py = y + wy;
            
            final pixel = image.getPixel(px, py);
            final brightness = FilterUtils.calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            ) / 255.0; // Normalize to 0-1
            
            windowSum += brightness;
            windowPixels++;
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
    
    // Require a minimum contrast difference to prevent false positives
    if (bestDifference < 0.25 || bestX < 0 || bestY < 0) {
      print('No marker found with sufficient contrast');
      return null;
    }
    
    // Draw marker on debug image if available
    if (debugImage != null) {
      final color = lookForDark ? 
        img.ColorRgba8(255, 0, 0, 255) : 
        img.ColorRgba8(0, 255, 0, 255);
      
      DrawingUtils.drawCircle(debugImage, bestX, bestY, 10, color);
      DrawingUtils.drawText(debugImage, "${role.toString()}: ${bestDifference.toStringAsFixed(2)}", 
                         bestX + 15, bestY, color);
      
      // Draw the search region on the debug image
      DrawingUtils.drawRectangle(debugImage, x1, y1, x2, y2, ColorUtils.colorYellow, fill: false);
    }
    
    return MarkerPoint(bestX, bestY, role, confidence: bestDifference);
  } catch (e) {
    print('Error finding marker in region: $e');
    return null;
  }
}

/// Create a MarkerDetectionResult from manually-selected marker points
MarkerDetectionResult createResultFromMarkerPoints(List<MarkerPoint> markers, {img.Image? debugImage}) {
  if (markers.length < 3) {
    throw Exception('Need at least 3 markers to create a coordinate system');
  }
  
  // Find the markers by role
  final originMarker = markers.firstWhere(
    (m) => m.role == MarkerRole.origin, 
    orElse: () => markers[0]
  );
  
  final xAxisMarker = markers.firstWhere(
    (m) => m.role == MarkerRole.xAxis,
    orElse: () => markers[1]
  );
  
  final scaleMarker = markers.firstWhere(
    (m) => m.role == MarkerRole.scale,
    orElse: () => markers[2]
  );
  
  // Calculate orientation angle
  final dx = xAxisMarker.x - originMarker.x;
  final dy = xAxisMarker.y - originMarker.y;
  final orientationAngle = math.atan2(dy, dx);
  
  // Calculate pixel-to-mm ratio from scale marker distance
  final scaleX = scaleMarker.x - originMarker.x;
  final scaleY = scaleMarker.y - originMarker.y;
  final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
  
  // Use a default value if we don't have markerRealDistanceMm property
  const markerRealDistanceMm = 50.0; // Default value
  
  // Calculate pixel-to-mm ratio
  final pixelToMmRatio = markerRealDistanceMm / distancePx;
  
  // Create origin point
  final origin = CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble());
  
  return MarkerDetectionResult(
    markers: markers,
    pixelToMmRatio: pixelToMmRatio,
    origin: origin,
    orientationAngle: orientationAngle,
    debugImage: debugImage,
  );
}


/// Find a marker near a specific point that was tapped by the user
MarkerPoint findMarkerNearPoint(
  img.Image image, 
  int centerX, 
  int centerY, 
  int searchRadius,
  MarkerRole role
) {
  // Define the search region
  final int x1 = math.max(0, centerX - searchRadius);
  final int y1 = math.max(0, centerY - searchRadius);
  final int x2 = math.min(image.width - 1, centerX + searchRadius);
  final int y2 = math.min(image.height - 1, centerY + searchRadius);
  
  print('Searching for ${role.toString()} marker in region: ($x1,$y1) to ($x2,$y2)');
  
  try {
    // Extract region statistics
    int totalPixels = 0;
    double sumBrightness = 0;
    
    for (int y = y1; y < y2; y++) {
      for (int x = x1; x < x2; x++) {
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          final pixel = image.getPixel(x, y);
          final brightness = FilterUtils.calculateLuminance(
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
    
    // Slide a smaller window through the region to find the distinctive marker
    final windowSize = math.max(5, math.min(x2 - x1, y2 - y1) ~/ 6);
    
    for (int y = y1; y < y2 - windowSize; y += windowSize ~/ 3) {
      for (int x = x1; x < x2 - windowSize; x += windowSize ~/ 3) {
        int windowPixels = 0;
        double windowSum = 0;
        
        // Calculate window statistics
        for (int wy = 0; wy < windowSize; wy++) {
          for (int wx = 0; wx < windowSize; wx++) {
            final px = x + wx;
            final py = y + wy;
            
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              final pixel = image.getPixel(px, py);
              final brightness = FilterUtils.calculateLuminance(
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
    
    // Use the detected point if we found one with good confidence
    if (bestDifference >= 0.15 && bestX >= 0 && bestY >= 0) {
      return MarkerPoint(bestX, bestY, role, confidence: bestDifference);
    }
    
    // If we couldn't find a clear marker, simply use the exact tap point
    return MarkerPoint(centerX, centerY, role, confidence: 0.5);
  } catch (e) {
    print('Error finding marker in region: $e');
    // Always fall back to using the tap point directly
    return MarkerPoint(centerX, centerY, role, confidence: 0.5);
  }
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
          final brightness = FilterUtils.calculateLuminance(
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
    
    // Slide a smaller window through the region to find the distinctive marker
    final windowSize = math.max(5, math.min(regionWidth, regionHeight) ~/ 6);
    
    for (int y = y1; y < y2 - windowSize; y += windowSize ~/ 3) {
      for (int x = x1; x < x2 - windowSize; x += windowSize ~/ 3) {
        int windowPixels = 0;
        double windowSum = 0;
        
        // Calculate window statistics
        for (int wy = 0; wy < windowSize; wy++) {
          for (int wx = 0; wx < windowSize; wx++) {
            final px = x + wx;
            final py = y + wy;
            
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              final pixel = image.getPixel(px, py);
              final brightness = FilterUtils.calculateLuminance(
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
    
    // Require a higher minimum contrast difference to prevent false positives
    if (bestDifference < 0.25 || bestX < 0 || bestY < 0) {
      return null;
    }
    
    // Draw marker on debug image if available
    if (debugImage != null) {
      final color = lookForDark ? 
        img.ColorRgba8(255, 0, 0, 255) : 
        img.ColorRgba8(0, 255, 0, 255);
      
      DrawingUtils.drawCircle(debugImage, bestX, bestY, 10, color);
      DrawingUtils.drawText(debugImage, "Contrast: ${bestDifference.toStringAsFixed(2)}", 
                         bestX + 15, bestY, color);
    }
    
    return MarkerPoint(bestX, bestY, MarkerRole.origin, confidence: bestDifference);
  } catch (e) {
    print('Error finding marker in region: $e');
    return null;
  }
}
/// Find high contrast blobs that could be markers
List<MarkerPoint> _findHighContrastBlobs(img.Image image, img.Image? debugImage) {
  final markers = <MarkerPoint>[];
  
  try {
    // Convert to grayscale
    final grayscale = FilterUtils.convertToGrayscale(image);
    
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
        DrawingUtils.drawCircle(debugImage, properties['centerX']!.round(), properties['centerY']!.round(), 8, ColorUtils.colorCyan, fill: false);
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
      final intensity = FilterUtils.calculateLuminance(
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
      _drawMarker(debugImage, originMarker, ColorUtils.colorRed, "Origin (Fallback)");
      _drawMarker(debugImage, xAxisMarker, ColorUtils.colorGreen, "X-Axis (Fallback)");
      _drawMarker(debugImage, scaleMarker, ColorUtils.colorBlue, "Scale (Fallback)");
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
      origin: CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble()),
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
          final pixelValue = FilterUtils.calculateLuminance(
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
          sum += FilterUtils.calculateLuminance(
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
            DrawingUtils.drawCircle(debugImage, centerX, centerY, 5, ColorUtils.colorBlue, fill: false);
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
            final isBlack = FilterUtils.calculateLuminance(
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
      final isBlack = FilterUtils.calculateLuminance(
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
      // Sort candidates by y coordinate (vertical position) first
      candidates.sort((a, b) => a.y.compareTo(b.y));
      
      // Find the lowest (highest y) markers - these should be origin and x-axis
      final bottom = candidates.reversed.take(2).toList();
      bottom.sort((a, b) => a.x.compareTo(b.x));
      
      // Use the leftmost as origin and rightmost as x-axis
      final originMarker = bottom.first;  // Leftmost of the bottom markers
      final xAxisMarker = bottom.last;    // Rightmost of the bottom markers
      
      // Find the marker that's furthest from both (this should be scale/y-axis)
      double maxDist = 0;
      MarkerPoint? scaleMarker;
      
      for (final candidate in candidates) {
        if (candidate == originMarker || candidate == xAxisMarker) continue;
        
        final distFromOrigin = math.sqrt(
          math.pow(candidate.x - originMarker.x, 2) + 
          math.pow(candidate.y - originMarker.y, 2)
        );
        
        final distFromXAxis = math.sqrt(
          math.pow(candidate.x - xAxisMarker.x, 2) + 
          math.pow(candidate.y - xAxisMarker.y, 2)
        );
        
        final combinedDist = distFromOrigin + distFromXAxis;
        if (combinedDist > maxDist) {
          maxDist = combinedDist;
          scaleMarker = candidate;
        }
      }
      
      if (scaleMarker == null) {
        // If we couldn't find a scale marker, use the highest remaining marker
        scaleMarker = candidates.firstWhere(
          (m) => m != originMarker && m != xAxisMarker,
          orElse: () => candidates.first  // Fallback if there are only 2 candidates
        );
      }
      
      return [
        MarkerPoint(originMarker.x, originMarker.y, MarkerRole.origin, confidence: 0.9),
        MarkerPoint(xAxisMarker.x, xAxisMarker.y, MarkerRole.xAxis, confidence: 0.9),
        MarkerPoint(scaleMarker.x, scaleMarker.y, MarkerRole.scale, confidence: 0.9),
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
    
    // Log the detected marker positions
    print('DEBUG MARKERS: Origin: (${originMarker.x}, ${originMarker.y})');
    print('DEBUG MARKERS: X-Axis: (${xAxisMarker.x}, ${xAxisMarker.y})');
    print('DEBUG MARKERS: Scale: (${scaleMarker.x}, ${scaleMarker.y})');
    
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
    
    // Log the calculated values
    print('DEBUG MARKERS: Orientation angle: ${orientationAngle * 180 / math.pi} degrees');
    print('DEBUG MARKERS: Distance in pixels: $distancePx');
    print('DEBUG MARKERS: Pixel-to-mm ratio: $pixelToMmRatio');
    
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
        _drawMarker(debugImage, originMarker, ColorUtils.colorRed, "Origin");
        _drawMarker(debugImage, xAxisMarker, ColorUtils.colorGreen, "X-Axis");
        _drawMarker(debugImage, scaleMarker, ColorUtils.colorBlue, "Scale");
        
        // Draw connecting lines
        DrawingUtils.drawLine(
          debugImage, 
          originMarker.x, originMarker.y, 
          xAxisMarker.x, xAxisMarker.y, 
          ColorUtils.colorRed
        );
        
        DrawingUtils.drawLine(
          debugImage, 
          originMarker.x, originMarker.y, 
          scaleMarker.x, scaleMarker.y, 
          ColorUtils.colorBlue
        );
        
        // Add calibration info text
        final infoText = "Ratio: ${pixelToMmRatio.toStringAsFixed(3)} mm/px";
        DrawingUtils.drawText(debugImage, infoText, 10, 10, ColorUtils.colorWhite);
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
      // Draw a larger, more visible circle
      DrawingUtils.drawCircle(image, marker.x, marker.y, 15, color, fill: false);
      
      // Draw a filled inner circle
      DrawingUtils.drawCircle(image, marker.x, marker.y, 8, color, fill: true);
      
      // Add a glow effect with a lighter color
      final glowColor = img.ColorRgba8(
        math.min(255, color.r.toInt() + 50),
        math.min(255, color.g.toInt() + 50),
        math.min(255, color.b.toInt() + 50),
        120
      );
      DrawingUtils.drawCircle(image, marker.x, marker.y, 20, glowColor, fill: false);
      
      // Draw crosshair
      const crosshairSize = 12;
      DrawingUtils.drawLine(
        image,
        marker.x - crosshairSize, marker.y,
        marker.x + crosshairSize, marker.y,
        color
      );
      
      DrawingUtils.drawLine(
        image,
        marker.x, marker.y - crosshairSize,
        marker.x, marker.y + crosshairSize,
        color
      );
      
      // Draw label with better visibility
      final labelBg = img.ColorRgba8(0, 0, 0, 180);
      
      // Add a background rectangle for the text
      DrawingUtils.drawRectangle(
        image,
        marker.x + 5, marker.y - 15,
        marker.x + 5 + label.length * 8, marker.y + 5,
        labelBg,
        fill: true
      );
      
      // Draw the label text with a brighter color for contrast
      DrawingUtils.drawText(image, label, marker.x + 10, marker.y - 10, color);
    } catch (e) {
      print('Error drawing marker: $e');
    }
  }
  
}