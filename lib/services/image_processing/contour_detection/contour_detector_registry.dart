import 'contour_detector_interface.dart';
import 'threshold_contour_detector.dart';
import 'edge_contour_detector.dart';
import 'color_contour_detector.dart';

/// Registry of all available contour detection strategies
class ContourDetectorRegistry {
  static final Map<String, ContourDetectorStrategy> _detectors = {};
  static String _currentStrategy = '';
  
  /// Initialize the registry with all available strategies
  static void initialize() {
    if (_detectors.isNotEmpty) return;
    
    // Register all available detectors
    registerDetector(ThresholdContourDetector());
    registerDetector(EdgeContourDetector());
    registerDetector(ColorContourDetector());
    
    // Set default strategy
    if (_currentStrategy.isEmpty && _detectors.isNotEmpty) {
      _currentStrategy = _detectors.keys.first;
    }
  }
  
  /// Register a new detector strategy
  static void registerDetector(ContourDetectorStrategy detector) {
    _detectors[detector.name] = detector;
  }
  
  /// Get the current active detector strategy
  static ContourDetectorStrategy getCurrentDetector() {
    initialize();
    return _detectors[_currentStrategy] ?? _detectors.values.first;
  }
  
  /// Set the current active detector strategy by name
  static void setCurrentDetector(String strategyName) {
    initialize();
    if (_detectors.containsKey(strategyName)) {
      _currentStrategy = strategyName;
    }
  }
  
  /// Get all available detector strategy names
  static List<String> getAvailableDetectors() {
    initialize();
    return _detectors.keys.toList();
  }
}