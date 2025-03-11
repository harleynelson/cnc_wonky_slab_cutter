// lib/services/image_processing/contour_algorithms/contour_algorithm_registry.dart
// Registry to manage all available contour detection algorithms

import 'contour_algorithm_interface.dart';
import 'color_contour_algorithm.dart';
import 'edge_contour_algorithm.dart';
import 'threshold_contour_algorithm.dart';
import 'default_contour_algorithm.dart';

/// Registry of all available contour detection algorithms
class ContourAlgorithmRegistry {
  static final Map<String, ContourDetectionAlgorithm> _algorithms = {};
  static String _currentAlgorithm = 'Default';  // Set Default as initial current algorithm
  
  /// Initialize the registry with all available algorithms
  static void initialize() {
    if (_algorithms.isNotEmpty) return;
    
    print('Initializing contour algorithm registry...');
    
    // Clear algorithms first to avoid duplicates
    _algorithms.clear();
    
    // Register all available algorithms
    final defaultAlgorithm = DefaultContourAlgorithm();
    print('Registering ${defaultAlgorithm.name} algorithm');
    _algorithms[defaultAlgorithm.name] = defaultAlgorithm;
    
    registerAlgorithm(ThresholdContourAlgorithm());
    registerAlgorithm(EdgeContourAlgorithm());
    registerAlgorithm(ColorContourAlgorithm());
    
    // Explicitly set default algorithm
    if (_currentAlgorithm.isEmpty && _algorithms.isNotEmpty) {
      _currentAlgorithm = 'Default';
    }
    
    // Print registered algorithms for debugging
    print('Registered algorithms: ${_algorithms.keys.join(', ')}');
  }
  
  /// Register a new detection algorithm
  static void registerAlgorithm(ContourDetectionAlgorithm algorithm) {
    print('Registering ${algorithm.name} algorithm');
    _algorithms[algorithm.name] = algorithm;
  }
  
  /// Get the current active algorithm
  static ContourDetectionAlgorithm getCurrentAlgorithm() {
    initialize();
    final algorithm = _algorithms[_currentAlgorithm];
    if (algorithm == null) {
      print('Warning: Current algorithm "$_currentAlgorithm" not found. Using first available.');
      return _algorithms.values.first;
    }
    return algorithm;
  }
  
  /// Get an algorithm by name
  static ContourDetectionAlgorithm? getAlgorithm(String name) {
    initialize();
    return _algorithms[name];
  }
  
  /// Set the current active algorithm by name
  static void setCurrentAlgorithm(String algorithmName) {
    initialize();
    if (_algorithms.containsKey(algorithmName)) {
      _currentAlgorithm = algorithmName;
      print('Set current algorithm to: $algorithmName');
    } else {
      print('Warning: Algorithm "$algorithmName" not found. Current algorithm remains: $_currentAlgorithm');
    }
  }
  
  /// Get all available algorithm names
  static List<String> getAvailableAlgorithms() {
    initialize();
    final algorithms = _algorithms.keys.toList();
    print('Available algorithms: ${algorithms.join(', ')}');
    return algorithms;
  }
}