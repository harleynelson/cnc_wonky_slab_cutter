// lib/screens/combined_detector_screen.dart
// Combined screen that handles both marker detection and slab contour detection

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/detection/contour_algorithms/contour_algorithm_registry.dart';
import '../services/detection/contour_algorithms/edge_contour_algorithm.dart';
import '../utils/general/machine_coordinates.dart';
import '../services/flow/processing_flow_manager.dart';
import '../widgets/marker_overlay.dart';
import '../widgets/contour_overlay.dart';
import '../utils/general/error_utils.dart';
import 'gcode_generator_screen.dart';
import 'multi_tap_detection_screen.dart';

class CombinedDetectorScreen extends StatefulWidget {
  final File imageFile;
  final SettingsModel settings;
  final Function(SettingsModel)? onSettingsChanged;

  const CombinedDetectorScreen({
    Key? key,
    required this.imageFile,
    required this.settings,
    this.onSettingsChanged,
  }) : super(key: key);

  @override
  _CombinedDetectorScreenState createState() => _CombinedDetectorScreenState();
}

class _CombinedDetectorScreenState extends State<CombinedDetectorScreen> {
  bool _isLoading = false;
  String _statusMessage = 'Starting detection...';
  String _errorMessage = '';
  
  // Detection state
  bool _markersDetected = false;
  bool _contourDetected = false;
  
  // Image dimensions for overlays
  Size? _imageSize;
  
  // Flow Manager
  late ProcessingFlowManager _flowManager;
  
  // Detection seed point for contour detection
  Offset? _selectedPoint;
  
  @override
  void initState() {
    super.initState();
    _flowManager = Provider.of<ProcessingProvider>(context, listen: false).flowManager!;
    _initializeDetection();
  }
  
