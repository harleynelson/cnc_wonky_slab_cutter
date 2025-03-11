// lib/services/image_processing/contour_algorithms/default_contour_algorithm.dart
// Default contour detection algorithm optimized for wood slab detection

import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../gcode/machine_coordinates.dart';
import '../../../utils/image_processing/contour_detection_utils.dart';
import '../../../utils/image_processing/filter_utils.dart';
import '../../../utils/image_processing/threshold_utils.dart';
import '../../../utils/image_processing/drawing_utils.dart';
import '../../../utils/image_processing/color_utils.dart';
import '../../../utils/image_processing/base_image_utils.dart';
import '../../../utils/image_processing/geometry_utils.dart';
import '../slab_contour_result.dart';
import 'contour_algorithm_interface.dart';

/// Default contour detection algorithm optimized for wood slab detection
class DefaultContourAlgorithm implements ContourDetectionAlgorithm {
@override
  String get name => "Default";
  
  final bool generateDebugImage;
  final double contrastEnhancementFactor;
  final int blurRadius;
  final int edgeThreshold;
  final int morphologySize;
  final int smoothingWindowSize;
  final double simplifyEpsilon;
  final bool useDarkBackgroundDetection;
  final int adaptiveThresholdBlockSize;
  final int adaptiveThresholdConstant;

  DefaultContourAlgorithm({
    this.generateDebugImage = true,
    this.contrastEnhancementFactor = 1.5,
    this.blurRadius = 3,
    this.edgeThreshold = 30,
    this.morphologySize = 3,
    this.smoothingWindowSize = 5,
    this.simplifyEpsilon = 3.0,
    this.useDarkBackgroundDetection = true,
    this.adaptiveThresholdBlockSize = 25,
    this.adaptiveThresholdConstant = 5,
  });

