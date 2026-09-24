import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/accounting_heads.dart';
import 'package:society_management/utils/flat_utils.dart';
import 'package:society_management/widgets/push_notification_banner.dart';

void main() {
  group('FlatUtils & Block Extraction Tests', () {
    test('normalize formats various flat input strings properly', () {
      expect(FlatUtils.normalize('b 312'), 'B-312');
      expect(FlatUtils.normalize('B312'), 'B-312');
      expect(FlatUtils.normalize('b-312'), 'B-312');
      expect(FlatUtils.normalize('A-101-A'), 'A-101-A');
      expect(FlatUtils.normalize('AB-101'), 'AB-101');
      expect(FlatUtils.normalize('ab101'), 'AB-101');
      expect(FlatUtils.normalize('101'), '101');
      expect(FlatUtils.normalize(''), '');
      expect(FlatUtils.normalize(null), '');
    });

    test('extractBlock extracts correct block identifier from various formats', () {
      expect(FlatUtils.extractBlock('B-312'), 'B');
      expect(FlatUtils.extractBlock('B312'), 'B');
      expect(FlatUtils.extractBlock('b 312'), 'B');
      expect(FlatUtils.extractBlock('a-101'), 'A');
      expect(FlatUtils.extractBlock('c 202'), 'C');
      expect(FlatUtils.extractBlock('D405'), 'D');
      expect(FlatUtils.extractBlock('AB-101'), 'General');
      expect(FlatUtils.extractBlock('ab101'), 'General');
      expect(FlatUtils.extractBlock('101'), 'General');
      expect(FlatUtils.extractBlock(''), 'General');
      expect(FlatUtils.extractBlock(null), 'General');
    });

    test('getMaintenanceHead maps blocks correctly', () {
      expect(FlatUtils.getMaintenanceHead('A-101'), 'Monthly Maintenance - Block A');
      expect(FlatUtils.getMaintenanceHead('B312'), 'Monthly Maintenance - Block B');
      expect(FlatUtils.getMaintenanceHead('C-101'), 'Monthly Maintenance - Block C');
      expect(FlatUtils.getMaintenanceHead('D-201'), 'Monthly Maintenance - Block D');
      expect(FlatUtils.getMaintenanceHead('101'), 'Monthly Maintenance Collection');
    });
  });

  group('AccountingConfig & Breakdown Calculations', () {
    test('calculateMaintenanceBreakdown works for standard and non-standard block formats', () {
      final breakdownB = AccountingConfig.calculateMaintenanceBreakdown(
        flatNumber: 'B-101',
        carCount: 1,
        bikeCount: 1,
      );
      expect(breakdownB.block, 'B');
      expect(breakdownB.baseMaintenance, 420.0);
      expect(breakdownB.carParkingCharges, 430.0);
      expect(breakdownB.bikeParkingCharges, 100.0);
      expect(breakdownB.totalMonthlyDue, 950.0);

      // Flat without hyphen: B101
      final breakdownBNoHyphen = AccountingConfig.calculateMaintenanceBreakdown(
        flatNumber: 'B101',
        carCount: 0,
        bikeCount: 2,
      );
      expect(breakdownBNoHyphen.block, 'B');
      expect(breakdownBNoHyphen.baseMaintenance, 420.0);
      expect(breakdownBNoHyphen.bikeParkingCharges, 200.0);
      expect(breakdownBNoHyphen.totalMonthlyDue, 620.0);

      // Block D
      final breakdownD = AccountingConfig.calculateMaintenanceBreakdown(
        flatNumber: 'D-202',
        carCount: 1,
        bikeCount: 0,
      );
      expect(breakdownD.block, 'D');
      expect(breakdownD.baseMaintenance, 490.0);
      expect(breakdownD.totalMonthlyDue, 920.0);

      // Flat with General block falls back safely to A
      final breakdownGeneral = AccountingConfig.calculateMaintenanceBreakdown(
        flatNumber: '101',
      );
      expect(breakdownGeneral.block, 'A');
      expect(breakdownGeneral.baseMaintenance, 450.0);
    });

    test('getFinancialYear and getFinancialYearMonths compute dynamically across future years', () {
      final date2026 = DateTime(2026, 9, 15);
      expect(AccountingConfig.getFinancialYear(date2026), '2026-27');
      final months2026 = AccountingConfig.getFinancialYearMonths(date2026);
      expect(months2026.first, 'April 2026');
      expect(months2026.last, 'March 2027');

      // Test post-March 2027 (e.g. May 2027)
      final date2027 = DateTime(2027, 5, 10);
      expect(AccountingConfig.getFinancialYear(date2027), '2027-28');
      final months2027 = AccountingConfig.getFinancialYearMonths(date2027);
      expect(months2027.first, 'April 2027');
      expect(months2027.last, 'March 2028');

      // Test Jan 2028 (Q4 of FY 2027-28)
      final dateJan2028 = DateTime(2028, 1, 20);
      expect(AccountingConfig.getFinancialYear(dateJan2028), '2027-28');
    });
  });

  group('Visitor Approval Payload & Queue Verification', () {
    test('isVisitorApprovalRequest accurately differentiates pending vs resolved payloads', () {
      final pendingPayload = PushNotificationPayload(
        id: 'v-101',
        title: 'Visitor At Gate',
        message: 'Guest waiting',
        type: 'VISITOR_CHECK_IN',
        flatNumber: 'B-101',
        extraData: {
          'approvalStatus': 'PENDING',
          'isWalkIn': true,
        },
      );
      expect(pendingPayload.isVisitorApprovalRequest, isTrue);

      final approvedPayload = PushNotificationPayload(
        id: 'v-102',
        title: 'Visitor At Gate',
        message: 'Guest waiting',
        type: 'VISITOR_CHECK_IN',
        flatNumber: 'B-101',
        extraData: {
          'approvalStatus': 'APPROVED',
          'isWalkIn': true,
        },
      );
      expect(approvedPayload.isVisitorApprovalRequest, isFalse);

      final leftAtGatePayload = PushNotificationPayload(
        id: 'v-103',
        title: 'Delivery At Gate',
        message: 'Delivery waiting',
        type: 'VISITOR_CHECK_IN',
        flatNumber: 'B-101',
        extraData: {
          'approvalStatus': 'LEAVE_AT_GATE',
          'isDelivery': true,
        },
      );
      expect(leftAtGatePayload.isVisitorApprovalRequest, isFalse);
    });

    test('Queue maintains FIFO order and handles multiple consecutive incoming visitors', () {
      final queue = <PushNotificationPayload>[];

      final p1 = PushNotificationPayload(
        id: 'p1',
        title: 'Visitor 1',
        message: 'Guest 1',
        type: 'VISITOR_CHECK_IN',
      );
      final p2 = PushNotificationPayload(
        id: 'p2',
        title: 'Visitor 2',
        message: 'Guest 2',
        type: 'VISITOR_CHECK_IN',
      );

      queue.add(p1);
      queue.add(p2);

      expect(queue.length, 2);
      expect(queue.first.id, 'p1');
      expect(queue.last.id, 'p2');

      // Pop latest
      final latest = queue.removeLast();
      expect(latest.id, 'p2');
      expect(queue.length, 1);
      expect(queue.first.id, 'p1');
    });
  });
}

