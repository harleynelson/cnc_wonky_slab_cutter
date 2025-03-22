// lib/screens/gcode_generator_screen.dart
// Screen for configuring and generating G-code with slab preview and margin adjustment

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/general/settings_model.dart';
import '../flow_of_app/flow_provider.dart';
import '../utils/gcode/gcode_generator.dart';
import '../utils/general/constants.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/general/time_formatter.dart';
import '../widgets/settings_fields.dart';
import '../widgets/contour_overlay.dart';
import '../widgets/marker_overlay.dart';
import 'gcode_visualization_screen.dart';

class GcodeGeneratorScreen extends StatefulWidget {
  final SettingsModel settings;

  const GcodeGeneratorScreen({
    Key? key,
    required this.settings,
  }) : super(key: key);

  @override
  _GcodeGeneratorScreenState createState() => _GcodeGeneratorScreenState();
}

class _GcodeGeneratorScreenState extends State<GcodeGeneratorScreen> {
  late SettingsModel _settings;
  bool _isGenerating = false;
  bool _isGenerated = false;
  String? _gcodePath;
  double _contourArea = 0.0;
  double _estimatedTime = 0.0;
  String _errorMessage = '';
  bool _forceHorizontalPaths = true;
  bool _returnToHome = true; // return to home option
  late TextEditingController _filenameController;
  String _fileExtension = '.gcode';
  double _slabMargin = 50.0; // Default 5mm margin
  List<CoordinatePointXY>? _adjustedContour;
  
@override
void initState() {
  super.initState();
  _settings = widget.settings.copy();
  _forceHorizontalPaths = _settings.forceHorizontalPaths;
  _returnToHome = _settings.returnToHome; // Initialize from settings
  _slabMargin = 50.0; // Default to 50mm
  _calculateStats();
  _updateAdjustedContour();
  
  // Initialize filename controller with default name
  _filenameController = TextEditingController(text: 'slab_surfacing');
}

// 1. Cache expensive calculations - add this to the class
Map<String, dynamic> _statsCache = {};
bool _statsCacheDirty = true;


// 2. Modify _calculateStats() to use caching
void _calculateStats() {
  // Skip recalculation if cache is valid
  if (!_statsCacheDirty && _statsCache.isNotEmpty) {
    _contourArea = _statsCache['area'] as double;
    _estimatedTime = _statsCache['time'] as double;
    return;
  }
  
  final provider = Provider.of<ProcessingProvider>(context, listen: false);
  final flowManager = provider.flowManager;
  
  if (flowManager?.result.contourResult != null) {
    // Calculate area
    final contour = flowManager!.result.contourResult!.machineContour;
    _contourArea = _calculateContourArea(contour);
    
    // Estimate time
    _estimatedTime = _estimateMachiningTime(contour, _settings);
    
    // Update cache
    _statsCache['area'] = _contourArea;
    _statsCache['time'] = _estimatedTime;
    _statsCacheDirty = false;
  }
}


// Update the _updateAdjustedContour method to use Simplified Polygon Buffering
// Simplified polygon buffering implementation
// SOOOOOOO helpful: https://medium.com/@gurbuzkaanakkaya/polygon-buffering-algorithm-generating-buffer-points-228ed062fdf9
// https://github.com/gurbuzkaanakkaya/Buffer-and-Path-Planning


// 3. Mark cache as dirty when relevant inputs change
void _updateAdjustedContour() {
  final provider = Provider.of<ProcessingProvider>(context, listen: false);
  final flowManager = provider.flowManager;
  
  if (flowManager?.result.contourResult != null) {
    final originalContour = flowManager!.result.contourResult!.machineContour;
    
    // Use original contour if no margin needed
    if (_slabMargin <= 0) {
      _adjustedContour = List.from(originalContour);
    } else {
      // Use offset polygon approach for positive margins
      // The negative sign is removed - positive margin should expand the contour
      _adjustedContour = _createBufferedPolygon(originalContour, _slabMargin);
    }
    
    // Recalculate area and time based on adjusted contour
    _statsCacheDirty = true;
    _calculateStats();
  }
}

// 4. Memory management
@override
void dispose() {
  // Clear caches
  _statsCache.clear();
  // Dispose controllers
  _filenameController.dispose();
  super.dispose();
}

/// Create a buffered polygon from the original contour using angle bisector method
/// /// with improved simplification for straighter edges
List<CoordinatePointXY> _createBufferedPolygon(List<CoordinatePointXY> originalContour, double distance) {
  if (originalContour.length < 3) {
    return originalContour;
  }
  
  // Ensure the contour is closed
  final contour = List<CoordinatePointXY>.from(originalContour);
  if (contour.first.x != contour.last.x || contour.first.y != contour.last.y) {
    contour.add(contour.first);
  }
  
  final bufferedPoints = <CoordinatePointXY>[];
  final size = contour.length;
  
  // Process each vertex except the last one (which is a duplicate of the first for closed polygon)
  for (int i = 0; i < size - 1; i++) {
    // Get previous, current, and next vertices
    final prev = contour[(i - 1 + size - 1) % (size - 1)]; // Previous vertex
    final curr = contour[i];                               // Current vertex
    final next = contour[(i + 1) % (size - 1)];            // Next vertex
    
    // Skip duplicate points
    if ((curr.x == prev.x && curr.y == prev.y) || 
        (curr.x == next.x && curr.y == next.y)) {
      continue;
    }
    
    // Calculate vectors from current vertex to previous and next vertices
    final v1x = prev.x - curr.x;
    final v1y = prev.y - curr.y;
    final v2x = next.x - curr.x;
    final v2y = next.y - curr.y;
    
    // Calculate distances to previous and next vertices
    final dist1 = math.sqrt(v1x * v1x + v1y * v1y);
    final dist2 = math.sqrt(v2x * v2x + v2y * v2y);
    
    if (dist1 < 1e-10 || dist2 < 1e-10) continue; // Skip if distances are too small
    
    // Calculate difference in coordinates between the previous and next vertices
    final thirdFirstXDist = next.x - prev.x;
    final thirdFirstYDist = next.y - prev.y;
    
    // Calculate the total rate (sum of distances between vertices)
    final totalRate = dist1 + dist2;
    
    // Calculate the point of the angle bisector
    final pointOfBisectorX = prev.x + ((thirdFirstXDist / totalRate) * dist1);
    final pointOfBisectorY = prev.y + ((thirdFirstYDist / totalRate) * dist1);
    
    // Handle case where calculated bisector point coincides with the current vertex
    double bisectorDistanceVertex;
    double currX = curr.x;
    double currY = curr.y;
    
    if ((pointOfBisectorX == currX) && (pointOfBisectorY == currY)) {
      // Add a tiny offset to avoid division by zero
      currX += 0.000001;
      bisectorDistanceVertex = 0.000001;
    } else {
      // Calculate distance between the bisector point and the current vertex
      final dx = pointOfBisectorX - currX;
      final dy = pointOfBisectorY - currY;
      bisectorDistanceVertex = math.sqrt(dx * dx + dy * dy);
    }
    
    // Check if the vertex is convex or concave
    final isConvex = _isVertexConvex([prev, curr, next], 1);
    
    double newPointX, newPointY;
    
    // FIXED: For convex vertices we move outward, for concave we move inward
    // This is the opposite of what was happening before
    if (isConvex) {
      // For convex vertices, move AWAY from the bisector point to EXPAND the contour
      newPointX = currX + (currX - pointOfBisectorX) * distance / bisectorDistanceVertex;
      newPointY = currY + (currY - pointOfBisectorY) * distance / bisectorDistanceVertex;
    } else {
      // For concave vertices, move TOWARD the bisector point
      newPointX = currX - (currX - pointOfBisectorX) * distance / bisectorDistanceVertex;
      newPointY = currY - (currY - pointOfBisectorY) * distance / bisectorDistanceVertex;
    }
    
    bufferedPoints.add(CoordinatePointXY(newPointX, newPointY));
  }
  
  // Close the polygon
  if (bufferedPoints.isNotEmpty) {
    bufferedPoints.add(bufferedPoints.first);
  }
  
  // Apply Douglas-Peucker simplification to reduce unnecessary points
  final double epsilon = 0.5 + distance * 0.05; // Scale epsilon based on margin size
  return _simplifyPolygon(bufferedPoints, epsilon);
}

/// Simplify polygon using Douglas-Peucker algorithm
List<CoordinatePointXY> _simplifyPolygon(List<CoordinatePointXY> points, double epsilon) {
  if (points.length <= 2) return List.from(points);
  
  // Find the point with the maximum distance
  double maxDistance = 0;
  int index = 0;
  
  for (int i = 1; i < points.length - 1; i++) {
    double distance = _perpendicularDistance(
      points[i],
      points.first,
      points.last
    );
    
    if (distance > maxDistance) {
      maxDistance = distance;
      index = i;
    }
  }
  
  // If max distance is greater than epsilon, recursively simplify
  if (maxDistance > epsilon) {
    // Recursive call
    final List<CoordinatePointXY> firstSegment = _simplifyPolygon(
      points.sublist(0, index + 1),
      epsilon
    );
    
    final List<CoordinatePointXY> secondSegment = _simplifyPolygon(
      points.sublist(index),
      epsilon
    );
    
    // Concatenate the results (avoiding duplicate point)
    return firstSegment.sublist(0, firstSegment.length - 1) + secondSegment;
  } else {
    // Below epsilon, return just the endpoints
    return [points.first, points.last];
  }
}

/// Calculate perpendicular distance from a point to a line segment
double _perpendicularDistance(
  CoordinatePointXY point,
  CoordinatePointXY lineStart,
  CoordinatePointXY lineEnd
) {
  final double x = point.x;
  final double y = point.y;
  final double x1 = lineStart.x;
  final double y1 = lineStart.y;
  final double x2 = lineEnd.x;
  final double y2 = lineEnd.y;
  
  // Calculate line length
  final double dx = x2 - x1;
  final double dy = y2 - y1;
  final double lineLengthSquared = dx * dx + dy * dy;
  
  // Handle case of zero-length line
  if (lineLengthSquared < 1e-10) {
    final double pdx = x - x1;
    final double pdy = y - y1;
    return math.sqrt(pdx * pdx + pdy * pdy);
  }
  
  // Calculate the projection factor
  final double t = ((x - x1) * dx + (y - y1) * dy) / lineLengthSquared;
  
  if (t < 0) {
    // Point is beyond the start of the line
    final double pdx = x - x1;
    final double pdy = y - y1;
    return math.sqrt(pdx * pdx + pdy * pdy);
  } else if (t > 1) {
    // Point is beyond the end of the line
    final double pdx = x - x2;
    final double pdy = y - y2;
    return math.sqrt(pdx * pdx + pdy * pdy);
  } else {
    // Point is on the line
    final double projX = x1 + t * dx;
    final double projY = y1 + t * dy;
    final double pdx = x - projX;
    final double pdy = y - projY;
    return math.sqrt(pdx * pdx + pdy * pdy);
  }
}

/// Check if a vertex is convex
bool _isVertexConvex(List<CoordinatePointXY> vertices, int vertexIndex) {
  final prev = vertices[(vertexIndex - 1 + vertices.length) % vertices.length];
  final curr = vertices[vertexIndex];
  final next = vertices[(vertexIndex + 1) % vertices.length];
  
  // Calculate cross product
  final crossProduct = (curr.x - prev.x) * (next.y - curr.y) - 
                       (curr.y - prev.y) * (next.x - curr.x);
  
  // If cross product is positive, the vertex is convex
  return crossProduct > 0;
}

/// Calculate cross product (z component) for CCW check
double _crossProduct(CoordinatePointXY a, CoordinatePointXY b, CoordinatePointXY c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

  double _calculateContourArea(List<CoordinatePointXY> contour) {
    if (contour.length < 3) return 0;
    
    double area = 0;
    for (int i = 0; i < contour.length; i++) {
      int j = (i + 1) % contour.length;
      area += contour[i].x * contour[j].y;
      area -= contour[j].x * contour[i].y;
    }
    
    return (area.abs() / 2);
  }

  double _estimateMachiningTime(List<CoordinatePointXY> contour, SettingsModel settings) {
    // Approximate toolpath length
    double pathLength = 0;
    for (int i = 0; i < contour.length - 1; i++) {
      final p1 = contour[i];
      final p2 = contour[i + 1];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      pathLength += math.sqrt(dx * dx + dy * dy);
    }
    
    // Add closing segment if needed
    if (contour.length > 1 && 
        (contour.first.x != contour.last.x || contour.first.y != contour.last.y)) {
      final p1 = contour.last;
      final p2 = contour.first;
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      pathLength += math.sqrt(dx * dx + dy * dy);
    }
    
    // Calculate time in minutes
    // Feed rate is in mm/min
    return pathLength / settings.feedRate;
  }

  Future<void> _generateGcode() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = '';
    });

    try {
      final provider = Provider.of<ProcessingProvider>(context, listen: false);
      final flowManager = provider.flowManager;
      
      if (flowManager == null || flowManager.result.contourResult == null) {
        throw Exception('No contour data available');
      }
      
      // Use the adjusted contour or fall back to the original contour
      final contour = _adjustedContour ?? flowManager.result.contourResult!.machineContour;
      
      // Generate G-code using our improved surfacing operation
      final gcodeGenerator = GcodeGenerator(
        safetyHeight: _settings.safetyHeight,
        feedRate: _settings.feedRate,
        plungeRate: _settings.plungeRate,
        cuttingDepth: _settings.cuttingDepth,
        stepover: _settings.stepover,
        toolDiameter: _settings.toolDiameter,
        spindleSpeed: _settings.spindleSpeed,
        depthPasses: _settings.depthPasses,
        margin: _slabMargin,
        forceHorizontal: _forceHorizontalPaths,
        returnToHome: _returnToHome, // Pass the new option to the generator
      );
      
      // Generate surfacing G-code
      final filenameWithoutExt = _filenameController.text;
      final gcode = gcodeGenerator.generateSurfacingGcode(
        contour, 
        filename: '$filenameWithoutExt$_fileExtension'
      );
      
      // Create a custom filename using the user input and selected extension
      final filename = '${_filenameController.text}${_fileExtension}';
      
      // Save G-code to file
      final tempDir = await Directory.systemTemp.createTemp('gcode_');
      final gcodeFile = File('${tempDir.path}/${filename}');
      await gcodeFile.writeAsString(gcode);
      
      setState(() {
        _isGenerating = false;
        _isGenerated = true;
        _gcodePath = gcodeFile.path;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('G-code generated successfully as $filename!')),
      );
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _errorMessage = 'Error generating G-code: ${e.toString()}';
      });
    }
  }

  Future<void> _shareGcode() async {
    if (_gcodePath == null) {
      setState(() {
        _errorMessage = 'No G-code file available to share';
      });
      return;
    }
    
    try {
      final file = XFile(_gcodePath!);
      await Share.shareXFiles([file], text: 'CNC Slab G-code');
    } catch (e) {
      setState(() {
        _errorMessage = 'Error sharing G-code: ${e.toString()}';
      });
    }
  }

  // Build the filename input field
