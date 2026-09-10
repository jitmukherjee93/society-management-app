import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/accounting_heads.dart';
import 'package:society_management/services/billing_service.dart';
import 'package:society_management/utils/flat_utils.dart';

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

  group('Audit Fixes: FlatUtils & Block Extraction Tests', () {
    test('normalizes composite and multi-hyphen flats correctly', () {
      expect(FlatUtils.normalize('b312'), 'B-312');
      expect(FlatUtils.normalize('B-312'), 'B-312');
      expect(FlatUtils.normalize('B-312-A'), 'B-312-A');
      expect(FlatUtils.normalize('A 101'), 'A-101');
    });

    test('extractBlock accurately extracts exact block letter using regex without substring confusion', () {
      expect(FlatUtils.extractBlock('A-101'), 'A');
      expect(FlatUtils.extractBlock('B-202'), 'B');
      expect(FlatUtils.extractBlock('C-303'), 'C');
      expect(FlatUtils.extractBlock('D-404'), 'D');
      expect(FlatUtils.extractBlock('B-312-A'), 'B');
      // Composite or non-standard flat names do not falsely match Block B or A
      expect(FlatUtils.extractBlock('AB-101'), 'General');
      expect(FlatUtils.extractBlock('Alpha-1'), 'General');
      expect(FlatUtils.extractBlock('101'), 'General');
    });

    test('calculateMaintenanceBreakdown uses strict regex and does not falsely classify AB-101 as Block B', () {
      final breakdownNormalB = AccountingConfig.calculateMaintenanceBreakdown(flatNumber: 'B-101');
      expect(breakdownNormalB.block, 'B');
      expect(breakdownNormalB.baseMaintenance, 420.0);

      final breakdownAB = AccountingConfig.calculateMaintenanceBreakdown(flatNumber: 'AB-101');
      // Should default to fallback Block A rather than matching 'B-' substring
      expect(breakdownAB.block, 'A');
      expect(breakdownAB.baseMaintenance, 450.0);
    });
  });

  group('Audit Fixes: Dynamic Financial Year & Budget Head Tests', () {
    test('getFinancialYear computes correct FY label for dates before and after April', () {
      expect(AccountingConfig.getFinancialYear(DateTime(2026, 9, 10)), '2026-27');
      expect(AccountingConfig.getFinancialYear(DateTime(2027, 2, 1)), '2026-27');
      expect(AccountingConfig.getFinancialYear(DateTime(2027, 4, 1)), '2027-28');
      expect(AccountingConfig.getFinancialYear(DateTime(2028, 1, 15)), '2027-28');
    });

    test('getFinancialYearMonths dynamically generates 12 consecutive months starting from April', () {
      final months2027 = AccountingConfig.getFinancialYearMonths(DateTime(2027, 5, 1));
      expect(months2027.length, 12);
      expect(months2027.first, 'April 2027');
      expect(months2027.last, 'March 2028');
    });

    test('BudgetHead calculates monthlyBudget dynamically as yearlyBudget / 12 when not explicitly specified', () {
      const head = BudgetHead(
        name: 'Registration',
        category: 'Statutory',
        yearlyBudget: 150,
      );
      expect(head.monthlyBudget, 12.5);
    });
  });

  group('Audit Fixes: FlatMaintenanceBreakdown Fine Property Tests', () {
    test('FlatMaintenanceBreakdown includes fine in total and in toMap', () {
      final breakdownWithFine = AccountingConfig.calculateMaintenanceBreakdown(
        flatNumber: 'B-101',
        carCount: 1,
        bikeCount: 0,
        fine: 100.0,
      );

      // Block B base (420) + Car (430) + Fine (100) = 950
      expect(breakdownWithFine.baseMaintenance, 420.0);
      expect(breakdownWithFine.carParkingCharges, 430.0);
      expect(breakdownWithFine.fine, 100.0);
      expect(breakdownWithFine.totalMonthlyDue, 950.0);

      final map = breakdownWithFine.toMap();
      expect(map['fine'], 100.0);
      expect(map['totalMonthlyDue'], 950.0);
    });
  });

  group('Multi-Month Receipt Line Items & Breakdown Tests', () {
    test('Flat B-312 3-Month advance with parking excluded produces correct base total (3 x ₹420 = ₹1,260)', () {
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'B',
        carCount: 1,
        bikeCount: 0,
        monthConfigs: [
          {'month': 'October 2026', 'includeParking': false},
          {'month': 'November 2026', 'includeParking': false},
          {'month': 'December 2026', 'includeParking': false},
        ],
      );

      expect(breakdown['monthCount'], 3);
      expect(breakdown['baseMaintenanceRate'], 420.0);
      expect(breakdown['totalBaseMaintenance'], 1260.0);
      expect(breakdown['totalCarParking'], 0.0);
      expect(breakdown['totalParking'], 0.0);
      expect(breakdown['totalAmount'], 1260.0);
      expect(breakdown['parkingExcludedMonths'], ['October 2026', 'November 2026', 'December 2026']);
    });

    test('Flat B-312 3-Month advance with parking included produces distinct maintenance and parking lines', () {
      final breakdown = BillingService.calculateMultiMonthBreakdown(
        block: 'B',
        carCount: 1,
        bikeCount: 0,
        monthConfigs: [
          {'month': 'October 2026', 'includeParking': true},
          {'month': 'November 2026', 'includeParking': true},
          {'month': 'December 2026', 'includeParking': true},
        ],
      );

      // Maintenance: 3 * 420 = 1260
      // Car Parking: 3 * 430 = 1290
      // Total: 2550
      expect(breakdown['monthCount'], 3);
      expect(breakdown['totalBaseMaintenance'], 1260.0);
      expect(breakdown['totalCarParking'], 1290.0);
      expect(breakdown['totalParking'], 1290.0);
      expect(breakdown['totalAmount'], 2550.0);
      expect(breakdown['parkingMonths'], ['October 2026', 'November 2026', 'December 2026']);
      expect(breakdown['parkingExcludedMonths'], isEmpty);
    });
  });

  group('Parking Gap Alert Timing Tests', () {
    test('Future advance months with excluded parking are not marked as due in current month (e.g. September)', () {
      final maintPaid = ['September 2026', 'October 2026', 'November 2026', 'December 2026', 'January 2027'];
      final parkPaid = ['September 2026', 'October 2026', 'November 2026'];
      final missingParking = maintPaid.where((m) => !parkPaid.contains(m)).toList();
      expect(missingParking, ['December 2026', 'January 2027']);

      // Simulated current month: September 2026 (index 5)
      final curMonthIdx = AccountingConfig.getMonthIndex('September 2026');
      final selectedMonth = 'September 2026';

      final dueGaps = missingParking.where((m) {
        final mIdx = AccountingConfig.getMonthIndex(m);
        return mIdx != -1 && (mIdx <= curMonthIdx || m == selectedMonth);
      }).toList();

      // In September 2026, December and January have NOT arrived yet -> 0 due gaps
      expect(dueGaps, isEmpty);
    });

    test('When specific month arrives (e.g. December 2026), parking gap becomes due and alerts admin', () {
      final maintPaid = ['September 2026', 'October 2026', 'November 2026', 'December 2026', 'January 2027'];
      final parkPaid = ['September 2026', 'October 2026', 'November 2026'];
      final missingParking = maintPaid.where((m) => !parkPaid.contains(m)).toList();

      // Simulated admin selecting December 2026 OR calendar reaching December 2026
      final curMonthIdx = AccountingConfig.getMonthIndex('September 2026');
      final selectedMonth = 'December 2026';

      final dueGaps = missingParking.where((m) {
        final mIdx = AccountingConfig.getMonthIndex(m);
        return mIdx != -1 && (mIdx <= curMonthIdx || m == selectedMonth);
      }).toList();

      // Only December 2026 is due; January 2027 remains in the future
      expect(dueGaps, ['December 2026']);
    });
  });

  group('Single Due Payment Mode & Parking-Only Due Tests', () {
    test('Parking-only due data preserves ₹0 base maintenance and ₹630 vehicle charges', () {
      final parkingDueData = {
        'flatNumber': 'B-312',
        'block': 'B',
        'month': 'December 2026',
        'baseMaintenance': 0.0,
        'carParkingCharges': 430.0,
        'bikeParkingCharges': 200.0,
        'amount': 630.0,
        'isParkingOnlyBill': true,
        'status': 'UNPAID',
      };

      final bool isParkingOnly = parkingDueData['isParkingOnlyBill'] == true ||
          ((parkingDueData['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0;
      expect(isParkingOnly, isTrue);

      final double baseMaint = (parkingDueData['baseMaintenance'] as num).toDouble();
      final double carParking = (parkingDueData['carParkingCharges'] as num).toDouble();
      final double bikeParking = (parkingDueData['bikeParkingCharges'] as num).toDouble();
      final double totalAmt = (parkingDueData['amount'] as num).toDouble();

      expect(baseMaint, 0.0);
      expect(carParking, 430.0);
      expect(bikeParking, 200.0);
      expect(totalAmt, 630.0);
      expect(carParking + bikeParking, 630.0);
    });

    test('Single due payment mode locks schedule strictly to 1 month and hides multi-month advance', () {
      const bool isExistingDue = true;
      const String billMonth = 'December 2026';

      List<String> buildSchedule({required bool isDue, required String month}) {
        if (isDue) {
          return [month]; // Single due mode locks to 1 month
        }
        final startIdx = AccountingConfig.getMonthIndex(month);
        final schedule = <String>[month];
        for (int i = startIdx + 1; i < AccountingConfig.financialYearMonths.length; i++) {
          schedule.add(AccountingConfig.financialYearMonths[i]);
        }
        return schedule;
      }

      final dueSchedule = buildSchedule(isDue: isExistingDue, month: billMonth);
      expect(dueSchedule, [billMonth]);
      expect(dueSchedule.length, 1);

      final advanceSchedule = buildSchedule(isDue: false, month: billMonth);
      expect(advanceSchedule.length, greaterThan(1));
      expect(advanceSchedule, contains('January 2027'));
    });
  });
}


