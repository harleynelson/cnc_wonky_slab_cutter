import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../gcode/machine_coordinates.dart';
import '../gcode/gcode_generator.dart';
import 'marker_detector.dart';
// Import with prefix to avoid naming conflicts
import 'image_utils.dart' as img_utils;
import '../../models/settings_model.dart';

/// Result of the slab processing operation
class SlabProcessingResult {
  final File processedImage;
  final File gcodeFile;
  final List<Point> slabContour;
  final List<Point> toolpath;

  SlabProcessingResult({
    required this.processedImage,
    required this.gcodeFile,
    required this.slabContour,
    required this.toolpath,
  });
}

/// Class for detecting slab outlines in images
class SlabDetector {
  final SettingsModel settings;
  
  SlabDetector({required this.settings});
  
  /// Process an image to detect slab outline and generate G-code
  Future<SlabProcessingResult> processImage(File imageFile) async {
    // This would normally be a complex operation using computer vision
    // We'll use a simplified approach for now
    
    // Process on background thread
    return compute(_processImageIsolate, {
      'imagePath': imageFile.path,
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
      }
    });
  }
}

/// Function to process the image in an isolate (separate thread)
Future<SlabProcessingResult> _processImageIsolate(Map<String, dynamic> data) async {
  final String imagePath = data['imagePath'];
  final Map<String, dynamic> settingsMap = data['settings'];
  
  // Load the image
  final bytes = await File(imagePath).readAsBytes();
  final image = img.decodeImage(bytes);
  
  if (image == null) {
    throw Exception('Failed to decode image');
  }
  
  // Create a copy of the image for visualization
  final outputImage = img.copyResize(image, width: image.width, height: image.height);
  
  // 1. Detect markers
  final markerDetector = MarkerDetector(
    markerRealDistanceMm: settingsMap['markerDistance'],
  );
  
  // For simplicity, we'll create predefined markers
  final markers = [
    MarkerPoint(
      (image.width * 0.2).round(), 
      (image.height * 0.2).round(), 
      MarkerRole.origin
    ),
    MarkerPoint(
      (image.width * 0.8).round(), 
      (image.height * 0.2).round(), 
      MarkerRole.xAxis
    ),
    MarkerPoint(
      (image.width * 0.2).round(), 
      (image.height * 0.8).round(), 
      MarkerRole.scale
    ),
  ];
  
  // Calculate calibration parameters
  final originMarker = markers.firstWhere((m) => m.role == MarkerRole.origin);
  final xAxisMarker = markers.firstWhere((m) => m.role == MarkerRole.xAxis);
  final scaleMarker = markers.firstWhere((m) => m.role == MarkerRole.scale);
  
  final coordinateSystem = MachineCoordinateSystem.fromMarkerPoints(
    Point(originMarker.x.toDouble(), originMarker.y.toDouble()),
    Point(xAxisMarker.x.toDouble(), xAxisMarker.y.toDouble()),
    Point(scaleMarker.x.toDouble(), scaleMarker.y.toDouble()),
    settingsMap['markerDistance'],
  );
  
  // Visualize markers
  for (final marker in markers) {
    // Draw marker
    img_utils.ImageUtils.drawCross(
      outputImage, 
      marker.x, 
      marker.y, 
      img_utils.ImageUtils.colorRed, 
      10
    );
  }
  
  // 2. Detect slab contour
  final slabContour = _detectSlabContour(image);
  
  // Convert from img_utils.Point to our Point for drawing
  final drawableContour = slabContour.map((p) => 
    img_utils.Point(p.x, p.y)
  ).toList();
  
  // Visualize contour
  img_utils.ImageUtils.drawContour(
    outputImage, 
    drawableContour, 
    img_utils.ImageUtils.colorGreen
  );
  
  // 3. Convert contour to machine coordinates
  final machineContour = coordinateSystem.convertPointListToMachineCoords(slabContour);
  
  // 4. Generate toolpath
  final toolpath = ToolpathGenerator.generatePocketToolpath(
    machineContour,
    settingsMap['toolDiameter'],
    settingsMap['stepover'],
  );
  
  // Visualize toolpath (convert back to pixel coordinates for display)
  final displayToolpath = coordinateSystem.convertPointListToPixelCoords(toolpath);
  
  // Convert for drawing
  final drawableToolpath = displayToolpath.map((p) => 
    img_utils.Point(p.x, p.y)
  ).toList();
  
  img_utils.ImageUtils.drawContour(
    outputImage, 
    drawableToolpath, 
    img_utils.ImageUtils.colorBlue
  );
  
  // 5. Generate G-code
  final gcodeGenerator = GcodeGenerator(
    safetyHeight: settingsMap['safetyHeight'],
    feedRate: settingsMap['feedRate'],
    plungeRate: settingsMap['plungeRate'],
    cuttingDepth: settingsMap['cuttingDepth'],
  );
  
  final gcodeContent = gcodeGenerator.generateGcode(toolpath);
  
  // Save processed image
  final tempDir = await getTemporaryDirectory();
  final processedImagePath = path.join(tempDir.path, 'processed_image.png');
  final processedImageFile = File(processedImagePath);
  await processedImageFile.writeAsBytes(img.encodePng(outputImage));
  
  // Save G-code to file
  final gcodePath = path.join(tempDir.path, 'slab_surfacing.gcode');
  final gcodeFile = File(gcodePath);
  await gcodeFile.writeAsString(gcodeContent);
  
  return SlabProcessingResult(
    processedImage: processedImageFile,
    gcodeFile: gcodeFile,
    slabContour: machineContour,
    toolpath: toolpath,
  );
}

/// Detect the slab contour in the image
List<Point> _detectSlabContour(img.Image image) {
  // This would normally use computer vision techniques like edge detection
  // For now, we'll create a simulated contour
  
  final centerX = image.width * 0.5;
  final centerY = image.height * 0.5;
  final radius = image.width * 0.3;
  
  final numPoints = 20;
  final contour = <Point>[];
  
  for (int i = 0; i < numPoints; i++) {
    final angle = i * 2 * 3.14159 / numPoints;
    // Add some randomness to make it look like a natural slab
    final r = radius * (0.8 + 0.2 * (i % 3) / 3);
    final x = centerX + r * math.cos(angle);
    final y = centerY + r * math.sin(angle);
    contour.add(Point(x, y));
  }
  
  return contour;
}
