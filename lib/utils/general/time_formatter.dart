// lib/utils/general/time_formatter.dart
// Utility for formatting time durations in minutes:seconds format

/// Utility class for formatting time values
class TimeFormatter {
  /// Format minutes as "X min Y sec"
  /// 
  /// Takes a double value in minutes and formats it as "X min Y sec"
  /// Examples:
  ///   1.5 -> "1 min 30 sec"
  ///   0.25 -> "0 min 15 sec"
  ///   3.0 -> "3 min 0 sec"
  static String formatMinutesAndSeconds(double minutes) {
    if (minutes <= 0) return "0 min 0 sec";
    
    // Split into minutes and seconds
    final int mins = minutes.floor();
    final int secs = ((minutes - mins) * 60).round();
    
    // Handle case where seconds rounds to 60
    if (secs == 60) {
      return "${mins + 1} min 0 sec";
    } else {
      return "$mins min $secs sec";
    }
  }
  
  /// Format minutes as "Xh Ym Zs" for longer durations
  /// 
  /// Takes a double value in minutes and formats it as hours, minutes, seconds
  /// Examples:
  ///   90.5 -> "1h 30m 30s"
  ///   0.25 -> "0m 15s"
  ///   3.0 -> "3m 0s"
  static String formatHoursMinutesSeconds(double minutes) {
    if (minutes <= 0) return "0m 0s";
    
    // Calculate hours, minutes and seconds
    int totalSeconds = (minutes * 60).round();
    final int hours = totalSeconds ~/ 3600;
    totalSeconds %= 3600;
    final int mins = totalSeconds ~/ 60;
    final int secs = totalSeconds % 60;
    
    // Format based on duration
    if (hours > 0) {
      return "${hours}h ${mins}m ${secs}s";
    } else {
      return "${mins}m ${secs}s";
    }
  }
  
  /// Format minutes as a compact string
  ///
  /// Takes a double value in minutes and formats it compactly
  /// Examples:
  ///   90.5 -> "1:30:30"
  ///   0.25 -> "0:15"
  ///   3.0 -> "3:00"
  static String formatCompact(double minutes) {
    if (minutes <= 0) return "0:00";
    
    // Calculate hours, minutes and seconds
    int totalSeconds = (minutes * 60).round();
    final int hours = totalSeconds ~/ 3600;
    totalSeconds %= 3600;
    final int mins = totalSeconds ~/ 60;
    final int secs = totalSeconds % 60;
    
    // Format with leading zeros for seconds
    final String secStr = secs.toString().padLeft(2, '0');
    
    // Include hours only if non-zero
    if (hours > 0) {
      final String minStr = mins.toString().padLeft(2, '0');
      return "$hours:$minStr:$secStr";
    } else {
      return "$mins:$secStr";
    }
  }
}