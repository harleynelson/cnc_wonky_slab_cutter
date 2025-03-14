import 'dart:math' as math;
import 'dart:ui';

/// Represents a point in 2D space
class Point {
  final double x;
  final double y;
  
  Point(this.x, this.y);
  
  /// Calculate the distance to another point
  double distanceTo(Point other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  @override
  String toString() => 'Point($x, $y)';
}

/// Represents a machine coordinate system calibrated from image pixels
class MachineCoordinateSystem {
  final Point originPx;
  final double orientationRad;
  final double pixelToMmRatio;
  
  MachineCoordinateSystem({
    required this.originPx,
    required this.orientationRad,
    required this.pixelToMmRatio,
  });

  /// Convert a point from image coordinates to display (canvas) coordinates
static Point imageToDisplayCoordinates(Point imagePoint, Size imageSize, Size displaySize) {
  final imageAspect = imageSize.width / imageSize.height;
  final displayAspect = displaySize.width / displaySize.height;
  
  double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
  
  if (imageAspect > displayAspect) {
    displayWidth = displaySize.width;
    displayHeight = displaySize.width / imageAspect;
    offsetY = (displaySize.height - displayHeight) / 2;
    // Remove any hardcoded offset correction
  } else {
    displayHeight = displaySize.height;
    displayWidth = displaySize.height * imageAspect;
    offsetX = (displaySize.width - displayWidth) / 2;
  }
  
  final normalizedX = imagePoint.x / imageSize.width;
  final normalizedY = imagePoint.y / imageSize.height;
  
  final displayX = normalizedX * displayWidth + offsetX;
  final displayY = normalizedY * displayHeight + offsetY;
  
  return Point(displayX, displayY);
}

/// Convert a point from display (canvas) coordinates to image coordinates
static Point displayToImageCoordinates(Point displayPoint, Size imageSize, Size displaySize) {
  // Calculate scale and offset - maintain aspect ratio
  final imageAspect = imageSize.width / imageSize.height;
  final displayAspect = displaySize.width / displaySize.height;
  
  double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
  
  if (imageAspect > displayAspect) {
    // Image is wider than display (letterboxed)
    displayWidth = displaySize.width;
    displayHeight = displaySize.width / imageAspect;
    offsetY = (displaySize.height - displayHeight) / 2;
    
    // Remove hardcoded correction
    // final offsetCorrection = 85.5; // 92.5 - a7.0
    // offsetY = offsetY - offsetCorrection;
  } else {
    // Image is taller than display (pillarboxed)
    displayHeight = displaySize.height;
    displayWidth = displaySize.height * imageAspect;
    offsetX = (displaySize.width - displayWidth) / 2;
  }
  
  // Reverse the transformation - account for offset then normalize
  final normalizedX = (displayPoint.x - offsetX) / displayWidth;
  final normalizedY = (displayPoint.y - offsetY) / displayHeight;
  
  final imageX = normalizedX * imageSize.width;
  final imageY = normalizedY * imageSize.height;
  
  return Point(imageX, imageY);
}
  
  /// Convert a point from pixel coordinates to machine (mm) coordinates
  Point pixelToMachineCoords(Point pixelPoint) {
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
    
    return Point(xMm, yMm);
  }
  
  /// Convert a point from machine (mm) coordinates to pixel coordinates
  Point machineToPixelCoords(Point machinePoint) {
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
    
    return Point(xPx, yPx);
  }
  
  /// Convert a list of points from pixel to machine coordinates
  List<Point> convertPointListToMachineCoords(List<Point> pixelPoints) {
    return pixelPoints.map((p) => pixelToMachineCoords(p)).toList();
  }
  
  /// Convert a list of points from machine to pixel coordinates
  List<Point> convertPointListToPixelCoords(List<Point> machinePoints) {
    return machinePoints.map((p) => machineToPixelCoords(p)).toList();
  }
  
  /// Create a coordinate system from three marker points with separate X and Y distances
static MachineCoordinateSystem fromMarkerPointsWithDistances(
  Point originMarker, 
  Point xAxisMarker, 
  Point scaleMarker,
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
  Point originMarker, 
  Point xAxisMarker, 
  Point scaleMarker,
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