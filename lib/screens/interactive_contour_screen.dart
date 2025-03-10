// lib/screens/interactive_contour_screen.dart
// Interactive contour detection screen with user guidance and algorithm selection

import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/gcode/machine_coordinates.dart';
import '../services/processing/processing_flow_manager.dart';
import '../services/image_processing/slab_contour_result.dart';
import '../services/image_processing/marker_detector.dart';
import '../services/image_processing/contour_detection/algorithms/contour_algorithm_registry.dart';
import '../services/image_processing/contour_detection/algorithms/contour_algorithm_interface.dart';

class InteractiveContourScreen extends StatefulWidget {
  final File imageFile;
  final MarkerDetectionResult markerResult;
  final SettingsModel settings;

  const InteractiveContourScreen({
    Key? key,
    required this.imageFile,
    required this.markerResult,
    required this.settings,
  }) : super(key: key);

  @override
  _InteractiveContourScreenState createState() => _InteractiveContourScreenState();
}

class _InteractiveContourScreenState extends State<InteractiveContourScreen> {
  bool _isProcessing = false;
  bool _hasSelectedPoint = false;
  Offset? _selectedPoint;
  img.Image? _sourceImage;
  Uint8List? _displayImageBytes;
  Uint8List? _resultImageBytes;
  List<Point>? _contourPoints;
  List<Point>? _contourMachinePoints;
  String _statusMessage = 'Tap on the slab to begin contour detection';
  String _errorMessage = '';
  String _selectedAlgorithm = '';

  // UI parameters
  final double _touchRadius = 15.0;
  
  // Coordinate system
  late MachineCoordinateSystem _coordinateSystem;
  
  // Available detection algorithms
  List<String> _availableAlgorithms = [];

  @override
  void initState() {
    super.initState();
    
    // Initialize coordinate system
    _coordinateSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
      widget.markerResult.markers[0].toPoint(),  // Origin
      widget.markerResult.markers[1].toPoint(),  // X-axis
      widget.markerResult.markers[2].toPoint(),  // Scale/Y-axis
      widget.settings.markerXDistance,
      widget.settings.markerYDistance
    );
    
    // Initialize contour detection algorithms
    ContourAlgorithmRegistry.initialize();
    _availableAlgorithms = ContourAlgorithmRegistry.getAvailableAlgorithms();
    if (_availableAlgorithms.isNotEmpty) {
      _selectedAlgorithm = _availableAlgorithms.first;
    }
    
