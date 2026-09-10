import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/notice_model.dart';
import 'package:society_management/widgets/notices/notice_card_widget.dart';
import 'package:society_management/widgets/notices/two_column_notice_list.dart';

void main() {
  group('NoticeCardWidget & TwoColumnNoticeList Tests', () {
    final baseNotice = NoticeModel(
      id: 'notice_1',
      title: 'Water Supply Maintenance',
      content: 'Water supply will be temporarily shut down tomorrow between 10 AM and 2 PM.',
      category: NoticeCategory.maintenance,
      priority: NoticePriority.medium,
      isPinned: false,
      authorName: 'Estate Manager',
      authorRole: 'Admin',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

    testWidgets('Renders notice card with title, author, and category chip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NoticeCardWidget(notice: baseNotice),
            ),
          ),
        ),
      );

      expect(find.text('Water Supply Maintenance'), findsOneWidget);
      expect(find.text('Maintenance & Utilities'), findsOneWidget);
      expect(find.textContaining('Estate Manager'), findsOneWidget);
      expect(find.text('Pinned'), findsNothing);
      expect(find.text('Expired'), findsNothing);
    });

    testWidgets('Renders Pinned badge and Urgent priority badge', (tester) async {
      final pinnedUrgentNotice = baseNotice.copyWith(
        isPinned: true,
        priority: NoticePriority.urgent,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NoticeCardWidget(notice: pinnedUrgentNotice),
            ),
          ),
        ),
      );

      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('Critical / Urgent'), findsOneWidget);
    });

    testWidgets('Renders Expired badge when validUntil is in the past', (tester) async {
      final expiredNotice = baseNotice.copyWith(
        validUntil: DateTime.now().subtract(const Duration(days: 1)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NoticeCardWidget(notice: expiredNotice),
            ),
          ),
        ),
      );

      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('TwoColumnNoticeList renders in single column and two column modes', (tester) async {
      final notices = [
        baseNotice.copyWith(id: 'n1', title: 'Notice 1'),
        baseNotice.copyWith(id: 'n2', title: 'Notice 2'),
        baseNotice.copyWith(id: 'n3', title: 'Notice 3'),
      ];

      // Single column
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TwoColumnNoticeList(
                notices: notices,
                isTwoColumn: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Notice 1'), findsOneWidget);
      expect(find.text('Notice 2'), findsOneWidget);
      expect(find.text('Notice 3'), findsOneWidget);
      expect(find.byType(Row), findsWidgets);

      // Two column
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TwoColumnNoticeList(
                notices: notices,
                isTwoColumn: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Notice 1'), findsOneWidget);
      expect(find.text('Notice 2'), findsOneWidget);
      expect(find.text('Notice 3'), findsOneWidget);
    });
  });
}
