import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Enhanced utility class for image processing operations
class ImageUtils {
  /// Convert an image to grayscale
  static img.Image convertToGrayscale(img.Image image) {
    try {
      return img.grayscale(image);
    } catch (e) {
      print('Error converting to grayscale: $e');
      // Create a new grayscale image manually if the built-in function fails
      final result = img.Image(width: image.width, height: image.height);
      
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          final gray = calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          result.setPixel(x, y, img.ColorRgba8(gray, gray, gray, 255));
        }
      }
      
      return result;
    }
  }

  /// Enhance contrast in an image
  static img.Image enhanceContrast(img.Image grayscale) {
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Find min and max pixel values
    int min = 255;
    int max = 0;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        min = math.min(min, intensity);
        max = math.max(max, intensity);
      }
    }
    
    // Avoid division by zero
    if (max == min) {
      return grayscale;
    }
    
    // Apply contrast stretching
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        final newIntensity = (255 * (intensity - min) / (max - min)).round().clamp(0, 255);
        result.setPixel(x, y, img.ColorRgba8(newIntensity, newIntensity, newIntensity, 255));
      }
    }
    
    return result;
  }
  
  /// Calculate luminance (brightness) from RGB values
  static int calculateLuminance(int r, int g, int b) {
    return (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
  }

  
  /// Apply threshold to create a binary image
  static img.Image applyThreshold(img.Image grayscale, int threshold) {
    // Create a new image with the same dimensions
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    try {
      // Iterate through all pixels
      for (int y = 0; y < result.height; y++) {
        for (int x = 0; x < result.width; x++) {
          // Get pixel value
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
    } catch (e) {
      print('Error applying threshold: $e');
      return grayscale; // Return original if thresholding fails
    }
  }
  
  /// Apply Otsu's method to find optimal threshold
  static int findOptimalThreshold(img.Image grayscale) {
    try {
      // Create histogram
      final histogram = List<int>.filled(256, 0);
      
      // Count pixel intensities
      for (int y = 0; y < grayscale.height; y++) {
        for (int x = 0; x < grayscale.width; x++) {
          final pixel = grayscale.getPixel(x, y);
          final intensity = calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          histogram[intensity]++;
        }
      }
      
      // Total number of pixels
      final total = grayscale.width * grayscale.height;
      
      double sum = 0;
      for (int i = 0; i < 256; i++) {
        sum += i * histogram[i];
      }
      
      double sumB = 0;
      int wB = 0;
      int wF = 0;
      
      double maxVariance = 0;
      int threshold = 0;
      
      // Compute threshold
      for (int t = 0; t < 256; t++) {
        wB += histogram[t]; // Weight background
        if (wB == 0) continue;
        
        wF = total - wB; // Weight foreground
        if (wF == 0) break;
        
        sumB += t * histogram[t];
        
        final mB = sumB / wB; // Mean background
        final mF = (sum - sumB) / wF; // Mean foreground
        
        // Calculate between-class variance
        final variance = wB * wF * (mB - mF) * (mB - mF);
        
        if (variance > maxVariance) {
          maxVariance = variance;
          threshold = t;
        }
      }
      
      return threshold;
    } catch (e) {
      print('Error finding optimal threshold: $e');
      return 128; // Return default threshold if calculation fails
    }
  }
  
  /// Apply adaptive thresholding
  static img.Image applyAdaptiveThreshold(img.Image grayscale, int blockSize, int constant) {
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    try {
      final halfBlock = blockSize ~/ 2;
      
      for (int y = 0; y < grayscale.height; y++) {
        for (int x = 0; x < grayscale.width; x++) {
          // Calculate local mean
          int sum = 0;
          int count = 0;
          
          for (int j = math.max(0, y - halfBlock); j <= math.min(grayscale.height - 1, y + halfBlock); j++) {
            for (int i = math.max(0, x - halfBlock); i <= math.min(grayscale.width - 1, x + halfBlock); i++) {
              final pixel = grayscale.getPixel(i, j);
              sum += calculateLuminance(
                pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
              );
              count++;
            }
          }
          
          final mean = count > 0 ? sum / count : 128;
          final pixel = grayscale.getPixel(x, y);
          final pixelValue = calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          
          // Apply threshold
          if (pixelValue > mean - constant) {
            result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
          } else {
            result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
          }
        }
      }
      
      return result;
    } catch (e) {
      print('Error applying adaptive threshold: $e');
      return grayscale; // Return original if thresholding fails
    }
  }
  
  /// Apply histogram equalization to enhance contrast
  static img.Image applyHistogramEqualization(img.Image grayscale) {
    final equalized = img.Image(width: grayscale.width, height: grayscale.height);
    
    try {
      // Create histogram
      final histogram = List<int>.filled(256, 0);
      
      // Count pixel intensities
      for (int y = 0; y < grayscale.height; y++) {
        for (int x = 0; x < grayscale.width; x++) {
          final pixel = grayscale.getPixel(x, y);
          final intensity = calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          histogram[intensity.clamp(0, 255)]++;
        }
      }
      
      // Calculate cumulative distribution function (CDF)
      final cdf = List<int>.filled(256, 0);
      cdf[0] = histogram[0];
      for (int i = 1; i < 256; i++) {
        cdf[i] = cdf[i - 1] + histogram[i];
      }
      
      // Normalize CDF to create lookup table
      final totalPixels = grayscale.width * grayscale.height;
      final lookup = List<int>.filled(256, 0);
      
      if (cdf[255] > 0) { // Ensure we don't divide by zero
        for (int i = 0; i < 256; i++) {
          lookup[i] = ((cdf[i] / cdf[255]) * 255).round().clamp(0, 255);
        }
      }
      
      // Apply lookup to create equalized image
      for (int y = 0; y < grayscale.height; y++) {
        for (int x = 0; x < grayscale.width; x++) {
          final pixel = grayscale.getPixel(x, y);
          final intensity = calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          ).clamp(0, 255);
          final newIntensity = lookup[intensity];
          equalized.setPixel(x, y, img.ColorRgba8(
            newIntensity, newIntensity, newIntensity, 255
          ));
        }
      }
      
      return equalized;
    } catch (e) {
      print('Error applying histogram equalization: $e');
      return grayscale; // Return original if equalization fails
    }
  }
  
  /// Apply edge detection
  static img.Image applyEdgeDetection(img.Image image, {int threshold = 50}) {
    try {
      // Use Sobel edge detection
      final edges = img.sobel(image);
      
      // Apply threshold if requested
      if (threshold > 0) {
        return applyThreshold(edges, threshold);
      }
      
      return edges;
    } catch (e) {
      print('Error applying edge detection: $e');
      return image; // Return original if edge detection fails
    }
  }
  
  /// Safely resize an image
  static img.Image safeResize(img.Image image, {int? width, int? height, int maxSize = 1200}) {
    try {
      // Calculate new dimensions while maintaining aspect ratio
      int targetWidth = width ?? image.width;
      int targetHeight = height ?? image.height;
      
      if (width == null && height == null) {
        // If neither width nor height specified, limit to maxSize
        if (image.width > maxSize || image.height > maxSize) {
          final aspectRatio = image.width / image.height;
          if (image.width > image.height) {
            targetWidth = maxSize;
            targetHeight = (maxSize / aspectRatio).round();
          } else {
            targetHeight = maxSize;
            targetWidth = (maxSize * aspectRatio).round();
          }
        }
      } else if (width == null) {
        // Height specified, calculate width from aspect ratio
        final aspectRatio = image.width / image.height;
        targetWidth = (targetHeight! * aspectRatio).round();
      } else if (height == null) {
        // Width specified, calculate height from aspect ratio
        final aspectRatio = image.width / image.height;
        targetHeight = (targetWidth / aspectRatio).round();
      }
      
      // Ensure positive dimensions
      targetWidth = math.max(1, targetWidth);
      targetHeight = math.max(1, targetHeight);
      
      return img.copyResize(
        image,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.average
      );
    } catch (e) {
      print('Error resizing image: $e');
      return image; // Return original if resize fails
    }
  }
  
  /// Draw a cross marker at the specified coordinates
  static void drawCross(img.Image image, int x, int y, img.Color color, int size) {
    try {
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
    } catch (e) {
      print('Error drawing cross: $e');
    }
  }
  
  /// Draw a circle at the specified coordinates
  static void drawCircle(img.Image image, int x, int y, int radius, img.Color color, {bool fill = false}) {
    try {
      for (int i = -radius; i <= radius; i++) {
        for (int j = -radius; j <= radius; j++) {
          final distance = math.sqrt(i * i + j * j);
          
          bool drawPixel = false;
          if (fill) {
            drawPixel = distance <= radius;
          } else {
            drawPixel = distance >= radius - 0.5 && distance <= radius + 0.5;
          }
          
          if (drawPixel) {
            final px = x + i;
            final py = y + j;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, color);
            }
          }
        }
      }
    } catch (e) {
      print('Error drawing circle: $e');
    }
  }
  
  /// Draw a line between two points
  static void drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
    try {
      // Validate coordinates
      if (x1 < 0 || x1 >= image.width || y1 < 0 || y1 >= image.height ||
          x2 < 0 || x2 >= image.width || y2 < 0 || y2 >= image.height) {
        // Use clipping to handle partially visible lines
        // For now, just skip invalid points
        if ((x1 < 0 || x1 >= image.width || y1 < 0 || y1 >= image.height) &&
            (x2 < 0 || x2 >= image.width || y2 < 0 || y2 >= image.height)) {
          return; // Both endpoints outside image
        }
      }
      
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
    } catch (e) {
      print('Error drawing line: $e');
    }
  }
  
  /// Draw a rectangle
  static void drawRectangle(img.Image image, int x1, int y1, int x2, int y2, img.Color color, {bool fill = false}) {
    try {
      if (fill) {
        for (int y = math.max(0, y1); y <= math.min(y2, image.height - 1); y++) {
          for (int x = math.max(0, x1); x <= math.min(x2, image.width - 1); x++) {
            image.setPixel(x, y, color);
          }
        }
      } else {
        // Draw top and bottom horizontal lines
        for (int x = math.max(0, x1); x <= math.min(x2, image.width - 1); x++) {
          if (y1 >= 0 && y1 < image.height) {
            image.setPixel(x, y1, color);
          }
          if (y2 >= 0 && y2 < image.height) {
            image.setPixel(x, y2, color);
          }
        }
        
        // Draw left and right vertical lines
        for (int y = math.max(0, y1); y <= math.min(y2, image.height - 1); y++) {
          if (x1 >= 0 && x1 < image.width) {
            image.setPixel(x1, y, color);
          }
          if (x2 >= 0 && x2 < image.width) {
            image.setPixel(x2, y, color);
          }
        }
      }
    } catch (e) {
      print('Error drawing rectangle: $e');
    }
  }
  
  
  /// Draw text on the image (simplified implementation)
  static void drawText(img.Image image, String text, int x, int y, img.Color color) {
    try {
      // Draw a background for better readability
      drawRectangle(
        image,
        x - 1, y - 1,
        x + text.length * 6, y + 8,
        img.ColorRgba8(0, 0, 0, 200),
        fill: true
      );
      
      // Simple implementation - in a real app, use a proper font renderer
      for (int i = 0; i < text.length; i++) {
        final char = text.codeUnitAt(i);
        final charX = x + i * 6;
        
        if (charX + 5 >= image.width) break;
        
        for (int dy = 0; dy < 7; dy++) {
          for (int dx = 0; dx < 5; dx++) {
            if (_getCharPixel(char, dx, dy)) {
              final screenX = charX + dx;
              final screenY = y + dy;
              
              if (screenX >= 0 && screenX < image.width && 
                  screenY >= 0 && screenY < image.height) {
                image.setPixel(screenX, screenY, color);
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error drawing text: $e');
    }
  }
  
  /// Simple bitmap font implementation (very basic)
  static bool _getCharPixel(int charCode, int x, int y) {
    if (x < 0 || y < 0 || x >= 5 || y >= 7) return false;
    
    // Simplified fonts for various characters
    switch (charCode) {
      case 32: // space
        return false;
      case 46: // .
        return y == 6 && x == 2;
      case 48: // 0
        return (x == 0 || x == 4 || y == 0 || y == 6) && !(x == 0 && y == 0) && !(x == 4 && y == 0) && !(x == 0 && y == 6) && !(x == 4 && y == 6);
      case 49: // 1
        return x == 2 || y == 6 || (x == 1 && y == 1);
      case 50: // 2
        return (y == 0 && x > 0) || (y == 3) || (y == 6) || (x == 4 && y == 1) || (x == 0 && y == 5);
      case 51: // 3
        return (y == 0 || y == 3 || y == 6) || x == 4;
      case 52: // 4
        return (x == 3) || (y == 3) || (x == 0 && y < 3);
      case 53: // 5
        return (y == 0) || (y == 3) || (y == 6) || (x == 0 && y < 3) || (x == 4 && y > 3);
      case 54: // 6
        return (y == 0 || y == 3 || y == 6) || (x == 0) || (x == 4 && y > 3);
      case 55: // 7
        return (y == 0) || (x == 4);
      case 56: // 8
        return (y == 0 || y == 3 || y == 6) || (x == 0 || x == 4);
      case 57: // 9
        return (y == 0 || y == 3 || y == 6) || (x == 4) || (x == 0 && y < 3);
      case 58: // :
        return (x == 2 && (y == 2 || y == 4));
      default:
        // Simple algorithm for letters and other characters
        if (charCode >= 65 && charCode <= 90) { // A-Z
          return _getUppercaseCharPixel(charCode, x, y);
        } else if (charCode >= 97 && charCode <= 122) { // a-z
          return _getLowercaseCharPixel(charCode, x, y);
        } else {
          // Default pattern for other chars
          return (x == 0 || x == 4 || y == 0 || y == 6);
        }
    }
  }
  
  /// Simplified uppercase character pixel getter
  static bool _getUppercaseCharPixel(int charCode, int x, int y) {
    switch (charCode) {
      case 65: // A
        return (x == 0 || x == 4) || (y == 0) || (y == 3);
      case 66: // B
        return (x == 0) || (y == 0 || y == 3 || y == 6) || (x == 4 && y != 0 && y != 3 && y != 6);
      case 67: // C
        return (y == 0 || y == 6) || (x == 0);
      case 68: // D
        return (x == 0) || (y == 0 || y == 6) || (x == 4 && y != 0 && y != 6);
      case 69: // E
        return (x == 0) || (y == 0 || y == 3 || y == 6);
      case 70: // F
        return (x == 0) || (y == 0 || y == 3);
      // Add more as needed...
      default:
        return (x == 0 || x == 4 || y == 0 || y == 3);
    }
  }
  
  /// Simplified lowercase character pixel getter
  static bool _getLowercaseCharPixel(int charCode, int x, int y) {
    // Offset to convert a-z to A-Z
    return _getUppercaseCharPixel(charCode - 32, x, y);
  }
  
  
  /// Common colors for convenience
  static img.Color get colorRed => img.ColorRgba8(255, 0, 0, 255);
  static img.Color get colorGreen => img.ColorRgba8(0, 255, 0, 255);
  static img.Color get colorBlue => img.ColorRgba8(0, 0, 255, 255);
  static img.Color get colorYellow => img.ColorRgba8(255, 255, 0, 255);
  static img.Color get colorCyan => img.ColorRgba8(0, 255, 255, 255);
  static img.Color get colorMagenta => img.ColorRgba8(255, 0, 255, 255);
  static img.Color get colorWhite => img.ColorRgba8(255, 255, 255, 255);
  static img.Color get colorBlack => img.ColorRgba8(0, 0, 0, 255);
  static img.Color get colorGray => img.ColorRgba8(128, 128, 128, 255);
  
  /// Create a color with custom RGB values
  static img.Color getRgbColor(int r, int g, int b, {int a = 255}) {
    return img.ColorRgba8(
      r.clamp(0, 255), 
      g.clamp(0, 255), 
      b.clamp(0, 255), 
      a.clamp(0, 255)
    );
  }
  
}