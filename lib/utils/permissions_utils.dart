import 'package:permission_handler/permission_handler.dart';

class PermissionsUtils {
  /// Request camera permission
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Check if camera permission is granted
  static Future<bool> isCameraPermissionGranted() async {
    return await Permission.camera.isGranted;
  }

  /// Request storage permission
  static Future<bool> requestStoragePermission() async {
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// Check if storage permission is granted
  static Future<bool> isStoragePermissionGranted() async {
    return await Permission.storage.isGranted;
  }

  /// Request all required permissions for the app
  static Future<Map<Permission, PermissionStatus>> requestAllPermissions() async {
    return await [
      Permission.camera,
      Permission.storage,
    ].request();
  }

  /// Check if all permissions needed by the app are granted
  static Future<bool> areAllPermissionsGranted() async {
    final cameraGranted = await isCameraPermissionGranted();
    final storageGranted = await isStoragePermissionGranted();
    
    return cameraGranted && storageGranted;
  }

  /// Opens app settings page
  static Future<bool> openAppSettings() async {
    return await openAppSettings();
  }
}