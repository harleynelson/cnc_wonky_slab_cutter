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
static CoordinatePointXY imageToDisplayCoordinates(CoordinatePointXY imagePoint, Size imageSize, Size displaySize) {
  // Calculate aspect ratios
  final imageAspect = imageSize.width / imageSize.height;
  final displayAspect = displaySize.width / displaySize.height;
  
  double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
  
  // Determine scaling to maintain aspect ratio
  if (imageAspect > displayAspect) {
    // Image is wider than display area (letterboxing)
    displayWidth = displaySize.width;
    displayHeight = displayWidth / imageAspect;
    offsetY = (displaySize.height - displayHeight) / 2;
  } else {
    // Image is taller than display area (pillarboxing)
    displayHeight = displaySize.height;
    displayWidth = displayHeight * imageAspect;
    offsetX = (displaySize.width - displayWidth) / 2;
  }
  
  // Calculate display coordinates
  final scaledX = (imagePoint.x / imageSize.width) * displayWidth;
  final scaledY = (imagePoint.y / imageSize.height) * displayHeight;
  
  return CoordinatePointXY(
    scaledX + offsetX, 
    scaledY + offsetY
  );
}

/// Debug helper method to print coordinate system information
void debugPrintInfo() {
  print("Coordinate System Info:");
  print("Origin: (${originPx.x}, ${originPx.y})");
  print("Orientation: ${orientationRad * 180 / math.pi} degrees");
  print("Pixel to MM ratio: $pixelToMmRatio");
}

/// Convert a point from display (canvas) coordinates to image coordinates
static CoordinatePointXY displayToImageCoordinates(CoordinatePointXY displayPoint, Size imageSize, Size displaySize) {
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
  // Remember to negate y for image coordinates (since image Y increases downward)
  final py = -(pxRot * math.sin(orientationRad) + pyRot * math.cos(orientationRad));
  
  // Translate from origin
  final xPx = px + originPx.x;
  final yPx = py + originPx.y;
  
  return CoordinatePointXY(xPx, yPx);
}
  
  /// Convert a list of points from pixel to machine coordinates accurately
List<CoordinatePointXY> convertPointListToMachineCoords(List<CoordinatePointXY> pixelPoints) {
  return pixelPoints.map((p) => pixelToMachineCoords(p)).toList();
}
  
  /// Convert a list of points from machine to pixel coordinates
  List<CoordinatePointXY> convertPointListToPixelCoords(List<CoordinatePointXY> machinePoints) {
    return machinePoints.map((p) => machineToPixelCoords(p)).toList();
  }

  /// Verify that a point can be accurately transformed back and forth
bool verifyCoordinateTransformation(CoordinatePointXY originalPoint) {
  final machinePoint = pixelToMachineCoords(originalPoint);
  final backToPixel = machineToPixelCoords(machinePoint);
  
  // Calculate error
  final errorX = (originalPoint.x - backToPixel.x).abs();
  final errorY = (originalPoint.y - backToPixel.y).abs();
  
  // Print debug info
  print("Original: ($originalPoint), Machine: ($machinePoint), Back: ($backToPixel)");
  print("Error: X=$errorX, Y=$errorY");
  
  // Error should be very small (floating point precision issues)
  return errorX < 0.001 && errorY < 0.001;
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
  // Force horizontal orientation (orientation angle = 0)
  final orientationRad = 0.0; // Instead of math.atan2(dy, dx);

  
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