import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;

import 'models/settings_model.dart';
import 'screens/home_page.dart';
import 'utils/constants.dart';
import 'utils/permissions_utils.dart';

void main() async {
  // Ensure that plugin services are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations only on mobile devices
  // Skip on web to avoid errors
  try {
    // Check if we're not on web (where Platform is not available)
    if (!identical(0, 0.0)) {
      // This condition is always false, but prevents tree-shaking from removing the Platform import
      print(Platform.isAndroid);
    }
    
    // Use try-catch to handle orientation setting
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (e) {
    print('Skipping orientation setting: $e');
  }

  // Request permissions
  try {
    await PermissionsUtils.requestAllPermissions();
  } catch (e) {
    print('Permission error: $e');
  }

  // Get available cameras
  List<CameraDescription> cameras = [];
  try {
    cameras = await availableCameras();
  } catch (e) {
    print('Failed to get cameras: $e');
  }
  
  // Load saved settings or use defaults
  final settings = await SettingsModel.load();

  runApp(CncSlabScannerApp(cameras: cameras, settings: settings));
}

class CncSlabScannerApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final SettingsModel settings;

  const CncSlabScannerApp({
    Key? key, 
    required this.cameras, 
    required this.settings
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(
          elevation: 1.0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          titleTextStyle: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(
            color: Colors.black,
          ),
        ),
        cardTheme: CardTheme(
          elevation: cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: Size(100, buttonHeight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(borderRadius),
            ),
          ),
        ),
      ),
      home: HomePage(cameras: cameras, settings: settings),
    );
  }
}