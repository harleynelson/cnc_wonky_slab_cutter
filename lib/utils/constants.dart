/// App-wide constants

// App Info
const String appName = "CNC Slab Scanner";
const String appVersion = "1.0.0";

// File Names
const String settingsFileName = "settings.json";
const String gcodeTempFileName = "slab_surfacing.gcode";
const String processedImageFileName = "processed_image.png";

// Default Settings
const double defaultCncWidth = 800.0;
const double defaultCncHeight = 800.0;
const double defaultMarkerDistance = 300.0;
const double defaultToolDiameter = 25.4;
const double defaultStepover = 20.0;
const double defaultSafetyHeight = 10.0;
const double defaultFeedRate = 1000.0;
const double defaultPlungeRate = 500.0;
const double defaultCuttingDepth = 0.0;

// UI Constants
const double appBarHeight = 56.0;
const double bottomNavBarHeight = 56.0;
const double buttonHeight = 48.0;
const double padding = 16.0;
const double smallPadding = 8.0;
const double largePadding = 24.0;
const double borderRadius = 8.0;
const double cardElevation = 2.0;

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

// Processing Constants
const int defaultThreshold = 128;
const int edgeDetectionThreshold = 50;
const int blurRadius = 2;

// G-code Constants
const String gcodeHeader = "; G-code generated for CNC slab surfacing";
const String gcodeFooter = "; End of G-code";