import 'package:flutter/foundation.dart';

void downloadBytes(List<int> bytes, String fileName, {String mimeType = 'application/octet-stream'}) {
  debugPrint('downloadBytes: ($fileName) invoked on non-web platform with ${bytes.length} bytes.');
}

