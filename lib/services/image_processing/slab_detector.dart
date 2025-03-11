// lib/services/image_processing/slab_detector.dart
// Class for detecting slab outlines in images and generating toolpaths

import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';

import '../gcode/machine_coordinates.dart';
import '../gcode/gcode_generator.dart';
import 'marker_detector.dart';
import 'slab_contour_detector.dart';
import 'slab_contour_result.dart';
import '../../models/settings_model.dart';
import '../../utils/image_processing/drawing_utils.dart';
import '../../utils/image_processing/image_utils.dart';
import '../../utils/image_processing/contour_detection_utils.dart';
import '../../utils/image_processing/geometry_utils.dart';

/// Result of the slab processing operation
class SlabProcessingResult {
  final File processedImage;
  final File gcodeFile;
  final List<Point> slabContour;
  final List<Point> toolpath;
  final double? contourAreaMm2;

  SlabProcessingResult({
    required this.processedImage,
    required this.gcodeFile,
    required this.slabContour,
    required this.toolpath,
    this.contourAreaMm2,
  });
  
  /// Dispose of resources when no longer needed
  Future<void> dispose() async {
    // Close file handles if they're still open
    try {
      await processedImage.exists().then((exists) {
        if (exists) {
          // The file exists and can be safely used
        }
      });
      
      await gcodeFile.exists().then((exists) {
        if (exists) {
          // The file exists and can be safely used
        }
      });
    } catch (e) {
      print('Error disposing SlabProcessingResult: $e');
    }
  }
}

/// Class for detecting slab outlines in images and generating toolpaths
class SlabDetector {
  final SettingsModel settings;
  final int processingTimeout;
  final int maxImageSize;
  
  SlabDetector({
    required this.settings,
    this.processingTimeout = 30000,  // 30 second timeout
    this.maxImageSize = 1200,        // Max image dimension
  });
  
  /// Process an image to detect slab outline and generate G-code
  Future<SlabProcessingResult> processImage(File imageFile) async {
    // Create a timeout for the entire processing operation
    return await Future.delayed(Duration.zero, () {
      return Future.value(_processImageWithTimeout(imageFile))
        .timeout(
          Duration(milliseconds: processingTimeout),
          onTimeout: () => throw TimeoutException('Processing timed out after ${processingTimeout}ms')
        );
    });
  }
  
  Future<SlabProcessingResult> _processImageWithTimeout(File imageFile) async {
    try {
      // Read image data before passing to isolate
      final bytes = await imageFile.readAsBytes();
      
      // Don't use compute for web platform since isolates work differently there
      if (kIsWeb) {
        return _processImageDirect(bytes, settings);
      }
      
      // On mobile, try to use an isolate but with error handling
      try {
        return await compute(_processImageIsolate, {
          'imageBytes': bytes,
          'settings': {
            'cncWidth': settings.cncWidth,
            'cncHeight': settings.cncHeight,
            'markerXDistance': settings.markerXDistance,
            'markerYDistance': settings.markerYDistance,
            'toolDiameter': settings.toolDiameter,
            'stepover': settings.stepover,
            'safetyHeight': settings.safetyHeight,
            'feedRate': settings.feedRate,
            'plungeRate': settings.plungeRate,
            'cuttingDepth': settings.cuttingDepth,
          },
          'maxImageSize': maxImageSize,
        });
      } catch (isolateError) {
        // If isolate fails, log the error and fall back to direct processing
        print('Isolate processing failed: $isolateError');
        return _processImageDirect(bytes, settings);
      }
    } catch (e, stackTrace) {
      // Create a user-friendly error message that can be copied
      final errorMessage = 'Error processing image: ${e.toString()}\n$stackTrace';
      print(errorMessage);
      
      // Rethrow with a more detailed message
      throw Exception(errorMessage);
    }
  }
  
  /// Process the image directly in the main isolate (fallback method)
  Future<SlabProcessingResult> _processImageDirect(List<int> bytes, SettingsModel settings) async {
    print('Processing image directly (no isolate)');
    
    // Decode the image
    final image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) {
      throw Exception('Failed to decode image - invalid format or corrupted file');
    }

    print('Image dimensions: ${image.width}x${image.height}');
    
    // Resize large images to conserve memory
    img.Image processImage = image;
    if (image.width > maxImageSize || image.height > maxImageSize) {
      processImage = ImageUtils.safeResize(image, maxSize: maxImageSize);
      print('Resized Image dimensions: ${processImage.width}x${processImage.height}');
    }
    
    // Create a copy for visualization
    final outputImage = img.copyResize(processImage, width: processImage.width, height: processImage.height);
    
    // 1. Detect markers with the improved marker detector
    final markerDetector = MarkerDetector(
      markerRealDistanceMm: settings.markerXDistance,
      generateDebugImage: true,
      maxImageSize: maxImageSize,
    );
    
    print('Detecting markers...');
    final markerResult = await markerDetector.detectMarkers(processImage);
    
