import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../models/settings_model.dart';
import '../services/image_processing/slab_detector.dart';
import '../utils/file_utils.dart';
import '../utils/constants.dart';
import 'file_picker_screen.dart';  // Import for MemoryFile type

class PreviewScreen extends StatefulWidget {
  final dynamic imageFile;  // Can be File or MemoryFile
  final SettingsModel settings;

  const PreviewScreen({
    Key? key,
    required this.imageFile,
    required this.settings,
  }) : super(key: key);

  @override
  _PreviewScreenState createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  bool _isProcessing = false;
  bool _isProcessed = false;
  File? _processedImageFile;
  File? _gcodeFile;
  String _statusMessage = '';
  String _errorDetails = '';
  SlabProcessingResult? _processingResult;
  Uint8List? _webImageBytes;

  @override
  void initState() {
    super.initState();
    // For web, extract the bytes from MemoryFile
    if (kIsWeb && widget.imageFile is MemoryFile) {
      _loadWebImage();
    }
  }

  Future<void> _loadWebImage() async {
    if (widget.imageFile is MemoryFile) {
      final memoryFile = widget.imageFile as MemoryFile;
      setState(() {
        _webImageBytes = memoryFile.bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Preview & Process'),
        actions: [
          if (_isProcessed && _gcodeFile != null)
            IconButton(
              icon: Icon(Icons.share),
              onPressed: _shareGcode,
              tooltip: 'Share G-code',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildImagePreview(),
          ),
          if (_errorDetails.isNotEmpty)
            _buildErrorPanel(),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'Processing image...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }
    
    if (_isProcessed && _processedImageFile != null) {
      return InteractiveViewer(
        panEnabled: true,
        boundaryMargin: EdgeInsets.all(20),
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(_processedImageFile!),
      );
    } else if (_webImageBytes != null && kIsWeb) {
      return InteractiveViewer(
        panEnabled: true,
        boundaryMargin: EdgeInsets.all(20),
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.memory(_webImageBytes!),
      );
    } else if (widget.imageFile is File) {
      return InteractiveViewer(
        panEnabled: true,
        boundaryMargin: EdgeInsets.all(20),
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(widget.imageFile),
      );
    } else {
      // Fallback
      return Center(
        child: Text('Unable to display image'),
      );
    }
  }

  Widget _buildErrorPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      color: Colors.red.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Error processing image',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.copy),
                tooltip: 'Copy error details',
                onPressed: () => _copyErrorToClipboard(),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            _errorDetails,
            style: TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_statusMessage.isNotEmpty && _errorDetails.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _statusMessage,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isProcessed ? Colors.green : Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.refresh),
                  label: Text('Retake'),
                  onPressed: _isProcessing ? null : () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(_isProcessed ? Icons.check : Icons.scanner),
                  label: Text(_isProcessed ? 'Processed' : 'Process Image'),
                  onPressed: _isProcessing || _isProcessed ? null : _processImage,
                ),
              ),
            ],
          ),
          if (_isProcessed && _gcodeFile != null && !kIsWeb)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ElevatedButton.icon(
                icon: Icon(Icons.save_alt),
                label: Text('Save G-code'),
                onPressed: _saveGcode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
              ),
            ),
          if (_isProcessed && _gcodeFile != null && kIsWeb)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ElevatedButton.icon(
                icon: Icon(Icons.download),
                label: Text('Download G-code'),
                onPressed: _downloadGcode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _processImage() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing image...';
      _errorDetails = '';
    });

    try {
      // On web, we don't have actual file processing capability yet
      if (kIsWeb) {
        // Simulate processing for web
        await _simulateWebProcessing();
        return;
      }
      
      // Create an instance of the slab detector
      final slabDetector = SlabDetector(settings: widget.settings);
      
      // Process the image
      final result = await slabDetector.processImage(widget.imageFile);
      
      setState(() {
        _processedImageFile = result.processedImage;
        _gcodeFile = result.gcodeFile;
        _processingResult = result;
        _isProcessed = true;
        _isProcessing = false;
        _statusMessage = 'Processing complete! G-code generated.';
      });
    } catch (e, stackTrace) {
      setState(() {
        _isProcessing = false;
        _statusMessage = '';
        _errorDetails = 'Error: ${e.toString()}\n\nStack trace:\n${stackTrace.toString()}';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing image. See details for more information.'),
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Copy Error',
            onPressed: _copyErrorToClipboard,
          ),
        ),
      );
    }
  }

  void _copyErrorToClipboard() {
    Clipboard.setData(ClipboardData(text: _errorDetails));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error details copied to clipboard')),
    );
  }

  // Simulated processing for web platform
  Future<void> _simulateWebProcessing() async {
    // Wait a bit to simulate processing
    await Future.delayed(Duration(seconds: 2));
    
    setState(() {
      // For web, we'll just display the original image as "processed"
      _webImageBytes = widget.imageFile.bytes;
      _isProcessed = true;
      _isProcessing = false;
      _statusMessage = 'Processing complete! (Web demo mode)';
    });
  }
  
  Future<void> _shareGcode() async {
    if (_gcodeFile != null && !kIsWeb) {
      try {
        await FileUtils.shareFile(
          _gcodeFile!,
          text: 'CNC Slab G-code generated by ${appName}',
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing file: ${e.toString()}')),
        );
      }
    }
  }
  
  Future<void> _saveGcode() async {
    if (_gcodeFile != null && !kIsWeb) {
      try {
        // Copy file to documents directory with a better name
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final fileName = 'slab_surfacing_$timestamp.gcode';
        final savedFile = await FileUtils.getDocumentFile(fileName);
        await _gcodeFile!.copy(savedFile.path);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('G-code saved: ${savedFile.path}'),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => FileUtils.shareFile(savedFile),
            ),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving file: ${e.toString()}')),
        );
      }
    }
  }
  
  // Web-specific method for downloading G-code
  void _downloadGcode() {
    // This is a placeholder - in a real app, you'd implement this
    // using js interop to trigger a download in the browser
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Download functionality is not implemented in this demo'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}