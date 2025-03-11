import 'dart:io';
import 'dart:typed_data';
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
  
  /// Safely load an image from a file
  static Future<img.Image?> loadImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return decodeImage(bytes);
    } catch (e) {
      print('Error loading image: $e');
      return null;
    }
  }
  
  /// Decode image bytes
  static img.Image? decodeImage(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (e) {
      print('Error decoding image: $e');
      return null;
    }
  }
  
  /// Save an image to a file
  static Future<File?> saveImage(img.Image image, String path, {String format = 'png'}) async {
    try {
      final file = File(path);
      List<int> bytes;
      
      switch (format.toLowerCase()) {
        case 'jpg':
        case 'jpeg':
          bytes = img.encodeJpg(image);
          break;
        case 'png':
        default:
          bytes = img.encodePng(image);
          break;
      }
      
      await file.writeAsBytes(bytes);
      return file;
    } catch (e) {
      print('Error saving image: $e');
      return null;
    }
  }
  
  /// Create a blank image with specified dimensions
  static img.Image createBlankImage(int width, int height, {img.Color? color}) {
    final image = img.Image(width: width, height: height);
    
    if (color != null) {
      // Fill with the specified color
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          image.setPixel(x, y, color);
        }
      }
    }
    
    return image;
  }
  
  /// Resize an image to specified dimensions
  static img.Image resizeImage(img.Image image, {int? width, int? height, bool maintainAspectRatio = true}) {
    if (width == null && height == null) {
      return image; // No resize needed
    }
    
    int targetWidth = width ?? image.width;
    int targetHeight = height ?? image.height;
    
    if (maintainAspectRatio) {
      final aspectRatio = image.width / image.height;
      
      if (width != null && height == null) {
        targetHeight = (width / aspectRatio).round();
      } else if (width == null && height != null) {
        targetWidth = (height * aspectRatio).round();
      } else {
        // Both width and height provided, use the more constraining one
        final widthRatio = width! / image.width;
        final heightRatio = height! / image.height;
        
        if (widthRatio < heightRatio) {
          targetHeight = (width / aspectRatio).round();
        } else {
          targetWidth = (height * aspectRatio).round();
        }
      }
    }
    
    return img.copyResize(
      image,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average
    );
  }
  
  /// Crop an image to specified rectangle
  static img.Image cropImage(img.Image image, int x, int y, int width, int height) {
    // Ensure dimensions are within bounds
    x = x.clamp(0, image.width - 1);
    y = y.clamp(0, image.height - 1);
    width = width.clamp(1, image.width - x);
    height = height.clamp(1, image.height - y);
    
    return img.copyCrop(image, x: x, y: y, width: width, height: height);
  }
  
  /// Copy one image into another at a specific position
  static void copyInto(img.Image target, img.Image source, {int x = 0, int y = 0}) {
    for (int sy = 0; sy < source.height; sy++) {
      for (int sx = 0; sx < source.width; sx++) {
        final dx = x + sx;
        final dy = y + sy;
        
        if (dx >= 0 && dx < target.width && dy >= 0 && dy < target.height) {
          target.setPixel(dx, dy, source.getPixel(sx, sy));
        }
      }
    }
  }
  
  /// Check if a point is within the bounds of an image
  static bool isPointInBounds(img.Image image, int x, int y) {
    return x >= 0 && x < image.width && y >= 0 && y < image.height;
  }
  
  /// Convert the image format
  static img.Image convertFormat(img.Image image, int format) {
    return img.Image.from(image)..format = format;
  }
  
  /// Get image dimensions as a Map
  static Map<String, int> getImageDimensions(img.Image image) {
    return {
      'width': image.width,
      'height': image.height,
    };
  }
  
  /// Get image format as string
  static String getFormatName(img.Image image) {
    switch (image.format) {
      case img.Format.uint1:
        return 'Uint1';
      case img.Format.uint2:
        return 'Uint2';
      case img.Format.uint4:
        return 'Uint4';
      case img.Format.uint8:
        return 'Uint8';
      case img.Format.uint16:
        return 'Uint16';
      case img.Format.uint32:
        return 'Uint32';
      case img.Format.int8:
        return 'Int8';
      case img.Format.int16:
        return 'Int16';
      case img.Format.int32:
        return 'Int32';
      case img.Format.float16:
        return 'Float16';
      case img.Format.float32:
        return 'Float32';
      case img.Format.float64:
        return 'Float64';
      default:
        return 'Unknown';
    }
  }
}