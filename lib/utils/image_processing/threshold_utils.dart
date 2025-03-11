import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../services/gcode/machine_coordinates.dart';
import 'base_image_utils.dart';

/// Utilities for image thresholding operations
class ThresholdUtils {
  /// Apply binary thresholding to create a black and white image
  static img.Image applyThreshold(img.Image image, int threshold) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = pixel.r.toInt();
        
        if (intensity > threshold) {
          // White
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        } else {
          // Black
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        }
      }
    }
    
    return result;
  }

  /// Apply adaptive thresholding for better results in varying lighting conditions
  static img.Image applyAdaptiveThreshold(img.Image image, int blockSize, int constant) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    final halfBlock = blockSize ~/ 2;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        // Calculate local mean
        int sum = 0;
        int count = 0;
        
        for (int j = math.max(0, y - halfBlock); j <= math.min(grayscale.height - 1, y + halfBlock); j++) {
          for (int i = math.max(0, x - halfBlock); i <= math.min(grayscale.width - 1, x + halfBlock); i++) {
            final pixel = grayscale.getPixel(i, j);
            sum += pixel.r.toInt();
            count++;
          }
        }
        
        final mean = count > 0 ? sum / count : 128;
        final pixelValue = grayscale.getPixel(x, y).r.toInt();
        
        // Apply threshold: if pixel is darker than local mean - constant, mark as foreground (black)
        if (pixelValue < mean - constant) {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        } else {
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        }
      }
    }
    
    return result;
  }

  /// Automatically find the optimal threshold using Otsu's method
  static int findOptimalThreshold(img.Image image) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    
    // Create histogram
    final histogram = List<int>.filled(256, 0);
    
    // Count pixel intensities
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = pixel.r.toInt();
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
  }

  /// Apply adaptive thresholding with automatic parameter selection
  static img.Image autoAdaptiveThreshold(img.Image image) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    
    // Analyze image to determine parameters
    final globalThreshold = findOptimalThreshold(grayscale);
    
    // Determine blockSize based on image dimensions
    final dimension = math.min(grayscale.width, grayscale.height);
    int blockSize = (dimension / 30).round() * 2 + 1; // Ensure odd number
    if (blockSize < 3) blockSize = 3;
    if (blockSize > 51) blockSize = 51;
    
    // Determine constant based on global threshold
    int constant = (globalThreshold * 0.1).round();
    if (constant < 2) constant = 2;
    
    return applyAdaptiveThreshold(grayscale, blockSize, constant);
  }

  /// Apply binary thresholding with inversion option
  static img.Image applyBinaryThreshold(img.Image image, int threshold, {bool invert = false}) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = pixel.r.toInt();
        bool isWhite = intensity > threshold;
        
        // Apply inversion if requested
        if (invert) isWhite = !isWhite;
        
        if (isWhite) {
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
        } else {
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        }
      }
    }
    
    return result;
  }

  /// Apply dithering using the Floyd-Steinberg algorithm
  static img.Image applyDithering(img.Image image, int threshold) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Make a copy of the grayscale image to manipulate
    final buffer = img.Image(width: grayscale.width, height: grayscale.height);
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        buffer.setPixel(x, y, grayscale.getPixel(x, y));
      }
    }
    
    // Apply Floyd-Steinberg dithering
    for (int y = 0; y < buffer.height; y++) {
      for (int x = 0; x < buffer.width; x++) {
        final oldPixel = buffer.getPixel(x, y);
        final oldValue = oldPixel.r.toInt();
        
        // Apply threshold
        final newValue = oldValue > threshold ? 255 : 0;
        result.setPixel(x, y, img.ColorRgba8(newValue, newValue, newValue, 255));
        
        // Calculate error
        final error = oldValue - newValue;
        
        // Distribute error to neighboring pixels
        if (x + 1 < buffer.width) {
          final right = buffer.getPixel(x + 1, y);
          final rightValue = (right.r.toInt() + (error * 7 / 16).round()).clamp(0, 255);
          buffer.setPixel(x + 1, y, img.ColorRgba8(rightValue, rightValue, rightValue, 255));
        }
        
        if (y + 1 < buffer.height) {
          if (x > 0) {
            final bottomLeft = buffer.getPixel(x - 1, y + 1);
            final bottomLeftValue = (bottomLeft.r.toInt() + (error * 3 / 16).round()).clamp(0, 255);
            buffer.setPixel(x - 1, y + 1, img.ColorRgba8(bottomLeftValue, bottomLeftValue, bottomLeftValue, 255));
          }
          
          final bottom = buffer.getPixel(x, y + 1);
          final bottomValue = (bottom.r.toInt() + (error * 5 / 16).round()).clamp(0, 255);
          buffer.setPixel(x, y + 1, img.ColorRgba8(bottomValue, bottomValue, bottomValue, 255));
          
          if (x + 1 < buffer.width) {
            final bottomRight = buffer.getPixel(x + 1, y + 1);
            final bottomRightValue = (bottomRight.r.toInt() + (error * 1 / 16).round()).clamp(0, 255);
            buffer.setPixel(x + 1, y + 1, img.ColorRgba8(bottomRightValue, bottomRightValue, bottomRightValue, 255));
          }
        }
      }
    }
    
    return result;
  }

  /// Apply multi-level thresholding (for multiple intensity levels)
  static img.Image applyMultiLevelThreshold(img.Image image, List<int> thresholds) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Sort thresholds to ensure correct ordering
    thresholds.sort();
    
    // Create levels based on thresholds
    final levels = thresholds.length + 1;
    final values = List<int>.filled(levels, 0);
    
    // Calculate level values (evenly distributed)
    for (int i = 0; i < levels; i++) {
      values[i] = (i * 255 / (levels - 1)).round();
    }
    
    // Apply multi-level thresholding
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = pixel.r.toInt();
        
        // Find the appropriate level
        int level = 0;
        for (int i = 0; i < thresholds.length; i++) {
          if (intensity > thresholds[i]) {
            level = i + 1;
          } else {
            break;
          }
        }
        
        final value = values[level];
        result.setPixel(x, y, img.ColorRgba8(value, value, value, 255));
      }
    }
    
    return result;
  }

  /// Apply a method to automatically determine multiple thresholds
  static List<int> findMultiLevelThresholds(img.Image image, int levels) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    
    // Create histogram
    final histogram = List<int>.filled(256, 0);
    
    // Count pixel intensities
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = pixel.r.toInt();
        histogram[intensity]++;
      }
    }
    
    // Simple approach: divide the histogram into equal parts
    // For a more sophisticated approach, clustering algorithms like K-means could be used
    
    // Total number of pixels
    final total = grayscale.width * grayscale.height;
    
    // Number of pixels per level
    final pixelsPerLevel = total / levels;
    
    // Find thresholds
    final thresholds = <int>[];
    int pixelCount = 0;
    
    for (int i = 0; i < 256; i++) {
      pixelCount += histogram[i];
      
      if (pixelCount > pixelsPerLevel * thresholds.length + pixelsPerLevel / 2 && thresholds.length < levels - 1) {
        thresholds.add(i);
        if (thresholds.length >= levels - 1) break;
      }
    }
    
    return thresholds;
  }

  /// Apply ISODATA thresholding algorithm
  static int findIsodataThreshold(img.Image image) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    
    // Create histogram
    final histogram = List<int>.filled(256, 0);
    
    // Count pixel intensities
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = pixel.r.toInt();
        histogram[intensity]++;
      }
    }
    
    // Start with the mean
    int sum = 0;
    int totalPixels = 0;
    
    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
      totalPixels += histogram[i];
    }
    
    int threshold = totalPixels > 0 ? sum ~/ totalPixels : 127;
    int oldThreshold;
    
    // Iterate until convergence
    do {
      oldThreshold = threshold;
      
      // Compute mean of background
      int sumBackground = 0;
      int countBackground = 0;
      
      for (int i = 0; i < threshold; i++) {
        sumBackground += i * histogram[i];
        countBackground += histogram[i];
      }
      
      // Compute mean of foreground
      int sumForeground = 0;
      int countForeground = 0;
      
      for (int i = threshold; i < 256; i++) {
        sumForeground += i * histogram[i];
        countForeground += histogram[i];
      }
      
      // Compute new threshold
      double meanBackground = countBackground > 0 ? sumBackground / countBackground : 0;
      double meanForeground = countForeground > 0 ? sumForeground / countForeground : 255;
      
      // New threshold is the average of the two means
      threshold = ((meanBackground + meanForeground) / 2).round();
    } while (threshold != oldThreshold);
    
    return threshold;
  }

  /// Apply Niblack's local thresholding algorithm
  static img.Image applyNiblackThreshold(img.Image image, int windowSize, double k) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    final halfWindow = windowSize ~/ 2;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        // Calculate local mean and standard deviation
        double sum = 0;
        double sumSquares = 0;
        int count = 0;
        
        for (int j = math.max(0, y - halfWindow); j <= math.min(grayscale.height - 1, y + halfWindow); j++) {
          for (int i = math.max(0, x - halfWindow); i <= math.min(grayscale.width - 1, x + halfWindow); i++) {
            final intensity = grayscale.getPixel(i, j).r.toInt();
            sum += intensity;
            sumSquares += intensity * intensity;
            count++;
          }
        }
        
        if (count > 0) {
          final mean = sum / count;
          final variance = (sumSquares / count) - (mean * mean);
          final stdDev = math.sqrt(variance);
          
          // Niblack's formula: threshold = mean + k * stdDev
          final threshold = (mean + k * stdDev).round().clamp(0, 255);
          
          final pixelValue = grayscale.getPixel(x, y).r.toInt();
          
          if (pixelValue < threshold) {
            result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255)); // Black
          } else {
            result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // White
          }
        } else {
          // Fallback if window is empty
          result.setPixel(x, y, grayscale.getPixel(x, y));
        }
      }
    }
    
    return result;
  }

  /// Apply Sauvola's local thresholding algorithm
  static img.Image applySauvolaThreshold(img.Image image, int windowSize, double k, int dynamicRange) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    final halfWindow = windowSize ~/ 2;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        // Calculate local mean and standard deviation
        double sum = 0;
        double sumSquares = 0;
        int count = 0;
        
        for (int j = math.max(0, y - halfWindow); j <= math.min(grayscale.height - 1, y + halfWindow); j++) {
          for (int i = math.max(0, x - halfWindow); i <= math.min(grayscale.width - 1, x + halfWindow); i++) {
            final intensity = grayscale.getPixel(i, j).r.toInt();
            sum += intensity;
            sumSquares += intensity * intensity;
            count++;
          }
        }
        
        if (count > 0) {
          final mean = sum / count;
          final variance = (sumSquares / count) - (mean * mean);
          final stdDev = math.sqrt(variance);
          
          // Sauvola's formula: threshold = mean * (1 + k * ((stdDev / dynamicRange) - 1))
          final threshold = (mean * (1 + k * ((stdDev / dynamicRange) - 1))).round().clamp(0, 255);
          
          final pixelValue = grayscale.getPixel(x, y).r.toInt();
          
          if (pixelValue < threshold) {
            result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255)); // Black
          } else {
            result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // White
          }
        } else {
          // Fallback if window is empty
          result.setPixel(x, y, grayscale.getPixel(x, y));
        }
      }
    }
    
    return result;
  }

  /// Apply Bernsen's local thresholding algorithm
  static img.Image applyBernsenThreshold(img.Image image, int windowSize, int contrastThreshold) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    final halfWindow = windowSize ~/ 2;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        // Find min and max in the window
        int minValue = 255;
        int maxValue = 0;
        
        for (int j = math.max(0, y - halfWindow); j <= math.min(grayscale.height - 1, y + halfWindow); j++) {
          for (int i = math.max(0, x - halfWindow); i <= math.min(grayscale.width - 1, x + halfWindow); i++) {
            final intensity = grayscale.getPixel(i, j).r.toInt();
            if (intensity < minValue) minValue = intensity;
            if (intensity > maxValue) maxValue = intensity;
          }
        }
        
        // Calculate local contrast
        final contrast = maxValue - minValue;
        
        final pixelValue = grayscale.getPixel(x, y).r.toInt();
        
        // Apply Bernsen's method
        if (contrast < contrastThreshold) {
          // Low contrast region, set to background
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // White
        } else {
          // Use local threshold (midpoint)
          final threshold = (minValue + maxValue) ~/ 2;
          
          if (pixelValue < threshold) {
            result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255)); // Black
          } else {
            result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // White
          }
        }
      }
    }
    
    return result;
  }

  /// Hysteresis thresholding (commonly used in Canny edge detection)
  static img.Image applyHysteresisThreshold(img.Image image, int lowThreshold, int highThreshold) {
    final grayscale = BaseImageUtils.convertToGrayscale(image);
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Initialize with zeros (black)
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
      }
    }
    
    // First pass: identify strong edges
    final strongEdges = <Point>[];
    final weakEdges = <Point>[];
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final intensity = grayscale.getPixel(x, y).r.toInt();
        
        if (intensity >= highThreshold) {
          strongEdges.add(Point(x.toDouble(), y.toDouble()));
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255)); // Strong edge (white)
        } else if (intensity >= lowThreshold) {
          weakEdges.add(Point(x.toDouble(), y.toDouble()));
        }
      }
    }
    
    // Second pass: trace weak edges connected to strong edges
    bool changed;
    do {
      changed = false;
      final newStrongEdges = <Point>[];
      
      for (final weakEdge in weakEdges) {
        // Convert to integer coordinates
        final x = weakEdge.x.round();
        final y = weakEdge.y.round();
        
        // Skip if already marked as strong
        if (result.getPixel(x, y).r.toInt() > 0) continue;
        
        // Check 8-connected neighbors
        bool connectedToStrong = false;
        for (int j = -1; j <= 1; j++) {
          for (int i = -1; i <= 1; i++) {
            if (i == 0 && j == 0) continue; // Skip center
            
            final nx = x + i;
            final ny = y + j;
            
            if (nx >= 0 && nx < grayscale.width && ny >= 0 && ny < grayscale.height) {
              if (result.getPixel(nx, ny).r.toInt() > 0) {
                connectedToStrong = true;
                break;
              }
            }
          }
          if (connectedToStrong) break;
        }
        
        if (connectedToStrong) {
          // Mark this weak edge as strong
          result.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
          newStrongEdges.add(weakEdge);
          changed = true;
        }
      }
      
      // Remove newly promoted edges from weak edges list
      for (final point in newStrongEdges) {
        weakEdges.remove(point);
      }
    } while (changed);
    
    return result;
  }
}