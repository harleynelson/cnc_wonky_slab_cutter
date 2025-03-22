// lib/screens/combined_detector_screen.dart
// Combined screen that handles both marker detection and slab contour detection

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cnc_wonky_slab_cutter/utils/drawing/drawing_utils.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../detection/marker_detector.dart';
import '../detection/marker_selection_state.dart';
import '../detection/slab_contour_result.dart';
import '../utils/general/settings_model.dart';
import '../flow_of_app/flow_provider.dart';
import '../detection/algorithms/contour_algorithm_registry.dart';
import '../detection/algorithms/edge_contour_algorithm.dart';
import '../utils/general/constants.dart';
import '../utils/general/machine_coordinates.dart';
import '../flow_of_app/flow_manager.dart';
import '../widgets/manual_contour_drawer.dart';
import '../widgets/marker_overlay.dart';
import '../widgets/contour_overlay.dart';
import '../utils/general/error_utils.dart';
import 'gcode_generator_screen.dart';

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
  String _statusMessage = 'Tap on the Origin marker (bottom left)';
  String _errorMessage = '';
  
  // Detection state
  bool _markersDetected = false;
  bool _contourDetected = false;
  
  // Image dimensions for overlays
  Size? _imageSize;
  
  // Flow Manager
  late ProcessingFlowManager _flowManager;
  
  // Detection seed point for contour detection
  Offset? _selectedPoint; // slab tap point
  Offset? _spillboardTapPoint; // spillboard tap point

  // Marker tap points
  Offset? _originTapPoint; // origin tap point
  Offset? _xAxisTapPoint; // X axis tap point
  Offset? _scaleTapPoint; // Y axis tap point

  // Current marker selection state
  MarkerSelectionState _markerSelectionState = MarkerSelectionState.origin;
  
  // Map of detected markers
  List<MarkerPoint> _detectedMarkers = [];
  
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
      _isLoading = false;
      _statusMessage = 'Tap on the Origin marker (bottom left)';
    });
  } catch (e) {
    setState(() {
      _errorMessage = 'Initialization error: ${e.toString()}';
      _isLoading = false;
    });
  }
}

  // Fixed _detectMarkersFromTapPoints method for CombinedDetectorScreen

