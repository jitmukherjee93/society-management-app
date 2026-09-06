import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Helper to pick files safely with try/catch.
Future<PlatformFile?> pickFile({
  List<String> extensions = const ['pdf', 'png', 'jpg', 'jpeg', 'csv', 'xlsx', 'xls'],
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

/// Helper to upload a file to Firebase Storage safely using raw bytes.
Future<String?> uploadFile(PlatformFile file, String storagePath) async {
  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Selected file "${file.name}" is empty.');
    }

    final ext = file.name.toLowerCase();
    String contentType = 'application/octet-stream';
    if (ext.endsWith('.pdf')) {
      contentType = 'application/pdf';
    } else if (ext.endsWith('.png')) {
      contentType = 'image/png';
    } else if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
      contentType = 'image/jpeg';
    } else if (ext.endsWith('.csv')) {
      contentType = 'text/csv';
    } else if (ext.endsWith('.xlsx')) {
      contentType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    } else if (ext.endsWith('.xls')) {
      contentType = 'application/vnd.ms-excel';
    }

    final ref = FirebaseStorage.instance.ref(storagePath);
    final uploadTask = await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return await uploadTask.ref.getDownloadURL();
  } catch (e) {
    debugPrint('Storage upload error ($storagePath): $e');
    rethrow;
  }
}

