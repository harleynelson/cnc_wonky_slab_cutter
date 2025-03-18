# CNC Slab Scanner

An app for generating optimized CNC toolpaths for surfacing irregularly shaped slabs of wood, stone, or other materials.

## Features

- Camera-based slab detection
- Marker reference system for accurate real-world measurements
- Automatic contour detection using computer vision
- Interactive seed-point selection for improved edge detection
- Optimized toolpath generation with customizable parameters
- G-code export for direct use with CNC machines
- Works on iOS, Android, and web platforms
- Support for both horizontal and vertical toolpaths
- Customizable safety margin around detected contours

## Workflow

1. **Capture Image**: Position three markers around your slab (Origin, X-axis, and Scale/Y-axis) and take a photo using the app's camera or select an existing image.

2. **Marker Detection**: The app automatically identifies the three reference markers that define the coordinate system.

3. **Contour Detection**: Tap on the slab to set a seed point for edge detection. The app uses advanced computer vision to find the slab's outline.

4. **G-code Generation**: Configure toolpath parameters (cutting depth, stepover, feed rate, etc.) and generate optimized G-code.

5. **Visualization**: Preview the generated toolpath to ensure accuracy before exporting.

6. **Export**: Save or share the G-code file for use with your CNC machine.

## Project Structure

```
lib/
├── main.dart                   # App entry point
├── models/
│   └── settings_model.dart     # App configuration and settings
├── providers/
│   └── processing_provider.dart # State management for processing flow
├── screens/
│   ├── camera_screen_with_overlay.dart  # Camera interface with marker guides
│   ├── combined_detector_screen.dart    # Marker and contour detection
│   ├── file_picker_screen.dart          # Image selection screen
│   ├── gcode_generator_screen.dart      # G-code parameter configuration 
│   ├── gcode_visualization_screen.dart  # Toolpath preview
│   ├── home_page.dart                   # Main navigation screen
│   ├── image_selection_screen.dart      # Image capture/selection
│   └── settings_screen.dart             # Settings configuration
├── services/
│   ├── gcode/
│   │   ├── gcode_generator.dart         # G-code creation
│   │   └── gcode_parser.dart            # G-code parsing for visualization
│   ├── image_processing/
│   │   ├── contour_algorithms/          # Edge detection algorithms
│   │   ├── marker_detector.dart         # Reference marker detection
│   │   ├── slab_contour_detector.dart   # Slab outline detection
│   │   └── slab_contour_result.dart     # Detection result structure
│   └── processing/
│       └── processing_flow_manager.dart  # Orchestrates the entire detection process
├── utils/
│   ├── general/
│   │   ├── constants.dart                # App-wide constants
│   │   ├── error_utils.dart              # Error handling utilities
│   │   ├── file_utils.dart               # File handling utilities
│   │   ├── machine_coordinates.dart      # Coordinate transformation
│   │   └── permissions_utils.dart        # Permission management
│   └── image_processing/                 # Image processing utilities
│       ├── base_image_utils.dart
│       ├── color_utils.dart
│       ├── contour_detection_utils.dart
│       ├── drawing_utils.dart
│       ├── filter_utils.dart
│       ├── geometry_utils.dart
│       ├── image_utils.dart
│       └── threshold_utils.dart
└── widgets/
    ├── camera_overlay.dart              # Camera guide overlay
    ├── contour_overlay.dart             # Contour visualization
    ├── marker_overlay.dart              # Marker visualization
    ├── manual_contour_dialog.dart       # Manual contour prompt
    └── settings_fields.dart             # Settings form fields
```

## Image Processing Pipeline

1. **Camera Calibration**: Uses three reference markers to establish a real-world coordinate system.

2. **Edge Detection**: Employs adaptive thresholding and Sobel edge detection to find the slab boundaries.

3. **Contour Extraction**: Interactive seed-point selection with ray casting and advanced gap-filling algorithms.

4. **Contour Refinement**: Applies smoothing and simplification while preserving corners.

5. **Coordinate Transformation**: Converts pixel coordinates to machine coordinates for accurate CNC operation.

## G-code Generation

1. **Boundary Calculation**: Determines the slab's outer boundary with optional safety margin.

2. **Path Planning**: Creates optimized parallel paths (horizontal or vertical) for efficient machining.

3. **Multi-pass Support**: Generates multiple depth passes for thick materials.

4. **G-code Formatting**: Outputs standard G-code with proper headers, safety moves, and spindle controls.

## Setup and Installation

1. Install Flutter (v3.7.0 or higher)
2. Clone this repository
3. Run `flutter pub get` to install dependencies
4. Connect a device or start an emulator
5. Run `flutter run` to start the app

## Usage

1. Start the app and grant required permissions
2. Place three reference markers on your workspace:
   - Origin marker (bottom left) - Red
   - X-axis marker (bottom right) - Green
   - Scale/Y-axis marker (top left) - Blue
3. Place your slab between the markers
4. Capture an image using the camera or select a file
5. The app will detect the reference markers
6. Tap on the slab to select a seed point for contour detection
7. Adjust detection parameters if needed
8. Review the detected contour and configure toolpath settings
9. Generate and visualize the G-code
10. Export or share the generated G-code file

## Dependencies

- `camera: ^0.11.1` - Camera access and photo capture
- `image: ^4.5.3` - Image processing
- `path_provider: ^2.0.11` - File system access
- `permission_handler: ^11.4.0` - Permission management
- `provider: ^6.0.5` - State management
- `shared_preferences: ^2.0.15` - Settings storage
- `share_plus: ^10.1.4` - File sharing
- `file_picker: ^5.2.10` - File selection

## Known Issues

- The web version has limited functionality due to browser restrictions
- Large images (>10MB) may cause performance issues on older devices
- Camera calibration is currently simplified and may need manual adjustment
- Edge detection can struggle with low-contrast materials

## To-Do

- [ ] Add machine learning-based slab edge detection
- [ ] Implement adaptive toolpath generation based on material properties
- [ ] Create a material library for optimized cutting parameters
- [ ] Create user-editable contour adjustments
- [ ] Add support for multiple languages
- [ ] Add metric/imperial unit system toggle

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

- Gürbüz Kaan Akkaya for writing up a simplified polygon buffering implementation
   https://medium.com/@gurbuzkaanakkaya/polygon-buffering-algorithm-generating-buffer-points-228ed062fdf9
   https://github.com/gurbuzkaanakkaya/Buffer-and-Path-Planning
- Timothy Malche for Edge Detection in Image Processing: An Introduction
   https://blog.roboflow.com/edge-detection/#canny-edge-detection
   