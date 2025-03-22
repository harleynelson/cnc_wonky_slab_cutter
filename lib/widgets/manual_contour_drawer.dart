// lib/widgets/manual_contour_drawer.dart
// Widget for drawing contours manually by tapping points

import 'package:flutter/material.dart';
import '../utils/general/machine_coordinates.dart';
import '../utils/image_processing/geometry_utils.dart';

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
        // The drawing area
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
        
        // Instructions at the top
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Card(
            color: Colors.black.withOpacity(0.7),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Manual Contour Drawing',
                    style: TextStyle(
                      color: Colors.white, 
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap around the slab to create points. ${_points.isEmpty ? 'Start by tapping your first point.' : _points.length < 3 ? 'Add at least ${3 - _points.length} more points.' : 'Tap "Complete" when finished or tap near the first point to close the shape.'}',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Action buttons at the bottom
        Positioned(
  bottom: 24,
  left: 16,
  right: 16,
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      // Cancel button
      ElevatedButton.icon(
        icon: Icon(Icons.cancel, color: Colors.white),
        label: Text('Cancel', style: TextStyle(color: Colors.white)),
        onPressed: widget.onCancel,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
        ),
      ),
      
      // Undo button
      ElevatedButton.icon(
        icon: Icon(Icons.undo, color: Colors.white),
        label: Text('Undo Point', style: TextStyle(color: Colors.white)),
        onPressed: _points.isEmpty ? null : _undoLastPoint,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
        ),
      ),
      
      // Complete button
      ElevatedButton.icon(
        icon: Icon(Icons.check_circle, color: Colors.white),
        label: Text('Complete', style: TextStyle(color: Colors.white)),
        onPressed: _points.length < 3 ? null : _completeDrawing,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
        ),
      ),
    ],
  ),
),
      ],
    );
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
    
    // Force rebuild with the new point
    setState(() {
      _points.add(tappedPoint);
      
      // Debug print to verify point was added
      print('Added point ${_points.length - 1}: $tappedPoint');
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
    
    // Convert display coordinates to image coordinates
    final imagePoints = _points.map((offset) {
      return MachineCoordinateSystem.displayToImageCoordinates(
        CoordinatePointXY(offset.dx, offset.dy),
        widget.imageSize,
        MediaQuery.of(context).size,
      );
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
    
    // Draw points on top of lines - iterate through a copy of the list to avoid modifying paint during iteration
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
      
      // Don't show point numbers for manual contour drawing
      // Instead just mark the first point differently to indicate the start/end
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