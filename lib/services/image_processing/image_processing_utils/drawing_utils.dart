import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../gcode/machine_coordinates.dart';

/// Utilities for drawing shapes, lines, and text on images
class DrawingUtils {
  /// Draw a line on an image
  static void drawLine(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    img.Color color
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
  
  /// Draw a thick line on an image
  static void drawThickLine(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    img.Color color,
    int thickness
  ) {
    // Draw the main line
    drawLine(image, x1, y1, x2, y2, color);
    
    // If thickness > 1, draw additional lines
    if (thickness > 1) {
      final dx = x2 - x1;
      final dy = y2 - y1;
      final length = math.sqrt(dx * dx + dy * dy);
      
      if (length > 0) {
        // Calculate perpendicular vector
        final px = -dy / length;
        final py = dx / length;
        
        // Draw parallel lines
        for (int i = 1; i <= thickness ~/ 2; i++) {
          // Positive offset
          final ox1 = (x1 + i * px).round();
          final oy1 = (y1 + i * py).round();
          final ox2 = (x2 + i * px).round();
          final oy2 = (y2 + i * py).round();
          
          // Negative offset
          final nx1 = (x1 - i * px).round();
          final ny1 = (y1 - i * py).round();
          final nx2 = (x2 - i * px).round();
          final ny2 = (y2 - i * py).round();
          
          drawLine(image, ox1, oy1, ox2, oy2, color);
          drawLine(image, nx1, ny1, nx2, ny2, color);
        }
      }
    }
  }
  
  /// Draw a dotted/dashed line
  static void drawDashedLine(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    img.Color color,
    int dashLength,
    int gapLength
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final length = math.sqrt(dx * dx + dy * dy);
    
    if (length < 1e-10) {
      // Just a point
      if (x1 >= 0 && x1 < image.width && y1 >= 0 && y1 < image.height) {
        image.setPixel(x1, y1, color);
      }
      return;
    }
    
    // Normalize direction vector
    final dirX = dx / length;
    final dirY = dy / length;
    
    // Draw dashed line
    double currentLength = 0;
    bool drawing = true;
    int currentDashLength = dashLength;
    
    while (currentLength < length) {
      final currentX = (x1 + currentLength * dirX).round();
      final currentY = (y1 + currentLength * dirY).round();
      
      if (drawing && currentX >= 0 && currentX < image.width && 
          currentY >= 0 && currentY < image.height) {
        image.setPixel(currentX, currentY, color);
      }
      
      currentLength++;
      currentDashLength--;
      
      if (currentDashLength == 0) {
        drawing = !drawing;
        currentDashLength = drawing ? dashLength : gapLength;
      }
    }
  }
  
  /// Draw a circle on an image
  static void drawCircle(
    img.Image image,
    int centerX,
    int centerY,
    int radius,
    img.Color color,
    {bool fill = false}
  ) {
    if (radius <= 0) {
      if (centerX >= 0 && centerX < image.width && 
          centerY >= 0 && centerY < image.height) {
        image.setPixel(centerX, centerY, color);
      }
      return;
    }
    
    if (fill) {
      // Draw filled circle using midpoint circle algorithm
      for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
          if (x * x + y * y <= radius * radius) {
            final px = centerX + x;
            final py = centerY + y;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, color);
            }
          }
        }
      }
    } else {
      // Draw circle outline using Bresenham's circle algorithm
      int x = 0;
      int y = radius;
      int d = 3 - 2 * radius;
      
      while (y >= x) {
        // Draw 8 octants
        _drawCirclePoints(image, centerX, centerY, x, y, color);
        
        if (d > 0) {
          d = d + 4 * (x - y) + 10;
          y--;
        } else {
          d = d + 4 * x + 6;
        }
        x++;
      }
    }
  }
  
  /// Helper method to draw points for each octant of a circle
  static void _drawCirclePoints(
    img.Image image,
    int centerX,
    int centerY,
    int x,
    int y,
    img.Color color
  ) {
    // Draw 8 points for 8 octants
    _setPixelSafe(image, centerX + x, centerY + y, color);
    _setPixelSafe(image, centerX - x, centerY + y, color);
    _setPixelSafe(image, centerX + x, centerY - y, color);
    _setPixelSafe(image, centerX - x, centerY - y, color);
    _setPixelSafe(image, centerX + y, centerY + x, color);
    _setPixelSafe(image, centerX - y, centerY + x, color);
    _setPixelSafe(image, centerX + y, centerY - x, color);
    _setPixelSafe(image, centerX - y, centerY - x, color);
  }
  
  /// Helper to safely set a pixel if it's in bounds
  static void _setPixelSafe(img.Image image, int x, int y, img.Color color) {
    if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
      image.setPixel(x, y, color);
    }
  }
  
  /// Draw an ellipse on an image
  static void drawEllipse(
    img.Image image,
    int centerX,
    int centerY,
    int radiusX,
    int radiusY,
    img.Color color,
    {bool fill = false}
  ) {
    // Handle edge cases
    if (radiusX <= 0 || radiusY <= 0) {
      if (centerX >= 0 && centerX < image.width && 
          centerY >= 0 && centerY < image.height) {
        image.setPixel(centerX, centerY, color);
      }
      return;
    }
    
    if (fill) {
      // Draw filled ellipse
      for (int y = -radiusY; y <= radiusY; y++) {
        for (int x = -radiusX; x <= radiusX; x++) {
          // Check if point is inside ellipse
          if ((x * x) / (radiusX * radiusX) + (y * y) / (radiusY * radiusY) <= 1) {
            final px = centerX + x;
            final py = centerY + y;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, color);
            }
          }
        }
      }
    } else {
      // Draw ellipse outline using midpoint algorithm
      int x = 0;
      int y = radiusY;
      double d1 = radiusY * radiusY - radiusX * radiusX * radiusY + 0.25 * radiusX * radiusX;
      double dx = (2 * radiusY * radiusY * x) as double;
      double dy = (2 * radiusX * radiusX * y) as double;
      
      // First region
      while (dx < dy) {
        // Draw 4 quadrants
        _setPixelSafe(image, centerX + x, centerY + y, color);
        _setPixelSafe(image, centerX - x, centerY + y, color);
        _setPixelSafe(image, centerX + x, centerY - y, color);
        _setPixelSafe(image, centerX - x, centerY - y, color);
        
        // Update
        if (d1 < 0) {
          x++;
          dx += 2 * radiusY * radiusY;
          d1 += dx + radiusY * radiusY;
        } else {
          x++;
          y--;
          dx += 2 * radiusY * radiusY;
          dy -= 2 * radiusX * radiusX;
          d1 += dx - dy + radiusY * radiusY;
        }
      }
      
      // Second region
      double d2 = radiusY * radiusY * (x + 0.5) * (x + 0.5) + 
                  radiusX * radiusX * (y - 1) * (y - 1) - 
                  radiusX * radiusX * radiusY * radiusY;
      
      while (y >= 0) {
        // Draw 4 quadrants
        _setPixelSafe(image, centerX + x, centerY + y, color);
        _setPixelSafe(image, centerX - x, centerY + y, color);
        _setPixelSafe(image, centerX + x, centerY - y, color);
        _setPixelSafe(image, centerX - x, centerY - y, color);
        
        // Update
        if (d2 > 0) {
          y--;
          dy -= 2 * radiusX * radiusX;
          d2 += radiusX * radiusX - dy;
        } else {
          y--;
          x++;
          dx += 2 * radiusY * radiusY;
          dy -= 2 * radiusX * radiusX;
          d2 += dx - dy + radiusX * radiusX;
        }
      }
    }
  }
  
  /// Draw a rectangle on an image
  static void drawRectangle(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    img.Color color,
    {bool fill = false}
  ) {
    // Ensure coordinates are ordered
    final left = math.min(x1, x2);
    final right = math.max(x1, x2);
    final top = math.min(y1, y2);
    final bottom = math.max(y1, y2);
    
    if (fill) {
      // Draw filled rectangle
      for (int y = top; y <= bottom; y++) {
        for (int x = left; x <= right; x++) {
          if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
            image.setPixel(x, y, color);
          }
        }
      }
    } else {
      // Draw rectangle outline
      // Horizontal lines
      for (int x = left; x <= right; x++) {
        if (top >= 0 && top < image.height && x >= 0 && x < image.width) {
          image.setPixel(x, top, color); // Top line
        }
        if (bottom >= 0 && bottom < image.height && x >= 0 && x < image.width) {
          image.setPixel(x, bottom, color); // Bottom line
        }
      }
      
      // Vertical lines
      for (int y = top + 1; y < bottom; y++) {
        if (left >= 0 && left < image.width && y >= 0 && y < image.height) {
          image.setPixel(left, y, color); // Left line
        }
        if (right >= 0 && right < image.width && y >= 0 && y < image.height) {
          image.setPixel(right, y, color); // Right line
        }
      }
    }
  }
  
  /// Draw a rounded rectangle on an image
  static void drawRoundedRectangle(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    int radius,
    img.Color color,
    {bool fill = false}
  ) {
    // Ensure coordinates are ordered
    final left = math.min(x1, x2);
    final right = math.max(x1, x2);
    final top = math.min(y1, y2);
    final bottom = math.max(y1, y2);
    
    // Ensure radius is not too large
    final width = right - left;
    final height = bottom - top;
    radius = math.min(radius, math.min(width, height) ~/ 2);
    
    if (fill) {
      // Draw filled rounded rectangle
      
      // Draw main rectangle without corners
      for (int y = top + radius; y <= bottom - radius; y++) {
        for (int x = left; x <= right; x++) {
          if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
            image.setPixel(x, y, color);
          }
        }
      }
      
      // Draw top and bottom rectangles without corners
      for (int y = top; y < top + radius; y++) {
        for (int x = left + radius; x <= right - radius; x++) {
          if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
            image.setPixel(x, y, color); // Top rectangle
          }
        }
      }
      
      for (int y = bottom - radius + 1; y <= bottom; y++) {
        for (int x = left + radius; x <= right - radius; x++) {
          if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
            image.setPixel(x, y, color); // Bottom rectangle
          }
        }
      }
      
      // Draw corner circles
      drawCircle(image, left + radius, top + radius, radius, color, fill: true); // Top-left
      drawCircle(image, right - radius, top + radius, radius, color, fill: true); // Top-right
      drawCircle(image, right - radius, bottom - radius, radius, color, fill: true); // Bottom-right
      drawCircle(image, left + radius, bottom - radius, radius, color, fill: true); // Bottom-left
    } else {
      // Draw horizontal lines
      for (int x = left + radius; x <= right - radius; x++) {
        if (top >= 0 && top < image.height && x >= 0 && x < image.width) {
          image.setPixel(x, top, color); // Top line
        }
        if (bottom >= 0 && bottom < image.height && x >= 0 && x < image.width) {
          image.setPixel(x, bottom, color); // Bottom line
        }
      }
      
      // Draw vertical lines
      for (int y = top + radius; y <= bottom - radius; y++) {
        if (left >= 0 && left < image.width && y >= 0 && y < image.height) {
          image.setPixel(left, y, color); // Left line
        }
        if (right >= 0 && right < image.width && y >= 0 && y < image.height) {
          image.setPixel(right, y, color); // Right line
        }
      }
      
      // Draw rounded corners
      _drawCornerArc(image, left + radius, top + radius, radius, 180, 270, color); // Top-left
      _drawCornerArc(image, right - radius, top + radius, radius, 270, 0, color); // Top-right
      _drawCornerArc(image, right - radius, bottom - radius, radius, 0, 90, color); // Bottom-right
      _drawCornerArc(image, left + radius, bottom - radius, radius, 90, 180, color); // Bottom-left
    }
  }
  
  /// Helper to draw a corner arc
  static void _drawCornerArc(
    img.Image image,
    int centerX,
    int centerY,
    int radius,
    int startAngle,
    int endAngle,
    img.Color color
  ) {
    // Ensure proper angle ordering
    if (startAngle > endAngle) {
      startAngle -= 360;
    }
    
    // Convert to radians
    final startRad = startAngle * math.pi / 180;
    final endRad = endAngle * math.pi / 180;
    
    // Use Bresenham's circle algorithm but only for the specified arc
    int x = 0;
    int y = radius;
    int d = 3 - 2 * radius;
    
    // Set of points in the circle
    final points = <List<int>>[];
    
    while (y >= x) {
      points.add([x, y]);
      
      if (d > 0) {
        d = d + 4 * (x - y) + 10;
        y--;
      } else {
        d = d + 4 * x + 6;
      }
      x++;
    }
    
    // Draw only points in the specified arc
    for (final point in points) {
      x = point[0];
      y = point[1];
      
      // Calculate angles for each octant
      final angles = [
        math.atan2(-y, x),   // 1st octant
        math.atan2(-x, y),   // 2nd octant
        math.atan2(-x, -y),  // 3rd octant
        math.atan2(-y, -x),  // 4th octant
        math.atan2(y, -x),   // 5th octant
        math.atan2(x, -y),   // 6th octant
        math.atan2(x, y),    // 7th octant
        math.atan2(y, x),    // 8th octant
      ];
      
      // Draw points if they are in the specified arc
      for (int i = 0; i < angles.length; i++) {
        double angle = angles[i];
        if (angle < 0) angle += 2 * math.pi;
        
        if (angle >= startRad && angle <= endRad) {
          int px, py;
          
          switch (i) {
            case 0: px = centerX + x; py = centerY - y; break;
            case 1: px = centerX + y; py = centerY - x; break;
            case 2: px = centerX + y; py = centerY + x; break;
            case 3: px = centerX + x; py = centerY + y; break;
            case 4: px = centerX - x; py = centerY + y; break;
            case 5: px = centerX - y; py = centerY + x; break;
            case 6: px = centerX - y; py = centerY - x; break;
            case 7: px = centerX - x; py = centerY - y; break;
            default: continue;
          }
          
          _setPixelSafe(image, px, py, color);
        }
      }
    }
  }
  
  /// Draw a polygon on an image
  static void drawPolygon(
    img.Image image,
    List<Point> points,
    img.Color color,
    {bool fill = false}
  ) {
    if (points.length < 3) return;
    
    // Draw polygon outline
    for (int i = 0; i < points.length; i++) {
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      
      drawLine(
        image, 
        p1.x.round(), p1.y.round(),
        p2.x.round(), p2.y.round(),
        color
      );
    }
    
    // Fill polygon if requested
    if (fill) {
      _fillPolygon(image, points, color);
    }
  }
  
  /// Fill a polygon using scan line algorithm
  static void _fillPolygon(img.Image image, List<Point> points, img.Color color) {
    if (points.length < 3) return;
    
    // Find min and max y-coordinates
    int minY = points[0].y.round();
    int maxY = points[0].y.round();
    
    for (int i = 1; i < points.length; i++) {
      minY = math.min(minY, points[i].y.round());
      maxY = math.max(maxY, points[i].y.round());
    }
    
    // Scan each line
    for (int y = minY; y <= maxY; y++) {
      final intersections = <int>[];
      
      // Find intersections with polygon edges
      for (int i = 0; i < points.length; i++) {
        final p1 = points[i];
        final p2 = points[(i + 1) % points.length];
        
        // Skip horizontal edges
        if ((p1.y < y && p2.y < y) || (p1.y > y && p2.y > y) || (p1.y == p2.y)) {
          continue;
        }
        
        // Calculate x-coordinate of intersection
        final x = p1.x + (p2.x - p1.x) * (y - p1.y) / (p2.y - p1.y);
        intersections.add(x.round());
      }
      
      // Sort intersections
      intersections.sort();
      
      // Fill between pairs of intersections
      for (int i = 0; i < intersections.length - 1; i += 2) {
        if (i + 1 < intersections.length) {
          for (int x = intersections[i]; x <= intersections[i + 1]; x++) {
            if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
              image.setPixel(x, y, color);
            }
          }
        }
      }
    }
  }
  
  /// Draw text on an image
  static void drawText(
    img.Image image,
    String text,
    int x,
    int y,
    img.Color color,
    {
      int scale = 1,
      bool drawBackground = false,
      img.Color backgroundColor = const img.ColorRgba8(0, 0, 0, 128),
    }
  ) {
    // Simple bitmap font implementation
    if (drawBackground) {
      // Calculate text size
      final textWidth = text.length * 6 * scale;
      final textHeight = 8 * scale;
      
      // Draw background
      drawRectangle(
        image, 
        x - scale, y - scale, 
        x + textWidth + scale, y + textHeight + scale, 
        backgroundColor,
        fill: true
      );
    }
    
    // Draw each character
    for (int i = 0; i < text.length; i++) {
      final charCode = text.codeUnitAt(i);
      _drawChar(image, charCode, x + i * 6 * scale, y, color, scale);
    }
  }
  
  /// Draw a character using a simple bitmap font
  static void _drawChar(
    img.Image image,
    int charCode,
    int x,
    int y,
    img.Color color,
    int scale
  ) {
    // Get bitmap for character
    final bitmap = _getCharBitmap(charCode);
    
    // Draw each pixel of the character bitmap
    for (int cy = 0; cy < bitmap.length; cy++) {
      for (int cx = 0; cx < bitmap[cy].length; cx++) {
        if (bitmap[cy][cx]) {
          // Draw scaled pixel
          for (int sy = 0; sy < scale; sy++) {
            for (int sx = 0; sx < scale; sx++) {
              final px = x + cx * scale + sx;
              final py = y + cy * scale + sy;
              
              if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
                image.setPixel(px, py, color);
              }
            }
          }
        }
      }
    }
  }
  
  /// Get bitmap for a character
  static List<List<bool>> _getCharBitmap(int charCode) {
    // Default 5x7 bitmap font
    switch (charCode) {
      // Space
      case 32:
        return [
          [false, false, false, false, false],
          [false, false, false, false, false],
          [false, false, false, false, false],
          [false, false, false, false, false],
          [false, false, false, false, false],
          [false, false, false, false, false],
          [false, false, false, false, false],
        ];
      
      // 0-9
      case 48: // 0
        return [
          [false, true, true, true, false],
          [true, false, false, false, true],
          [true, false, false, true, true],
          [true, false, true, false, true],
          [true, true, false, false, true],
          [true, false, false, false, true],
          [false, true, true, true, false],
        ];
      
      // A-Z
      case 65: // A
        return [
          [false, true, true, true, false],
          [true, false, false, false, true],
          [true, false, false, false, true],
          [true, true, true, true, true],
          [true, false, false, false, true],
          [true, false, false, false, true],
          [true, false, false, false, true],
        ];
      
      // a-z
      case 97: // a
        return [
          [false, false, false, false, false],
          [false, false, false, false, false],
          [false, true, true, true, false],
          [false, false, false, false, true],
          [false, true, true, true, true],
          [true, false, false, false, true],
          [false, true, true, true, true],
        ];
      
      // Default character (unknown)
      default:
        return [
          [true, true, true, true, true],
          [true, false, false, false, true],
          [true, false, false, false, true],
          [true, false, false, false, true],
          [true, false, false, false, true],
          [true, false, false, false, true],
          [true, true, true, true, true],
        ];
    }
  }
  
  /// Draw a marker (cross) at a specific point
  static void drawMarker(
    img.Image image,
    int x,
    int y,
    img.Color color,
    int size
  ) {
    // Draw a cross
    for (int i = -size; i <= size; i++) {
      final px = x + i;
      final py = y;
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        image.setPixel(px, py, color);
      }
      
      final px2 = x;
      final py2 = y + i;
      if (px2 >= 0 && px2 < image.width && py2 >= 0 && py2 < image.height) {
        image.setPixel(px2, py2, color);
      }
    }
    
    // Draw a circle around the cross
    drawCircle(image, x, y, size + 2, color);
  }
  
  /// Draw a dot marker at a specific point
  static void drawDotMarker(
    img.Image image,
    int x,
    int y,
    img.Color color,
    int size
  ) {
    drawCircle(image, x, y, size, color, fill: true);
  }
  
  /// Draw a contour (list of connected points)
  static void drawContour(
    img.Image image,
    List<Point> contour,
    img.Color color,
    {int thickness = 1}
  ) {
    if (contour.length < 2) return;
    
    for (int i = 0; i < contour.length - 1; i++) {
      drawThickLine(
        image,
        contour[i].x.round(), contour[i].y.round(),
        contour[i + 1].x.round(), contour[i + 1].y.round(),
        color,
        thickness
      );
    }
    
    // Close the contour if not already closed
    if (contour.first.x != contour.last.x || contour.first.y != contour.last.y) {
      drawThickLine(
        image,
        contour.last.x.round(), contour.last.y.round(),
        contour.first.x.round(), contour.first.y.round(),
        color,
        thickness
      );
    }
  }
  
  /// Draw multiple contours on an image
  static void drawContours(
    img.Image image,
    List<List<Point>> contours,
    img.Color color,
    {int thickness = 1}
  ) {
    for (final contour in contours) {
      drawContour(image, contour, color, thickness: thickness);
    }
  }
  
  /// Draw a grid on an image
  static void drawGrid(
    img.Image image,
    int cellSize,
    img.Color color,
    {int thickness = 1}
  ) {
    // Draw vertical lines
    for (int x = 0; x < image.width; x += cellSize) {
      drawThickLine(
        image,
        x, 0,
        x, image.height - 1,
        color,
        thickness
      );
    }
    
    // Draw horizontal lines
    for (int y = 0; y < image.height; y += cellSize) {
      drawThickLine(
        image,
        0, y,
        image.width - 1, y,
        color,
        thickness
      );
    }
  }
  
  /// Draw a ruler on the edge of an image
  static void drawRuler(
    img.Image image,
    img.Color color,
    {
      int tickInterval = 10,
      int labelInterval = 50,
      bool drawHorizontal = true,
      bool drawVertical = true
    }
  ) {
    final rulerWidth = 20;
    final tickLength = 5;
    final labelOffset = 5;
    
    if (drawHorizontal) {
      // Draw horizontal ruler
      drawRectangle(
        image,
        0, 0,
        image.width - 1, rulerWidth - 1,
        color,
        fill: true
      );
      
      // Draw ticks
      for (int x = 0; x < image.width; x += tickInterval) {
        final tickHeight = x % labelInterval == 0 ? tickLength * 2 : tickLength;
        
        drawLine(
          image,
          x, 0,
          x, tickHeight,
          img.ColorRgba8(0, 0, 0, 255)
        );
        
        // Draw labels
        if (x % labelInterval == 0) {
          drawText(
            image,
            x.toString(),
            x - 10, labelOffset,
            img.ColorRgba8(0, 0, 0, 255)
          );
        }
      }
    }
    
    if (drawVertical) {
      // Draw vertical ruler
      drawRectangle(
        image,
        0, 0,
        rulerWidth - 1, image.height - 1,
        color,
        fill: true
      );
      
      // Draw ticks
      for (int y = 0; y < image.height; y += tickInterval) {
        final tickWidth = y % labelInterval == 0 ? tickLength * 2 : tickLength;
        
        drawLine(
          image,
          0, y,
          tickWidth, y,
          img.ColorRgba8(0, 0, 0, 255)
        );
        
        // Draw labels
        if (y % labelInterval == 0) {
          drawText(
            image,
            y.toString(),
            labelOffset, y - 3,
            img.ColorRgba8(0, 0, 0, 255)
          );
        }
      }
    }
  }
  
  /// Draw a bounding box around an object
  static void drawBoundingBox(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    img.Color color,
    {
      int thickness = 1,
      String? label,
      img.Color? labelColor,
      bool drawBackground = true
    }
  ) {
    // Draw rectangle
    drawRectangle(
      image,
      x1, y1,
      x2, y2,
      color,
      fill: false
    );
    
    // Draw label if provided
    if (label != null) {
      final textColor = labelColor ?? img.ColorRgba8(255, 255, 255, 255);
      
      drawText(
        image,
        label,
        x1, y1 - 10,
        textColor,
        drawBackground: drawBackground,
        backgroundColor: color
      );
    }
  }
}