// lib/services/processing/processing_flow_manager.dart
// Manages the flow of image processing from capture to gcode generation

import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../models/settings_model.dart';
import '../image_processing/contour_algorithms/default_contour_algorithm.dart';
import '../image_processing/marker_detector.dart';
import '../image_processing/slab_contour_detector.dart';
import '../image_processing/slab_contour_result.dart';
import '../gcode/machine_coordinates.dart';
import '../gcode/gcode_generator.dart';
import '../../utils/general/error_utils.dart';

/// Represents the current state of the processing flow
enum ProcessingState {
  notStarted,
  markerDetection,
  slabDetection,
  gcodeGeneration,
  completed,
  error
}

/// Method used for contour detection
enum ContourDetectionMethod {
  automatic,
  interactive,
  manual
}

/// Result of the processing flow containing all intermediate and final results
class ProcessingResult {
  final File? originalImage;
  final img.Image? processedImage;
  final MarkerDetectionResult? markerResult;
  final SlabContourResult? contourResult;
  final List<Point>? toolpath;
  final String? gcode;
  final File? gcodeFile;
  final String? errorMessage;
  final ProcessingState state;
  final ContourDetectionMethod? contourMethod;
  
  ProcessingResult({
    this.originalImage,
    this.processedImage,
    this.markerResult,
    this.contourResult,
    this.toolpath,
    this.gcode,
    this.gcodeFile,
    this.errorMessage,
    this.state = ProcessingState.notStarted,
    this.contourMethod,
  });
  
  /// Create a copy with updated values
  ProcessingResult copyWith({
    File? originalImage,
    img.Image? processedImage,
    MarkerDetectionResult? markerResult,
    SlabContourResult? contourResult,
    List<Point>? toolpath,
    String? gcode,
    File? gcodeFile,
    String? errorMessage,
    ProcessingState? state,
    ContourDetectionMethod? contourMethod,
  }) {
    return ProcessingResult(
      originalImage: originalImage ?? this.originalImage,
      processedImage: processedImage ?? this.processedImage,
      markerResult: markerResult ?? this.markerResult,
      contourResult: contourResult ?? this.contourResult,
      toolpath: toolpath ?? this.toolpath,
      gcode: gcode ?? this.gcode,
      gcodeFile: gcodeFile ?? this.gcodeFile,
      errorMessage: errorMessage ?? this.errorMessage,
      state: state ?? this.state,
      contourMethod: contourMethod ?? this.contourMethod,
    );
  }
  
  /// Create a result in error state
  factory ProcessingResult.error(String errorMessage) {
    return ProcessingResult(
      errorMessage: errorMessage,
      state: ProcessingState.error,
    );
  }
  
  /// Check if the current state can proceed to the next step
  bool get canProceedToNextStep {
    switch (state) {
      case ProcessingState.notStarted:
        return originalImage != null;
      case ProcessingState.markerDetection:
        return markerResult != null;
      case ProcessingState.slabDetection:
        return contourResult != null;
      case ProcessingState.gcodeGeneration:
        return gcode != null;
      case ProcessingState.completed:
        return false;
      case ProcessingState.error:
        return false;
    }
  }
}

/// Manager class for handling the processing flow
class ProcessingFlowManager with ChangeNotifier {
  ProcessingResult _result = ProcessingResult();
  final SettingsModel settings;
  
  // Default contour detection method
  ContourDetectionMethod _preferredContourMethod = ContourDetectionMethod.interactive;
  
  ProcessingFlowManager({required this.settings});
  
  /// Current processing result
  ProcessingResult get result => _result;
  
  /// Current processing state
  ProcessingState get state => _result.state;
  
  /// Get preferred contour detection method
  ContourDetectionMethod get preferredContourMethod => _preferredContourMethod;
  
  /// Set preferred contour detection method
  set preferredContourMethod(ContourDetectionMethod method) {
    _preferredContourMethod = method;
    notifyListeners();
  }
  
  /// Initialize with an image file
  Future<void> initWithImage(File imageFile) async {
    _result = ProcessingResult(
      originalImage: imageFile,
      state: ProcessingState.notStarted,
    );
    notifyListeners();
  }
  
