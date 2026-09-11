import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// On Android/iOS: saves [bytes] to the app temp directory and opens
/// the system share sheet so the user can save to Files / Drive / WhatsApp etc.
void downloadBytes(List<int> bytes, String fileName, {String mimeType = 'application/octet-stream'}) async {
  try {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    final params = ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: fileName)],
      subject: fileName,
    );
    await SharePlus.instance.share(params);
  } catch (e) {
    debugPrint('downloadBytes mobile error: $e');
  }
}
