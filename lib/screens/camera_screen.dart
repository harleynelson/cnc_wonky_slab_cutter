import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:async';

import '../models/settings_model.dart';
import '../utils/permissions_utils.dart';
import '../utils/constants.dart';
import '../widgets/camera_overlay.dart';
import 'preview_screen.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final SettingsModel settings;
  final Function(File) onImageCaptured;

  const CameraScreen({
    Key? key,
    required this.cameras,
    required this.settings,
    required this.onImageCaptured,
  }) : super(key: key);

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  late CameraController _controller;
  Future<void>? _initializeControllerFuture;
  bool _isCameraPermissionGranted = false;
  bool _isFlashOn = false;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final cameraStatus = await PermissionsUtils.requestCameraPermission();
    setState(() {
      _isCameraPermissionGranted = cameraStatus;
    });
    
    if (_isCameraPermissionGranted) {
      _initializeCamera();
    }
  }

  void _initializeCamera() {
    if (widget.cameras.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Error'),
          content: Text('No cameras available on this device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    _controller = CameraController(
      widget.cameras[_selectedCameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    }).catchError((error) {
      print('Error initializing camera: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initialize camera: $error')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera is not ready yet')),
      );
      return;
    }

    try {
      // Display a loading indicator
      setState(() {});

      // Take the picture
      final XFile photo = await _controller.takePicture();
      
      // Create a File instance from the XFile
      final File imageFile = File(photo.path);
      
      // Navigate to preview screen
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PreviewScreen(
            imageFile: imageFile,
            settings: widget.settings,
          ),
        ),
      );

      // Call the callback
      widget.onImageCaptured(imageFile);
    } catch (e) {
      print('Error taking picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to take picture: $e')),
      );
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
    if (widget.cameras.length <= 1) return;

    setState(() {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
      _initializeCamera();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraPermissionGranted) {
      return _buildPermissionDeniedUI();
    }

    return Scaffold(
      appBar: AppBar(title: Text('Capture Slab Image')),
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
                _checkPermissions();
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
            onPressed: widget.cameras.length > 1 ? _switchCamera : null,
          ),
        ],
      ),
    );
  }
}