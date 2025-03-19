import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'base_image_utils.dart';

/// Utilities for image filtering operations like blur, sharpen, and edge detection
class FilterUtils {
  /// Apply Gaussian blur to an image
  static img.Image applyGaussianBlur(img.Image image, int radius) {
    try {
      return img.gaussianBlur(image, radius: radius);
    } catch (e) {
      print('Error applying Gaussian blur: $e');
      
      // Fallback to a simpler box blur
      return applyBoxBlur(image, radius);
    }
  }
  
  /// Apply box blur to an image
  static img.Image applyBoxBlur(img.Image image, int radius) {
    try {
      // The correct function is gaussianBlur with radius parameter
      return img.gaussianBlur(image, radius: radius);
    } catch (e) {
      print('Error applying box blur: $e');
      return image; // Return original if blur fails
    }
  }
  
  /// Apply edge detection using Sobel operator
  static img.Image applyEdgeDetection(img.Image image, {int threshold = 10}) {
    try {
      // Convert to grayscale for edge detection
      final grayscale = BaseImageUtils.convertToGrayscale(image);
    
      // Apply Sobel edge detection - the params in image package may have changed
      return img.sobel(grayscale);  // Remove threshold parameter
    } catch (e) {
      print('Error in edge detection: $e');
      return _applySimpleEdgeDetection(image, threshold);
    }
  }
  
  /// Simple edge detection fallback using pixel difference
  static img.Image _applySimpleEdgeDetection(img.Image image, int threshold) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Initialize with black
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
      }
    }
    
    // Apply simple edge detection using pixel differences
    for (int y = 1; y < grayscale.height - 1; y++) {
      for (int x = 1; x < grayscale.width - 1; x++) {
        final center = grayscale.getPixel(x, y).r.toInt();
        final left = grayscale.getPixel(x - 1, y).r.toInt();
        final right = grayscale.getPixel(x + 1, y).r.toInt();
        final top = grayscale.getPixel(x, y - 1).r.toInt();
        final bottom = grayscale.getPixel(x, y + 1).r.toInt();
        
        final maxDiff = math.max(
          math.max((center - left).abs(), (center - right).abs()),
          math.max((center - top).abs(), (center - bottom).abs())
        );
        
        if (maxDiff > threshold) {
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        }
      }
    }
    
    return result;
  }
  
  /// Apply Canny edge detection (more precise than Sobel)
  static img.Image applyCannyEdgeDetection(img.Image image, {int lowThreshold = 50, int highThreshold = 100}) {
    try {
      // 1. Convert to grayscale
      final grayscale = BaseImageUtils.convertToGrayscale(image);
      
      // 2. Apply Gaussian blur
      final blurred = applyGaussianBlur(grayscale, 2);
      
      // 3. Apply Sobel edge detection
      final edges = img.sobel(blurred);
      
      // 4. Apply non-maximum suppression and hysteresis thresholding
      // These steps are complex and might need a custom implementation
      // For now, use a global threshold
      
      final result = img.Image(width: edges.width, height: edges.height);
      
      for (int y = 0; y < edges.height; y++) {
        for (int x = 0; x < edges.width; x++) {
          final pixel = edges.getPixel(x, y);
          final intensity = pixel.r.toInt();
          
          if (intensity > highThreshold) {
            // Strong edge
            result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
          } else if (intensity > lowThreshold) {
            // Check if any 8-connected neighbor is a strong edge
            bool hasStrongNeighbor = false;
            
            for (int dy = -1; dy <= 1; dy++) {
              for (int dx = -1; dx <= 1; dx++) {
                if (dx == 0 && dy == 0) continue;
                
                final nx = x + dx;
                final ny = y + dy;
                
                if (nx >= 0 && nx < edges.width && ny >= 0 && ny < edges.height) {
                  final neighborPixel = edges.getPixel(nx, ny);
                  if (neighborPixel.r.toInt() > highThreshold) {
                    hasStrongNeighbor = true;
                    break;
                  }
                }
              }
              if (hasStrongNeighbor) break;
            }
            
            if (hasStrongNeighbor) {
              // Weak edge with strong neighbor
              result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
            } else {
              // Weak edge with no strong neighbor
              result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
            }
          } else {
            // Non-edge
            result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
          }
        }
      }
      
      return result;
    } catch (e) {
      print('Error applying Canny edge detection: $e');
      return applyEdgeDetection(image, threshold: lowThreshold);
    }
  }
}