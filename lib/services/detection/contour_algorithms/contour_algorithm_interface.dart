// lib/services/image_processing/contour_detection/algorithms/contour_algorithm_interface.dart
// Interface for contour detection algorithms

import 'package:image/image.dart' as img;
import '../../../utils/general/machine_coordinates.dart';
import '../slab_contour_result.dart';

/// Interface for all contour detection algorithms
abstract class ContourDetectionAlgorithm {
  /// Algorithm name for dropdown display
  String get name;
  
  /// Detect a slab contour in the given image with seed point
  Future<SlabContourResult> detectContour(
    img.Image image, 
    int seedX,
    int seedY,
    MachineCoordinateSystem coordSystem
  );
}