Widget _buildFilenameInput() {
  return Card(
    child: Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Output File Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Divider(),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filenameController,
                  decoration: InputDecoration(
                    labelText: 'Filename',
                    hintText: 'Enter filename',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.file_present),
                  ),
                ),
              ),
              SizedBox(width: 16),
              DropdownButton<String>(
                value: _fileExtension,
                items: [
                  DropdownMenuItem(value: '.gcode', child: Text('.gcode')),
                  DropdownMenuItem(value: '.nc', child: Text('.nc')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _fileExtension = value;
                    });
                  }
                },
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'The file will be saved with this name after generation.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
      title: Text('G-code Generator'),
    ),
    body: SingleChildScrollView(
      child: Column(
        children: [
          // Image preview with overlays
          Container(
            height: 250,
            child: _buildImagePreview(),
          ),
          
          // Stats and settings
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatisticsCard(),
                SizedBox(height: 16),
                _buildPathSettings(),
                SizedBox(height: 16),
                _buildMarkerSettingsCard(),
                SizedBox(height: 16),
                _buildToolSettingsCard(),
                SizedBox(height: 16),
                _buildFeedSettingsCard(),
                SizedBox(height: 16),
                _buildFilenameInput(),
                SizedBox(height: 16),
                _buildActionButtons(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildActionButtons() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_errorMessage.isNotEmpty)
        Container(
          padding: EdgeInsets.all(8),
          color: Colors.red.shade50,
          width: double.infinity,
          child: Text(
            _errorMessage,
            style: TextStyle(color: Colors.red.shade900),
            textAlign: TextAlign.center,
          ),
        ),
      
      // Generate G-code button
      ElevatedButton.icon(
        icon: Icon(_isGenerated ? Icons.refresh : Icons.code, color: Colors.white),
        label: Text(_isGenerated ? 'Regenerate G-code' : 'Generate G-code', 
          style: TextStyle(color: Colors.white)),
        onPressed: _isGenerating ? null : _generateGcode,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          minimumSize: Size(double.infinity, 48),
        ),
      ),
      
      SizedBox(height: 12),
      
      // Visualize and Share buttons
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(Icons.visibility, color: Colors.white),
              label: Text('Visualize Path', style: TextStyle(color: Colors.white)),
              onPressed: _isGenerating || !_isGenerated ? null : _visualizeGcode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(Icons.share, color: Colors.white),
              label: Text('Share G-code', style: TextStyle(color: Colors.white)),
              onPressed: _isGenerating || !_isGenerated ? null : _shareGcode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ),
        ],
      ),
      
      // Bottom padding
      SizedBox(height: 30),
    ],
  );
}

  Widget _buildImagePreview() {
  final provider = Provider.of<ProcessingProvider>(context, listen: false);
  final flowManager = provider.flowManager;
  
  if (flowManager?.result.originalImage == null) {
    return Container(
      height: 250,
      color: Colors.grey.shade300,
      child: Center(child: Text('No image available')),
    );
  }
  
  return Container(
    height: 250,
    width: double.infinity,
    child: LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Display the image
            Center(
              child: Image.file(
                flowManager!.result.originalImage!,
                fit: BoxFit.contain,
              ),
            ),
            
            // Get image dimensions for proper overlay positioning
            FutureBuilder<Size>(
              future: _getImageDimensions(flowManager.result.originalImage!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container(); // Still loading
                }
                
                final imageSize = snapshot.data!;
                
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Marker overlay
                    if (flowManager.result.markerResult != null)
                      MarkerOverlay(
                        markers: flowManager.result.markerResult!.markers,
                        imageSize: imageSize,
                      ),
                    
                    // Original contour overlay
                    if (flowManager.result.contourResult != null)
                      ContourOverlay(
                        contourPoints: flowManager.result.contourResult!.pixelContour,
                        imageSize: imageSize,
                        color: Colors.green,
                        strokeWidth: 2,
                      ),
                      
                    // Adjusted contour preview with both original and buffered contours
                    if (_adjustedContour != null && _slabMargin > 0 && flowManager.result.markerResult != null)
                      Container(
                        child: CustomPaint(
                          size: Size(constraints.maxWidth, constraints.maxHeight),
                          painter: AdjustedContourPainter(
                            adjustedContour: _adjustedContour!,
                            originalContour: flowManager.result.contourResult!.machineContour,
                            coordSystem: MachineCoordinateSystem.fromMarkerPointsWithDistances(
                              flowManager.result.markerResult!.markers[0].toPoint(),
                              flowManager.result.markerResult!.markers[1].toPoint(),
                              flowManager.result.markerResult!.markers[2].toPoint(),
                              _settings.markerXDistance,
                              _settings.markerYDistance
                            ),
                            imageSize: imageSize,
                            displaySize: Size(constraints.maxWidth, constraints.maxHeight),
                            showOriginalContour: true,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    ),
  );
}
  
  // Helper method to get image dimensions
  Future<Size> _getImageDimensions(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = await decodeImageFromList(bytes);
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  Widget _buildPathSettings() {
  return Card(
    child: Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Path Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Divider(),
          
          // Margin Slider
          Text(
            'Slab Margin: ${_slabMargin.toStringAsFixed(0)} mm',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            'Add a margin around the slab for extra cutting',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Row(
            children: [
              Text('0 mm'),
              Expanded(
                child: Slider(
                  value: _slabMargin,
                  min: 0,
                  max: 100,
                  divisions: 50,
                  label: '${_slabMargin.toStringAsFixed(0)} mm',
                  onChanged: (value) {
                    setState(() {
                      _slabMargin = value;
                      _updateAdjustedContour();
                    });
                  },
                ),
              ),
              Text('100 mm'),
            ],
          ),
          
          SizedBox(height: 16),
          
          // Direction toggle
          Text(
            'Path Direction',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            'Set cutting path direction',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          SizedBox(height: 8),
          Center(
            child: ToggleButtons(
              isSelected: [_forceHorizontalPaths, !_forceHorizontalPaths],
              onPressed: (int index) {
                setState(() {
                  _forceHorizontalPaths = index == 0;
                  _settings.forceHorizontalPaths = _forceHorizontalPaths;
                  _settings.save(); // Save to persistent storage
                });
              },
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz),
                      SizedBox(width: 4),
                      Text('Horizontal')
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.swap_vert),
                      SizedBox(width: 4),
                      Text('Vertical')
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: 16),
          
          // Return to home option
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Return to Home Position',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Move to X0 Y0 after completion',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              Switch(
                value: _returnToHome,
                onChanged: (bool value) {
                  setState(() {
                    _returnToHome = value;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildStatisticsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contour Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Area:'),
                Text('${_contourArea.toStringAsFixed(2)} mm²'),
              ],
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estimated Time:'),
                Text(TimeFormatter.formatMinutesAndSeconds(_estimatedTime)),
              ],
            ),
            if (_slabMargin > 0) ...[
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Extra Margin:'),
                  Text('${_slabMargin.toStringAsFixed(0)} mm all around'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMarkerSettingsCard() {
  return Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Marker Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Divider(),
          SettingsTextField(
            label: 'X-Axis Marker Distance (mm)',
            value: _settings.markerXDistance,
            onChanged: (value) => setState(() {
              _settings.markerXDistance = value;
              _statsCacheDirty = true; // Mark stats as dirty since coordinate system changes
              _updateAdjustedContour(); // Update contour with new marker settings
            }),
            icon: Icons.arrow_right_alt,
            helperText: 'Real-world distance between Origin and X-Axis markers',
          ),
          SettingsTextField(
            label: 'Y-Axis Marker Distance (mm)',
            value: _settings.markerYDistance,
            onChanged: (value) => setState(() {
              _settings.markerYDistance = value;
              _statsCacheDirty = true; // Mark stats as dirty since coordinate system changes
              _updateAdjustedContour(); // Update contour with new marker settings
            }),
            icon: Icons.arrow_upward,
            helperText: 'Real-world distance between Origin and Y-Axis/Scale markers',
          ),
        ],
      ),
    ),
  );
}

  Widget _buildToolSettingsCard() {
  return Card(
    child: Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tool Settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Divider(),
          SettingsTextField(
            label: 'Tool Diameter (mm)',
            value: _settings.toolDiameter,
            onChanged: (value) => setState(() => _settings.toolDiameter = value),
            icon: Icons.circle_outlined,
          ),
          SettingsTextField(
            label: 'Stepover Distance (mm)',
            value: _settings.stepover,
            onChanged: (value) => setState(() => _settings.stepover = value),
            icon: Icons.compare_arrows,
            helperText: 'Distance between parallel toolpaths',
          ),
          SettingsTextField(
            label: 'Safety Height (mm)',
            value: _settings.safetyHeight,
            onChanged: (value) => setState(() => _settings.safetyHeight = value),
            icon: Icons.arrow_upward,
            helperText: 'Height for rapid movements',
          ),
          SettingsTextField(
            label: 'Cutting Depth (mm)',
            value: _settings.cuttingDepth,
            onChanged: (value) => setState(() => _settings.cuttingDepth = value),
            icon: Icons.arrow_downward,
            helperText: 'Total cutting depth (will be divided into passes)',
          ),
          SettingsTextField(
            label: 'Depth Passes',
            value: _settings.depthPasses.toDouble(),
            onChanged: (value) => setState(() => _settings.depthPasses = value.round()),
            icon: Icons.layers,
            helperText: 'Number of passes to reach full depth',
            min: 1,
            max: 10,
            isInteger: true, // Set this to true for integer-only display
          ),
        ],
      ),
    ),
  );
}

  Widget _buildFeedSettingsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Feed Rate Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Divider(),
            SettingsTextField(
              label: 'Feed Rate (mm/min)',
              value: _settings.feedRate,
              onChanged: (value) => setState(() => _settings.feedRate = value),
              icon: Icons.speed,
              helperText: 'Speed for cutting movements',
              isInteger: true, // Set this to true for integer-only display
            ),
            SettingsTextField(
              label: 'Plunge Rate (mm/min)',
              value: _settings.plungeRate,
              onChanged: (value) => setState(() => _settings.plungeRate = value),
              icon: Icons.vertical_align_bottom,
              helperText: 'Speed for vertical plunging movements',
              isInteger: true, // Set this to true for integer-only display
            ),
          ],
        ),
      ),
    );
  }

