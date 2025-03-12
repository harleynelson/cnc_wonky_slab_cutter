// lib/screens/processing_screen.dart
// Screen for processing images through a step-by-step flow with simplified slab detection

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image/image.dart' as img;

import '../services/processing/processing_flow_manager.dart';
import '../models/settings_model.dart';
import '../utils/general/constants.dart';
import '../utils/general/file_utils.dart';
import '../widgets/marker_overlay.dart';
import 'interactive_contour_screen.dart';

class ProcessingScreen extends StatefulWidget {
  final File imageFile;
  final SettingsModel settings;

  const ProcessingScreen({
    Key? key,
    required this.imageFile,
    required this.settings,
  }) : super(key: key);

  @override
  _ProcessingScreenState createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen> {
  late ProcessingFlowManager _flowManager;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _flowManager = ProcessingFlowManager(settings: widget.settings);
    _initProcessing();
  }

  Future<void> _initProcessing() async {
    setState(() {
      _isLoading = true;
    });

    // Initialize with the image
    await _flowManager.initWithImage(widget.imageFile);

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _openSlabDetectionScreen(ProcessingFlowManager flowManager) async {
    if (flowManager.result.markerResult == null || flowManager.result.originalImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marker detection must be completed first'))
      );
      return;
    }
    
    final bool? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InteractiveContourScreen(
          imageFile: flowManager.result.originalImage!,
          markerResult: flowManager.result.markerResult!,
          settings: widget.settings,
        ),
      ),
    );
    
    if (result == true) {
      // Contour detection was accepted, refresh the UI
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _flowManager,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Process Slab Image'),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _confirmReset,
              tooltip: 'Reset Processing',
            ),
          ],
        ),
        body: _isLoading
            ? _buildLoadingIndicator()
            : Consumer<ProcessingFlowManager>(
                builder: (context, flowManager, child) {
                  if (flowManager.state == ProcessingState.error) {
                    return _buildErrorView(flowManager.result.errorMessage ?? 'Unknown error');
                  }
                  return _buildProcessingView(flowManager);
                },
              ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Initializing...'),
        ],
      ),
    );
  }

  Widget _buildErrorView(String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.red),
            SizedBox(height: 20),
            Text(
              'Processing Error',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(
              errorMessage,
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 30),
            ElevatedButton.icon(
              icon: Icon(Icons.refresh),
              label: Text('Reset & Try Again'),
              onPressed: () {
                _flowManager.reset();
                _initProcessing();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingView(ProcessingFlowManager flowManager) {
    return Column(
      children: [
        _buildProgressStepper(flowManager),
        Expanded(
          child: _buildCurrentStepView(flowManager),
        ),
        _buildControlButtons(flowManager),
      ],
    );
  }

  Widget _buildProgressStepper(ProcessingFlowManager flowManager) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Stepper(
        currentStep: _getStepIndex(flowManager.state),
        controlsBuilder: (context, details) => Container(), // Hide default controls
        steps: [
          Step(
            title: Text('Image Capture'),
            subtitle: Text('Image captured and ready for processing'),
            content: Container(),
            isActive: flowManager.state != ProcessingState.notStarted,
            state: flowManager.state != ProcessingState.notStarted 
                ? StepState.complete 
                : StepState.indexed,
          ),
          Step(
            title: Text('Marker Detection'),
            subtitle: Text('Detecting calibration markers'),
            content: Container(),
            isActive: flowManager.state != ProcessingState.notStarted,
            state: _getStepState(flowManager.state, ProcessingState.markerDetection),
          ),
          Step(
            title: Text('Slab Detection'),
            subtitle: Text('Detecting slab contour'),
            content: Container(),
            isActive: flowManager.state != ProcessingState.notStarted && 
                     flowManager.state != ProcessingState.markerDetection,
            state: _getStepState(flowManager.state, ProcessingState.slabDetection),
          ),
          Step(
            title: Text('G-code Generation'),
            subtitle: Text('Generating toolpath and G-code'),
            content: Container(),
            isActive: flowManager.state == ProcessingState.gcodeGeneration || 
                     flowManager.state == ProcessingState.completed,
            state: _getStepState(flowManager.state, ProcessingState.gcodeGeneration),
          ),
        ],
      ),
    );
  }

  int _getStepIndex(ProcessingState state) {
    switch (state) {
      case ProcessingState.notStarted:
        return 0;
      case ProcessingState.markerDetection:
        return 1;
      case ProcessingState.slabDetection:
        return 2;
      case ProcessingState.gcodeGeneration:
      case ProcessingState.completed:
        return 3;
      case ProcessingState.error:
        return 0; // Default to first step on error
    }
  }

  StepState _getStepState(ProcessingState currentState, ProcessingState stepState) {
    if (currentState == ProcessingState.error) {
      return StepState.error;
    }
    
    if (currentState == stepState) {
      return StepState.editing;
    }
    
    if (_getStepIndex(currentState) > _getStepIndex(stepState)) {
      return StepState.complete;
    }
    
    return StepState.indexed;
  }

  Widget _buildCurrentStepView(ProcessingFlowManager flowManager) {
    switch (flowManager.state) {
      case ProcessingState.notStarted:
        return _buildImagePreview(flowManager);
      case ProcessingState.markerDetection:
        return _buildMarkerDetectionView(flowManager);
      case ProcessingState.slabDetection:
        return _buildSlabDetectionView(flowManager);
      case ProcessingState.gcodeGeneration:
      case ProcessingState.completed:
        return _buildGcodeGenerationView(flowManager);
      case ProcessingState.error:
        return _buildErrorView(flowManager.result.errorMessage ?? 'Unknown error');
    }
  }

  Widget _buildImagePreview(ProcessingFlowManager flowManager) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: flowManager.result.originalImage != null
                  ? Image.file(
                      flowManager.result.originalImage!,
                      fit: BoxFit.contain,
                    )
                  : Placeholder(),
            ),
            SizedBox(height: 20),
            Text(
              'Image ready for processing',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkerDetectionView(ProcessingFlowManager flowManager) {
  final markerResult = flowManager.result.markerResult;
  
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: flowManager.result.originalImage != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Original image
                      Image.file(
                        flowManager.result.originalImage!,
                        fit: BoxFit.contain,
                      ),
                      
                      // Marker overlay
                      if (markerResult != null && markerResult.markers.isNotEmpty)
                        FutureBuilder<Size>(
                          future: _getImageDimensions(flowManager.result.originalImage!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return SizedBox.shrink();
                            }
                            
                            return MarkerOverlay(
                              markers: markerResult.markers,
                              imageSize: snapshot.data!,
                            );
                          },
                        ),
                    ],
                  )
                : Placeholder(),
          ),
          SizedBox(height: 10),
          if (markerResult != null)
            Text(
              'Marker detection complete',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
            )
          else
            Text(
              'Detecting markers...',
              style: TextStyle(fontSize: 16),
            ),
        ],
      ),
    ),
  );
}

