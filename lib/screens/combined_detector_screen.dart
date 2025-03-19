// lib/screens/combined_detector_screen.dart
// Combined screen that handles both marker detection and slab contour detection

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
  Offset? _selectedPoint;

  // Marker tap points
  Offset? _originTapPoint;
  Offset? _xAxisTapPoint;
  Offset? _scaleTapPoint;

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

  Future<void> _detectMarkersFromTapPoints() async {
    if (_originTapPoint == null || _xAxisTapPoint == null || _scaleTapPoint == null || _imageSize == null) {
      setState(() {
        _errorMessage = 'Missing tap points for markers';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _statusMessage = 'Detecting markers...';
      _errorMessage = '';
    });

    try {
      // Convert tap points to image coordinates
      final originImagePoint = _calculateImagePoint(_originTapPoint!);
      final xAxisImagePoint = _calculateImagePoint(_xAxisTapPoint!);
      final scaleImagePoint = _calculateImagePoint(_scaleTapPoint!);
      
      // Load the image
      final imageBytes = await widget.imageFile.readAsBytes();
      final originalImage = img.decodeImage(imageBytes);
      
      if (originalImage == null) {
        throw Exception('Failed to decode image');
      }
      
      // Create search regions around each tap point
      final searchRadius = math.min(originalImage.width, originalImage.height) ~/ 10;
      
      // Detect markers in regions around tap points
      final originMarker = _findMarkerInRegion(
        originalImage, 
        originImagePoint.x.toInt(), 
        originImagePoint.y.toInt(), 
        searchRadius,
        MarkerRole.origin
      );
      
      final xAxisMarker = _findMarkerInRegion(
        originalImage, 
        xAxisImagePoint.x.toInt(), 
        xAxisImagePoint.y.toInt(), 
        searchRadius,
        MarkerRole.xAxis
      );
      
      final scaleMarker = _findMarkerInRegion(
        originalImage, 
        scaleImagePoint.x.toInt(), 
        scaleImagePoint.y.toInt(), 
        searchRadius,
        MarkerRole.scale
      );
      
      // Create list of detected markers
      _detectedMarkers = [originMarker, xAxisMarker, scaleMarker];
      
      // Create a debug image
      img.Image? debugImage;
      if (originalImage != null) {
        debugImage = img.copyResize(originalImage, width: originalImage.width, height: originalImage.height);
        
        // Draw markers on debug image
        _drawMarkersOnDebugImage(debugImage, _detectedMarkers);
      }
      
      // Calculate parameters for the MarkerDetectionResult
      final dx = xAxisMarker.x - originMarker.x;
      final dy = xAxisMarker.y - originMarker.y;
      final orientationAngle = math.atan2(dy, dx);
      
      final scaleX = scaleMarker.x - originMarker.x;
      final scaleY = scaleMarker.y - originMarker.y;
      final distancePx = math.sqrt(scaleX * scaleX + scaleY * scaleY);
      
      final pixelToMmRatio = widget.settings.markerXDistance / distancePx;
      
      final origin = CoordinatePointXY(originMarker.x.toDouble(), originMarker.y.toDouble());
      
      // Create the marker detection result
      final markerResult = MarkerDetectionResult(
        markers: _detectedMarkers,
        pixelToMmRatio: pixelToMmRatio,
        origin: origin,
        orientationAngle: orientationAngle,
        debugImage: debugImage,
      );
      
      // Update flow manager with the result
      var updatedResult = _flowManager.result.copyWith(
        markerResult: markerResult,
        processedImage: debugImage,
      );
      
      // This creates a dummy SlabContourResult just to update the flow manager
      // with our marker detection debug image
      if (debugImage != null) {
        final dummyContourResult = SlabContourResult(
          pixelContour: [],
          machineContour: [],
          debugImage: debugImage,
        );
        _flowManager.updateContourResult(dummyContourResult, method: null);
      }
      
      setState(() {
        _markersDetected = true;
        _isLoading = false;
        _statusMessage = 'Markers detected! Now tap on the slab to select a seed point for contour detection.';
        _markerSelectionState = MarkerSelectionState.slab;
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

  MarkerPoint _findMarkerInRegion(img.Image image, int centerX, int centerY, int searchRadius, MarkerRole role) {
    // Define the search region
    final int x1 = math.max(0, centerX - searchRadius);
    final int y1 = math.max(0, centerY - searchRadius);
    final int x2 = math.min(image.width - 1, centerX + searchRadius);
    final int y2 = math.min(image.height - 1, centerY + searchRadius);
    
    try {
      // Extract region statistics
      int totalPixels = 0;
      double sumBrightness = 0;
      
      for (int y = y1; y < y2; y++) {
        for (int x = x1; x < x2; x++) {
          if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
            final pixel = image.getPixel(x, y);
            final brightness = _calculateLuminance(
              pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
            ) / 255.0; // Normalize to 0-1
            
            sumBrightness += brightness;
            totalPixels++;
          }
        }
      }
      
      // Calculate average brightness
      final avgBrightness = totalPixels > 0 ? sumBrightness / totalPixels : 0.5;
      
      // Look for the darkest or brightest area in the region as the marker
      int bestX = -1, bestY = -1;
      double bestDifference = -1;
      
      // Determine if we should look for dark markers on light background or vice versa
      final lookForDark = avgBrightness > 0.5;
      
      // Slide a smaller window through the region to find the distinctive marker
      final windowSize = math.max(5, math.min(x2 - x1, y2 - y1) ~/ 6);
      
      for (int y = y1; y < y2 - windowSize; y += windowSize ~/ 3) {
        for (int x = x1; x < x2 - windowSize; x += windowSize ~/ 3) {
          int windowPixels = 0;
          double windowSum = 0;
          
          // Calculate window statistics
          for (int wy = 0; wy < windowSize; wy++) {
            for (int wx = 0; wx < windowSize; wx++) {
              final px = x + wx;
              final py = y + wy;
              
              if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
                final pixel = image.getPixel(px, py);
                final brightness = _calculateLuminance(
                  pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()
                ) / 255.0; // Normalize to 0-1
                
                windowSum += brightness;
                windowPixels++;
              }
            }
          }
          
          if (windowPixels > 0) {
            final windowAvg = windowSum / windowPixels;
            double difference;
            
            if (lookForDark) {
              // Looking for dark markers on light background
              difference = avgBrightness - windowAvg;
            } else {
              // Looking for light markers on dark background
              difference = windowAvg - avgBrightness;
            }
            
            if (difference > bestDifference) {
              bestDifference = difference;
              bestX = x + windowSize ~/ 2;
              bestY = y + windowSize ~/ 2;
            }
          }
        }
      }
      
      // Require a higher minimum contrast difference to prevent false positives
      if (bestDifference < 0.15 || bestX < 0 || bestY < 0) {
        // If we couldn't find a clear marker, use the center of the search region
        return MarkerPoint(centerX, centerY, role, confidence: 0.5);
      }
      
      return MarkerPoint(bestX, bestY, role, confidence: bestDifference);
    } catch (e) {
      print('Error finding marker in region: $e');
      // Fall back to using the tap point directly
      return MarkerPoint(centerX, centerY, role, confidence: 0.5);
    }
  }

  int _calculateLuminance(int r, int g, int b) {
    return (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
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
      _drawCircle(debugImage, marker.x, marker.y, 15, color);
      
      // Draw a filled inner circle
      _drawCircle(debugImage, marker.x, marker.y, 5, color, fill: true);
      
      // Draw marker role text
      final roleText = marker.role.toString().split('.').last;
      _drawText(debugImage, roleText, marker.x + 20, marker.y - 5, color);
    }
    
    // Draw lines between markers if we have all three
    if (markers.length >= 3) {
      final originMarker = markers.firstWhere((m) => m.role == MarkerRole.origin);
      final xAxisMarker = markers.firstWhere((m) => m.role == MarkerRole.xAxis);
      final scaleMarker = markers.firstWhere((m) => m.role == MarkerRole.scale);
      
      // Draw line from origin to X-axis
      _drawLine(
        debugImage, 
        originMarker.x, originMarker.y, 
        xAxisMarker.x, xAxisMarker.y, 
        img.ColorRgba8(255, 255, 0, 200)
      );
      
      // Draw line from origin to scale marker
      _drawLine(
        debugImage, 
        originMarker.x, originMarker.y, 
        scaleMarker.x, scaleMarker.y, 
        img.ColorRgba8(255, 255, 0, 200)
      );
    }
  }

  void _drawCircle(img.Image image, int x, int y, int radius, img.Color color, {bool fill = false}) {
    for (int j = -radius; j <= radius; j++) {
      for (int i = -radius; i <= radius; i++) {
        final distance = math.sqrt(i * i + j * j);
        if ((fill && distance <= radius) || (!fill && (distance >= radius - 0.5 && distance <= radius + 0.5))) {
          final px = x + i;
          final py = y + j;
          if (px >= 0 && px < image.width && py >= 0 && py < image.height) {
            image.setPixel(px, py, color);
          }
        }
      }
    }
  }

  void _drawLine(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
    // Bresenham's line algorithm
    int dx = (x2 - x1).abs();
    int dy = (y2 - y1).abs();
    int sx = x1 < x2 ? 1 : -1;
    int sy = y1 < y2 ? 1 : -1;
    int err = dx - dy;
    
    while (true) {
      if (x1 >= 0 && x1 < image.width && y1 >= 0 && y1 < image.height) {
        image.setPixel(x1, y1, color);
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

  void _drawText(img.Image image, String text, int x, int y, img.Color color) {
    // Simple implementation that draws a placeholder for text
    // In a real implementation, you would render actual text
    _drawRectangle(image, x, y, x + text.length * 8, y + 10, color);
  }
  
  void _drawRectangle(img.Image image, int x1, int y1, int x2, int y2, img.Color color) {
    for (int y = y1; y <= y2; y++) {
      for (int x = x1; x <= x2; x++) {
        if (x >= 0 && x < image.width && y >= 0 && y < image.height) {
          image.setPixel(x, y, color);
        }
      }
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
          _statusMessage = 'Tap on the Scale/Y-Axis marker (top left)';
          _markerSelectionState = MarkerSelectionState.scale;
          break;
          
        case MarkerSelectionState.scale:
          _scaleTapPoint = details.localPosition;
          _detectMarkersFromTapPoints();
          break;
          
        case MarkerSelectionState.slab:
          _selectedPoint = details.localPosition;
          
          // Calculate image point
          final imagePoint = _calculateImagePoint(_selectedPoint!);
          
          // Update status message with tap coordinates
          _statusMessage = 'Tap at: (${_selectedPoint!.dx.toInt()},${_selectedPoint!.dy.toInt()}) → Image: (${imagePoint.x.toInt()},${imagePoint.y.toInt()}). Tap "Detect Contour" to proceed.';
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
          // Detect Contour Button (only visible after markers are detected)
          if (_markerSelectionState == MarkerSelectionState.slab)
            ElevatedButton.icon(
              icon: Icon(Icons.content_cut),
              label: Text('Detect Contour'),
              onPressed: _isLoading || _selectedPoint == null ? null : _detectContour,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
              ),
            ),
          
          // Detect Markers Button (only visible when all three markers have been tapped)
          if (_markerSelectionState == MarkerSelectionState.scale && 
              _originTapPoint != null && _xAxisTapPoint != null && _scaleTapPoint != null)
            ElevatedButton.icon(
              icon: Icon(Icons.check_circle),
              label: Text('Detect Markers'),
              onPressed: _isLoading ? null : _detectMarkersFromTapPoints,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 48),
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

  void _resetDetection() {
    setState(() {
      _markersDetected = false;
      _contourDetected = false;
      _selectedPoint = null;
      _originTapPoint = null;
      _xAxisTapPoint = null;
      _scaleTapPoint = null;
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
}}