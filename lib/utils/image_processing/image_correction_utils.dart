// lib/utils/image_processing/image_correction_utils.dart
// Utility functions for correcting image perspective based on four markers

import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../general/machine_coordinates.dart';
import '../../services/detection/marker_detector.dart';
import 'image_utils.dart';

/// Utilities for image perspective correction
class ImageCorrectionUtils {
  /// Correct perspective distortion of an image based on four marker positions
  static Future<img.Image> correctPerspective(
    img.Image sourceImage,
    CoordinatePointXY originMarker,
    CoordinatePointXY xAxisMarker,
    CoordinatePointXY yAxisMarker,
    CoordinatePointXY topRightMarker,
    double markerXDistance,
    double markerYDistance
  ) async {
    print('MARKER DEBUG: Origin (${originMarker.x.round()}, ${originMarker.y.round()})');
    print('MARKER DEBUG: X-Axis (${xAxisMarker.x.round()}, ${xAxisMarker.y.round()})');
    print('MARKER DEBUG: Y-Axis (${yAxisMarker.x.round()}, ${yAxisMarker.y.round()})');
    print('MARKER DEBUG: Top-Right (${topRightMarker.x.round()}, ${topRightMarker.y.round()})');
    
    // Original corners of the quadrilateral in the source image
    final List<CoordinatePointXY> sourcePts = [
      originMarker,       // Bottom-left
      xAxisMarker,        // Bottom-right
      topRightMarker,     // Top-right
      yAxisMarker,        // Top-left
    ];
    
    // Calculate destination points to form a perfect rectangle
    final List<CoordinatePointXY> destPts = [
      CoordinatePointXY(0, markerYDistance),                            // Bottom-left
      CoordinatePointXY(markerXDistance, markerYDistance),              // Bottom-right
      CoordinatePointXY(markerXDistance, 0),                            // Top-right
      CoordinatePointXY(0, 0),                                          // Top-left
    ];
    
    print('SOURCE QUAD: ${sourcePts.map((p) => "(${p.x.round()},${p.y.round()})").join(", ")}');
    print('DEST QUAD: ${destPts.map((p) => "(${p.x.round()},${p.y.round()})").join(", ")}');
    
    // Create destination image with dimensions based on marker distances
    final int outputWidth = (markerXDistance * 1.1).toInt();
    final int outputHeight = (markerYDistance * 1.1).toInt();
    
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
    
    // Draw calibration grid
    final gridSpacing = (markerXDistance / 10).round();
    _drawCalibrationGrid(
      destImage,
      0, 
      0, 
      outputWidth, 
      outputHeight, 
      gridSpacing,
      img.ColorRgba8(0, 100, 255, 80)
    );
    
    return destImage;
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

  /// Legacy support for three markers
  static Future<img.Image> correctPerspectiveWithThreeMarkers(
    img.Image sourceImage,
    CoordinatePointXY originMarker,
    CoordinatePointXY xAxisMarker,
    CoordinatePointXY yAxisMarker,
    double markerXDistance,
    double markerYDistance
  ) async {
    // Calculate the theoretical position of the top-right marker
    final topRightX = xAxisMarker.x + (yAxisMarker.x - originMarker.x);
    final topRightY = yAxisMarker.y + (xAxisMarker.y - originMarker.y);
    final topRightMarker = CoordinatePointXY(topRightX, topRightY);
    
    // Call the four-marker version
    return correctPerspective(
      sourceImage,
      originMarker,
      xAxisMarker,
      yAxisMarker,
      topRightMarker,
      markerXDistance,
      markerYDistance
    );
  }
}