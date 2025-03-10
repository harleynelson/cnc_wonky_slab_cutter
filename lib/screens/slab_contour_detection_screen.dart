import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/gcode/machine_coordinates.dart';
import '../services/image_processing/contour_detection/contour_detector_registry.dart';
import '../services/image_processing/slab_contour_result.dart';
import '../services/image_processing/marker_detector.dart';

class SlabContourDetectionScreen extends StatefulWidget {
  final File imageFile;
  final SettingsModel settings;

  const SlabContourDetectionScreen({
    Key? key,
    required this.imageFile,
    required this.settings,
  }) : super(key: key);

  @override
  _SlabContourDetectionScreenState createState() => _SlabContourDetectionScreenState();
}

class _SlabContourDetectionScreenState extends State<SlabContourDetectionScreen> {
  bool _isProcessing = false;
  img.Image? _sourceImage;
  MarkerDetectionResult? _markerResult;
  SlabContourResult? _contourResult;
  String _currentDetector = '';
  List<String> _availableDetectors = [];
  String _statusMessage = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadImage();
    _initDetectors();
  }

  void _initDetectors() {
    ContourDetectorRegistry.initialize();
    _availableDetectors = ContourDetectorRegistry.getAvailableDetectors();
    _currentDetector = _availableDetectors.isNotEmpty ? _availableDetectors.first : '';
  }

  Future<void> _loadImage() async {
    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Loading image...';
      });

      final bytes = await widget.imageFile.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        setState(() {
          _errorMessage = 'Failed to decode image';
          _isProcessing = false;
        });
        return;
      }

      setState(() {
        _sourceImage = image;
        _statusMessage = 'Image loaded';
        _isProcessing = false;
      });

      // Detect markers automatically
      await _detectMarkers();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading image: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _detectMarkers() async {
    if (_sourceImage == null) return;

    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Detecting markers...';
      });

      final markerDetector = MarkerDetector(
        markerRealDistanceMm: widget.settings.markerXDistance,
        generateDebugImage: true,
      );

      final result = await markerDetector.detectMarkers(_sourceImage!);

      setState(() {
        _markerResult = result;
        _statusMessage = 'Markers detected';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error detecting markers: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _detectContour() async {
    if (_sourceImage == null || _markerResult == null) {
      setState(() {
        _errorMessage = 'Marker detection required before contour detection';
      });
      return;
    }

    try {
      setState(() {
        _isProcessing = true;
        _statusMessage = 'Detecting contour with ${_currentDetector}...';
        _errorMessage = '';
      });

      // Create coordinate system from marker detection
      final coordinateSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
        _markerResult!.markers[0].toPoint(),
        _markerResult!.markers[1].toPoint(),
        _markerResult!.markers[2].toPoint(),
        widget.settings.markerXDistance,
        widget.settings.markerYDistance
      );

      // Get the current detector
      ContourDetectorRegistry.setCurrentDetector(_currentDetector);
      final detector = ContourDetectorRegistry.getCurrentDetector();

      // Detect contour
      final result = await detector.detectContour(_sourceImage!, coordinateSystem);

      setState(() {
        _contourResult = result;
        _statusMessage = 'Contour detected with ${detector.name}';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error detecting contour: $e';
        _isProcessing = false;
      });
    }
  }

  void _acceptContour() {
    if (_contourResult == null) {
      setState(() {
        _errorMessage = 'No contour detected yet';
      });
      return;
    }

    final processingProvider = Provider.of<ProcessingProvider>(context, listen: false);
    if (processingProvider.flowManager != null) {
      // Store the contour result in the processing flow
      processingProvider.flowManager!.updateContourResult(_contourResult!);
      
      // Navigate back
      Navigator.pop(context, true);
    } else {
      setState(() {
        _errorMessage = 'Processing flow not initialized';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Contour Detection'),
        actions: [
          if (_contourResult != null)
            IconButton(
              icon: Icon(Icons.check),
              tooltip: 'Accept Contour',
              onPressed: _acceptContour,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildDetectorSelector(),
          Expanded(
            child: _buildMainContent(),
          ),
          _buildStatusBar(),
          _buildControlButtons(),
        ],
      ),
    );
  }

  Widget _buildDetectorSelector() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Text('Detection Method:'),
          SizedBox(width: 16),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _currentDetector,
              items: _availableDetectors.map((String strategy) {
                return DropdownMenuItem<String>(
                  value: strategy,
                  child: Text(strategy),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _currentDetector = newValue;
                  });
                }
              },
            ),
          ),
          SizedBox(width: 16),
          ElevatedButton(
            onPressed: _isProcessing ? null : _detectContour,
            child: Text('Detect'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(_statusMessage),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              SizedBox(height: 16),
              Text(
                _errorMessage,
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Show the appropriate debug image
    if (_contourResult?.debugImage != null) {
      final debugImage = _contourResult!.debugImage!;
      final imgBytes = img.encodePng(debugImage);
      
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(Uint8List.fromList(imgBytes)),
        ),
      );
    } else if (_markerResult?.debugImage != null) {
      final debugImage = _markerResult!.debugImage!;
      final imgBytes = img.encodePng(debugImage);
      
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(Uint8List.fromList(imgBytes)),
        ),
      );
    } else if (_sourceImage != null) {
      final imgBytes = img.encodePng(_sourceImage!);
      
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(Uint8List.fromList(imgBytes)),
        ),
      );
    }

    return Center(
      child: Text('No image loaded'),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      color: Colors.grey.shade200,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            _isProcessing ? Icons.sync : (_errorMessage.isNotEmpty ? Icons.error : Icons.info),
            color: _errorMessage.isNotEmpty ? Colors.red : Colors.blue,
            size: 16,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: _errorMessage.isNotEmpty ? Colors.red : Colors.black87,
              ),
            ),
          ),
          if (_contourResult != null)
            Text(
              'Points: ${_contourResult!.pointCount}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: Icon(Icons.refresh),
              label: Text('Detect Markers'),
              onPressed: _isProcessing ? null : _detectMarkers,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(Icons.check),
              label: Text('Use This Contour'),
              onPressed: _isProcessing || _contourResult == null ? null : _acceptContour,
            ),
          ),
        ],
      ),
    );
  }
}