import 'dart:math' as math;
import '../services/gcode/machine_coordinates.dart';

/// Utility class for coordinate transformations and operations
class CoordinateUtils {
  /// Creates a coordinate system from three marker points
  static MachineCoordinateSystem createCoordinateSystem(
    Point originMarker, 
    Point xAxisMarker, 
    Point scaleMarker,
    double markerRealDistanceMm,
  ) {
    try {
      // Validate input points
      if (_arePointsCollinear(originMarker, xAxisMarker, scaleMarker)) {
        throw Exception('Reference markers are collinear. Please reposition markers.');
      }
      
      if (_arePointsTooClose(originMarker, xAxisMarker) || 
          _arePointsTooClose(originMarker, scaleMarker) ||
          _arePointsTooClose(xAxisMarker, scaleMarker)) {
        throw Exception('Reference markers are too close together.');
      }
      
      // Calculate orientation angle
      final dx = xAxisMarker.x - originMarker.x;
      final dy = xAxisMarker.y - originMarker.y;
      final orientationRad = math.atan2(dy, dx);
      
      // Calculate mm per pixel from the distance between origin and scale marker
      final scaleX = scaleMarker.x - originMarker.x;
      final scaleY = scaleMarker.y - originMarker.y;
      final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
      
      if (distancePx < 10.0) {
        throw Exception('Scale marker too close to origin.');
      }
      
      final pixelToMmRatio = markerRealDistanceMm / distancePx;
      
      // Validate resulting ratio
      if (pixelToMmRatio.isNaN || pixelToMmRatio.isInfinite || 
          pixelToMmRatio <= 0.01 || pixelToMmRatio > 100.0) {
        throw Exception('Invalid pixel-to-mm ratio: $pixelToMmRatio');
      }
      
      return MachineCoordinateSystem(
        originPx: originMarker,
        orientationRad: orientationRad,
        pixelToMmRatio: pixelToMmRatio,
      );
    } catch (e) {
      // In case of error, return a fallback coordinate system
      return _createFallbackCoordinateSystem(
        originMarker,
        markerRealDistanceMm,
      );
    }
  }
  
  /// Creates a fallback coordinate system with reasonable defaults
  static MachineCoordinateSystem _createFallbackCoordinateSystem(
    Point origin,
    double markerRealDistanceMm,
  ) {
    // Default to 1 mm per 10 pixels as a reasonable fallback
    const fallbackPixelToMmRatio = 0.1; 
    const fallbackOrientation = 0.0; // Horizontal orientation
    
    return MachineCoordinateSystem(
      originPx: origin,
      orientationRad: fallbackOrientation,
      pixelToMmRatio: fallbackPixelToMmRatio,
    );
  }
  
  /// Converts a point from pixel coordinates to machine coordinates
  static Point pixelToMachineCoords(Point pixelPoint, MachineCoordinateSystem coordSystem) {
    try {
      // Translate to origin
      final px = pixelPoint.x - coordSystem.originPx.x;
      final py = pixelPoint.y - coordSystem.originPx.y;
      
      // Rotate to align with machine coordinates
      // Note: In image coordinates, Y increases downward, so we negate it for standard coordinates
      final pxRot = px * math.cos(-coordSystem.orientationRad) - 
                    (-py) * math.sin(-coordSystem.orientationRad);
      final pyRot = px * math.sin(-coordSystem.orientationRad) + 
                    (-py) * math.cos(-coordSystem.orientationRad);
      
      // Scale to millimeters
      final xMm = pxRot * coordSystem.pixelToMmRatio;
      final yMm = pyRot * coordSystem.pixelToMmRatio;
      
      return Point(xMm, yMm);
    } catch (e) {
      // Fallback: just scale without rotation if an error occurs
      final xMm = (pixelPoint.x - coordSystem.originPx.x) * coordSystem.pixelToMmRatio;
      final yMm = (pixelPoint.y - coordSystem.originPx.y) * coordSystem.pixelToMmRatio;
      return Point(xMm, yMm);
    }
  }
  
