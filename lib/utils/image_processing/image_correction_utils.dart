// lib/utils/image_processing/image_correction_utils.dart
// Utility functions for correcting image perspective based on four markers

import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../general/machine_coordinates.dart';
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
  
  // Calculate destination points for a perfect rectangle with 90-degree corners
  // We'll use the real-world measurements to ensure proper aspect ratio
  final List<CoordinatePointXY> destPts = [
    CoordinatePointXY(0, markerYDistance),                            // Bottom-left
    CoordinatePointXY(markerXDistance, markerYDistance),              // Bottom-right
    CoordinatePointXY(markerXDistance, 0),                            // Top-right
    CoordinatePointXY(0, 0),                                          // Top-left
  ];
  
  print('SOURCE QUAD: ${sourcePts.map((p) => "(${p.x.round()},${p.y.round()})").join(", ")}');
  print('DEST QUAD: ${destPts.map((p) => "(${p.x.round()},${p.y.round()})").join(", ")}');
  
  // Create destination image with dimensions based on marker distances
  // Add slight padding to ensure we don't cut off any edges
  final int outputWidth = (markerXDistance * 1.1).round();
  final int outputHeight = (markerYDistance * 1.1).round();
  
  // Create destination image
  final img.Image destImage = img.Image(width: outputWidth, height: outputHeight);
  
  // Fill with white background
  for (int y = 0; y < outputHeight; y++) {
    for (int x = 0; x < outputWidth; x++) {
      destImage.setPixel(x, y, img.ColorRgba8(255, 255, 255, 255));
    }
  }
  
  // Check if points form a valid quadrilateral
  if (!_isValidQuadrilateral(sourcePts[0], sourcePts[1], sourcePts[2], sourcePts[3])) {
    // Draw error indication on the destination image
    _drawErrorIndicator(destImage, "Invalid marker placement");
    return destImage;
  }
  
  try {
    // Calculate the perspective transform matrix
    final perspectiveMatrix = _computeHomography(sourcePts, destPts);
    
    // Apply the perspective transformation
    _applyPerspectiveTransform(sourceImage, destImage, perspectiveMatrix);
    
    // Draw calibration grid for visual reference
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
    
    print('DEBUG TRANSFORM: Perspective transform completed successfully');
  } catch (e) {
    print('ERROR: Perspective correction failed: $e');
    // Draw error indication on the destination image
    _drawErrorIndicator(destImage, "Perspective correction failed: $e");
  }
  
  return destImage;
}
  
  /// Draw error indicator on image
  static void _drawErrorIndicator(img.Image image, String errorMessage) {
    // Draw a red X across the image
    ImageUtils.drawLine(
      image, 
      0, 0, 
      image.width - 1, image.height - 1, 
      ImageUtils.colorRed
    );
    
    ImageUtils.drawLine(
      image, 
      0, image.height - 1, 
      image.width - 1, 0, 
      ImageUtils.colorRed
    );
    
    // Draw error message
    ImageUtils.drawText(
      image,
      errorMessage,
      20,
      image.height ~/ 2,
      ImageUtils.colorRed
    );
  }
  
  /// Check for valid quadrilateral before attempting perspective correction
