// lib/utils/image_processing_utils.dart

import 'dart:math';
import 'package:flutter/material.dart';

/// Validates and processes tap points for image perspective correction
class ImageTapPointHandler {
  final Size imageSize;
  final Size displaySize;
  
  ImageTapPointHandler({required this.imageSize, required this.displaySize});
  
  /// Converts raw tap coordinates to image coordinates with validation
  Offset? calculateValidImagePoint(Offset tapPoint) {
    // Calculate scale factors between display and actual image
    final double scaleX = imageSize.width / displaySize.width;
    final double scaleY = imageSize.height / displaySize.height;
    
    // Convert tap coordinates to image coordinates
    final double imageX = tapPoint.dx * scaleX;
    final double imageY = tapPoint.dy * scaleY;
    
    // Validate that the point is within image bounds
    if (imageX < 0 || imageX > imageSize.width || 
        imageY < 0 || imageY > imageSize.height) {
      print('WARNING: Tap point ($imageX, $imageY) is outside image bounds');
      return null;
    }
    
    return Offset(imageX, imageY);
  }
  
  /// Ensures we have valid points for perspective correction
  List<Offset> getValidPerspectivePoints(List<Offset> rawPoints) {
    final List<Offset?> processedPoints = 
        rawPoints.map((point) => calculateValidImagePoint(point)).toList();
    
    // Filter out null points and ensure we have enough valid points
    final List<Offset> validPoints = 
        processedPoints.whereType<Offset>().toList();
    
    return validPoints;
  }
}