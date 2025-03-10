import 'package:image/image.dart' as img;
import '../../gcode/machine_coordinates.dart';
import '../slab_contour_result.dart';

/// Interface for contour detection strategies
abstract class ContourDetectorStrategy {
  /// Strategy name for dropdown display
  String get name;
  
  /// Detect a slab contour in the given image
  Future<SlabContourResult> detectContour(
    img.Image image, 
    MachineCoordinateSystem coordSystem
  );
}