Future<void> _detectMarkersFromTapPoints() async {
  if (_flowManager.result.originalImage == null) {
    setState(() {
      _errorMessage = 'No image available for marker detection';
      _isLoading = false;
    });
    return;
  }
  
  try {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Detecting markers...';
      _errorMessage = '';
    });
    
    // Load image
    final imageBytes = await widget.imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);
    
    if (image == null) {
      setState(() {
        _errorMessage = 'Failed to decode image';
        _isLoading = false;
      });
      return;
    }
    
    // Create a debug image for visualization
    img.Image debugImage = img.copyResize(image, width: image.width, height: image.height);
    
    // Create marker detector
    final markerDetector = MarkerDetector(
      markerRealDistanceMm: widget.settings.markerXDistance,
      generateDebugImage: true,
    );
    
    // Create markers directly from the tap points
    final List<MarkerPoint> detectedMarkers = [];
    
    // Prepare tap regions for marker detector
    final tapRegions = [
      {
        'x': _calculateImagePoint(_originTapPoint!).x.toInt(),
        'y': _calculateImagePoint(_originTapPoint!).y.toInt(),
        'role': MarkerRole.origin
      },
      {
        'x': _calculateImagePoint(_xAxisTapPoint!).x.toInt(),
        'y': _calculateImagePoint(_xAxisTapPoint!).y.toInt(),
        'role': MarkerRole.xAxis
      },
      {
        'x': _calculateImagePoint(_scaleTapPoint!).x.toInt(),
        'y': _calculateImagePoint(_scaleTapPoint!).y.toInt(),
        'role': MarkerRole.scale
      }
    ];
    
    for (final tapPoint in tapRegions) {
      final int tapX = tapPoint['x'] as int;
      final int tapY = tapPoint['y'] as int;
      final MarkerRole role = tapPoint['role'] as MarkerRole;
      
      // Use the utility method to enhance the tap point detection
      final marker = markerDetector.findMarkerNearPoint(
        image, 
        tapX, 
        tapY, 
        math.min(image.width, image.height) ~/ 10, // Reasonable search radius
        role
      );
      
      detectedMarkers.add(marker);
      
      // Draw marker on debug image
      final color = role == MarkerRole.origin ? 
        img.ColorRgba8(255, 0, 0, 255) : 
        (role == MarkerRole.xAxis ? 
          img.ColorRgba8(0, 255, 0, 255) : 
          img.ColorRgba8(0, 0, 255, 255));
      
      DrawingUtils.drawCircle(debugImage, marker.x, marker.y, 15, color);
      DrawingUtils.drawText(debugImage, role.toString().split('.').last, 
                        marker.x + 20, marker.y - 5, color);
    }
    
    // Draw connecting lines between markers
    if (detectedMarkers.length >= 3) {
      final originMarker = detectedMarkers.firstWhere((m) => m.role == MarkerRole.origin);
      final xAxisMarker = detectedMarkers.firstWhere((m) => m.role == MarkerRole.xAxis);
      final scaleMarker = detectedMarkers.firstWhere((m) => m.role == MarkerRole.scale);
      
      // Draw line from origin to x-axis
      DrawingUtils.drawLine(
        debugImage,
        originMarker.x, originMarker.y,
        xAxisMarker.x, xAxisMarker.y,
        img.ColorRgba8(255, 255, 0, 200)
      );
      
      // Draw line from origin to scale point
      DrawingUtils.drawLine(
        debugImage,
        originMarker.x, originMarker.y,
        scaleMarker.x, scaleMarker.y,
        img.ColorRgba8(255, 255, 0, 200)
      );
    }
    
    // Create result from detected markers
    final markerResult = markerDetector.createResultFromMarkerPoints(
      detectedMarkers,
      debugImage: debugImage
    );
    
    // Store the detected markers for later use
    _detectedMarkers = detectedMarkers;
    
    // Use the flow manager to update with the marker result
    await _flowManager.detectMarkersFromUserTaps(tapRegions);
    
    setState(() {
      _markersDetected = true;
      _isLoading = false;
      _statusMessage = 'Markers detected! You can now draw the contour manually.';
      _markerSelectionState = MarkerSelectionState.complete;
    });
    
    // No popup dialog - user sees status message and buttons to continue or reset
  } catch (e, stackTrace) {
    ErrorUtils().logError(
      'Error during user-assisted marker detection',
      e,
      stackTrace: stackTrace,
      context: 'marker_detection_user_taps',
    );
    
    setState(() {
      _errorMessage = 'Marker detection failed: ${e.toString()}';
      _isLoading = false;
    });
  }
}
  void _drawMarkersOnDebugImage(img.Image debugImage, List<MarkerPoint> markers) {
  // Define colors for each marker type
  final colors = {
    MarkerRole.origin: img.ColorRgba8(255, 0, 0, 255),      // Red
    MarkerRole.xAxis: img.ColorRgba8(0, 255, 0, 255),       // Green
    MarkerRole.scale: img.ColorRgba8(0, 0, 255, 255)        // Blue
  };
  
  // Draw each marker
  for (var marker in markers) {
    final color = colors[marker.role] ?? img.ColorRgba8(255, 255, 0, 255);
    
    // Draw a circle around the marker
    DrawingUtils.drawCircle(debugImage, marker.x, marker.y, 15, color);
    
    // Draw a filled inner circle
    DrawingUtils.drawCircle(debugImage, marker.x, marker.y, 5, color, fill: true);
    
    // Draw marker role text
    final roleText = marker.role.toString().split('.').last;
    DrawingUtils.drawText(debugImage, roleText, marker.x + 20, marker.y - 5, color);
  }
  
  // Draw lines between markers if we have all three
  if (markers.length >= 3) {
    final originMarker = markers.firstWhere((m) => m.role == MarkerRole.origin);
    final xAxisMarker = markers.firstWhere((m) => m.role == MarkerRole.xAxis);
    final scaleMarker = markers.firstWhere((m) => m.role == MarkerRole.scale);
    
    // Draw line from origin to X-axis
    DrawingUtils.drawLine(
      debugImage, 
      originMarker.x, originMarker.y, 
      xAxisMarker.x, xAxisMarker.y, 
      img.ColorRgba8(255, 255, 0, 200)
    );
    
    // Draw line from origin to scale marker
    DrawingUtils.drawLine(
      debugImage, 
      originMarker.x, originMarker.y, 
      scaleMarker.x, scaleMarker.y, 
      img.ColorRgba8(255, 255, 0, 200)
    );
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
    
    // Calculate the actual seed point in the image
    final imagePoint = _calculateImagePoint(_selectedPoint!);
    
    // Verify we have markers detected before proceeding
    if (!_markersDetected) {
      throw Exception('Markers must be detected before contour detection');
    }
    
    // Check if marker result is available
    if (_flowManager.result.markerResult == null) {
      print('Marker result is null, attempting to recreate it');
      
      // Recreate marker result
      if (_detectedMarkers.length < 3) {
        throw Exception('Not enough markers detected');
      }
      
      // Create original image and debug image
      final imageBytes = await widget.imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }
      
      // Create a debug image
      img.Image debugImage = img.copyResize(originalImage, width: originalImage.width, height: originalImage.height);
      
      // Draw markers on debug image
      _drawMarkersOnDebugImage(debugImage, _detectedMarkers);
      
      // Use the marker detector to create a result
      final markerDetector = MarkerDetector(
        markerRealDistanceMm: widget.settings.markerXDistance,
        generateDebugImage: true,
      );
      
      // Recreate marker detection result
      final originMarker = _detectedMarkers.firstWhere((m) => m.role == MarkerRole.origin);
      final xAxisMarker = _detectedMarkers.firstWhere((m) => m.role == MarkerRole.xAxis);
      final scaleMarker = _detectedMarkers.firstWhere((m) => m.role == MarkerRole.scale);
      
      // Calculate parameters
      final dx = xAxisMarker.x - originMarker.x;
      final dy = xAxisMarker.y - originMarker.y;
      final orientationAngle = math.atan2(dy, dx);
      
      final scaleX = scaleMarker.x - originMarker.x;
      final scaleY = scaleMarker.y - originMarker.y;
      final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
      
      final pixelToMmRatio = widget.settings.markerXDistance / distancePx;
      
      final origin = CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble());
      
      // Create the result
      final markerResult = MarkerDetectionResult(
        markers: _detectedMarkers,
        pixelToMmRatio: pixelToMmRatio,
        origin: origin,
        orientationAngle: orientationAngle,
        debugImage: debugImage,
      );
      
      // Update flow manager
      var updatedResult = _flowManager.result.copyWith(
        markerResult: markerResult,
        processedImage: debugImage,
      );
      
      // This creates a dummy SlabContourResult just to update the flow manager
      final dummyContourResult = SlabContourResult(
        pixelContour: [],
        machineContour: [],
        debugImage: debugImage,
      );
      
      _flowManager.updateContourResult(dummyContourResult, method: ContourDetectionMethod.manual);
    }
    
    // Double-check if we have a marker result now
    if (_flowManager.result.markerResult == null) {
      throw Exception('Marker detection result not available despite recovery attempts');
    }
    
    // Use edge contour algorithm with the calculated image point coordinates
    final contourAlgorithmRegistry = await _flowManager.detectSlabContourAutomatic(
      imagePoint.x.toInt(),  // Pass the seed point x coordinate
      imagePoint.y.toInt()   // Pass the seed point y coordinate
    );
    
    setState(() {
      _contourDetected = true;
      _isLoading = false;
      _statusMessage = 'Contour detected! Tap "Continue" to generate G-code.';
      _markerSelectionState = MarkerSelectionState.complete;
    });
    
    // If automatic detection failed, offer manual drawing
    } catch (e, stackTrace) {
      ErrorUtils().logError(
        'Error during contour detection',
        e,
        stackTrace: stackTrace,
        context: 'contour_detection',
      );
      
      // Show dialog to offer manual drawing instead of just showing error
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Contour Detection Failed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.orange, size: 48),
              SizedBox(height: 16),
              Text(
                'We couldn\'t automatically detect the contour of your slab.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Would you like to draw the contour manually?',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _errorMessage = 'Contour detection failed: ${e.toString()}';
                  _isLoading = false;
                });
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startManualContourDrawing();
              },
              child: Text('Draw Manually'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
            ),
          ],
        ),
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
  if (_isLoading) return;
  
  setState(() {
    switch (_markerSelectionState) {
      case MarkerSelectionState.origin:
        _originTapPoint = details.localPosition;
        _statusMessage = 'Tap on the X-Axis marker (bottom right)';
        _markerSelectionState = MarkerSelectionState.xAxis;
        break;
        
      case MarkerSelectionState.xAxis:
        _xAxisTapPoint = details.localPosition;
        _statusMessage = 'Tap on the Y-Axis marker (top left)';
        _markerSelectionState = MarkerSelectionState.scale;
        break;
        
      case MarkerSelectionState.scale:
        _scaleTapPoint = details.localPosition;
        _detectMarkersFromTapPoints();
        break;
        
      // Skip the slab and spillboard steps - we'll move directly to manual drawing
      case MarkerSelectionState.slab:
      case MarkerSelectionState.spillboard:
        // These states are now skipped
        break;
      
      case MarkerSelectionState.manualDrawing:
        // This is handled in the ManualContourDrawer
        break;
        
      case MarkerSelectionState.complete:
        // Do nothing when we've completed all the steps
        break;
    }
  });
}

  CoordinatePointXY _calculateImagePoint(Offset tapPosition) {
  if (_imageSize == null) {
    return CoordinatePointXY(0, 0);
  }
  
  // Get the direct parent render object of the image
  final RenderBox imageContainer = context.findRenderObject() as RenderBox;
  
  // Use the specific constant value that is known to work
  final markerOverlaySize = Size(imageContainer.size.width, detectorScreenOverlayHeight); 
  
  print('DEBUG: Tap position: ${tapPosition.dx}x${tapPosition.dy}');
  print('DEBUG: Using overlay size: ${markerOverlaySize.width}x${markerOverlaySize.height}');
  
  // Use the same logic as in imageToDisplayCoordinates but in reverse
  final imageAspect = _imageSize!.width / _imageSize!.height;
  final displayAspect = markerOverlaySize.width / markerOverlaySize.height;
  
  double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
  
  if (imageAspect > displayAspect) {
    // Image is wider than display area (letterboxing)
    displayWidth = markerOverlaySize.width;
    displayHeight = displayWidth / imageAspect;
    offsetY = (markerOverlaySize.height - displayHeight) / 2;
  } else {
    // Image is taller than display area (pillarboxing)
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

void _showDebugImage() {
    if (_flowManager.result.markerResult?.debugImage == null && 
        _flowManager.result.contourResult?.debugImage == null) return;
    
    final debugImage = _flowManager.result.markerResult?.debugImage ?? 
                       _flowManager.result.contourResult?.debugImage;
    
    if (debugImage == null) return;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                _markersDetected && !_contourDetected ? 
                  'Marker Detection Debug Image' : 
                  'Contour Detection Debug Image',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Image.memory(
              Uint8List.fromList(
                img.encodePng(debugImage)
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Image dimensions: ${debugImage.width}x${debugImage.height}',
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
            onTapDown: _handleImageTap,
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
                      strokeWidth: defaultContourStrokeWidth,
                    ),
                  ),
                  
                // Draw marker tap indicators
                if (_originTapPoint != null && !_markersDetected)
                  Positioned(
                    left: _originTapPoint!.dx - seedPointIndicatorSize / 2,
                    top: _originTapPoint!.dy - seedPointIndicatorSize / 2,
                    child: Container(
                      width: seedPointIndicatorSize,
                      height: seedPointIndicatorSize,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(seedPointIndicatorOpacity),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.red, width: seedPointIndicatorBorderWidth),
                      ),
                      child: Center(
                        child: Text("O", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                
                if (_xAxisTapPoint != null && !_markersDetected)
                  Positioned(
                    left: _xAxisTapPoint!.dx - seedPointIndicatorSize / 2,
                    top: _xAxisTapPoint!.dy - seedPointIndicatorSize / 2,
                    child: Container(
                      width: seedPointIndicatorSize,
                      height: seedPointIndicatorSize,
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(seedPointIndicatorOpacity),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.green, width: seedPointIndicatorBorderWidth),
                      ),
                      child: Center(
                        child: Text("X", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                
                if (_scaleTapPoint != null && !_markersDetected)
                  Positioned(
                    left: _scaleTapPoint!.dx - seedPointIndicatorSize / 2,
                    top: _scaleTapPoint!.dy - seedPointIndicatorSize / 2,
                    child: Container(
                      width: seedPointIndicatorSize,
                      height: seedPointIndicatorSize,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(seedPointIndicatorOpacity),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.blue, width: seedPointIndicatorBorderWidth),
                      ),
                      child: Center(
                        child: Text("Y", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  
                // Seed point indicator for slab
                if (_selectedPoint != null && _markersDetected && !_contourDetected)
                  Positioned(
                    left: _selectedPoint!.dx - seedPointIndicatorSize / 2,
                    top: _selectedPoint!.dy - seedPointIndicatorSize / 2,
                    child: Container(
                      width: seedPointIndicatorSize,
                      height: seedPointIndicatorSize,
                      decoration: BoxDecoration(
                        color: Colors.yellow.withOpacity(seedPointIndicatorOpacity),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.orange, width: seedPointIndicatorBorderWidth),
                      ),
                    ),
                  ),
                  
                  if (_spillboardTapPoint != null && (_markerSelectionState == MarkerSelectionState.complete || _markerSelectionState == MarkerSelectionState.spillboard))
                  Positioned(
                    left: _spillboardTapPoint!.dx - seedPointIndicatorSize / 2,
                    top: _spillboardTapPoint!.dy - seedPointIndicatorSize / 2,
                    child: Container(
                      width: seedPointIndicatorSize,
                      height: seedPointIndicatorSize,
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(seedPointIndicatorOpacity),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.purple, width: seedPointIndicatorBorderWidth),
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
                          SizedBox(height: padding),
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
          
        // Status bar
        Container(
          padding: EdgeInsets.all(smallPadding),
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
        // After markers detected but before contour, show the manual draw button
        if (_markersDetected && !_contourDetected) 
          ElevatedButton.icon(
            icon: Icon(Icons.draw, color: Colors.white),
            label: Text('Draw Contour Manually', style: TextStyle(color: Colors.white)),
            onPressed: _isLoading ? null : _startManualContourDrawing,
            style: ElevatedButton.styleFrom(
              minimumSize: Size(double.infinity, 48),
              backgroundColor: Colors.blue,
            ),
          ),
        
        // Detect Markers Button
        if (_markerSelectionState == MarkerSelectionState.scale && 
            _originTapPoint != null && _xAxisTapPoint != null && _scaleTapPoint != null)
          ElevatedButton.icon(
            icon: Icon(Icons.check_circle, color: Colors.white),
            label: Text('Detect Markers', style: TextStyle(color: Colors.white)),
            onPressed: _isLoading ? null : _detectMarkersFromTapPoints,
            style: ElevatedButton.styleFrom(
              minimumSize: Size(double.infinity, 48),
              backgroundColor: Colors.blue,
            ),
          ),
        
        SizedBox(height: 8),
        
        // Rest of buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(Icons.refresh),
                label: Text('Reset'),
                onPressed: _isLoading ? null : _resetDetection,
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
                icon: Icon(Icons.arrow_forward, color: Colors.white),
                label: Text('Continue', style: TextStyle(color: Colors.white)),
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

  void _startManualContourDrawing() {
    setState(() {
      _isLoading = false;
      _errorMessage = '';
      _statusMessage = 'Drawing contour manually';
    });
    
    // Show the manual drawing widget as a full-screen dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog.fullscreen(
        child: Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Show the image in the background
              Center(
                child: Image.file(
                  widget.imageFile,
                  fit: BoxFit.contain,
                ),
              ),
              
              // Add semi-transparent overlay for better contrast
              Container(
                color: Colors.black.withOpacity(0.1),
              ),
              
              // Add the manual contour drawer on top
              RepaintBoundary(
                child: ManualContourDrawer(
                  key: UniqueKey(), // Force creation of a new instance
                  imageSize: _imageSize!,
                  onContourComplete: (contourPoints) {
                    // Close the dialog
                    Navigator.of(context).pop();
                    
                    // Process the manually drawn contour
                    _processManualContour(contourPoints);
                  },
                  onCancel: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Method to process the manually drawn contour (add after the method above)
  void _processManualContour(List<CoordinatePointXY> contourPoints) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Processing manual contour...';
    });
    
    try {
      final provider = Provider.of<ProcessingProvider>(context, listen: false);
      final flowManager = provider.flowManager;
      
      if (flowManager == null || flowManager.result.markerResult == null) {
        throw Exception('Marker detection must be completed before contour detection');
      }
      
      // Create coordinate system
      final markerResult = flowManager.result.markerResult!;
      final coordSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
        markerResult.markers[0].toPoint(),
        markerResult.markers[1].toPoint(),
        markerResult.markers[2].toPoint(),
        widget.settings.markerXDistance,
        widget.settings.markerYDistance
      );
      
      // Load original image for visualization
      final imageBytes = await widget.imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      
      // Create a debug image for visualization
      final debugImage = img.copyResize(image, width: image.width, height: image.height);
      
      // Draw the contour on the debug image
      DrawingUtils.drawContour(
        debugImage, 
        contourPoints, 
        img.ColorRgba8(0, 255, 0, 255), 
        thickness: 3
      );
      
      // Convert to machine coordinates
      final machineContour = coordSystem.convertPointListToMachineCoords(contourPoints);
      
      // Create contour result
      final contourResult = SlabContourResult(
        pixelContour: contourPoints,
        machineContour: machineContour,
        debugImage: debugImage,
      );
      
      // Update the flow manager
      flowManager.updateContourResult(contourResult, method: ContourDetectionMethod.manual);
      
      setState(() {
        _contourDetected = true;
        _isLoading = false;
        _statusMessage = 'Manual contour processed successfully. Tap "Continue" to generate G-code.';
        _markerSelectionState = MarkerSelectionState.complete;
      });
    } catch (e, stackTrace) {
      ErrorUtils().logError(
        'Error processing manual contour',
        e,
        stackTrace: stackTrace,
        context: 'manual_contour_processing',
      );
      
      setState(() {
        _errorMessage = 'Error processing manual contour: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _resetDetection() {
  setState(() {
    _markersDetected = false;
    _contourDetected = false;
    _selectedPoint = null;
    _originTapPoint = null;
    _xAxisTapPoint = null;
    _scaleTapPoint = null;
    _spillboardTapPoint = null;
    _errorMessage = '';
    _statusMessage = 'Tap on the Origin marker (bottom left)';
    _markerSelectionState = MarkerSelectionState.origin;
    _detectedMarkers = [];
  });
  
  _flowManager.reset();
  _initializeDetection();
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
    } else if (_markersDetected && _flowManager.result.markerResult?.debugImage != null) {
      // Use Image.memory to display the debug image if markers were detected
      return Center(
        child: Image.memory(
          Uint8List.fromList(img.encodePng(_flowManager.result.markerResult!.debugImage!)),
          fit: BoxFit.contain,
        ),
      );
    } else {
      // Show the original image if no debug images available
      // Remove all padding to fix positioning issues
      return Center(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              _flowManager.result.originalImage!,
              fit: BoxFit.contain, 
            ),
            
            // Only show one overlay, not both
            if (_contourDetected && _flowManager.result.contourResult != null && _imageSize != null)
              ContourOverlay(
                contourPoints: _flowManager.result.contourResult!.pixelContour,
                imageSize: _imageSize!,
                color: Colors.green,
                strokeWidth: defaultContourStrokeWidth,
              ),
          ],
        ),
      );
    }
  } else {
    return Center(child: Text('Image not available'));
  }
}

void _updateLocalSettings(SettingsModel updatedSettings) {
    setState(() {
      // Update the settings in the flow manager
      if (_flowManager != null) {
        _flowManager.updateSettings(updatedSettings);
      }
    });
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

}}