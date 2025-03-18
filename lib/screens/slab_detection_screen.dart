// lib/screens/slab_detection_screen.dart
// Screen for slab detection on the corrected image

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/flow/processing_flow_manager.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/image_processing/multi_tap_detection_utils.dart';
import '../services/detection/slab_contour_result.dart';
import 'gcode_generator_screen.dart';

class SlabDetectionScreen extends StatefulWidget {
  final SettingsModel settings;
  final Function(SettingsModel)? onSettingsChanged;

  const SlabDetectionScreen({
    Key? key,
    required this.settings,
    this.onSettingsChanged,
  }) : super(key: key);

  @override
  _SlabDetectionScreenState createState() => _SlabDetectionScreenState();
}

class _SlabDetectionScreenState extends State<SlabDetectionScreen> {
  bool _isLoading = false;
  String _statusMessage = 'Tap on the SLAB to select a sample point';
  String _errorMessage = '';
  
  // Image dimensions for overlays
  Size? _imageSize;
  
  // Flow Manager
  late ProcessingFlowManager _flowManager;
  
  // Sample points
  PointOfCoordinates? _slabSamplePoint;
  PointOfCoordinates? _spillboardSamplePoint;
  
  // Region samples with color information
  RegionSample? _slabSample;
  RegionSample? _spillboardSample;
  
  // Detection result
  List<PointOfCoordinates>? _contourPoints;
  bool _contourDetected = false;
  
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
      // Check if we have a corrected image
      if (_flowManager.result.correctedImage == null) {
        throw Exception('No corrected image available');
      }
      
      // Get image dimensions
      final imageBytes = await _flowManager.result.correctedImage!.readAsBytes();
      final decodedImage = await decodeImageFromList(imageBytes);
      
      setState(() {
        _imageSize = Size(decodedImage.width.toDouble(), decodedImage.height.toDouble());
        _isLoading = false;
        _statusMessage = 'Tap on the SLAB to select a sample point';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Initialization error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  void _handleImageTap(TapDownDetails details) {
    if (_isLoading || _contourDetected) return;
    
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
      if (_slabSamplePoint == null) {
        _slabSamplePoint = imagePoint;
        _statusMessage = 'Tap on the SPILLBOARD (background) to select a sample point';
      } else if (_spillboardSamplePoint == null) {
        _spillboardSamplePoint = imagePoint;
        _statusMessage = 'Processing samples...';
        _processRegionSamples();
      }
    });
  }
  
  Future<void> _processRegionSamples() async {
    if (_slabSamplePoint == null || _spillboardSamplePoint == null) {
      setState(() {
        _errorMessage = 'Both slab and spillboard sample points are required';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Analyzing samples and detecting contour...';
    });
    
    try {
      // Load the corrected image for processing
      final imageBytes = await _flowManager.result.correctedImage!.readAsBytes();
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
      
      // Create coordinate system from marker result
      final markerResult = _flowManager.result.markerResult;
      if (markerResult == null) {
        throw Exception('Marker detection result not available');
      }
      
      // Convert to machine coordinates - note these should already be correct
      // since we're working with the corrected image
      final machineContour = MachineCoordinateSystem.fromMarkerPointsWithDistances(
        PointOfCoordinates(0, 0), // Origin at (0,0) in corrected image
        PointOfCoordinates(widget.settings.markerXDistance, 0), // X-axis at marker distance
        PointOfCoordinates(0, widget.settings.markerYDistance), // Y-axis at marker distance
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
        detectionMethod: 'Multi-Tap on Corrected Image'
      );
      
      // Update flow manager with the result
      _flowManager.updateContourResult(
        contourResult,
        method: ContourDetectionMethod.multiTap
      );
      
      setState(() {
        _isLoading = false;
        _contourDetected = true;
        _statusMessage = 'Contour detected! Tap "Continue" to generate G-code.';
      });
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Error detecting contour: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  PointOfCoordinates _calculateImagePoint(Offset tapPosition) {
    if (_imageSize == null) {
      return PointOfCoordinates(0, 0);
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
    
    return PointOfCoordinates(imageX, imageY);
  }
  
  Widget _buildSamplePointIndicator(PointOfCoordinates point, Color color, String label) {
    if (_imageSize == null) return Container();
    
    // Get container size with fixed height for consistency
    final containerSize = Size(
      (context.findRenderObject() as RenderBox).size.width,
      438.0 // Fixed height to match combined_detector_screen
    );
    
    // Use standard method for coordinate transformation
    final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
      point,
      _imageSize!,
      containerSize
    );
    
    // Add debug logs
    print('DEBUG INDICATOR: Image point (${point.x}, ${point.y}) -> Display point (${displayPoint.x}, ${displayPoint.y})');
    
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
    if (_flowManager.result.correctedImage != null) {
      if (_contourDetected && _flowManager.result.contourResult?.debugImage != null) {
        // Display visualization with contour
        return Center(
          child: Image.memory(
            Uint8List.fromList(img.encodePng(_flowManager.result.contourResult!.debugImage!)),
            fit: BoxFit.contain,
          ),
        );
      } else {
        // Show the corrected image if no contour detected yet
        return Center(
          child: Image.file(
            _flowManager.result.correctedImage!,
            fit: BoxFit.contain,
          ),
        );
      }
    } else {
      return Center(child: Text('Corrected image not available'));
    }
  }
  
  void _continueToGCodeGenerator() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GcodeGeneratorScreen(
          settings: widget.settings,
        ),
      ),
    );
  }
  
  void _resetDetection() {
    setState(() {
      _contourDetected = false;
      _slabSamplePoint = null;
      _spillboardSamplePoint = null;
      _slabSample = null;
      _spillboardSample = null;
      _contourPoints = null;
      _errorMessage = '';
      _statusMessage = 'Tap on the SLAB to select a sample point';
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Slab Detection'),
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
            label: Text('Reset Samples'),
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
                  onPressed: _isLoading || !_contourDetected ? null : _continueToGCodeGenerator,
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
  
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Slab Detection Help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This step detects the slab contour on your corrected image.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            
            Text('Tap to select sample points:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.orange, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('First tap on the SLAB material'),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, color: Colors.purple, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Then tap on the SPILLBOARD/background'),
                ),
              ],
            ),
            
            SizedBox(height: 12),
            Text(
              'The app will automatically detect the contour based on the color difference between your sample points.',
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