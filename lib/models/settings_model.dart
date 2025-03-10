import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class SettingsModel {
  double cncWidth;
  double cncHeight;
  double markerXDistance;  // Distance between origin and X-axis marker in mm
  double markerYDistance;  // Distance between origin and Y-axis/scale marker in mm
  double toolDiameter;
  double stepover;
  double safetyHeight;
  double feedRate;
  double plungeRate;
  double cuttingDepth;

  SettingsModel({
    required this.cncWidth,
    required this.cncHeight,
    required this.markerXDistance,
    required this.markerYDistance,
    required this.toolDiameter,
    required this.stepover,
    required this.safetyHeight,
    required this.feedRate,
    required this.plungeRate,
    required this.cuttingDepth,
  });
  
  // Create a copy of the settings
  SettingsModel copy() {
    return SettingsModel(
      cncWidth: cncWidth,
      cncHeight: cncHeight,
      markerXDistance: markerXDistance,
      markerYDistance: markerYDistance,
      toolDiameter: toolDiameter,
      stepover: stepover,
      safetyHeight: safetyHeight,
      feedRate: feedRate,
      plungeRate: plungeRate,
      cuttingDepth: cuttingDepth,
    );
  }

  // Get default settings
  static SettingsModel defaults() {
    return SettingsModel(
      cncWidth: defaultCncWidth,
      cncHeight: defaultCncHeight,
      markerXDistance: defaultMarkerXDistance,
      markerYDistance: defaultMarkerYDistance,
      toolDiameter: defaultToolDiameter,
      stepover: defaultStepover,
      safetyHeight: defaultSafetyHeight,
      feedRate: defaultFeedRate,
      plungeRate: defaultPlungeRate,
      cuttingDepth: defaultCuttingDepth,
    );
  }

  // Convert settings to JSON
  Map<String, dynamic> toJson() {
    return {
      'cncWidth': cncWidth,
      'cncHeight': cncHeight,
      'markerXDistance': markerXDistance,
      'markerYDistance': markerYDistance,
      'toolDiameter': toolDiameter,
      'stepover': stepover,
      'safetyHeight': safetyHeight,
      'feedRate': feedRate,
      'plungeRate': plungeRate,
      'cuttingDepth': cuttingDepth,
    };
  }

  // Create settings from JSON
  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      cncWidth: json['cncWidth'] ?? defaultCncWidth,
      cncHeight: json['cncHeight'] ?? defaultCncHeight,
      markerXDistance: json['markerXDistance'] ?? defaultMarkerXDistance,
      markerYDistance: json['markerYDistance'] ?? defaultMarkerYDistance,
      toolDiameter: json['toolDiameter'] ?? defaultToolDiameter,
      stepover: json['stepover'] ?? defaultStepover,
      safetyHeight: json['safetyHeight'] ?? defaultSafetyHeight,
      feedRate: json['feedRate'] ?? defaultFeedRate,
      plungeRate: json['plungeRate'] ?? defaultPlungeRate,
      cuttingDepth: json['cuttingDepth'] ?? defaultCuttingDepth,
    );
  }

  // Load settings from SharedPreferences
  static Future<SettingsModel> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString('settings');
      
      if (settingsJson == null) {
        return defaults();
      }
      
      final Map<String, dynamic> settings = jsonDecode(settingsJson);
      return SettingsModel.fromJson(settings);
    } catch (e) {
      print('Error loading settings: $e');
      return defaults();
    }
  }

  // Save settings to SharedPreferences
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = jsonEncode(toJson());
      await prefs.setString('settings', settingsJson);
    } catch (e) {
      print('Error saving settings: $e');
    }
  }
}