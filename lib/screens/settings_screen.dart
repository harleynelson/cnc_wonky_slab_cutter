import 'package:flutter/material.dart';
import '../models/settings_model.dart';
import '../utils/constants.dart';
import '../widgets/settings_fields.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsModel settings;
  final Function(SettingsModel) onSettingsChanged;
  final int maxImageSize;
  final int processingTimeout;

  const SettingsScreen({
    Key? key,
    required this.settings,
    required this.onSettingsChanged,
    this.maxImageSize = 1200,  // Add default value
    this.processingTimeout = 30000,  // Add default value
  }) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsModel _settings;
  final _formKey = GlobalKey<FormState>();
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    // Create a copy of the settings to work with
    _settings = widget.settings.copy();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        actions: [
          if (_hasChanges)
            IconButton(
              icon: Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: 'Save Settings',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        onChanged: () {
          setState(() {
            _hasChanges = true;
          });
        },
        child: _buildSettingsForm(),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildSettingsForm() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('CNC Machine Settings'),
          SettingsTextField(
            label: 'CNC Work Area Width (mm)',
            value: _settings.cncWidth,
            onChanged: (value) => _settings.cncWidth = value,
            icon: Icons.width_normal,
          ),
          SettingsTextField(
            label: 'CNC Work Area Height (mm)',
            value: _settings.cncHeight,
            onChanged: (value) => _settings.cncHeight = value,
            icon: Icons.height,
          ),
          
          _buildSectionTitle('Marker Settings'),
          SettingsTextField(
            label: 'Marker Distance (mm)',
            value: _settings.markerDistance,
            onChanged: (value) => _settings.markerDistance = value,
            icon: Icons.straighten,
            helperText: 'Real-world distance between markers',
          ),
          
          _buildSectionTitle('Tool Settings'),
          SettingsTextField(
            label: 'Tool Diameter (mm)',
            value: _settings.toolDiameter,
            onChanged: (value) => _settings.toolDiameter = value,
            icon: Icons.circle_outlined,
          ),
          SettingsTextField(
            label: 'Stepover Distance (mm)',
            value: _settings.stepover,
            onChanged: (value) => _settings.stepover = value,
            icon: Icons.compare_arrows,
            helperText: 'Distance between parallel toolpaths',
          ),
          SettingsTextField(
            label: 'Safety Height (mm)',
            value: _settings.safetyHeight,
            onChanged: (value) => _settings.safetyHeight = value,
            icon: Icons.arrow_upward,
            helperText: 'Height for rapid movements',
          ),
          SettingsTextField(
            label: 'Cutting Depth (mm)',
            value: _settings.cuttingDepth,
            onChanged: (value) => _settings.cuttingDepth = value,
            icon: Icons.arrow_downward,
            helperText: 'Z-height for cutting (usually 0 or negative)',
          ),
          
          _buildSectionTitle('Feed Rates'),
          SettingsTextField(
            label: 'Feed Rate (mm/min)',
            value: _settings.feedRate,
            onChanged: (value) => _settings.feedRate = value,
            icon: Icons.speed,
            helperText: 'Speed for cutting movements',
          ),
          SettingsTextField(
            label: 'Plunge Rate (mm/min)',
            value: _settings.plungeRate,
            onChanged: (value) => _settings.plungeRate = value,
            icon: Icons.vertical_align_bottom,
            helperText: 'Speed for vertical plunging movements',
          ),
          
          SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          Divider(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          OutlinedButton.icon(
            icon: Icon(Icons.restore),
            label: Text('Restore Defaults'),
            onPressed: _restoreDefaults,
          ),
          ElevatedButton.icon(
            icon: Icon(Icons.save),
            label: Text('Save Settings'),
            onPressed: _hasChanges ? _saveSettings : null,
          ),
        ],
      ),
    );
  }

  void _restoreDefaults() {
    setState(() {
      _settings = SettingsModel.defaults();
      _hasChanges = true;
    });
  }

  void _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      // Save to persistent storage
      await _settings.save();
      
      // Notify parent
      widget.onSettingsChanged(_settings);
      
      // Update state
      setState(() {
        _hasChanges = false;
      });
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settings saved successfully')),
      );
    }
  }
}