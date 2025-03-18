// lib/utils/general/machine_coordinates.dart
// Common static methods for coordinate transformations

import 'dart:math' as math;
import 'dart:ui';

/// Represents a point in 2D space
class CoordinatePointXY {
  final double x;
  final double y;
  
  CoordinatePointXY(this.x, this.y);
  
  /// Calculate the distance to another point
  double distanceTo(CoordinatePointXY other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  @override
  String toString() => 'Point($x, $y)';
}

/// Represents a machine coordinate system calibrated from image pixels
class MachineCoordinateSystem {
  final CoordinatePointXY originPx;
  final double orientationRad;
  final double pixelToMmRatio;
  
  MachineCoordinateSystem({
    required this.originPx,
    required this.orientationRad,
    required this.pixelToMmRatio,
  });

  /// Convert a point from image coordinates to display (canvas) coordinates
  static CoordinatePointXY imageToDisplayCoordinates(
    CoordinatePointXY imagePoint, 
    Size imageSize, 
    Size displaySize
  ) {
    // Log input values for debugging
    print('DEBUG IMG2DISP: Convert image (${imagePoint.x}, ${imagePoint.y}) from img size ${imageSize.width}x${imageSize.height} to display ${displaySize.width}x${displaySize.height}');
    
    final imageAspect = imageSize.width / imageSize.height;
    final displayAspect = displaySize.width / displaySize.height;
    
    double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
    
    if (imageAspect > displayAspect) {
      // Image is wider than display area - fill width
      displayWidth = displaySize.width;
      displayHeight = displayWidth / imageAspect;
      offsetY = (displaySize.height - displayHeight) / 2;
    } else {
      // Image is taller than display area - fill height
      displayHeight = displaySize.height;
      displayWidth = displayHeight * imageAspect;
      offsetX = (displaySize.width - displayWidth) / 2;
    }

    print('DEBUG IMG2DISP: Scaled to ${displayWidth}x${displayHeight} with offset (${offsetX}, ${offsetY})');
    
    // Calculate normalized position within the image
    final normalizedX = imagePoint.x / imageSize.width;
    final normalizedY = imagePoint.y / imageSize.height;
    
    // Convert to display coordinates
    final displayX = normalizedX * displayWidth + offsetX;
    final displayY = normalizedY * displayHeight + offsetY;
    
    print('DEBUG IMG2DISP: Result: display (${displayX}, ${displayY})');
    
    return CoordinatePointXY(displayX, displayY);
  }

  /// Convert a point from display (canvas) coordinates to image coordinates
  static CoordinatePointXY displayToImageCoordinates(
    CoordinatePointXY displayPoint, 
    Size imageSize, 
    Size displaySize
  ) {
    // Log input values for debugging
    print('DEBUG DISP2IMG: Convert display (${displayPoint.x}, ${displayPoint.y}) to image coords');
    
    // Calculate scale and offset - maintain aspect ratio
    final imageAspect = imageSize.width / imageSize.height;
    final displayAspect = displaySize.width / displaySize.height;
    
    double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
    
    if (imageAspect > displayAspect) {
      // Image is wider than display (letterboxed)
      displayWidth = displaySize.width;
      displayHeight = displayWidth / imageAspect;
      offsetY = (displaySize.height - displayHeight) / 2;
    } else {
      // Image is taller than display (pillarboxed)
      displayHeight = displaySize.height;
      displayWidth = displayHeight * imageAspect;
      offsetX = (displaySize.width - displayWidth) / 2;
    }
    
    print('DEBUG DISP2IMG: Scaled area ${displayWidth}x${displayHeight} with offset (${offsetX}, ${offsetY})');
    
    // Check if point is within the image display area
    bool isOutsideBounds = displayPoint.x < offsetX || 
                          displayPoint.x > offsetX + displayWidth ||
                          displayPoint.y < offsetY || 
                          displayPoint.y > offsetY + displayHeight;
    
    if (isOutsideBounds) {
      print('WARNING DISP2IMG: Display point outside image display area');
    }
    
    // Reverse the transformation - account for offset then normalize
    final normalizedX = (displayPoint.x - offsetX) / displayWidth;
    final normalizedY = (displayPoint.y - offsetY) / displayHeight;
    
    // Convert normalized coordinates to image coordinates
    final imageX = normalizedX * imageSize.width;
    final imageY = normalizedY * imageSize.height;
    
    print('DEBUG DISP2IMG: Result: image (${imageX}, ${imageY})');
    
    return CoordinatePointXY(imageX, imageY);
  }
  
