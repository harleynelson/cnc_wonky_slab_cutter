
// Utility class for handling metric and imperial unit conversions

/// Utility for converting between metric and imperial units
class UnitsConverter {
  /// Convert millimeters to inches
  static double mmToInches(double mm) {
    return mm / 25.4;
  }
  
  /// Convert inches to millimeters
  static double inchesToMm(double inches) {
    return inches * 25.4;
  }
  
  /// Format a distance value for display based on unit system
  static String formatDistance(double value, bool isMetric) {
    if (isMetric) {
      return '${value.toStringAsFixed(2)} mm';
    } else {
      return '${mmToInches(value).toStringAsFixed(3)} in';
    }
  }
  
  /// Format feed rate for display based on unit system
  static String formatFeedRate(double value, bool isMetric) {
    if (isMetric) {
      return '${value.toStringAsFixed(0)} mm/min';
    } else {
      return '${mmToInches(value).toStringAsFixed(1)} in/min';
    }
  }
  
  /// Format area for display based on unit system
  static String formatArea(double valueMmSq, bool isMetric) {
    if (isMetric) {
      if (valueMmSq >= 1000000) {
        return '${(valueMmSq / 1000000).toStringAsFixed(2)} m²';
      } else if (valueMmSq >= 10000) {
        return '${(valueMmSq / 10000).toStringAsFixed(2)} dm²';
      } else {
        return '${valueMmSq.toStringAsFixed(2)} mm²';
      }
    } else {
      // Convert mm² to in²
      final valueInSq = valueMmSq / (25.4 * 25.4);
      
      if (valueInSq >= 144) {
        // Convert to ft²
        return '${(valueInSq / 144).toStringAsFixed(2)} ft²';
      } else {
        return '${valueInSq.toStringAsFixed(2)} in²';
      }
    }
  }
  
  /// Convert a value based on the current unit system
  static double convertValue(double value, bool fromMetric, bool toMetric) {
    if (fromMetric == toMetric) {
      return value; // No conversion needed
    }
    
    if (fromMetric) {
      return mmToInches(value); // Convert from mm to inches
    } else {
      return inchesToMm(value); // Convert from inches to mm
    }
  }
}