    // Create coordinate system from marker detection
    final coordinateSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
      markerResult.markers[0].toPoint(),  // Origin
      markerResult.markers[1].toPoint(),  // X-axis
      markerResult.markers[2].toPoint(),  // Scale/Y-axis
      settings.markerXDistance,
      settings.markerYDistance
    );
    
    // If we have debug information from marker detection, copy to output
    if (markerResult.debugImage != null) {
      try {
        // Overlay marker detection debug info on the output image
        _overlayDebugImage(outputImage, markerResult.debugImage!);
      } catch (e) {
        print('Error overlaying marker debug image: $e');
      }
    }
    
    // 2. Detect slab contour with the improved contour detector
    final contourDetector = SlabContourDetector(
      generateDebugImage: true,
      maxImageSize: maxImageSize,
      processingTimeout: 20000, // Extended timeout for more thorough processing
    );
    
    print('Detecting slab contour...');
    final contourResult = await contourDetector.detectContour(processImage, coordinateSystem);
    
    // Post-process the contour to ensure we get a clean outline
    final cleanedContour = ContourDetectionUtils.ensureCleanOuterContour(contourResult.machineContour);
    
    // If we have debug information from contour detection, copy to output
    if (contourResult.debugImage != null) {
      try {
        // Overlay contour detection debug info
        _overlayDebugImage(outputImage, contourResult.debugImage!, greenOnly: true);
      } catch (e) {
        print('Error overlaying contour debug image: $e');
      }
    }
    
    // Draw machine contour on output image
    final machineContourPixels = coordinateSystem.convertPointListToPixelCoords(cleanedContour);
    
    try {
      for (int i = 0; i < machineContourPixels.length - 1; i++) {
        final p1 = machineContourPixels[i];
        final p2 = machineContourPixels[i + 1];
        
        DrawingUtils.drawLine(
          outputImage,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          img.ColorRgba8(0, 255, 0, 255) // Green
        );
      }
    } catch (e) {
      print('Error drawing machine contour: $e');
    }
    
    // 3. Generate toolpath - use the cleaned contour
    print('Generating toolpath...');
    final toolpath = _generateOptimizedToolpath(
      cleanedContour,
      settings.toolDiameter,
      settings.stepover,
    );
    
    try {
      // Draw toolpath on output image
      final toolpathPixels = coordinateSystem.convertPointListToPixelCoords(toolpath);
      
      for (int i = 0; i < toolpathPixels.length - 1; i++) {
        final p1 = toolpathPixels[i];
        final p2 = toolpathPixels[i + 1];
        
        DrawingUtils.drawLine(
          outputImage,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          img.ColorRgba8(0, 0, 255, 255) // Blue
        );
      }
    } catch (e) {
      print('Error drawing toolpath: $e');
    }

    print('Contour points: ${cleanedContour.length}');
    print('Toolpath points: ${toolpath.length}');
    
    // 4. Generate G-code
    print('Generating G-code...');
    final gcodeGenerator = GcodeGenerator(
      safetyHeight: settings.safetyHeight,
      feedRate: settings.feedRate,
      plungeRate: settings.plungeRate,
      cuttingDepth: settings.cuttingDepth,
    );
    
    final gcodeContent = gcodeGenerator.generateGcode(toolpath);
    
    try {
      // Add metadata and statistics to output image
      DrawingUtils.drawText(
        outputImage, 
        "Area: ${GeometryUtils.polygonArea(cleanedContour).toStringAsFixed(2)} sq mm", 
        10, 
        10, 
        img.ColorRgba8(255, 255, 255, 255)
      );
      
      DrawingUtils.drawText(
        outputImage, 
        "Toolpath length: ${GeometryUtils.polygonPerimeter(toolpath).toStringAsFixed(2)} mm", 
        10, 
        30, 
        img.ColorRgba8(255, 255, 255, 255)
      );
    } catch (e) {
      print('Error drawing metadata: $e');
    }
    
    // Save processed image
    File processedImageFile;
    File gcodeFile;
    
    try {
      final tempDir = await getTemporaryDirectory();
      final processedImagePath = path.join(tempDir.path, 'processed_image.png');
      processedImageFile = File(processedImagePath);
      
      // Use try-with-resources pattern for file operations
      final imageData = img.encodePng(outputImage);
      await processedImageFile.writeAsBytes(imageData);
      
      // Save G-code to file
      final gcodePath = path.join(tempDir.path, 'slab_surfacing.gcode');
      gcodeFile = File(gcodePath);
      await gcodeFile.writeAsString(gcodeContent);
    } catch (e) {
      throw Exception('Error saving output files: $e');
    }
    
    return SlabProcessingResult(
      processedImage: processedImageFile,
      gcodeFile: gcodeFile,
      slabContour: cleanedContour,
      toolpath: toolpath,
      contourAreaMm2: GeometryUtils.polygonArea(cleanedContour),
    );
  }
  
  /// Overlay debug visualization from one image onto another
  void _overlayDebugImage(img.Image target, img.Image source, {bool greenOnly = false}) {
    if (target.width != source.width || target.height != source.height) {
      print('Warning: Debug image dimensions do not match output image');
      return;
    }
    
    for (int y = 0; y < source.height; y++) {
      for (int x = 0; x < source.width; x++) {
        if (x >= 0 && x < target.width && y >= 0 && y < target.height) {
          try {
            final debugPixel = source.getPixel(x, y);
            
            if (greenOnly) {
              // Only copy green pixels (contour visualization)
              if (debugPixel.g > 100 && debugPixel.r < 100 && debugPixel.b < 100) {
                target.setPixel(x, y, debugPixel);
              }
            } else {
              // Only copy non-black pixels (markers and visualizations)
              final intensity = (debugPixel.r + debugPixel.g + debugPixel.b) ~/ 3;
              if (intensity > 20) {
                target.setPixel(x, y, debugPixel);
              }
            }
          } catch (e) {
            // Skip this pixel if there's an error
            continue;
          }
        }
      }
    }
  }

  /// Generate an optimized toolpath for the given contour
  List<Point> _generateOptimizedToolpath(
    List<Point> contour, 
    double toolDiameter, 
    double stepover
  ) {
    // If the contour is too small or invalid, use the basic toolpath generator
    if (contour.length < 10) {
      return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
    }
    
    try {
      // Find the bounding box of the contour
      final boundingBox = GeometryUtils.calculateBoundingBox(contour);
      double minX = boundingBox['minX']!;
      double minY = boundingBox['minY']!;
      double maxX = boundingBox['maxX']!;
      double maxY = boundingBox['maxY']!;
      
      // Inset by half tool diameter to account for tool radius
      final inset = toolDiameter / 2;
      minX += inset;
      minY += inset;
      maxX -= inset;
      maxY -= inset;
      
      // Check if bounding box is valid after inset
      if (minX >= maxX || minY >= maxY) {
        // Contour is too small for the tool, use a simpler approach
        return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
      }
      
      // Generate zigzag pattern for efficient material removal
      // Calculate direction based on longest dimension
      final width = maxX - minX;
      final height = maxY - minY;
      final horizontal = width > height;
      
      final toolpath = <Point>[];
      
      if (horizontal) {
        // Generate horizontal zigzag (moving along Y)
        double y = minY;
        bool movingRight = true;
        
        while (y <= maxY) {
          if (movingRight) {
            toolpath.add(Point(minX, y));
            toolpath.add(Point(maxX, y));
          } else {
            toolpath.add(Point(maxX, y));
            toolpath.add(Point(minX, y));
          }
          
          y += stepover;
          movingRight = !movingRight;
        }
      } else {
        // Generate vertical zigzag (moving along X)
        double x = minX;
        bool movingDown = true;
        
        while (x <= maxX) {
          if (movingDown) {
            toolpath.add(Point(x, minY));
            toolpath.add(Point(x, maxY));
          } else {
            toolpath.add(Point(x, maxY));
            toolpath.add(Point(x, minY));
          }
          
          x += stepover;
          movingDown = !movingDown;
        }
      }
      
      // Post-process the toolpath to ensure it stays within the contour
      return ContourDetectionUtils.clipToolpathToContour(toolpath, contour);
    } catch (e) {
      print('Error generating optimized toolpath: $e');
      // Fall back to basic toolpath generation
      return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
    }
  }
}

