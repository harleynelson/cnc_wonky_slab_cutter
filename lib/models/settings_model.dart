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
  int depthPasses;  // New property for multiple depth passes
  double edgeThreshold;
  double simplificationEpsilon;
  bool useConvexHull;
  int blurRadius;
  int smoothingWindowSize;
  int minSlabSize;
  int gapAllowedMin;
  int gapAllowedMax;
  int continueSearchDistance;
  int contourPostProcessPoints;  // New property for contour post-processing
  bool forceHorizontalPaths; // for path direction preference

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
    this.depthPasses = 1,  // Default to 1 depth pass
    this.edgeThreshold = defaultEdgeThreshold,
    this.simplificationEpsilon = defaultSimplificationEpsilon,
    this.useConvexHull = defaultUseConvexHull,
    this.blurRadius = defaultBlurRadius,
    this.smoothingWindowSize = defaultSmoothingWindowSize,
    this.minSlabSize = minSlabSizeDefault,
    this.gapAllowedMin = gapAllowedMinDefault,
    this.gapAllowedMax = gapAllowedMaxDefault,
    this.continueSearchDistance = continueSearchDistanceDefault,
    this.contourPostProcessPoints = defaultContourPostProcessPoints,
    this.forceHorizontalPaths = true, // Default to horizontal
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
      depthPasses: depthPasses,
      edgeThreshold: edgeThreshold,
      simplificationEpsilon: simplificationEpsilon,
      useConvexHull: useConvexHull,
      blurRadius: blurRadius,
      smoothingWindowSize: smoothingWindowSize,
      minSlabSize: minSlabSize,
      gapAllowedMin: gapAllowedMin,
      gapAllowedMax: gapAllowedMax,
      continueSearchDistance: continueSearchDistance,
      contourPostProcessPoints: contourPostProcessPoints,
    forceHorizontalPaths: forceHorizontalPaths,
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
      depthPasses: 1,  // Default to 1 depth pass
      edgeThreshold: defaultEdgeThreshold,
      simplificationEpsilon: defaultSimplificationEpsilon,
      useConvexHull: defaultUseConvexHull,
      blurRadius: defaultBlurRadius,
      smoothingWindowSize: defaultSmoothingWindowSize,
      minSlabSize: minSlabSizeDefault,
      gapAllowedMin: gapAllowedMinDefault,
      gapAllowedMax: gapAllowedMaxDefault,
      continueSearchDistance: continueSearchDistanceDefault,
      contourPostProcessPoints: defaultContourPostProcessPoints,
      forceHorizontalPaths: true,
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
      'depthPasses': depthPasses,
      'edgeThreshold': edgeThreshold,
      'simplificationEpsilon': simplificationEpsilon,
      'useConvexHull': useConvexHull,
      'blurRadius': blurRadius,
      'smoothingWindowSize': smoothingWindowSize,
      'minSlabSize': minSlabSize,
      'gapAllowedMin': gapAllowedMin,
      'gapAllowedMax': gapAllowedMax,
      'continueSearchDistance': continueSearchDistance,
      'contourPostProcessPoints': contourPostProcessPoints,
      'forceHorizontalPaths': forceHorizontalPaths,
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
      depthPasses: json['depthPasses'] ?? 1,
      edgeThreshold: json['edgeThreshold'] ?? defaultEdgeThreshold,
      simplificationEpsilon: json['simplificationEpsilon'] ?? defaultSimplificationEpsilon,
      useConvexHull: json['useConvexHull'] ?? defaultUseConvexHull,
      blurRadius: json['blurRadius'] ?? defaultBlurRadius,
      smoothingWindowSize: json['smoothingWindowSize'] ?? defaultSmoothingWindowSize,
      minSlabSize: json['minSlabSize'] ?? minSlabSizeDefault,
      gapAllowedMin: json['gapAllowedMin'] ?? gapAllowedMinDefault,
      gapAllowedMax: json['gapAllowedMax'] ?? gapAllowedMaxDefault,
      continueSearchDistance: json['continueSearchDistance'] ?? continueSearchDistanceDefault,
      contourPostProcessPoints: json['contourPostProcessPoints'] ?? defaultContourPostProcessPoints,
      forceHorizontalPaths: json['forceHorizontalPaths'] ?? true,
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