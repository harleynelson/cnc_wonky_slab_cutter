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
      return img.blur(image, radius);
    } catch (e) {
      print('Error applying box blur: $e');
      return image; // Return original if blur fails
    }
  }
  
  /// Apply median filter for noise reduction
  static img.Image applyMedianFilter(img.Image image, int radius) {
    final result = img.Image(width: image.width, height: image.height);
    
    // Apply a median filter with the specified radius
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        // For color images, process each channel separately
        final rValues = <int>[];
        final gValues = <int>[];
        final bValues = <int>[];
        
        // Gather pixel values in the neighborhood
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            
            if (nx >= 0 && nx < image.width && ny >= 0 && ny < image.height) {
              final pixel = image.getPixel(nx, ny);
              rValues.add(pixel.r.toInt());
              gValues.add(pixel.g.toInt());
              bValues.add(pixel.b.toInt());
            }
          }
        }
        
        // Sort values to find median
        rValues.sort();
        gValues.sort();
        bValues.sort();
        
        // Get median value
        final medianIndex = rValues.length ~/ 2;
        final medianR = rValues[medianIndex];
        final medianG = gValues[medianIndex];
        final medianB = bValues[medianIndex];
        
        // Preserve alpha channel from original pixel
        final alpha = image.getPixel(x, y).a.toInt();
        
        result.setPixel(x, y, img.ColorRgba8(medianR, medianG, medianB, alpha));
      }
    }
    
    return result;
  }
  
  /// Apply unsharp mask for sharpening
  static img.Image applySharpen(img.Image image, {int amount = 3}) {
    try {
      // Cap the amount to avoid excessive sharpening
      final safeAmount = amount.clamp(1, 5);
      
      // First create a blurred version
      final blurred = img.gaussianBlur(image, radius: safeAmount);
      
      // Apply unsharp mask formula: sharpened = original + amount * (original - blurred)
      final result = img.Image(width: image.width, height: image.height);
      
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final originalPixel = image.getPixel(x, y);
          final blurredPixel = blurred.getPixel(x, y);
          
          // Calculate each channel separately
          final newR = _applyUnsharpMask(originalPixel.r.toInt(), blurredPixel.r.toInt(), safeAmount);
          final newG = _applyUnsharpMask(originalPixel.g.toInt(), blurredPixel.g.toInt(), safeAmount);
          final newB = _applyUnsharpMask(originalPixel.b.toInt(), blurredPixel.b.toInt(), safeAmount);
          
          result.setPixel(x, y, img.ColorRgba8(newR, newG, newB, originalPixel.a.toInt()));
        }
      }
      
      return result;
    } catch (e) {
      print('Error applying sharpening: $e');
      return image; // Return original if sharpening fails
    }
  }
  
  /// Helper method for unsharp mask calculation
  static int _applyUnsharpMask(int original, int blurred, int amount) {
    return (original + amount * (original - blurred)).round().clamp(0, 255);
  }
  
  /// Apply edge detection using Sobel operator
  static img.Image applyEdgeDetection(img.Image image, {int threshold = 10}) {
    try {
      // Convert to grayscale for edge detection
      final grayscale = BaseImageUtils.convertToGrayscale(image);
      
      // Apply Sobel edge detection
      return img.sobel(grayscale, threshold: threshold);
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
  
  /// Apply emboss filter
  static img.Image applyEmbossFilter(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 1; y < image.height - 1; y++) {
      for (int x = 1; x < image.width - 1; x++) {
        final topLeft = image.getPixel(x - 1, y - 1);
        final bottomRight = image.getPixel(x + 1, y + 1);
        
        // Calculate emboss effect
        int r = (bottomRight.r.toInt() - topLeft.r.toInt() + 128).clamp(0, 255);
        int g = (bottomRight.g.toInt() - topLeft.g.toInt() + 128).clamp(0, 255);
        int b = (bottomRight.b.toInt() - topLeft.b.toInt() + 128).clamp(0, 255);
        
        result.setPixel(x, y, img.ColorRgba8(r, g, b, image.getPixel(x, y).a.toInt()));
      }
    }
    
    return result;
  }
  
  /// Apply a custom convolution filter
  static img.Image applyConvolution(img.Image image, List<List<double>> kernel) {
    final result = img.Image(width: image.width, height: image.height);
    
    // Calculate kernel dimensions
    final kernelHeight = kernel.length;
    final kernelWidth = kernel[0].length;
    final kernelCenterX = kernelWidth ~/ 2;
    final kernelCenterY = kernelHeight ~/ 2;
    
    // Calculate kernel sum for normalization
    double kernelSum = 0;
    for (int ky = 0; ky < kernelHeight; ky++) {
      for (int kx = 0; kx < kernelWidth; kx++) {
        kernelSum += kernel[ky][kx];
      }
    }
    
    // If kernel sum is zero, set it to 1 to avoid division by zero
    if (kernelSum.abs() < 0.00001) {
      kernelSum = 1;
    }
    
    // Apply convolution
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        double sumR = 0, sumG = 0, sumB = 0;
        
        // Apply kernel
        for (int ky = 0; ky < kernelHeight; ky++) {
          for (int kx = 0; kx < kernelWidth; kx++) {
            final sourceX = x + kx - kernelCenterX;
            final sourceY = y + ky - kernelCenterY;
            
            // Handle boundaries - use closest valid pixel (clamping)
            final validX = sourceX.clamp(0, image.width - 1);
            final validY = sourceY.clamp(0, image.height - 1);
            
            final pixel = image.getPixel(validX, validY);
            final kernelValue = kernel[ky][kx];
            
            sumR += pixel.r.toInt() * kernelValue;
            sumG += pixel.g.toInt() * kernelValue;
            sumB += pixel.b.toInt() * kernelValue;
          }
        }
        
        // Normalize and clamp results
        final r = (sumR / kernelSum).round().clamp(0, 255);
        final g = (sumG / kernelSum).round().clamp(0, 255);
        final b = (sumB / kernelSum).round().clamp(0, 255);
        
        result.setPixel(x, y, img.ColorRgba8(r, g, b, image.getPixel(x, y).a.toInt()));
      }
    }
    
    return result;
  }
  
  /// Detect lines using Hough transform
  static Map<String, dynamic> detectLines(img.Image image, {int threshold = 100}) {
    // First, apply edge detection
    final edges = applyEdgeDetection(image, threshold: threshold ~/ 2);
    
    // Convert to binary
    final binary = img.Image(width: edges.width, height: edges.height);
    for (int y = 0; y < edges.height; y++) {
      for (int x = 0; x < edges.width; x++) {
        final pixel = edges.getPixel(x, y);
        final isEdge = pixel.r.toInt() > threshold;
        binary.setPixel(x, y, isEdge ? 
          img.ColorRgba8(255, 255, 255, 255) : 
          img.ColorRgba8(0, 0, 0, 255)
        );
      }
    }
    
    // Parameters for Hough transform
    final width = binary.width;
    final height = binary.height;
    final maxRadius = math.sqrt(width * width + height * height).round();
    final thetaStep = math.pi / 180; // 1 degree increment
    
    // Create Hough space accumulator
    final accumulator = List.generate(
      180, // 180 degrees (0-179)
      (_) => List<int>.filled(maxRadius * 2, 0) // -maxRadius to +maxRadius
    );
    
    // Perform Hough transform
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixel = binary.getPixel(x, y);
        
        if (pixel.r.toInt() > 128) { // Edge pixel
          for (int thetaIndex = 0; thetaIndex < 180; thetaIndex++) {
            final theta = thetaIndex * thetaStep;
            final rho = (x * math.cos(theta) + y * math.sin(theta)).round();
            final rhoIndex = rho + maxRadius; // Offset to make indices non-negative
            
            if (rhoIndex >= 0 && rhoIndex < maxRadius * 2) {
              accumulator[thetaIndex][rhoIndex]++;
            }
          }
        }
      }
    }
    
    // Extract lines (rho, theta pairs) that exceed threshold
    final lines = <Map<String, dynamic>>[];
    
    for (int thetaIndex = 0; thetaIndex < 180; thetaIndex++) {
      for (int rhoIndex = 0; rhoIndex < maxRadius * 2; rhoIndex++) {
        if (accumulator[thetaIndex][rhoIndex] > threshold) {
          final theta = thetaIndex * thetaStep;
          final rho = rhoIndex - maxRadius;
          
          lines.add({
            'rho': rho,
            'theta': theta,
            'votes': accumulator[thetaIndex][rhoIndex],
          });
        }
      }
    }
    
    // Sort lines by votes (strongest first)
    lines.sort((a, b) => b['votes'].compareTo(a['votes']));
    
    // Create a visualization
    final visualization = img.copyResize(image, width: width, height: height);
    
    // Draw the detected lines
    for (final line in lines) {
      _drawHoughLine(visualization, line['rho'], line['theta'], maxRadius);
    }
    
    return {
      'lines': lines,
      'visualization': visualization,
    };
  }
  
  /// Draw a line detected by Hough transform
  static void _drawHoughLine(img.Image image, int rho, double theta, int maxRadius) {
    final a = math.cos(theta);
    final b = math.sin(theta);
    
    int x0, y0, x1, y1;
    
    if (b.abs() < 0.001) {
      // Vertical line
      x0 = rho;
      y0 = 0;
      x1 = rho;
      y1 = image.height - 1;
    } else if (a.abs() < 0.001) {
      // Horizontal line
      x0 = 0;
      y0 = rho;
      x1 = image.width - 1;
      y1 = rho;
    } else {
      // Angle line
      x0 = 0;
      y0 = (rho - x0 * a) ~/ b;
      x1 = image.width - 1;
      y1 = (rho - x1 * a) ~/ b;
    }
    
    // Ensure points are within image boundaries
    if (y0 < 0 || y0 >= image.height) {
      if (y0 < 0) {
        x0 = (rho - b * 0) ~/ a;
        y0 = 0;
      } else {
        x0 = (rho - b * (image.height - 1)) ~/ a;
        y0 = image.height - 1;
      }
    }
    
    if (y1 < 0 || y1 >= image.height) {
      if (y1 < 0) {
        x1 = (rho - b * 0) ~/ a;
        y1 = 0;
      } else {
        x1 = (rho - b * (image.height - 1)) ~/ a;
        y1 = image.height - 1;
      }
    }
    
    // Draw the line
    _drawLine(image, x0, y0, x1, y1, img.ColorRgba8(255, 0, 0, 255));
  }
  
  /// Draw a line between two points
  static void _drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
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