import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'pdf_iframe.dart';

/// Reusable dialog to preview PDFs, images, or documents across Admin & Resident dashboards.
void showDocumentPreviewDialog(BuildContext context, String url, String fileName) {
  final lowerName = fileName.toLowerCase();
  final isPdf = lowerName.endsWith('.pdf') || url.toLowerCase().contains('.pdf');
  final isImage = lowerName.endsWith('.png') ||
      lowerName.endsWith('.jpg') ||
      lowerName.endsWith('.jpeg') ||
      url.toLowerCase().contains('.png') ||
      url.toLowerCase().contains('.jpg') ||
      url.toLowerCase().contains('.jpeg');

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              fileName.isNotEmpty ? 'Document: $fileName' : 'Document Preview',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.sizeOf(ctx).width.clamp(0.0, 700.0),
        height: (MediaQuery.sizeOf(ctx).height * 0.65).clamp(280.0, 520.0),
        child: isPdf
            ? buildPdfIframe(url)
            : isImage
                ? InteractiveViewer(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Text('Failed to render image. Please download to view.'),
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.description, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text('File: $fileName',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                          'Preview only available for PDF and images. Please download to view.'),
                    ],
                  ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: Text(MediaQuery.sizeOf(ctx).width < 500 ? 'Download' : 'Download / Open in New Tab'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      ],
    ),
  );
}

