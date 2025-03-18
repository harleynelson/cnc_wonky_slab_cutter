// lib/utils/general/constants.dart
// App-wide constants

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

// Animation Durations
const Duration shortAnimationDuration = Duration(milliseconds: 200);
const Duration normalAnimationDuration = Duration(milliseconds: 300);
const Duration longAnimationDuration = Duration(milliseconds: 500);

// Camera Constants
const double cameraCrosshairSize = 20.0;
const double markerSize = 10.0;
const double cameraBottomBarHeight = 100.0; // Camera control bar height
const double cameraStatusBarHeight = 100.0; // Status bar height for camera screens

// Marker Colors
const int markerOriginColorHex = 0xFFFF0000; // Red
const int markerXAxisColorHex = 0xFF00FF00; // Green
const int markerScaleColorHex = 0xFF0000FF; // Blue

// Marker Position Constants (relative to screen size)
const double markerOriginX = 0.2;   // Origin X position (bottom left)
const double markerOriginY = 0.8;   // Origin Y position
const double markerXAxisX = 0.8;    // X-Axis X position (bottom right)
const double markerXAxisY = 0.8;    // X-Axis Y position
const double markerScaleX = 0.2;    // Scale X position (top left)
const double markerScaleY = 0.2;    // Scale Y position
const double workAreaBorderPadding = 0.1; // Work area padding from screen edges

// Processing Constants
const int defaultThreshold = 128;
const int edgeDetectionThreshold = 50;
const int defaultBlurRadius = 3;
const int defaultSmoothingWindowSize = 5;
const int minSlabSizeDefault = 1000;
const int gapAllowedMinDefault = 5;
const int gapAllowedMaxDefault = 20;
const int continueSearchDistanceDefault = 30;
const double defaultEdgeThreshold = 65.0;
const double defaultSimplificationEpsilon = 5.0;
const bool defaultUseConvexHull = true;
const int defaultContourPostProcessPoints = 40; // Higher number = smoother contour

// Image Processing Constants
const int defaultMaxImageSize = 1200; // Maximum dimension for image processing
const int defaultProcessingTimeout = 10000; // Default timeout in milliseconds

// G-code Constants
const String gcodeHeader = "; G-code generated for CNC slab surfacing";
const String gcodeFooter = "; End of G-code";
const double defaultSlabMargin = 50.0; // Default margin for slab in mm
const double maxSlabMargin = 100.0; // Maximum margin for slabs

// Contour Display Constants
const double detectorScreenOverlayHeight = 438.0; // Specific height for marker overlay in detector screen
const double defaultContourStrokeWidth = 2.0;
const double contourPointRadius = 3.0;
const double contourGlowStrokeWidth = 6.0;
const double contourGlowBlurRadius = 3.0;
const double contourTextFontSize = 12.0;
const double contourBackgroundOpacity = 0.7;
const double contourCenterCrosshairSize = 5.0;

// Marker Overlay Constants
const double markerCircleRadius = 20.0;
const double markerInnerCircleRadius = 10.0;
const double markerLabelFontSize = 14.0;
const double markerLabelPadding = 10.0;
const double markerLabelXOffset = 20.0;
const double markerLabelYOffset = -7.0;
const double markerLineOpacity = 0.7;
const double markerLineStrokeWidth = 2.0;

// Seed Point Indicator Constants
const double seedPointIndicatorSize = 20.0;
const double seedPointIndicatorOpacity = 0.7;
const double seedPointIndicatorBorderWidth = 2.0;

// Button Width Constants
const double minButtonWidth = 100.0;