// Helper method to get image dimensions
Future<Size> _getImageDimensions(File imageFile) async {
  final bytes = await imageFile.readAsBytes();
  final image = await decodeImageFromList(bytes);
  return Size(image.width.toDouble(), image.height.toDouble());
}

  Widget _buildSlabDetectionView(ProcessingFlowManager flowManager) {
    final contourResult = flowManager.result.contourResult;
    final contourMethod = flowManager.result.contourMethod;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: flowManager.result.processedImage != null
                  ? _buildImageFromImgImage(flowManager.result.processedImage!)
                  : (flowManager.result.markerResult?.debugImage != null
                      ? _buildImageFromImgImage(flowManager.result.markerResult!.debugImage!)
                      : Placeholder()),
            ),
            SizedBox(height: 20),
            
            // Single detection button
            if (contourResult == null)
              ElevatedButton.icon(
                icon: Icon(Icons.find_in_page),
                label: Text('Detect Slab'),
                onPressed: () => _openSlabDetectionScreen(flowManager),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
              ),
            
            SizedBox(height: 10),
            if (contourResult != null)
              Text(
                'Slab contour detection complete',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
              )
            else
              Text(
                'Tap "Detect Slab" to proceed with slab detection',
                style: TextStyle(fontSize: 16),
              ),
            if (contourResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Detected ${contourResult.pointCount} contour points',
                  style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGcodeGenerationView(ProcessingFlowManager flowManager) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: flowManager.result.processedImage != null
                  ? _buildImageFromImgImage(flowManager.result.processedImage!)
                  : Placeholder(),
            ),
            SizedBox(height: 10),
            if (flowManager.state == ProcessingState.completed)
              Text(
                'G-code generation complete',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
              )
            else
              Text(
                'Generating G-code...',
                style: TextStyle(fontSize: 16),
              ),
            if (flowManager.result.gcode != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(Icons.save_alt),
                      label: Text('Save G-code'),
                      onPressed: () => _saveGcode(flowManager),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: Icon(Icons.share),
                      label: Text('Share G-code'),
                      onPressed: () => _shareGcode(flowManager),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageFromImgImage(img.Image image) {
    return FutureBuilder<Uint8List>(
      future: Future.value(Uint8List.fromList(img.encodePng(image))),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
          );
        }
        return Center(child: CircularProgressIndicator());
      },
    );
  }

  Widget _buildControlButtons(ProcessingFlowManager flowManager) {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Back button
          if (flowManager.state != ProcessingState.notStarted)
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(Icons.arrow_back),
                label: Text('Back'),
                onPressed: () {
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[300],
                  foregroundColor: Colors.black,
                ),
              ),
            ),

          SizedBox(width: 12),

          // Next step button
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(_getNextStepIcon(flowManager.state)),
              label: Text(_getNextStepLabel(flowManager.state)),
              onPressed: flowManager.result.canProceedToNextStep && flowManager.state != ProcessingState.completed
                  ? () => _proceedToNextStep(flowManager)
                  : null,
            ),
          ),

          // View debug button (only show when appropriate)
          if (_shouldShowDebugButton(flowManager))
            Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: IconButton(
                icon: Icon(Icons.bug_report),
                tooltip: 'View Debug Info',
                onPressed: () => _showDebugInfo(flowManager),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getNextStepIcon(ProcessingState state) {
    switch (state) {
      case ProcessingState.notStarted:
        return Icons.search;
      case ProcessingState.markerDetection:
        return Icons.content_cut;
      case ProcessingState.slabDetection:
        return Icons.code;
      case ProcessingState.gcodeGeneration:
      case ProcessingState.completed:
      case ProcessingState.error:
        return Icons.check;
    }
  }

  String _getNextStepLabel(ProcessingState state) {
    switch (state) {
      case ProcessingState.notStarted:
        return 'Detect Markers';
      case ProcessingState.markerDetection:
        return 'Detect Slab';
      case ProcessingState.slabDetection:
        return 'Generate G-code';
      case ProcessingState.gcodeGeneration:
        return 'Complete';
      case ProcessingState.completed:
        return 'Done';
      case ProcessingState.error:
        return 'Try Again';
    }
  }

  bool _shouldShowDebugButton(ProcessingFlowManager flowManager) {
    // Show debug button only when we have some debug info
    return flowManager.state == ProcessingState.markerDetection && flowManager.result.markerResult != null ||
           flowManager.state == ProcessingState.slabDetection && flowManager.result.contourResult != null ||
           flowManager.state == ProcessingState.completed;
  }

  Future<void> _proceedToNextStep(ProcessingFlowManager flowManager) async {
  setState(() {
    _isLoading = true;
  });

  if (flowManager.state == ProcessingState.markerDetection && 
      flowManager.result.markerResult != null) {
    // Go directly to interactive contour detection
    await _openSlabDetectionScreen(flowManager);
  } else {
    // Normal flow for other steps
    await flowManager.proceedToNextStep();
  }

  setState(() {
    _isLoading = false;
  });
}

  Future<void> _saveGcode(ProcessingFlowManager flowManager) async {
    if (flowManager.result.gcodeFile == null) {
      _showSnackBar('No G-code file available');
      return;
    }

    try {
      // Copy to documents directory with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'slab_surfacing_$timestamp.gcode';
      final savedFile = await FileUtils.getDocumentFile(fileName);
      await flowManager.result.gcodeFile!.copy(savedFile.path);
      
      _showSnackBar('G-code saved: ${savedFile.path}');
    } catch (e) {
      _showSnackBar('Error saving file: ${e.toString()}');
    }
  }

  Future<void> _shareGcode(ProcessingFlowManager flowManager) async {
    if (flowManager.result.gcodeFile == null) {
      _showSnackBar('No G-code file available');
      return;
    }

    try {
      await FileUtils.shareFile(
        flowManager.result.gcodeFile!,
        text: 'CNC Slab G-code generated by $appName',
      );
    } catch (e) {
      _showSnackBar('Error sharing file: ${e.toString()}');
    }
  }

  void _showDebugInfo(ProcessingFlowManager flowManager) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Processing Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (flowManager.result.markerResult != null) ...[
                Text('Marker Detection:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('• Markers found: ${flowManager.result.markerResult!.markers.length}'),
                Text('• Pixel to mm ratio: ${flowManager.result.markerResult!.pixelToMmRatio.toStringAsFixed(4)}'),
                Text('• Orientation angle: ${(flowManager.result.markerResult!.orientationAngle * 180 / 3.14159).toStringAsFixed(1)}°'),
                SizedBox(height: 10),
              ],
              if (flowManager.result.contourResult != null) ...[
                Text('Contour Detection:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('• Method: ${flowManager.result.contourMethod?.toString().split('.').last ?? "Unknown"}'),
                Text('• Contour points: ${flowManager.result.contourResult!.pointCount}'),
                if (flowManager.result.contourResult!.pixelArea > 0)
                  Text('• Area (px): ${flowManager.result.contourResult!.pixelArea.toStringAsFixed(1)}'),
                if (flowManager.result.contourResult!.machineArea > 0)
                  Text('• Area (mm²): ${flowManager.result.contourResult!.machineArea.toStringAsFixed(1)}'),
                SizedBox(height: 10),
              ],
              if (flowManager.result.toolpath != null) ...[
                Text('Toolpath:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('• Points: ${flowManager.result.toolpath!.length}'),
                SizedBox(height: 10),
              ],
              if (flowManager.result.gcode != null) ...[
                Text('G-code:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('• Size: ${(flowManager.result.gcode!.length / 1024).toStringAsFixed(1)} KB'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            child: Text('View Raw Debug Image'),
            onPressed: () {
              Navigator.pop(context);
              _showRawDebugImages(flowManager);
            },
          ),
          TextButton(
            child: Text('Close'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showRawDebugImages(ProcessingFlowManager flowManager) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Debug Images'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (flowManager.result.markerResult?.debugImage != null) ...[
                Text('Marker Detection Debug Image', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                _buildImageFromImgImage(flowManager.result.markerResult!.debugImage!),
                SizedBox(height: 15),
              ],
              if (flowManager.result.contourResult?.debugImage != null) ...[
                Text('Contour Detection Debug Image', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 5),
                _buildImageFromImgImage(flowManager.result.contourResult!.debugImage!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            child: Text('Close'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Processing'),
        content: Text('This will clear all current processing results. Continue?'),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          TextButton(
            child: Text('Reset'),
            onPressed: () {
              Navigator.pop(context);
              _flowManager.reset();
              _initProcessing();
            },
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}