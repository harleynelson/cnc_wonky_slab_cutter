import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/settings_model.dart';
import 'preview_screen.dart';
import '../utils/general/constants.dart';

class FilePickerScreen extends StatefulWidget {
  final SettingsModel settings;
  final Function(File)? onImageSelected;

  const FilePickerScreen({
    Key? key,
    required this.settings,
    this.onImageSelected,
  }) : super(key: key);

  @override
  _FilePickerScreenState createState() => _FilePickerScreenState();
}

class _FilePickerScreenState extends State<FilePickerScreen> {
  // Using dynamic to handle both File and our custom MemoryFile
  dynamic _selectedImage;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Select Image')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Center(
      child: _isLoading
          ? _buildLoadingIndicator()
          : _selectedImage != null
              ? _buildImagePreview()
              : _buildInstructions(),
    );
  }

  Widget _buildLoadingIndicator() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Loading image...'),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: kIsWeb && _selectedImage is MemoryFile
                ? Image.memory(
                    (_selectedImage as MemoryFile).bytes,
                    fit: BoxFit.contain,
                  )
                : Image.file(
                    _selectedImage as File,
                    fit: BoxFit.contain,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                icon: Icon(Icons.refresh),
                label: Text('Select Another'),
                onPressed: _pickImage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  foregroundColor: Colors.black,
                ),
              ),
              ElevatedButton.icon(
                icon: Icon(Icons.arrow_forward),
                label: Text('Continue'),
                onPressed: _continueToPreview,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstructions() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image,
            size: 100,
            color: Colors.blue.withOpacity(0.5),
          ),
          SizedBox(height: 24),
          Text(
            'Select an image of your slab with markers',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16),
          Text(
            'The image should contain your slab with three markers positioned at:\n'
            '• Top left (Origin)\n'
            '• Top right (X-axis)\n'
            '• Bottom left (Scale)',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 32),
          ElevatedButton.icon(
            icon: Icon(Icons.photo_library),
            label: Text('Select Image'),
            onPressed: _pickImage,
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      setState(() {
        _isLoading = true;
      });

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        if (kIsWeb) {
          // Web platform handling
          if (result.files.single.bytes != null) {
            // Create a memory file with the bytes
            final fileName = 'web_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
            final memoryFile = MemoryFile(fileName, Uint8List.fromList(result.files.single.bytes!));
            
            setState(() {
              _selectedImage = memoryFile;
              _isLoading = false;
            });
          }
        } else {
          // Mobile/Desktop platform
          if (result.files.single.path != null) {
            setState(() {
              _selectedImage = File(result.files.single.path!);
              _isLoading = false;
            });
          }
        }
      } else {
        // User canceled the picker
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting image: $e')),
      );
    }
  }

  void _continueToPreview() {
    if (_selectedImage != null) {
      if (widget.onImageSelected != null) {
        if (_selectedImage is File) {
          widget.onImageSelected!(_selectedImage);
        } else if (_selectedImage is MemoryFile) {
          // In web, we need special handling in the parent component
          // This is simplified - actual implementation would need more care
          widget.onImageSelected!(_selectedImage);
        }
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PreviewScreen(
              imageFile: _selectedImage,
              settings: widget.settings,
            ),
          ),
        );
      }
    }
  }
}

// A custom class to handle web file operations
class MemoryFile {
  final String path;
  final Uint8List bytes;
  
  MemoryFile(this.path, this.bytes);
  
  Future<Uint8List> readAsBytes() async {
    return bytes;
  }
  
  // Add other methods as needed
  Future<String> readAsString() async {
    return String.fromCharCodes(bytes);
  }
}