    _loadImage();
  }

  Future<void> _loadImage() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Loading image...';
    });

    try {
      // Load and decode the image
      final bytes = await widget.imageFile.readAsBytes();
      final decodedImage = img.decodeImage(bytes);

      if (decodedImage == null) {
        setState(() {
          _errorMessage = 'Failed to decode image';
          _isProcessing = false;
        });
        return;
      }

      // Create a copy for display
      final displayImage = img.copyResize(decodedImage, 
          width: decodedImage.width, height: decodedImage.height);

      // Draw markers on the display image for reference
      _drawMarkers(displayImage, widget.markerResult.markers);
      
      // Convert for display
      final displayBytes = Uint8List.fromList(img.encodePng(displayImage));

      setState(() {
        _sourceImage = decodedImage;
        _displayImageBytes = displayBytes;
        _isProcessing = false;
        _statusMessage = 'Tap on the slab to select a seed point, then tap "Detect Contour"';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading image: $e';
        _isProcessing = false;
      });
    }
  }

  void _drawMarkers(img.Image image, List<MarkerPoint> markers) {
    // Draw markers with different colors
    for (final marker in markers) {
      img.Color color;
      
      switch (marker.role) {
        case MarkerRole.origin:
          color = img.ColorRgba8(255, 0, 0, 255); // Red
          break;
        case MarkerRole.xAxis:
          color = img.ColorRgba8(0, 255, 0, 255); // Green
          break;
        case MarkerRole.scale:
          color = img.ColorRgba8(0, 0, 255, 255); // Blue
          break;
      }
      
      // Draw a circle for each marker
      for (int dy = -10; dy <= 10; dy++) {
        for (int dx = -10; dx <= 10; dx++) {
          if (dx * dx + dy * dy <= 100) { // radius = 10
            final px = marker.x + dx;
            final py = marker.y + dy;
            if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
              image.setPixel(px, py, color);
            }
          }
        }
      }
    }
  }

  void _handleImageTap(TapDownDetails details, Size imageSize, Size screenSize) {
    if (_isProcessing) return;

    // Calculate tap position relative to the image
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPosition = box.globalToLocal(details.globalPosition);
    
    // Scale from screen coordinates to image coordinates
    final double scaleX = _sourceImage!.width / imageSize.width;
    final double scaleY = _sourceImage!.height / imageSize.height;
    
    final int imageX = (localPosition.dx * scaleX).round();
    final int imageY = (localPosition.dy * scaleY).round();
    
    // Ensure coordinates are within image bounds
    if (imageX < 0 || imageX >= _sourceImage!.width || 
        imageY < 0 || imageY >= _sourceImage!.height) {
      return;
    }
    
    setState(() {
      _selectedPoint = localPosition;
      _hasSelectedPoint = true;
      // Clear any previous contour result
      _contourPoints = null;
      _contourMachinePoints = null;
      _resultImageBytes = null;
      
      _statusMessage = 'Seed point selected. Tap "Detect Contour" to proceed.';
    });
  }

  Future<void> _detectContour() async {
    if (_sourceImage == null || !_hasSelectedPoint || _selectedPoint == null) {
      setState(() {
        _errorMessage = 'Please tap on the slab to select a seed point first';
      });
      return;
    }
    
    if (_selectedAlgorithm.isEmpty) {
      setState(() {
        _errorMessage = 'No detection algorithm selected';
      });
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Detecting contour using $_selectedAlgorithm algorithm...';
      _errorMessage = '';
    });

    try {
      // Calculate image coordinates of the seed point
      final Size? screenSize = context.findRenderObject()?.paintBounds.size;
      if (screenSize == null) {
        throw Exception('Cannot determine screen size');
      }
      
      final double scaleX = _sourceImage!.width / screenSize.width;
      final double scaleY = _sourceImage!.height / screenSize.height;
      
      final int seedX = (_selectedPoint!.dx * scaleX).round();
      final int seedY = (_selectedPoint!.dy * scaleY).round();
      
      // Get the selected algorithm
      final algorithm = ContourAlgorithmRegistry.getAlgorithm(_selectedAlgorithm);
      
      if (algorithm == null) {
        throw Exception('Selected algorithm not found');
      }
      
      // Run contour detection
      final contourResult = await algorithm.detectContour(
        _sourceImage!,
        seedX,
        seedY,
        _coordinateSystem
      );
      
      // If we have a result, convert it for display
      if (contourResult.debugImage != null) {
        final resultBytes = Uint8List.fromList(img.encodePng(contourResult.debugImage!));
        
        setState(() {
          _resultImageBytes = resultBytes;
          _contourPoints = contourResult.pixelContour;
          _contourMachinePoints = contourResult.machineContour;
          _isProcessing = false;
          _statusMessage = 'Contour detected with $_selectedAlgorithm algorithm! (${contourResult.pointCount} points)';
        });
      } else {
        // If no debug image, create one with a basic visualization
        final contourImage = img.copyResize(_sourceImage!, 
            width: _sourceImage!.width, height: _sourceImage!.height);
        
        // Draw seed point
        _drawCircle(contourImage, seedX, seedY, 8, [255, 255, 0, 255]);
        
        // Draw contour
        for (int i = 0; i < contourResult.pixelContour.length - 1; i++) {
          _drawLine(
            contourImage, 
            contourResult.pixelContour[i].x.round(), 
            contourResult.pixelContour[i].y.round(),
            contourResult.pixelContour[i + 1].x.round(), 
            contourResult.pixelContour[i + 1].y.round(),
            [0, 255, 0, 255]
          );
        }
        
        final resultBytes = Uint8List.fromList(img.encodePng(contourImage));
        
        setState(() {
          _resultImageBytes = resultBytes;
          _contourPoints = contourResult.pixelContour;
          _contourMachinePoints = contourResult.machineContour;
          _isProcessing = false;
          _statusMessage = 'Contour detected with $_selectedAlgorithm algorithm! (${contourResult.pointCount} points)';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error detecting contour: $e';
        _isProcessing = false;
        _statusMessage = 'Failed to detect contour';
      });
    }
  }

  // Simple drawing utilities for fallback visualization
  void _drawCircle(img.Image image, int x, int y, int radius, List<int> color) {
    final rgbaColor = img.ColorRgba8(color[0], color[1], color[2], color[3]);
    
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy <= radius * radius) {
          final px = x + dx;
          final py = y + dy;
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, rgbaColor);
          }
        }
      }
    }
  }
  
  void _drawLine(img.Image image, int x1, int y1, int x2, int y2, List<int> color) {
    final rgbaColor = img.ColorRgba8(color[0], color[1], color[2], color[3]);
    
    // Basic Bresenham line algorithm
    int dx = (x2 - x1).abs();
    int dy = (y2 - y1).abs();
    int sx = x1 < x2 ? 1 : -1;
    int sy = y1 < y2 ? 1 : -1;
    int err = dx - dy;
    
    while (true) {
      if (x1 >= 0 && x1 < image.width && y1 >= 0 && y1 < image.height) {
        image.setPixel(x1, y1, rgbaColor);
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
  }

  // Accept the current contour
  void _acceptContour() {
    if (_contourPoints == null || _contourMachinePoints == null) {
      setState(() {
        _errorMessage = 'No contour detected';
      });
      return;
    }

    // Create a SlabContourResult
    final contourResult = SlabContourResult(
      pixelContour: _contourPoints!,
      machineContour: _contourMachinePoints!,
      debugImage: _resultImageBytes != null ? 
        img.decodePng(_resultImageBytes!) : null,
    );
    
    // Update the flow manager with the new contour
    final processingProvider = Provider.of<ProcessingProvider>(context, listen: false);
    if (processingProvider.flowManager != null) {
      processingProvider.flowManager!.updateContourResult(
        contourResult, 
        method: ContourDetectionMethod.interactive
      );
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Contour successfully updated')),
      );
      
      // Navigate back
      Navigator.pop(context, true);
    } else {
      setState(() {
        _errorMessage = 'Processing flow not initialized';
      });
    }
  }

  // Reset the contour detection
  void _resetContour() {
    setState(() {
      _selectedPoint = null;
      _hasSelectedPoint = false;
      _contourPoints = null;
      _contourMachinePoints = null;
      _resultImageBytes = null;
      _statusMessage = 'Tap on the slab to select a seed point, then tap "Detect Contour"';
      _errorMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Slab Contour Detection'),
        actions: [
          if (_contourPoints != null)
            IconButton(
              icon: Icon(Icons.check),
              tooltip: 'Accept Contour',
              onPressed: _acceptContour,
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            padding: EdgeInsets.all(8),
            color: _errorMessage.isEmpty ? Colors.blue.shade50 : Colors.red.shade50,
            width: double.infinity,
            child: Text(
              _errorMessage.isEmpty ? _statusMessage : _errorMessage,
              style: TextStyle(
                color: _errorMessage.isEmpty ? Colors.blue.shade900 : Colors.red.shade900,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          // Algorithm selection dropdown
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Detection Algorithm: ', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _selectedAlgorithm,
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedAlgorithm = newValue;
                      });
                    }
                  },
                  items: _availableAlgorithms
                    .map<DropdownMenuItem<String>>((String algorithm) {
                      return DropdownMenuItem<String>(
                        value: algorithm,
                        child: Text(algorithm),
                      );
                    }).toList(),
                ),
              ],
            ),
          ),
          
          // Image display area
          Expanded(
            child: _buildImageDisplay(),
          ),
          
          // Instructions
          if (!_hasSelectedPoint && !_isProcessing)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Tap on your slab to select a seed point',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          
          // Control buttons
          _buildControlButtons(),
        ],
      ),
    );
  }

  Widget _buildImageDisplay() {
    if (_isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing, please wait...'),
          ],
        ),
      );
    }
    
    if (_resultImageBytes != null) {
      return GestureDetector(
        onTapDown: null, // Disable tapping after contour is detected
        child: InteractiveViewer(
          constrained: true,
          minScale: 0.5,
          maxScale: 3.0,
          child: Image.memory(
            _resultImageBytes!,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    
    if (_displayImageBytes != null) {
      return GestureDetector(
        onTapDown: (details) {
          final Size size = MediaQuery.of(context).size;
          _handleImageTap(details, size, size);
        },
        child: Stack(
          children: [
            InteractiveViewer(
              constrained: true,
              minScale: 0.5,
              maxScale: 3.0,
              child: Image.memory(
                _displayImageBytes!,
                fit: BoxFit.contain,
              ),
            ),
            
            // Draw the touch indicator if we have a selected point
            if (_hasSelectedPoint && _selectedPoint != null)
              Positioned(
                left: _selectedPoint!.dx - _touchRadius,
                top: _selectedPoint!.dy - _touchRadius,
                child: Container(
                  width: _touchRadius * 2,
                  height: _touchRadius * 2,
                  decoration: BoxDecoration(
                    color: Colors.yellow.withOpacity(0.5),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.yellow, width: 2),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    
    // Loading or error state
    return Center(
      child: _errorMessage.isNotEmpty
          ? Text('Error: $_errorMessage')
          : CircularProgressIndicator(),
    );
  }

  Widget _buildControlButtons() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          // Detect button
          if (_hasSelectedPoint && _contourPoints == null)
            ElevatedButton.icon(
              icon: Icon(Icons.search),
              label: Text('Detect Contour'),
              onPressed: _detectContour,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                minimumSize: Size(double.infinity, 48),
              ),
            ),
            
          SizedBox(height: 8),
            
          // Reset and Accept buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Reset button
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.refresh),
                  label: Text('Reset'),
                  onPressed: _resetContour,
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: Colors.grey.shade300,
                  ),
                ),
              ),
              
              SizedBox(width: 16),
              
              // Accept button
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.check),
                  label: Text('Accept Contour'),
                  onPressed: _contourPoints != null ? _acceptContour : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}