/// Function to process the image in an isolate (separate thread)
Future<SlabProcessingResult> _processImageIsolate(Map<String, dynamic> data) async {
  // Initialize the compute isolate's Flutter binary messenger
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Extract data passed to the isolate
    final List<int> imageBytes = data['imageBytes'] as List<int>;
    final Map<String, dynamic> settingsMap = data['settings'] as Map<String, dynamic>;
    final int? maxImageSize = data['maxImageSize'] as int?;
    
    // Convert settings map to SettingsModel
    final settings = SettingsModel(
      cncWidth: settingsMap['cncWidth'],
      cncHeight: settingsMap['cncHeight'],
      markerXDistance: settingsMap['markerXDistance'],
      markerYDistance: settingsMap['markerYDistance'],
      toolDiameter: settingsMap['toolDiameter'],
      stepover: settingsMap['stepover'],
      safetyHeight: settingsMap['safetyHeight'],
      feedRate: settingsMap['feedRate'],
      plungeRate: settingsMap['plungeRate'],
      cuttingDepth: settingsMap['cuttingDepth'],
    );
    
    // Create temporary detector instance for this isolate
    final detector = SlabDetector(
      settings: settings,
      maxImageSize: maxImageSize ?? 1200,
    );
    
    // Process using the direct method
    return await detector._processImageDirect(imageBytes, settings);
  } catch (e, stackTrace) {
    print('Error in isolate: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}