import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/settings_model.dart';
import 'camera_screen.dart';
import 'file_picker_screen.dart';
import 'settings_screen.dart';
import '../utils/constants.dart';

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
          ? CameraScreen(
              cameras: widget.cameras,
              settings: _settings,
              onImageCaptured: _handleImageCaptured,
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
    // Navigation to preview screen will be handled in the camera/file_picker screen
    // This is just a placeholder for any additional logic needed at this level
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