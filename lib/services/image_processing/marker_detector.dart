import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../gcode/machine_coordinates.dart';
// Use prefix to avoid naming conflicts
import 'image_utils.dart' as img_utils;

class MarkerPoint {
  final int x;
  final int y;
  final MarkerRole role;

  MarkerPoint(this.x, this.y, this.role);
}

enum MarkerRole {
  origin,
  xAxis,
  scale
}

class MarkerDetectionResult {
  final List<MarkerPoint> markers;
  final double pixelToMmRatio;
  final Point origin;
  final double orientationAngle;

  MarkerDetectionResult({
    required this.markers,
    required this.pixelToMmRatio,
    required this.origin,
    required this.orientationAngle,
  });
}

class MarkerDetector {
  final double markerRealDistanceMm;
  
  MarkerDetector({required this.markerRealDistanceMm});
  
  /// Detect markers in the image and calculate calibration parameters
  Future<MarkerDetectionResult> detectMarkers(File imageFile) async {
    // Read the image
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    
    if (image == null) {
      throw Exception('Failed to decode image');
    }
    
    // In a real implementation, we would use advanced computer vision
    // Here we'll use a simplified approach
    final List<MarkerPoint> markers = _findMarkers(image);
    
    // Sort markers to identify which is which
    final sortedMarkers = _identifyMarkers(markers, image.width, image.height);
    
    // Calculate calibration parameters
    final calibrationResult = _calculateCalibration(sortedMarkers);
    
    return calibrationResult;
  }
  
  /// Find markers in the image using color thresholding
  List<MarkerPoint> _findMarkers(img.Image image) {
    // Convert image to grayscale
    final grayImage = img_utils.ImageUtils.convertToGrayscale(image);
    
    // For demonstration purposes, we'll just use predefined marker positions
    // This would be replaced with actual detection algorithm
    final List<MarkerPoint> markers = [
      MarkerPoint((image.width * 0.2).round(), (image.height * 0.2).round(), MarkerRole.origin),
      MarkerPoint((image.width * 0.8).round(), (image.height * 0.2).round(), MarkerRole.xAxis),
      MarkerPoint((image.width * 0.2).round(), (image.height * 0.8).round(), MarkerRole.scale),
    ];
    
    return markers;
  }
  
  /// Identify which marker is which
  List<MarkerPoint> _identifyMarkers(List<MarkerPoint> markers, int width, int height) {
    // In a real implementation, we would identify markers based on their positions
    // or special features
    
    // For this simple example, we'll return the predefined roles
    return markers;
  }
  
  /// Calculate calibration parameters from the detected markers
  MarkerDetectionResult _calculateCalibration(List<MarkerPoint> markers) {
    // Find origin marker
    final originMarker = markers.firstWhere((m) => m.role == MarkerRole.origin);
    final xAxisMarker = markers.firstWhere((m) => m.role == MarkerRole.xAxis);
    final scaleMarker = markers.firstWhere((m) => m.role == MarkerRole.scale);
    
    // Calculate orientation angle
    final dx = xAxisMarker.x - originMarker.x;
    final dy = xAxisMarker.y - originMarker.y;
    final orientationAngle = math.atan2(dy, dx);
    
    // Calculate mm per pixel from the distance between origin and scale marker
    final scaleX = scaleMarker.x - originMarker.x;
    final scaleY = scaleMarker.y - originMarker.y;
    final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
    final pixelToMmRatio = markerRealDistanceMm / distancePx;
    
    // Create origin point
    final origin = Point(originMarker.x.toDouble(), originMarker.y.toDouble());
    
    return MarkerDetectionResult(
      markers: markers,
      pixelToMmRatio: pixelToMmRatio,
      origin: origin,
      orientationAngle: orientationAngle,
    );
  }
  
  /// Visualize markers on the given image
  img.Image visualizeMarkers(img.Image image, List<MarkerPoint> markers) {
    final outputImage = img.copyResize(image, width: image.width, height: image.height);
    
    // Draw each marker
    for (final marker in markers) {
      // Choose color based on marker role
      int color;
      switch (marker.role) {
        case MarkerRole.origin:
          color = img_utils.ImageUtils.colorRed as int;  // Red for origin
          break;
        case MarkerRole.xAxis:
          color = img_utils.ImageUtils.colorGreen as int;  // Green for X-axis
          break;
        case MarkerRole.scale:
          color = img_utils.ImageUtils.colorBlue as int;  // Blue for scale
          break;
      }
      
      // Draw cross
      img_utils.ImageUtils.drawCross(outputImage, marker.x, marker.y, color as img.Color, 10);
      
      // Add label
      final label = marker.role.toString().split('.').last;
      img_utils.ImageUtils.drawText(outputImage, label, marker.x + 15, marker.y, color as img.Color);
    }
    
    return outputImage;
  }
}