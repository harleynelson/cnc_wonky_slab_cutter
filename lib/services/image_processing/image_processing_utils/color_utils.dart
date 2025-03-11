import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'base_image_utils.dart';

/// Utilities for color processing and manipulation
class ColorUtils {
  /// Convert RGB to HSV color space
  static Map<String, double> rgbToHsv(int r, int g, int b) {
    // Normalize RGB values to 0-1
    final red = r / 255;
    final green = g / 255;
    final blue = b / 255;
    
    final maxValue = math.max(red, math.max(green, blue));
    final minValue = math.min(red, math.min(green, blue));
    final delta = maxValue - minValue;
    
    double hue = 0;
    double saturation = maxValue == 0 ? 0 : delta / maxValue;
    double value = maxValue;
    
    if (delta > 0) {
      if (maxValue == red) {
        hue = 60 * (((green - blue) / delta) % 6);
      } else if (maxValue == green) {
        hue = 60 * (((blue - red) / delta) + 2);
      } else {
        hue = 60 * (((red - green) / delta) + 4);
      }
      
      if (hue < 0) hue += 360;
    }
    
    return {
      'h': hue,
      's': saturation,
      'v': value,
    };
  }
  
  /// Convert HSV to RGB color space
  static Map<String, int> hsvToRgb(double h, double s, double v) {
    int r, g, b;
    
    if (s <= 0.0) {
      // Achromatic (gray)
      r = g = b = (v * 255).round();
      return {'r': r, 'g': g, 'b': b};
    }
    
    h %= 360;
    h /= 60; // sector 0 to 5
    int i = h.floor();
    double f = h - i; // factorial part of h
    double p = v * (1 - s);
    double q = v * (1 - s * f);
    double t = v * (1 - s * (1 - f));
    
    switch (i) {
      case 0:
        r = (v * 255).round();
        g = (t * 255).round();
        b = (p * 255).round();
        break;
      case 1:
        r = (q * 255).round();
        g = (v * 255).round();
        b = (p * 255).round();
        break;
      case 2:
        r = (p * 255).round();
        g = (v * 255).round();
        b = (t * 255).round();
        break;
      case 3:
        r = (p * 255).round();
        g = (q * 255).round();
        b = (v * 255).round();
        break;
      case 4:
        r = (t * 255).round();
        g = (p * 255).round();
        b = (v * 255).round();
        break;
      default: // case 5:
        r = (v * 255).round();
        g = (p * 255).round();
        b = (q * 255).round();
        break;
    }
    
    return {'r': r, 'g': g, 'b': b};
  }
  
