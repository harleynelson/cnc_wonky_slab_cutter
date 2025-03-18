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
  Point? _originMarkerPoint;
  Point? _xAxisMarkerPoint;
  Point? _yAxisMarkerPoint;
  
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
    
    // Verify tap is within a reasonable range for the image container
    final RenderBox imageContainer = context.findRenderObject() as RenderBox;
    final containerSize = imageContainer.size;
    
    if (tapPosition.dx < 0 || tapPosition.dx > containerSize.width || 
        tapPosition.dy < 0 || tapPosition.dy > 438.0) { // Using fixed height of 438
      print('DEBUG: Tap outside of image container bounds');
      return;
    }
    
    // Calculate actual image coordinates from tap position
    final imagePoint = _calculateImagePoint(tapPosition);
    
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
        _statusMessage = 'Processing markers...';
        _processMarkerPoints();
      }
    });
  }
  
  Future<void> _processMarkerPoints() async {
  if (_originMarkerPoint == null || _xAxisMarkerPoint == null || _yAxisMarkerPoint == null) {
    setState(() {
      _errorMessage = 'All three marker points are required';
    });
    return;
  }
  
  setState(() {
    _isLoading = true;
    _statusMessage = 'Processing marker points...';
  });
  
  try {
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
    
    // Calculate orientation angle
    final dx = xAxisMarker.x - originMarker.x;
    final dy = xAxisMarker.y - originMarker.y;
    final orientationAngle = math.atan2(dy, dx);
    
    // Calculate pixel to mm ratio
    final scaleX = scaleMarker.x - originMarker.x;
    final scaleY = scaleMarker.y - originMarker.y;
    final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
    
    // Validate markers aren't collinear or too close
    if (distancePx < 10.0) {
      throw Exception('Scale marker too close to origin');
    }
    
    // Create marker detection result
    final markers = [originMarker, xAxisMarker, scaleMarker];
    final origin = Point(originMarker.x.toDouble(), originMarker.y.toDouble());
    
    // Load the original image
    final imageBytes = await widget.imageFile.readAsBytes();
    final image = img.decodePng(imageBytes);
    
    if (image == null) {
      throw Exception('Failed to decode image');
    }
    
    // Apply OpenCV perspective correction
    final correctedImage = await ImageCorrectionUtils.correctPerspective(
      image, 
      originMarker.toPoint(), 
      xAxisMarker.toPoint(), 
      scaleMarker.toPoint(),
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
    final pixelToMmRatio = (widget.settings.markerXDistance / correctedImage.width + 
                           widget.settings.markerYDistance / correctedImage.height) / 2;
    
    // Create marker result
    final markerResult = MarkerDetectionResult(
      markers: markers,
      pixelToMmRatio: pixelToMmRatio,
      origin: origin,
      orientationAngle: orientationAngle,
      debugImage: null
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
  
  Point _calculateImagePoint(Offset tapPosition) {
  if (_imageSize == null) {
    return Point(0, 0);
  }
  
  final RenderBox box = context.findRenderObject() as RenderBox;
  final Size boxSize = box.size;
  
  // Calculate image display size and position within container
  final double imageAspect = _imageSize!.width / _imageSize!.height;
  final double boxAspect = boxSize.width / boxSize.height;
  
  double scaledWidth, scaledHeight;
  double offsetX = 0, offsetY = 0;
  
  if (imageAspect > boxAspect) {
    // Image is wider than box - fills width, centers vertically
    scaledWidth = boxSize.width;
    scaledHeight = boxSize.width / imageAspect;
    offsetY = (boxSize.height - scaledHeight) / 2;
  } else {
    // Image is taller than box - fills height, centers horizontally
    scaledHeight = boxSize.height;
    scaledWidth = boxSize.height * imageAspect;
    offsetX = (boxSize.width - scaledWidth) / 2;
  }
  
  // Check if tap is inside image bounds
  if (tapPosition.dx < offsetX || tapPosition.dx > offsetX + scaledWidth ||
      tapPosition.dy < offsetY || tapPosition.dy > offsetY + scaledHeight) {
    print("Warning: Tap outside image bounds");
  }
  
  // Convert tap position to image coordinates
  final imageX = ((tapPosition.dx - offsetX) / scaledWidth) * _imageSize!.width;
  final imageY = ((tapPosition.dy - offsetY) / scaledHeight) * _imageSize!.height;
  
  return Point(imageX, imageY);
}
  
  Widget _buildSamplePointIndicator(Point point, Color color, String label) {
  final RenderBox box = context.findRenderObject() as RenderBox;
  final Size boxSize = box.size;
  
  // Calculate image display size and position
  final double imageAspect = _imageSize!.width / _imageSize!.height;
  final double boxAspect = boxSize.width / boxSize.height;
  
  double scaledWidth, scaledHeight;
  double offsetX = 0, offsetY = 0;
  
  if (imageAspect > boxAspect) {
    scaledWidth = boxSize.width;
    scaledHeight = boxSize.width / imageAspect;
    offsetY = (boxSize.height - scaledHeight) / 2;
  } else {
    scaledHeight = boxSize.height;
    scaledWidth = boxSize.height * imageAspect;
    offsetX = (boxSize.width - scaledWidth) / 2;
  }
  
  // Convert image to screen coordinates
  final screenX = (point.x / _imageSize!.width) * scaledWidth + offsetX;
  final screenY = (point.y / _imageSize!.height) * scaledHeight + offsetY;
  
  return Positioned(
    left: screenX - 10,
    top: screenY - 10,
    child: Column(
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
  
  Widget _buildImageDisplay() {
    if (_flowManager.result.originalImage != null) {
      if (_markersDetected && _flowManager.result.correctedImage != null) {
        // Display corrected image
        return Center(
          child: Image.file(
            _flowManager.result.correctedImage!,
            fit: BoxFit.contain,
          ),
        );
      } else {
        // Show the original image if not yet corrected
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
                    "Scale Marker"
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
            
            Text('Place three markers on your slab:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  child: Text('Tap the Y marker (top left corner)'),
                ),
              ],
            ),
            
            SizedBox(height: 12),
            Text(
              'The app will correct the image to match the real-world coordinates for accurate CNC processing.',
              style: TextStyle(fontStyle: FontStyle.italic),
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