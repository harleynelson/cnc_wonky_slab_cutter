// lib/widgets/manual_contour_drawer.dart
// Widget for drawing contours manually by tapping points

import 'package:flutter/material.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/image_processing/geometry_utils.dart';
import '../utils/general/constants.dart';

class ManualContourDrawer extends StatefulWidget {
  final Size imageSize;
  final Function(List<CoordinatePointXY>) onContourComplete;
  final VoidCallback onCancel;

  const ManualContourDrawer({
    Key? key,
    required this.imageSize,
    required this.onContourComplete,
    required this.onCancel,
  }) : super(key: key);

  @override
  _ManualContourDrawerState createState() => _ManualContourDrawerState();
}

class _ManualContourDrawerState extends State<ManualContourDrawer> {
  final List<Offset> _points = [];
  bool _isDrawingComplete = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Full-screen GestureDetector for drawing
        GestureDetector(
          onTapDown: _handleTap,
          child: CustomPaint(
            key: ValueKey(_points.length), // Force rebuild when points change
            size: Size.infinite,
            painter: ManualContourPainter(
              points: _points,
              isComplete: _isDrawingComplete,
            ),
          ),
        ),
        
        // Status bar at bottom - matching combined_detector_screen.dart
        Positioned(
          bottom: 100, // Position above the buttons
          left: 16,
          right: 16,
          child: Container(
            padding: EdgeInsets.all(smallPadding),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              _getStatusMessage(),
              style: TextStyle(
                color: Colors.blue.shade900,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        
        // Control buttons at bottom - matches the layout from combined_detector_screen
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
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
                // Main action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.undo),
                        label: Text('Undo Point'),
                        onPressed: _points.isEmpty ? null : _undoLastPoint,
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.check_circle, color: Colors.white),
                        label: Text('Complete Drawing', style: TextStyle(color: Colors.white)),
                        onPressed: _points.length < 3 ? null : _completeDrawing,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 8),
                
                // Cancel button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.cancel),
                    label: Text('Cancel'),
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getStatusMessage() {
    if (_points.isEmpty) {
      return 'Tap anywhere to add your first point';
    } else if (_points.length < 3) {
      return 'Add at least ${3 - _points.length} more points';
    } else if (_isDrawingComplete) {
      return 'Contour complete! Tap Complete to continue';
    } else {
      return 'Tap near the first point to close the shape or press Complete when finished';
    }
  }

  void _handleTap(TapDownDetails details) {
    if (_isDrawingComplete) return;
    
    final tappedPoint = details.localPosition;
    
    // If we have points and tapped near the first one, close the shape
    if (_points.length > 2) {
      final firstPoint = _points.first;
      final distance = (tappedPoint - firstPoint).distance;
      
      if (distance < 30) { // Threshold for considering tap as "on" the first point
        _completeDrawing();
        return;
      }
    }
    
    setState(() {
      _points.add(tappedPoint);
    });
  }

  void _undoLastPoint() {
    if (_points.isNotEmpty) {
      setState(() {
        _points.removeLast();
        _isDrawingComplete = false;
      });
    }
  }

  void _completeDrawing() {
    if (_points.length < 3) return;
    
    setState(() {
      _isDrawingComplete = true;
    });
    
    // Get actual drawing area dimensions
    final renderBox = context.findRenderObject() as RenderBox;
    final drawingAreaSize = renderBox.size;
    
    // Calculate aspect ratios
    final imageAspect = widget.imageSize.width / widget.imageSize.height;
    final screenAspect = drawingAreaSize.width / drawingAreaSize.height;
    
    // Determine scale and offset for accurate mapping
    double scaledWidth, scaledHeight, offsetX = 0, offsetY = 0;
    
    if (imageAspect > screenAspect) {
      // Image is wider than screen (letterboxed)
      scaledWidth = drawingAreaSize.width;
      scaledHeight = scaledWidth / imageAspect;
      offsetY = (drawingAreaSize.height - scaledHeight) / 2;
    } else {
      // Image is taller than screen (pillarboxed)
      scaledHeight = drawingAreaSize.height;
      scaledWidth = scaledHeight * imageAspect;
      offsetX = (drawingAreaSize.width - scaledWidth) / 2;
    }
    
    // Convert display coordinates to image coordinates with aspect ratio correction
    final imagePoints = _points.map((offset) {
      // Remove offsets first
      final adjustedX = offset.dx - offsetX;
      final adjustedY = offset.dy - offsetY;
      
      // Scale to image dimensions
      final imageX = adjustedX * (widget.imageSize.width / scaledWidth);
      final imageY = adjustedY * (widget.imageSize.height / scaledHeight);
      
      return CoordinatePointXY(imageX, imageY);
    }).toList();
    
    // Add first point to end if not already closed
    if (imagePoints.first.x != imagePoints.last.x || 
        imagePoints.first.y != imagePoints.last.y) {
      imagePoints.add(imagePoints.first);
    }
    
    // Apply some smoothing/simplification if needed
    final simplifiedPoints = GeometryUtils.simplifyPolygon(imagePoints, 2.0);
    
    // Call the callback with the contour points
    widget.onContourComplete(simplifiedPoints);
  }
  
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manual Drawing Help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to draw the slab contour:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('• Tap on the screen to add points around your slab'),
            Text('• Continue adding points to trace the entire outline'),
            Text('• Tap near the first point to automatically close the shape'),
            Text('• Or press "Complete Drawing" when you\'re done'),
            Text('• Use "Undo Point" if you make a mistake'),
            SizedBox(height: 12),
            Text(
              'The more points you add, the more accurate the contour will be.',
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

class ManualContourPainter extends CustomPainter {
  final List<Offset> points;
  final bool isComplete;

  ManualContourPainter({
    required this.points,
    required this.isComplete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    
    // Configure paint styles
    final pointPaint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;
      
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
      
    final completedPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
      
    final outlinePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // Draw the lines between points
    if (points.length > 1) {
      final path = Path();
      path.moveTo(points.first.dx, points.first.dy);
      
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      
      // Close the path if drawing is complete
      if (isComplete) {
        path.close();
        canvas.drawPath(path, completedPaint);
      } else {
        canvas.drawPath(path, linePaint);
      }
    }
    
    // Draw points on top of lines
    for (int i = 0; i < points.length; i++) {
      // Draw a larger first point to make it clear where to tap to close
      final pointSize = i == 0 ? 12.0 : 8.0;
      final pointColor = i == 0 ? Colors.yellow : Colors.red;
      
      // Draw white outline around point for better visibility
      canvas.drawCircle(
        points[i], 
        pointSize + 2, 
        outlinePaint
      );
      
      // Draw the point
      pointPaint.color = pointColor;
      canvas.drawCircle(
        points[i], 
        pointSize, 
        pointPaint
      );
      
      // Mark the first point differently to indicate the start/end
      if (i == 0) {
        // Add a special marker for the first point
        final firstPointMarker = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.fill;
        
        canvas.drawCircle(
          points[i],
          pointSize / 2,
          firstPointMarker
        );
      }
    }
  }

  @override
  bool shouldRepaint(ManualContourPainter oldDelegate) {
    return points != oldDelegate.points || isComplete != oldDelegate.isComplete;
  }
}