  /// Converts a point from machine coordinates to pixel coordinates
  static Point machineToPixelCoords(Point machinePoint, MachineCoordinateSystem coordSystem) {
    try {
      // Scale to pixels
      final pxRot = machinePoint.x / coordSystem.pixelToMmRatio;
      final pyRot = machinePoint.y / coordSystem.pixelToMmRatio;
      
      // Rotate from machine coordinates
      final px = pxRot * math.cos(coordSystem.orientationRad) - 
                 pyRot * math.sin(coordSystem.orientationRad);
      // Remember to negate y for image coordinates
      final py = -(pxRot * math.sin(coordSystem.orientationRad) + 
                  pyRot * math.cos(coordSystem.orientationRad));
      
      // Translate from origin
      final xPx = px + coordSystem.originPx.x;
      final yPx = py + coordSystem.originPx.y;
      
      return Point(xPx, yPx);
    } catch (e) {
      // Fallback: just scale without rotation if an error occurs
      final xPx = machinePoint.x / coordSystem.pixelToMmRatio + coordSystem.originPx.x;
      final yPx = machinePoint.y / coordSystem.pixelToMmRatio + coordSystem.originPx.y;
      return Point(xPx, yPx);
    }
  }
  
  /// Convert a list of points from pixel to machine coordinates
  static List<Point> convertPointListToMachineCoords(
    List<Point> pixelPoints, 
    MachineCoordinateSystem coordSystem
  ) {
    return pixelPoints.map((p) => pixelToMachineCoords(p, coordSystem)).toList();
  }
  
  /// Convert a list of points from machine to pixel coordinates
  static List<Point> convertPointListToPixelCoords(
    List<Point> machinePoints, 
    MachineCoordinateSystem coordSystem
  ) {
    return machinePoints.map((p) => machineToPixelCoords(p, coordSystem)).toList();
  }
  
  /// Check if three points are approximately collinear
  static bool _arePointsCollinear(Point a, Point b, Point c) {
    // Calculate the area of the triangle formed by the three points
    // If the area is close to zero, the points are collinear
    final area = (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)).abs() / 2;
    
    // Define a threshold for collinearity based on the distances between points
    final maxDist = math.max(
      math.max(_distanceBetween(a, b), _distanceBetween(b, c)),
      _distanceBetween(a, c)
    );
    
    // The threshold is proportional to the max distance for scale invariance
    final threshold = maxDist * 0.01;
    
