// lib/screens/gcode_generator_screen.dart
// Screen for configuring and generating G-code

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/settings_model.dart';
import '../providers/processing_provider.dart';
import '../services/gcode/gcode_generator.dart';
import '../utils/general/machine_coordinates.dart';
import '../widgets/settings_fields.dart';

class GcodeGeneratorScreen extends StatefulWidget {
  final SettingsModel settings;

  const GcodeGeneratorScreen({
    Key? key,
    required this.settings,
  }) : super(key: key);

  @override
  _GcodeGeneratorScreenState createState() => _GcodeGeneratorScreenState();
}

class _GcodeGeneratorScreenState extends State<GcodeGeneratorScreen> {
  late SettingsModel _settings;
  bool _isGenerating = false;
  bool _isGenerated = false;
  String? _gcodePath;
  double _contourArea = 0.0;
  double _estimatedTime = 0.0;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _settings = widget.settings.copy();
    _calculateStats();
  }

  void _calculateStats() {
    final provider = Provider.of<ProcessingProvider>(context, listen: false);
    final flowManager = provider.flowManager;
    
    if (flowManager?.result.contourResult != null) {
      // Calculate area
      final contour = flowManager!.result.contourResult!.machineContour;
      _contourArea = _calculateContourArea(contour);
      
      // Estimate time
      _estimatedTime = _estimateMachiningTime(contour, _settings);
    }
  }

  double _calculateContourArea(List<Point> contour) {
    if (contour.length < 3) return 0;
    
    double area = 0;
    for (int i = 0; i < contour.length; i++) {
      int j = (i + 1) % contour.length;
      area += contour[i].x * contour[j].y;
      area -= contour[j].x * contour[i].y;
    }
    
    return (area.abs() / 2);
  }

  double _estimateMachiningTime(List<Point> contour, SettingsModel settings) {
    // Approximate toolpath length
    double pathLength = 0;
    for (int i = 0; i < contour.length - 1; i++) {
      final p1 = contour[i];
      final p2 = contour[i + 1];
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      pathLength += (dx * dx + dy * dy).sqrt();
    }
    
    // Add closing segment if needed
    if (contour.length > 1 && 
        (contour.first.x != contour.last.x || contour.first.y != contour.last.y)) {
      final p1 = contour.last;
      final p2 = contour.first;
      final dx = p2.x - p1.x;
      final dy = p2.y - p1.y;
      pathLength += (dx * dx + dy * dy).sqrt();
    }
    
    // Calculate time in minutes
    // Feed rate is in mm/min
    return pathLength / settings.feedRate;
  }

  Future<void> _generateGcode() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = '';
    });

    try {
      final provider = Provider.of<ProcessingProvider>(context, listen: false);
      final flowManager = provider.flowManager;
      
      if (flowManager == null || flowManager.result.contourResult == null) {
        throw Exception('No contour data available');
      }
      
      // Generate G-code
      final gcodeGenerator = GcodeGenerator(
        safetyHeight: _settings.safetyHeight,
        feedRate: _settings.feedRate,
        plungeRate: _settings.plungeRate,
        cuttingDepth: _settings.cuttingDepth,
      );
      
      final contour = flowManager.result.contourResult!.machineContour;
      final gcode = gcodeGenerator.generateContourGcode(contour);
      
      // Save G-code to file
      final tempDir = await Directory.systemTemp.createTemp('gcode_');
      final gcodeFile = File('${tempDir.path}/slab_surfacing.gcode');
      await gcodeFile.writeAsString(gcode);
      
      setState(() {
        _isGenerating = false;
        _isGenerated = true;
        _gcodePath = gcodeFile.path;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('G-code generated successfully!')),
      );
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _errorMessage = 'Error generating G-code: ${e.toString()}';
      });
    }
  }

  Future<void> _shareGcode() async {
    if (_gcodePath == null) {
      setState(() {
        _errorMessage = 'No G-code file available to share';
      });
      return;
    }
    
    try {
      final file = XFile(_gcodePath!);
      await Share.shareXFiles([file], text: 'CNC Slab G-code');
    } catch (e) {
      setState(() {
        _errorMessage = 'Error sharing G-code: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('G-code Generator'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatisticsCard(),
                  SizedBox(height: 16),
                  _buildMachineSettingsCard(),
                  SizedBox(height: 16),
                  _buildToolSettingsCard(),
                  SizedBox(height: 16),
                  _buildFeedSettingsCard(),
                ],
              ),
            ),
          ),
          if (_errorMessage.isNotEmpty)
            Container(
              padding: EdgeInsets.all(8),
              color: Colors.red.shade50,
              width: double.infinity,
              child: Text(
                _errorMessage,
                style: TextStyle(color: Colors.red.shade900),
                textAlign: TextAlign.center,
              ),
            ),
          _buildBottomButtons(),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contour Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Area:'),
                Text('${_contourArea.toStringAsFixed(2)} mm²'),
              ],
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Estimated Time:'),
                Text('${_estimatedTime.toStringAsFixed(2)} min'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineSettingsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Machine Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Divider(),
            SettingsTextField(
              label: 'CNC Work Area Width (mm)',
              value: _settings.cncWidth,
              onChanged: (value) => setState(() => _settings.cncWidth = value),
              icon: Icons.width_normal,
            ),
            SettingsTextField(
              label: 'CNC Work Area Height (mm)',
              value: _settings.cncHeight,
              onChanged: (value) => setState(() => _settings.cncHeight = value),
              icon: Icons.height,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolSettingsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tool Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Divider(),
            SettingsTextField(
              label: 'Tool Diameter (mm)',
              value: _settings.toolDiameter,
              onChanged: (value) => setState(() => _settings.toolDiameter = value),
              icon: Icons.circle_outlined,
            ),
            SettingsTextField(
              label: 'Stepover Distance (mm)',
              value: _settings.stepover,
              onChanged: (value) => setState(() => _settings.stepover = value),
              icon: Icons.compare_arrows,
              helperText: 'Distance between parallel toolpaths',
            ),
            SettingsTextField(
              label: 'Safety Height (mm)',
              value: _settings.safetyHeight,
              onChanged: (value) => setState(() => _settings.safetyHeight = value),
              icon: Icons.arrow_upward,
              helperText: 'Height for rapid movements',
            ),
            SettingsTextField(
              label: 'Cutting Depth (mm)',
              value: _settings.cuttingDepth,
              onChanged: (value) => setState(() => _settings.cuttingDepth = value),
              icon: Icons.arrow_downward,
              helperText: 'Z-height for cutting (usually 0 or negative)',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedSettingsCard() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Feed Rate Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Divider(),
            SettingsTextField(
              label: 'Feed Rate (mm/min)',
              value: _settings.feedRate,
              onChanged: (value) => setState(() => _settings.feedRate = value),
              icon: Icons.speed,
              helperText: 'Speed for cutting movements',
            ),
            SettingsTextField(
              label: 'Plunge Rate (mm/min)',
              value: _settings.plungeRate,
              onChanged: (value) => setState(() => _settings.plungeRate = value),
              icon: Icons.vertical_align_bottom,
              helperText: 'Speed for vertical plunging movements',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons() {
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
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(_isGenerated ? Icons.refresh : Icons.code),
              label: Text(_isGenerated ? 'Regenerate G-code' : 'Generate G-code'),
              onPressed: _isGenerating ? null : _generateGcode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              icon: Icon(Icons.share),
              label: Text('Share G-code'),
              onPressed: _isGenerating || !_isGenerated ? null : _shareGcode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension DoubleExtension on double {
  double sqrt() => (this <= 0) ? 0 : math.sqrt(this);
}
