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

  void _updateAdjustedContour() {
    final provider = Provider.of<ProcessingProvider>(context, listen: false);
    final flowManager = provider.flowManager;
    
    if (flowManager?.result.contourResult != null) {
      final originalContour = flowManager!.result.contourResult!.machineContour;
      
      // Create expanded contour if margin is not zero
      if (_slabMargin > 0) {
        // We work directly with machine coordinates which already account for rotation
        // Simply add margin to every point's distance from centroid
        
        // First calculate contour centroid
        double sumX = 0, sumY = 0;
        for (final point in originalContour) {
          sumX += point.x;
          sumY += point.y;
        }
        final centroidX = sumX / originalContour.length;
        final centroidY = sumY / originalContour.length;
        
        // Create expanded contour by moving each point away from centroid
        _adjustedContour = originalContour.map((point) {
          // Calculate vector from centroid to point
          final vx = point.x - centroidX;
          final vy = point.y - centroidY;
          
          // Calculate distance and normalized direction
          final dist = math.sqrt(vx * vx + vy * vy);
          if (dist < 0.0001) return point; // Avoid division by zero
          
          final nx = vx / dist;
          final ny = vy / dist;
          
          // Add margin in the direction from centroid to point
          return Point(
            point.x + nx * _slabMargin,
            point.y + ny * _slabMargin
          );
        }).toList();
        
        // Recalculate area and time based on adjusted contour
        _contourArea = _calculateContourArea(_adjustedContour!);
        _estimatedTime = _estimateMachiningTime(_adjustedContour!, _settings);
      } else {
        // Use original contour if no margin
        _adjustedContour = List.from(originalContour);
      }
    }
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
      
      // Generate G-code using adjusted contour
      final gcodeGenerator = GcodeGenerator(
        safetyHeight: _settings.safetyHeight,
        feedRate: _settings.feedRate,
        plungeRate: _settings.plungeRate,
        cuttingDepth: _settings.cuttingDepth,
      );
      
      final contour = _adjustedContour ?? flowManager.result.contourResult!.machineContour;
      final gcode = gcodeGenerator.generateContourGcode(contour);
      
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
                        
                      // Adjusted contour preview
                      if (_adjustedContour != null && _slabMargin > 0 && flowManager.result.markerResult != null)
                        Container(
                          child: CustomPaint(
                            size: Size(constraints.maxWidth, constraints.maxHeight),
                            painter: AdjustedContourPainter(
                              adjustedContour: _adjustedContour!,
                              coordSystem: MachineCoordinateSystem.fromMarkerPointsWithDistances(
                                flowManager.result.markerResult!.markers[0].toPoint(),
                                flowManager.result.markerResult!.markers[1].toPoint(),
                                flowManager.result.markerResult!.markers[2].toPoint(),
                                _settings.markerXDistance,
                                _settings.markerYDistance
                              ),
                              imageSize: imageSize,
                              displaySize: Size(constraints.maxWidth, constraints.maxHeight),
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

  AdjustedContourPainter({
    required this.adjustedContour,
    required this.coordSystem,
    required this.imageSize,
    required this.displaySize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Create a path for the adjusted contour
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

extension DoubleExtension on double {
  double sqrt() => (this <= 0) ? 0 : math.sqrt(this);
}