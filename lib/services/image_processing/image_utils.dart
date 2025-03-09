import 'package:image/image.dart' as img;
import 'dart:math' as math;

/// Utility functions for image processing operations
class ImageUtils {
  /// Convert an image to grayscale
  static img.Image convertToGrayscale(img.Image image) {
    return img.grayscale(image);
  }
  
  /// Calculate luminance from RGB values
  static int calculateLuminance(int r, int g, int b) {
    return (0.299 * r + 0.587 * g + 0.114 * b).round();
  }
  
  /// Apply threshold to create a binary image
  static img.Image applyThreshold(img.Image grayscale, int threshold) {
    // Create a new image with the same dimensions
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Iterate through all pixels
    for (int y = 0; y < result.height; y++) {
      for (int x = 0; x < result.width; x++) {
        // Get pixel value from the newest API
        final pixel = grayscale.getPixel(x, y);
        
        // Calculate luminance from the pixel's RGB values
        final luminance = calculateLuminance(
          pixel.r.toInt(), 
          pixel.g.toInt(), 
          pixel.b.toInt()
        );
        
        // Apply threshold
        if (luminance > threshold) {
          // Set white
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        } else {
          // Set black
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        }
      }
    }
    
    return result;
  }
  
  /// Apply a blur filter to the image
  static img.Image applyBlur(img.Image image, int radius) {
    return img.gaussianBlur(image, radius: radius);
  }
  
  /// Draw a cross marker at the specified coordinates
  static void drawCross(img.Image image, int x, int y, img.Color color, int size) {
    for (int i = -size; i <= size; i++) {
      final px = x + i;
      final py = y;
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        image.setPixel(px, py, color);
      }
    }
    
    for (int i = -size; i <= size; i++) {
      final px = x;
      final py = y + i;
      if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
        image.setPixel(px, py, color);
      }
    }
  }
  
  /// Draw a circle at the specified coordinates
  static void drawCircle(img.Image image, int x, int y, int radius, img.Color color, {bool fill = false}) {
    for (int i = -radius; i <= radius; i++) {
      for (int j = -radius; j <= radius; j++) {
        final distance = math.sqrt(i * i + j * j);
        
        if (fill) {
          if (distance <= radius) {
            final px = x + i;
            final py = y + j;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, color);
            }
          }
        } else {
          if (distance >= radius - 0.5 && distance <= radius + 0.5) {
            final px = x + i;
            final py = y + j;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, color);
            }
          }
        }
      }
    }
  }
  
  /// Draw a line between two points
  static void drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
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
  
  /// Draw text at the specified coordinates
  static void drawText(img.Image image, String text, int x, int y, img.Color color) {
    // This is a simple implementation - ideally we'd have a proper font renderer
    // For now, we'll just draw a placeholder for the text
    final textWidth = text.length * 5;
    final textHeight = 10;
    
    // Draw a box to represent the text
    drawRectangle(image, x, y, x + textWidth, y + textHeight, color);
  }
  
  /// Draw a rectangle
  static void drawRectangle(img.Image image, int x1, int y1, int x2, int y2, img.Color color, {bool fill = false}) {
    if (fill) {
      for (int y = y1; y <= y2; y++) {
        for (int x = x1; x <= x2; x++) {
          if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
            image.setPixel(x, y, color);
          }
        }
      }
    } else {
      // Draw top and bottom horizontal lines
      for (int x = x1; x <= x2; x++) {
        if (x >= 0 && x < image.width && y1 >= 0 && y1 < image.height) {
          image.setPixel(x, y1, color);
        }
        if (x >= 0 && x < image.width && y2 >= 0 && y2 < image.height) {
          image.setPixel(x, y2, color);
        }
      }
      
      // Draw left and right vertical lines
      for (int y = y1; y <= y2; y++) {
        if (x1 >= 0 && x1 < image.width && y >= 0 && y < image.height) {
          image.setPixel(x1, y, color);
        }
        if (x2 >= 0 && x2 < image.width && y >= 0 && y < image.height) {
          image.setPixel(x2, y, color);
        }
      }
    }
  }
  
  /// Draw a contour (series of connected points)
  static void drawContour(img.Image image, List<Point> contour, img.Color color) {
    if (contour.isEmpty) return;
    
    for (int i = 0; i < contour.length; i++) {
      final p1 = contour[i];
      final p2 = contour[(i + 1) % contour.length];
      
      drawLine(
        image, 
        p1.x.round(), p1.y.round(), 
        p2.x.round(), p2.y.round(), 
        color
      );
    }
  }
  
  /// Apply edge detection to find contours in the image
  static img.Image applyEdgeDetection(img.Image image) {
    return img.sobel(image);
  }

  /// Common colors
  static img.Color get colorRed => img.ColorRgba8(255, 0, 0, 255);
  static img.Color get colorGreen => img.ColorRgba8(0, 255, 0, 255);
  static img.Color get colorBlue => img.ColorRgba8(0, 0, 255, 255);
  static img.Color get colorWhite => img.ColorRgba8(255, 255, 255, 255);
  static img.Color get colorBlack => img.ColorRgba8(0, 0, 0, 255);
}

class Point {
  final double x;
  final double y;
  
  Point(this.x, this.y);
}