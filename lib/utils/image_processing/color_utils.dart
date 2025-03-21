
import 'package:image/image.dart' as img;

/// Utilities for color processing and manipulation
class ColorUtils {

  /// Common colors for convenience
  static img.Color get colorRed => img.ColorRgba8(255, 0, 0, 255);
  static img.Color get colorGreen => img.ColorRgba8(0, 255, 0, 255);
  static img.Color get colorBlue => img.ColorRgba8(0, 0, 255, 255);
  static img.Color get colorYellow => img.ColorRgba8(255, 255, 0, 255);
  static img.Color get colorCyan => img.ColorRgba8(0, 255, 255, 255);
  static img.Color get colorMagenta => img.ColorRgba8(255, 0, 255, 255);
  static img.Color get colorWhite => img.ColorRgba8(255, 255, 255, 255);
  static img.Color get colorBlack => img.ColorRgba8(0, 0, 0, 255);
  static img.Color get colorGray => img.ColorRgba8(128, 128, 128, 255);
  
  /// Create a color with custom RGB values
  static img.Color getRgbColor(int r, int g, int b, {int a = 255}) {
    return img.ColorRgba8(
      r.clamp(0, 255), 
      g.clamp(0, 255), 
      b.clamp(0, 255), 
      a.clamp(0, 255)
    );
  }

}