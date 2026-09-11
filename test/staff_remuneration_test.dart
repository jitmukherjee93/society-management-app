import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/accounting_heads.dart';
import 'package:society_management/services/staff_remuneration_service.dart';

void main() {
  group('Staff Remuneration Budget & Service Tests', () {
    test('Staff Remuneration positions match FY 2026-27 approved budget', () {
      final monthlyRates = AccountingConfig.staffRemunerationMonthly;
      expect(monthlyRates.length, 11);
      expect(monthlyRates['Electrician'], 5346.0);
      expect(monthlyRates['Guard 1'], 4472.0);
      expect(monthlyRates['Guard 2'], 4472.0);
      expect(monthlyRates['Sweeper 1'], 3911.0);
      expect(monthlyRates['Sweeper 2'], 3438.0);
      expect(monthlyRates['Sweeper 3'], 3212.0);
      expect(monthlyRates['Sweeper 4'], 3212.0);
      expect(monthlyRates['Medical Allowance'], 875.0);
      expect(monthlyRates['Leave Encashment'], 875.0);
      expect(monthlyRates['Puja Assistance'], 2126.0);
      expect(monthlyRates['2 Nos. New Security Guard'], 20600.0);

      final totalMonthly = monthlyRates.values.fold(0.0, (acc, val) => acc + val);
      expect(totalMonthly, 52539.0);
      expect(totalMonthly * 12, 630468.0);

      final budgetHead = AccountingConfig.getBudgetHead('Staff Remuneration');
      expect(budgetHead, isNotNull);
      expect(budgetHead!.yearlyBudget, 630468.0);
      expect(budgetHead.monthlyBudget, 52539.0);
      expect(budgetHead.isDocRequired, isTrue);
    });

    test('generateVoucherNumber creates EXP-2627 format', () {
      final service = StaffRemunerationService();
      final voucher = service.generateVoucherNumber();
      expect(voucher.startsWith('EXP-2627-'), isTrue);
      expect(voucher.length, 14);
    });

    test('computeMonthlyStatus correctly marks Electrician as isPaid for September 2026', () {
      final service = StaffRemunerationService();
      final fakeTxn = {
        'id': 'txn-1',
        'type': 'EXPENDITURE',
        'accountHead': 'Staff Remuneration',
        'staffRole': 'Electrician',
        'remunerationMonth': 'September 2026',
        'amount': 5346.0,
        'paidToOrReceivedFrom': 'Dilip Halder',
        'voucherNumber': 'EXP-2627-10001',
        'documentUrl': 'https://storage.googleapis.com/slip.pdf',
        'documentFileName': 'slip.pdf',
      };

      final statuses = service.computeMonthlyStatus(
        selectedMonth: 'September 2026',
        transactions: [fakeTxn],
      );

      final elecStatus = statuses.firstWhere((s) => s.role == 'Electrician');
      expect(elecStatus.isPaid, isTrue);
      expect(elecStatus.paidAmount, 5346.0);
      expect(elecStatus.voucherNumber, 'EXP-2627-10001');
      expect(elecStatus.payeeName, 'Dilip Halder');

      // Unpaid roles remain isPaid = false
      final guardStatus = statuses.firstWhere((s) => s.role == 'Guard 1');
      expect(guardStatus.isPaid, isFalse);
    });

    test('findRoleStatus returns paid details for paid role and null for unpaid role', () {
      final service = StaffRemunerationService();
      final fakeTxn = {
        'id': 'txn-2',
        'type': 'EXPENDITURE',
        'accountHead': 'Staff Remuneration',
        'staffRole': 'Electrician',
        'remunerationMonth': 'September 2026',
        'amount': 5346.0,
        'voucherNumber': 'EXP-2627-99999',
      };

      final paid = service.findRoleStatus(
        role: 'Electrician',
        month: 'September 2026',
        transactions: [fakeTxn],
      );
      expect(paid, isNotNull);
      expect(paid!.isPaid, isTrue);
      expect(paid.voucherNumber, 'EXP-2627-99999');

      final unpaidRole = service.findRoleStatus(
        role: 'Sweeper 1',
        month: 'September 2026',
        transactions: [fakeTxn],
      );
      expect(unpaidRole, isNull);

      final otherMonth = service.findRoleStatus(
        role: 'Electrician',
        month: 'October 2026',
        transactions: [fakeTxn],
      );
      expect(otherMonth, isNull);
    });

    test('computeMonthlyStatus ignores voided transactions', () {
      final service = StaffRemunerationService();
      final voidedTxn = {
        'id': 'txn-3',
        'type': 'EXPENDITURE',
        'accountHead': 'Staff Remuneration',
        'staffRole': 'Electrician',
        'remunerationMonth': 'September 2026',
        'amount': 5346.0,
        'isVoid': true,
      };

      final statuses = service.computeMonthlyStatus(
        selectedMonth: 'September 2026',
        transactions: [voidedTxn],
      );

      final elecStatus = statuses.firstWhere((s) => s.role == 'Electrician');
      expect(elecStatus.isPaid, isFalse);
    });
  });
}

