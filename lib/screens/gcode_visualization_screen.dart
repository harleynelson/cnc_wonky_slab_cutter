// lib/screens/gcode_visualization_screen.dart
// Fixed visualization for G-code toolpaths on the slab image

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/general/constants.dart';
import '../models/settings_model.dart';
import '../services/gcode/gcode_parser.dart';

class GcodeVisualizationScreen extends StatefulWidget {
  final File imageFile;
  final String gcodePath;
  final List<CoordinatePointXY> contourPoints;
  final List<CoordinatePointXY>? toolpath;
  final MachineCoordinateSystem coordSystem;
  final SettingsModel settings;

  const GcodeVisualizationScreen({
    Key? key,
    required this.imageFile,
    required this.gcodePath,
    required this.contourPoints,
    this.toolpath,
    required this.coordSystem,
    required this.settings,
  }) : super(key: key);

  @override
  _GcodeVisualizationScreenState createState() => _GcodeVisualizationScreenState();
}

class _GcodeVisualizationScreenState extends State<GcodeVisualizationScreen> {
  List<List<CoordinatePointXY>> _toolpaths = [];
  bool _isLoading = true;
  String _errorMessage = '';
  bool _showContour = true;
  bool _showToolpath = true;
  int _selectedLayer = 0;
  List<String> _layers = ['All Layers'];
  Size? _imageSize;
  
