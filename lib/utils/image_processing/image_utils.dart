import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:io';

import '../general/machine_coordinates.dart';

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

  /// Apply Gaussian smoothing to contour points
  static List<Point> applyGaussianSmoothing(List<Point> contour, int windowSize, [double sigma = 1.0]) {
    if (contour.length <= windowSize) return contour;
    
    final result = <Point>[];
    final halfWindow = windowSize ~/ 2;
    
    // Generate Gaussian kernel
    final kernel = List<double>.filled(windowSize, 0);
    final halfSize = windowSize ~/ 2;
    
    double sum = 0;
    for (int i = 0; i < windowSize; i++) {
      final x = i - halfSize;
      kernel[i] = math.exp(-(x * x) / (2 * sigma * sigma));
      sum += kernel[i];
    }
    
    // Normalize kernel
    for (int i = 0; i < windowSize; i++) {
      kernel[i] /= sum;
    }
    
    // Apply smoothing
    for (int i = 0; i < contour.length; i++) {
      double sumX = 0;
      double sumY = 0;
      double sumWeight = 0;
      
      for (int j = -halfWindow; j <= halfWindow; j++) {
        final idx = (i + j + contour.length) % contour.length;
        final weight = kernel[j + halfWindow];
        
        sumX += contour[idx].x * weight;
        sumY += contour[idx].y * weight;
        sumWeight += weight;
      }
      
      if (sumWeight > 0) {
        result.add(Point(sumX / sumWeight, sumY / sumWeight));
      } else {
        result.add(contour[i]);
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
  
  /// Apply a blur filter to the image
  static img.Image applyBlur(img.Image image, int radius) {
    try {
      return img.gaussianBlur(image, radius: radius);
    } catch (e) {
      print('Error applying blur: $e');
      return image; // Return original if blur fails
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
  
  /// Apply Canny edge detection for better edge detection
  static img.Image applyCannyEdgeDetection(img.Image grayscale, 
      {double lowThreshold = 50, double highThreshold = 150}) {
    try {
      // 1. Apply Gaussian blur to reduce noise
      final blurred = applyBlur(grayscale, 2);
      
      // 2. Compute gradients using Sobel operator
      final gradientX = _applySobelX(blurred);
      final gradientY = _applySobelY(blurred);
      
      // 3. Compute gradient magnitude and direction
      final width = grayscale.width;
      final height = grayscale.height;
      final magnitude = img.Image(width: width, height: height);
      final direction = List<List<double>>.generate(
        height, (_) => List<double>.filled(width, 0.0));
      
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final pixelX = gradientX.getPixel(x, y);
          final pixelY = gradientY.getPixel(x, y);
          
          final gx = calculateLuminance(
            pixelX.r.toInt(), pixelX.g.toInt(), pixelX.b.toInt()
          ) - 128;
          
          final gy = calculateLuminance(
            pixelY.r.toInt(), pixelY.g.toInt(), pixelY.b.toInt()
          ) - 128;
          
          final mag = math.sqrt(gx * gx + gy * gy).round().clamp(0, 255);
          magnitude.setPixel(x, y, img.ColorRgba8(mag, mag, mag, 255));
          
          // Calculate gradient direction in radians
          direction[y][x] = math.atan2(gy, gx);
        }
      }
      
      // 4. Non-maximum suppression
      final suppressed = img.Image(width: width, height: height);
      
      for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
          final pixel = magnitude.getPixel(x, y);
          final mag = calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          
          // Quantize direction to 8 possible orientations
          final angle = ((direction[y][x] * 8 / math.pi) + 8) % 8;
          
          int q = 0, r = 0;
          
          if ((0 <= angle && angle < 1) || (7 <= angle && angle < 8)) {
            q = x + 1; r = x - 1;
          } else if (1 <= angle && angle < 3) {
            q = x + 1; r = x - 1;
            q += (angle > 2) ? 1 : 0;
            r -= (angle < 2) ? 1 : 0;
          } else if (3 <= angle && angle < 5) {
            q = x; r = x;
            q += (angle > 4) ? 1 : -1;
            r -= (angle < 4) ? 1 : -1;
          } else { // 5 <= angle < 7
            q = x - 1; r = x + 1;
            q += (angle > 6) ? 1 : 0;
            r -= (angle < 6) ? 1 : 0;
          }
          
          final pixelQ = magnitude.getPixel(math.min(width - 1, math.max(0, q)), y);
          final pixelR = magnitude.getPixel(math.min(width - 1, math.max(0, r)), y);
          
          final magQ = calculateLuminance(
            pixelQ.r.toInt(), pixelQ.g.toInt(), pixelQ.b.toInt()
          );
          
          final magR = calculateLuminance(
            pixelR.r.toInt(), pixelR.g.toInt(), pixelR.b.toInt()
          );
          
          if (mag >= magQ && mag >= magR) {
            suppressed.setPixel(x, y, img.ColorRgba8(mag, mag, mag, 255));
          } else {
            suppressed.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
          }
        }
      }
      
      // 5. Hysteresis thresholding
      final result = img.Image(width: width, height: height);
      
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        }
      }
      
      // Find strong edges (above high threshold)
      for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
          final pixel = suppressed.getPixel(x, y);
          final mag = calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          );
          
          if (mag >= highThreshold) {
            result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
            _hysteresisRecursive(suppressed, result, x, y, lowThreshold, width, height);
          }
        }
      }
      
      return result;
    } catch (e) {
      print('Error applying Canny edge detection: $e');
      return grayscale; // Return original if Canny fails
    }
  }
  
  /// Helper for Canny edge detection - recursive hysteresis
  static void _hysteresisRecursive(img.Image suppressed, img.Image result, 
      int x, int y, double lowThreshold, int width, int height, {int depth = 0}) {
    
    // Prevent stack overflow with excessive recursion
    if (depth >= 1000) return;
    
    // Check 8-connected neighbors
    for (int i = -1; i <= 1; i++) {
      for (int j = -1; j <= 1; j++) {
        if (i == 0 && j == 0) continue;
        
        final nx = x + i;
        final ny = y + j;
        
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
          continue;
        }
        
        final pixel = suppressed.getPixel(nx, ny);
        final resultPixel = result.getPixel(nx, ny);
        
        final mag = calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        final resultMag = calculateLuminance(
          resultPixel.r.toInt(), resultPixel.g.toInt(), resultPixel.b.toInt()
        );
        
        if (mag >= lowThreshold && resultMag == 0) {
          result.setPixel(nx, ny, img.ColorRgba8(255, 255, 255, 255));
          _hysteresisRecursive(suppressed, result, nx, ny, lowThreshold, width, height, depth: depth + 1);
        }
      }
    }
  }
  
  /// Helper function for Sobel X gradient
  static img.Image _applySobelX(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);
    final width = image.width;
    final height = image.height;
    
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        // Sobel X kernel: [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]]
        int sum = 0;
        
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            final pixel = image.getPixel(x + i, y + j);
            final intensity = calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            );
            
            int weight = 0;
            if (i == -1) weight = (j == 0) ? -2 : -1;
            else if (i == 1) weight = (j == 0) ? 2 : 1;
            
            sum += intensity * weight;
          }
        }
        
        // Normalize to 0-255 range (add 128 for middle gray)
        final normalizedValue = math.min(255, math.max(0, 128 + sum ~/ 8));
        result.setPixel(x, y, img.ColorRgba8(normalizedValue, normalizedValue, normalizedValue, 255));
      }
    }
    
    return result;
  }
  
  /// Helper function for Sobel Y gradient
  static img.Image _applySobelY(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);
    final width = image.width;
    final height = image.height;
    
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        // Sobel Y kernel: [[-1, -2, -1], [0, 0, 0], [1, 2, 1]]
        int sum = 0;
        
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            final pixel = image.getPixel(x + i, y + j);
            final intensity = calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            );
            
            int weight = 0;
            if (j == -1) weight = (i == 0) ? -2 : -1;
            else if (j == 1) weight = (i == 0) ? 2 : 1;
            
            sum += intensity * weight;
          }
        }
        
        // Normalize to 0-255 range (add 128 for middle gray)
        final normalizedValue = math.min(255, math.max(0, 128 + sum ~/ 8));
        result.setPixel(x, y, img.ColorRgba8(normalizedValue, normalizedValue, normalizedValue, 255));
      }
    }
    
    return result;
  }
  
  /// Find connected components (blobs) in a binary image
  static List<List<int>> findConnectedComponents(img.Image binaryImage, 
      {int minSize = 20, int maxSize = 1000, int maxRecursionDepth = 1000}) {
    
    final width = binaryImage.width;
    final height = binaryImage.height;
    final List<List<int>> blobs = [];
    
    try {
      final visited = List.generate(
        height, 
        (_) => List.filled(width, false)
      );
      
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          if (visited[y][x]) continue;
          
          final pixel = binaryImage.getPixel(x, y);
          final isBlack = calculateLuminance(
            pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
          ) < 128;
          
          if (isBlack) {
            final List<int> blob = [];
            _floodFill(binaryImage, x, y, visited, blob, maxRecursionDepth);
            
            // Check if blob is within size constraints
            if (blob.length >= minSize * 2 && blob.length <= maxSize * 2) {
              blobs.add(blob);
            }
          } else {
            visited[y][x] = true;
          }
        }
      }
    } catch (e) {
      print('Error finding connected components: $e');
    }
    
    return blobs;
  }
  
  /// Flood fill helper for connected components
  static void _floodFill(img.Image binaryImage, int x, int y, List<List<bool>> visited, 
      List<int> blob, int maxDepth, {int depth = 0}) {
    
    // Prevent stack overflow with excessive recursion
    if (depth >= maxDepth) return;
    
    if (x < 0 || y < 0 || x >= binaryImage.width || y >= binaryImage.height || visited[y][x]) {
      return;
    }
    
    try {
      final pixel = binaryImage.getPixel(x, y);
      final isBlack = calculateLuminance(
        pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
      ) < 128;
      
      if (!isBlack) {
        visited[y][x] = true;
        return;
      }
    } catch (e) {
      visited[y][x] = true;
      return;
    }
    
    visited[y][x] = true;
    blob.add(x);
    blob.add(y);
    
    // Check 4-connected neighbors (instead of 8 to prevent stack overflow)
    _floodFill(binaryImage, x + 1, y, visited, blob, maxDepth, depth: depth + 1);
    _floodFill(binaryImage, x - 1, y, visited, blob, maxDepth, depth: depth + 1);
    _floodFill(binaryImage, x, y + 1, visited, blob, maxDepth, depth: depth + 1);
    _floodFill(binaryImage, x, y - 1, visited, blob, maxDepth, depth: depth + 1);
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
  
  /// Draw a contour (series of connected points)
  static void drawContour(img.Image image, List<Point> contour, img.Color color) {
    if (contour.isEmpty) return;
    
    try {
      for (int i = 0; i < contour.length - 1; i++) {
        final p1 = contour[i];
        final p2 = contour[i + 1];
        
        drawLine(
          image, 
          p1.x.round(), p1.y.round(), 
          p2.x.round(), p2.y.round(), 
          color
        );
      }
      
      // Close the contour if not already closed
      final first = contour.first;
      final last = contour.last;
      if (first.x != last.x || first.y != last.y) {
        drawLine(
          image,
          last.x.round(), last.y.round(),
          first.x.round(), first.y.round(),
          color
        );
      }
    } catch (e) {
      print('Error drawing contour: $e');
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
  
  /// Get grayscale color with the specified intensity
  static img.Color getGrayscaleColor(int intensity) {
    final value = intensity.clamp(0, 255);
    return img.ColorRgba8(value, value, value, 255);
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
  
  /// Save an image to a file
  static Future<File> saveImageToFile(img.Image image, String filePath, {String format = 'png'}) async {
    try {
      final file = File(filePath);
      List<int> bytes;
      
      // Encode based on format
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
      rethrow;
    }
  }
  
  /// Load an image from a file
  static Future<img.Image?> loadImageFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('File does not exist: $filePath');
        return null;
      }
      
      final bytes = await file.readAsBytes();
      return decodeImage(bytes);
    } catch (e) {
      print('Error loading image: $e');
      return null;
    }
  }
  
  /// Decode image bytes to an img.Image
  static img.Image? decodeImage(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (e) {
      print('Error decoding image: $e');
      return null;
    }
  }
  
  /// Create a blank image with the specified dimensions
  static img.Image createBlankImage(int width, int height, {img.Color? color}) {
    final image = img.Image(width: width, height: height);
    
    if (color != null) {
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          image.setPixel(x, y, color);
        }
      }
    }
    
    return image;
  }
  
}