  /// Calculate color histogram for an image
  static Map<String, List<int>> calculateHistogram(img.Image image) {
    final histR = List<int>.filled(256, 0);
    final histG = List<int>.filled(256, 0);
    final histB = List<int>.filled(256, 0);
    final histGray = List<int>.filled(256, 0);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        histR[r]++;
        histG[g]++;
        histB[b]++;
        
        final gray = BaseImageUtils.calculateLuminance(r, g, b);
        histGray[gray]++;
      }
    }
    
    return {
      'r': histR,
      'g': histG,
      'b': histB,
      'gray': histGray,
    };
  }
  
  /// Apply a color adjustment to an image
  static img.Image adjustColor(
    img.Image image, {
    double rFactor = 1.0,
    double gFactor = 1.0,
    double bFactor = 1.0,
  }) {
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        
        final r = (pixel.r.toInt() * rFactor).round().clamp(0, 255);
        final g = (pixel.g.toInt() * gFactor).round().clamp(0, 255);
        final b = (pixel.b.toInt() * bFactor).round().clamp(0, 255);
        
        result.setPixel(x, y, img.ColorRgba8(r, g, b, pixel.a.toInt()));
      }
    }
    
    return result;
  }
  
  /// Apply a tint (color overlay) to an image
  static img.Image applyTint(img.Image image, img.Color tintColor, double strength) {
    final result = img.Image(width: image.width, height: image.height);
    
    final tintR = tintColor.r.toInt();
    final tintG = tintColor.g.toInt();
    final tintB = tintColor.b.toInt();
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        
        final r = _blend(pixel.r.toInt(), tintR, strength);
        final g = _blend(pixel.g.toInt(), tintG, strength);
        final b = _blend(pixel.b.toInt(), tintB, strength);
        
        result.setPixel(x, y, img.ColorRgba8(r, g, b, pixel.a.toInt()));
      }
    }
    
    return result;
  }
  
  /// Convert an image to sepia tone
  static img.Image applySepiaFilter(img.Image image, {double intensity = 1.0}) {
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        final tr = math.min(255, (0.393 * r + 0.769 * g + 0.189 * b).round());
        final tg = math.min(255, (0.349 * r + 0.686 * g + 0.168 * b).round());
        final tb = math.min(255, (0.272 * r + 0.534 * g + 0.131 * b).round());
        
        final newR = _blend(r, tr, intensity);
        final newG = _blend(g, tg, intensity);
        final newB = _blend(b, tb, intensity);
        
        result.setPixel(x, y, img.ColorRgba8(newR, newG, newB, pixel.a.toInt()));
      }
    }
    
    return result;
  }
  
  /// Apply a color filter (e.g., red filter)
  static img.Image applyColorFilter(img.Image image, {int r = 0, int g = 0, int b = 0}) {
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        
        final newR = (pixel.r.toInt() + r).clamp(0, 255);
        final newG = (pixel.g.toInt() + g).clamp(0, 255);
        final newB = (pixel.b.toInt() + b).clamp(0, 255);
        
        result.setPixel(x, y, img.ColorRgba8(newR, newG, newB, pixel.a.toInt()));
      }
    }
    
    return result;
  }
  
  /// Invert the colors of an image
  static img.Image invertColors(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        
        final r = 255 - pixel.r.toInt();
        final g = 255 - pixel.g.toInt();
        final b = 255 - pixel.b.toInt();
        
        result.setPixel(x, y, img.ColorRgba8(r, g, b, pixel.a.toInt()));
      }
    }
    
    return result;
  }
  
  /// Adjust image temperature (warm/cool)
  static img.Image adjustTemperature(img.Image image, double temperature) {
    // Temperature ranges from -1.0 (cool/blue) to 1.0 (warm/yellow)
    final result = img.Image(width: image.width, height: image.height);
    
    double rFactor = 1.0, gFactor = 1.0, bFactor = 1.0;
    
    if (temperature > 0) {
      // Warm/yellow
      rFactor = 1.0 + temperature * 0.2;
      gFactor = 1.0 + temperature * 0.1;
      bFactor = 1.0 - temperature * 0.1;
    } else if (temperature < 0) {
      // Cool/blue
      rFactor = 1.0 + temperature * 0.1;
      gFactor = 1.0 + temperature * 0.05;
      bFactor = 1.0 - temperature * 0.2;
    }
    
    return adjustColor(image, rFactor: rFactor, gFactor: gFactor, bFactor: bFactor);
  }
  
  /// Adjust image saturation
  static img.Image adjustSaturation(img.Image image, double saturationFactor) {
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // Convert to HSV
        final hsv = rgbToHsv(r, g, b);
        
        // Adjust saturation
        final newSaturation = (hsv['s']! * saturationFactor).clamp(0.0, 1.0);
        
        // Convert back to RGB
        final rgb = hsvToRgb(hsv['h']!, newSaturation, hsv['v']!);
        
        result.setPixel(x, y, img.ColorRgba8(rgb['r']!, rgb['g']!, rgb['b']!, pixel.a.toInt()));
      }
    }
    
    return result;
  }
  
  /// Replace a specific color with another
  static img.Image replaceColor(
    img.Image image,
    img.Color targetColor,
    img.Color replacementColor,
    double tolerance
  ) {
    final result = img.Image(width: image.width, height: image.height);
    
    final targetR = targetColor.r.toInt();
    final targetG = targetColor.g.toInt();
    final targetB = targetColor.b.toInt();
    
    final newR = replacementColor.r.toInt();
    final newG = replacementColor.g.toInt();
    final newB = replacementColor.b.toInt();
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // Calculate color distance
        final distance = math.sqrt(
          math.pow(r - targetR, 2) +
          math.pow(g - targetG, 2) +
          math.pow(b - targetB, 2)
        ) / 442.0; // Normalize to 0-1 (max distance = sqrt(255^2 + 255^2 + 255^2))
        
        if (distance <= tolerance) {
          // Replace color based on proximity
          final blend = 1.0 - (distance / tolerance);
          final finalR = _blend(r, newR, blend);
          final finalG = _blend(g, newG, blend);
          final finalB = _blend(b, newB, blend);
          
          result.setPixel(x, y, img.ColorRgba8(finalR, finalG, finalB, pixel.a.toInt()));
        } else {
          // Keep original color
          result.setPixel(x, y, pixel);
        }
      }
    }
    
    return result;
  }
  
  /// Helper function to blend two colors
  static int _blend(int original, int target, double factor) {
    return (original * (1 - factor) + target * factor).round().clamp(0, 255);
  }
  
  /// Create a color palette from an image
  static List<img.Color> extractDominantColors(img.Image image, int numColors) {
    // This is a simplified implementation for dominant color extraction
    // A proper implementation would use clustering algorithms like K-means
    
    // Step 1: Extract all pixels and count frequency
    final colorMap = <int, int>{};
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Use RGB value as a key
        final colorKey = (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
        colorMap[colorKey] = (colorMap[colorKey] ?? 0) + 1;
      }
    }
    
    // Step 2: Sort by frequency
    final sortedColors = colorMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    // Step 3: Return top colors
    return sortedColors.take(numColors).map((entry) {
      final r = (entry.key >> 16) & 0xFF;
      final g = (entry.key >> 8) & 0xFF;
      final b = entry.key & 0xFF;
      return img.ColorRgba8(r, g, b, 255);
    }).toList();
  }
}