  @override
  void initState() {
    super.initState();
    _loadImage();
    _loadGcode();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final image = await decodeImageFromList(bytes);
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      });
    } catch (e) {
      print("Error loading image dimensions: $e");
      setState(() {
        _errorMessage = 'Error loading image: ${e.toString()}';
      });
    }
  }

  Future<void> _loadGcode() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Read the G-code file
      final gcodeContent = await File(widget.gcodePath).readAsString();
      
      // Parse the G-code content
      final parser = GcodeParser();
      final parsedToolpaths = parser.parseGcode(gcodeContent);
      
      // If we have depth passes, they'll be separated
      final layerNames = ['All Layers'];
      for (int i = 0; i < parsedToolpaths.length; i++) {
        layerNames.add('Layer ${i + 1}');
      }
      
      setState(() {
        _toolpaths = parsedToolpaths;
        _layers = layerNames;
        _isLoading = false;
      });
      
      // Debug: Log toolpath information
      print("Loaded ${_toolpaths.length} toolpaths");
      for (int i = 0; i < _toolpaths.length; i++) {
        print("Toolpath $i has ${_toolpaths[i].length} points");
        if (_toolpaths[i].isNotEmpty) {
          print("First point: ${_toolpaths[i][0].x}, ${_toolpaths[i][0].y}");
          print("Last point: ${_toolpaths[i].last.x}, ${_toolpaths[i].last.y}");
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading G-code: ${e.toString()}';
        _isLoading = false;
        
        // If we have the toolpath from the generator, use that as fallback
        if (widget.toolpath != null) {
          _toolpaths = [widget.toolpath!];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('G-code Visualization'),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
            tooltip: 'Help',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildVisualizationOptions(),
          _isLoading 
              ? const Expanded(child: Center(child: CircularProgressIndicator()))
              : _errorMessage.isNotEmpty 
                  ? _buildErrorMessage() 
                  : _buildVisualizationView(),
        ],
      ),
    );
  }

  Widget _buildVisualizationOptions() {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Layer selection dropdown
          Row(
            children: [
              Text('Layer: ', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 8),
              Expanded(
                child: DropdownButton<int>(
                  value: _selectedLayer,
                  isExpanded: true,
                  items: List.generate(_layers.length, (index) {
                    return DropdownMenuItem(
                      value: index,
                      child: Text(_layers[index]),
                    );
                  }),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedLayer = value;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          // Visibility toggles
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToggleChip(
                label: 'Show Contour',
                icon: Icons.timeline,
                isSelected: _showContour,
                onSelected: (value) {
                  setState(() {
                    _showContour = value;
                  });
                },
              ),
              _buildToggleChip(
                label: 'Show Toolpath',
                icon: Icons.route,
                isSelected: _showToolpath,
                onSelected: (value) {
                  setState(() {
                    _showToolpath = value;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Function(bool) onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      avatar: Icon(
        icon,
        color: isSelected ? Colors.white : Colors.blue,
        size: 18,
      ),
      selected: isSelected,
      onSelected: onSelected,
      backgroundColor: Colors.grey.shade200,
      selectedColor: Colors.blue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(padding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadGcode,
              child: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualizationView() {
    if (_imageSize == null) {
      return const Expanded(
        child: Center(
          child: Text("Loading image dimensions..."),
        ),
      );
    }
    
    return Expanded(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Container(
          color: Colors.grey.shade100,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background image
                Image.file(widget.imageFile),
                
                // Contour overlay
                if (_showContour)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      print("Canvas size: ${constraints.maxWidth}x${constraints.maxHeight}");
                      print("Image size: ${_imageSize!.width}x${_imageSize!.height}");
                      print("Contour points: ${widget.contourPoints.length}");
                      
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: ContourPainter(
                          contour: widget.contourPoints,
                          imageSize: _imageSize!,
                          coordSystem: widget.coordSystem,
                          color: Colors.green.withOpacity(0.7),
                          strokeWidth: 2.0,
                        ),
                      );
                    },
                  ),
                
                // Toolpath overlay
                if (_showToolpath && _toolpaths.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      print("Toolpaths to display: ${_toolpaths.length}");
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: ToolpathPainter(
                          toolpaths: _selectedLayer == 0 ? _toolpaths : [_toolpaths[_selectedLayer - 1]],
                          imageSize: _imageSize!,
                          coordSystem: widget.coordSystem,
                          settings: widget.settings,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('G-code Visualization Help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This screen shows the G-code toolpath overlaid on your slab image.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('• Green outline: Detected slab contour'),
            Text('• Blue lines: Cutting toolpath'),
            Text('• Red points: Rapid moves'),
            SizedBox(height: 12),
            Text(
              'Use pinch gestures to zoom in/out and drag to pan the view.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
            SizedBox(height: 12),
            Text(
              'Layer Selection:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('• "All Layers" shows the complete toolpath'),
            Text('• Individual layers show depth passes'),
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

class ContourPainter extends CustomPainter {
  final List<CoordinatePointXY> contour;
  final Size imageSize;
  final MachineCoordinateSystem coordSystem;
  final Color color;
  final double strokeWidth;

  ContourPainter({
    required this.contour,
    required this.imageSize,
    required this.coordSystem,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (contour.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    bool first = true;

    for (final point in contour) {
      // This conversion is critical for proper display
      final pixelPoint = coordSystem.machineToPixelCoords(point);
      final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
        pixelPoint, imageSize, size);

      if (first) {
        path.moveTo(displayPoint.x, displayPoint.y);
        first = false;
      } else {
        path.lineTo(displayPoint.x, displayPoint.y);
      }
    }

    // Close the contour
    path.close();

    // Draw the path
    canvas.drawPath(path, paint);
    
    // Draw a dot for the first point to verify orientation
    if (contour.isNotEmpty) {
      final startPoint = coordSystem.machineToPixelCoords(contour.first);
      final displayStart = MachineCoordinateSystem.imageToDisplayCoordinates(
        startPoint, imageSize, size);
      
      canvas.drawCircle(
        Offset(displayStart.x, displayStart.y), 
        5.0, 
        Paint()..color = Colors.red..style = PaintingStyle.fill
      );
    }
  }

  @override
  bool shouldRepaint(ContourPainter oldDelegate) {
    return contour != oldDelegate.contour ||
           imageSize != oldDelegate.imageSize ||
           color != oldDelegate.color ||
           strokeWidth != oldDelegate.strokeWidth;
  }
}

class ToolpathPainter extends CustomPainter {
  final List<List<CoordinatePointXY>> toolpaths;
  final Size imageSize;
  final MachineCoordinateSystem coordSystem;
  final SettingsModel settings;

  ToolpathPainter({
    required this.toolpaths,
    required this.imageSize,
    required this.coordSystem,
    required this.settings,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (toolpaths.isEmpty) return;
    
    // Create paints
    final cutPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final rapidPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
      
    // Special paint for return-to-home movement
    final homePaint = Paint()
      ..color = Colors.purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
      
    // Create dashed pattern for return-to-home
    final homeDashPaint = Paint()
      ..color = Colors.purple
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final pointPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;
    
    // Draw the machine origin for reference
    final originPixel = coordSystem.machineToPixelCoords(CoordinatePointXY(0, 0));
    final originDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
      originPixel, imageSize, size);
    
    canvas.drawCircle(
      Offset(originDisplay.x, originDisplay.y),
      6.0,
      Paint()..color = Colors.purple..style = PaintingStyle.fill
    );
    
    // Draw text "Origin" next to the point
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Machine Origin',
        style: TextStyle(
          color: Colors.purple,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.white.withOpacity(0.7),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(originDisplay.x + 10, originDisplay.y - 10));
    
    // First draw traverse paths (if present - assumed to be the first path)
    if (toolpaths.length > 0 && toolpaths[0].isNotEmpty) {
      bool isFirstPath = true;
      final traversePath = toolpaths[0];
      final traversePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round;
      
      // Special dashed pattern for traverse moves
      traversePaint.strokeWidth = 1.5;
      
      if (traversePath.length > 1) {
        for (int i = 0; i < traversePath.length - 1; i++) {
          final CoordinatePointXY p1 = traversePath[i];
          final CoordinatePointXY p2 = traversePath[i + 1];
          
          // Convert to display coordinates
          final p1Pixel = coordSystem.machineToPixelCoords(p1);
          final p2Pixel = coordSystem.machineToPixelCoords(p2);
          
          final p1Display = MachineCoordinateSystem.imageToDisplayCoordinates(
            p1Pixel, imageSize, size);
          final p2Display = MachineCoordinateSystem.imageToDisplayCoordinates(
            p2Pixel, imageSize, size);
          
          // Draw traverse line
          canvas.drawLine(
            Offset(p1Display.x, p1Display.y),
            Offset(p2Display.x, p2Display.y),
            traversePaint
          );
          
          // Draw small circles at the start and end
          canvas.drawCircle(
            Offset(p1Display.x, p1Display.y),
            2.0,
            Paint()..color = Colors.red..style = PaintingStyle.fill
          );
          
          // Mark the first point with a special indicator
          if (isFirstPath && i == 0) {
            canvas.drawCircle(
              Offset(p1Display.x, p1Display.y),
              5.0,
              Paint()
                ..color = Colors.yellow
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.0
            );
            
            // Add "Start" label
            final textPainter = TextPainter(
              text: TextSpan(
                text: 'Start',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  backgroundColor: Colors.yellow.withOpacity(0.7),
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            textPainter.layout();
            textPainter.paint(canvas, Offset(p1Display.x + 10, p1Display.y - 10));
            
            isFirstPath = false;
          }
        }
      }
    }
    
    // Then draw cutting paths (skip the first one if it's traverse)
    for (int i = 1; i < toolpaths.length; i++) {
      final path = toolpaths[i];
      if (path.isEmpty) continue;
      
      // Adjust opacity based on layer index for multi-layer display
      final opacity = toolpaths.length <= 2 ? 
          1.0 : 
          0.3 + (0.7 * i / (toolpaths.length - 1));
      
      cutPaint.color = Colors.blue.withOpacity(opacity);
      
      // Draw the complete cutting path as one continuous line
      // This helps prevent any apparent slope due to improper point placement
      final cutPath = Path();
      bool first = true;
      
      for (int j = 0; j < path.length; j++) {
        final point = path[j];
        
        // Convert to display coordinates
        final pixelPoint = coordSystem.machineToPixelCoords(point);
        final displayPoint = MachineCoordinateSystem.imageToDisplayCoordinates(
          pixelPoint, imageSize, size);
        
        if (first) {
          cutPath.moveTo(displayPoint.x, displayPoint.y);
          first = false;
        } else {
          cutPath.lineTo(displayPoint.x, displayPoint.y);
        }
        
        // Draw points at vertices
        if (j % 10 == 0 || j == 0 || j == path.length - 1) { // Draw fewer points to reduce clutter
          canvas.drawCircle(
            Offset(displayPoint.x, displayPoint.y),
            1.0,
            pointPaint
          );
        }
      }
      
      // Draw the complete path at once
      canvas.drawPath(cutPath, cutPaint);
      
      // Draw start and end points more prominently
      if (path.length > 1) {
        // Start point
        final startPixel = coordSystem.machineToPixelCoords(path.first);
        final startDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
          startPixel, imageSize, size);
        
        canvas.drawCircle(
          Offset(startDisplay.x, startDisplay.y),
          3.0,
          Paint()..color = Colors.green..style = PaintingStyle.fill
        );
        
        // End point
        final endPixel = coordSystem.machineToPixelCoords(path.last);
        final endDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
          endPixel, imageSize, size);
        
        canvas.drawCircle(
          Offset(endDisplay.x, endDisplay.y),
          3.0,
          Paint()..color = Colors.orange..style = PaintingStyle.fill
        );
        
        // Add return-to-home visualization if it's the last toolpath
        if (i == toolpaths.length - 1 && settings.returnToHome) {
          // Draw the return-to-home path
          final lastPoint = path.last;
          final homePoint = CoordinatePointXY(0, 0);
          
          // Convert to display coordinates
          final lastPixel = coordSystem.machineToPixelCoords(lastPoint);
          final homePixel = coordSystem.machineToPixelCoords(homePoint);
          
          final lastDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
            lastPixel, imageSize, size);
          final homeDisplay = MachineCoordinateSystem.imageToDisplayCoordinates(
            homePixel, imageSize, size);
          
          // Draw dashed return-to-home line
          _drawDashedLine(
            canvas,
            Offset(lastDisplay.x, lastDisplay.y),
            Offset(homeDisplay.x, homeDisplay.y),
            homeDashPaint,
            dashLength: 5,
            spaceLength: 5
          );
          
          // Add "Return Home" label
          final textPainter = TextPainter(
            text: TextSpan(
              text: 'Return Home',
              style: TextStyle(
                color: Colors.purple,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                backgroundColor: Colors.white.withOpacity(0.7),
              ),
            ),
            textDirection: TextDirection.ltr,
          );
          textPainter.layout();
          
          // Calculate midpoint of return-to-home line for label placement
          final midX = (lastDisplay.x + homeDisplay.x) / 2;
          final midY = (lastDisplay.y + homeDisplay.y) / 2;
          
          textPainter.paint(canvas, Offset(midX, midY - 15));
        }
      }
    }
  }


  // Helper method to draw a dashed line
  void _drawDashedLine(
    Canvas canvas, 
    Offset start, 
    Offset end, 
    Paint paint, 
    {double dashLength = 5, double spaceLength = 5}
  ) {
    // Calculate the delta values and the total distance
    double dx = end.dx - start.dx;
    double dy = end.dy - start.dy;
    double distance = math.sqrt(dx * dx + dy * dy);
    
    // Normalize the direction vector
    double nx = dx / distance;
    double ny = dy / distance;
    
    // Pattern: dash, space, dash, space, ...
    double drawn = 0;
    bool isDash = true;
    
    while (drawn < distance) {
      double segmentLength = isDash ? dashLength : spaceLength;
      if (drawn + segmentLength > distance) {
        segmentLength = distance - drawn;
      }
      
      if (isDash) {
        double startX = start.dx + drawn * nx;
        double startY = start.dy + drawn * ny;
        double endX = start.dx + (drawn + segmentLength) * nx;
        double endY = start.dy + (drawn + segmentLength) * ny;
        
        canvas.drawLine(
          Offset(startX, startY),
          Offset(endX, endY),
          paint
        );
      }
      
      drawn += segmentLength;
      isDash = !isDash;
    }
  }

  @override
  bool shouldRepaint(ToolpathPainter oldDelegate) {
    return toolpaths != oldDelegate.toolpaths ||
           imageSize != oldDelegate.imageSize ||
           settings != oldDelegate.settings;
  }
}