    return area < threshold;
  }
  
  /// Check if two points are too close together
  static bool _arePointsTooClose(Point a, Point b) {
    final minDistance = 10.0; // Minimum distance in pixels
    return _distanceBetween(a, b) < minDistance;
  }
  
  /// Calculate distance between two points
  static double _distanceBetween(Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  /// Calculate area of a polygon defined by a list of points
  static double calculatePolygonArea(List<Point> points) {
    if (points.length < 3) return 0.0;
    
    try {
      double area = 0.0;
      
      // Apply the Shoelace formula (Gauss's area formula)
      for (int i = 0; i < points.length; i++) {
        final j = (i + 1) % points.length;
        area += points[i].x * points[j].y;
        area -= points[j].x * points[i].y;
      }
      
      area = area.abs() / 2.0;
      
      // Validate area is reasonable
      if (area.isNaN || area.isInfinite || area < 0) {
        return 0.0;
      }
      
      return area;
    } catch (e) {
      return 0.0;
    }
  }
  
  /// Calculate perimeter of a polygon defined by a list of points
  static double calculatePolygonPerimeter(List<Point> points) {
    if (points.length < 2) return 0.0;
    
    try {
      double perimeter = 0.0;
      
      for (int i = 0; i < points.length; i++) {
        final j = (i + 1) % points.length;
        perimeter += _distanceBetween(points[i], points[j]);
      }
      
      return perimeter;
    } catch (e) {
      return 0.0;
    }
  }
  
  /// Check if a point is inside a polygon using ray casting algorithm
  static bool isPointInPolygon(Point point, List<Point> polygon) {
    if (polygon.length < 3) return false;
    
    try {
      bool isInside = false;
      int j = polygon.length - 1;
      
      for (int i = 0; i < polygon.length; i++) {
        // Ray casting algorithm
        if ((polygon[i].y > point.y) != (polygon[j].y > point.y) &&
            (point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / 
             (polygon[j].y - polygon[i].y) + polygon[i].x)) {
          isInside = !isInside;
        }
        j = i;
      }
      
      return isInside;
    } catch (e) {
      return false;
    }
  }
  
  /// Find the centroid of a polygon
  static Point findPolygonCentroid(List<Point> polygon) {
    if (polygon.length < 3) {
      // Default to average point if not a proper polygon
      return _calculateAveragePoint(polygon);
    }
    
    try {
      double cx = 0.0;
      double cy = 0.0;
      double area = 0.0;
      
      for (int i = 0; i < polygon.length; i++) {
        final j = (i + 1) % polygon.length;
        final cross = polygon[i].x * polygon[j].y - polygon[j].x * polygon[i].y;
        
        cx += (polygon[i].x + polygon[j].x) * cross;
        cy += (polygon[i].y + polygon[j].y) * cross;
        area += cross;
      }
      
      area /= 2;
      cx /= (6 * area);
      cy /= (6 * area);
      
      // Validate centroid is reasonable
      if (cx.isNaN || cx.isInfinite || cy.isNaN || cy.isInfinite) {
        return _calculateAveragePoint(polygon);
      }
      
      return Point(cx, cy);
    } catch (e) {
      // Fall back to average of points
      return _calculateAveragePoint(polygon);
    }
  }
  
  /// Calculate average of all points (fallback for centroid)
  static Point _calculateAveragePoint(List<Point> points) {
    if (points.isEmpty) return Point(0, 0);
    
    double sumX = 0;
    double sumY = 0;
    
    for (final point in points) {
      sumX += point.x;
      sumY += point.y;
    }
    
    return Point(sumX / points.length, sumY / points.length);
  }
  
  /// Simplify a polygon using the Douglas-Peucker algorithm
  static List<Point> simplifyPolygon(List<Point> points, double epsilon, {int maxDepth = 100}) {
    if (points.length <= 2) return List.from(points);
    
    try {
      return _douglasPeucker(points, epsilon, 0, maxDepth);
    } catch (e) {
      // If simplification fails, return original points
      return points;
    }
  }
  
  /// Douglas-Peucker algorithm with stack overflow prevention
  static List<Point> _douglasPeucker(List<Point> points, double epsilon, int depth, int maxDepth) {
    if (points.length <= 2) return List.from(points);
    if (depth >= maxDepth) return List.from(points);
    
    // Find point with maximum distance
    double maxDistance = 0;
    int index = 0;
    
    final start = points.first;
    final end = points.last;
    
    for (int i = 1; i < points.length - 1; i++) {
      final point = points[i];
      final distance = _perpendicularDistance(point, start, end);
      
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }
    
    // If max distance exceeds epsilon, recursively simplify
    if (maxDistance > epsilon) {
      // Recursive simplification
      final firstPart = _douglasPeucker(points.sublist(0, index + 1), epsilon, depth + 1, maxDepth);
      final secondPart = _douglasPeucker(points.sublist(index), epsilon, depth + 1, maxDepth);
      
      // Concatenate results, excluding duplicate middle point
      return [...firstPart.sublist(0, firstPart.length - 1), ...secondPart];
    } else {
      // Base case - just use endpoints
      return [start, end];
    }
  }
  
  /// Calculate perpendicular distance from point to line segment
  static double _perpendicularDistance(Point point, Point lineStart, Point lineEnd) {
    try {
      final dx = lineEnd.x - lineStart.x;
      final dy = lineEnd.y - lineStart.y;
      
      // If line is just a point, return distance to that point
      if (dx == 0 && dy == 0) {
        return math.sqrt(math.pow(point.x - lineStart.x, 2) + 
                       math.pow(point.y - lineStart.y, 2));
      }
      
      // Calculate perpendicular distance
      final norm = math.sqrt(dx * dx + dy * dy);
      return ((dy * point.x - dx * point.y + lineEnd.x * lineStart.y - 
                      lineEnd.y * lineStart.x) / norm).abs();
    } catch (e) {
      // Simple fallback distance calculation
      return 0.0;
    }
  }
  
  /// Offset a polygon contour inward or outward by a given distance
  static List<Point> offsetPolygon(List<Point> polygon, double distance) {
    if (polygon.length < 3) return polygon;
    
    try {
      // Close the polygon if not already closed
      final isClosed = (polygon.first.x == polygon.last.x && polygon.first.y == polygon.last.y);
      final workingPolygon = isClosed ? polygon : [...polygon, polygon.first];
      
      final result = <Point>[];
      
      for (int i = 0; i < workingPolygon.length - 1; i++) {
        final current = workingPolygon[i];
        final next = workingPolygon[i + 1];
        
        // Calculate normal vector
        final dx = next.x - current.x;
        final dy = next.y - current.y;
        final length = math.sqrt(dx * dx + dy * dy);
        
        if (length < 0.001) continue; // Skip very short segments
        
        // Normalize the vector
        final nx = dx / length;
        final ny = dy / length;
        
        // Rotate 90 degrees for normal
        final normalX = -ny;
        final normalY = nx;
        
        // Offset points
        result.add(Point(
          current.x + normalX * distance,
          current.y + normalY * distance
        ));
      }
      
      // Add the last point to close the polygon
      if (result.isNotEmpty) {
        result.add(result.first);
      }
      
      // Simple approach for now - for proper offsetting, 
      // we would need to handle intersections at corners
      
      return result;
    } catch (e) {
      return polygon; // Return original if offsetting fails
    }
  }
}