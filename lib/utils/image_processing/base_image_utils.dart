
import 'package:image/image.dart' as img;

/// Core image utility functions for loading, saving, and basic manipulation
class BaseImageUtils {
  /// Calculate luminance (brightness) from RGB values
  /// Using the standard luminance formula: Y = 0.299*R + 0.587*G + 0.114*B
  static int calculateLuminance(int r, int g, int b) {
    return (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
  }
  
  /// Convert an image to grayscale
  static img.Image convertToGrayscale(img.Image image) {
    try {
      // Try the built-in method first
      return img.grayscale(image);
    } catch (e) {
      print('Error using built-in grayscale, falling back to manual conversion: $e');
      
      // Manual conversion as fallback
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
  
}