import 'dart:math' as math;

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
  
  /// Create a coordinate system from three marker points
  static MachineCoordinateSystem fromMarkerPoints(
    Point originMarker, 
    Point xAxisMarker, 
    Point scaleMarker,
    double markerRealDistanceMm,
  ) {
    // Calculate orientation angle
    final dx = xAxisMarker.x - originMarker.x;
    final dy = xAxisMarker.y - originMarker.y;
    final orientationRad = math.atan2(dy, dx);
    
    // Calculate mm per pixel from the distance between origin and scale marker
    final scaleX = scaleMarker.x - originMarker.x;
    final scaleY = scaleMarker.y - originMarker.y;
    final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
    final pixelToMmRatio = markerRealDistanceMm / distancePx;
    
    return MachineCoordinateSystem(
      originPx: originMarker,
      orientationRad: orientationRad,
      pixelToMmRatio: pixelToMmRatio,
    );
  }
}