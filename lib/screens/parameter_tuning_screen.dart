// lib/screens/parameter_tuning_screen.dart
// Screen for interactive parameter tuning of contour detection algorithms

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../services/image_processing/contour_algorithms/default_contour_algorithm.dart';
import '../services/image_processing/marker_detector.dart';
import '../services/gcode/machine_coordinates.dart';
import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/processing/processing_flow_manager.dart';
import '../utils/image_processing/image_utils.dart';

class ParameterTuningScreen extends StatefulWidget {
  final File imageFile;
  final List<MarkerPoint> markers;
  final SettingsModel settings;
  final int seedX;
  final int seedY;

  const ParameterTuningScreen({
    Key? key,
    required this.imageFile,
    required this.markers,
    required this.settings,
    required this.seedX,
    required this.seedY,
  }) : super(key: key);

  @override
  _ParameterTuningScreenState createState() => _ParameterTuningScreenState();
}

class _ParameterTuningScreenState extends State<ParameterTuningScreen> {
  bool _isProcessing = false;
  img.Image? _originalImage;
  img.Image? _resultImage;
  
  // Parameter values
  double _contrastFactor = 1.5;
  int _blurRadius = 3;
  int _edgeThreshold = 30;
  int _morphologySize = 3;
  bool _useDarkBackground = true;
  double _simplifyEpsilon = 3.0;
  int _smoothingWindow = 5;
  
  @override
  void initState() {
    super.initState();
    _loadImage();
  }
  
  Future<void> _loadImage() async {
    setState(() {
      _isProcessing = true;
    });
    
    try {
      final bytes = await widget.imageFile.readAsBytes();
      _originalImage = img.decodeImage(bytes);
      
      if (_originalImage != null) {
        // Apply initial detection with default parameters
        await _processWithCurrentParameters();
      }
    } catch (e) {
      print('Error loading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading image: $e'))
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  Future<void> _processWithCurrentParameters() async {
    if (_originalImage == null) return;
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      // Create coordinate system
      final coordSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
        widget.markers[0].toPoint(),
        widget.markers[1].toPoint(),
        widget.markers[2].toPoint(),
        widget.settings.markerXDistance,
        widget.settings.markerYDistance
      );
      
      // Create algorithm with current parameters
      final algorithm = DefaultContourAlgorithm(
        contrastEnhancementFactor: _contrastFactor,
        blurRadius: _blurRadius,
        edgeThreshold: _edgeThreshold,
        morphologySize: _morphologySize,
        useDarkBackgroundDetection: _useDarkBackground,
        simplifyEpsilon: _simplifyEpsilon,
        smoothingWindowSize: _smoothingWindow,
      );
      
      // Run detection
      final result = await algorithm.detectContour(
        _originalImage!,
        widget.seedX,
        widget.seedY,
        coordSystem
      );
      
      setState(() {
        _resultImage = result.debugImage;
      });
      
      // Update flow manager with new contour if successful
      if (result.pixelContour.isNotEmpty) {
        final processingProvider = Provider.of<ProcessingProvider>(context, listen: false);
        if (processingProvider.flowManager != null) {
          processingProvider.flowManager!.updateContourResult(
            result,
            method: ContourDetectionMethod.interactive
          );
        }
      }
    } catch (e) {
      print('Error processing with parameters: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing: $e'))
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Parameter Tuning'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: () => Navigator.pop(context, true),
            tooltip: 'Save and Apply',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildPreviewArea(),
          ),
          _buildControlPanel(),
        ],
      ),
    );
  }
  
  Widget _buildPreviewArea() {
    if (_isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing with current parameters...'),
          ],
        ),
      );
    }
    
    if (_resultImage != null) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: Image.memory(
            img.encodePng(_resultImage!),
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    
    return Center(
      child: Text('No preview available'),
    );
  }
  
  Widget _buildControlPanel() {
    return Container(
      padding: EdgeInsets.all(16),
      color: Colors.grey[200],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Algorithm Parameters',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8),
          
          // Contrast Factor
          _buildParameterSlider(
            'Contrast Enhancement',
            _contrastFactor,
            1.0,
            3.0,
            (value) {
              setState(() {
                _contrastFactor = value;
              });
            },
          ),
          
          // Blur Radius
          _buildIntSlider(
            'Blur Radius',
            _blurRadius,
            1,
            7,
            (value) {
              setState(() {
                _blurRadius = value;
              });
            },
          ),
          
          // Edge Threshold
          _buildIntSlider(
            'Edge Threshold',
            _edgeThreshold,
            10,
            100,
            (value) {
              setState(() {
                _edgeThreshold = value;
              });
            },
          ),
          
          // Morphology Size
          _buildIntSlider(
            'Morphology Size',
            _morphologySize,
            1,
            7,
            (value) {
              setState(() {
                _morphologySize = value;
              });
            },
          ),
          
          // Simplify Epsilon
          _buildParameterSlider(
            'Simplify Epsilon',
            _simplifyEpsilon,
            1.0,
            10.0,
            (value) {
              setState(() {
                _simplifyEpsilon = value;
              });
            },
          ),
          
          // Smoothing Window
          _buildIntSlider(
            'Smoothing Window',
            _smoothingWindow,
            3,
            11,
            (value) {
              setState(() {
                _smoothingWindow = value;
              });
            },
            step: 2, // Only odd values
          ),
          
          // Dark Background
          Row(
            children: [
              Text('Use Dark Background Detection'),
              Spacer(),
              Switch(
                value: _useDarkBackground,
                onChanged: (value) {
                  setState(() {
                    _useDarkBackground = value;
                  });
                },
              ),
            ],
          ),
          
          SizedBox(height: 16),
          
          // Process Button
          ElevatedButton.icon(
            icon: Icon(Icons.refresh),
            label: Text('Process with Current Parameters'),
            onPressed: _isProcessing ? null : _processWithCurrentParameters,
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildParameterSlider(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value.toStringAsFixed(1)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: ((max - min) * 10).round(),
          onChanged: onChanged,
        ),
      ],
    );
  }
  
  Widget _buildIntSlider(
    String label,
    int value,
    int min,
    int max,
    Function(int) onChanged, {
    int step = 1,  
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('$value'),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: ((max - min) ~/ step),
          onChanged: (val) {
            // Round to nearest step
            int roundedValue = (val ~/ step) * step;
            if (roundedValue < min) roundedValue = min;
            if (roundedValue > max) roundedValue = max;
            onChanged(roundedValue);
          },
        ),
      ],
    );
  }
}