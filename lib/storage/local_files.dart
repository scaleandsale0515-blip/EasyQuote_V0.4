import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../utils/ids.dart';

/// Copies a picked image into this app's private local documents folder
/// (still entirely on-device — just outside Hive, since Hive isn't meant
/// for large binary blobs) and returns the saved file's path.
class LocalFiles {
  static Future<String> saveImage(File source, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/easyquote_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    final ext = source.path.split('.').last;
    final fileName = '${prefix}_${generateId()}.$ext';
    final dest = File('${imagesDir.path}/$fileName');
    await source.copy(dest.path);
    return dest.path;
  }

  /// Reads an image file on disk and returns it as a base64 string —
  /// used when building a backup, so the actual image bytes travel with
  /// the backup file instead of just a path that's meaningless on another
  /// device.
  static Future<String?> readImageAsBase64(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Writes a base64-encoded image back to a fresh file in this app's
  /// private local documents folder — used when restoring a backup so
  /// logo/signature/stamp images become real files on the new device
  /// again, with a fresh local path.
  static Future<String?> writeImageFromBase64(String base64Str, String prefix, String ext) async {
    try {
      final bytes = base64Decode(base64Str);
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${dir.path}/easyquote_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      final fileName = '${prefix}_${generateId()}.$ext';
      final dest = File('${imagesDir.path}/$fileName');
      await dest.writeAsBytes(bytes);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> exportsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${dir.path}/easyquote_exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    return exportsDir;
  }
}
