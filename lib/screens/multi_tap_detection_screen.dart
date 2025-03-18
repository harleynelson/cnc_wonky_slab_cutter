// lib/screens/multi_tap_detection_screen.dart
// Screen for multi-tap detection to differentiate between similar colored materials

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/detection/marker_detector.dart';
import '../services/detection/slab_contour_result.dart';
import '../services/flow/processing_flow_manager.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/image_processing/image_utils.dart';
import '../utils/image_processing/multi_tap_detection_utils.dart';
import '../widgets/contour_overlay.dart';
import '../widgets/marker_overlay.dart';
import 'gcode_generator_screen.dart';

enum MultiTapMode {
  originMarkerSelection,
  xAxisMarkerSelection,
  scaleMarkerSelection,
  slabSelection,
  spillboardSelection,
  contourDetection,
  contourReady
}

class MultiTapDetectionScreen extends StatefulWidget {
  final File imageFile;
  final SettingsModel settings;
  final Function(SettingsModel)? onSettingsChanged;

  const MultiTapDetectionScreen({
    Key? key,
    required this.imageFile,
    required this.settings,
    this.onSettingsChanged,
  }) : super(key: key);

  @override
  _MultiTapDetectionScreenState createState() => _MultiTapDetectionScreenState();
}

class _MultiTapDetectionScreenState extends State<MultiTapDetectionScreen> {
  bool _isLoading = false;
  String _statusMessage = 'Tap on the slab to select a sample point';
  String _errorMessage = '';
  
  // Image dimensions for overlays
  Size? _imageSize;
  
  // Flow Manager
  late ProcessingFlowManager _flowManager;
  
  // Multi-tap mode tracking
  MultiTapMode _currentMode = MultiTapMode.originMarkerSelection;
  
  // Sample points
  CoordinatePointXY? _slabSamplePoint;
  CoordinatePointXY? _spillboardSamplePoint;
  
  // Marker points
  CoordinatePointXY? _originMarkerPoint;
  CoordinatePointXY? _xAxisMarkerPoint;
  CoordinatePointXY? _scaleMarkerPoint;
  
  // Region samples with color information
  RegionSample? _slabSample;
  RegionSample? _spillboardSample;
  
  // Detection result
  List<CoordinatePointXY>? _contourPoints;
  
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
      final decodedImage = await decodeImageFromList(imageBytes);
      