  Future<void> _initializeDetection() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing...';
    });

    try {
      // Initialize with the image file
      await _flowManager.initWithImage(widget.imageFile);
      
      // Get image dimensions
      final imageBytes = await widget.imageFile.readAsBytes();
      final image = await decodeImageFromList(imageBytes);
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
      
      // Start marker detection automatically
      await _detectMarkers();
    } catch (e) {
      setState(() {
        _errorMessage = 'Initialization error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _detectMarkers() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Detecting markers...';
      _errorMessage = '';
    });

    try {
      await _flowManager.detectMarkers();
      
      setState(() {
        _markersDetected = true;
        _isLoading = false;
        _statusMessage = 'Markers detected! Now tap on the slab to select a seed point for contour detection.';
      });
    } catch (e, stackTrace) {
      ErrorUtils().logError(
        'Error during marker detection',
        e,
        stackTrace: stackTrace,
        context: 'marker_detection',
      );
      
      setState(() {
        _errorMessage = 'Marker detection failed: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _detectContour() async {
  if (_selectedPoint == null) {
    setState(() {
      _errorMessage = 'Please tap on the slab to select a seed point first';
    });
    return;
  }

  setState(() {
    _isLoading = true;
    _statusMessage = 'Detecting contour...';
    _errorMessage = '';
  });

  try {
    // If the image size is not available, we can't reliably calculate the seed point
    if (_imageSize == null) {
      throw Exception('Image dimensions not available');
    }
    
    // // Calculate the actual seed point in the image
    // final imagePoint = _calculateImagePoint(_selectedPoint!);
    
    // Detect contour using interactive method
    final markerResult = _flowManager.result.markerResult;
    if (markerResult == null) {
      throw Exception('Marker detection result not available');
    }
    
    // Load image
    final imageBytes = await widget.imageFile.readAsBytes();
    final decodedImage = img.decodeImage(imageBytes);
    
    if (decodedImage == null) {
      throw Exception('Failed to decode image');
    }
    
    // // Create coordinate system from marker detection result
    // final coordinateSystem = _flowManager.result.markerResult!;
    
    // // Use edge contour algorithm with the calculated image point coordinates
    // final contourAlgorithmRegistry = await _flowManager.detectSlabContourAutomatic(
    //   imagePoint.x.toInt(),  // Pass the seed point x coordinate
    //   imagePoint.y.toInt()   // Pass the seed point y coordinate
    // );
    
    setState(() {
      _contourDetected = true;
      _isLoading = false;
      _statusMessage = 'Contour detected! Tap "Continue" to generate G-code.';
    });
  } catch (e, stackTrace) {
    ErrorUtils().logError(
      'Error during contour detection',
      e,
      stackTrace: stackTrace,
      context: 'contour_detection',
    );
    
    setState(() {
      _errorMessage = 'Contour detection failed: ${e.toString()}';
      _isLoading = false;
    });
    
    // Show dialog offering multi-tap detection
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Detection Failed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
              SizedBox(height: 16),
              Text(
                'The automatic contour detection failed. This often happens when the slab and background are similar colors.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Text(
                'Would you like to try the multi-tap detection method?',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openMultiTapDetection();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: Text('Try Multi-Tap'),
            ),
          ],
        );
      },
    );
  }
}
  
  Future<void> _generateGcode() async {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => GcodeGeneratorScreen(
        settings: widget.settings,
      ),
    ),
  );
}
  
  void _handleImageTap(TapDownDetails details) {
    if (_isLoading || !_markersDetected) return;
    
    setState(() {
      _selectedPoint = details.localPosition;
      
      // Calculate image point
      final imagePoint = _calculateImagePoint(_selectedPoint!);
      
      // Update status message with tap coordinates
      _statusMessage = 'Tap at: (${_selectedPoint!.dx.toInt()},${_selectedPoint!.dy.toInt()}) → Image: (${imagePoint.x.toInt()},${imagePoint.y.toInt()}). Tap "Detect Contour" to proceed.';
    });
  }
  
  CoordinatePointXY _calculateImagePoint(Offset tapPosition) {
  if (_imageSize == null) {
    return CoordinatePointXY(0, 0);
  }
  
  // Get the direct parent render object of the image
  final RenderBox imageContainer = context.findRenderObject() as RenderBox;
  
  // Get the overlay's container size - this is crucial
  final markerOverlaySize = Size(imageContainer.size.width, 438.0); // Match overlay's canvas size
  
  print('DEBUG: Tap position: ${tapPosition.dx}x${tapPosition.dy}');
  print('DEBUG: Using overlay size: ${markerOverlaySize.width}x${markerOverlaySize.height}');
  
  // Use the same logic as in imageToDisplayCoordinates but in reverse
  final imageAspect = _imageSize!.width / _imageSize!.height;
  final displayAspect = markerOverlaySize.width / markerOverlaySize.height;
  
  double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
  
  if (imageAspect > displayAspect) {
    displayWidth = markerOverlaySize.width;
    displayHeight = displayWidth / imageAspect;
    offsetY = (markerOverlaySize.height - displayHeight) / 2;
  } else {
    displayHeight = markerOverlaySize.height;
    displayWidth = displayHeight * imageAspect;
    offsetX = (markerOverlaySize.width - displayWidth) / 2;
  }
  
  // Scale factors
  final scaleX = _imageSize!.width / displayWidth;
  final scaleY = _imageSize!.height / displayHeight;
  
  // Convert tap position to image coordinates
  final imageX = (tapPosition.dx - offsetX) * scaleX;
  final imageY = (tapPosition.dy - offsetY) * scaleY;
  
  print('DEBUG: Display size: ${displayWidth}x${displayHeight} with offset (${offsetX},${offsetY})');
  print('DEBUG: Scale factors: ${scaleX}x${scaleY}');
  print('DEBUG: Tap at (${tapPosition.dx},${tapPosition.dy}) → Image (${imageX},${imageY})');
  
  return CoordinatePointXY(imageX, imageY);
}
  
  @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text('Slab Detection'),
      actions: [
        if (_markersDetected && _flowManager.result.markerResult?.debugImage != null)
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: _showDebugImage,
          ),
      ],
    ),
    body: Column(
      children: [
        // Main content area
        Expanded(
          child: GestureDetector(
            onTapDown: _markersDetected && !_contourDetected ? _handleImageTap : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image display
                _buildImageDisplay(),
                
                // Marker overlay - ensure markers are shown at the correct positions
                if (_markersDetected && _flowManager.result.markerResult != null && _imageSize != null)
                  Positioned.fill(
                    child: MarkerOverlay(
                      markers: _flowManager.result.markerResult!.markers,
                      imageSize: _imageSize!,
                    ),
                  ),
                
                // Contour overlay
                if (_contourDetected && _flowManager.result.contourResult != null && _imageSize != null)
                  Positioned.fill(
                    child: ContourOverlay(
                      contourPoints: _flowManager.result.contourResult!.pixelContour,
                      imageSize: _imageSize!,
                      color: Colors.green,
                    ),
                  ),
                  
                // Seed point indicator
                if (_selectedPoint != null && !_contourDetected)
                  Positioned(
                    left: _selectedPoint!.dx - 10,
                    top: _selectedPoint!.dy - 10,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.yellow.withOpacity(0.7),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.orange, width: 2),
                      ),
                    ),
                  ),
                  
                // Loading indicator
                if (_isLoading)
                  Container(
                    color: Colors.black.withOpacity(0.5),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            _statusMessage,
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
          
        // Status bar - MOVED TO BOTTOM
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
          
        // Action buttons
        _buildControlButtons(),
      ],
    ),
  );
}
  
  Widget _buildImageDisplay() {
  if (_flowManager.result.originalImage != null) {
    if (_contourDetected && _flowManager.result.contourResult?.debugImage != null) {
      // Use Image.memory to display the debug image if contour was detected
      return Center(
        child: Image.memory(
          Uint8List.fromList(img.encodePng(_flowManager.result.contourResult!.debugImage!)),
          fit: BoxFit.contain,
        ),
      );
    } else {
      // Show the original image if no contour detected yet
      return Center(
        child: Image.file(
          _flowManager.result.originalImage!,
          fit: BoxFit.contain,
        ),
      );
    }
  } else {
    return Center(child: Text('Image not available'));
  }
}
  
  Widget _buildControlButtons() {
  return Container(
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black12,
          blurRadius: 4,
          offset: Offset(0, -2),
        ),
      ],
    ),
    child: Column(
      children: [
        // Detect Contour Button (always visible)
        ElevatedButton.icon(
          icon: Icon(Icons.content_cut),
          label: Text('Detect Contour'),
          onPressed: _isLoading || !_markersDetected || _selectedPoint == null ? null : _detectContour,
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 48),
          ),
        ),
        
        SizedBox(height: 8),
        
        // Multi-Tap Mode Button (new)
        ElevatedButton.icon(
          icon: Icon(Icons.touch_app),
          label: Text('Multi-Tap Mode'),
          onPressed: _isLoading || !_markersDetected ? null : _openMultiTapDetection,
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 48),
            backgroundColor: Colors.orange,
          ),
        ),
        
        SizedBox(height: 8),
        
        // Reset and Parameters buttons row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.refresh),
                label: Text('Reset'),
                onPressed: _isLoading ? null : _resetDetection,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(Icons.settings),
                label: Text('Parameters'),
                onPressed: _isLoading ? null : _showParametersDialog,
              ),
            ),
          ],
        ),
        
        SizedBox(height: 8),
        
        // Back and Continue buttons row
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.arrow_back),
                label: Text('Back'),
                onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(Icons.arrow_forward),
                label: Text('Continue'),
                onPressed: _isLoading || !_contourDetected ? null : _generateGcode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _contourDetected ? Colors.green : Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// Add method to navigate to multi-tap detection screen around line ~380

  Future<void> _openMultiTapDetection() async {
    // Navigate to the multi-tap detection screen if contour detection fails
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultiTapDetectionScreen(
          imageFile: widget.imageFile,
          settings: widget.settings,
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    );
  }

