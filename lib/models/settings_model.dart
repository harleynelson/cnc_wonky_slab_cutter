import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/general/constants.dart';

class SettingsModel {
  double cncWidth;
  double cncHeight;
  double markerXDistance;
  double markerYDistance;
  double toolDiameter;
  double stepover;
  double safetyHeight;
  double feedRate;
  double plungeRate;
  double cuttingDepth;
  int spindleSpeed;
  double edgeThreshold;
  double simplificationEpsilon;
  bool useConvexHull;
  int blurRadius;           // New parameter
  int smoothingWindowSize;  // New parameter
  int minSlabSize;           // Minimum area to be considered a slab
int gapAllowedMin;         // Minimum gap that can be bridged
int gapAllowedMax;         // Maximum gap that can be bridged
int continueSearchDistance;  // Distance to continue searching past first edge

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
  required this.spindleSpeed,
  this.edgeThreshold = 65.0,
  this.simplificationEpsilon = 5.0,
  this.useConvexHull = true,
  this.blurRadius = 6,          
  this.smoothingWindowSize = 7,
  this.minSlabSize = 1000,     // Add default value
  this.gapAllowedMin = 5,      // Add default value
  this.gapAllowedMax = 20,     // Add default value
  this.continueSearchDistance = 30,  // Default value
});
  
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
    spindleSpeed: spindleSpeed,
    edgeThreshold: edgeThreshold,
    simplificationEpsilon: simplificationEpsilon,
    useConvexHull: useConvexHull,
    blurRadius: blurRadius,
    smoothingWindowSize: smoothingWindowSize,
    minSlabSize: minSlabSize,
    gapAllowedMin: gapAllowedMin,
    gapAllowedMax: gapAllowedMax,
    continueSearchDistance: continueSearchDistance,
  );
}

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
    spindleSpeed: defaultSpindleSpeed,
    edgeThreshold: 65.0,
    simplificationEpsilon: 5.0,
    useConvexHull: true,
    blurRadius: 6,
    smoothingWindowSize: 7,
    minSlabSize: 1000,
    gapAllowedMin: 5, 
    gapAllowedMax: 20,
    continueSearchDistance: 30,
  );
}

  // Update toJson method
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
    'spindleSpeed': spindleSpeed,
    'edgeThreshold': edgeThreshold,
    'simplificationEpsilon': simplificationEpsilon,
    'useConvexHull': useConvexHull,
    'blurRadius': blurRadius,
    'smoothingWindowSize': smoothingWindowSize,
    'minSlabSize': minSlabSize,
    'gapAllowedMin': gapAllowedMin,
    'gapAllowedMax': gapAllowedMax,
    'continueSearchDistance': continueSearchDistance,
  };
}

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
    spindleSpeed: json['spindleSpeed'] ?? defaultSpindleSpeed,
    edgeThreshold: json['edgeThreshold'] ?? 50.0,
    simplificationEpsilon: json['simplificationEpsilon'] ?? 5.0,
    useConvexHull: json['useConvexHull'] ?? true,
    blurRadius: json['blurRadius'] ?? 3,
    smoothingWindowSize: json['smoothingWindowSize'] ?? 5,
    minSlabSize: json['minSlabSize'] ?? 1000,
    gapAllowedMin: json['gapAllowedMin'] ?? 5,
    gapAllowedMax: json['gapAllowedMax'] ?? 20,
    continueSearchDistance: json['continueSearchDistance'] ?? 30,
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