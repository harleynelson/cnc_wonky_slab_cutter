// lib/utils/image_processing/image_correction_utils.dart
// Utility functions for correcting image perspective based on markers

import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../general/machine_coordinates.dart';
import '../../services/detection/marker_detector.dart';
import 'image_utils.dart';

/// Utilities for image perspective correction
class ImageCorrectionUtils {
  /// Correct perspective distortion of an image based on marker positions
static Future<img.Image> correctPerspective(
  img.Image sourceImage,
  CoordinatePointXY originMarker,
  CoordinatePointXY xAxisMarker,
  CoordinatePointXY scaleMarker,
  double markerXDistance,
  double markerYDistance
) async {
  print('MARKER DEBUG: Origin (${originMarker.x.round()}, ${originMarker.y.round()})');
  print('MARKER DEBUG: X-Axis (${xAxisMarker.x.round()}, ${xAxisMarker.y.round()})');
  print('MARKER DEBUG: Y-Axis (${scaleMarker.x.round()}, ${scaleMarker.y.round()})');
  
  // Calculate the vectors between markers
  final double baseVectorX = xAxisMarker.x - originMarker.x;
  final double baseVectorY = xAxisMarker.y - originMarker.y;
  final double sideVectorX = scaleMarker.x - originMarker.x;
  final double sideVectorY = scaleMarker.y - originMarker.y;
  
  // Calculate lengths of sides
  final double baseLength = math.sqrt(baseVectorX * baseVectorX + baseVectorY * baseVectorY);
  final double sideLength = math.sqrt(sideVectorX * sideVectorX + sideVectorY * sideVectorY);
  
  // Calculate the top-right corner from our three markers
  final CoordinatePointXY topRightCorner = CoordinatePointXY(
    xAxisMarker.x + sideVectorX,
    xAxisMarker.y + sideVectorY
  );
  
  // Calculate lengths of the top edge
  final double topEdgeX = topRightCorner.x - scaleMarker.x;
  final double topEdgeY = topRightCorner.y - scaleMarker.y;
  final double topLength = math.sqrt(topEdgeX * topEdgeX + topEdgeY * topEdgeY);
  
  print('DEBUG: Base length: $baseLength, Side length: $sideLength, Top length: $topLength');
  
  // The extension factor for the bottom edge (making it wider)
  final double bottomExtensionFactor = 1.5; // Adjust as needed
  
  // Original corners of the quadrilateral in the source image
  final List<CoordinatePointXY> sourcePts = [
    originMarker,       // Bottom-left
    xAxisMarker,        // Bottom-right
    topRightCorner,     // Top-right
    scaleMarker,        // Top-left
  ];
  
  // Calculate the bottom edge midpoint
  final double bottomMidX = (originMarker.x + xAxisMarker.x) / 2;
  final double bottomMidY = (originMarker.y + xAxisMarker.y) / 2;
  
  // Calculate the extension amount for bottom edge
  final double extensionAmount = (baseLength * (bottomExtensionFactor - 1)) / 2;
  
  // Calculate destination points with BOTTOM edge extended
  final List<CoordinatePointXY> destPts = [
    CoordinatePointXY(                                          // Extended bottom-left
      originMarker.x - extensionAmount, 
      originMarker.y
    ),
    CoordinatePointXY(                                          // Extended bottom-right
      xAxisMarker.x + extensionAmount, 
      xAxisMarker.y
    ),
    topRightCorner,                                 // Top-right stays the same
    scaleMarker,                                    // Top-left stays the same
  ];
  
  print('SOURCE QUAD: ${sourcePts.map((p) => "(${p.x.round()},${p.y.round()})").join(", ")}');
  print('DEST QUAD: ${destPts.map((p) => "(${p.x.round()},${p.y.round()})").join(", ")}');
  
  // Create a destination image large enough to hold the wider bottom
  final int extraWidth = (extensionAmount * 2.2).toInt();
  final int outputWidth = sourceImage.width + extraWidth;
  final int outputHeight = sourceImage.height;
  
  // Create destination image
  final img.Image destImage = img.Image(width: outputWidth, height: outputHeight);
  
  // Fill with white background
  for (int y = 0; y < outputHeight; y++) {
    for (int x = 0; x < outputWidth; x++) {
      destImage.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
    }
  }
  
  // Apply perspective transformation
  final perspectiveMatrix = _calculatePerspectiveTransform(sourcePts, destPts);
  _applyPerspectiveTransform(sourceImage, destImage, perspectiveMatrix);
  
  // Draw calibration grid at the bottom part
  _drawCalibrationGrid(
    destImage,
    destPts[0].x.round(), // Extended bottom-left
    destPts[0].y.round() - sideLength.round(), // Go up by side length 
    (destPts[1].x - destPts[0].x).round(), // Width of extended bottom
    sideLength.round(), // Height equal to side length
    (baseLength / 10).round(), // Grid spacing
    img.ColorRgba8(0, 100, 255, 80)
  );
  
  return destImage;
}
  
