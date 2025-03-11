import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../gcode/machine_coordinates.dart';
import 'base_image_utils.dart';

/// Utilities for contour extraction and manipulation
class ContourUtils {
  /// Extract contours from a binary image
  static List<List<Point>> findContours(img.Image binaryImage, {
    int minSize = 10,
    int maxSize = 100000,
    int maxDepth = 1000,
  }) {
    final List<List<Point>> contours = [];
    final width = binaryImage.width;
    final height = binaryImage.height;
    
    // Create visited array
    final visited = List.generate(
      height,
      (y) => List.filled(width, false),
    );
    
    // Find connected components
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (visited[y][x]) continue;
        
        final pixel = binaryImage.getPixel(x, y);
        final isObject = pixel.r.toInt() < 128; // Object is dark in binary image
        
        if (isObject) {
          final List<Point> component = [];
          _floodFill(binaryImage, x, y, visited, component, maxDepth);
          
          // Filter by size
          if (component.length >= minSize && component.length <= maxSize) {
            // Extract boundary points
            final contour = _extractContourFromComponent(component, binaryImage);
            contours.add(contour);
          }
        } else {
          visited[y][x] = true;
        }
      }
    }
    
    return contours;
  }
  
  /// Find connected components in a binary image
  static List<List<Point>> findConnectedComponents(img.Image binaryImage, {
    int minSize = 20,
    int maxSize = 100000,
    int maxDepth = 1000,
  }) {
    final List<List<Point>> components = [];
    final width = binaryImage.width;
    final height = binaryImage.height;
    
    // Create visited array
    final visited = List.generate(
      height,
      (y) => List.filled(width, false),
    );
    
    // Find connected components
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (visited[y][x]) continue;
        
        final pixel = binaryImage.getPixel(x, y);
        final isObject = pixel.r.toInt() < 128; // Object is dark in binary image
        
        if (isObject) {
          final List<Point> component = [];
          _floodFill(binaryImage, x, y, visited, component, maxDepth);
          
          // Filter by size
          if (component.length >= minSize && component.length <= maxSize) {
            components.add(component);
          }
        } else {
          visited[y][x] = true;
        }
      }
    }
    
    return components;
  }
  
  /// Flood fill algorithm for connected component labeling
  static void _floodFill(
    img.Image image,
    int x,
    int y,
    List<List<bool>> visited,
    List<Point> component,
    int maxDepth,
    {int depth = 0}
  ) {
    // Prevent stack overflow
    if (depth >= maxDepth) return;
    
    if (x < 0 || y < 0 || x >= image.width || y >= image.height || visited[y][x]) {
      return;
    }
    
    final pixel = image.getPixel(x, y);
    final isObject = pixel.r.toInt() < 128; // Object is dark
    
    if (!isObject) {
      visited[y][x] = true;
      return;
    }
    
    visited[y][x] = true;
    component.add(Point(x.toDouble(), y.toDouble()));
    
    // Check 4-connected neighbors
    _floodFill(image, x + 1, y, visited, component, maxDepth, depth: depth + 1);
    _floodFill(image, x - 1, y, visited, component, maxDepth, depth: depth + 1);
    _floodFill(image, x, y + 1, visited, component, maxDepth, depth: depth + 1);
    _floodFill(image, x, y - 1, visited, component, maxDepth, depth: depth + 1);
  }
  
  /// Extract contour boundary points from a component using boundary tracing
  static List<Point> _extractContourFromComponent(List<Point> component, img.Image binaryImage) {
    if (component.isEmpty) return [];
    
    // Find the leftmost point (which is guaranteed to be on the boundary)
    int minXIndex = 0;
    double minX = component[0].x;
    
    for (int i = 1; i < component.length; i++) {
      if (component[i].x < minX) {
        minX = component[i].x;
        minXIndex = i;
      }
    }
    
    final startPoint = component[minXIndex];
    
    // Use Moore boundary tracing algorithm
    return _traceBoundary(binaryImage, startPoint);
  }
  
  /// Trace the boundary of an object using Moore boundary tracing
  static List<Point> _traceBoundary(img.Image binaryImage, Point startPoint) {
    final boundary = <Point>[];
    final width = binaryImage.width;
    final height = binaryImage.height;
    
    // Direction codes: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
    final dx = [1, 1, 0, -1, -1, -1, 0, 1];
    final dy = [0, 1, 1, 1, 0, -1, -1, -1];
    
    int x = startPoint.x.round();
    int y = startPoint.y.round();
    int dir = 7;  // Start by looking in the NE direction
    
    final visited = <String>{};
    const maxSteps = 10000;  // Safety limit
    int steps = 0;
    
    do {
      // Add current point to boundary
      boundary.add(Point(x.toDouble(), y.toDouble()));
      
      // Mark as visited
      final key = "$x,$y";
      visited.add(key);
      
      // Look for next boundary pixel
      bool found = false;
      for (int i = 0; i < 8 && !found; i++) {
        // Check in a counter-clockwise direction starting from dir
        int checkDir = (dir + i) % 8;
        int nx = x + dx[checkDir];
        int ny = y + dy[checkDir];
        
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
        
        final pixel = binaryImage.getPixel(nx, ny);
        final isObject = pixel.r.toInt() < 128;
        
        if (isObject) {  // Found an object pixel
          x = nx;
          y = ny;
          dir = (checkDir + 5) % 8;  // Backtrack direction
          found = true;
        }
      }
      
      if (!found) break;
      
      steps++;
      if (steps >= maxSteps) break;  // Safety check
      
    } while (!(x == startPoint.x.round() && y == startPoint.y.round()) || boundary.length <= 1);
    
    return boundary;
  }
  
  /// Compute convex hull using Graham scan algorithm
  static List<Point> computeConvexHull(List<Point> points) {
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
      final distA = _squaredDistance(p0, a);
      final distB = _squaredDistance(p0, b);
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
    
    // Ensure hull is closed
    if (hull.length > 2 && (hull.first.x != hull.last.x || hull.first.y != hull.last.y)) {
      hull.add(hull.first);
    }
    
    return hull;
  }
  
  /// Cross product for determining counter-clockwise orientation
  static double _ccw(Point a, Point b, Point c) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }
  
  /// Calculate squared distance between two points
  static double _squaredDistance(Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return dx * dx + dy * dy;
  }
  
  /// Simplify contour using Douglas-Peucker algorithm
  static List<Point> simplifyContour(List<Point> contour, double epsilon) {
    if (contour.length <= 2) return contour;
    
    return _douglasPeucker(contour, epsilon);
  }
  
  /// Douglas-Peucker algorithm for contour simplification
  static List<Point> _douglasPeucker(List<Point> points, double epsilon, {int depth = 0, int maxDepth = 20}) {
    if (points.length <= 2 || depth >= maxDepth) return List.from(points);
    
    // Find point with maximum distance
    double maxDistance = 0;
    int index = 0;
    
    final start = points.first;
    final end = points.last;
    
    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], start, end);
      
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }
    
    // If max distance is greater than epsilon, recursively simplify
    if (maxDistance > epsilon) {
      // Split contour and simplify each part
      final firstPart = _douglasPeucker(
        points.sublist(0, index + 1), 
        epsilon, 
        depth: depth + 1,
        maxDepth: maxDepth
      );
      
      final secondPart = _douglasPeucker(
        points.sublist(index), 
        epsilon, 
        depth: depth + 1,
        maxDepth: maxDepth
      );
      
      // Combine results (avoid duplicating the point at index)
      return [
        ...firstPart.sublist(0, firstPart.length - 1),
        ...secondPart
      ];
    } else {
      // Just use endpoints
      return [start, end];
    }
  }
  
  /// Calculate perpendicular distance from point to line
  static double _perpendicularDistance(Point point, Point lineStart, Point lineEnd) {
    // Line equation: Ax + By + C = 0
    // A = y2 - y1, B = x1 - x2, C = x2*y1 - x1*y2
    double A = lineEnd.y - lineStart.y;
    double B = lineStart.x - lineEnd.x;
    double C = lineEnd.x * lineStart.y - lineStart.x * lineEnd.y;
    
    // Distance = |Ax + By + C| / sqrt(A^2 + B^2)
    return (A * point.x + B * point.y + C).abs() / math.sqrt(A * A + B * B);
  }
  
  /// Smooth contour using Gaussian smoothing
  static List<Point> smoothContour(List<Point> contour, {int windowSize = 5, double sigma = 1.0}) {
    if (contour.length <= 3) return contour;
    
    final result = <Point>[];
    final halfWindow = windowSize ~/ 2;
    
    // Generate Gaussian kernel
    final kernel = <double>[];
    double sum = 0.0;
    
    for (int i = -halfWindow; i <= halfWindow; i++) {
      final weight = math.exp(-(i * i) / (2 * sigma * sigma));
      kernel.add(weight);
      sum += weight;
    }
    
    // Normalize kernel
    for (int i = 0; i < kernel.length; i++) {
      kernel[i] /= sum;
    }
    
    // Apply smoothing
    for (int i = 0; i < contour.length; i++) {
      double sumX = 0.0;
      double sumY = 0.0;
      
      for (int j = -halfWindow; j <= halfWindow; j++) {
        final idx = (i + j + contour.length) % contour.length;
        final weight = kernel[j + halfWindow];
        
        sumX += contour[idx].x * weight;
        sumY += contour[idx].y * weight;
      }
      
      result.add(Point(sumX, sumY));
    }
    
    return result;
  }
  
  /// Ensure contour is closed (last point equals first point)
  static List<Point> ensureClosedContour(List<Point> contour) {
    if (contour.length < 3) return contour;
    
    // Check if already closed
    if (contour.first.x == contour.last.x && contour.first.y == contour.last.y) {
      return contour;
    }
    
    // Add first point to the end
    final result = List<Point>.from(contour);
    result.add(result.first);
    
    return result;
  }
  
  /// Calculate contour area using shoelace formula
  static double calculateContourArea(List<Point> contour) {
    if (contour.length < 3) return 0.0;
    
    double area = 0.0;
    
    // Shoelace formula (Gauss's area formula)
    for (int i = 0; i < contour.length - 1; i++) {
      area += contour[i].x * contour[i + 1].y;
      area -= contour[i + 1].x * contour[i].y;
    }
    
    return area.abs() / 2.0;
  }
  
  /// Calculate contour perimeter (length)
  static double calculateContourPerimeter(List<Point> contour) {
    if (contour.length < 2) return 0.0;
    
    double perimeter = 0.0;
    
    for (int i = 0; i < contour.length - 1; i++) {
      perimeter += _distanceBetween(contour[i], contour[i + 1]);
    }
    
    return perimeter;
  }
  
  /// Calculate distance between two points
  static double _distanceBetween(Point a, Point b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    return math.sqrt(dx * dx + dy * dy);
  }
  
  /// Find contour centroid
  static Point findContourCentroid(List<Point> contour) {
    if (contour.isEmpty) return Point(0, 0);
    
    if (contour.length == 1) return contour[0];
    
    double cx = 0.0;
    double cy = 0.0;
    double area = 0.0;
    
    // Calculate centroid using shoelace formula
    for (int i = 0; i < contour.length - 1; i++) {
      final p1 = contour[i];
      final p2 = contour[i + 1];
      final det = p1.x * p2.y - p2.x * p1.y;
      
      cx += (p1.x + p2.x) * det;
      cy += (p1.y + p2.y) * det;
      area += det;
    }
    
    area /= 2.0;
    
    if (area.abs() < 1e-10) {
      // If area is too small, just average the points
      return _calculateAveragePoint(contour);
    }
    
    cx /= 6.0 * area;
    cy /= 6.0 * area;
    
    return Point(cx, cy);
  }
  
  /// Calculate average of all points
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
  
  /// Create an offset contour (expand or shrink)
  static List<Point> offsetContour(List<Point> contour, double distance) {
    if (contour.length < 3) return contour;
    
    final result = <Point>[];
    
    // Make sure contour is closed
    final closedContour = ensureClosedContour(contour);
    
    for (int i = 0; i < closedContour.length - 1; i++) {
      final prev = i == 0 ? closedContour[closedContour.length - 2] : closedContour[i - 1];
      final curr = closedContour[i];
      final next = closedContour[i + 1];
      
      // Calculate direction vectors
      final v1x = curr.x - prev.x;
      final v1y = curr.y - prev.y;
      final v2x = next.x - curr.x;
      final v2y = next.y - curr.y;
      
      // Normalize direction vectors
      final len1 = math.sqrt(v1x * v1x + v1y * v1y);
      final len2 = math.sqrt(v2x * v2x + v2y * v2y);
      
      if (len1 < 1e-10 || len2 < 1e-10) continue;
      
      final n1x = v1x / len1;
      final n1y = v1y / len1;
      final n2x = v2x / len2;
      final n2y = v2y / len2;
      
      // Calculate normal vectors (perpendicular)
      final norm1x = -n1y;
      final norm1y = n1x;
      final norm2x = -n2y;
      final norm2y = n2x;
      
      // Average normals for a smooth transition
      final normX = (norm1x + norm2x) / 2;
      final normY = (norm1y + norm2y) / 2;
      
      // Normalize the average normal
      final normLen = math.sqrt(normX * normX + normY * normY);
      if (normLen < 1e-10) continue;
      
      final finalNormX = normX / normLen;
      final finalNormY = normY / normLen;
      
      // Calculate offset point
      final offsetX = curr.x + finalNormX * distance;
      final offsetY = curr.y + finalNormY * distance;
      
      result.add(Point(offsetX, offsetY));
    }
    
    // Add the last point to close the contour
    if (result.isNotEmpty) {
      result.add(result.first);
    }
    
    return result;
  }
  
  /// Detect if a point is inside a contour
  static bool isPointInContour(Point point, List<Point> contour) {
    if (contour.length < 3) return false;
    
    bool inside = false;
    int j = contour.length - 1;
    
    for (int i = 0; i < contour.length; i++) {
      if ((contour[i].y > point.y) != (contour[j].y > point.y) &&
          point.x < (contour[j].x - contour[i].x) * (point.y - contour[i].y) / 
          (contour[j].y - contour[i].y) + contour[i].x) {
        inside = !inside;
      }
      j = i;
    }
    
    return inside;
  }
  
  /// Interpolate points along a contour to achieve even spacing
  static List<Point> interpolateContour(List<Point> contour, int desiredPointCount) {
    if (contour.length <= 2 || desiredPointCount <= contour.length) return contour;
    
    final result = <Point>[];
    
    // Calculate total contour length
    double totalLength = 0.0;
    for (int i = 0; i < contour.length - 1; i++) {
      totalLength += _distanceBetween(contour[i], contour[i + 1]);
    }
    
    // Desired segment length
    final desiredSpacing = totalLength / desiredPointCount;
    
    // Add first point
    result.add(contour.first);
    
    double accumulatedLength = 0.0;
    int currentSegment = 0;
    
    // Interpolate points
    for (int i = 1; i < desiredPointCount - 1; i++) {
      final targetDistance = i * desiredSpacing;
      
      // Find the segment containing target distance
      while (currentSegment < contour.length - 1) {
        final segmentLength = _distanceBetween(
          contour[currentSegment], 
          contour[currentSegment + 1]
        );
        
        if (accumulatedLength + segmentLength >= targetDistance) {
          // Interpolate within this segment
          final t = (targetDistance - accumulatedLength) / segmentLength;
          
          final x = contour[currentSegment].x + 
                   t * (contour[currentSegment + 1].x - contour[currentSegment].x);
          final y = contour[currentSegment].y + 
                   t * (contour[currentSegment + 1].y - contour[currentSegment].y);
          
          result.add(Point(x, y));
          break;
        } else {
          accumulatedLength += segmentLength;
          currentSegment++;
        }
      }
    }
    
    // Add last point
    result.add(contour.last);
    
    return result;
  }
  
  /// Find the bounding box of a contour
  static Map<String, double> findContourBoundingBox(List<Point> contour) {
    if (contour.isEmpty) {
      return {
        'minX': 0.0,
        'minY': 0.0,
        'maxX': 0.0,
        'maxY': 0.0,
        'width': 0.0,
        'height': 0.0,
      };
    }
    
    double minX = contour[0].x;
    double minY = contour[0].y;
    double maxX = contour[0].x;
    double maxY = contour[0].y;
    
    for (int i = 1; i < contour.length; i++) {
      if (contour[i].x < minX) minX = contour[i].x;
      if (contour[i].y < minY) minY = contour[i].y;
      if (contour[i].x > maxX) maxX = contour[i].x;
      if (contour[i].y > maxY) maxY = contour[i].y;
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
  
  /// Calculate contour orientation (clockwise or counter-clockwise)
  static bool isContourClockwise(List<Point> contour) {
    if (contour.length < 3) return true;
    
    // Calculate signed area
    double area = 0.0;
    for (int i = 0; i < contour.length - 1; i++) {
      area += contour[i].x * contour[i + 1].y - contour[i + 1].x * contour[i].y;
    }
    
    // Clockwise if area is negative
    return area < 0;
  }
  
  /// Reverse contour orientation
  static List<Point> reverseContour(List<Point> contour) {
    return contour.reversed.toList();
  }
  
  /// Merge contours if they overlap
  static List<Point> mergeContours(List<Point> contour1, List<Point> contour2) {
    // Simplified approach: Use convex hull of combined points
    final combined = <Point>[...contour1, ...contour2];
    return computeConvexHull(combined);
  }
  
  /// Find intersection points between two contours
  static List<Point> findContourIntersections(List<Point> contour1, List<Point> contour2) {
    final intersections = <Point>[];
    
    for (int i = 0; i < contour1.length - 1; i++) {
      final p1 = contour1[i];
      final p2 = contour1[i + 1];
      
      for (int j = 0; j < contour2.length - 1; j++) {
        final p3 = contour2[j];
        final p4 = contour2[j + 1];
        
        final intersection = _lineLineIntersection(p1, p2, p3, p4);
        if (intersection != null) {
          intersections.add(intersection);
        }
      }
    }
    
    return intersections;
  }
  
  /// Calculate intersection point between two line segments
  static Point? _lineLineIntersection(Point p1, Point p2, Point p3, Point p4) {
    // Line 1 represented as a1x + b1y = c1
    final a1 = p2.y - p1.y;
    final b1 = p1.x - p2.x;
    final c1 = a1 * p1.x + b1 * p1.y;
    
    // Line 2 represented as a2x + b2y = c2
    final a2 = p4.y - p3.y;
    final b2 = p3.x - p4.x;
    final c2 = a2 * p3.x + b2 * p3.y;
    
    final determinant = a1 * b2 - a2 * b1;
    
    // If lines are parallel, no intersection
    if (determinant.abs() < 1e-10) return null;
    
    // Calculate intersection point
    final x = (b2 * c1 - b1 * c2) / determinant;
    final y = (a1 * c2 - a2 * c1) / determinant;
    
    // Check if intersection is within both line segments
    if (_isPointOnLineSegment(x, y, p1.x, p1.y, p2.x, p2.y) &&
        _isPointOnLineSegment(x, y, p3.x, p3.y, p4.x, p4.y)) {
      return Point(x, y);
    }
    
    return null;
  }
  
  /// Check if a point lies on a line segment
  static bool _isPointOnLineSegment(double x, double y, double x1, double y1, double x2, double y2) {
    final crossProduct = (y - y1) * (x2 - x1) - (x - x1) * (y2 - y1);
    
    // Not on the line if cross product is not close to zero
    if (crossProduct.abs() > 1e-10) return false;
    
    // Check if point is within the bounding box of the line segment
    if (x < math.min(x1, x2) - 1e-10 ||
        x > math.max(x1, x2) + 1e-10) return false;
    if (y < math.min(y1, y2) - 1e-10 ||
        y > math.max(y1, y2) + 1e-10) return false;
    
    return true;
  }
  
  /// Create a regular polygon contour
  static List<Point> createRegularPolygonContour(
    Point center,
    double radius,
    int sides,
    {double rotation = 0.0}
  ) {
    final contour = <Point>[];
    
    for (int i = 0; i <= sides; i++) {
      final angle = rotation + 2 * math.pi * i / sides;
      final x = center.x + radius * math.cos(angle);
      final y = center.y + radius * math.sin(angle);
      contour.add(Point(x, y));
    }
    
    return contour;
  }
  
  /// Create a rectangular contour
  static List<Point> createRectangularContour(
    double x,
    double y,
    double width,
    double height,
    {double rotation = 0.0}
  ) {
    final center = Point(x + width / 2, y + height / 2);
    final contour = <Point>[
      Point(x, y),
      Point(x + width, y),
      Point(x + width, y + height),
      Point(x, y + height),
      Point(x, y), // Close the contour
    ];
    
    // Apply rotation if needed
    if (rotation != 0.0) {
      return _rotateContour(contour, center, rotation);
    }
    
    return contour;
  }
  
  /// Rotate a contour around a center point
  static List<Point> _rotateContour(List<Point> contour, Point center, double angle) {
    final rotated = <Point>[];
    
    for (final point in contour) {
      // Translate to origin
      final x = point.x - center.x;
      final y = point.y - center.y;
      
      // Rotate
      final xRot = x * math.cos(angle) - y * math.sin(angle);
      final yRot = x * math.sin(angle) + y * math.cos(angle);
      
      // Translate back
      rotated.add(Point(xRot + center.x, yRot + center.y));
    }
    
    return rotated;
  }
  
  /// Visualize contours on an image
  static img.Image drawContours(
    img.Image image,
    List<List<Point>> contours,
    {
      img.Color? color,
      int thickness = 1,
    }
  ) {
    // Use a default color if not provided
    final drawColor = color ?? img.ColorRgba8(0, 255, 0, 255);
    
    final result = img.copyResize(image, width: image.width, height: image.height);
    
    for (final contour in contours) {
      // Draw the contour lines
      for (int i = 0; i < contour.length - 1; i++) {
        _drawThickLine(
          result,
          contour[i].x.round(),
          contour[i].y.round(),
          contour[i + 1].x.round(),
          contour[i + 1].y.round(),
          drawColor,
          thickness,
        );
      }
    }
    
    return result;
  }
  
  /// Draw a thick line on an image
  static void _drawThickLine(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    img.Color color,
    int thickness,
  ) {
    // Draw a line with thickness
    // First draw the main line
    _drawLine(image, x1, y1, x2, y2, color);
    
    // If thickness is greater than 1, draw additional lines
    if (thickness > 1) {
      final dx = x2 - x1;
      final dy = y2 - y1;
      final length = math.sqrt(dx * dx + dy * dy);
      
      if (length > 0) {
        // Calculate perpendicular offsets
        final perpX = -dy / length;
        final perpY = dx / length;
        
        // Draw parallel lines for thickness
        for (int i = 1; i <= thickness ~/ 2; i++) {
          // Positive offset
          final px1 = (x1 + i * perpX).round();
          final py1 = (y1 + i * perpY).round();
          final px2 = (x2 + i * perpX).round();
          final py2 = (y2 + i * perpY).round();
          
          // Negative offset
          final nx1 = (x1 - i * perpX).round();
          final ny1 = (y1 - i * perpY).round();
          final nx2 = (x2 - i * perpX).round();
          final ny2 = (y2 - i * perpY).round();
          
          _drawLine(image, px1, py1, px2, py2, color);
          _drawLine(image, nx1, ny1, nx2, ny2, color);
        }
      }
    }
  }
  
  /// Draw a line on an image
  static void _drawLine(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    img.Color color,
  ) {
    // Bresenham's line algorithm
    int dx = (x2 - x1).abs();
    int dy = (y2 - y1).abs();
    int sx = x1 < x2 ? 1 : -1;
    int sy = y1 < y2 ? 1 : -1;
    int err = dx - dy;
    
    while (true) {
      if (x1 >= 0 && x1 < image.width && y1 >= 0 && y1 < image.height) {
        image.setPixel(x1, y1, color);
      }
      
      if (x1 == x2 && y1 == y2) break;
      
      int e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x1 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y1 += sy;
      }
    }
  }
}