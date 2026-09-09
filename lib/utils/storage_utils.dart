import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../services/document_quality_service.dart';
import '../widgets/document_reupload_dialog.dart';

/// In-memory implementation of [PlatformFile] for manipulated / optimized byte buffers.
final class BytesPlatformFile extends PlatformFile {
  @override
  final String name;
  final Uint8List bytes;

  BytesPlatformFile({
    required this.name,
    required this.bytes,
  });

  @override
  Uri get uri => Uri.dataFromBytes(bytes);

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

/// Helper to pick files safely with automatic readability verification,
/// blur detection, user-facing re-upload prompting, and document image downscaling/optimization.
Future<PlatformFile?> pickFile({
  BuildContext? context,
  List<String> extensions = const ['pdf', 'png', 'jpg', 'jpeg', 'csv', 'xlsx', 'xls'],
  bool performReadabilityCheck = true,
}) async {
  try {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (res.isEmpty) {
      return null;
    }

    final rawFile = res.first;
    final bytes = await rawFile.readAsBytes();

    if (bytes.isEmpty || !performReadabilityCheck) {
      return rawFile;
    }

    // Perform quality, readability, blur, and contrast analysis
    final result = await DocumentQualityService.evaluateAndOptimize(
      bytes: bytes,
      fileName: rawFile.name,
    );

    // If document is blurry or unreadable, present the re-upload dialog to the user
    if (!result.isReadable) {
      if (context != null && context.mounted) {
        return await DocumentReuploadDialog.show(
          context: context,
          failedBytes: bytes,
          fileName: rawFile.name,
          failureReason: result.rejectionReason ?? 'Document is blurry or unreadable.',
          allowedExtensions: extensions,
        );
      }
      return null;
    }

    // Return the readable and shrunk/optimized file payload
    if (result.optimizedBytes != null) {
      return BytesPlatformFile(
        name: result.optimizedFileName ?? rawFile.name,
        bytes: result.optimizedBytes!,
      );
    }

    return rawFile;
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
    } else if (ext.endsWith('.webp')) {
      contentType = 'image/webp';
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
