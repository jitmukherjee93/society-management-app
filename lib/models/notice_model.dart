import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum NoticeCategory {
  general('General Notice', Icons.campaign_rounded, Color(0xFF3F51B5), Color(0xFFE8EAF6)),
  urgent('Urgent / Alert', Icons.warning_amber_rounded, Color(0xFFD32F2F), Color(0xFFFFEBEE)),
  maintenance('Maintenance & Utilities', Icons.build_circle_outlined, Color(0xFFE65100), Color(0xFFFFF3E0)),
  meeting('Meeting & AGM', Icons.groups_rounded, Color(0xFF6A1B9A), Color(0xFFF3E5F5)),
  event('Festivals & Events', Icons.celebration_rounded, Color(0xFF00897B), Color(0xFFE0F2F1)),
  security('Security & Rules', Icons.shield_outlined, Color(0xFF455A64), Color(0xFFECEFF1));

  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;

  const NoticeCategory(this.label, this.icon, this.color, this.backgroundColor);

  static NoticeCategory fromString(String? val) {
    if (val == null) return NoticeCategory.general;
    return NoticeCategory.values.firstWhere(
      (c) => c.name.toLowerCase() == val.toLowerCase() || c.label.toLowerCase() == val.toLowerCase(),
      orElse: () => NoticeCategory.general,
    );
  }
}

enum NoticePriority {
  low('Low', Color(0xFF757575)),
  medium('Medium', Color(0xFF1976D2)),
  high('High', Color(0xFFE65100)),
  urgent('Critical / Urgent', Color(0xFFD32F2F));

  final String label;
  final Color color;

  const NoticePriority(this.label, this.color);

  static NoticePriority fromString(String? val) {
    if (val == null) return NoticePriority.medium;
    return NoticePriority.values.firstWhere(
      (p) => p.name.toLowerCase() == val.toLowerCase() || p.label.toLowerCase() == val.toLowerCase(),
      orElse: () => NoticePriority.medium,
    );
  }
}

class NoticeAttachment {
  final String name;
  final String url;
  final String fileType; // 'pdf', 'image', 'document', 'other'
  final int? sizeBytes;
  final DateTime? uploadedAt;

  NoticeAttachment({
    required this.name,
    required this.url,
    required this.fileType,
    this.sizeBytes,
    this.uploadedAt,
  });

  bool get isImage {
    if (fileType == 'image') return true;
    if (fileType == 'pdf' || fileType == 'document') return false;
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  bool get isPdf {
    if (fileType == 'pdf') return true;
    if (fileType == 'image') return false;
    return name.toLowerCase().endsWith('.pdf');
  }

  String get formattedSize {
    if (sizeBytes == null || sizeBytes == 0) return '';
    if (sizeBytes! < 1024) return '$sizeBytes B';
    if (sizeBytes! < 1024 * 1024) return '${(sizeBytes! / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'url': url,
      'fileType': fileType,
      'sizeBytes': sizeBytes,
      'uploadedAt': uploadedAt != null ? Timestamp.fromDate(uploadedAt!) : FieldValue.serverTimestamp(),
    };
  }

  factory NoticeAttachment.fromMap(Map<String, dynamic> map) {
    DateTime? dt;
    if (map['uploadedAt'] is Timestamp) {
      dt = (map['uploadedAt'] as Timestamp).toDate();
    }
    return NoticeAttachment(
      name: map['name'] ?? 'attachment',
      url: map['url'] ?? '',
      fileType: map['fileType'] ?? 'document',
      sizeBytes: map['sizeBytes'] is int ? map['sizeBytes'] : (map['sizeBytes'] as num?)?.toInt(),
      uploadedAt: dt,
    );
  }
}

class NoticeModel {
  final String id;
  final String title;
  final String content;
  final NoticeCategory category;
  final NoticePriority priority;
  final bool isPinned;
  final String authorName;
  final String authorRole;
  final DateTime createdAt;
  final DateTime? validUntil;
  final List<NoticeAttachment> attachments;
  final String targetAudience; // 'All Residents', 'Owners Only', 'Tenants Only'

  NoticeModel({
    required this.id,
    required this.title,
    required this.content,
    this.category = NoticeCategory.general,
    this.priority = NoticePriority.medium,
    this.isPinned = false,
    this.authorName = 'Admin',
    this.authorRole = 'RWA Management',
    required this.createdAt,
    this.validUntil,
    this.attachments = const [],
    this.targetAudience = 'All Residents',
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'message': content, // backward compatibility with previous 'message' field
      'content': content,
      'category': category.name,
      'priority': priority.name,
      'isPinned': isPinned,
      'authorName': authorName,
      'authorRole': authorRole,
      'createdAt': Timestamp.fromDate(createdAt),
      'validUntil': validUntil != null ? Timestamp.fromDate(validUntil!) : null,
      'attachments': attachments.map((a) => a.toMap()).toList(),
      'targetAudience': targetAudience,
    };
  }

  factory NoticeModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    DateTime created = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      created = (data['createdAt'] as Timestamp).toDate();
    }

    DateTime? valid;
    if (data['validUntil'] is Timestamp) {
      valid = (data['validUntil'] as Timestamp).toDate();
    }

    List<NoticeAttachment> attList = [];
    if (data['attachments'] is List) {
      attList = (data['attachments'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => NoticeAttachment.fromMap(m))
          .toList();
    }

    // Support both 'content' and legacy 'message'
    final bodyContent = (data['content'] as String?) ?? (data['message'] as String?) ?? '';

    return NoticeModel(
      id: doc.id,
      title: data['title'] ?? '',
      content: bodyContent,
      category: NoticeCategory.fromString(data['category']),
      priority: NoticePriority.fromString(data['priority']),
      isPinned: data['isPinned'] ?? false,
      authorName: data['authorName'] ?? 'Admin',
      authorRole: data['authorRole'] ?? 'RWA Management',
      createdAt: created,
      validUntil: valid,
      attachments: attList,
      targetAudience: data['targetAudience'] ?? 'All Residents',
    );
  }

  bool get isExpired => validUntil != null && DateTime.now().isAfter(validUntil!);

  String get timeAgo {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
  }

  NoticeModel copyWith({
    String? id,
    String? title,
    String? content,
    NoticeCategory? category,
    NoticePriority? priority,
    bool? isPinned,
    String? authorName,
    String? authorRole,
    DateTime? createdAt,
    DateTime? validUntil,
    List<NoticeAttachment>? attachments,
    String? targetAudience,
  }) {
    return NoticeModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      isPinned: isPinned ?? this.isPinned,
      authorName: authorName ?? this.authorName,
      authorRole: authorRole ?? this.authorRole,
      createdAt: createdAt ?? this.createdAt,
      validUntil: validUntil ?? this.validUntil,
      attachments: attachments ?? this.attachments,
      targetAudience: targetAudience ?? this.targetAudience,
    );
  }
}