  /// Create a debug image showing original and corrected images
static img.Image createDebugImage(
  img.Image originalImage,
  List<MarkerPoint> markers,
  img.Image correctedImage
) {
  // Create a composite debug image
  final debugWidth = originalImage.width;
  final debugHeight = originalImage.height * 2; // Space for both images
  
  final img.Image debugImage = img.Image(width: debugWidth, height: debugHeight);
  
  // Fill with black background
  for (int y = 0; y < debugHeight; y++) {
    for (int x = 0; x < debugWidth; x++) {
      debugImage.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
    }
  }
  
  // Copy original image to top half
  for (int y = 0; y < originalImage.height; y++) {
    if (y >= debugHeight) break; // Prevent overflow
    for (int x = 0; x < originalImage.width; x++) {
      if (x >= debugWidth) break; // Prevent overflow
      try {
        debugImage.setPixel(x, y, originalImage.getPixel(x, y));
      } catch (e) {
        // Skip this pixel if there's an error
        print('Error copying original pixel at ($x,$y): $e');
      }
    }
  }
  
  // Draw markers on original image
  for (final marker in markers) {
    try {
      final color = marker.role == MarkerRole.origin 
          ? img.ColorRgba8(255, 0, 0, 255)  // Red for origin
          : marker.role == MarkerRole.xAxis 
              ? img.ColorRgba8(0, 255, 0, 255)  // Green for X-axis
              : img.ColorRgba8(0, 0, 255, 255); // Blue for scale
              
      // Make sure marker coordinates are within bounds
      if (marker.x >= 0 && marker.x < debugWidth && 
          marker.y >= 0 && marker.y < originalImage.height) {
        ImageUtils.drawCircle(
          debugImage, 
          marker.x, 
          marker.y, 
          10, 
          color, 
          fill: true
        );
        
        ImageUtils.drawText(
          debugImage,
          marker.role.toString().split('.').last,
          marker.x + 15,
          marker.y,
          color
        );
      }
    } catch (e) {
      print('Error drawing marker: $e');
    }
  }
  
  // Add a separator line
  for (int x = 0; x < debugWidth; x++) {
    try {
      debugImage.setPixel(x, originalImage.height - 1, img.ColorRgba8(255, 0, 0, 255));
    } catch (e) {
      // Skip if out of bounds
    }
  }
  
  // Add "Original" and "Corrected" labels
  try {
    ImageUtils.drawText(
      debugImage,
      "Original Image with Markers",
      10,
      10,
      img.ColorRgba8(255, 255, 255, 255)
    );
    
    if (originalImage.height < debugHeight) {
      ImageUtils.drawText(
        debugImage,
        "Perspective Corrected (Cropped & Resized)",
        10,
        originalImage.height + 10,
        img.ColorRgba8(255, 255, 255, 255)
      );
    }
  } catch (e) {
    print('Error drawing labels: $e');
  }
  
  // Copy corrected image to bottom half - we don't need to resize
  // since we already made it match the original dimensions
  final bottomHalfStart = originalImage.height;
  if (bottomHalfStart < debugHeight) {
    for (int y = 0; y < correctedImage.height; y++) {
      final destY = y + bottomHalfStart;
      if (destY >= debugHeight) break; // Prevent overflow
      
      for (int x = 0; x < correctedImage.width; x++) {
        if (x >= debugWidth) break; // Prevent overflow
        try {
          debugImage.setPixel(x, destY, correctedImage.getPixel(x, y));
        } catch (e) {
          // Skip this pixel if there's an error
        }
      }
    }
    
    // Draw grid on corrected image to show calibration
    try {
      _drawCalibrationGrid(
        debugImage, 
        0, bottomHalfStart, 
        debugWidth, originalImage.height,
        50, // Grid spacing in pixels
        img.ColorRgba8(0, 255, 255, 100)
      );
    } catch (e) {
      print('Error drawing calibration grid: $e');
    }
  }
  
  return debugImage;
}

/// Crop the image to create a rectangle based on the narrowest width of the trapezoid
static img.Image _cropToRectangle(
  img.Image image, 
  List<CoordinatePointXY> destPts,
  CoordinatePointXY originPoint,
  CoordinatePointXY xAxisPoint
) {
  const int margin = 10;
  
  // Find narrowest width - typically this would be between top points (points 2 and 3)
  final double topWidth = (destPts[2].x - destPts[3].x).abs();
  final double bottomWidth = (destPts[1].x - destPts[0].x).abs();
  final double narrowestWidth = math.min(topWidth, bottomWidth);
  
  // Get the midpoint of the top edge and bottom edge
  final double topMidX = (destPts[2].x + destPts[3].x) / 2;
  final double bottomMidX = (destPts[0].x + destPts[1].x) / 2;
  
  // Calculate crop bounds centered on the midpoint of the narrowest edge
  double cropLeft, cropRight;
  if (topWidth < bottomWidth) {
    // Top is narrower, center the crop on the top midpoint
    cropLeft = topMidX - narrowestWidth / 2 - margin;
    cropRight = topMidX + narrowestWidth / 2 + margin;
  } else {
    // Bottom is narrower, center the crop on the bottom midpoint
    cropLeft = bottomMidX - narrowestWidth / 2 - margin;
    cropRight = bottomMidX + narrowestWidth / 2 + margin;
  }
  
  // Ensure crop bounds are within image
  final int safeLeft = math.max(0, cropLeft.round());
  final int safeRight = math.min(image.width - 1, cropRight.round());
  
  // Calculate crop dimensions
  final int cropWidth = safeRight - safeLeft + 1;
  final int cropHeight = image.height;
  
  // Create new image for cropped area
  final img.Image croppedImage = img.Image(width: cropWidth, height: cropHeight);
  
  // Copy pixels
  for (int y = 0; y < cropHeight; y++) {
    for (int x = 0; x < cropWidth; x++) {
      final srcX = safeLeft + x;
      final srcY = y;
      
      if (srcX >= 0 && srcX < image.width && srcY >= 0 && srcY < image.height) {
        croppedImage.setPixel(x, y, image.getPixel(srcX, srcY));
      } else {
        croppedImage.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
      }
    }
  }
  
  return croppedImage;
}
  
