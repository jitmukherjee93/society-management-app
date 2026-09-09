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

      final totalMonthly = monthlyRates.values.fold(0.0, (sum, val) => sum + val);
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
  });
}

