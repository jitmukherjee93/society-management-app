import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/notice_model.dart';
import 'package:society_management/widgets/notices/notice_rich_formatter.dart';

void main() {
  group('Notice Model & Priority Tests', () {
    test('NoticeCategory fromString maps correctly and provides defaults', () {
      expect(NoticeCategory.fromString('urgent'), NoticeCategory.urgent);
      expect(NoticeCategory.fromString('maintenance'), NoticeCategory.maintenance);
      expect(NoticeCategory.fromString('Meeting & AGM'), NoticeCategory.meeting);
      expect(NoticeCategory.fromString(null), NoticeCategory.general);
      expect(NoticeCategory.fromString('unknown_category'), NoticeCategory.general);
    });

    test('NoticePriority fromString maps correctly and defaults to medium', () {
      expect(NoticePriority.fromString('low'), NoticePriority.low);
      expect(NoticePriority.fromString('urgent'), NoticePriority.urgent);
      expect(NoticePriority.fromString('Critical / Urgent'), NoticePriority.urgent);
      expect(NoticePriority.fromString(null), NoticePriority.medium);
    });

    test('NoticeAttachment formats file size properly', () {
      final smallAtt = NoticeAttachment(name: 'doc.pdf', url: 'https://...', fileType: 'pdf', sizeBytes: 500);
      expect(smallAtt.formattedSize, '500 B');

      final kbAtt = NoticeAttachment(name: 'photo.jpg', url: 'https://...', fileType: 'image', sizeBytes: 2048);
      expect(kbAtt.formattedSize, '2.0 KB');

      final mbAtt = NoticeAttachment(name: 'circular.pdf', url: 'https://...', fileType: 'pdf', sizeBytes: 5 * 1024 * 1024);
      expect(mbAtt.formattedSize, '5.0 MB');
    });
  });

  group('Notice Color Presets Tests', () {
    test('Parses hex colors and name colors correctly', () {
      expect(NoticeColorPresets.parseColor('red'), NoticeColorPresets.crimsonRed);
      expect(NoticeColorPresets.parseColor('blue'), NoticeColorPresets.sapphireBlue);
      expect(NoticeColorPresets.parseColor('green'), NoticeColorPresets.emeraldGreen);
      expect(NoticeColorPresets.parseColor('#D32F2F'), const Color(0xFFD32F2F));
      expect(NoticeColorPresets.parseColor('#1976D2'), const Color(0xFF1976D2));
      expect(NoticeColorPresets.parseColor('invalid'), isNull);
    });
  });

  group('NoticeRichText Widget Rendering Tests', () {
    testWidgets('Renders plain notice text without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NoticeRichText(content: 'Standard notice content with no markup.'),
          ),
        ),
      );

      expect(find.byType(NoticeRichText), findsOneWidget);
    });

    testWidgets('Renders headings, bold, colored text and callout boxes', (tester) async {
      const richContent = '''
# Society Annual General Meeting
## Important Agenda
**Dear Residents**, please note the following:
• The meeting starts at 10:00 AM.
• [color=#D32F2F]Attendance is mandatory[/color] for all flat owners.
> [!ALERT] Lift maintenance will be active during this period.
---
Thank you.
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NoticeRichText(content: richContent),
            ),
          ),
        ),
      );

      expect(find.byType(NoticeRichText), findsOneWidget);
      expect(find.text('Society Annual General Meeting'), findsOneWidget);
      expect(find.text('Important Agenda'), findsOneWidget);
      expect(find.text('Important Alert'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('Renders multi-line color blocks across line breaks without displaying raw tags', (tester) async {
      const userMultiLineColor = '''
[color=#D32F2F]We are notifying you about the tank cleaning activity
to be held from 7th to 11th September 2026. Below are the list of the dates
to keep eye on:[/color]
• 7th September: B Block All 4 Tanks
• 8th September: A Block All 4 tanks
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NoticeRichText(content: userMultiLineColor),
            ),
          ),
        ),
      );

      expect(find.byType(NoticeRichText), findsOneWidget);
      expect(find.textContaining('[color='), findsNothing);
      expect(find.textContaining('[/color]'), findsNothing);
    });

    testWidgets('Renders inline documents directly within text stream', (tester) async {
      const inlineDocContent = '''
Please review the attached document below:

[doc:https://example.com/test.pdf|AGM_Minutes_2026.pdf]

Let us know your feedback.
''';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NoticeRichText(content: inlineDocContent),
            ),
          ),
        ),
      );

      expect(find.byType(NoticeRichText), findsOneWidget);
      expect(find.text('AGM_Minutes_2026.pdf'), findsOneWidget);
    });
  });
}
