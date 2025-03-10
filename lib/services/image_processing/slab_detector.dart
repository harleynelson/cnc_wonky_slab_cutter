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
            'markerDistance': settings.markerDistance,
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
    
    // Resize large images to conserve memory
    img.Image processImage = image;
    if (image.width > maxImageSize || image.height > maxImageSize) {
      final scaleFactor = maxImageSize / math.max(image.width, image.height);
      try {
        processImage = img.copyResize(
          image,
          width: (image.width * scaleFactor).round(),
          height: (image.height * scaleFactor).round(),
          interpolation: img.Interpolation.average
        );
      } catch (e) {
        print('Warning: Failed to resize image: $e');
        // Continue with original image if resize fails
        processImage = image;
      }
    }
    
    // Create a copy for visualization
    final outputImage = img.copyResize(processImage, width: processImage.width, height: processImage.height);
    
    // 1. Detect markers with the improved marker detector
    final markerDetector = MarkerDetector(
      markerRealDistanceMm: settings.markerDistance,
      generateDebugImage: true,
      maxImageSize: maxImageSize,
    );
    
    print('Detecting markers...');
    final markerResult = await markerDetector.detectMarkers(processImage);
    
    // Create coordinate system from marker detection
    final coordinateSystem = MachineCoordinateSystem.fromMarkerPoints(
      markerResult.markers[0].toPoint(),
      markerResult.markers[1].toPoint(),
      markerResult.markers[2].toPoint(),
      settings.markerDistance,
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
    
    // 2. Detect slab contour with the new contour detector
    final contourDetector = SlabContourDetector(
      generateDebugImage: true,
      maxImageSize: maxImageSize,
    );
    
    print('Detecting slab contour...');
    final contourResult = await contourDetector.detectContour(processImage, coordinateSystem);
    
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
    final machineContourPixels = coordinateSystem.convertPointListToPixelCoords(
      contourResult.machineContour
    );
    
    try {
      for (int i = 0; i < machineContourPixels.length - 1; i++) {
        final p1 = machineContourPixels[i];
        final p2 = machineContourPixels[i + 1];
        
        _drawLine(
          outputImage,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          img.ColorRgba8(0, 255, 0, 255) // Green
        );
      }
    } catch (e) {
      print('Error drawing machine contour: $e');
    }
    
    // 3. Generate toolpath
    print('Generating toolpath...');
    final toolpath = ToolpathGenerator.generatePocketToolpath(
      contourResult.machineContour,
      settings.toolDiameter,
      settings.stepover,
    );
    
    try {
      // Draw toolpath on output image
      final toolpathPixels = coordinateSystem.convertPointListToPixelCoords(toolpath);
      
      for (int i = 0; i < toolpathPixels.length - 1; i++) {
        final p1 = toolpathPixels[i];
        final p2 = toolpathPixels[i + 1];
        
        _drawLine(
          outputImage,
          p1.x.round(), p1.y.round(),
          p2.x.round(), p2.y.round(),
          img.ColorRgba8(0, 0, 255, 255) // Blue
        );
      }
    } catch (e) {
      print('Error drawing toolpath: $e');
    }
    
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
      _drawText(
        outputImage, 
        "Area: ${contourResult.machineArea.toStringAsFixed(2)} sq mm", 
        10, 
        10, 
        img.ColorRgba8(255, 255, 255, 255)
      );
      
      _drawText(
        outputImage, 
        "Toolpath length: ${_calculatePathLength(toolpath).toStringAsFixed(2)} mm", 
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
      slabContour: contourResult.machineContour,
      toolpath: toolpath,
      contourAreaMm2: contourResult.machineArea,
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
  
  /// Calculate total length of a toolpath
  double _calculatePathLength(List<Point> path) {
    double length = 0.0;
    
    try {
      for (int i = 0; i < path.length - 1; i++) {
        final dx = path[i + 1].x - path[i].x;
        final dy = path[i + 1].y - path[i].y;
        length += math.sqrt(dx * dx + dy * dy);
      }
    } catch (e) {
      print('Error calculating path length: $e');
    }
    
    return length;
  }
  
  /// Draw a line between two points
  void _drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
    // Validate coordinates
    if (x1 < 0 || x1 >= image.width || y1 < 0 || y1 >= image.height ||
        x2 < 0 || x2 >= image.width || y2 < 0 || y2 >= image.height) {
      // Clip line to image boundaries
      // Simple approach: just return if any coordinate is outside
      // A more sophisticated approach would clip the line, but that's more complex
      return;
    }
    
    try {
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
  
  /// Draw text on the image (simplified implementation)
  void _drawText(img.Image image, String text, int x, int y, img.Color color) {
    // A basic implementation of text rendering
    // In a real app, you would use a proper font renderer
    final textWidth = text.length * 6;
    final textHeight = 12;
    
    try {
      // Draw a background for better readability
      for (int py = y - 1; py < y + textHeight + 1; py++) {
        for (int px = x - 1; px < x + textWidth + 1; px++) {
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, img.ColorRgba8(0, 0, 0, 200));
          }
        }
      }
      
      // Simple pixel-based font (just a proof of concept)
      for (int i = 0; i < text.length; i++) {
        final char = text.codeUnitAt(i);
        
        // Draw a simple pixel representation of the character
        final charX = x + i * 6;
        
        if (charX + 5 >= image.width) break;
        
        for (int py = 0; py < 8; py++) {
          for (int px = 0; px < 5; px++) {
            if (_getCharPixel(char, px, py)) {
              final screenX = charX + px;
              final screenY = y + py;
              
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
  bool _getCharPixel(int charCode, int x, int y) {
    if (x < 0 || y < 0 || x >= 5 || y >= 8) return false;
    
    // Show only for certain characters like numbers and letters
    if (charCode >= 48 && charCode <= 57) { // 0-9
      if (x == 0 || x == 4 || y == 0 || y == 7) return true;
      return charCode == 56; // 8 is filled
    } else if (charCode >= 65 && charCode <= 90) { // A-Z
      return (x == 0 || x == 4 || y == 0 || y == 3);
    } else if (charCode >= 97 && charCode <= 122) { // a-z
      return (x == 0 || x == 4 || y == 3 || y == 7);
    } else if (charCode == 46) { // .
      return (x == 2 && y == 7);
    } else if (charCode == 58) { // :
      return (x == 2 && (y == 2 || y == 6));
    } else if (charCode == 32) { // space
      return false;
    }
    
    // Default pattern for other chars
    return (x % 2 == 0 && y % 2 == 0);
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
      markerDistance: settingsMap['markerDistance'],
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