void _visualizeGcode() {
  if (_gcodePath == null) {
    setState(() {
      _errorMessage = 'No G-code file available to visualize';
    });
    return;
  }
  
  final provider = Provider.of<ProcessingProvider>(context, listen: false);
  final flowManager = provider.flowManager;
  
  if (flowManager == null || flowManager.result.originalImage == null || 
      flowManager.result.contourResult == null || 
      flowManager.result.markerResult == null) {
    setState(() {
      _errorMessage = 'Missing required data for visualization';
    });
    return;
  }
  
  // Get the contour and coordinate system
  final contour = _adjustedContour ?? flowManager.result.contourResult!.machineContour;
  
  // Create the coordinate system using the marker detection results AND marker settings
  final markerResult = flowManager.result.markerResult!;
  final coordSystem = MachineCoordinateSystem.fromMarkerPointsWithDistances(
    markerResult.markers[0].toPoint(),
    markerResult.markers[1].toPoint(),
    markerResult.markers[2].toPoint(),
    _settings.markerXDistance, // Using marker settings for X distance
    _settings.markerYDistance  // Using marker settings for Y distance
  );
  
  // Navigate to visualization screen
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => GcodeVisualizationScreen(
        imageFile: flowManager.result.originalImage!,
        gcodePath: _gcodePath!,
        contourPoints: contour,
        toolpath: null, // We'll parse from the G-code file
        coordSystem: coordSystem,
        settings: _settings,
      ),
    ),
  );
}
}



