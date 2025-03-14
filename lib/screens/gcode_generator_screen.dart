// lib/screens/gcode_generator_screen.dart
// Screen for configuring and generating G-code with slab preview and margin adjustment

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image/image.dart' as img;

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/gcode/gcode_generator.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/image_processing/contour_detection_utils.dart';
import '../utils/image_processing/drawing_utils.dart';
import '../widgets/settings_fields.dart';
import '../widgets/contour_overlay.dart';
import '../widgets/marker_overlay.dart';

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
  
  // Add slabMargin for adjusting the contour size
  double _slabMargin = 5.0; // Default 5mm margin
  List<Point>? _adjustedContour;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings.copy();
    _calculateStats();
    _updateAdjustedContour();
  }

  void _calculateStats() {
    final provider = Provider.of<ProcessingProvider>(context, listen: false);
    final flowManager = provider.flowManager;
    
    if (flowManager?.result.contourResult != null) {
      // Calculate area
      final contour = flowManager!.result.contourResult!.machineContour;
      _contourArea = _calculateContourArea(contour);
      
      // Estimate time
      _estimatedTime = _estimateMachiningTime(contour, _settings);
    }
  }

// Update the _updateAdjustedContour method to use Simplified Polygon Buffering
// Simplified polygon buffering implementation
// SOOOOOOO helpful: https://medium.com/@gurbuzkaanakkaya/polygon-buffering-algorithm-generating-buffer-points-228ed062fdf9
// https://github.com/gurbuzkaanakkaya/Buffer-and-Path-Planning


void _updateAdjustedContour() {
  final provider = Provider.of<ProcessingProvider>(context, listen: false);
  final flowManager = provider.flowManager;
  
  if (flowManager?.result.contourResult != null) {
    final originalContour = flowManager!.result.contourResult!.machineContour;
    
    // Use original contour if no margin needed
    if (_slabMargin <= 0) {
      _adjustedContour = List.from(originalContour);
    } else {
      // Use buffered polygon approach for positive margins
      _adjustedContour = _createBufferedPolygon(originalContour, _slabMargin);
    }
    
    // Recalculate area and time based on adjusted contour
    _contourArea = _calculateContourArea(_adjustedContour!);
    _estimatedTime = _estimateMachiningTime(_adjustedContour!, _settings);
  }
}

/// Create a buffered polygon from the original contour using angle bisector method
List<Point> _createBufferedPolygon(List<Point> originalContour, double distance) {
  if (originalContour.length < 3) {
    return originalContour;
  }
  
  // Ensure the contour is closed
  final contour = List<Point>.from(originalContour);
  if (contour.first.x != contour.last.x || contour.first.y != contour.last.y) {
    contour.add(contour.first);
  }
  
  final bufferedPoints = <Point>[];
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
    
    if (!isConvex) {
      // For concave vertices, move away from the bisector point
      newPointX = currX + (currX - pointOfBisectorX) * distance / bisectorDistanceVertex;
      newPointY = currY + (currY - pointOfBisectorY) * distance / bisectorDistanceVertex;
    } else {
      // For convex vertices, move toward the bisector point
      newPointX = currX - (currX - pointOfBisectorX) * distance / bisectorDistanceVertex;
      newPointY = currY - (currY - pointOfBisectorY) * distance / bisectorDistanceVertex;
    }
    
    bufferedPoints.add(Point(newPointX, newPointY));
  }
  
  // Close the polygon
  if (bufferedPoints.isNotEmpty) {
    bufferedPoints.add(bufferedPoints.first);
  }
  
  return bufferedPoints;
}

