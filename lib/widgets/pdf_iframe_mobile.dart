import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

Widget buildPdfIframe(String url) {
  return _MobilePdfPreview(url: url);
}

class _MobilePdfPreview extends StatefulWidget {
  final String url;
  const _MobilePdfPreview({required this.url});

  @override
  State<_MobilePdfPreview> createState() => _MobilePdfPreviewState();
}

class _MobilePdfPreviewState extends State<_MobilePdfPreview> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Using Google Docs Viewer to render PDF in mobile WebView
    final googleDocsViewerUrl =
        'https://docs.google.com/gview?embedded=true&url=${Uri.encodeComponent(widget.url)}';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(googleDocsViewerUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}