  /// Calculate perspective transform matrix
  static List<double> _calculatePerspectiveTransform(
    List<CoordinatePointXY> sourcePts, 
    List<CoordinatePointXY> destPts
  ) {
    // We need to solve for the 8 parameters of the perspective transform
    // [ a b c ]   [x]   [X]
    // [ d e f ] * [y] = [Y]
    // [ g h 1 ]   [1]   [W]
    // Where X = x' * W, Y = y' * W
    
    // This is a simplified implementation - in production, you'd use a more robust library
    
    final matrix = List<double>.filled(9, 0.0);
    
    // For simplicity, we'll use a simplified approach that doesn't handle all cases
    // but works for our scenario with rectangular markers
    
    // Calculate the matrix for the forward mapping
    _computeProjectiveMatrix(
      sourcePts[0].x, sourcePts[0].y, destPts[0].x, destPts[0].y,
      sourcePts[1].x, sourcePts[1].y, destPts[1].x, destPts[1].y,
      sourcePts[2].x, sourcePts[2].y, destPts[2].x, destPts[2].y,
      sourcePts[3].x, sourcePts[3].y, destPts[3].x, destPts[3].y,
      matrix
    );
    
    return matrix;
  }
  
  /// Compute the projective matrix for perspective transform
  static void _computeProjectiveMatrix(
  double x0, double y0, double X0, double Y0,
  double x1, double y1, double X1, double Y1,
  double x2, double y2, double X2, double Y2,
  double x3, double y3, double X3, double Y3,
  List<double> matrix
) {
  // Build the coefficient matrix
  final List<List<double>> coeffs = [
    [x0, y0, 1, 0, 0, 0, -X0*x0, -X0*y0],
    [0, 0, 0, x0, y0, 1, -Y0*x0, -Y0*y0],
    [x1, y1, 1, 0, 0, 0, -X1*x1, -X1*y1],
    [0, 0, 0, x1, y1, 1, -Y1*x1, -Y1*y1],
    [x2, y2, 1, 0, 0, 0, -X2*x2, -X2*y2],
    [0, 0, 0, x2, y2, 1, -Y2*x2, -Y2*y2],
    [x3, y3, 1, 0, 0, 0, -X3*x3, -X3*y3],
    [0, 0, 0, x3, y3, 1, -Y3*x3, -Y3*y3]
  ];
  
  // Build the right-hand side
  final List<double> rhs = [X0, Y0, X1, Y1, X2, Y2, X3, Y3];
  
  // Solve the system using Gaussian elimination
  _solveLinearSystem(coeffs, rhs, 8);
  
  // Extract the solution
  matrix[0] = rhs[0]; // a
  matrix[1] = rhs[1]; // b
  matrix[2] = rhs[2]; // c
  matrix[3] = rhs[3]; // d
  matrix[4] = rhs[4]; // e
  matrix[5] = rhs[5]; // f
  matrix[6] = rhs[6]; // g
  matrix[7] = rhs[7]; // h
  matrix[8] = 1.0;    // i = 1
}
  
