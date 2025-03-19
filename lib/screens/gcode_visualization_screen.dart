// lib/screens/gcode_visualization_screen.dart
// Fixed visualization for G-code toolpaths on the slab image

import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/general/constants.dart';
import '../utils/general/settings_model.dart';
import '../utils/gcode/gcode_parser.dart';
import '../utils/toolpath/contour_painter.dart';
import '../utils/toolpath/toolpath_painter.dart';

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
  bool _showContour = false; // Changed to false by default
  bool _showToolpath = true;
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
      
      setState(() {
        _toolpaths = parsedToolpaths;
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
      child: Row(
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
                
                // Toolpath overlay - show all toolpaths at once
                if (_showToolpath && _toolpaths.isNotEmpty)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      print("Toolpaths to display: ${_toolpaths.length}");
                      return CustomPaint(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                        painter: ToolpathPainter(
                          toolpaths: _toolpaths,
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