/// Custom painter for visualizing the adjusted contour
class AdjustedContourPainter extends CustomPainter {
  final List<CoordinatePointXY> adjustedContour;
  final MachineCoordinateSystem coordSystem;
  final Size imageSize;
  final Size displaySize;
  final bool showOriginalContour;
  final List<CoordinatePointXY>? originalContour;

  AdjustedContourPainter({
    required this.adjustedContour,
    required this.coordSystem,
    required this.imageSize,
    required this.displaySize,
    this.showOriginalContour = true,
    this.originalContour,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Paint for the buffered contour
    final path = Path();
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeJoin = StrokeJoin.round;
    
    // Convert machine coordinates to pixel coordinates
    final pixelPoints = coordSystem.convertPointListToPixelCoords(adjustedContour);
    
    // Convert pixel coordinates to display coordinates
    bool isFirst = true;
    
    for (final point in pixelPoints) {
      final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
        point,
        imageSize,
        displaySize
      );
      
      if (isFirst) {
        path.moveTo(displayPoint.x, displayPoint.y);
        isFirst = false;
      } else {
        path.lineTo(displayPoint.x, displayPoint.y);
      }
    }
    
    // Close the path if it's not already closed
    if (pixelPoints.isNotEmpty && 
        (pixelPoints.first.x != pixelPoints.last.x || 
         pixelPoints.first.y != pixelPoints.last.y)) {
      path.close();
    }
    
    // Draw outline for adjusted contour
    canvas.drawPath(path, paint);
    
    // Draw the original contour in a different color if requested
    if (showOriginalContour && originalContour != null && originalContour!.isNotEmpty) {
      final originalPath = Path();
      final originalPaint = Paint()
        ..color = Colors.green.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeJoin = StrokeJoin.round;
      
      // Convert original contour to pixel and display coordinates
      final originalPixelPoints = coordSystem.convertPointListToPixelCoords(originalContour!);
      bool isFirstOriginal = true;
      
      for (final point in originalPixelPoints) {
        final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
          point,
          imageSize,
          displaySize
        );
        
        if (isFirstOriginal) {
          originalPath.moveTo(displayPoint.x, displayPoint.y);
          isFirstOriginal = false;
        } else {
          originalPath.lineTo(displayPoint.x, displayPoint.y);
        }
      }
      
      // Close the original path if needed
      if (originalPixelPoints.isNotEmpty && 
          (originalPixelPoints.first.x != originalPixelPoints.last.x || 
           originalPixelPoints.first.y != originalPixelPoints.last.y)) {
        originalPath.close();
      }
      
      // Draw outline for original contour
      canvas.drawPath(originalPath, originalPaint);
    }
    
    // Draw points at vertices to highlight them
    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    
    for (final point in pixelPoints) {
      final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
        point,
        imageSize,
        displaySize
      );
      
      canvas.drawCircle(Offset(displayPoint.x, displayPoint.y), 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

extension DoubleExtension on double {
  double sqrt() => (this <= 0) ? 0 : math.sqrt(this);
}