      setState(() {
        _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
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
  if (_isLoading) return;
  
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
    switch (_currentMode) {
      case MultiTapMode.originMarkerSelection:
        _originMarkerPoint = imagePoint;
        _statusMessage = 'Tap the X-AXIS marker (bottom right)';
        _currentMode = MultiTapMode.xAxisMarkerSelection;
        break;
        
      case MultiTapMode.xAxisMarkerSelection:
        _xAxisMarkerPoint = imagePoint;
        _statusMessage = 'Tap the SCALE/Y-AXIS marker (top left)';
        _currentMode = MultiTapMode.scaleMarkerSelection;
        break;
        
      case MultiTapMode.scaleMarkerSelection:
        _scaleMarkerPoint = imagePoint;
        _statusMessage = 'Tap on the SLAB to select a sample point';
        _currentMode = MultiTapMode.slabSelection;
        // Process marker points first
        _processMarkerPoints();
        break;
        
      case MultiTapMode.slabSelection:
        // First tap selects slab sample
        _slabSamplePoint = imagePoint;
        _statusMessage = 'Tap on the SPILLBOARD (background) to select a sample point';
        _currentMode = MultiTapMode.spillboardSelection;
        break;
        
      case MultiTapMode.spillboardSelection:
        // Second tap selects spillboard sample
        _spillboardSamplePoint = imagePoint;
        _statusMessage = 'Processing samples...';
        _currentMode = MultiTapMode.contourDetection;
        // Trigger contour detection with samples
        _processRegionSamples();
        break;
        
      case MultiTapMode.contourDetection:
      case MultiTapMode.contourReady:
        // Allow re-sampling if needed
        _resetSamples();
        break;
    }
  });
}

  Future<void> _processMarkerPoints() async {
    if (_originMarkerPoint == null || _xAxisMarkerPoint == null || _scaleMarkerPoint == null) {
      setState(() {
        _errorMessage = 'All three marker points are required';
        _currentMode = MultiTapMode.originMarkerSelection;
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
        _scaleMarkerPoint!.x.toInt(), 
        _scaleMarkerPoint!.y.toInt(), 
        MarkerRole.scale
      );
      
      // Calculate orientation angle
      final dx = xAxisMarker.x - originMarker.x;
      final dy = xAxisMarker.y - originMarker.y;
      final orientationAngle = math.atan2(dy, dx);
      
      // Calculate pixel to mm ratio
      final scaleX = scaleMarker.x - originMarker.x;
      final scaleY = scaleMarker.y - originMarker.y;
      final distanceInPixels = math.sqrt(scaleX * scaleX + scaleY * scaleY);
      final pixelToMmRatio = widget.settings.markerYDistance / distanceInPixels;
      
      // Create marker detection result
      final markers = [originMarker, xAxisMarker, scaleMarker];
      final origin = CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble());
      
      // Load the original image for visualization
      final imageBytes = await widget.imageFile.readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      
      // Create a debug visualization
      final debugImage = img.copyResize(image, width: image.width, height: image.height);
      
      // Draw the markers on the debug image
      for (final marker in markers) {
        final color = marker.role == MarkerRole.origin 
            ? img.ColorRgba8(255, 0, 0, 255)  // Red for origin
            : marker.role == MarkerRole.xAxis 
                ? img.ColorRgba8(0, 255, 0, 255)  // Green for X-axis
                : img.ColorRgba8(0, 0, 255, 255); // Blue for scale
                
        ImageUtils.drawCircle(
          debugImage, 
          marker.x, 
          marker.y, 
          10, 
          color, 
          fill: true
        );
        
        ImageUtils.drawText(
          debugImage,
          marker.role.toString().split('.').last,
          marker.x + 15,
          marker.y,
          color
        );
      }
      
      // Draw lines between markers
      ImageUtils.drawLine(
        debugImage,
        originMarker.x,
        originMarker.y,
        xAxisMarker.x,
        xAxisMarker.y,
        img.ColorRgba8(255, 255, 0, 255)  // Yellow line
      );
      
      ImageUtils.drawLine(
        debugImage,
        originMarker.x,
        originMarker.y,
        scaleMarker.x,
        scaleMarker.y,
        img.ColorRgba8(0, 255, 255, 255)  // Cyan line
      );
      
      // Create marker result
      final markerResult = MarkerDetectionResult(
        markers: markers,
        pixelToMmRatio: pixelToMmRatio,
        origin: origin,
        orientationAngle: orientationAngle,
        debugImage: debugImage
      );
      
      // Update the flow manager with the new marker result
      _flowManager.updateMarkerResult(markerResult);
      
      setState(() {
        _isLoading = false;
        _statusMessage = 'Tap on the SLAB to select a sample point';
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Error processing markers: ${e.toString()}';
        _isLoading = false;
        _currentMode = MultiTapMode.originMarkerSelection;
      });
    }
  }
  
  void _resetSamples() {
    setState(() {
      _originMarkerPoint = null;
      _xAxisMarkerPoint = null;
      _scaleMarkerPoint = null;
      _slabSamplePoint = null;
      _spillboardSamplePoint = null;
      _slabSample = null;
      _spillboardSample = null;
      _contourPoints = null;
      _currentMode = MultiTapMode.originMarkerSelection;
      _statusMessage = 'Tap the ORIGIN marker (bottom left)';
    });
  }
  
  
  Future<void> _processRegionSamples() async {
  if (_slabSamplePoint == null || _spillboardSamplePoint == null) {
    setState(() {
      _errorMessage = 'Both slab and spillboard sample points are required';
      _currentMode = MultiTapMode.slabSelection;
    });
    return;
  }
  
  setState(() {
    _isLoading = true;
    _statusMessage = 'Analyzing samples and detecting contour...';
  });
  
  try {
    // Load the original image for processing
    final imageBytes = await widget.imageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);
    
    if (image == null) {
      throw Exception('Failed to decode image');
    }
    
    // Extract color samples from the tapped regions
    final slabX = _slabSamplePoint!.x.toInt();
    final slabY = _slabSamplePoint!.y.toInt();
    final spillboardX = _spillboardSamplePoint!.x.toInt();
    final spillboardY = _spillboardSamplePoint!.y.toInt();
    
    // Get the pixel colors
    final slabPixel = image.getPixel(slabX, slabY);
    final spillboardPixel = image.getPixel(spillboardX, spillboardY);
    
    // Create region samples
    _slabSample = RegionSample(
      _slabSamplePoint!,
      [slabPixel.r.toInt(), slabPixel.g.toInt(), slabPixel.b.toInt()],
      'Slab'
    );
    
    _spillboardSample = RegionSample(
      _spillboardSamplePoint!,
      [spillboardPixel.r.toInt(), spillboardPixel.g.toInt(), spillboardPixel.b.toInt()],
      'Spillboard'
    );
    
    // Detect contour using the samples
    _contourPoints = MultiTapDetectionUtils.findContourWithRegionSamples(
      image,
      _slabSample!,
      _spillboardSample!,
      sampleRadius: 5,
      colorThresholdMultiplier: 1.5,
      minSlabSize: widget.settings.minSlabSize,
      seedX: slabX,
      seedY: slabY
    );
    
    // Create coordinate system from previously set marker points
    final markerResult = _flowManager.result.markerResult;
    if (markerResult == null) {
      throw Exception('Marker detection result not available');
    }
    
    // Convert to machine coordinates
    final machineContour = MachineCoordinateSystem.fromMarkerPointsWithDistances(
      markerResult.markers[0].toPoint(),  // Origin
      markerResult.markers[1].toPoint(),  // X-axis
      markerResult.markers[2].toPoint(),  // Scale/Y-axis
      widget.settings.markerXDistance,
      widget.settings.markerYDistance
    ).convertPointListToMachineCoords(_contourPoints!);
    
    // Create debug visualization
    final visualization = MultiTapDetectionUtils.createVisualization(
      image,
      _slabSample!,
      _spillboardSample!,
      _contourPoints!
    );
    
    // Create contour result
    final contourResult = SlabContourResult(
      pixelContour: _contourPoints!,
      machineContour: machineContour,
      debugImage: visualization,
      detectionMethod: 'Multi-Tap'
    );
    
    // Update flow manager with the result
    _flowManager.updateContourResult(
      contourResult,
      method: ContourDetectionMethod.multiTap
    );
    
    setState(() {
      _isLoading = false;
      _currentMode = MultiTapMode.contourReady;
      _statusMessage = 'Contour detected! Tap "Continue" to generate G-code.';
    });
    
  } catch (e) {
    setState(() {
      _errorMessage = 'Error detecting contour: ${e.toString()}';
      _isLoading = false;
      _currentMode = MultiTapMode.slabSelection;
    });
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
  
  CoordinatePointXY _calculateImagePoint(Offset tapPosition) {
  if (_imageSize == null) {
    return CoordinatePointXY(0, 0);
  }
  
  // Get the direct parent render object of the image
  final RenderBox imageContainer = context.findRenderObject() as RenderBox;
  
  // Get the overlay's container size - using the same fixed height as in combined_detector_screen
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
      title: Text('Multi-Tap Slab Detection'),
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
        // Main content area with fixed height for consistency
        Container(
          height: 438.0, // Fixed height to match combined_detector_screen
          child: GestureDetector(
            onTapDown: _handleImageTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image display
                _buildImageDisplay(),
                
                // Marker overlay
                if (_flowManager.result.markerResult != null && _imageSize != null)
                  Positioned.fill(
                    child: MarkerOverlay(
                      markers: _flowManager.result.markerResult!.markers,
                      imageSize: _imageSize!,
                    ),
                  ),
                
                // Contour overlay
                if (_contourPoints != null && _imageSize != null)
                  Positioned.fill(
                    child: ContourOverlay(
                      contourPoints: _contourPoints!,
                      imageSize: _imageSize!,
                      color: Colors.green,
                      strokeWidth: 3,
                    ),
                  ),
                  
                // Marker point indicators
                if (_originMarkerPoint != null && _imageSize != null)
                  _buildSamplePointIndicator(
                    _originMarkerPoint!, 
                    Colors.red,
                    'Origin Marker'
                  ),
                  
                if (_xAxisMarkerPoint != null && _imageSize != null)
                  _buildSamplePointIndicator(
                    _xAxisMarkerPoint!, 
                    Colors.green,
                    'X-Axis Marker'
                  ),
                  
                if (_scaleMarkerPoint != null && _imageSize != null)
                  _buildSamplePointIndicator(
                    _scaleMarkerPoint!, 
                    Colors.blue,
                    'Scale Marker'
                  ),
                  
                // Sample point indicators
                if (_slabSamplePoint != null && _imageSize != null)
                  _buildSamplePointIndicator(
                    _slabSamplePoint!, 
                    Colors.orange,
                    'Slab Sample'
                  ),
                  
                if (_spillboardSamplePoint != null && _imageSize != null)
                  _buildSamplePointIndicator(
                    _spillboardSamplePoint!, 
                    Colors.purple,
                    'Spillboard Sample'
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
  
  Widget _buildSamplePointIndicator(CoordinatePointXY point, Color color, String label) {
    if (_imageSize == null) return Container();
    
    final imageContainer = context.findRenderObject() as RenderBox;
    final containerSize = Size(imageContainer.size.width, imageContainer.size.height);
    
    final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
      point,
      _imageSize!,
      containerSize
    );
    
    return Positioned(
      left: displayPoint.x - 10,
      top: displayPoint.y - 10,
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
    return Container(
      height: 438.0, // Set fixed height to match combined_detector_screen 
      child: Center(
        child: _contourPoints != null && _flowManager.result.contourResult?.debugImage != null
          ? Image.memory(
              Uint8List.fromList(img.encodePng(_flowManager.result.contourResult!.debugImage!)),
              fit: BoxFit.contain,
            )
          : Image.file(
              _flowManager.result.originalImage!,
              fit: BoxFit.contain,
            ),
      ),
    );
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
          // Reset button
          if (_slabSamplePoint != null)
            ElevatedButton.icon(
              icon: Icon(Icons.refresh),
              label: Text('Reset Samples'),
              onPressed: _isLoading ? null : _resetSamples,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
              ),
            ),
            
          if (_slabSamplePoint != null) SizedBox(height: 8),
            
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
                  onPressed: _isLoading || _currentMode != MultiTapMode.contourReady ? null : _generateGcode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _currentMode == MultiTapMode.contourReady ? Colors.green : Colors.grey,
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
        title: Text('Multi-Tap Detection Help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Complete detection process:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            
            Text('Step 1: Mark reference points', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.red, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap the ORIGIN marker (bottom left)'),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.green, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap the X-AXIS marker (bottom right)'),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap the SCALE marker (top left)'),
                ),
              ],
            ),
            
            SizedBox(height: 12),
            Text('Step 2: Mark material samples', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap on the slab material'),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.purple, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Tap on the spillboard/background'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('The app will automatically detect the contour'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              'This method works best when the slab and background are similar colors but have subtle differences.',
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