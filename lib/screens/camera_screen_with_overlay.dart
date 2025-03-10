// lib/screens/camera_screen_with_overlay.dart
// Camera screen with visual marker overlay

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../models/settings_model.dart';
import '../utils/constants.dart';
import '../utils/permissions_utils.dart';
import '../widgets/camera_overlay.dart';

class CameraScreenWithOverlay extends StatefulWidget {
  final SettingsModel settings;

  const CameraScreenWithOverlay({
    Key? key,
    required this.settings,
  }) : super(key: key);

  @override
  _CameraScreenWithOverlayState createState() => _CameraScreenWithOverlayState();
}

class _CameraScreenWithOverlayState extends State<CameraScreenWithOverlay> with WidgetsBindingObserver {
  late CameraController _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCameraPermissionGranted = false;
  bool _isFlashOn = false;
  int _selectedCameraIndex = 0;
  List<CameraDescription> _cameras = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCameras();
  }

  Future<void> _initCameras() async {
    try {
      // Check camera permission
      final cameraStatus = await PermissionsUtils.requestCameraPermission();
      setState(() {
        _isCameraPermissionGranted = cameraStatus;
      });
      
      if (_isCameraPermissionGranted) {
        // Get available cameras
        _cameras = await availableCameras();
        
        if (_cameras.isNotEmpty) {
          _initializeCamera();
        } else {
          _showErrorDialog('No cameras available on this device.');
        }
      }
    } catch (e) {
      _showErrorDialog('Error initializing camera: $e');
    }
  }

  void _initializeCamera() {
    if (_cameras.isEmpty) {
      _showErrorDialog('No cameras available on this device.');
      return;
    }

    _controller = CameraController(
      _cameras[_selectedCameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    }).catchError((error) {
      print('Error initializing camera: $error');
      _showErrorDialog('Failed to initialize camera: $error');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed before we got the chance to initialize the camera
    if (!_controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _takePicture() async {
    if (!_controller.value.isInitialized) {
      _showErrorDialog('Camera is not ready yet');
      return;
    }

    try {
      // Display a loading indicator
      setState(() {});

      // Take the picture
      final XFile photo = await _controller.takePicture();
      
      // Create a File instance from the XFile
      final File imageFile = File(photo.path);
      
      // Return the image file to the caller
      Navigator.pop(context, imageFile);
    } catch (e) {
      print('Error taking picture: $e');
      _showErrorDialog('Failed to take picture: $e');
    } finally {
      setState(() {});
    }
  }

  void _toggleFlash() async {
    if (!_controller.value.isInitialized) return;

    try {
      if (_isFlashOn) {
        await _controller.setFlashMode(FlashMode.off);
      } else {
        await _controller.setFlashMode(FlashMode.torch);
      }
      
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (e) {
      print('Error toggling flash: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to toggle flash: $e')),
      );
    }
  }

  void _switchCamera() {
    if (_cameras.length <= 1) return;

    setState(() {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
      _initializeCamera();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraPermissionGranted) {
      return _buildPermissionDeniedUI();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Capture Slab Image'),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
            tooltip: 'Marker Placement Help',
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Column(
              children: [
                Expanded(
                  child: _buildCameraPreview(),
                ),
                _buildCameraControls(),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }

  Widget _buildPermissionDeniedUI() {
    return Scaffold(
      appBar: AppBar(title: Text('Camera Access Needed')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.camera_alt, size: 100, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              'Camera permission is required',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                _initCameras();
              },
              child: Text('Grant Permission'),
            ),
            TextButton(
              onPressed: () async {
                await PermissionsUtils.openAppSettings();
              },
              child: Text('Open App Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final size = MediaQuery.of(context).size;
    
    return ClipRect(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Camera preview
          Container(
            width: size.width,
            height: size.width * _controller.value.aspectRatio,
            child: CameraPreview(_controller),
          ),
          
          // Camera overlay with guides
          CameraOverlay(
            markerSize: markerSize,
            markerOriginColor: Color(markerOriginColorHex),
            markerXAxisColor: Color(markerXAxisColorHex),
            markerScaleColor: Color(markerScaleColorHex),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraControls() {
    return Container(
      height: 100,
      color: Colors.black,
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Flash toggle
          IconButton(
            icon: Icon(
              _isFlashOn ? Icons.flash_on : Icons.flash_off,
              color: Colors.white,
              size: 28,
            ),
            onPressed: _toggleFlash,
          ),
          
          // Capture button
          FloatingActionButton(
            heroTag: "takePicture",
            child: Icon(Icons.camera_alt, size: 36),
            onPressed: _takePicture,
          ),
          
          // Camera switch button
          IconButton(
            icon: Icon(
              Icons.flip_camera_ios,
              color: Colors.white,
              size: 28,
            ),
            onPressed: _cameras.length > 1 ? _switchCamera : null,
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Marker Placement Guide'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Place three markers on your slab as follows:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.circle, color: Color(markerOriginColorHex), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Origin (Red): Bottom left corner'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.circle, color: Color(markerXAxisColorHex), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('X-Axis (Green): Bottom right corner'),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.circle, color: Color(markerScaleColorHex), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Scale (Blue): Top left corner'),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text(
              'These markers define the coordinate system for CNC processing.',
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