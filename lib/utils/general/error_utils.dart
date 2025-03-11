import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:async';

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
  
  /// Create a technical error message with details for developers
  String getTechnicalErrorMessage(dynamic error, {StackTrace? stackTrace}) {
    final buffer = StringBuffer();
    
    buffer.writeln("Technical Error Details:");
    buffer.writeln("Error: ${error.toString()}");
    
    if (stackTrace != null) {
      buffer.writeln("\nStack Trace:");
      
      // Get the most relevant part of the stack trace (first 10 lines)
      final traceString = stackTrace.toString();
      final lines = traceString.split('\n');
      final relevantLines = lines.take(10).join('\n');
      
      buffer.writeln(relevantLines);
      
      if (lines.length > 10) {
        buffer.writeln("... (${lines.length - 10} more lines)");
      }
    }
    
    return buffer.toString();
  }
  
  /// Show error dialog to user with option to copy technical details
  Future<void> showErrorDialog(
    BuildContext buildContext,  // Renamed from context to buildContext
    String userMessage, 
    dynamic error, 
    {StackTrace? stackTrace, 
    String? context}) async {  // This is fine as an optional named parameter
   
    // Log the error - pass the String context, not the BuildContext
    logError(userMessage, error, stackTrace: stackTrace, context: context);
  
    
    // Generate technical details
    final technicalDetails = getTechnicalErrorMessage(error, stackTrace: stackTrace);
    
    return showDialog(
      context: buildContext,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Error'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(userMessage),
                SizedBox(height: 16),
                Text('Need help? Tap below to copy technical details for support.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: Text('Copy Details'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: technicalDetails));
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Technical details copied to clipboard')),
                );
              },
            ),
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }
  
  /// Export error logs to a file for debugging
  Future<File?> exportErrorLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = path.join(directory.path, 'error_log_$timestamp.txt');
      final file = File(filePath);
      
      final buffer = StringBuffer();
      buffer.writeln('Error Log Export');
      buffer.writeln('Generated: ${DateTime.now().toString()}');
      buffer.writeln('');
      
      for (final entry in _errorLog) {
        buffer.writeln('='.padRight(50, '='));
        buffer.writeln('${entry.severity.toString().split('.').last.toUpperCase()}: ${entry.message}');
        buffer.writeln('Timestamp: ${entry.timestamp}');
        
        if (entry.context != null) {
          buffer.writeln('Context: ${entry.context}');
        }
        
        if (entry.error != null) {
          buffer.writeln('Error: ${entry.error}');
        }
        
        if (entry.stackTrace != null) {
          buffer.writeln('Stack Trace:');
          buffer.writeln(entry.stackTrace);
        }
        
        buffer.writeln('');
      }
      
      await file.writeAsString(buffer.toString());
      return file;
    } catch (e) {
      print('Error exporting logs: $e');
      return null;
    }
  }
  
  /// Clear error logs
  void clearErrorLogs() {
    _errorLog.clear();
  }
  
  /// Handle common processing errors with retry options
  Future<T?> handleProcessingError<T>(
    BuildContext context,
    Future<T> Function() processFunction, {
    String operationName = 'processing',
    int maxRetries = 1,
    bool showDialog = true,
  }) async {
    int attempts = 0;
    
    while (attempts <= maxRetries) {
      try {
        return await processFunction();
      } catch (e, stackTrace) {
        attempts++;
        logError(
          'Error during $operationName (attempt $attempts/${maxRetries + 1})',
          e,
          stackTrace: stackTrace,
          context: operationName,
        );
        
        // If we've reached max retries, show error and return null
        if (attempts > maxRetries) {
          if (showDialog && context.mounted) {
            final userMessage = getUserFriendlyMessage(e, context: operationName);
            await showErrorDialog(context, userMessage, e, stackTrace: stackTrace);
          }
          return null;
        }
        
        // Otherwise, if we have retries left, continue the loop
      }
    }
    
    return null; // Should never reach here due to the return in the catch block
  }
  
  /// Create a categorized error report
  String createErrorReport(List<LogEntry> logs) {
    final buffer = StringBuffer();
    final categories = <ErrorSeverity, List<LogEntry>>{};
    
    // Categorize logs by severity
    for (final log in logs) {
      categories.putIfAbsent(log.severity, () => []).add(log);
    }
    
    // Add report header
    buffer.writeln('ERROR REPORT');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('Total Error Count: ${logs.length}');
    buffer.writeln('');
    
    // Add section for each severity level
    for (final severity in ErrorSeverity.values) {
      final logsInCategory = categories[severity] ?? [];
      buffer.writeln('${severity.toString().split('.').last.toUpperCase()} (${logsInCategory.length})');
      buffer.writeln('='.padRight(40, '='));
      
      if (logsInCategory.isEmpty) {
        buffer.writeln('No errors in this category.');
      } else {
        for (final log in logsInCategory) {
          buffer.writeln('${log.timestamp}: ${log.message}');
          if (log.context != null) {
            buffer.writeln('Context: ${log.context}');
          }
          buffer.writeln('');
        }
      }
      
      buffer.writeln('');
    }
    
    // Add most common errors summary
    buffer.writeln('MOST COMMON ERRORS');
    buffer.writeln('='.padRight(40, '='));
    
    final messageCounts = <String, int>{};
    for (final log in logs) {
      final message = log.message;
      messageCounts[message] = (messageCounts[message] ?? 0) + 1;
    }
    
    final sortedMessages = messageCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (int i = 0; i < math.min(5, sortedMessages.length); i++) {
      final entry = sortedMessages[i];
      buffer.writeln('${entry.value} occurrences: ${entry.key}');
    }
    
    return buffer.toString();
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