  /// Process markers in the image
  Future<void> detectMarkers() async {
    if (_result.originalImage == null) {
      _setErrorState('No image available for marker detection');
      return;
    }
    
    try {
      _updateState(ProcessingState.markerDetection);
      
      // Load image
      final imageBytes = await _result.originalImage!.readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        _setErrorState('Failed to decode image');
        return;
      }
      
      // Create marker detector
      final markerDetector = MarkerDetector(
        markerRealDistanceMm: settings.markerXDistance,
        generateDebugImage: true,
      );
      
      // Process image to detect markers - this should not modify the original image
      final markerResult = await markerDetector.detectMarkers(image);
      
      // Update result but keep original image intact
      _result = _result.copyWith(
        processedImage: image, // Keep original image without markers drawn on it
        markerResult: markerResult,
      );
      
      notifyListeners();
    } catch (e, stackTrace) {
      ErrorUtils().logError(
        'Error during marker detection',
        e,
        stackTrace: stackTrace,
        context: 'marker_detection',
      );
      _setErrorState('Marker detection failed: ${e.toString()}');
    }
  }
  
  /// Process slab contour detection using automatic method
  Future<void> detectSlabContourAutomatic() async {
  if (_result.markerResult == null || _result.processedImage == null) {
    _setErrorState('Marker detection must be completed first');
    return;
  }
  
  try {
    _updateState(ProcessingState.slabDetection);
    
    // Create coordinate system from marker detection result
    final markerResult = _result.markerResult!;
    final coordinateSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
      markerResult.markers[0].toPoint(),  // Origin
      markerResult.markers[1].toPoint(),  // X-axis
      markerResult.markers[2].toPoint(),  // Scale/Y-axis
      settings.markerXDistance,
      settings.markerYDistance
    );
    
    // Use our default contour algorithm (better for wood slabs)
    final contourAlgorithm = DefaultContourAlgorithm(
      // Default parameters that work well for wood slabs
      contrastEnhancementFactor: 1.8,
      blurRadius: 3,
      edgeThreshold: 40,
      morphologySize: 3,
      useDarkBackgroundDetection: true,
      simplifyEpsilon: 3.0,
      smoothingWindowSize: 5,
    );
    
    // Estimate a seed point in the center of the image
    final seedX = _result.processedImage!.width ~/ 2;
    final seedY = _result.processedImage!.height ~/ 2;
    
    // Process image to detect slab contour
    final contourResult = await contourAlgorithm.detectContour(
      _result.processedImage!,
      seedX,
      seedY,
      coordinateSystem
    );
    
    // Create composite visualization image
    final compositeImage = _createCompositeImage(
      _result.processedImage!,
      markerResult.debugImage,
      contourResult.debugImage
    );
    
    // Update result
    _result = _result.copyWith(
      contourResult: contourResult,
      processedImage: compositeImage,
      contourMethod: ContourDetectionMethod.automatic,
    );
    
    notifyListeners();
  } catch (e, stackTrace) {
    ErrorUtils().logError(
      'Error during automatic slab contour detection',
      e,
      stackTrace: stackTrace,
      context: 'slab_detection_automatic',
    );
    _setErrorState('Automatic slab detection failed: ${e.toString()}');
  }
}

  void clearDebugImages() {
    _result = _result.copyWith(
      processedImage: null,
    );
    notifyListeners();
  }
  
  /// Process slab contour detection
  Future<void> detectSlabContour() async {
  // Use the preferred method
  switch (_preferredContourMethod) {
    case ContourDetectionMethod.automatic:
      await detectSlabContourAutomatic();
      break;
    case ContourDetectionMethod.interactive:
      // Interactive method is handled by the UI via updateContourResult
      _updateState(ProcessingState.slabDetection);
      notifyListeners();
      break;
    case ContourDetectionMethod.manual:
      // Manual method is handled by the UI via updateContourResult
      _updateState(ProcessingState.slabDetection);
      notifyListeners();
      break;
  }
}
  
  /// Update contour result from external source (interactive or manual methods)
  void updateContourResult(SlabContourResult contourResult, {ContourDetectionMethod? method}) {
    final usedMethod = method ?? _preferredContourMethod;
    
    _result = _result.copyWith(
      contourResult: contourResult,
      processedImage: contourResult.debugImage ?? _result.processedImage,
      state: ProcessingState.slabDetection,
      contourMethod: usedMethod,
    );
    
    notifyListeners();
  }
  
  /// Generate toolpath and G-code
  Future<void> generateGcode() async {
    if (_result.contourResult == null) {
      _setErrorState('Slab contour detection must be completed first');
      return;
    }
    
    try {
      _updateState(ProcessingState.gcodeGeneration);
      
      final contourResult = _result.contourResult!;
      
      // Generate toolpath
      final toolpath = _generateToolpath(
        contourResult.machineContour,
        settings.toolDiameter,
        settings.stepover
      );
      
      // Generate G-code
      final gcodeGenerator = GcodeGenerator(
        safetyHeight: settings.safetyHeight,
        feedRate: settings.feedRate,
        plungeRate: settings.plungeRate,
        cuttingDepth: settings.cuttingDepth,
      );
      
      final gcode = gcodeGenerator.generateGcode(toolpath);
      
      // Save G-code to file
      final tempDir = await Directory.systemTemp.createTemp('gcode_');
      final gcodeFile = File('${tempDir.path}/slab_surfacing.gcode');
      await gcodeFile.writeAsString(gcode);
      
      // Update result
      _result = _result.copyWith(
        toolpath: toolpath,
        gcode: gcode,
        gcodeFile: gcodeFile,
        state: ProcessingState.completed,
      );
      
      notifyListeners();
    } catch (e, stackTrace) {
      ErrorUtils().logError(
        'Error during G-code generation',
        e,
        stackTrace: stackTrace,
        context: 'gcode_generation',
      );
      _setErrorState('G-code generation failed: ${e.toString()}');
    }
  }
  
  /// Reset the processing flow
  void reset() {
    _result = ProcessingResult();
    notifyListeners();
  }
  
  /// Move to the next step in the processing flow
  Future<void> proceedToNextStep() async {
  if (!_result.canProceedToNextStep) {
    return;
  }
  
  switch (_result.state) {
    case ProcessingState.notStarted:
      await detectMarkers();
      break;
    case ProcessingState.markerDetection:
      // Skip ahead to interactive contour detection
      _updateState(ProcessingState.slabDetection);
      break;
    case ProcessingState.slabDetection:
      await generateGcode();
      break;
    case ProcessingState.gcodeGeneration:
      _updateState(ProcessingState.completed);
      break;
    case ProcessingState.completed:
    case ProcessingState.error:
      // No next step
      break;
  }
}
  
  /// Update the processing state
  void _updateState(ProcessingState newState) {
    _result = _result.copyWith(state: newState);
    notifyListeners();
  }
  
  /// Set error state with a message
  void _setErrorState(String errorMessage) {
    _result = _result.copyWith(
      errorMessage: errorMessage,
      state: ProcessingState.error,
    );
    notifyListeners();
  }
  
  /// Create a composite image with marker and contour visualizations
  img.Image _createCompositeImage(
    img.Image baseImage,
    img.Image? markerDebugImage,
    img.Image? contourDebugImage
  ) {
    // Create a copy of the base image
    final compositeImage = img.copyResize(
      baseImage,
      width: baseImage.width,
      height: baseImage.height
    );
    
    // Overlay marker detection visualization if available
    if (markerDebugImage != null) {
      _overlayDebugImage(compositeImage, markerDebugImage);
    }
    
    // Overlay contour detection visualization if available
    if (contourDebugImage != null) {
      _overlayDebugImage(compositeImage, contourDebugImage, greenOnly: true);
    }
    
    return compositeImage;
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
  
  /// Generate a toolpath for the contour
  List<Point> _generateToolpath(List<Point> contour, double toolDiameter, double stepover) {
    // Find the bounding box of the contour
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    
    for (final point in contour) {
      minX = min(minX, point.x);
      minY = min(minY, point.y);
      maxX = max(maxX, point.x);
      maxY = max(maxY, point.y);
    }
    
    // Inset by half tool diameter to account for tool radius
    final inset = toolDiameter / 2;
    minX += inset;
    minY += inset;
    maxX -= inset;
    maxY -= inset;
    
    // Generate zigzag pattern
    final toolpath = <Point>[];
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
    
    return toolpath;
  }
}

/// Utility functions
double min(double a, double b) => a < b ? a : b;
double max(double a, double b) => a > b ? a : b;