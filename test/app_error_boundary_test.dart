import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/widgets/app_error_boundary.dart';

void main() {
  group('AppErrorFormatter Tests', () {
    test('sanitizes null error', () {
      expect(AppErrorFormatter.clean(null), contains('unexpected issue'));
    });

    test('strips Exception: and Error: prefixes', () {
      expect(AppErrorFormatter.clean(Exception('Flat already has maximum parking allocated')),
          'Flat already has maximum parking allocated');
      expect(AppErrorFormatter.clean('Error: Something went wrong'), 'Something went wrong');
    });

    test('formats email already in use errors into friendly message', () {
      expect(
        AppErrorFormatter.clean('[firebase_auth/email-already-in-use] The email address is already in use by another account.'),
        contains('already registered'),
      );
      expect(
        AppErrorFormatter.clean('User (d-206@ramkrishnapuram.com) already exists with a different password.'),
        contains('different password'),
      );
    });

    test('formats navigation/framework assertions into friendly message', () {
      expect(
        AppErrorFormatter.clean('Assertion failed: _dependents.isEmpty is not true'),
        contains('screen transition completed'),
      );
    });

    test('formats permission denied errors', () {
      expect(
        AppErrorFormatter.clean('[cloud_firestore/permission-denied] Missing or insufficient permissions.'),
        contains('Access denied'),
      );
    });
  });

  group('AppErrorWidget Tests', () {
    testWidgets('renders friendly UI and technical details toggle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorWidget(
              error: Exception('Test exception detail'),
              componentName: 'Member Registry',
              onRetry: () {},
            ),
          ),
        ),
      );

      expect(find.text('Unable to load Member Registry'), findsOneWidget);
      expect(find.text('Test exception detail'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('compact mode renders inline alert', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorWidget(
              error: 'Invalid flat format',
              isCompact: true,
            ),
          ),
        ),
      );

      expect(find.text('Invalid flat format'), findsOneWidget);
    });
  });
}

