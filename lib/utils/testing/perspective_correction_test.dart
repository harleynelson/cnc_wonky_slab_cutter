// lib/utils/testing/perspective_correction_test.dart
// Utility to test the perspective correction algorithm

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../general/machine_coordinates.dart';
import '../image_processing/image_correction_utils.dart';

/// Utility class for testing the perspective correction algorithm
class PerspectiveCorrectionTest {
  /// Generate a test grid image with distortion to test perspective correction
  static Future<File> generateTestGrid(String outputPath, int width, int height) async {
    // Create a new image with checkerboard pattern
    final testImage = img.Image(width: width, height: height);
    
    // Fill with white
    img.fill(testImage, color: img.ColorRgba8(255, 255, 255, 255));
    
    // Draw grid lines
    final gridSize = 50;
    final gridColor = img.ColorRgba8(0, 0, 0, 255);
    
    // Draw horizontal lines
    for (int y = 0; y < height; y += gridSize) {
      for (int x = 0; x < width; x++) {
        testImage.setPixel(x, y, gridColor);
      }
    }
    
    // Draw vertical lines
    for (int x = 0; x < width; x += gridSize) {
      for (int y = 0; y < height; y++) {
        testImage.setPixel(x, y, gridColor);
      }
    }
    
    // Draw numbered markers at grid intersections
    int markerCount = 0;
    for (int y = 0; y < height; y += gridSize) {
      for (int x = 0; x < width; x += gridSize) {
        if (x > 0 && y > 0) {
          markerCount++;
          _drawNumber(testImage, x, y, markerCount);
        }
      }
    }
    
    // Save to file
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(img.encodePng(testImage));
    
    return outputFile;
  }
  
  /// Test perspective correction with a specific image and marker points
  static Future<File> testPerspectiveCorrection(
    File inputImageFile, 
    CoordinatePointXY originMarker,
    CoordinatePointXY xAxisMarker,
    CoordinatePointXY yAxisMarker,
    CoordinatePointXY topRightMarker,
    double markerXDistance,
    double markerYDistance,
    String outputPath
  ) async {
    // Load the image
    final imageBytes = await inputImageFile.readAsBytes();
    final image = img.decodeImage(imageBytes);
    
    if (image == null) {
      throw Exception('Failed to decode input image');
    }
    
    // Apply perspective correction
    final correctedImage = await ImageCorrectionUtils.correctPerspective(
      image,
      originMarker,
      xAxisMarker,
      yAxisMarker,
      topRightMarker,
      markerXDistance,
      markerYDistance
    );
    
    // Save corrected image
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(img.encodePng(correctedImage));
    
    return outputFile;
  }
  
  /// Draw a number on the image
  static void _drawNumber(img.Image image, int x, int y, int number) {
    final numberStr = number.toString();
    final textColor = img.ColorRgba8(255, 0, 0, 255);
    final bgColor = img.ColorRgba8(255, 255, 255, 200);
    
    // Draw background
    img.fillCircle(
      image,
      x: x,
      y: y,
      radius: 10,
      color: bgColor
    );
    
    // Draw text (simplified - just a cross marker with the number next to it)
    // Using a primitive drawing approach since drawString requires font parameter
    for (int i = 0; i < numberStr.length; i++) {
      // Draw a simple dot representation of the digit
      final int digit = int.parse(numberStr[i]);
      final int digitX = x + 5 + (i * 10);
      
      // Draw a small filled circle
      img.fillCircle(
        image, 
        x: digitX, 
        y: y - 5, 
        radius: 3,
        color: textColor
      );
    }
  }
  
  /// Run a comprehensive test of the perspective correction algorithm
  static Future<void> runComprehensiveTest(String testDir) async {
    // Create test directory if it doesn't exist
    final directory = Directory(testDir);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    
    // Generate test grid image
    final testGridPath = '$testDir/test_grid.png';
    final testGridFile = await generateTestGrid(testGridPath, 800, 800);
    
    // Test with different perspective distortions
    
    // 1. Rectangular (no distortion)
    await testPerspectiveCorrection(
      testGridFile,
      CoordinatePointXY(100, 700),  // Origin
      CoordinatePointXY(700, 700),  // X-Axis
      CoordinatePointXY(100, 100),  // Y-Axis
      CoordinatePointXY(700, 100),  // Top-Right
      600,  // markerXDistance
      600,  // markerYDistance
      '$testDir/corrected_rectangular.png'
    );
    
    // 2. Trapezoid (perspective distortion)
    await testPerspectiveCorrection(
      testGridFile,
      CoordinatePointXY(200, 700),  // Origin
      CoordinatePointXY(600, 700),  // X-Axis
      CoordinatePointXY(100, 100),  // Y-Axis
      CoordinatePointXY(700, 100),  // Top-Right
      600,  // markerXDistance
      600,  // markerYDistance
      '$testDir/corrected_trapezoid.png'
    );
    
    // 3. Quadrilateral (severe distortion)
    await testPerspectiveCorrection(
      testGridFile,
      CoordinatePointXY(300, 650),  // Origin
      CoordinatePointXY(600, 700),  // X-Axis
      CoordinatePointXY(200, 150),  // Y-Axis
      CoordinatePointXY(550, 100),  // Top-Right
      600,  // markerXDistance
      600,  // markerYDistance
      '$testDir/corrected_quadrilateral.png'
    );
    
    print('Comprehensive perspective correction tests completed. Check $testDir for results.');
  }
}