import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';

/// Utility class for error handling, logging, and user-friendly error presentation
class ErrorUtils {
  // Singleton instance
  static final ErrorUtils _instance = ErrorUtils._internal();
  factory ErrorUtils() => _instance;
  ErrorUtils._internal();
  
  // Error log history
  final List<LogEntry> _errorLog = [];
  
  // Get error log
  List<LogEntry> get errorLog => List.unmodifiable(_errorLog);
  
  /// Log an error with context information
  LogEntry logError(String message, dynamic error, {
    StackTrace? stackTrace,
    String? context,
    ErrorSeverity severity = ErrorSeverity.error,
  }) {
    final timestamp = DateTime.now();
    final entry = LogEntry(
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context,
      timestamp: timestamp,
      severity: severity,
    );
    
    _errorLog.add(entry);
    
    // Print to console for development debugging
    print('${severity.toString().split('.').last.toUpperCase()}: $message');
    if (error != null) print('Error: $error');
    if (stackTrace != null) print('Stack trace: $stackTrace');
    
    return entry;
  }
  
  /// Log a warning
  LogEntry logWarning(String message, {String? context}) {
    return logError(message, null, context: context, severity: ErrorSeverity.warning);
  }
  
  /// Log information
  LogEntry logInfo(String message, {String? context}) {
    return logError(message, null, context: context, severity: ErrorSeverity.info);
  }
  
  /// Create a user-friendly error message from an exception
  String getUserFriendlyMessage(dynamic error, {String? context}) {
    // Handle specific error types
    if (error is TimeoutException) {
      return "Operation timed out. This could be due to a large image or limited device resources.";
    } else if (error is OutOfMemoryError || error.toString().contains('OutOfMemory')) {
      return "Not enough memory. Try with a smaller image or close other apps.";
    } else if (error is FileSystemException) {
      return "File system error: ${error.message}";
    } else if (error is FormatException) {
      return "Format error: The file may be corrupted or in an unsupported format.";
    } else if (error is PlatformException) {
      return "Platform error: ${error.message}";
    }
    
    // For unknown errors, provide a general message with the context
    if (context != null) {
      return "Error during $context. Please try again or use a different image.";
    } else {
      return "An unexpected error occurred. Please try again.";
    }
  }
  
}

/// Severity levels for error logging
enum ErrorSeverity {
  info,
  warning,
  error,
  critical
}

/// Log entry for error tracking
class LogEntry {
  final String message;
  final dynamic error;
  final StackTrace? stackTrace;
  final String? context;
  final DateTime timestamp;
  final ErrorSeverity severity;
  
  LogEntry({
    required this.message,
    required this.timestamp,
    this.error,
    this.stackTrace,
    this.context,
    this.severity = ErrorSeverity.error,
  });
  
  @override
  String toString() {
    return '[$severity] $timestamp - $message ${context != null ? '($context)' : ''}';
  }
}