  /// Solve a system of linear equations using Gaussian elimination
  static void _solveLinearSystem(List<List<double>> coeffs, List<double> rhs, int n) {
    // Perform Gaussian elimination
    for (int i = 0; i < n; i++) {
      // Find pivot
      double max = coeffs[i][i].abs();
      int maxRow = i;
      for (int j = i + 1; j < n; j++) {
        if (coeffs[j][i].abs() > max) {
          max = coeffs[j][i].abs();
          maxRow = j;
        }
      }
      
      // Swap rows if needed
      if (maxRow != i) {
        for (int j = i; j < n; j++) {
          final temp = coeffs[i][j];
          coeffs[i][j] = coeffs[maxRow][j];
          coeffs[maxRow][j] = temp;
        }
        final temp = rhs[i];
        rhs[i] = rhs[maxRow];
        rhs[maxRow] = temp;
      }
      
      // Eliminate below
      for (int j = i + 1; j < n; j++) {
        final factor = coeffs[j][i] / coeffs[i][i];
        rhs[j] -= factor * rhs[i];
        for (int k = i; k < n; k++) {
          coeffs[j][k] -= factor * coeffs[i][k];
        }
      }
    }
  
  // Back-substitution
  for (int i = n - 1; i >= 0; i--) {
    double sum = 0.0;
    for (int j = i + 1; j < n; j++) {
      sum += coeffs[i][j] * rhs[j];
    }
    rhs[i] = (rhs[i] - sum) / coeffs[i][i];
  }
}
  
