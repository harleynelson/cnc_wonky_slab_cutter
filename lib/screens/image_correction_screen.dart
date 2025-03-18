// lib/screens/image_correction_screen.dart
// Screen for correcting image perspective based on marker positions

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/flow/processing_flow_manager.dart';
import '../utils/general/coordinate_utils.dart';
import '../utils/image_processing/image_correction_utils.dart';
import '../utils/general/machine_coordinates.dart';
import '../services/detection/marker_detector.dart';
import 'slab_detection_screen.dart';

class ImageCorrectionScreen extends StatefulWidget {
  final File imageFile;
  final SettingsModel settings;
  final Function(SettingsModel)? onSettingsChanged;

  const ImageCorrectionScreen({
    Key? key,
    required this.imageFile,
    required this.settings,
    this.onSettingsChanged,
  }) : super(key: key);

  @override
  _ImageCorrectionScreenState createState() => _ImageCorrectionScreenState();
}

class _ImageCorrectionScreenState extends State<ImageCorrectionScreen> {
  bool _isLoading = false;
  String _statusMessage = 'Tap the ORIGIN marker (bottom left)';
  String _errorMessage = '';
  
  // Image dimensions for overlays
  Size? _imageSize;
  
  // Flow Manager
  late ProcessingFlowManager _flowManager;
  
  // Processing state
  bool _markersDetected = false;
  
  // Marker positions
  CoordinatePointXY? _originMarkerPoint;
  CoordinatePointXY? _xAxisMarkerPoint;
  CoordinatePointXY? _yAxisMarkerPoint;
  CoordinatePointXY? _topRightMarkerPoint;
  
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
        _statusMessage = 'Tap the ORIGIN marker (bottom left)';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Initialization error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  void _handleImageTap(TapDownDetails details) {
    if (_isLoading || _markersDetected) return;
    
    final tapPosition = details.localPosition;
    
    // Log raw tap position for debugging
    print('DEBUG: Raw tap at (${tapPosition.dx}, ${tapPosition.dy})');
    
    // Calculate actual image coordinates from tap position using the standard utility
    final containerSize = CoordinateUtils.getEffectiveContainerSize(context);
    final imagePoint = CoordinateUtils.tapPositionToImageCoordinates(
      tapPosition, 
      _imageSize!, 
      containerSize,
      debug: true
    );
    
    print('DEBUG: Calculated image point: (${imagePoint.x}, ${imagePoint.y})');
    
    setState(() {
      if (_originMarkerPoint == null) {
        _originMarkerPoint = imagePoint;
        _statusMessage = 'Tap the X-AXIS marker (bottom right)';
      } else if (_xAxisMarkerPoint == null) {
        _xAxisMarkerPoint = imagePoint;
        _statusMessage = 'Tap the Y-AXIS marker (top left)';
      } else if (_yAxisMarkerPoint == null) {
        _yAxisMarkerPoint = imagePoint;
        _statusMessage = 'Tap the TOP-RIGHT marker (top right)';
      } else if (_topRightMarkerPoint == null) {
        _topRightMarkerPoint = imagePoint;
        _statusMessage = 'Processing markers...';
        _processMarkerPoints();
      }
    });
  }
  
