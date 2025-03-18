// lib/utils/general/constants.dart
// App-wide constants

// App Info
const String appName = "CNC Slab Scanner";
const String appVersion = "1.1.0";

// File Names
const String settingsFileName = "settings.json";
const String gcodeTempFileName = "slab_surfacing.gcode";
const String processedImageFileName = "processed_image.png";

// Default Settings
const double defaultCncWidth = 800.0;
const double defaultCncHeight = 800.0;
const double defaultMarkerXDistance = 762.0;    // X-axis distance (horizontal)
const double defaultMarkerYDistance = 762.0;    // Y-axis distance (vertical)
const double defaultToolDiameter = 25.4;
const double defaultStepover = 20.0;
const double defaultSafetyHeight = 10.0;
const double defaultFeedRate = 1000.0;
const double defaultPlungeRate = 500.0;
const double defaultCuttingDepth = 0.0;
const int defaultSpindleSpeed = 18000;

// UI Constants
const double appBarHeight = 56.0;
const double bottomNavBarHeight = 56.0;
const double buttonHeight = 48.0;
const double padding = 16.0;
const double smallPadding = 8.0;
const double largePadding = 24.0;
const double borderRadius = 8.0;
const double cardElevation = 2.0;
const double statusBarHeight = 24.0; // Approximate
const double imageContainerMinHeight = 400.0; // Minimum height for image container

// Animation Durations
const Duration shortAnimationDuration = Duration(milliseconds: 200);
const Duration normalAnimationDuration = Duration(milliseconds: 300);
const Duration longAnimationDuration = Duration(milliseconds: 500);

// Camera Constants
const double cameraCrosshairSize = 20.0;
const double markerSize = 10.0;

// Marker Colors
const int markerOriginColorHex = 0xFFFF0000; // Red
const int markerXAxisColorHex = 0xFF00FF00; // Green
const int markerScaleColorHex = 0xFF0000FF; // Blue
const int markerTopRightColorHex = 0xFFFFFF00; // Yellow

// Processing Constants
const int defaultThreshold = 128;
const int edgeDetectionThreshold = 50;
const int blurRadius = 2;

// G-code Constants
const String gcodeHeader = "; G-code generated for CNC slab surfacing";
const String gcodeFooter = "; End of G-code";