/// Check if a vertex is convex
bool _isVertexConvex(List<Point> vertices, int vertexIndex) {
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
double _crossProduct(Point a, Point b, Point c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

  double _calculateContourArea(List<Point> contour) {
    if (contour.length < 3) return 0;
    
    double area = 0;
    for (int i = 0; i < contour.length; i++) {
      int j = (i + 1) % contour.length;
      area += contour[i].x * contour[j].y;
      area -= contour[j].x * contour[i].y;
    }
    
    return (area.abs() / 2);
  }

  double _estimateMachiningTime(List<Point> contour, SettingsModel settings) {
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
    
    // Generate G-code using our new surfacing operation
    final gcodeGenerator = GcodeGenerator(
      safetyHeight: _settings.safetyHeight,
      feedRate: _settings.feedRate,
      plungeRate: _settings.plungeRate,
      cuttingDepth: _settings.cuttingDepth,
      stepover: _settings.stepover / _settings.toolDiameter, // Convert to percentage of tool diameter
      toolDiameter: _settings.toolDiameter,
    );
    
    // Generate surfacing G-code instead of just contour G-code
    final gcode = gcodeGenerator.generateSurfacingGcode(contour);
    
    // Save G-code to file
    final tempDir = await Directory.systemTemp.createTemp('gcode_');
    final gcodeFile = File('${tempDir.path}/slab_surfacing.gcode');
    await gcodeFile.writeAsString(gcode);
    
    setState(() {
      _isGenerating = false;
      _isGenerated = true;
      _gcodePath = gcodeFile.path;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('G-code generated successfully!')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('G-code Generator'),
      ),
      body: Column(
        children: [
          // Image preview with overlays
          _buildImagePreview(),
          
          // Margin slider
          _buildMarginSlider(),
          
          // Stats and settings
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatisticsCard(),
                  SizedBox(height: 16),
                  _buildMachineSettingsCard(),
                  SizedBox(height: 16),
                  _buildToolSettingsCard(),
                  SizedBox(height: 16),
                  _buildFeedSettingsCard(),
                ],
              ),
            ),
          ),
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
          _buildBottomButtons(),
        ],
      ),
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

  Widget _buildMarginSlider() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Slab Margin: ${_slabMargin.toStringAsFixed(1)} mm',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              Text('0 mm'),
              Expanded(
                child: Slider(
                  value: _slabMargin,
                  min: 0,
                  max: 50,
                  divisions: 50,
                  label: '${_slabMargin.toStringAsFixed(1)} mm',
                  onChanged: (value) {
                    setState(() {
                      _slabMargin = value;
                      _updateAdjustedContour();
                    });
                  },
                ),
              ),
              Text('50 mm'),
            ],
          ),
          Text(
            'Add a safety margin around the detected slab for CNC cutting',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
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
                Text('${_estimatedTime.toStringAsFixed(2)} min'),
              ],
            ),
            if (_slabMargin > 0) ...[
              SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Safety Margin:'),
                  Text('${_slabMargin.toStringAsFixed(1)} mm all around'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMachineSettingsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Machine Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Divider(),
            SettingsTextField(
              label: 'CNC Work Area Width (mm)',
              value: _settings.cncWidth,
              onChanged: (value) => setState(() => _settings.cncWidth = value),
              icon: Icons.width_normal,
            ),
            SettingsTextField(
              label: 'CNC Work Area Height (mm)',
              value: _settings.cncHeight,
              onChanged: (value) => setState(() => _settings.cncHeight = value),
              icon: Icons.height,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolSettingsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
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
              helperText: 'Z-height for cutting (usually 0 or negative)',
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
            ),
            SettingsTextField(
              label: 'Plunge Rate (mm/min)',
              value: _settings.plungeRate,
              onChanged: (value) => setState(() => _settings.plungeRate = value),
              icon: Icons.vertical_align_bottom,
              helperText: 'Speed for vertical plunging movements',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons() {
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
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(_isGenerated ? Icons.refresh : Icons.code),
              label: Text(_isGenerated ? 'Regenerate G-code' : 'Generate G-code'),
              onPressed: _isGenerating ? null : _generateGcode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(Icons.share),
              label: Text('Share G-code'),
              onPressed: _isGenerating || !_isGenerated ? null : _shareGcode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for visualizing the adjusted contour
class AdjustedContourPainter extends CustomPainter {
  final List<Point> adjustedContour;
  final MachineCoordinateSystem coordSystem;
  final Size imageSize;
  final Size displaySize;
  final bool showOriginalContour;
  final List<Point>? originalContour;

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