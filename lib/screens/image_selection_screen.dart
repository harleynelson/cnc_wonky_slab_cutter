// lib/screens/image_selection_screen.dart
// Screen for selecting an image from gallery or camera

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/general/settings_model.dart';
import '../flow_of_app/flow_provider.dart';
import '../utils/general/permissions_utils.dart';
import 'camera_screen_with_overlay.dart';

class ImageSelectionScreen extends StatefulWidget {
  final SettingsModel settings;
  final Function(File) onImageSelected;

  const ImageSelectionScreen({
    Key? key,
    required this.settings,
    required this.onImageSelected,
  }) : super(key: key);

  @override
  _ImageSelectionScreenState createState() => _ImageSelectionScreenState();
}

class _ImageSelectionScreenState extends State<ImageSelectionScreen> {
  File? _selectedImage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Reset any previous processing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final processingProvider = Provider.of<ProcessingProvider>(context, listen: false);
      processingProvider.clearFlowManager();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select Slab Image'),
      ),
      body: _isLoading
          ? _buildLoadingIndicator()
          : _selectedImage != null
              ? _buildImagePreview()
              : _buildSelectionOptions(),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Loading...'),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Image.file(
              _selectedImage!,
              fit: BoxFit.contain,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.refresh),
                  label: Text('Choose Another'),
                  onPressed: _clearSelectedImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.arrow_forward),
                  label: Text('Continue'),
                  onPressed: _continueToDetection,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionOptions() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate,
              size: 100,
              color: Colors.blue.withOpacity(0.5),
            ),
            SizedBox(height: 24),
            Text(
              'Add an image of your slab with markers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Text(
              'The image should contain your slab with three markers positioned at:\n'
              '• Bottom left (Origin)\n'
              '• Bottom right (X-axis)\n'
              '• Top left (Scale)',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildOptionCard(
                  icon: Icons.camera_alt,
                  title: 'Camera',
                  onTap: _takePicture,
                ),
                _buildOptionCard(
                  icon: Icons.photo_library,
                  title: 'Gallery',
                  onTap: _pickFromGallery,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Card(
          elevation: 4,
          margin: EdgeInsets.symmetric(horizontal: 10),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 50, color: Colors.blue),
                SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _takePicture() async {
    try {
      // Request camera permission
      final permissionGranted = await PermissionsUtils.requestCameraPermission();
      if (!permissionGranted) {
        _showSnackBar('Camera permission is required to take a picture');
        return;
      }

      // Navigate to the custom camera screen with overlay
      final File? imageFile = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CameraScreenWithOverlay(
            settings: widget.settings,
          ),
        ),
      );

      if (imageFile != null) {
        setState(() {
          _selectedImage = imageFile;
        });
      }
    } catch (e) {
      _showSnackBar('Error taking picture: ${e.toString()}');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      // Request storage permission
      final permissionGranted = await PermissionsUtils.requestStoragePermission();
      if (!permissionGranted) {
        _showSnackBar('Storage permission is required to pick an image');
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 90,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
      }
    } catch (e) {
      _showSnackBar('Error picking image: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  void _continueToDetection() {
    if (_selectedImage == null) {
      _showSnackBar('Please select an image first');
      return;
    }

    // Pass the selected image to the parent widget
    widget.onImageSelected(_selectedImage!);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}