static bool _isValidQuadrilateral(
  CoordinatePointXY p1,
  CoordinatePointXY p2,
  CoordinatePointXY p3,
  CoordinatePointXY p4
) {
  // Ensure the points don't form a degenerate quad (e.g., three points in a line)
  // First check distances
  double minDist = 10.0; // Minimum distance in pixels
  
  double d12 = _distance(p1, p2);
  double d23 = _distance(p2, p3);
  double d34 = _distance(p3, p4);
  double d41 = _distance(p4, p1);
  double d13 = _distance(p1, p3); // Diagonal
  double d24 = _distance(p2, p4); // Diagonal
  
  if (d12 < minDist || d23 < minDist || d34 < minDist || d41 < minDist) {
    print('ERROR: Points too close together: $d12, $d23, $d34, $d41');
    return false;
  }
  
  // Check for proper winding (should be convex)
  double crossProduct1 = _crossProduct(p1, p2, p3);
  double crossProduct2 = _crossProduct(p2, p3, p4);
  double crossProduct3 = _crossProduct(p3, p4, p1);
  double crossProduct4 = _crossProduct(p4, p1, p2);
  
  // All cross products should have the same sign for a convex polygon
  bool allPositive = crossProduct1 > 0 && crossProduct2 > 0 && 
                    crossProduct3 > 0 && crossProduct4 > 0;
  bool allNegative = crossProduct1 < 0 && crossProduct2 < 0 && 
                    crossProduct3 < 0 && crossProduct4 < 0;
  
  if (!allPositive && !allNegative) {
    print('ERROR: Points do not form a convex quadrilateral');
    return false;
  }
  
  // Check if aspect ratio is reasonable (not too extreme)
  final double aspectRatio = math.max(d12, d34) / math.max(d23, d41);
  if (aspectRatio > 10.0 || aspectRatio < 0.1) {
    print('ERROR: Extreme aspect ratio: $aspectRatio');
    return false;
  }
  
  return true;
}
  
  /// Helper method to calculate the cross product of vectors AB and AC
  static double _crossProduct(CoordinatePointXY a, CoordinatePointXY b, CoordinatePointXY c) {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  }
  
  /// Helper method to calculate distance between two points
  static double _distance(CoordinatePointXY p1, CoordinatePointXY p2) {
    double dx = p2.x - p1.x;
    double dy = p2.y - p1.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Compute the homography matrix for perspective transformation
static List<double> _computeHomography(
  List<CoordinatePointXY> sourcePts, 
  List<CoordinatePointXY> destPts
) {
  if (sourcePts.length != 4 || destPts.length != 4) {
    throw Exception('Four source and destination points are required');
  }
  
  // Validate the source points form a proper quadrilateral
  if (!_isValidQuadrilateral(
      sourcePts[0], sourcePts[1], sourcePts[2], sourcePts[3])) {
    throw Exception('Source points do not form a valid quadrilateral');
  }
  
  // Set up the equation system: Ah = b
  // For each corresponding point pair, we get two equations
  final List<List<double>> A = List.generate(8, (_) => List<double>.filled(8, 0.0));
  final List<double> b = List<double>.filled(8, 0.0);
  
  // Log source and destination points
  print('DEBUG HOMOG: Source points: ' + 
        sourcePts.map((p) => '(${p.x.toStringAsFixed(2)}, ${p.y.toStringAsFixed(2)})').join(', '));
  print('DEBUG HOMOG: Dest points: ' + 
        destPts.map((p) => '(${p.x.toStringAsFixed(2)}, ${p.y.toStringAsFixed(2)})').join(', '));
  
  for (int i = 0; i < 4; i++) {
    final double x = sourcePts[i].x;
    final double y = sourcePts[i].y;
    final double X = destPts[i].x; 
    final double Y = destPts[i].y;
    
    // Equations for the x-coordinate
    int idx = i * 2;
    A[idx][0] = x;
    A[idx][1] = y;
    A[idx][2] = 1;
    A[idx][3] = 0;
    A[idx][4] = 0;
    A[idx][5] = 0;
    A[idx][6] = -X * x;
    A[idx][7] = -X * y;
    b[idx] = X;
    
    // Equations for the y-coordinate
    idx = i * 2 + 1;
    A[idx][0] = 0;
    A[idx][1] = 0;
    A[idx][2] = 0;
    A[idx][3] = x;
    A[idx][4] = y;
    A[idx][5] = 1;
    A[idx][6] = -Y * x;
    A[idx][7] = -Y * y;
    b[idx] = Y;
  }
  
  try {
    // Solve the system using Gaussian elimination with partial pivoting
    final List<double> h = _solveLinearSystem(A, b);
    
    // Create a new mutable list for the result
    List<double> result = List<double>.from(h);
    // Add the last element h[8] = 1 to complete the homography matrix
    result.add(1.0);
    
    print('DEBUG HOMOG: Computed homography matrix: ' + result.map((v) => v.toStringAsFixed(4)).join(', '));
    
    return result;
  } catch (e) {
    print('ERROR HOMOG: Failed to compute homography: $e');
    throw Exception('Failed to compute perspective transformation: $e');
  }
}
  
  /// Solve a system of linear equations using Gaussian elimination with partial pivoting
  static List<double> _solveLinearSystem(List<List<double>> A, List<double> b) {
    final int n = b.length;
    
    // Perform Gaussian elimination with partial pivoting
    for (int i = 0; i < n; i++) {
      // Find the pivot (maximum absolute value in the current column)
      int maxRow = i;
      double maxVal = A[i][i].abs();
      
      for (int j = i + 1; j < n; j++) {
        if (A[j][i].abs() > maxVal) {
          maxVal = A[j][i].abs();
          maxRow = j;
        }
      }
      
      // Swap rows if needed
      if (maxRow != i) {
        // Swap rows in A
        for (int j = i; j < n; j++) {
          final temp = A[i][j];
          A[i][j] = A[maxRow][j];
          A[maxRow][j] = temp;
        }
        
        // Swap corresponding element in b
        final temp = b[i];
        b[i] = b[maxRow];
        b[maxRow] = temp;
      }
      
      // Check if matrix is singular
      if (A[i][i].abs() < 1e-10) {
        throw Exception('Matrix is singular or nearly singular');
      }
      
      // Eliminate elements below the pivot
      for (int j = i + 1; j < n; j++) {
        final factor = A[j][i] / A[i][i];
        
        // Update b
        b[j] -= factor * b[i];
        
        // Update A
        for (int k = i; k < n; k++) {
          A[j][k] -= factor * A[i][k];
        }
      }
    }
    
    // Back-substitution
    final List<double> x = List<double>.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      double sum = 0.0;
      for (int j = i + 1; j < n; j++) {
        sum += A[i][j] * x[j];
      }
      x[i] = (b[i] - sum) / A[i][i];
    }
    
    return x;
  }
  
  /// Apply the perspective transform with extra error handling
