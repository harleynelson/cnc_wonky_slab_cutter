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

  /// Calculate luminance (brightness) from RGB values
  static int calculateLuminance(int r, int g, int b) {
    return (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
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
  // TODO: had 2 applyEdgeDetection's, commenting out this one to see if it still works
  // /// Apply edge detection using Sobel operator
  // static img.Image applyEdgeDetection(img.Image image, {int threshold = 10}) {
  //   try {
  //     // Convert to grayscale for edge detection
  //     final grayscale = BaseImageUtils.convertToGrayscale(image);
    
  //     // Apply Sobel edge detection - the params in image package may have changed
  //     return img.sobel(grayscale);  // Remove threshold parameter
  //   } catch (e) {
  //     print('Error in edge detection: $e');
  //     return _applySimpleEdgeDetection(image, threshold);
  //   }
  // }
  
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