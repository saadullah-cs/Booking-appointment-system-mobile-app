import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Professional Image Service for extreme compression
/// Handles AI Posture Scanning image optimization to save Storage costs.
class ImageService {
  /// Compresses the given [sourceFile] by ~80% (quality 65, JPEG)
  /// Returns the compressed [File] and deletes the heavy raw source file.
  static Future<File?> compressPostureImage(File sourceFile) async {
    try {
      final String originalPath = sourceFile.path;
      final String targetPath = originalPath.replaceFirst(
        RegExp(r'\.(jpg|jpeg|png|heic)$', caseSensitive: false),
        '_compressed.jpg',
      );

      // Perform compression
      // Quality 65 provides significant space savings with minimal visual loss for AI analysis
      final XFile? compressedXFile =
          await FlutterImageCompress.compressAndGetFile(
            originalPath,
            targetPath,
            quality: 65,
            format: CompressFormat.jpeg,
          );

      if (compressedXFile == null) return null;

      final File compressedFile = File(compressedXFile.path);

      if (await sourceFile.exists()) {
        await sourceFile.delete();
        if (kDebugMode) {
          debugPrint('ImageService: Raw file deleted. Space saved.');
        }
      }

      return compressedFile;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ImageService: Compression failed: $e');
      }
      return null;
    }
  }
}
