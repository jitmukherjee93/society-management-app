import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/accounting_heads.dart';
import 'package:society_management/services/billing_service.dart';

void main() {
  group('AccountingConfig Financial Year Months Tests', () {
    test('financialYearMonths contains 12 months in correct order from April to March', () {
      expect(AccountingConfig.financialYearMonths.length, 12);
      expect(AccountingConfig.financialYearMonths.first, 'April 2026');
      expect(AccountingConfig.financialYearMonths.last, 'March 2027');
      expect(AccountingConfig.financialYearMonths[5], 'September 2026');
      expect(AccountingConfig.financialYearMonths[6], 'October 2026');
    });

    test('getMonthIndex correctly returns index in financial year', () {
      expect(AccountingConfig.getMonthIndex('April 2026'), 0);
      expect(AccountingConfig.getMonthIndex('September 2026'), 5);
      expect(AccountingConfig.getMonthIndex('October 2026'), 6);
      expect(AccountingConfig.getMonthIndex('March 2027'), 11);
      expect(AccountingConfig.getMonthIndex('NonExistentMonth'), -1);
    });
  });

  group('BillingService Multi-Month Breakdown Tests', () {
    test('calculates single month with full vehicle parking included (Block A: ₹450)', () {
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'A',
        carCount: 1,
        bikeCount: 1,
        monthConfigs: [
          {'month': 'September 2026', 'includeParking': true}
        ],
      );

      expect(breakdown['monthCount'], 1);
      expect(breakdown['baseMaintenanceRate'], 450.0);
      expect(breakdown['totalBaseMaintenance'], 450.0);
      expect(breakdown['totalCarParking'], 430.0);
      expect(breakdown['totalBikeParking'], 100.0);
      expect(breakdown['totalParking'], 530.0);
      expect(breakdown['totalAmount'], 980.0);
      expect(breakdown['maintenanceMonths'], ['September 2026']);
      expect(breakdown['parkingMonths'], ['September 2026']);
      expect(breakdown['parkingExcludedMonths'], isEmpty);
      expect((breakdown['parkingExcludedMonths'] as List).isNotEmpty, isFalse);
    });

    test('calculates single month with vehicle parking excluded (opted-out)', () {
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'A',
        carCount: 1,
        bikeCount: 1,
        monthConfigs: [
          {'month': 'September 2026', 'includeParking': false}
        ],
      );

      expect(breakdown['monthCount'], 1);
      expect(breakdown['totalBaseMaintenance'], 450.0);
      expect(breakdown['totalParking'], 0.0);
      expect(breakdown['totalAmount'], 450.0);
      expect(breakdown['maintenanceMonths'], ['September 2026']);
      expect(breakdown['parkingMonths'], isEmpty);
      expect(breakdown['parkingExcludedMonths'], ['September 2026']);
      expect((breakdown['parkingExcludedMonths'] as List).isNotEmpty, isTrue);
    });

    test('calculates 3 months advance with parking paid for month 1 only (User scenario)', () {
      // User pays Sep maintenance + parking, but Oct and Nov maintenance only
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'A',
        carCount: 1,
        bikeCount: 0,
        monthConfigs: [
          {'month': 'September 2026', 'includeParking': true},
          {'month': 'October 2026', 'includeParking': false},
          {'month': 'November 2026', 'includeParking': false},
        ],
      );

      expect(breakdown['monthCount'], 3);
      expect(breakdown['totalBaseMaintenance'], 450.0 * 3); // 1350.0
      expect(breakdown['totalCarParking'], 430.0); // 1 month car parking
      expect(breakdown['totalParking'], 430.0);
      expect(breakdown['totalAmount'], 1780.0);
      expect(breakdown['maintenanceMonths'], ['September 2026', 'October 2026', 'November 2026']);
      expect(breakdown['parkingMonths'], ['September 2026']);
      expect(breakdown['parkingExcludedMonths'], ['October 2026', 'November 2026']);
      expect((breakdown['parkingExcludedMonths'] as List).isNotEmpty, isTrue);
    });

    test('calculates 4 months with all parking included (Block B: ₹420)', () {
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'B',
        carCount: 1,
        bikeCount: 1,
        monthConfigs: [
          {'month': 'September 2026', 'includeParking': true},
          {'month': 'October 2026', 'includeParking': true},
          {'month': 'November 2026', 'includeParking': true},
          {'month': 'December 2026', 'includeParking': true},
        ],
      );

      expect(breakdown['monthCount'], 4);
      expect(breakdown['baseMaintenanceRate'], 420.0);
      expect(breakdown['totalBaseMaintenance'], 1680.0);
      expect(breakdown['totalParking'], 530.0 * 4); // 2120.0
      expect(breakdown['totalAmount'], 3800.0);
      expect(breakdown['parkingMonths'].length, 4);
      expect(breakdown['parkingExcludedMonths'], isEmpty);
      expect((breakdown['parkingExcludedMonths'] as List).isNotEmpty, isFalse);
    });

    test('handles flat with 0 vehicles gracefully', () {
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'A',
        carCount: 0,
        bikeCount: 0,
        monthConfigs: [
          {'month': 'September 2026', 'includeParking': true},
          {'month': 'October 2026', 'includeParking': true},
        ],
      );

      expect(breakdown['totalBaseMaintenance'], 900.0);
      expect(breakdown['totalParking'], 0.0);
      expect(breakdown['totalAmount'], 900.0);
      expect(breakdown['parkingMonths'], isEmpty);
      expect(breakdown['parkingExcludedMonths'], isEmpty);
      expect((breakdown['parkingExcludedMonths'] as List).isNotEmpty, isFalse);
    });
  });
}