  @override
  Future<SlabContourResult> detectContour(
    img.Image image, 
    int seedX, 
    int seedY, 
    MachineCoordinateSystem coordSystem
  ) async {
    // Create a debug image if needed
    img.Image? debugImage;
    if (generateDebugImage) {
      debugImage = img.copyResize(image, width: image.width, height: image.height);
    }

    // Save intermediate processing steps for debugging
    final processingSteps = <img.Image>[];
    
    try {
      // STEP 1: Convert to grayscale for processing
      final grayscale = BaseImageUtils.convertToGrayscale(image);
      if (generateDebugImage) processingSteps.add(img.copyResize(grayscale, width: grayscale.width, height: grayscale.height));
      
      // STEP 2: Apply contrast enhancement to make the slab stand out
      final enhanced = _enhanceContrast(grayscale, contrastEnhancementFactor);
      if (generateDebugImage) processingSteps.add(img.copyResize(enhanced, width: enhanced.width, height: enhanced.height));
      
      // STEP 3: Apply blur to reduce noise
      final blurred = FilterUtils.applyGaussianBlur(enhanced, blurRadius);
      if (generateDebugImage) processingSteps.add(img.copyResize(blurred, width: blurred.width, height: blurred.height));
      
      // STEP 4: Try multiple approaches and choose the best one
      
      // Approach 1: Adaptive thresholding
      final adaptiveThreshold = ThresholdUtils.applyAdaptiveThreshold(
        blurred, 
        adaptiveThresholdBlockSize, 
        adaptiveThresholdConstant
      );
      if (generateDebugImage) processingSteps.add(img.copyResize(adaptiveThreshold, width: adaptiveThreshold.width, height: adaptiveThreshold.height));
      
      // Approach 2: Edge detection
      final edges = FilterUtils.applyEdgeDetection(blurred, threshold: edgeThreshold);
      if (generateDebugImage) processingSteps.add(img.copyResize(edges, width: edges.width, height: edges.height));
      
      // Create binary masks from both approaches
      List<List<bool>> edgeMask = ThresholdUtils.createBinaryMask(edges, 128);
      List<List<bool>> adaptiveMask = ThresholdUtils.createBinaryMask(adaptiveThreshold, 128);
      
      // Apply morphological operations to both masks
      edgeMask = ContourDetectionUtils.applyMorphologicalClosing(edgeMask, morphologySize);
      adaptiveMask = ContourDetectionUtils.applyMorphologicalClosing(adaptiveMask, morphologySize);
      
      // STEP A: Try using the dark background detection approach
      List<List<bool>> darkBackgroundMask = _detectDarkBackground(blurred);
      if (useDarkBackgroundDetection) {
        darkBackgroundMask = ContourDetectionUtils.applyMorphologicalClosing(darkBackgroundMask, morphologySize);
      }
      
      // STEP 5: Decide which mask to use based on results at the seed point
      List<List<bool>> selectedMask;
      
      // Check if seed point is in a valid area for each mask
      bool seedInEdgeMask = _isSeedInValidArea(edgeMask, seedX, seedY);
      bool seedInAdaptiveMask = _isSeedInValidArea(adaptiveMask, seedX, seedY);
      bool seedInDarkBackgroundMask = useDarkBackgroundDetection && _isSeedInValidArea(darkBackgroundMask, seedX, seedY);
      
      // Choose the mask based on seed point validity and preferred method
      if (seedInDarkBackgroundMask && useDarkBackgroundDetection) {
        selectedMask = darkBackgroundMask;
        print('Using dark background detection mask');
      } else if (seedInAdaptiveMask) {
        selectedMask = adaptiveMask;
        print('Using adaptive threshold mask');
      } else if (seedInEdgeMask) {
        selectedMask = edgeMask;
        print('Using edge detection mask');
      } else {
        // Default to adaptive if seed point doesn't work with any method
        selectedMask = adaptiveMask;
        print('Defaulting to adaptive threshold mask (seed not in valid area)');
      }
      
      // STEP 6: Flood fill from seed point to identify the slab region
      final slabMask = _floodFillFromSeed(selectedMask, seedX, seedY);
      
      // STEP 7: Apply morphological operations to smooth the slab region
      final smoothedMask = ContourDetectionUtils.applyMorphologicalClosing(slabMask, 5);
      
      // STEP 8: Find the contour points from the mask
      final contourPoints = ContourDetectionUtils.findOuterContour(smoothedMask);
      
      // STEP 9: Simplify and smooth the contour
      final simplifiedContour = GeometryUtils.simplifyPolygon(contourPoints, simplifyEpsilon);
      final smoothContour = ContourDetectionUtils.smoothAndSimplifyContour(
        simplifiedContour, 
        simplifyEpsilon,
        windowSize: smoothingWindowSize
      );
      
      // STEP 10: Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(smoothContour);
      
      // STEP 11: Draw visualization for debugging
      if (debugImage != null) {
        // Draw processing stages
        _visualizeAdvancedProcessingSteps(
          debugImage, 
          edgeMask, 
          adaptiveMask, 
          slabMask, 
          smoothedMask,
          useDarkBackgroundDetection ? darkBackgroundMask : null
        );
        
        // Draw seed point
        DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
        
        // Draw final contour
        DrawingUtils.drawContour(debugImage, smoothContour, img.ColorRgba8(0, 255, 0, 255), thickness: 2);
        
        // Add algorithm name label
        DrawingUtils.drawText(debugImage, "Algorithm: $name", 10, 10, img.ColorRgba8(255, 255, 255, 255));
      }
      
      return SlabContourResult(
        pixelContour: smoothContour,
        machineContour: machineContour,
        debugImage: debugImage,
      );
      
    } catch (e) {
      print('Error in Default contour algorithm: $e');
      return _createFallbackResult(image, coordSystem, debugImage, seedX, seedY);
    }
  }
  
