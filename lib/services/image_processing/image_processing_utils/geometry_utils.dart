import 'dart:math' as math;
import '../../gcode/machine_coordinates.dart';

/// Utilities for geometric operations and calculations
class GeometryUtils {
  /// Calculate distance between two points
  static double distance(Point p1, Point p2) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  /// Calculate squared distance between two points (faster when only comparing distances)
  static double squaredDistance(Point p1, Point p2) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    return dx * dx + dy * dy;
  }
  
  /// Calculate the angle between two points in radians
  static double angleBetween(Point center, Point point) {
    return math.atan2(point.y - center.y, point.x - center.x);
  }
  
  /// Calculate the angle between three points in radians
  static double angleBetweenThreePoints(Point p1, Point p2, Point p3) {
    final a = squaredDistance(p2, p3);
    final b = squaredDistance(p1, p3);
    final c = squaredDistance(p1, p2);
    
    // Use law of cosines
    return math.acos((a + c - b) / (2 * math.sqrt(a) * math.sqrt(c)));
  }
  
  /// Calculate the midpoint between two points
  static Point midpoint(Point p1, Point p2) {
    return Point(
      (p1.x + p2.x) / 2,
      (p1.y + p2.y) / 2,
    );
  }
  
  /// Interpolate between two points
  static Point interpolate(Point p1, Point p2, double t) {
    return Point(
      p1.x + (p2.x - p1.x) * t,
      p1.y + (p2.y - p1.y) * t,
    );
  }
  
  /// Calculate the scalar projection of vector a onto vector b
  static double scalarProjection(Point a, Point b) {
    return (a.x * b.x + a.y * b.y) / math.sqrt(b.x * b.x + b.y * b.y);
  }
  
  /// Check if a point is inside a rectangle
  static bool isPointInRectangle(Point point, Point topLeft, Point bottomRight) {
    return point.x >= topLeft.x && 
           point.x <= bottomRight.x && 
           point.y >= topLeft.y && 
           point.y <= bottomRight.y;
  }
  
  /// Check if a point is inside a circle
  static bool isPointInCircle(Point point, Point center, double radius) {
    return squaredDistance(point, center) <= radius * radius;
  }
  
  /// Calculate the perpendicular distance from a point to a line
  static double distancePointToLine(Point point, Point lineStart, Point lineEnd) {
    // Line equation: Ax + By + C = 0
    // A = y2 - y1, B = x1 - x2, C = x2*y1 - x1*y2
    final A = lineEnd.y - lineStart.y;
    final B = lineStart.x - lineEnd.x;
    final C = lineEnd.x * lineStart.y - lineStart.x * lineEnd.y;
    
    // Distance = |Ax + By + C| / sqrt(A^2 + B^2)
    return (A * point.x + B * point.y + C).abs() / math.sqrt(A * A + B * B);
  }
  
  /// Check if a point is on a line segment
  static bool isPointOnLineSegment(Point point, Point lineStart, Point lineEnd) {
    // Check if point is on line
    final crossProduct = (point.y - lineStart.y) * (lineEnd.x - lineStart.x) - 
                      (point.x - lineStart.x) * (lineEnd.y - lineStart.y);
    
    if (crossProduct.abs() > 1e-10) return false;  // Not on the line
    
    // Check if point is within the bounding box
    final dotProduct = (point.x - lineStart.x) * (lineEnd.x - lineStart.x) + 
                     (point.y - lineStart.y) * (lineEnd.y - lineStart.y);
    
    if (dotProduct < 0) return false;  // Point is on line but before start
    
    final squaredLength = squaredDistance(lineStart, lineEnd);
    if (dotProduct > squaredLength) return false;  // Point is on line but after end
    
    return true;
  }
  
  /// Find the closest point on a line segment to a given point
  static Point closestPointOnLineSegment(Point point, Point lineStart, Point lineEnd) {
    // Calculate direction vector of the line
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;
    
    // Calculate squared length of the line segment
    final lineLength = dx * dx + dy * dy;
    
    if (lineLength.abs() < 1e-10) {
      // Line segment is a point
      return lineStart;
    }
    
    // Calculate projection of the point vector onto the line vector
    final t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lineLength;
    
    if (t < 0) {
      // Closest point is line start
      return lineStart;
    } else if (t > 1) {
      // Closest point is line end
      return lineEnd;
    } else {
      // Closest point is on the line segment
      return Point(
        lineStart.x + t * dx,
        lineStart.y + t * dy,
      );
    }
  }
  
  /// Rotate a point around another point
  static Point rotatePoint(Point point, Point center, double angle) {
    // Translate to origin
    final x = point.x - center.x;
    final y = point.y - center.y;
    
    // Rotate
    final xRot = x * math.cos(angle) - y * math.sin(angle);
    final yRot = x * math.sin(angle) + y * math.cos(angle);
    
    // Translate back
    return Point(
      xRot + center.x,
      yRot + center.y,
    );
  }
  
  /// Scale a point around another point
  static Point scalePoint(Point point, Point center, double scale) {
    // Translate to origin
    final x = point.x - center.x;
    final y = point.y - center.y;
    
    // Scale
    final xScaled = x * scale;
    final yScaled = y * scale;
    
    // Translate back
    return Point(
      xScaled + center.x,
      yScaled + center.y,
    );
  }
  
  /// Calculate the intersection point of two lines
  static Point? lineIntersection(Point line1Start, Point line1End, Point line2Start, Point line2End) {
    // Line 1 represented as a1x + b1y = c1
    final a1 = line1End.y - line1Start.y;
    final b1 = line1Start.x - line1End.x;
    final c1 = a1 * line1Start.x + b1 * line1Start.y;
    
    // Line 2 represented as a2x + b2y = c2
    final a2 = line2End.y - line2Start.y;
    final b2 = line2Start.x - line2End.x;
    final c2 = a2 * line2Start.x + b2 * line2Start.y;
    
    final determinant = a1 * b2 - a2 * b1;
    
    // If determinant is 0, lines are parallel
    if (determinant.abs() < 1e-10) return null;
    
    // Calculate intersection point
    final x = (b2 * c1 - b1 * c2) / determinant;
    final y = (a1 * c2 - a2 * c1) / determinant;
    
    return Point(x, y);
  }
  
  /// Calculate the intersection point of two line segments
  static Point? lineSegmentIntersection(Point line1Start, Point line1End, Point line2Start, Point line2End) {
    final intersection = lineIntersection(line1Start, line1End, line2Start, line2End);
    
    if (intersection == null) return null;
    
    // Check if intersection is within both line segments
    if (isPointOnLineSegment(intersection, line1Start, line1End) &&
        isPointOnLineSegment(intersection, line2Start, line2End)) {
      return intersection;
    }
    
    return null;
  }
  
  /// Calculate the area of a triangle
  static double triangleArea(Point p1, Point p2, Point p3) {
    return 0.5 * ((p2.x - p1.x) * (p3.y - p1.y) - (p3.x - p1.x) * (p2.y - p1.y)).abs();
  }
  
  /// Calculate the area of a polygon
  static double polygonArea(List<Point> points) {
    if (points.length < 3) return 0.0;
    
    double area = 0.0;
    
    // Shoelace formula (Gauss's area formula)
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].x * points[j].y;
      area -= points[j].x * points[i].y;
    }
    
    return area.abs() / 2.0;
  }
  
  /// Calculate the centroid of a polygon
  static Point polygonCentroid(List<Point> points) {
    if (points.length < 3) {
      return _calculateAveragePoint(points);
    }
    
    double cx = 0.0;
    double cy = 0.0;
    double area = 0.0;
    
    // Calculate centroid using shoelace formula
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      final p1 = points[i];
      final p2 = points[j];
      final cross = p1.x * p2.y - p2.x * p1.y;
      
      cx += (p1.x + p2.x) * cross;
      cy += (p1.y + p2.y) * cross;
      area += cross;
    }
    
    area /= 2.0;
    
    if (area.abs() < 1e-10) {
      // If area is too small, just average the points
      return _calculateAveragePoint(points);
    }
    
    cx /= 6.0 * area;
    cy /= 6.0 * area;
    
    return Point(cx, cy);
  }
  
  /// Calculate average of points
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
  
  /// Check if a polygon is convex
  static bool isPolygonConvex(List<Point> points) {
    if (points.length < 3) return false;
    
    bool sign = false;
    bool signSet = false;
    
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      final k = (i + 2) % points.length;
      
      final dx1 = points[j].x - points[i].x;
      final dy1 = points[j].y - points[i].y;
      final dx2 = points[k].x - points[j].x;
      final dy2 = points[k].y - points[j].y;
      
      final crossProduct = dx1 * dy2 - dy1 * dx2;
      
      // Set sign on first iteration
      if (!signSet) {
        sign = crossProduct > 0;
        signSet = true;
      } else {
        // If sign changes, the polygon is not convex
        if ((crossProduct > 0) != sign) {
          return false;
        }
      }
    }
    
    return true;
  }
  
  /// Calculate the perimeter of a polygon
  static double polygonPerimeter(List<Point> points) {
    if (points.length < 2) return 0.0;
    
    double perimeter = 0.0;
    
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      perimeter += distance(points[i], points[j]);
    }
    
    return perimeter;
  }
  
  /// Check if two polygons intersect
  static bool doPolygonsIntersect(List<Point> polygon1, List<Point> polygon2) {
    // Check if any point of one polygon is inside the other
    for (final point in polygon1) {
      if (isPointInPolygon(point, polygon2)) {
        return true;
      }
    }
    
    for (final point in polygon2) {
      if (isPointInPolygon(point, polygon1)) {
        return true;
      }
    }
    
    // Check if any line segments intersect
    for (int i = 0; i < polygon1.length; i++) {
      final j = (i + 1) % polygon1.length;
      
      for (int k = 0; k < polygon2.length; k++) {
        final l = (k + 1) % polygon2.length;
        
        if (lineSegmentIntersection(polygon1[i], polygon1[j], polygon2[k], polygon2[l]) != null) {
          return true;
        }
      }
    }
    
    return false;
  }
  
  /// Check if a point is inside a polygon
  static bool isPointInPolygon(Point point, List<Point> polygon) {
    if (polygon.length < 3) return false;
    
    bool inside = false;
    int j = polygon.length - 1;
    
    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].y > point.y) != (polygon[j].y > point.y) &&
          point.x < (polygon[j].x - polygon[i].x) * (point.y - polygon[i].y) / 
          (polygon[j].y - polygon[i].y) + polygon[i].x) {
        inside = !inside;
      }
      j = i;
    }
    
    return inside;
  }
  
  /// Calculate the convex hull of a set of points using Graham scan
  static List<Point> convexHull(List<Point> points) {
    if (points.length <= 3) return List.from(points);
    
    // Find point with lowest y-coordinate (and leftmost if tied)
    int lowestIndex = 0;
    for (int i = 1; i < points.length; i++) {
      if (points[i].y < points[lowestIndex].y || 
          (points[i].y == points[lowestIndex].y && points[i].x < points[lowestIndex].x)) {
        lowestIndex = i;
      }
    }
    
    // Swap lowest point to first position
    final temp = points[0];
    points[0] = points[lowestIndex];
    points[lowestIndex] = temp;
    
    // Sort points by polar angle with respect to the lowest point
    final p0 = points[0];
    points.sort((a, b) {
      if (a == p0) return -1;
      if (b == p0) return 1;
      
      final angleA = math.atan2(a.y - p0.y, a.x - p0.x);
      final angleB = math.atan2(b.y - p0.y, b.x - p0.x);
      
      if (angleA < angleB) return -1;
      if (angleA > angleB) return 1;
      
      // If angles are the same, pick the closer point
      final distA = squaredDistance(p0, a);
      final distB = squaredDistance(p0, b);
      return distA.compareTo(distB);
    });
    
    // Build convex hull
    final hull = <Point>[];
    hull.add(points[0]);
    hull.add(points[1]);
    
    for (int i = 2; i < points.length; i++) {
      while (hull.length > 1 && _ccw(hull[hull.length - 2], hull[hull.length - 1], points[i]) <= 0) {
        hull.removeLast();
      }
      hull.add(points[i]);
    }
    
    return hull;
  }
  
  /// Cross product for determining counter-clockwise orientation
  static double _ccw(Point a, Point b, Point c) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }
  
  /// Generate a circle of points
  static List<Point> generateCirclePoints(Point center, double radius, int numPoints) {
    final points = <Point>[];
    
    for (int i = 0; i < numPoints; i++) {
      final angle = 2 * math.pi * i / numPoints;
      final x = center.x + radius * math.cos(angle);
      final y = center.y + radius * math.sin(angle);
      points.add(Point(x, y));
    }
    
    return points;
  }
  
  /// Generate a rectangle of points
  static List<Point> generateRectanglePoints(Point topLeft, Point bottomRight) {
    return [
      topLeft,
      Point(bottomRight.x, topLeft.y),
      bottomRight,
      Point(topLeft.x, bottomRight.y),
      topLeft, // Close the rectangle
    ];
  }
  
  /// Generate a regular polygon
  static List<Point> generateRegularPolygon(Point center, double radius, int sides) {
    final points = <Point>[];
    
    for (int i = 0; i <= sides; i++) {
      final angle = 2 * math.pi * i / sides;
      final x = center.x + radius * math.cos(angle);
      final y = center.y + radius * math.sin(angle);
      points.add(Point(x, y));
    }
    
    return points;
  }
  
  /// Calculate the bounding box of a set of points
  static Map<String, double> calculateBoundingBox(List<Point> points) {
    if (points.isEmpty) {
      return {
        'minX': 0.0,
        'minY': 0.0,
        'maxX': 0.0,
        'maxY': 0.0,
        'width': 0.0,
        'height': 0.0,
      };
    }
    
    double minX = points[0].x;
    double minY = points[0].y;
    double maxX = points[0].x;
    double maxY = points[0].y;
    
    for (int i = 1; i < points.length; i++) {
      if (points[i].x < minX) minX = points[i].x;
      if (points[i].y < minY) minY = points[i].y;
      if (points[i].x > maxX) maxX = points[i].x;
      if (points[i].y > maxY) maxY = points[i].y;
    }
    
    return {
      'minX': minX,
      'minY': minY,
      'maxX': maxX,
      'maxY': maxY,
      'width': maxX - minX,
      'height': maxY - minY,
    };
  }
}