import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/document_quality_service.dart';
import '../theme/app_colors.dart';
import '../utils/storage_utils.dart';

/// Modal dialog presented to users when an uploaded document fails readability/blur check.
/// Allows viewing the blurry preview and selecting a clearer document immediately.
class DocumentReuploadDialog extends StatefulWidget {
  final Uint8List failedBytes;
  final String fileName;
  final String failureReason;
  final List<String> allowedExtensions;

  const DocumentReuploadDialog({
    super.key,
    required this.failedBytes,
    required this.fileName,
    required this.failureReason,
    this.allowedExtensions = const ['pdf', 'png', 'jpg', 'jpeg'],
  });

  /// Shows the dialog and returns the validated, readable PlatformFile, or null if cancelled.
  static Future<PlatformFile?> show({
    required BuildContext context,
    required Uint8List failedBytes,
    required String fileName,
    required String failureReason,
    List<String> allowedExtensions = const ['pdf', 'png', 'jpg', 'jpeg'],
  }) {
    return showDialog<PlatformFile>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DocumentReuploadDialog(
        failedBytes: failedBytes,
        fileName: fileName,
        failureReason: failureReason,
        allowedExtensions: allowedExtensions,
      ),
    );
  }

  @override
  State<DocumentReuploadDialog> createState() => _DocumentReuploadDialogState();
}

class _DocumentReuploadDialogState extends State<DocumentReuploadDialog> {
  bool _isRechecking = false;
  late Uint8List _currentBytes;
  late String _currentFileName;
  late String _currentReason;

  @override
  void initState() {
    super.initState();
    _currentBytes = widget.failedBytes;
    _currentFileName = widget.fileName;
    _currentReason = widget.failureReason;
  }

  Future<void> _pickAnotherFile() async {
    setState(() => _isRechecking = true);
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.allowedExtensions,
      );

      if (res.isNotEmpty) {
        final newFile = res.first;
        final newBytes = await newFile.readAsBytes();

        if (newBytes.isEmpty) {
          if (mounted) {
            setState(() {
              _currentReason = 'The selected file is empty. Please pick a valid file.';
              _isRechecking = false;
            });
          }
          return;
        }

        // Run readability check on new file
        final evaluation = await DocumentQualityService.evaluateAndOptimize(
          bytes: newBytes,
          fileName: newFile.name,
        );

        if (evaluation.isReadable && evaluation.optimizedBytes != null) {
          final optimizedFile = BytesPlatformFile(
            name: evaluation.optimizedFileName ?? newFile.name,
            bytes: evaluation.optimizedBytes!,
          );

          if (mounted) {
            Navigator.pop(context, optimizedFile);
          }
          return;
        } else {
          if (mounted) {
            setState(() {
              _currentBytes = newBytes;
              _currentFileName = newFile.name;
              _currentReason = evaluation.rejectionReason ?? 'Document is still too blurry. Please try again.';
              _isRechecking = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentReason = 'Error checking file: $e';
          _isRechecking = false;
        });
      }
    } finally {
      if (mounted && _isRechecking) {
        setState(() => _isRechecking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isImage = _currentFileName.toLowerCase().endsWith('.jpg') ||
        _currentFileName.toLowerCase().endsWith('.jpeg') ||
        _currentFileName.toLowerCase().endsWith('.png') ||
        _currentFileName.toLowerCase().endsWith('.webp');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.sizeOf(context).width.clamp(0.0, 520.0),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.errorSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.blur_on_rounded, color: AppColors.error, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Document Unreadable / Blurry',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.slate900),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Please upload a clear, legible copy to proceed.',
                        style: TextStyle(fontSize: 12, color: AppColors.slate500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Flexible Content Area
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Preview Container
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200, width: 1.5),
                      ),
                      child: Column(
                        children: [
                          if (isImage) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200),
                                child: Image.memory(
                                  _currentBytes,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 60, color: Colors.grey),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else ...[
                            const Icon(Icons.description_outlined, size: 64, color: AppColors.error),
                            const SizedBox(height: 8),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'BLURRY / ILLEGIBLE',
                                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _currentFileName,
                                  style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Specific Error Reason
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _currentReason,
                              style: const TextStyle(fontSize: 12, color: AppColors.error, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Guidelines for clean upload
                    const Text(
                      'Guidelines for a clear document copy:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.slate800),
                    ),
                    const SizedBox(height: 8),
                    _buildTipRow(Icons.wb_sunny_outlined, 'Ensure good lighting with no glare or harsh shadows'),
                    _buildTipRow(Icons.camera_alt_outlined, 'Hold your phone camera steady and tap to focus on text'),
                    _buildTipRow(Icons.zoom_in, 'Make sure all amounts, dates, and names are clearly readable'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isRechecking ? null : () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  ),
                  onPressed: _isRechecking ? null : _pickAnotherFile,
                  icon: _isRechecking
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.file_upload_outlined, size: 18),
                  label: Text(_isRechecking ? 'Checking Clarity...' : 'Re-upload Document'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTipRow(IconData icon, String tip) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tip,
              style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
            ),
          ),
        ],
      ),
    );
  }
}