void _showParametersDialog() {
  // Get values from settings
  double edgeThreshold = widget.settings.edgeThreshold;
  double simplificationEpsilon = widget.settings.simplificationEpsilon;
  bool useConvexHull = widget.settings.useConvexHull;
  int blurRadius = widget.settings.blurRadius;
  int smoothingWindow = widget.settings.smoothingWindowSize;
  int minSlabSize = widget.settings.minSlabSize;
  int gapAllowedMin = widget.settings.gapAllowedMin;
  int gapAllowedMax = widget.settings.gapAllowedMax;
  int continueSearchDistance = widget.settings.continueSearchDistance;
  
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Detection Parameters'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adjust parameters for contour detection:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  
                  // Edge Threshold Slider
                  Text('Edge Threshold: ${edgeThreshold.round()}'),
                  Text(
                    'Controls edge sensitivity. Lower values detect more edges.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: edgeThreshold,
                    min: 10,
                    max: 100,
                    divisions: 18,
                    label: edgeThreshold.round().toString(),
                    onChanged: (value) {
                      setState(() {
                        edgeThreshold = value;
                      });
                    },
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Blur Radius Slider
                  Text('Blur Radius: $blurRadius'),
                  Text(
                    'Controls noise reduction. Higher values smooth more.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: blurRadius.toDouble(),
                    min: 1,
                    max: 7,
                    divisions: 6,
                    label: blurRadius.toString(),
                    onChanged: (value) {
                      setState(() {
                        blurRadius = value.round();
                      });
                    },
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Smoothing Window Slider
                  Text('Smoothing Window: $smoothingWindow'),
                  Text(
                    'Controls contour smoothness. Higher values create smoother contours.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: smoothingWindow.toDouble(),
                    min: 3,
                    max: 11,
                    divisions: 4,
                    label: smoothingWindow.toString(),
                    onChanged: (value) {
                      setState(() {
                        smoothingWindow = value.round();
                      });
                    },
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Minimum Slab Size Slider - NEW
                  Text('Minimum Slab Size: $minSlabSize'),
                  Text(
                    'Minimum area to be considered a slab.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: minSlabSize.toDouble(),
                    min: 100,
                    max: 3000,
                    divisions: 29,
                    label: minSlabSize.toString(),
                    onChanged: (value) {
                      setState(() {
                        minSlabSize = value.round();
                      });
                    },
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Minimum Gap Allowed Slider - NEW
                  Text('Minimum Gap Allowed: $gapAllowedMin'),
                  Text(
                    'Minimum size of gap that will be bridged.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: gapAllowedMin.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: gapAllowedMin.toString(),
                    onChanged: (value) {
                      setState(() {
                        gapAllowedMin = value.round();
                      });
                    },
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Maximum Gap Allowed Slider - NEW
                  Text('Maximum Gap Allowed: $gapAllowedMax'),
                  Text(
                    'Maximum size of gap that will be bridged.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: gapAllowedMax.toDouble(),
                    min: 10,
                    max: 50,
                    divisions: 8,
                    label: gapAllowedMax.toString(),
                    onChanged: (value) {
                      setState(() {
                        gapAllowedMax = value.round();
                      });
                    },
                  ),

                  // Add this slider to the dialog content
                  Text('Continue Search Distance: $continueSearchDistance'),
                  Text(
                    'Distance to continue searching past initial edges.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: continueSearchDistance.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: continueSearchDistance.toString(),
                    onChanged: (value) {
                      setState(() {
                        continueSearchDistance = value.round();
                      });
                    },
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Simplification Epsilon Slider
                  Text('Simplification: ${simplificationEpsilon.toStringAsFixed(1)}'),
                  Text(
                    'Controls contour detail. Higher values create simpler contours.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: simplificationEpsilon,
                    min: 1.0,
                    max: 10.0,
                    divisions: 18,
                    label: simplificationEpsilon.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() {
                        simplificationEpsilon = value;
                      });
                    },
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Convex Hull Switch
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Use Convex Hull'),
                          Text(
                            'Makes contour more convex',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      Switch(
                        value: useConvexHull,
                        onChanged: (value) {
                          setState(() {
                            useConvexHull = value;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Create a copy of the settings with the updated values
                  final updatedSettings = widget.settings.copy()
                    ..edgeThreshold = edgeThreshold
                    ..simplificationEpsilon = simplificationEpsilon
                    ..useConvexHull = useConvexHull
                    ..blurRadius = blurRadius
                    ..smoothingWindowSize = smoothingWindow
                    ..minSlabSize = minSlabSize
                    ..gapAllowedMin = gapAllowedMin
                    ..gapAllowedMax = gapAllowedMax
                    ..continueSearchDistance = continueSearchDistance;
                  
                  // Save the updated settings
                  updatedSettings.save();

                  // Update the flow manager's EdgeContourAlgorithm with these values
                  final edgeAlgorithm = EdgeContourAlgorithm(
                    generateDebugImage: true,
                    edgeThreshold: edgeThreshold,
                    useConvexHull: useConvexHull,
                    simplificationEpsilon: simplificationEpsilon,
                    blurRadius: blurRadius,
                    smoothingWindowSize: smoothingWindow,
                    continueSearchDistance: continueSearchDistance,
                  );
                    
                  // Register the updated algorithm
                  ContourAlgorithmRegistry.registerAlgorithm(edgeAlgorithm);
                  
                  // Notify the parent widget
                  if (widget.onSettingsChanged != null) {
                    widget.onSettingsChanged!(updatedSettings);
                  }
                  
                  // Update the local settings
                  _updateLocalSettings(updatedSettings);
                  
                  Navigator.of(context).pop();
                },
                child: Text('Apply'),
              ),
            ],
          );
        },
      );
    },
  );
}

void _updateLocalSettings(SettingsModel updatedSettings) {
  setState(() {
    // Update the settings in the widget
    widget.settings.edgeThreshold = updatedSettings.edgeThreshold;
    widget.settings.simplificationEpsilon = updatedSettings.simplificationEpsilon;
    widget.settings.useConvexHull = updatedSettings.useConvexHull;
    widget.settings.blurRadius = updatedSettings.blurRadius;
    widget.settings.smoothingWindowSize = updatedSettings.smoothingWindowSize;
    widget.settings.minSlabSize = updatedSettings.minSlabSize;
    widget.settings.gapAllowedMin = updatedSettings.gapAllowedMin;
    widget.settings.gapAllowedMax = updatedSettings.gapAllowedMax;
    widget.settings.continueSearchDistance = updatedSettings.continueSearchDistance;
    
    // Update the settings in the flow manager
    _flowManager.updateSettings(updatedSettings);
    });
}

// Add this method to display the debug image
void _showDebugImage() {
  if (_flowManager.result.markerResult?.debugImage == null) return;
  
  showDialog(
    context: context,
    builder: (context) => Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Marker Detection Debug Image',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Image.memory(
            Uint8List.fromList(
              img.encodePng(_flowManager.result.markerResult!.debugImage!)
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Image dimensions: ${_flowManager.result.markerResult!.debugImage!.width}x'
              '${_flowManager.result.markerResult!.debugImage!.height}',
              style: TextStyle(fontSize: 12),
            ),
          ),
          TextButton(
            child: Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
}
  
  void _resetDetection() {
    setState(() {
      _markersDetected = false;
      _contourDetected = false;
      _selectedPoint = null;
      _errorMessage = '';
      _statusMessage = 'Detection reset. Starting over...';
    });
    
    _flowManager.reset();
    _initializeDetection();
  }
}