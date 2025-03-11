# CNC Slab Scanner

An app for generating optimized CNC toolpaths for surfacing irregularly shaped slabs of wood, stone, or other materials.

## Features

- Camera-based slab detection
- Marker reference system for accurate real-world measurements
- Automatic contour detection using computer vision
- Optimized toolpath generation
- G-code export for direct use with CNC machines
- Works on iOS, Android, and web platforms

## Project Structure

```
lib/
├── main.dart                   # App entry point
├── models/
│   └── settings_model.dart     # App configuration and settings
├── screens/
│   ├── camera_screen.dart      # Camera capture interface
│   ├── file_picker_screen.dart # Image selection screen
│   ├── home_page.dart          # Main navigation screen
│   ├── preview_screen.dart     # Image preview and processing
│   └── settings_screen.dart    # Settings configuration
├── services/
│   ├── gcode/
│   │   ├── gcode_generator.dart    # G-code creation
│   │   └── machine_coordinates.dart # Coordinate system handling
│   └── image_processing/
│       ├── image_utils.dart        # Image manipulation utilities
│       ├── marker_detector.dart    # Reference marker detection
│       ├── slab_contour_detector.dart # Slab outline detection
│       ├── slab_contour_result.dart   # Detection result structure
│       └── slab_detector.dart      # Main detection orchestration
├── utils/
│   ├── constants.dart          # App-wide constants
│   ├── file_utils.dart         # File handling utilities
│   └── permissions_utils.dart  # Permission management
└── widgets/
    ├── camera_overlay.dart     # Camera guide overlay
    └── settings_fields.dart    # Settings form fields
```

// Organization structure for image processing utilities
1. BaseImageUtils.dart
   - Core utility functions common to all operations
   - Image format conversion, loading, saving
   - Simple pixel operations

2. ColorUtils.dart
   - Color space conversions (RGB, HSV, Lab)
   - Color manipulation functions
   - Histogram calculation and operations

3. FilterUtils.dart
   - Blur operations (Gaussian, Box, Median)
   - Sharpening filters
   - Noise reduction
   - Edge detection filters

4. MorphologyUtils.dart
   - Binary morphology operations (erosion, dilation)
   - Opening, closing operations
   - Advanced morphological transforms

5. ThresholdUtils.dart
   - Global thresholding
   - Adaptive thresholding
   - Automatic threshold calculation (Otsu, etc)

6. ContourUtils.dart
   - Contour extraction
   - Contour simplification
   - Contour analysis (area, perimeter, etc)

7. DrawingUtils.dart
   - Drawing functions for visualization
   - Text rendering
   - Shape drawing (lines, circles, etc)

8. GeometryUtils.dart
   - Point and vector operations
   - Geometric algorithms (convex hull, etc)
   - Coordinate transforms

9. EnhancementUtils.dart
   - Histogram equalization
   - Contrast enhancement
   - Brightness adjustment

10. AnalysisUtils.dart
    - Component analysis
    - Feature detection
    - Blob analysis

## Setup and Installation

1. Install Flutter (v3.7.0 or higher)
2. Clone this repository
3. Run `flutter pub get` to install dependencies
4. Connect a device or start an emulator
5. Run `flutter run` to start the app

## Usage

1. Start the app and grant required permissions
2. Place three reference markers on your workspace:
   - Origin marker (top left)
   - X-axis marker (top right)
   - Scale marker (bottom left)
3. Place your slab between the markers
4. Capture an image using the camera or select a file
5. Review the detected contour and toolpath
6. Export or share the generated G-code

## Dependencies

- `camera: ^0.11.1` - Camera access and photo capture
- `path_provider: ^2.0.11` - File system access
- `permission_handler: ^11.4.0` - Permission management
- `image: ^4.5.3` - Image processing
- `shared_preferences: ^2.0.15` - Settings storage
- `share_plus: ^10.1.4` - File sharing

## Known Issues

- The web version has limited functionality due to browser restrictions
- Large images (>10MB) may cause performance issues on older devices
- Camera calibration is currently simplified and may need manual adjustment

## To-Do

- [ ] Add machine learning-based slab edge detection
- [ ] Implement adaptive toolpath generation based on material properties
- [ ] Add support for external Bluetooth/USB cameras
- [ ] Implement cloud backup for settings and G-code files
- [ ] Add support for multiple cutting depths and 3D surface mapping
- [ ] Create a material library for optimized cutting parameters
- [ ] Implement augmented reality preview of the toolpath
- [ ] Add support for directly sending G-code to compatible CNC machines
- [ ] Create user-editable contour adjustments
- [ ] Add support for multiple languages
- [ ] Implement unit tests for core detection algorithms
- [ ] Create CI/CD pipeline for automated testing
- [ ] Add analytics for usage patterns (opt-in)
- [ ] Create a marketplace for sharing cutting strategies

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- The Flutter team for the amazing framework
- The `image` package maintainers for the image processing tools
- The open-source CNC community for inspiration and feedback