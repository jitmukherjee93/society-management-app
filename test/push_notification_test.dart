import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/widgets/push_notification_banner.dart';
import 'package:society_management/services/push_notification_manager.dart';

// ============================================================================
// PUSH NOTIFICATION SYSTEM UNIT & WIDGET TESTS
// ============================================================================
// Verifies:
// 1. Payload categorization (Emergency, Gate visitor actions, Payments, Parcels).
// 2. Heads-up push banner rendering and high-visibility styling.
// 3. Quick interactive actions (1-tap Approve & Deny for gate visitors).
// 4. Dismissal and banner body tap callbacks.
// ============================================================================

void main() {
  group('PushNotificationPayload Tests', () {
    test('Emergency payload identification', () {
      final payload = PushNotificationPayload(
        id: 'notif-1',
        title: '🚨 EMERGENCY ALERT: Fire',
        message: 'Fire reported at Main Gate by Guard John.',
        type: 'EMERGENCY',
      );

      expect(payload.isEmergency, isTrue);
      expect(payload.isVisitorApprovalRequest, isFalse);
      expect(payload.isPaymentOrBill, isFalse);
    });

    test('Visitor approval request payload identification', () {
      final payload = PushNotificationPayload(
        id: 'notif-2',
        title: 'Visitor At Gate: Blinkit Courier',
        message: 'Blinkit Courier (Ramesh) is at Security Gate.',
        type: 'VISITOR_CHECK_IN',
        extraData: {
          'approvalStatus': 'PENDING',
          'isWalkIn': true,
          'visitorName': 'Ramesh',
        },
      );

      expect(payload.isVisitorApprovalRequest, isTrue);
      expect(payload.isEmergency, isFalse);
    });

    test('Maintenance bill and payment approval identification', () {
      final billPayload = PushNotificationPayload(
        id: 'notif-3',
        title: 'Maintenance Bill Due: October 2026',
        message: 'Dear Resident (B-312), your bill for October 2026 is ₹420.',
        type: 'MAINTENANCE_DUE',
      );

      final paymentPayload = PushNotificationPayload(
        id: 'notif-4',
        title: 'Maintenance Payment Approved (INC-2627-10023)',
        message: 'Your payment of ₹420 has been verified.',
        type: 'MAINTENANCE_PAYMENT_APPROVED',
      );

      expect(billPayload.isPaymentOrBill, isTrue);
      expect(paymentPayload.isPaymentOrBill, isTrue);
    });

    test('Parcel notification identification', () {
      final payload = PushNotificationPayload(
        id: 'notif-5',
        title: 'Parcel Received at Gate',
        message: '1 package from Amazon received at Main Gate.',
        type: 'PARCEL_HELD',
      );

      expect(payload.isParcel, isTrue);
    });

    test('Complaint update notification identification', () {
      final payload = PushNotificationPayload(
        id: 'notif-6',
        title: '🛠️ Ticket Update: Pipe Leak',
        message: 'Your ticket has been marked as IN_PROGRESS.',
        type: 'COMPLAINT_UPDATE',
      );

      expect(payload.isComplaint, isTrue);
    });

    test('Visitor overstay notification identification', () {
      final payload = PushNotificationPayload(
        id: 'notif-7',
        title: 'OVERSTAY ALERT: Blinkit Courier (B-312)',
        message: 'Blinkit Courier has exceeded the maximum allowed stay time inside campus.',
        type: 'VISITOR_OVERSTAY',
        flatNumber: 'B-312',
        extraData: {
          'visitorName': 'Blinkit Courier',
          'durationStr': '35m',
        },
      );

      expect(payload.isOverstay, isTrue);
      expect(payload.isEmergency, isFalse);
      expect(payload.isVisitorApprovalRequest, isFalse);
    });
  });

  group('PushNotificationBanner Widget Tests', () {
    testWidgets('Renders push banner with clear title, message and tag', (tester) async {
      bool dismissed = false;
      bool tapped = false;

      final payload = PushNotificationPayload(
        id: 'notif-test-1',
        title: '✅ Payment Approved: October 2026',
        message: 'Your payment for October 2026 (Flat B-312) has been approved by Admin. Receipt #INC-2627-8899.',
        type: 'MAINTENANCE_PAYMENT_APPROVED',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PushNotificationBanner(
              payload: payload,
              onDismiss: () => dismissed = true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title, message, and tag are rendered
      expect(find.text('✅ Payment Approved: October 2026'), findsOneWidget);
      expect(
        find.text('Your payment for October 2026 (Flat B-312) has been approved by Admin. Receipt #INC-2627-8899.'),
        findsOneWidget,
      );
      expect(find.text('JUST NOW'), findsOneWidget);

      // Verify tapping banner body triggers onTap callback
      await tester.tap(find.text('✅ Payment Approved: October 2026'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);

      // Verify close button triggers dismissal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets('Renders 1-tap APPROVE and DENY action buttons for visitor check-in', (tester) async {
      bool approved = false;
      bool denied = false;

      final payload = PushNotificationPayload(
        id: 'notif-test-2',
        title: 'Visitor At Gate: [Swiggy] Suresh',
        message: '[Swiggy] Suresh (Food Delivery) has checked in at Security Gate.',
        type: 'VISITOR_CHECK_IN',
        extraData: {
          'approvalStatus': 'PENDING',
          'isWalkIn': true,
          'visitorName': 'Suresh',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PushNotificationBanner(
              payload: payload,
              onDismiss: () {},
              onApprove: () => approved = true,
              onDeny: () => denied = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify APPROVE and DENY buttons appear
      expect(find.text('APPROVE'), findsOneWidget);
      expect(find.text('DENY'), findsOneWidget);

      // Tap APPROVE
      await tester.tap(find.text('APPROVE'));
      await tester.pumpAndSettle();
      expect(approved, isTrue);

      // Tap DENY
      await tester.tap(find.text('DENY'));
      await tester.pumpAndSettle();
      expect(denied, isTrue);
    });

    testWidgets('Renders PushNotificationOverlay without crashing when activeNotification is null', (tester) async {
      PushNotificationManager.instance.activeNotification.value = null;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PushNotificationOverlay(
              child: Center(child: Text('Main App Content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Main App Content'), findsOneWidget);
      expect(find.byType(PushNotificationBanner), findsNothing);
    });

    testWidgets('PushNotificationOverlay banner tap invokes onNotificationClick delegate with payload and context', (tester) async {
      bool clicked = false;
      PushNotificationPayload? receivedPayload;

      final testPayload = PushNotificationPayload(
        id: 'notif-click-test',
        title: 'Visitor At Gate: Courier',
        message: 'Courier is at Security Gate.',
        type: 'VISITOR_CHECK_IN',
        extraData: {'visitorName': 'Courier'},
      );

      PushNotificationManager.instance.onNotificationClick = (context, payload) {
        clicked = true;
        receivedPayload = payload;
      };

      PushNotificationManager.instance.activeNotification.value = testPayload;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PushNotificationOverlay(
              child: Center(child: Text('Main App Content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PushNotificationBanner), findsOneWidget);

      // Tap on the banner body
      await tester.tap(find.text('Visitor At Gate: Courier'));
      await tester.pumpAndSettle();

      // Verify onNotificationClick was invoked with the exact payload
      expect(clicked, isTrue);
      expect(receivedPayload?.id, equals('notif-click-test'));

      // Clean up
      PushNotificationManager.instance.onNotificationClick = null;
      PushNotificationManager.instance.activeNotification.value = null;
    });

    test('isDelivery correctly differentiates Delivery vs Guest payload', () {
      final guestPayload = PushNotificationPayload(
        id: 'guest-1',
        title: 'Visitor At Gate: Rahul Sharma',
        message: 'Rahul Sharma (Guest / Personal) is at Security Gate.',
        type: 'VISITOR_CHECK_IN',
        extraData: {
          'purpose': 'Guest / Personal',
          'isWalkIn': true,
        },
      );

      final deliveryPayload = PushNotificationPayload(
        id: 'delivery-1',
        title: 'Delivery: Blinkit - Rohan',
        message: 'Blinkit executive Rohan is at Security Gate.',
        type: 'VISITOR_CHECK_IN',
        extraData: {
          'purpose': 'Delivery / Courier',
          'deliveryApp': 'Blinkit',
          'isDelivery': true,
          'isWalkIn': true,
        },
      );

      expect(guestPayload.isDelivery, isFalse);
      expect(guestPayload.deliveryCompany, isNull);

      expect(deliveryPayload.isDelivery, isTrue);
      expect(deliveryPayload.deliveryCompany, equals('Blinkit'));
    });

    testWidgets('PushNotificationBanner hides Leave At Gate button for Guests and shows it for Delivery', (tester) async {
      bool leaveAtGateCalled = false;

      // 1. Guest payload: Leave At Gate button must NOT be present
      final guestPayload = PushNotificationPayload(
        id: 'guest-notif',
        title: 'Visitor At Gate: Priya Verma',
        message: 'Priya Verma (Guest / Personal) is at Security Gate.',
        type: 'VISITOR_CHECK_IN',
        extraData: {
          'purpose': 'Guest / Personal',
          'approvalStatus': 'PENDING',
          'isWalkIn': true,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PushNotificationBanner(
              payload: guestPayload,
              onDismiss: () {},
              onApprove: () {},
              onLeaveAtGate: () => leaveAtGateCalled = true,
              onDeny: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('APPROVE'), findsOneWidget);
      expect(find.text('DENY'), findsOneWidget);
      expect(find.text('GATE'), findsNothing); // Must NOT show Leave at Gate for Guests!

      // 2. Delivery payload: Leave At Gate button MUST be present
      final deliveryPayload = PushNotificationPayload(
        id: 'delivery-notif',
        title: 'Delivery: Blinkit - Delivery Boy',
        message: 'Blinkit executive is at Security Gate.',
        type: 'VISITOR_CHECK_IN',
        extraData: {
          'purpose': 'Delivery / Courier',
          'deliveryApp': 'Blinkit',
          'isDelivery': true,
          'approvalStatus': 'PENDING',
          'isWalkIn': true,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PushNotificationBanner(
              payload: deliveryPayload,
              onDismiss: () {},
              onApprove: () {},
              onLeaveAtGate: () => leaveAtGateCalled = true,
              onDeny: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('APPROVE'), findsOneWidget);
      expect(find.text('DENY'), findsOneWidget);
      expect(find.text('GATE'), findsOneWidget); // Shown for delivery!
      expect(find.text('Blinkit'), findsOneWidget); // Company name badge shown!

      // Tap on GATE button
      await tester.tap(find.text('GATE'));
      await tester.pumpAndSettle();
      expect(leaveAtGateCalled, isTrue);
    });
  });
}