  /// Apply perspective transform to an image
  static void _applyPerspectiveTransform(
  img.Image sourceImage, 
  img.Image destImage, 
  List<double> matrix
) {
  // Extract matrix components
  final double a = matrix[0];
  final double b = matrix[1];
  final double c = matrix[2];
  final double d = matrix[3];
  final double e = matrix[4];
  final double f = matrix[5];
  final double g = matrix[6];
  final double h = matrix[7];
  
  // For each pixel in the destination image, find the source pixel
  for (int y = 0; y < destImage.height; y++) {
    for (int x = 0; x < destImage.width; x++) {
      // Apply inverse transform to find source coordinates
      final double denominator = g * x + h * y + 1.0;
      if (denominator.abs() < 1e-10) continue; // Avoid division by zero
      
      final double srcX = (a * x + b * y + c) / denominator;
      final double srcY = (d * x + e * y + f) / denominator;
      
      // Check if source coordinates are within bounds
      if (srcX >= 0 && srcX < sourceImage.width - 1 && 
          srcY >= 0 && srcY < sourceImage.height - 1) {
        try {
          // Use bilinear interpolation for better quality
          final int x0 = srcX.floor();
          final int y0 = srcY.floor();
          final int x1 = x0 + 1;
          final int y1 = y0 + 1;
          
          // Add additional bounds checking here
          if (x0 < 0 || x0 >= sourceImage.width || 
              y0 < 0 || y0 >= sourceImage.height ||
              x1 < 0 || x1 >= sourceImage.width || 
              y1 < 0 || y1 >= sourceImage.height) {
            continue;
          }
          
          final double dx = srcX - x0;
          final double dy = srcY - y0;
          
          final p00 = sourceImage.getPixel(x0, y0);
          final p01 = sourceImage.getPixel(x0, y1);
          final p10 = sourceImage.getPixel(x1, y0);
          final p11 = sourceImage.getPixel(x1, y1);
          
          // Bilinear interpolation for each channel
          final int r = _interpolate(p00.r.toInt(), p10.r.toInt(), p01.r.toInt(), p11.r.toInt(), dx, dy);
          final int g = _interpolate(p00.g.toInt(), p10.g.toInt(), p01.g.toInt(), p11.g.toInt(), dx, dy);
          final int b = _interpolate(p00.b.toInt(), p10.b.toInt(), p01.b.toInt(), p11.b.toInt(), dx, dy);
          final int a = _interpolate(p00.a.toInt(), p10.a.toInt(), p01.a.toInt(), p11.a.toInt(), dx, dy);
          
          destImage.setPixel(x, y, img.ColorRgba8(r, g, b, a));
        } catch (e) {
          // Log the error and continue
          print('Error at pixel ($x,$y) using source (${srcX.toStringAsFixed(2)},${srcY.toStringAsFixed(2)}): $e');
          continue;
        }
      }
    }
  }
}
  
  /// Bilinear interpolation helper
  static int _interpolate(int p00, int p10, int p01, int p11, double dx, double dy) {
    final double result = 
        p00 * (1 - dx) * (1 - dy) +
        p10 * dx * (1 - dy) +
        p01 * (1 - dx) * dy +
        p11 * dx * dy;
    return result.round().clamp(0, 255);
  }
  
  /// Draw a calibration grid on the image
  static void _drawCalibrationGrid(
  img.Image image, 
  int startX, 
  int startY, 
  int width, 
  int height, 
  int gridSpacing, 
  img.Color color
) {
  // Ensure parameters are within image bounds
  final endX = math.min(startX + width, image.width);
  final endY = math.min(startY + height, image.height);
  
  // Draw horizontal lines
  for (int y = startY; y <= endY; y += gridSpacing) {
    if (y < 0 || y >= image.height) continue; // Skip if out of bounds
    
    for (int x = startX; x < endX; x++) {
      if (x < 0 || x >= image.width) continue; // Skip if out of bounds
      try {
        image.setPixel(x, y, color);
      } catch (e) {
        // Skip if error
        print('Error drawing horizontal grid line at ($x,$y): $e');
      }
    }
  }
  
  // Draw vertical lines
  for (int x = startX; x <= endX; x += gridSpacing) {
    if (x < 0 || x >= image.width) continue; // Skip if out of bounds
    
    for (int y = startY; y < endY; y++) {
      if (y < 0 || y >= image.height) continue; // Skip if out of bounds
      try {
        image.setPixel(x, y, color);
      } catch (e) {
        // Skip if error
        print('Error drawing vertical grid line at ($x,$y): $e');
      }
    }
  }
}
}