import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'base_image_utils.dart';

/// Utilities for image thresholding operations
class ThresholdUtils {

  /// Create a binary mask from an image using a threshold
static List<List<bool>> createBinaryMask(img.Image image, int threshold) {
  final mask = List.generate(
    image.height, 
    (_) => List<bool>.filled(image.width, false)
  );
  
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final intensity = BaseImageUtils.calculateLuminance(
        pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
      );
      
      mask[y][x] = intensity < threshold;
    }
  }
  
  return mask;
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
}