  Future<void> _processMarkerPoints() async {
    if (_originMarkerPoint == null || _xAxisMarkerPoint == null || 
        _yAxisMarkerPoint == null || _topRightMarkerPoint == null) {
      setState(() {
        _errorMessage = 'All four marker points are required';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Processing marker points...';
    });
    
    try {
      // Validate points are within image bounds
      if (_isPointOutOfBounds(_originMarkerPoint!) || 
          _isPointOutOfBounds(_xAxisMarkerPoint!) ||
          _isPointOutOfBounds(_yAxisMarkerPoint!) ||
          _isPointOutOfBounds(_topRightMarkerPoint!)) {
        throw Exception('One or more markers are outside the image bounds');
      }
      
      // Create marker points from tap positions
      final originMarker = MarkerPoint(
        _originMarkerPoint!.x.toInt(), 
        _originMarkerPoint!.y.toInt(), 
        MarkerRole.origin
      );
      
      final xAxisMarker = MarkerPoint(
        _xAxisMarkerPoint!.x.toInt(), 
        _xAxisMarkerPoint!.y.toInt(), 
        MarkerRole.xAxis
      );
      
      final scaleMarker = MarkerPoint(
        _yAxisMarkerPoint!.x.toInt(), 
        _yAxisMarkerPoint!.y.toInt(), 
        MarkerRole.scale
      );
      
      final topRightMarker = MarkerPoint(
        _topRightMarkerPoint!.x.toInt(), 
        _topRightMarkerPoint!.y.toInt(), 
        MarkerRole.topRight
      );
      
      // Calculate orientation angle
      final dx = xAxisMarker.x - originMarker.x;
      final dy = xAxisMarker.y - originMarker.y;
      final orientationAngle = math.atan2(dy, dx);
      
      // Validate markers aren't too close
      final bottomEdgeLength = math.sqrt(math.pow(xAxisMarker.x - originMarker.x, 2) + 
                                       math.pow(xAxisMarker.y - originMarker.y, 2));
      final leftEdgeLength = math.sqrt(math.pow(scaleMarker.x - originMarker.x, 2) + 
                                     math.pow(scaleMarker.y - originMarker.y, 2));
                                     
      if (bottomEdgeLength < 10.0 || leftEdgeLength < 10.0) {
        throw Exception('Markers too close together');
      }
      
      // Create marker detection result
      final markers = [originMarker, xAxisMarker, scaleMarker, topRightMarker];
      final origin = CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble());
      
      // Load the original image for visualization
      final imageBytes = await widget.imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      
      // Apply perspective correction with four markers
      final correctedImage = await ImageCorrectionUtils.correctPerspective(
        image, 
        originMarker.toPoint(), 
        xAxisMarker.toPoint(), 
        scaleMarker.toPoint(),
        topRightMarker.toPoint(),
        widget.settings.markerXDistance,
        widget.settings.markerYDistance
      );
      
      // Save the corrected image to a temporary file
      final tempDir = await Directory.systemTemp.createTemp('corrected_image_');
      final correctedImagePath = '${tempDir.path}/corrected_image.png';
      final correctedImageBytes = img.encodePng(correctedImage);
      final correctedImageFile = File(correctedImagePath);
      await correctedImageFile.writeAsBytes(correctedImageBytes);
      
      // Calculate pixel to mm ratio for corrected image
      final pixelToMmRatioX = widget.settings.markerXDistance / (xAxisMarker.x - originMarker.x).abs();
      final pixelToMmRatioY = widget.settings.markerYDistance / (scaleMarker.y - originMarker.y).abs();
      final pixelToMmRatio = (pixelToMmRatioX + pixelToMmRatioY) / 2;
      
      // Create marker result
      final markerResult = MarkerDetectionResult(
        markers: markers,
        pixelToMmRatio: pixelToMmRatio,
        origin: origin,
        orientationAngle: orientationAngle,
        debugImage: null // No debug image
      );
      
      // Update the flow manager with the corrected image and markers
      _flowManager.updateCorrectedImage(
        correctedImageFile,
        markerResult
      );
      
      setState(() {
        _markersDetected = true;
        _isLoading = false;
        _statusMessage = 'Image corrected! Tap "Continue" to proceed.';
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Error processing markers: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  // Helper method to check if a point is outside image bounds
  bool _isPointOutOfBounds(CoordinatePointXY point) {
    if (_imageSize == null) return true;
    
    return point.x < 0 || 
           point.x >= _imageSize!.width || 
           point.y < 0 || 
           point.y >= _imageSize!.height;
  }
  
  CoordinatePointXY _calculateImagePoint(Offset tapPosition) {
    if (_imageSize == null) {
      return CoordinatePointXY(0, 0);
    }
    
    // Get the container size
    final RenderBox box = context.findRenderObject() as RenderBox;
    final containerSize = Size(box.size.width, box.size.height);
    
    // Use the standard utility method for coordinate transformation
    final displayPoint = CoordinatePointXY(tapPosition.dx, tapPosition.dy);
    final imagePoint = MachineCoordinateSystem.displayToImageCoordinates(
      displayPoint, 
      _imageSize!, 
      containerSize
    );
    
    // Ensure point is within image bounds
    final clampedX = imagePoint.x.clamp(0.0, _imageSize!.width - 1);
    final clampedY = imagePoint.y.clamp(0.0, _imageSize!.height - 1);
    
    return CoordinatePointXY(clampedX, clampedY);
  }
  
  Widget _buildSamplePointIndicator(CoordinatePointXY point, Color color, String label) {
    if (_imageSize == null) return Container();
    
    // Get effective container size
    final containerSize = CoordinateUtils.getEffectiveContainerSize(context);
    
    // Convert image coordinates to display position using the standard utility
    final displayPosition = CoordinateUtils.imageCoordinatesToDisplayPosition(
      point, 
      _imageSize!, 
      containerSize,
      debug: true
    );
    
    return Positioned(
      left: displayPosition.dx - 10,
      top: displayPosition.dy - 10,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color.withOpacity(0.7),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
          Container(
            margin: EdgeInsets.only(top: 4),
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _continueToSlabDetection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SlabDetectionScreen(
          settings: widget.settings,
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    );
  }
  
  void _resetDetection() {
    setState(() {
      _markersDetected = false;
      _originMarkerPoint = null;
      _xAxisMarkerPoint = null;
      _yAxisMarkerPoint = null;
      _topRightMarkerPoint = null;
      _errorMessage = '';
      _statusMessage = 'Tap the ORIGIN marker (bottom left)';
    });
    
    _flowManager.reset();
    _initializeDetection();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Perspective Correction'),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
            tooltip: 'How to use',
          ),
        ],
      ),
      body: Column(
        children: [
          // Main content area - responsive
          Expanded(
            child: GestureDetector(
              onTapDown: _handleImageTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Image display
                  Center(
                    child: _imageSize != null
                        ? AspectRatio(
                            aspectRatio: _imageSize!.width / _imageSize!.height,
                            child: _markersDetected && _flowManager.result.correctedImage != null
                                ? Image.file(
                                    _flowManager.result.correctedImage!,
                                    fit: BoxFit.contain,
                                  )
                                : Image.file(
                                    _flowManager.result.originalImage!,
                                    fit: BoxFit.contain,
                                  ),
                          )
                        : Container(
                            child: Text('Image not available'),
                          ),
                  ),
                  
                  // Marker point indicators
                  if (_originMarkerPoint != null && _imageSize != null)
                    _buildSamplePointIndicator(
                      _originMarkerPoint!, 
                      Colors.red,
                      "Origin Marker"
                    ),
                    
                  if (_xAxisMarkerPoint != null && _imageSize != null)
                    _buildSamplePointIndicator(
                      _xAxisMarkerPoint!, 
                      Colors.green,
                      "X-Axis Marker"
                    ),
                    
                  if (_yAxisMarkerPoint != null && _imageSize != null)
                    _buildSamplePointIndicator(
                      _yAxisMarkerPoint!, 
                      Colors.blue,
                      "Y-Axis Marker"
                    ),
                    
                  if (_topRightMarkerPoint != null && _imageSize != null)
                    _buildSamplePointIndicator(
                      _topRightMarkerPoint!, 
                      Colors.yellow,
                      "Top-Right Marker"
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
          // Reset Button
          ElevatedButton.icon(
            icon: Icon(Icons.refresh),
            label: Text('Reset Markers'),
            onPressed: _isLoading ? null : _resetDetection,
            style: ElevatedButton.styleFrom(
              minimumSize: Size(double.infinity, 48),
              backgroundColor: Colors.orange,
            ),
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
                  onPressed: _isLoading || !_markersDetected ? null : _continueToSlabDetection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _markersDetected ? Colors.green : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Perspective Correction Help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This step corrects the image perspective to create accurate measurements for the CNC machine.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            
            Text('Place four markers on your slab to form a perfect rectangle:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.red, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap the ORIGIN marker (bottom left corner)'),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.green, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap the X-AXIS marker (bottom right corner)'),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap the Y-AXIS marker (top left corner)'),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.yellow, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap the TOP-RIGHT marker (top right corner)'),
                ),
              ],
            ),
            
            SizedBox(height: 12),
            Text(
              'The app will correct the image to match the real-world coordinates for accurate CNC processing. Make sure your markers form a true rectangle with 90-degree corners.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
            SizedBox(height: 12),
            Text(
              'Why four markers? Using all four corners allows for precise perspective correction, which is essential for accurate CNC measurements and operations.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }
}