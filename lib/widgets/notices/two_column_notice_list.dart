import 'package:flutter/material.dart';
import '../../models/notice_model.dart';
import 'notice_card_widget.dart';

/// Reusable widget for responsive two-column or single-column notice lists.
class TwoColumnNoticeList extends StatelessWidget {
  final List<NoticeModel> notices;
  final bool isTwoColumn;
  final bool isAdmin;
  final VoidCallback? onRefresh;

  const TwoColumnNoticeList({
    super.key,
    required this.notices,
    this.isTwoColumn = false,
    this.isAdmin = false,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) {
      return const SizedBox.shrink();
    }

    if (isTwoColumn) {
      final col1 = <NoticeModel>[];
      final col2 = <NoticeModel>[];
      for (int i = 0; i < notices.length; i++) {
        if (i % 2 == 0) {
          col1.add(notices[i]);
        } else {
          col2.add(notices[i]);
        }
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: col1.map((notice) => NoticeCardWidget(
                key: ValueKey(notice.id),
                notice: notice,
                isAdmin: isAdmin,
                onRefresh: onRefresh,
              )).toList(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: col2.map((notice) => NoticeCardWidget(
                key: ValueKey(notice.id),
                notice: notice,
                isAdmin: isAdmin,
                onRefresh: onRefresh,
              )).toList(),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: notices.map((notice) => NoticeCardWidget(
        key: ValueKey(notice.id),
        notice: notice,
        isAdmin: isAdmin,
        onRefresh: onRefresh,
      )).toList(),
    );
  }
}
