import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Helper to pick files safely with try/catch.
Future<PlatformFile?> pickFile({
  List<String> extensions = const ['pdf', 'png', 'jpg', 'jpeg'],
}) async {
  try {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (res.isNotEmpty) {
      return res.first;
    }
  } catch (e) {
    debugPrint('File picker error: $e');
  }
  return null;
}

/// Helper to upload a file to Firebase Storage safely using base64 encoding
/// (avoids dart2js Int64 serialization bug on Flutter Web).
Future<String?> uploadFile(PlatformFile file, String storagePath) async {
  try {
    final ext = file.name.toLowerCase();
    final contentType = ext.endsWith('.pdf')
        ? 'application/pdf'
        : ext.endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';

    final bytes = await file.readAsBytes();
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putString(
      base64Encode(bytes),
      format: PutStringFormat.base64,
      metadata: SettableMetadata(contentType: contentType),
    );
    return await ref.getDownloadURL();
  } catch (e) {
    debugPrint('Storage upload error ($storagePath): $e');
    rethrow;
  }
}

