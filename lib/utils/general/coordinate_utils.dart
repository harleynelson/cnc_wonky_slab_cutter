// lib/utils/general/coordinate_utils.dart

import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'machine_coordinates.dart';
import 'constants.dart';

/// Utility class for coordinate transformations and operations
class CoordinateUtils {
  /// Get effective image display area within a container, accounting for aspect ratio
  static Rect getImageDisplayRect(Size imageSize, Size containerSize) {
    final imageAspect = imageSize.width / imageSize.height;
    final containerAspect = containerSize.width / containerSize.height;
    
    double displayWidth, displayHeight, offsetX = 0, offsetY = 0;
    
    if (imageAspect > containerAspect) {
      // Image is wider than container - fills width, centers vertically
      displayWidth = containerSize.width;
      displayHeight = displayWidth / imageAspect;
      offsetY = (containerSize.height - displayHeight) / 2;
    } else {
      // Image is taller than container - fills height, centers horizontally
      displayHeight = containerSize.height;
      displayWidth = displayHeight * imageAspect;
      offsetX = (containerSize.width - displayWidth) / 2;
    }
    
    return Rect.fromLTWH(offsetX, offsetY, displayWidth, displayHeight);
  }
  
  /// Convert a tap position to image coordinates
  static CoordinatePointXY tapPositionToImageCoordinates(
    Offset tapPosition, 
    Size imageSize, 
    Size containerSize,
    {bool debug = false}
  ) {
    if (debug) {
      print('DEBUG: Tap at (${tapPosition.dx}, ${tapPosition.dy})');
      print('DEBUG: Image size: ${imageSize.width}x${imageSize.height}');
      print('DEBUG: Container size: ${containerSize.width}x${containerSize.height}');
    }
    
    final displayRect = getImageDisplayRect(imageSize, containerSize);
    
    if (debug) {
      print('DEBUG: Image display area: ${displayRect.left},${displayRect.top} to '
            '${displayRect.right},${displayRect.bottom}');
    }
    
    // Check if tap is inside display area
    bool isOutsideBounds = !displayRect.contains(tapPosition);
    if (isOutsideBounds && debug) {
      print('WARNING: Tap outside image display area');
    }
    
    // Calculate normalized position within the image (0-1 range)
    final normalizedX = (tapPosition.dx - displayRect.left) / displayRect.width;
    final normalizedY = (tapPosition.dy - displayRect.top) / displayRect.height;
    
    // Convert to image coordinates
    double imageX = normalizedX * imageSize.width;
    double imageY = normalizedY * imageSize.height;
    
    if (debug) {
      print('DEBUG: Normalized position: ($normalizedX, $normalizedY)');
      print('DEBUG: Raw image coordinates: ($imageX, $imageY)');
    }
    
    // Clamp to valid image range
    imageX = imageX.clamp(0.0, imageSize.width - 1);
    imageY = imageY.clamp(0.0, imageSize.height - 1);
    
    return CoordinatePointXY(imageX, imageY);
  }
  
  /// Convert image coordinates to display position
  static Offset imageCoordinatesToDisplayPosition(
    CoordinatePointXY imagePoint, 
    Size imageSize, 
    Size containerSize,
    {bool debug = false}
  ) {
    if (debug) {
      print('DEBUG: Converting image point (${imagePoint.x}, ${imagePoint.y}) to display position');
    }
    
    final displayRect = getImageDisplayRect(imageSize, containerSize);
    
    // Calculate normalized position within the image (0-1 range)
    final normalizedX = imagePoint.x / imageSize.width;
    final normalizedY = imagePoint.y / imageSize.height;
    
    // Convert to display coordinates
    final displayX = normalizedX * displayRect.width + displayRect.left;
    final displayY = normalizedY * displayRect.height + displayRect.top;
    
    if (debug) {
      print('DEBUG: Display position: ($displayX, $displayY)');
    }
    
    return Offset(displayX, displayY);
  }
  
  /// Get effective container size for image display, accounting for UI elements
  static Size getEffectiveContainerSize(BuildContext context) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Size boxSize = box.size;
    
    // Ensure minimum height for the container
    final height = math.max(boxSize.height, imageContainerMinHeight);
    
    return Size(boxSize.width, height);
  }
}