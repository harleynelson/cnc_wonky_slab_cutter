// lib/screens/interactive_contour_screen.dart
// Interactive contour detection screen with enhanced visualization

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
import '../services/image_processing/contour_algorithms/contour_algorithm_registry.dart';
import '../utils/image_processing/drawing_utils.dart';
import '../utils/image_processing/geometry_utils.dart';
import 'parameter_tuning_screen.dart';

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
  Point? _selectedImagePoint; // Actual point in image coordinates
  img.Image? _sourceImage;
  Uint8List? _displayImageBytes;
  Uint8List? _resultImageBytes;
  List<Point>? _contourPoints;
  List<Point>? _contourMachinePoints;
  String _statusMessage = 'Tap on the slab to begin contour detection';
  String _errorMessage = '';
  double? _contourAreaMm2;
  
  // Fixed visualization settings (formerly customizable)
  final Map<String, dynamic> _visualSettings = {
    'showOriginalContour': false,
    'showSmoothedContour': true,
    'showAreaMeasurement': true,
    'showSeedPoint': true,
    'contourStyle': 'glowing',
    'contourThickness': 4,
    'contourColor': const Color(0xFF0000FF), // Blue
  };

  // UI parameters
  final double _touchRadius = 15.0;
  
  // Coordinate system
  late MachineCoordinateSystem _coordinateSystem;
  
  // Display calculations
  double _imageScale = 1.0;
  Offset _imageOffset = Offset.zero;
  Size _displaySize = Size.zero;
  
  // Reference to image container key for proper positioning
  final GlobalKey _imageContainerKey = GlobalKey();

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
      DrawingUtils.drawCircle(image, marker.x, marker.y, 10, color);
      
      // Draw a small filled circle in the center
      DrawingUtils.drawCircle(image, marker.x, marker.y, 3, color, fill: true);
      
      // Add label
      String label = "";
      switch (marker.role) {
        case MarkerRole.origin:
          label = "Origin";
          break;
        case MarkerRole.xAxis:
          label = "X-Axis";
          break;
        case MarkerRole.scale:
          label = "Scale";
          break;
      }
      
      DrawingUtils.drawText(
        image, 
        label, 
        marker.x + 12, 
        marker.y - 10, 
        color,
        drawBackground: true
      );
    }
  }

  // Calculate image display properties once we know both image and container sizes
  void _calculateImageDisplayProperties(Size containerSize) {
    if (_sourceImage == null) return;
    
    final double imageAspect = _sourceImage!.width / _sourceImage!.height;
    final double containerAspect = containerSize.width / containerSize.height;
    
    double displayWidth, displayHeight;
    double offsetX = 0, offsetY = 0;
    
    if (imageAspect > containerAspect) {
      // Image is wider than container (letterboxed)
      displayWidth = containerSize.width;
      displayHeight = containerSize.width / imageAspect;
      offsetY = (containerSize.height - displayHeight) / 2;
    } else {
      // Image is taller than container (pillarboxed)
      displayHeight = containerSize.height;
      displayWidth = containerSize.height * imageAspect;
      offsetX = (containerSize.width - displayWidth) / 2;
    }
    
    _imageScale = displayWidth / _sourceImage!.width;
    _imageOffset = Offset(offsetX, offsetY);
    _displaySize = Size(displayWidth, displayHeight);
  }

  // Convert screen coordinates to image coordinates
  Point screenToImageCoordinates(Offset screenPoint) {
    // First adjust for the position of the touch within the image
    final relativeX = screenPoint.dx - _imageOffset.dx;
    final relativeY = screenPoint.dy - _imageOffset.dy;
    
    // Then convert to image coordinates using the scale
    final imageX = relativeX / _imageScale;
    final imageY = relativeY / _imageScale;
    
    return Point(imageX, imageY);
  }

  void _handleImageTap(TapDownDetails details, Size containerSize) {
    if (_isProcessing || _sourceImage == null) return;

    // Calculate display properties if they haven't been set
    if (_displaySize == Size.zero) {
      _calculateImageDisplayProperties(containerSize);
    }

    // Get tap position relative to the GestureDetector
    final RenderBox box = _imageContainerKey.currentContext!.findRenderObject() as RenderBox;
    final Offset localPosition = box.globalToLocal(details.globalPosition);
    
    // Check if tap is within the displayed image bounds
    if (localPosition.dx < _imageOffset.dx || 
        localPosition.dx > _imageOffset.dx + _displaySize.width ||
        localPosition.dy < _imageOffset.dy || 
        localPosition.dy > _imageOffset.dy + _displaySize.height) {
      return;  // Tap outside image area
    }
    
    // Convert to image coordinates
    final Point imagePoint = screenToImageCoordinates(localPosition);
    final int imageX = imagePoint.x.round();
    final int imageY = imagePoint.y.round();
    
    // Ensure coordinates are within image bounds
    if (imageX < 0 || imageX >= _sourceImage!.width || 
        imageY < 0 || imageY >= _sourceImage!.height) {
      return;
    }
    
    setState(() {
      // Store both screen and image coordinates
      _selectedPoint = localPosition;
      _selectedImagePoint = imagePoint;
      _hasSelectedPoint = true;
      
      // Clear any previous contour result
      _contourPoints = null;
      _contourMachinePoints = null;
      _resultImageBytes = null;
      _contourAreaMm2 = null;
      
      _statusMessage = 'Seed point selected. Tap "Detect Contour" to proceed.';
    });
  }

  Future<void> _detectContour() async {
  if (_sourceImage == null || !_hasSelectedPoint || _selectedImagePoint == null) {
    setState(() {
      _errorMessage = 'Please tap on the slab to select a seed point first';
    });
    return;
  }
  
  setState(() {
    _isProcessing = true;
    _statusMessage = 'Detecting contour using Edge algorithm...';
    _errorMessage = '';
  });

  try {
    // Use the stored image coordinates
    final int seedX = _selectedImagePoint!.x.round();
    final int seedY = _selectedImagePoint!.y.round();
    
    // Get the edge algorithm directly
    final algorithm = ContourAlgorithmRegistry.getAlgorithm('Edge');
    
    if (algorithm == null) {
      throw Exception('Edge algorithm not found');
    }
    
    // Run contour detection
    final contourResult = await algorithm.detectContour(
      _sourceImage!,
      seedX,
      seedY,
      _coordinateSystem
    );
    
    // Calculate area if we have a valid contour
    double? areaMm2;
    if (contourResult.machineContour.length >= 3) {
      areaMm2 = GeometryUtils.polygonArea(contourResult.machineContour);
    }
    
    // Create enhanced visualization
    img.Image enhancedVisualization;
    if (contourResult.debugImage != null) {
      enhancedVisualization = _createEnhancedVisualization(
        contourResult.debugImage!,
        contourResult.pixelContour,
        seedX,
        seedY,
        areaMm2
      );
    } else {
      // If no debug image, create one from the source image
      enhancedVisualization = img.copyResize(_sourceImage!, 
          width: _sourceImage!.width, height: _sourceImage!.height);
          
      // Apply enhancements to the source image copy
      _enhanceSourceImageVisualization(
        enhancedVisualization,
        contourResult.pixelContour,
        seedX,
        seedY,
        areaMm2
      );
    }
    
    final resultBytes = Uint8List.fromList(img.encodePng(enhancedVisualization));
    
    setState(() {
      _resultImageBytes = resultBytes;
      _contourPoints = contourResult.pixelContour;
      _contourMachinePoints = contourResult.machineContour;
      _contourAreaMm2 = areaMm2;
      _isProcessing = false;
      
      final pointCount = contourResult.pointCount;
      final areaText = areaMm2 != null ? ' Area: ${areaMm2.toStringAsFixed(2)} mm²' : '';
      _statusMessage = 'Contour detected with Edge algorithm! (${pointCount} points).$areaText';
    });
  } catch (e) {
    setState(() {
      _errorMessage = 'Error detecting contour: $e';
      _isProcessing = false;
      _statusMessage = 'Failed to detect contour';
    });
  }
}

  // Create an enhanced visualization from the debug image
  img.Image _createEnhancedVisualization(
    img.Image debugImage,
    List<Point> contour,
    int seedX,
    int seedY,
    double? areaMm2
  ) {
    final result = img.copyResize(debugImage, width: debugImage.width, height: debugImage.height);
    
    // Ensure we have the markers
    _drawMarkers(result, widget.markerResult.markers);
    
    // Draw seed point if enabled
    if (_visualSettings['showSeedPoint'] && _selectedImagePoint != null) {
      DrawingUtils.drawCircle(result, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255), fill: true);
    }
    
    // Create Color from visualization settings
    final contourColor = img.ColorRgba8(
      _visualSettings['contourColor'].red,
      _visualSettings['contourColor'].green,
      _visualSettings['contourColor'].blue,
      255
    );
    
    // Draw contour as glowing (fixed style)
    if (contour.isNotEmpty) {
      DrawingUtils.drawGlowingContour(
        result,
        contour,
        img.ColorRgba8(255, 255, 0, 150), // Yellow glow
        contourColor,
        glowSize: 5,
        lineThickness: _visualSettings['contourThickness']
      );
    }
    
    // Add area measurement if enabled
    if (_visualSettings['showAreaMeasurement'] && areaMm2 != null && contour.isNotEmpty) {
      DrawingUtils.drawAreaMeasurement(
        result,
        contour,
        areaMm2,
        _coordinateSystem,
        color: contourColor
      );
    }
    
    return result;
  }
  
  // Enhance the source image for visualization when no debug image is available
  void _enhanceSourceImageVisualization(
    img.Image image,
    List<Point> contour,
    int seedX,
    int seedY,
    double? areaMm2
  ) {
    // Draw seed point
    if (_visualSettings['showSeedPoint']) {
      DrawingUtils.drawCircle(image, seedX, seedY, 8, img.ColorRgba8(255, 255, 0, 255), fill: true);
    }
    
    // Draw the contour
    final contourColor = img.ColorRgba8(
      _visualSettings['contourColor'].red,
      _visualSettings['contourColor'].green,
      _visualSettings['contourColor'].blue,
      255
    );
    
    // Draw glowing contour (fixed style)
    if (contour.isNotEmpty) {
      DrawingUtils.drawGlowingContour(
        image,
        contour,
        img.ColorRgba8(255, 255, 0, 150), // Yellow glow
        contourColor,
        glowSize: 5,
        lineThickness: _visualSettings['contourThickness']
      );
    }
    
    // Add area measurement
    if (_visualSettings['showAreaMeasurement'] && areaMm2 != null && contour.isNotEmpty) {
      DrawingUtils.drawAreaMeasurement(
        image,
        contour,
        areaMm2,
        _coordinateSystem,
        color: contourColor
      );
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

    // Create a SlabContourResult with area information
    final contourResult = SlabContourResult(
      pixelContour: _contourPoints!,
      machineContour: _contourMachinePoints!,
      debugImage: _resultImageBytes != null ? 
        img.decodeImage(_resultImageBytes!) : null,
      pixelArea: _contourPoints!.length >= 3 ? 
        GeometryUtils.polygonArea(_contourPoints!) : 0,
      machineArea: _contourAreaMm2 ?? 0,
    );
    
    // Update the flow manager with the new contour
    final processingProvider = Provider.of<ProcessingProvider>(context, listen: false);
    if (processingProvider.flowManager != null) {
      processingProvider.flowManager!.updateContourResult(
        contourResult, 
        method: ContourDetectionMethod.interactive
      );
      
      // Show success message with area information
      final areaText = _contourAreaMm2 != null ? 
        ' (Area: ${_contourAreaMm2!.toStringAsFixed(2)} mm²)' : '';
        
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contour successfully updated$areaText'),
          duration: Duration(seconds: 2),
        ),
      );
      
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
        title: Text('Slab Contour Detection'),
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
          
          // Image display area
          Expanded(
            child: _buildImageDisplay(),
          ),
          
          // Area display if available
          if (_contourAreaMm2 != null)
            Container(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Calculated Area: ${_contourAreaMm2!.toStringAsFixed(2)} mm²',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
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
      return InteractiveViewer(
        constrained: true,
        minScale: 0.5,
        maxScale: 5.0,
        child: Image.memory(
          _resultImageBytes!,
          fit: BoxFit.contain,
        ),
      );
    }
    
    if (_displayImageBytes != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          // Calculate image display properties
          _calculateImageDisplayProperties(Size(constraints.maxWidth, constraints.maxHeight));
          
          return Container(
            key: _imageContainerKey,
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            color: Colors.grey.withOpacity(0.1), // Subtle background to visualize container
            child: GestureDetector(
              onTapDown: (details) {
                _handleImageTap(details, Size(constraints.maxWidth, constraints.maxHeight));
              },
              child: Stack(
                children: [
                  // The image
                  Center(
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
                    
                  // Show helper guides for placing seed point
                  if (!_hasSelectedPoint)
                    Positioned(
                      top: 10,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        color: Colors.black54,
                        child: Text(
                          'Tap inside the slab to set a seed point',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    }
    
    // Loading or error state
    return Center(
      child: _errorMessage.isNotEmpty
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 48),
                SizedBox(height: 16),
                Text(
                  'Error: $_errorMessage',
                  style: TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
            )
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
                    disabledBackgroundColor: Colors.green.withOpacity(0.3),
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: 8),
          
          // Parameter tuning button
          ElevatedButton.icon(
            icon: Icon(Icons.tune),
            label: Text('Algorithm Parameters'),
            onPressed: _contourPoints != null ? null : _openParameterTuning,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: EdgeInsets.symmetric(vertical: 12),
              minimumSize: Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  // Reset the contour detection
  void _resetContour() {
    setState(() {
      _selectedPoint = null;
      _selectedImagePoint = null;
      _hasSelectedPoint = false;
      _contourPoints = null;
      _contourMachinePoints = null;
      _resultImageBytes = null;
      _contourAreaMm2 = null;
      _statusMessage = 'Tap on the slab to select a seed point, then tap "Detect Contour"';
      _errorMessage = '';
    });
  }

  void _openParameterTuning() async {
    if (widget.markerResult == null || widget.imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marker detection must be completed first'))
      );
      return;
    }

    // First, make sure we have a seed point
    int seedX, seedY;
    if (_selectedImagePoint != null) {
      // Use the selected point if available
      seedX = _selectedImagePoint!.x.round();
      seedY = _selectedImagePoint!.y.round();
    } else {
      // Use the center of the image if no point is selected
      if (_sourceImage != null) {
        seedX = _sourceImage!.width ~/ 2;
        seedY = _sourceImage!.height ~/ 2;
      } else {
        // Default to marker coordinates if image dimensions aren't available
        final centerMarker = widget.markerResult.markers[0]; // Use origin marker as fallback
        seedX = centerMarker.x;
        seedY = centerMarker.y;
      }
    }

    // Navigate to parameter tuning screen
    final bool? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ParameterTuningScreen(
          imageFile: widget.imageFile,
          markers: widget.markerResult.markers,
          settings: widget.settings,
          seedX: seedX,
          seedY: seedY,
        ),
      ),
    );
    
    if (result == true) {
      // Refresh the UI and use the updated contour
      setState(() {});
    }
  }
}