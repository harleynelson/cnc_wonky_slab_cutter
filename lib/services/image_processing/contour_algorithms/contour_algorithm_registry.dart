// lib/services/image_processing/contour_algorithms/contour_algorithm_registry.dart
// Registry to manage all available contour detection algorithms

import 'contour_algorithm_interface.dart';
import 'color_contour_algorithm.dart';
import 'edge_contour_algorithm.dart';
import 'threshold_contour_algorithm.dart';

/// Registry of all available contour detection algorithms
class ContourAlgorithmRegistry {
  static final Map<String, ContourDetectionAlgorithm> _algorithms = {};
  static String _currentAlgorithm = '';
  
  /// Initialize the registry with all available algorithms
  static void initialize() {
    if (_algorithms.isNotEmpty) {
      // Clear existing algorithms to ensure fresh initialization
      _algorithms.clear();
    }
    
    // Register all available algorithms with consistent parameters
    registerAlgorithm(ThresholdContourAlgorithm(
      generateDebugImage: true,
      regionGrowThreshold: 40,
      useConvexHull: true,
      simplificationEpsilon: 5.0,
      removeHoles: true,
    ));
    
    registerAlgorithm(EdgeContourAlgorithm(
      generateDebugImage: true,
      edgeThreshold: 50,
      useConvexHull: true,
      simplificationEpsilon: 5.0,
    ));
    
    registerAlgorithm(ColorContourAlgorithm(
      generateDebugImage: true,
      colorThreshold: 35.0,
      useConvexHull: true,
      simplificationEpsilon: 5.0,
    ));
    
    // Set default algorithm
    if (_currentAlgorithm.isEmpty && _algorithms.isNotEmpty) {
      _currentAlgorithm = _algorithms.keys.first;
    }
  }
  
  /// Register a new detection algorithm
  static void registerAlgorithm(ContourDetectionAlgorithm algorithm) {
    _algorithms[algorithm.name] = algorithm;
  }
  
  /// Get the current active algorithm
  static ContourDetectionAlgorithm getCurrentAlgorithm() {
    initialize();
    return _algorithms[_currentAlgorithm] ?? _algorithms.values.first;
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
    }
  }
  
  /// Get all available algorithm names
  static List<String> getAvailableAlgorithms() {
    initialize();
    return _algorithms.keys.toList();
  }
}