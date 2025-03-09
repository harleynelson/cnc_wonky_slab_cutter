import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

class FileUtils {
  /// Get a temporary file with the given name
  static Future<File> getTempFile(String fileName) async {
    final tempDir = await getTemporaryDirectory();
    return File(path.join(tempDir.path, fileName));
  }

  /// Get an application document file with the given name
  static Future<File> getDocumentFile(String fileName) async {
    final docDir = await getApplicationDocumentsDirectory();
    return File(path.join(docDir.path, fileName));
  }

  /// Save string content to a file
  static Future<File> saveStringToFile(String content, String fileName) async {
    final file = await getDocumentFile(fileName);
    return file.writeAsString(content);
  }

  /// Save bytes to a file
  static Future<File> saveBytesToFile(List<int> bytes, String fileName) async {
    final file = await getDocumentFile(fileName);
    return file.writeAsBytes(bytes);
  }

  /// Share a file with other apps
  static Future<void> shareFile(File file, {String? text}) async {
    await Share.shareXFiles([XFile(file.path)], text: text);
  }

  /// Delete a file if it exists
  static Future<void> deleteFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// List files in application documents directory
  static Future<List<FileSystemEntity>> listDocumentFiles() async {
    final docDir = await getApplicationDocumentsDirectory();
    return docDir.listSync();
  }

  /// Get files with a specific extension
  static Future<List<File>> getFilesByExtension(String extension) async {
    final docDir = await getApplicationDocumentsDirectory();
    final entities = docDir.listSync();
    
    return entities
        .whereType<File>()
        .where((file) => path.extension(file.path) == extension)
        .toList();
  }
}