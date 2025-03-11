// lib/services/image_processing/slab_detector.dart
// Orchestrator class for the complete slab processing workflow

import 'dart:io';
import 'dart:async';
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
    try {
      await processedImage.exists();
      await gcodeFile.exists();
    } catch (e) {
      print('Error disposing SlabProcessingResult: $e');
    }
  }
}

/// Main orchestrator class for the entire slab detection and processing workflow
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
      final bytes = await imageFile.readAsBytes();
      
      if (kIsWeb) {
        return _processImageDirect(bytes, settings);
      }
      
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
        print('Isolate processing failed: $isolateError');
        return _processImageDirect(bytes, settings);
      }
    } catch (e, stackTrace) {
      final errorMessage = 'Error processing image: ${e.toString()}\n$stackTrace';
      print(errorMessage);
      throw Exception(errorMessage);
    }
  }
  
  /// Process the image directly in the main isolate (fallback method)
  Future<SlabProcessingResult> _processImageDirect(List<int> bytes, SettingsModel settings) async {
    print('Processing image directly (no isolate)');
    
    // STEP 1: Load and prepare image
    final image = img.decodeImage(Uint8List.fromList(bytes));
    if (image == null) {
      throw Exception('Failed to decode image - invalid format or corrupted file');
    }

    img.Image processImage = image;
    if (image.width > maxImageSize || image.height > maxImageSize) {
      processImage = ImageUtils.safeResize(image, maxSize: maxImageSize);
    }
    
    final outputImage = img.copyResize(processImage, width: processImage.width, height: processImage.height);
    
    // STEP 2: Detect markers 
    final markerDetector = MarkerDetector(
      markerRealDistanceMm: settings.markerXDistance,
      generateDebugImage: true,
      maxImageSize: maxImageSize,
    );
    
    final markerResult = await markerDetector.detectMarkers(processImage);
    
    final coordinateSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
      markerResult.markers[0].toPoint(),
      markerResult.markers[1].toPoint(),
      markerResult.markers[2].toPoint(),
      settings.markerXDistance,
      settings.markerYDistance
    );
    
    if (markerResult.debugImage != null) {
      _overlayDebugImage(outputImage, markerResult.debugImage!);
    }
    
    // STEP 3: Detect slab contour
    final contourDetector = SlabContourDetector(
      generateDebugImage: true,
      maxImageSize: maxImageSize,
      processingTimeout: 20000,
    );
    
    final contourResult = await contourDetector.detectContour(processImage, coordinateSystem);
    final cleanedContour = ContourDetectionUtils.ensureCleanOuterContour(contourResult.machineContour);
    
    if (contourResult.debugImage != null) {
      _overlayDebugImage(outputImage, contourResult.debugImage!, greenOnly: true);
    }
    
    // Draw machine contour on output image
    _drawContourOnImage(outputImage, cleanedContour, coordinateSystem, img.ColorRgba8(0, 255, 0, 255));
    
    // STEP 4: Generate toolpath
    final toolpath = _generateToolpath(cleanedContour, settings.toolDiameter, settings.stepover);
    _drawContourOnImage(outputImage, toolpath, coordinateSystem, img.ColorRgba8(0, 0, 255, 255));
    
    // STEP 5: Generate G-code
    final gcodeGenerator = GcodeGenerator(
      safetyHeight: settings.safetyHeight,
      feedRate: settings.feedRate,
      plungeRate: settings.plungeRate,
      cuttingDepth: settings.cuttingDepth,
    );
    
    final gcodeContent = gcodeGenerator.generateGcode(toolpath);
    
    // STEP 6: Add information overlay
    _addMetadataToImage(outputImage, cleanedContour, toolpath);
    
    // STEP 7: Save output files
    final processedImageFile = await _saveProcessedImage(outputImage);
    final gcodeFile = await _saveGcode(gcodeContent);
    
    return SlabProcessingResult(
      processedImage: processedImageFile,
      gcodeFile: gcodeFile,
      slabContour: cleanedContour,
      toolpath: toolpath,
      contourAreaMm2: GeometryUtils.polygonArea(cleanedContour),
    );
  }
  
  /// Draw contour on the output image
  void _drawContourOnImage(img.Image image, List<Point> contour, MachineCoordinateSystem coordSystem, img.Color color) {
    try {
      final pixelPoints = coordSystem.convertPointListToPixelCoords(contour);
      
      for (int i = 0; i < pixelPoints.length - 1; i++) {
        final p1 = pixelPoints[i];
        final p2 = pixelPoints[i + 1];
        
        DrawingUtils.drawLine(
          image,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          color
        );
      }
    } catch (e) {
      print('Error drawing contour: $e');
    }
  }
  
  /// Add metadata text to the output image
  void _addMetadataToImage(img.Image image, List<Point> contour, List<Point> toolpath) {
    try {
      DrawingUtils.drawText(
        image, 
        "Area: ${GeometryUtils.polygonArea(contour).toStringAsFixed(2)} sq mm", 
        10, 
        10, 
        img.ColorRgba8(255, 255, 255, 255)
      );
      
      DrawingUtils.drawText(
        image, 
        "Toolpath length: ${GeometryUtils.polygonPerimeter(toolpath).toStringAsFixed(2)} mm", 
        10, 
        30, 
        img.ColorRgba8(255, 255, 255, 255)
      );
    } catch (e) {
      print('Error adding metadata: $e');
    }
  }
  
  /// Save the processed image to a file
  Future<File> _saveProcessedImage(img.Image image) async {
    final tempDir = await getTemporaryDirectory();
    final processedImagePath = path.join(tempDir.path, 'processed_image.png');
    final file = File(processedImagePath);
    
    final imageData = img.encodePng(image);
    await file.writeAsBytes(imageData);
    
    return file;
  }
  
  /// Save the G-code to a file
  Future<File> _saveGcode(String gcodeContent) async {
    final tempDir = await getTemporaryDirectory();
    final gcodePath = path.join(tempDir.path, 'slab_surfacing.gcode');
    final file = File(gcodePath);
    
    await file.writeAsString(gcodeContent);
    
    return file;
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
            continue;
          }
        }
      }
    }
  }

  /// Generate a toolpath based on the contour
  List<Point> _generateToolpath(List<Point> contour, double toolDiameter, double stepover) {
    if (contour.length < 10) {
      return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
    }
    
    try {
      final boundingBox = GeometryUtils.calculateBoundingBox(contour);
      double minX = boundingBox['minX']!;
      double minY = boundingBox['minY']!;
      double maxX = boundingBox['maxX']!;
      double maxY = boundingBox['maxY']!;
      
      final inset = toolDiameter / 2;
      minX += inset;
      minY += inset;
      maxX -= inset;
      maxY -= inset;
      
      if (minX >= maxX || minY >= maxY) {
        return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
      }
      
      final width = maxX - minX;
      final height = maxY - minY;
      final horizontal = width > height;
      
      final toolpath = <Point>[];
      
      if (horizontal) {
        // Horizontal zigzag (moving along Y)
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
        // Vertical zigzag (moving along X)
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
      
      return ContourDetectionUtils.clipToolpathToContour(toolpath, contour);
    } catch (e) {
      print('Error generating toolpath: $e');
      return ToolpathGenerator.generatePocketToolpath(contour, toolDiameter, stepover);
    }
  }
}

/// Function to process the image in an isolate (separate thread)
Future<SlabProcessingResult> _processImageIsolate(Map<String, dynamic> data) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    final List<int> imageBytes = data['imageBytes'] as List<int>;
    final Map<String, dynamic> settingsMap = data['settings'] as Map<String, dynamic>;
    final int? maxImageSize = data['maxImageSize'] as int?;
    
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
    
    final detector = SlabDetector(
      settings: settings,
      maxImageSize: maxImageSize ?? 1200,
    );
    
    return await detector._processImageDirect(imageBytes, settings);
  } catch (e, stackTrace) {
    print('Error in isolate: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}