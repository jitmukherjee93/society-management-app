import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/accounting_heads.dart';
import 'package:society_management/services/billing_service.dart';
import 'package:society_management/services/notification_service.dart';
import 'package:society_management/utils/flat_utils.dart';

// ============================================================================
// SERVICE LAYER & UTILITY REGRESSION TESTS
// ============================================================================
// Validates critical service-layer edge cases, financial calculations,
// occupant classification heuristics, and notification caching logic.
// ============================================================================

void main() {
  group('FlatUtils Occupant Classification Tests (ARCH-03)', () {
    test('isRentee correctly identifies rent-paying tenant roles', () {
      expect(FlatUtils.isRentee('Rentee'), isTrue);
      expect(FlatUtils.isRentee('rentee'), isTrue);
      expect(FlatUtils.isRentee('Tenant'), isTrue);
      expect(FlatUtils.isRentee('tenant'), isTrue);
      expect(FlatUtils.isRentee('Resident'), isTrue);
      expect(FlatUtils.isRentee('Owner'), isFalse);
      expect(FlatUtils.isRentee('ADMIN'), isFalse);
      expect(FlatUtils.isRentee(null), isFalse);
    });

    test('isOwner correctly identifies flat owner roles', () {
      expect(FlatUtils.isOwner('Owner'), isTrue);
      expect(FlatUtils.isOwner('owner'), isTrue);
      expect(FlatUtils.isOwner('Landlord'), isTrue);
      expect(FlatUtils.isOwner('Rentee'), isFalse);
      expect(FlatUtils.isOwner('Tenant'), isFalse);
      expect(FlatUtils.isOwner(null), isFalse);
    });

    test('getLookupKeys produces all search variants for security and queries', () {
      final keys = FlatUtils.getLookupKeys('B-312');
      expect(keys.contains('B-312'), isTrue);
      expect(keys.contains('b-312'), isTrue);
      expect(keys.contains('B312'), isTrue);
      expect(keys.contains('b312'), isTrue);
      expect(keys.contains('312'), isTrue);
    });
  });

  group('NotificationService Cache Invalidation Tests (BUG-28)', () {
    test('invalidateFlatUserCache clears specific flat and all flats without crashing', () {
      // Verify invoking cache invalidation for specific flat
      expect(() => NotificationService.invalidateFlatUserCache('B-312'), returnsNormally);

      // Verify invoking cache invalidation globally
      expect(() => NotificationService.invalidateFlatUserCache(), returnsNormally);
    });
  });

  group('AccountingConfig & Voucher Monotonicity Tests (BUG-17, BUG-19)', () {
    test('generateVoucherCode produces collision-resistant sequential codes', () {
      final code1 = AccountingConfig.generateVoucherCode('INC');
      final code2 = AccountingConfig.generateVoucherCode('INC');
      final expCode = AccountingConfig.generateVoucherCode('EXP');

      expect(code1.startsWith('INC-'), isTrue);
      expect(code2.startsWith('INC-'), isTrue);
      expect(expCode.startsWith('EXP-'), isTrue);
      expect(code1 != code2, isTrue, reason: 'Consecutive voucher numbers must be distinct');
    });

    test('getFinancialYear dynamically adapts across calendar years', () {
      // April 2026 -> FY 2026-27
      expect(AccountingConfig.getFinancialYear(DateTime(2026, 4, 1)), '2026-27');
      // March 2027 -> FY 2026-27
      expect(AccountingConfig.getFinancialYear(DateTime(2027, 3, 31)), '2026-27');
      // April 2027 -> FY 2027-28
      expect(AccountingConfig.getFinancialYear(DateTime(2027, 4, 1)), '2027-28');
      // January 2028 -> FY 2027-28
      expect(AccountingConfig.getFinancialYear(DateTime(2028, 1, 15)), '2027-28');
    });

    test('getFinancialYearMonths produces 12 consecutive months for future FY', () {
      final months2027 = AccountingConfig.getFinancialYearMonths(DateTime(2027, 5, 1));
      expect(months2027.length, 12);
      expect(months2027.first, 'April 2027');
      expect(months2027.last, 'March 2028');
    });
  });

  group('BillingService Multi-Month Edge Cases (SEC-03, BUG-23)', () {
    test('calculateMultiMonthBreakdown computes accurate totals with fine', () {
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'C', // Official rate: ₹390/mo
        carCount: 0,
        bikeCount: 2, // 2 * ₹100 = ₹200/mo
        monthConfigs: [
          {'month': 'April 2026', 'includeParking': true},
          {'month': 'May 2026', 'includeParking': true},
        ],
        fine: 50.0, // ₹50 late fine
      );

      // Total base: 390 * 2 = 780
      // Total bike parking: 200 * 2 = 400
      // Fine: 50
      // Total: 780 + 400 + 50 = 1230
      expect(breakdown['totalBaseMaintenance'], 780.0);
      expect(breakdown['totalBikeParking'], 400.0);
      expect(breakdown['fine'], 50.0);
      expect(breakdown['totalAmount'], 1230.0);
      expect(breakdown['monthCount'], 2);
    });

    test('calculateMultiMonthBreakdown handles parking exclusion for one month', () {
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'D', // Official rate: ₹490/mo
        carCount: 1, // ₹430/mo
        bikeCount: 0,
        monthConfigs: [
          {'month': 'April 2026', 'includeParking': true},
          {'month': 'May 2026', 'includeParking': false},
        ],
      );

      // Base: 490 * 2 = 980
      // Car parking: 430 for 1 month only = 430
      // Total: 980 + 430 = 1410
      expect(breakdown['totalBaseMaintenance'], 980.0);
      expect(breakdown['totalCarParking'], 430.0);
      expect(breakdown['totalAmount'], 1410.0);
      expect(breakdown['parkingExcludedMonths'], ['May 2026']);
    });
  });
}
