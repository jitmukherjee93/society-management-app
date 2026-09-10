import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants/firestore_collections.dart';
import '../../models/notice_model.dart';
import '../../utils/notice_utils.dart';
import 'notice_editor_dialog.dart';
import 'notice_rich_formatter.dart';

class NoticeCardWidget extends StatelessWidget {
  final NoticeModel notice;
  final bool isAdmin;
  final VoidCallback? onRefresh;

  const NoticeCardWidget({
    super.key,
    required this.notice,
    this.isAdmin = false,
    this.onRefresh,
  });

  void _togglePin(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.announcements)
          .doc(notice.id)
          .update({'isPinned': !notice.isPinned});
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating pin status: $e')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Notice?'),
          ],
        ),
        content: Text('Are you sure you want to delete "${notice.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFirestore.instance
                    .collection(FirestoreCollections.announcements)
                    .doc(notice.id)
                    .delete();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notice deleted successfully.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting notice: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = notice.category;
    final isPinned = notice.isPinned;
    final isUrgent = notice.priority == NoticePriority.urgent;

    return Card(
      elevation: isPinned ? 1.5 : 0.5,
      shadowColor: isPinned ? Colors.amber.withValues(alpha: 0.2) : Colors.black12,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isUrgent
              ? Colors.red.shade300
              : (isPinned ? Colors.amber.shade300 : const Color(0xFFE2E8F0)),
          width: isUrgent ? 1.4 : 1.0,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: isPinned
              ? const LinearGradient(
                  colors: [Color(0xFFFFFBEB), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Meta Bar: Badges on Left, Author/Time/Actions on Right
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Category Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: cat.backgroundColor,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: cat.color.withValues(alpha: 0.25), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cat.icon, size: 12, color: cat.color),
                            const SizedBox(width: 4),
                            Text(
                              cat.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: cat.color,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Priority Badge (if not normal)
                      if (notice.priority != NoticePriority.low && notice.priority != NoticePriority.medium)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: notice.priority.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            notice.priority.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: notice.priority.color,
                            ),
                          ),
                        ),

                      // Pinned Indicator
                      if (isPinned)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.shade400, width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.push_pin, size: 11, color: Colors.deepOrange),
                              SizedBox(width: 3),
                              Text(
                                'Pinned',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Expired Indicator
                      if (notice.isExpired)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey.shade400, width: 0.8),
                          ),
                          child: Text(
                            'Expired',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Author & relative timestamp + Admin actions
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${notice.authorName} • ${notice.timeAgo}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 2),
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF64748B)),
                            padding: EdgeInsets.zero,
                            onSelected: (val) {
                              if (val == 'pin') {
                                _togglePin(context);
                              } else if (val == 'edit') {
                                NoticeEditorDialog.show(context, notice: notice);
                              } else if (val == 'delete') {
                                _confirmDelete(context);
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'pin',
                                child: Row(
                                  children: [
                                    Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin, size: 16, color: Colors.amber.shade800),
                                    const SizedBox(width: 8),
                                    Text(isPinned ? 'Unpin from Top' : 'Pin to Top', style: const TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 16, color: Colors.blue),
                                    const SizedBox(width: 8),
                                    Text('Edit Notice', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Text('Delete Notice', style: TextStyle(color: Colors.red, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Notice Title
            Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 4),
              child: Text(
                notice.title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
            ),

            // Rich Notice Body
            NoticeRichText(content: notice.content),

            // Attachments Section
            if (notice.attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              const Divider(height: 1, thickness: 0.8, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 6),

              // Image Thumbnails Grid
              if (notice.attachments.any((a) => a.isImage))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: notice.attachments.where((a) => a.isImage).map((imgAtt) {
                      return InkWell(
                        onTap: () => NoticeImageLightbox.show(context, imgAtt.url, caption: imgAtt.name),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                imgAtt.url,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Center(
                                  child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 18),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  color: Colors.black54,
                                  padding: const EdgeInsets.all(1),
                                  child: const Text(
                                    'View',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 8.5, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // Document & PDF Chips
              if (notice.attachments.any((a) => !a.isImage))
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: notice.attachments.where((a) => !a.isImage).map((docAtt) {
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFFF8FAFC),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      avatar: Icon(
                        docAtt.isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
                        size: 14,
                        color: docAtt.isPdf ? Colors.red : Colors.blueGrey,
                      ),
                      label: Text(
                        '${docAtt.name}${docAtt.formattedSize.isNotEmpty ? " (${docAtt.formattedSize})" : ""}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                      ),
                      onPressed: () => UrlUtils.openUrl(context, docAtt.url),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