  /// Enhance contrast of a grayscale image to make the slab stand out
  img.Image _enhanceContrast(img.Image grayscale, double factor) {
    final result = img.Image(width: grayscale.width, height: grayscale.height);
    
    // Find min and max pixel values
    int min = 255;
    int max = 0;
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        min = math.min(min, intensity);
        max = math.max(max, intensity);
      }
    }
    
    // Calculate contrast adjustment
    final range = max - min;
    final midpoint = min + (range / 2);
    
    // Apply contrast enhancement
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        // Apply contrast enhancement centered around midpoint
        final adjusted = ((intensity - midpoint) * factor) + midpoint;
        final newIntensity = adjusted.round().clamp(0, 255);
        
        result.setPixel(x, y, img.ColorRgba8(newIntensity, newIntensity, newIntensity, 255));
      }
    }
    
    return result;
  }
  
  /// Flood fill from a seed point to identify the slab region
  List<List<bool>> _floodFillFromSeed(List<List<bool>> binaryMask, int seedX, int seedY) {
    final height = binaryMask.length;
    final width = binaryMask[0].length;
    
    // Create a result mask (initially all false)
    final resultMask = List.generate(
      height, (_) => List<bool>.filled(width, false)
    );
    
    // If seed is on an edge pixel, move it slightly
    int adjustedSeedX = seedX;
    int adjustedSeedY = seedY;
    
    // Check if seed is on a true pixel (edge) and attempt to move it
    if (seedX >= 0 && seedX < width && seedY >= 0 && seedY < height && binaryMask[seedY][seedX]) {
      // Try to find a nearby false pixel (non-edge)
      bool found = false;
      for (int radius = 1; radius < 20 && !found; radius++) {
        for (int dy = -radius; dy <= radius && !found; dy++) {
          for (int dx = -radius; dx <= radius && !found; dx++) {
            if (dx*dx + dy*dy <= radius*radius) {
              final nx = seedX + dx;
              final ny = seedY + dy;
              
              if (nx >= 0 && nx < width && ny >= 0 && ny < height && !binaryMask[ny][nx]) {
                adjustedSeedX = nx;
                adjustedSeedY = ny;
                found = true;
                break;
              }
            }
          }
        }
      }
    }
    
    // Invert mask for flood fill (false becomes true, true becomes false)
    // This way, edges (true in binaryMask) become barriers (false in inverted)
    final invertedMask = List.generate(
      height,
      (y) => List.generate(
        width,
        (x) => !binaryMask[y][x]
      )
    );
    
    // Use a queue for flood fill to avoid stack overflow
    final queue = <List<int>>[];
    queue.add([adjustedSeedX, adjustedSeedY]);
    
    // Track visited pixels
    final visited = List.generate(
      height, (_) => List<bool>.filled(width, false)
    );
    visited[adjustedSeedY][adjustedSeedX] = true;
    resultMask[adjustedSeedY][adjustedSeedX] = true;
    
    // 4-connected directions
    final dx = [1, 0, -1, 0];
    final dy = [0, 1, 0, -1];
    
    while (queue.isNotEmpty) {
      final point = queue.removeAt(0);
      final x = point[0];
      final y = point[1];
      
      // Check neighbors
      for (int i = 0; i < 4; i++) {
        final nx = x + dx[i];
        final ny = y + dy[i];
        
        // Skip if out of bounds or already visited
        if (nx < 0 || nx >= width || ny < 0 || ny >= height || visited[ny][nx]) {
          continue;
        }
        
        visited[ny][nx] = true;
        
        // If this is a non-edge pixel in the inverted mask (true),
        // add to the result and queue
        if (invertedMask[ny][nx]) {
          resultMask[ny][nx] = true;
          queue.add([nx, ny]);
        }
      }
    }
    
    return resultMask;
  }
  
  /// Visualize advanced processing steps for debugging
  void _visualizeAdvancedProcessingSteps(
    img.Image debugImage,
    List<List<bool>> edgeMask,
    List<List<bool>> adaptiveMask,
    List<List<bool>> slabMask,
    List<List<bool>> smoothedMask,
    List<List<bool>>? darkBackgroundMask
  ) {
    // Create a visualization with multiple stages visible
    final width = debugImage.width;
    final height = debugImage.height;
    
    // Draw edge mask as red overlay (semi-transparent)
    for (int y = 0; y < height && y < edgeMask.length; y++) {
      for (int x = 0; x < width && x < edgeMask[y].length; x++) {
        if (edgeMask[y][x]) {
          final pixel = debugImage.getPixel(x, y);
          debugImage.setPixel(x, y, img.ColorRgba8(
            (pixel.r.toInt() + 180) ~/ 2, 
            (pixel.g.toInt() + 0) ~/ 2, 
            (pixel.b.toInt() + 0) ~/ 2,
            150
          ));
        }
      }
    }
    
    // Draw adaptive mask as green overlay (even less opacity)
    for (int y = 0; y < height && y < adaptiveMask.length; y++) {
      for (int x = 0; x < width && x < adaptiveMask[y].length; x++) {
        if (adaptiveMask[y][x]) {
          final pixel = debugImage.getPixel(x, y);
          debugImage.setPixel(x, y, img.ColorRgba8(
            (pixel.r.toInt() * 3 + 0) ~/ 4, 
            (pixel.g.toInt() * 3 + 180) ~/ 4, 
            (pixel.b.toInt() * 3 + 0) ~/ 4,
            120
          ));
        }
      }
    }
    
    // If we have dark background mask, draw it in purple
    if (darkBackgroundMask != null) {
      for (int y = 0; y < height && y < darkBackgroundMask.length; y++) {
        for (int x = 0; x < width && x < darkBackgroundMask[y].length; x++) {
          if (darkBackgroundMask[y][x]) {
            final pixel = debugImage.getPixel(x, y);
            debugImage.setPixel(x, y, img.ColorRgba8(
              (pixel.r.toInt() * 3 + 180) ~/ 4, 
              (pixel.g.toInt() * 3 + 0) ~/ 4, 
              (pixel.b.toInt() * 3 + 180) ~/ 4,
              100
            ));
          }
        }
      }
    }
    
    // Draw slab mask outline with cyan for visibility
    _drawMaskOutline(debugImage, slabMask, img.ColorRgba8(0, 220, 255, 220), thickness: 1);
    
    // Draw smoothed mask outline with yellow for final result
    _drawMaskOutline(debugImage, smoothedMask, img.ColorRgba8(255, 255, 0, 180), thickness: 1);
    
    // Add stage labels
    DrawingUtils.drawText(debugImage, "Red: Edge Mask", 10, 30, img.ColorRgba8(255, 255, 255, 255));
    DrawingUtils.drawText(debugImage, "Green: Adaptive Mask", 10, 50, img.ColorRgba8(255, 255, 255, 255));
    if (darkBackgroundMask != null) {
      DrawingUtils.drawText(debugImage, "Purple: Dark Background", 10, 70, img.ColorRgba8(255, 255, 255, 255));
      DrawingUtils.drawText(debugImage, "Cyan: Slab Region", 10, 90, img.ColorRgba8(255, 255, 255, 255));
      DrawingUtils.drawText(debugImage, "Yellow: Smoothed Outline", 10, 110, img.ColorRgba8(255, 255, 255, 255));
    } else {
      DrawingUtils.drawText(debugImage, "Cyan: Slab Region", 10, 70, img.ColorRgba8(255, 255, 255, 255));
      DrawingUtils.drawText(debugImage, "Yellow: Smoothed Outline", 10, 90, img.ColorRgba8(255, 255, 255, 255));
    }
  }
  
  /// Helper method to draw mask outline
  void _drawMaskOutline(
    img.Image image, 
    List<List<bool>> mask, 
    img.Color color,
    {int thickness = 1}
  ) {
    final height = math.min(image.height, mask.length);
    final width = height > 0 ? math.min(image.width, mask[0].length) : 0;
    
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        if (mask[y][x]) {
          // Check if this is a boundary pixel
          if (!mask[y-1][x] || !mask[y+1][x] || 
              !mask[y][x-1] || !mask[y][x+1]) {
            
            // For thicker boundary, draw a small square
            for (int dy = -thickness ~/ 2; dy <= thickness ~/ 2; dy++) {
              for (int dx = -thickness ~/ 2; dx <= thickness ~/ 2; dx++) {
                final nx = x + dx;
                final ny = y + dy;
                if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                  image.setPixel(nx, ny, color);
                }
              }
            }
          }
        }
      }
    }
  }
  
  /// Check if the seed is within a valid area of the mask (not on edge)
  bool _isSeedInValidArea(List<List<bool>> mask, int seedX, int seedY) {
    if (seedX < 0 || seedY < 0 || seedY >= mask.length || seedX >= mask[0].length) {
      return false;
    }
    
    // Check if seed is on a true pixel (we want it to be false - inside area)
    if (mask[seedY][seedX]) {
      // Seed is on edge (true), check if there are non-edge areas nearby
      final searchRadius = 20;
      for (int radius = 1; radius < searchRadius; radius++) {
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            if (dx*dx + dy*dy <= radius*radius) {
              final ny = seedY + dy;
              final nx = seedX + dx;
              
              if (ny >= 0 && ny < mask.length && nx >= 0 && nx < mask[0].length && !mask[ny][nx]) {
                // Found a valid seed point nearby
                return true;
              }
            }
          }
        }
      }
      return false;  // No valid seed points found nearby
    }
    
    // Seed is on non-edge (false) - check if it's not isolated
    int falseNeighbors = 0;
    for (int dy = -5; dy <= 5; dy++) {
      for (int dx = -5; dx <= 5; dx++) {
        final ny = seedY + dy;
        final nx = seedX + dx;
        
        if (ny >= 0 && ny < mask.length && nx >= 0 && nx < mask[0].length && !mask[ny][nx]) {
          falseNeighbors++;
        }
      }
    }
    
    // Ensure we have a reasonable number of non-edge pixels around us
    return falseNeighbors > 10;
  }
  
  /// Detect dark background vs lighter slab
  List<List<bool>> _detectDarkBackground(img.Image grayscale) {
    // Get the number of light vs dark pixels
    int darkPixels = 0;
    int lightPixels = 0;
    final threshold = 128;
    
    // Create a histogram of intensities
    final histogram = List<int>.filled(256, 0);
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        histogram[intensity]++;
        if (intensity < threshold) {
          darkPixels++;
        } else {
          lightPixels++;
        }
      }
    }
    
    // If we have more dark pixels than light, assume dark background
    final hasDarkBackground = darkPixels > lightPixels;
    
    // Find the optimal threshold using Otsu's method
    final otsuThreshold = ThresholdUtils.findOptimalThreshold(grayscale);
    
    // Create a binary mask where true values are edges (background)
    final mask = List.generate(
      grayscale.height,
      (y) => List<bool>.filled(grayscale.width, false)
    );
    
    for (int y = 0; y < grayscale.height; y++) {
      for (int x = 0; x < grayscale.width; x++) {
        final pixel = grayscale.getPixel(x, y);
        final intensity = BaseImageUtils.calculateLuminance(
          pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
        );
        
        // If dark background, mark dark pixels as true (background/edges)
        // If light background, mark light pixels as true (background/edges)
        if (hasDarkBackground) {
          mask[y][x] = intensity < otsuThreshold;
        } else {
          mask[y][x] = intensity > otsuThreshold;
        }
      }
    }
    
    return mask;
  }
  
  /// Create a fallback result when detection fails
  SlabContourResult _createFallbackResult(
    img.Image image, 
    MachineCoordinateSystem coordSystem,
    img.Image? debugImage,
    int seedX,
    int seedY
  ) {
    // Create a circular contour around the seed point
    final radius = math.min(image.width, image.height) * 0.3;
    final contour = <Point>[];
    
    for (int i = 0; i <= 36; i++) {
      final angle = i * math.pi / 18; // 10 degrees in radians
      final x = seedX + radius * math.cos(angle);
      final y = seedY + radius * math.sin(angle);
      contour.add(Point(x, y));
    }
    
    // Convert to machine coordinates
    final machineContour = coordSystem.convertPointListToMachineCoords(contour);
    
    // Draw on debug image if available
    if (debugImage != null) {
      // Draw the fallback contour
      DrawingUtils.drawContour(debugImage, contour, img.ColorRgba8(255, 0, 0, 255));
      
      // Draw seed point
      DrawingUtils.drawCircle(debugImage, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255));
      
      // Add fallback label
      DrawingUtils.drawText(debugImage, "FALLBACK: $name algorithm", 10, 10, img.ColorRgba8(255, 0, 0, 255));
    }
    
    return SlabContourResult(
      pixelContour: contour,
      machineContour: machineContour,
      debugImage: debugImage,
    );
  }
}