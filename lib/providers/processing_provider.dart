// lib/providers/processing_provider.dart
// Provider to manage processing state across the app

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/processing/processing_flow_manager.dart';
import '../models/settings_model.dart';

class ProcessingProvider extends ChangeNotifier {
  ProcessingFlowManager? _flowManager;
  
  // Getter for current flow manager
  ProcessingFlowManager? get flowManager => _flowManager;
  
  // Create a new flow manager with the given settings
  void createFlowManager(SettingsModel settings) {
    _flowManager = ProcessingFlowManager(settings: settings);
    notifyListeners();
  }
  
  // Reset current flow manager
  void resetFlowManager() {
    if (_flowManager != null) {
      _flowManager!.reset();
      notifyListeners();
    }
  }
  
  // Clear current flow manager
  void clearFlowManager() {
    _flowManager = null;
    notifyListeners();
  }
}