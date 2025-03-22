# CNC Slab Scanner

An app for generating optimized CNC toolpaths for surfacing irregularly shaped slabs of wood, stone, or other materials.

## Features

- Camera-based slab detection
- Marker reference system for accurate real-world measurements
- Automatic contour detection using computer vision
- Manual contour drawing option when automatic detection is challenging
- Interactive seed-point selection for improved edge detection
- Optimized toolpath generation with customizable parameters
- G-code export for direct use with CNC machines
- Works on iOS, Android, and web platforms
- Support for both horizontal and vertical toolpaths
- Customizable safety margin around detected contours
- Multiple depth passes for thick materials
- Option to return to home position after completion

## Workflow

1. **Capture Image**: Position three markers around your slab (Origin, X-axis, and Scale/Y-axis) and take a photo using the app's camera or select an existing image.

2. **Marker Detection**: The app automatically identifies the three reference markers that define the coordinate system.

3. **Contour Detection**: Either tap on the slab to set a seed point for edge detection, or draw the contour manually. The app uses advanced computer vision to find the slab's outline when using automatic detection.

4. **G-code Generation**: Configure toolpath parameters (cutting depth, stepover, feed rate, etc.) and generate optimized G-code.

5. **Visualization**: Preview the generated toolpath to ensure accuracy before exporting.

6. **Export**: Save or share the G-code file for use with your CNC machine.

## Project Structure

```
lib/
├── main.dart                          # App entry point
├── detection/                         # Detection algorithms
│   ├── algorithms/                    # Contour detection algorithms
│   │   ├── contour_algorithm_interface.dart
│   │   ├── contour_algorithm_registry.dart
│   │   └── edge_contour_algorithm.dart
│   ├── marker_detector.dart           # Reference marker detection
│   ├── marker_selection_state.dart    # State management for marker selection
│   ├── slab_contour_detector.dart     # Slab outline detection
│   └── slab_contour_result.dart       # Detection result structure
├── flow_of_app/                       # Application flow management
│   ├── flow_manager.dart              # Manages the overall processing flow
│   ├── flow_provider.dart             # Provider for flow manager
│   └── processing_provider.dart       # State management for processing
├── screens/                           # UI screens
│   ├── camera_screen_with_overlay.dart  # Camera interface with marker guides
│   ├── combined_detector_screen.dart    # Marker and contour detection
│   ├── file_picker_screen.dart          # Image selection screen
│   ├── gcode_generator_screen.dart      # G-code parameter configuration 
│   ├── gcode_visualization_screen.dart  # Toolpath preview
│   ├── home_page.dart                   # Main navigation screen
│   ├── image_selection_screen.dart      # Image capture/selection
│   └── settings_screen.dart             # Settings configuration
├── utils/                             # Utility functions and helpers
│   ├── drawing/                       # Drawing utilities
│   │   ├── drawing_utils.dart           # Shape and line drawing
│   │   └── line_drawing_utils.dart      # Line drawing utilities
│   ├── general/                       # General utilities
│   │   ├── constants.dart               # App-wide constants
│   │   ├── error_utils.dart             # Error handling utilities
│   │   ├── file_utils.dart              # File handling utilities
│   │   ├── machine_coordinates.dart     # Coordinate transformation
│   │   ├── permissions_utils.dart       # Permission management
│   │   ├── settings_model.dart          # Settings model
│   │   ├── time_formatter.dart          # Time formatting utilities
│   │   └── units_converter.dart         # Unit conversion utilities
│   ├── gcode/                         # G-code utilities
│   │   ├── gcode_generator.dart         # G-code creation
│   │   └── gcode_parser.dart            # G-code parsing for visualization
│   ├── image_processing/              # Image processing utilities
│   │   ├── base_image_utils.dart        # Basic image operations
│   │   ├── color_utils.dart             # Color manipulation
│   │   ├── contour_detection_utils.dart # Contour detection
│   │   ├── filter_utils.dart            # Image filtering
│   │   ├── geometry_utils.dart          # Geometric operations
│   │   └── threshold_utils.dart         # Thresholding operations
│   └── toolpath/                      # Toolpath utilities
│       ├── contour_painter.dart         # Contour visualization
│       └── toolpath_painter.dart        # Toolpath visualization
└── widgets/                           # Reusable widgets
    ├── camera_overlay.dart            # Camera guide overlay
    ├── contour_overlay.dart           # Contour visualization
    ├── manual_contour_drawer.dart     # Manual contour drawing
    ├── manual_contour_dialog.dart     # Manual contour prompt
    ├── marker_overlay.dart            # Marker visualization
    ├── settings_fields.dart           # Settings form fields
    └── units_toggle.dart              # Unit system toggle
```

## Enhanced Features

### Manual Contour Drawing
When automatic edge detection is challenging (such as with low-contrast materials like wood on MDF), users can now draw the contour manually with an intuitive point-based drawing interface.

### Multiple Depth Passes
The app now supports configuring multiple depth passes for thick materials, automatically distributing the cutting depth across passes for optimal results.

### Margin Configuration
Users can add a customizable safety margin around the detected slab, ensuring complete coverage during machining.

### Path Direction Control
Choose between horizontal and vertical toolpaths based on your specific material and CNC requirements.

### Return to Home
Option to add a return to home position command at the end of the G-code, improving workflow efficiency.

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
   - Origin marker (bottom left)
   - X-axis marker (bottom right)
   - Y-axis marker (top left)
3. Place your slab between the markers
4. Capture an image using the camera or select a file
5. The app will detect the reference markers
6. Either tap on the slab to select a seed point for automatic contour detection, or draw the contour manually
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
- Camera calibration is currently simplified and may need manual adjustments
- Edge detection can struggle with low-contrast materials (especially wood on MDF spillboard)
- Manual contour drawing may require careful placement for best results

## To-Do

- [ ] Add machine learning-based slab edge detection
- [ ] Implement adaptive toolpath generation based on material properties
- [ ] Create a material library for optimized cutting parameters
- [ ] Add fully editable contour adjustments with drag handles
- [ ] Add support for multiple languages
- [ ] Add metric/imperial unit system toggle

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/feature`)
3. Commit your changes (`git commit -m 'Add some feature'`)
4. Push to the branch (`git push origin feature/feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Gürbüz Kaan Akkaya for writing up a simplified polygon buffering implementation
   https://medium.com/@gurbuzkaanakkaya/polygon-buffering-algorithm-generating-buffer-points-228ed062fdf9
   https://github.com/gurbuzkaanakkaya/Buffer-and-Path-Planning
- Timothy Malche for Edge Detection in Image Processing: An Introduction
   https://blog.roboflow.com/edge-detection/#canny-edge-detection