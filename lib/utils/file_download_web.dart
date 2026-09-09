// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void downloadBytes(List<int> bytes, String fileName, {String mimeType = 'application/octet-stream'}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

