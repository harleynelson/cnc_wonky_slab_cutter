// lib/screens/home_page.dart
// Main home page that initializes the app and manages navigation

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';

import '../utils/general/settings_model.dart';
import '../flow_of_app/flow_provider.dart';
import 'file_picker_screen.dart';
import 'image_selection_screen.dart';
import 'settings_screen.dart';
import 'combined_detector_screen.dart';

class HomePage extends StatefulWidget {
  final List<CameraDescription> cameras;
  final SettingsModel settings;

  const HomePage({
    Key? key,
    required this.cameras,
    required this.settings,
  }) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  late List<Widget> _widgetOptions;
  late SettingsModel _settings;
  late bool _hasCameraSupport;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _hasCameraSupport = widget.cameras.isNotEmpty && !kIsWeb;
    _initializePages();
  }

  void _initializePages() {
    _widgetOptions = <Widget>[
      _hasCameraSupport
          ? ImageSelectionScreen(
              settings: _settings,
              onImageSelected: _handleImageCaptured,
            )
          : FilePickerScreen(
              settings: _settings,
              onImageSelected: _handleImageCaptured,
            ),
      SettingsScreen(
        settings: _settings,
        onSettingsChanged: _handleSettingsChanged,
      ),
    ];
  }

  void _handleImageCaptured(File imageFile) {
    // Initialize the processing provider
    final processingProvider = Provider.of<ProcessingProvider>(context, listen: false);
    processingProvider.createFlowManager(_settings);
    
    // Navigate to the combined detector screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CombinedDetectorScreen(
          imageFile: imageFile,
          settings: _settings,
          onSettingsChanged: _handleSettingsChanged,
        ),
      ),
    );
  }

  void _handleSettingsChanged(SettingsModel newSettings) async {
    setState(() {
      _settings = newSettings;
      // Reinitialize pages with new settings
      _initializePages();
    });
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(_hasCameraSupport ? Icons.camera_alt : Icons.photo_library),
            label: _hasCameraSupport ? 'Scan' : 'Select Image',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }
}