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

  /// Request photo storage permission for SDK > 33
  static Future<bool> requestStoragePermission() async {
    // For Android SDK 33 and above, use Photos and Videos permission
    final status = await Permission.photos.request();
    return status.isGranted;
  }

  /// Check if photo storage permission is granted
  static Future<bool> isStoragePermissionGranted() async {
    return await Permission.photos.isGranted;
  }

  /// Request all required permissions for the app
  static Future<Map<Permission, PermissionStatus>> requestAllPermissions() async {
    return await [
      Permission.camera,
      Permission.photos,
    ].request();
  }

  /// Check if all permissions needed by the app are granted
  static Future<bool> areAllPermissionsGranted() async {
    final cameraGranted = await isCameraPermissionGranted();
    final photosGranted = await isStoragePermissionGranted();
   
    return cameraGranted && photosGranted;
  }

  /// Opens app settings page
  static Future<bool> openAppSettings() async {
    return await openAppSettings();
  }
}