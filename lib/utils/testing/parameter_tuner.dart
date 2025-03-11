// lib/utils/testing/parameter_tuner.dart
// Utility for tuning algorithm parameters with visual feedback

import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

import '../../services/image_processing/contour_algorithms/default_contour_algorithm.dart';
import '../../services/image_processing/marker_detector.dart';
import '../../services/gcode/machine_coordinates.dart';
import '../../models/settings_model.dart';
import '../image_processing/drawing_utils.dart';

/// Utility class for tuning algorithm parameters
class ParameterTuner {
  /// Generate a set of test images with different parameter variations for tuning
  static Future<List<File>> tuneParameters(
    File imageFile,
    List<MarkerPoint> markers,
    SettingsModel settings,
    int seedX,
    int seedY
  ) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      
      // Create a coordinate system from markers
      final coordSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
        markers[0].toPoint(),  // Origin
        markers[1].toPoint(),  // X-axis
        markers[2].toPoint(),  // Scale/Y-axis
        settings.markerXDistance,
        settings.markerYDistance
      );
      
      // Parameter variations to test
      final variations = [
        // Default parameters for baseline
        {
          'name': '01_default',
          'contrastEnhancementFactor': 1.5,
          'blurRadius': 3,
          'edgeThreshold': 30,
          'morphologySize': 3,
          'useDarkBackgroundDetection': true,
        },
        // Higher contrast
        {
          'name': '02_high_contrast',
          'contrastEnhancementFactor': 2.2,
          'blurRadius': 3,
          'edgeThreshold': 30,
          'morphologySize': 3,
          'useDarkBackgroundDetection': true,
        },
        // More blur
        {
          'name': '03_more_blur',
          'contrastEnhancementFactor': 1.5,
          'blurRadius': 5,
          'edgeThreshold': 30,
          'morphologySize': 3,
          'useDarkBackgroundDetection': true,
        },
        // Higher edge threshold
        {
          'name': '04_high_edge_threshold',
          'contrastEnhancementFactor': 1.5,
          'blurRadius': 3,
          'edgeThreshold': 50,
          'morphologySize': 3,
          'useDarkBackgroundDetection': true,
        },
        // More morphological operations
        {
          'name': '05_more_morphology',
          'contrastEnhancementFactor': 1.5,
          'blurRadius': 3,
          'edgeThreshold': 30,
          'morphologySize': 5,
          'useDarkBackgroundDetection': true,
        },
        // Without dark background detection
        {
          'name': '06_no_dark_background',
          'contrastEnhancementFactor': 1.5,
          'blurRadius': 3,
          'edgeThreshold': 30,
          'morphologySize': 3,
          'useDarkBackgroundDetection': false,
        },
        // Combined: High contrast + more blur
        {
          'name': '07_high_contrast_blur',
          'contrastEnhancementFactor': 2.2,
          'blurRadius': 5,
          'edgeThreshold': 30,
          'morphologySize': 3,
          'useDarkBackgroundDetection': true,
        },
        // Combined: High contrast + higher edge threshold
        {
          'name': '08_high_contrast_edge',
          'contrastEnhancementFactor': 2.2,
          'blurRadius': 3,
          'edgeThreshold': 50,
          'morphologySize': 3,
          'useDarkBackgroundDetection': true,
        },
        // Aggressive processing
        {
          'name': '09_aggressive',
          'contrastEnhancementFactor': 2.5,
          'blurRadius': 5,
          'edgeThreshold': 50,
          'morphologySize': 5,
          'useDarkBackgroundDetection': true,
        },
        // Minimal processing
        {
          'name': '10_minimal',
          'contrastEnhancementFactor': 1.2,
          'blurRadius': 2,
          'edgeThreshold': 20,
          'morphologySize': 2,
          'useDarkBackgroundDetection': true,
        },
      ];
      
      // Generate a result for each variation
      final results = <File>[];
      
      for (final params in variations) {
        // Create algorithm with these parameters
        final algorithm = DefaultContourAlgorithm(
          contrastEnhancementFactor: params['contrastEnhancementFactor'] as double,
          blurRadius: params['blurRadius'] as int,
          edgeThreshold: params['edgeThreshold'] as int,
          morphologySize: params['morphologySize'] as int,
          useDarkBackgroundDetection: params['useDarkBackgroundDetection'] as bool,
        );
        
        // Run detection
        final result = await algorithm.detectContour(
          image,
          seedX,
          seedY,
          coordSystem
        );
        
        // Save result if we have a debug image
        if (result.debugImage != null) {
          // Add parameters to image
          final annotatedImage = _annotateImage(
            result.debugImage!,
            params
          );
          
          // Save to file
          final outputDir = Directory('${Directory.systemTemp.path}/parameter_tuning');
          await outputDir.create(recursive: true);
          
          final outputFile = File('${outputDir.path}/${params['name']}.png');
          await outputFile.writeAsBytes(img.encodePng(annotatedImage));
          
          results.add(outputFile);
        }
      }
      
      // Create a composite image with all results
      if (results.length > 1) {
        final composite = await _createCompositeImage(results);
        results.add(composite);
      }
      
      return results;
    } catch (e) {
      print('Error tuning parameters: $e');
      return [];
    }
  }
  
  /// Create a composite image from all the result files
  static Future<File> _createCompositeImage(List<File> resultFiles) async {
    try {
      // Load all images
      final images = <img.Image>[];
      for (final file in resultFiles) {
        final bytes = await file.readAsBytes();
        final image = img.decodeImage(bytes);
        if (image != null) {
          images.add(image);
        }
      }
      
      if (images.isEmpty) {
        throw Exception('No valid images found for composite');
      }
      
      // Calculate layout dimensions
      final int cols = math.min(3, images.length);
      final int rows = (images.length + cols - 1) ~/ cols;
      
      // Get dimensions from first image
      final sampleWidth = images[0].width;
      final sampleHeight = images[0].height;
      
      // Determine thumbnail size
      final maxWidth = 400;
      final scale = maxWidth / sampleWidth;
      final thumbWidth = (sampleWidth * scale).round();
      final thumbHeight = (sampleHeight * scale).round();
      
      // Create composite image
      final compositeWidth = thumbWidth * cols;
      final compositeHeight = thumbHeight * rows;
      final composite = img.Image(
        width: compositeWidth, 
        height: compositeHeight
      );
      
      // Fill with black background
      for (int y = 0; y < compositeHeight; y++) {
        for (int x = 0; x < compositeWidth; x++) {
          composite.setPixel(x, y, img.ColorRgba8(0, 0, 0, 255));
        }
      }
      
      // Place each image in the grid
      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        
        // Calculate position
        final col = i % cols;
        final row = i ~/ cols;
        
        // Resize image
        final resized = img.copyResize(
          image,
          width: thumbWidth,
          height: thumbHeight,
          interpolation: img.Interpolation.average
        );
        
        // Copy into composite
        final xOffset = col * thumbWidth;
        final yOffset = row * thumbHeight;
        for (int y = 0; y < resized.height; y++) {
          for (int x = 0; x < resized.width; x++) {
            composite.setPixel(xOffset + x, yOffset + y, resized.getPixel(x, y));
          }
        }
      }
      
      // Save composite
      final outputDir = Directory('${Directory.systemTemp.path}/parameter_tuning');
      await outputDir.create(recursive: true);
      final outputFile = File('${outputDir.path}/composite.png');
      await outputFile.writeAsBytes(img.encodePng(composite));
      
      return outputFile;
    } catch (e) {
      print('Error creating composite image: $e');
      // Return an empty file as fallback
      final outputFile = File('${Directory.systemTemp.path}/parameter_tuning/error.txt');
      await outputFile.writeAsString('Error creating composite: $e');
      return outputFile;
    }
  }
  
  /// Annotate image with parameter values
  static img.Image _annotateImage(img.Image image, Map<String, dynamic> params) {
    final result = img.copyResize(image, width: image.width, height: image.height);
    
    // Add title
    DrawingUtils.drawText(result, params['name'] as String, 10, 130, img.ColorRgba8(255, 255, 255, 255));
    
    // Add parameter values
    int y = 150;
    params.forEach((key, value) {
      if (key != 'name') {
        DrawingUtils.drawText(
          result, 
          '$key: $value', 
          10, 
          y, 
          img.ColorRgba8(255, 255, 255, 255)
        );
        y += 20;
      }
    });
    
    return result;
  }
}