// lib/screens/combined_detector_screen.dart
// Combined screen that handles both marker detection and slab contour detection

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/image_processing/marker_detector.dart';
import '../services/processing/processing_flow_manager.dart';
import '../widgets/marker_overlay.dart';
import '../widgets/contour_overlay.dart';
import '../utils/image_processing/image_utils.dart';
import '../utils/general/error_utils.dart';

class CombinedDetectorScreen extends StatefulWidget {
  final File imageFile;
  final SettingsModel settings;

  const CombinedDetectorScreen({
    Key? key,
    required this.imageFile,
    required this.settings,
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
      
      // Calculate the actual seed point in the image
      final imagePoint = _calculateImagePoint(_selectedPoint!);
      
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
      
      // Create coordinate system from marker detection result
      final coordinateSystem = _flowManager.result.markerResult!;
      
      // Use edge contour algorithm
      final contourAlgorithmRegistry = await _flowManager.detectSlabContourAutomatic();
      
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
    }
  }
  
  Future<void> _generateGcode() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Generating G-code...';
      _errorMessage = '';
    });

    try {
      await _flowManager.generateGcode();
      
      setState(() {
        _isLoading = false;
        _statusMessage = 'G-code generation complete!';
      });
      
      // Navigate back to home
      Navigator.of(context).popUntil((route) => route.isFirst);
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('G-code generated successfully!'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      ErrorUtils().logError(
        'Error during G-code generation',
        e,
        stackTrace: stackTrace,
        context: 'gcode_generation',
      );
      
      setState(() {
        _errorMessage = 'G-code generation failed: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  void _handleImageTap(TapDownDetails details) {
    if (_isLoading || !_markersDetected) return;
    
    setState(() {
      _selectedPoint = details.localPosition;
      _statusMessage = 'Seed point selected. Now tap "Detect Contour" to proceed.';
    });
  }
  
  // Calculate the actual point in the image coordinates
  Point _calculateImagePoint(Offset tapPosition) {
    if (_imageSize == null) {
      return Point(0, 0);
    }
    
    final containerSize = MediaQuery.of(context).size;
    
    // Calculate how the image is displayed (accounting for aspect ratio)
    final imageAspect = _imageSize!.width / _imageSize!.height;
    final containerAspect = containerSize.width / containerSize.height;
    
    double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
    
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
    
    // Scale factors
    final scaleX = _imageSize!.width / displayWidth;
    final scaleY = _imageSize!.height / displayHeight;
    
    // Convert tap position to image coordinates
    final imageX = (tapPosition.dx - offsetX) * scaleX;
    final imageY = (tapPosition.dy - offsetY) * scaleY;
    
    return Point(imageX, imageY);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Slab Detection'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _isLoading ? null : _resetDetection,
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
          
          // Main content
          Expanded(
            child: GestureDetector(
              onTapDown: _markersDetected && !_contourDetected ? _handleImageTap : null,
              child: Stack(
                children: [
                  // Image display
                  _buildImageDisplay(),
                  
                  // Marker overlay
                  if (_markersDetected && _flowManager.result.markerResult != null && _imageSize != null)
                    MarkerOverlay(
                      markers: _flowManager.result.markerResult!.markers,
                      imageSize: _imageSize!,
                    ),
                  
                  // Contour overlay
                  if (_contourDetected && _flowManager.result.contourResult != null && _imageSize != null)
                    ContourOverlay(
                      contourPoints: _flowManager.result.contourResult!.pixelContour,
                      imageSize: _imageSize!,
                      color: Colors.green,
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
          
          // Action buttons
          _buildControlButtons(),
        ],
      ),
    );
  }
  
  Widget _buildImageDisplay() {
    if (_flowManager.result.originalImage != null) {
      return Image.file(
        _flowManager.result.originalImage!,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
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
          if (!_markersDetected)
            ElevatedButton.icon(
              icon: Icon(Icons.search),
              label: Text('Detect Markers'),
              onPressed: _isLoading ? null : _detectMarkers,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
              ),
            ),
          
          if (_markersDetected && !_contourDetected)
            ElevatedButton.icon(
              icon: Icon(Icons.content_cut),
              label: Text('Detect Contour'),
              onPressed: _isLoading || _selectedPoint == null ? null : _detectContour,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
              ),
            ),
          
          if (_contourDetected)
            ElevatedButton.icon(
              icon: Icon(Icons.code),
              label: Text('Generate G-code'),
              onPressed: _isLoading ? null : _generateGcode,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
                backgroundColor: Colors.green,
              ),
            ),
          
          SizedBox(height: 8),
          
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
                child: OutlinedButton.icon(
                  icon: Icon(Icons.refresh),
                  label: Text('Reset'),
                  onPressed: _isLoading ? null : _resetDetection,
                ),
              ),
            ],
          ),
        ],
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