static void _applyPerspectiveTransform(
  img.Image sourceImage, 
  img.Image destImage, 
  List<double> homography
) {
  try {
    // Extract homography matrix elements
    final double h11 = homography[0];
    final double h12 = homography[1];
    final double h13 = homography[2];
    final double h21 = homography[3];
    final double h22 = homography[4];
    final double h23 = homography[5];
    final double h31 = homography[6];
    final double h32 = homography[7];
    final double h33 = homography[8];
    
    print('DEBUG TRANSFORM: Applying homography to image ${sourceImage.width}x${sourceImage.height} → ${destImage.width}x${destImage.height}');
    
    // If homography values are too extreme, the transformation might fail
    double maxValue = homography.reduce((a, b) => a.abs() > b.abs() ? a : b).abs();
    if (maxValue > 1000) {
      print('WARNING TRANSFORM: Homography has extreme values (max: $maxValue)');
    }
    
    // For each pixel in the destination image, find the corresponding source pixel
    for (int y = 0; y < destImage.height; y++) {
      for (int x = 0; x < destImage.width; x++) {
        // Apply inverse homography to get source coordinates
        // [xs, ys, w] = H^(-1) * [x, y, 1]
        final double w = h31 * x + h32 * y + h33;
        
        // Skip if denominator is too small
        if (w.abs() < 1e-10) continue;
        
        final double srcX = (h11 * x + h12 * y + h13) / w;
        final double srcY = (h21 * x + h22 * y + h23) / w;
        
        // Skip if source coordinates are outside the image bounds with a small margin
        if (srcX < -0.5 || srcX >= sourceImage.width - 0.5 || 
            srcY < -0.5 || srcY >= sourceImage.height - 0.5) {
          continue;
        }
        
        // Bilinear interpolation for better quality
        final int x0 = srcX.floor();
        final int y0 = srcY.floor();
        final int x1 = x0 + 1;
        final int y1 = y0 + 1;
        
        // Ensure neighbor pixels are within image bounds
        final int safeX0 = x0.clamp(0, sourceImage.width - 1);
        final int safeY0 = y0.clamp(0, sourceImage.height - 1);
        final int safeX1 = x1.clamp(0, sourceImage.width - 1);
        final int safeY1 = y1.clamp(0, sourceImage.height - 1);
        
        // Calculate interpolation weights
        final double dx = srcX - x0;
        final double dy = srcY - y0;
        
        // Get pixel values with bounds checking
        final p00 = sourceImage.getPixel(safeX0, safeY0);
        final p01 = sourceImage.getPixel(safeX0, safeY1);
        final p10 = sourceImage.getPixel(safeX1, safeY0);
        final p11 = sourceImage.getPixel(safeX1, safeY1);
        
        // Bilinear interpolation for each channel
        final int r = _interpolate(p00.r, p10.r, p01.r, p11.r, dx, dy);
        final int g = _interpolate(p00.g, p10.g, p01.g, p11.g, dx, dy);
        final int b = _interpolate(p00.b, p10.b, p01.b, p11.b, dx, dy);
        final int a = _interpolate(p00.a, p10.a, p01.a, p11.a, dx, dy);
        
        // Set the pixel in the destination image
        destImage.setPixel(x, y, img.ColorRgba8(r, g, b, a));
      }
    }
    
  } catch (e) {
    print('ERROR TRANSFORM: $e');
    // Fill destination with an error pattern in case of failure
    _fillWithErrorPattern(destImage);
  }
}
  
  /// Fill the destination image with an error pattern if transformation fails
  static void _fillWithErrorPattern(img.Image image) {
    final redColor = img.ColorRgba8(255, 100, 100, 255);
    final blackColor = img.ColorRgba8(0, 0, 0, 255);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        // Create a checkerboard pattern
        bool isRed = (x ~/ 20 + y ~/ 20) % 2 == 0;
        image.setPixel(x, y, isRed ? redColor : blackColor);
      }
    }
  }
  
  /// Bilinear interpolation helper for pixel values
  static int _interpolate(num p00, num p10, num p01, num p11, double dx, double dy) {
    final double interpVal = 
      p00.toDouble() * (1 - dx) * (1 - dy) +
      p10.toDouble() * dx * (1 - dy) +
      p01.toDouble() * (1 - dx) * dy +
      p11.toDouble() * dx * dy;
    
    return interpVal.round().clamp(0, 255);
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