  /// Convert a point from pixel coordinates to machine (mm) coordinates
  CoordinatePointXY pixelToMachineCoords(CoordinatePointXY pixelPoint) {
    // Translate to origin
    final px = pixelPoint.x - originPx.x;
    final py = pixelPoint.y - originPx.y;
    
    // Rotate to align with machine coordinates
    // Note: In image coordinates, Y increases downward, so we negate it for standard coordinates
    final pxRot = px * math.cos(-orientationRad) - (-py) * math.sin(-orientationRad);
    final pyRot = px * math.sin(-orientationRad) + (-py) * math.cos(-orientationRad);
    
    // Scale to millimeters
    final xMm = pxRot * pixelToMmRatio;
    final yMm = pyRot * pixelToMmRatio;
    
    return CoordinatePointXY(xMm, yMm);
  }
  
  /// Convert a point from machine (mm) coordinates to pixel coordinates
  CoordinatePointXY machineToPixelCoords(CoordinatePointXY machinePoint) {
    // Scale to pixels
    final pxRot = machinePoint.x / pixelToMmRatio;
    final pyRot = machinePoint.y / pixelToMmRatio;
    
    // Rotate from machine coordinates
    final px = pxRot * math.cos(orientationRad) - pyRot * math.sin(orientationRad);
    // Remember to negate y for image coordinates
    final py = -(pxRot * math.sin(orientationRad) + pyRot * math.cos(orientationRad));
    
    // Translate from origin
    final xPx = px + originPx.x;
    final yPx = py + originPx.y;
    
    return CoordinatePointXY(xPx, yPx);
  }
  
  /// Convert a list of points from pixel to machine coordinates
  List<CoordinatePointXY> convertPointListToMachineCoords(List<CoordinatePointXY> pixelPoints) {
    return pixelPoints.map((p) => pixelToMachineCoords(p)).toList();
  }
  
  /// Convert a list of points from machine to pixel coordinates
  List<CoordinatePointXY> convertPointListToPixelCoords(List<CoordinatePointXY> machinePoints) {
    return machinePoints.map((p) => machineToPixelCoords(p)).toList();
  }
  
  /// Create a coordinate system from three marker points with separate X and Y distances
  static MachineCoordinateSystem fromMarkerPointsWithDistances(
    CoordinatePointXY originMarker, 
    CoordinatePointXY xAxisMarker, 
    CoordinatePointXY scaleMarker,
    double markerXDistanceMm,
    double markerYDistanceMm,
  ) {
    // Calculate orientation angle from origin to x-axis marker
    final dx = xAxisMarker.x - originMarker.x;
    final dy = xAxisMarker.y - originMarker.y;
    final orientationRad = math.atan2(dy, dx);
    
    // Calculate pixel distances
    final xDistancePx = math.sqrt(dx * dx + dy * dy);
    
    // Calculate scale marker distance (for Y axis)
    final scaleX = scaleMarker.x - originMarker.x;
    final scaleY = scaleMarker.y - originMarker.y;
    final yDistancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
    
    // Average the two ratios for better accuracy
    // We could also use separate X and Y scales, but that complicates the transformation
    final xPixelToMmRatio = markerXDistanceMm / xDistancePx;
    final yPixelToMmRatio = markerYDistanceMm / yDistancePx;
    final pixelToMmRatio = (xPixelToMmRatio + yPixelToMmRatio) / 2;
    
    return MachineCoordinateSystem(
      originPx: originMarker,
      orientationRad: orientationRad,
      pixelToMmRatio: pixelToMmRatio,
    );
  }

  // Backward compatibility method that uses a single distance value
  static MachineCoordinateSystem fromMarkerPoints(
    CoordinatePointXY originMarker, 
    CoordinatePointXY xAxisMarker, 
    CoordinatePointXY scaleMarker,
    double markerRealDistanceMm,
  ) {
    return fromMarkerPointsWithDistances(
      originMarker, 
      xAxisMarker, 
      scaleMarker, 
      markerRealDistanceMm, 
      markerRealDistanceMm
    );
  }
}