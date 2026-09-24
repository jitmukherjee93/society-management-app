import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/accounting_heads.dart';
import 'package:society_management/models/amenity_booking.dart';
import 'package:society_management/services/amenity_booking_service.dart';
import 'package:society_management/services/visitor_pass_service.dart';
import 'package:society_management/utils/currency_math.dart';
import 'package:society_management/utils/flat_utils.dart';
import 'package:society_management/utils/number_to_words.dart';

void main() {
  group('White Box Testing — NumberToWords Converter', () {
    test('Zero returns Rupees Zero Only', () {
      expect(NumberToWords.convert(0), equals('Rupees Zero Only'));
      expect(NumberToWords.convert(0.0), equals('Rupees Zero Only'));
    });

    test('Single digit and teens conversion', () {
      expect(NumberToWords.convert(5), equals('Five Rupees Only'));
      expect(NumberToWords.convert(11), equals('Eleven Rupees Only'));
      expect(NumberToWords.convert(19), equals('Nineteen Rupees Only'));
    });

    test('Tens and compound two-digit numbers', () {
      expect(NumberToWords.convert(20), equals('Twenty Rupees Only'));
      expect(NumberToWords.convert(45), equals('Forty Five Rupees Only'));
      expect(NumberToWords.convert(99), equals('Ninety Nine Rupees Only'));
    });

    test('Hundreds, thousands, lakhs, and crores', () {
      expect(NumberToWords.convert(100), equals('One Hundred Rupees Only'));
      expect(NumberToWords.convert(390), equals('Three Hundred Ninety Rupees Only'));
      expect(NumberToWords.convert(1000), equals('One Thousand Rupees Only'));
      expect(NumberToWords.convert(4250), equals('Four Thousand Two Hundred Fifty Rupees Only'));
      expect(NumberToWords.convert(100000), equals('One Lakh Rupees Only'));
      expect(NumberToWords.convert(1550000), equals('Fifteen Lakh Fifty Thousand Rupees Only'));
      expect(NumberToWords.convert(10000000), equals('One Crore Rupees Only'));
      expect(NumberToWords.convert(20500000), equals('Two Crore Five Lakh Rupees Only'));
    });

    test('Paise only and mixed Rupees and Paise', () {
      expect(NumberToWords.convert(0.50), equals('Fifty Paise Only'));
      expect(NumberToWords.convert(0.05), equals('Five Paise Only'));
      expect(NumberToWords.convert(1290.50), equals('One Thousand Two Hundred Ninety Rupees and Fifty Paise Only'));
      expect(NumberToWords.convert(4000.75), equals('Four Thousand Rupees and Seventy Five Paise Only'));
    });

    test('Defensive negative amounts', () {
      expect(NumberToWords.convert(-500), equals('Minus Five Hundred Rupees Only'));
    });
  });

  group('White Box Testing — CurrencyMath Precision & Rounding', () {
    test('roundPaise rounds correctly to two decimal places', () {
      expect(CurrencyMath.roundPaise(10.555), equals(10.56));
      expect(CurrencyMath.roundPaise(10.554), equals(10.55));
      expect(CurrencyMath.roundPaise(0.0), equals(0.0));
    });

    test('toPaise and fromPaise roundtrip accurately', () {
      expect(CurrencyMath.toPaise(430.0), equals(43000));
      expect(CurrencyMath.toPaise(1290.75), equals(129075));
      expect(CurrencyMath.fromPaise(43000), equals(430.0));
      expect(CurrencyMath.fromPaise(129075), equals(1290.75));
    });

    test('sum eliminates binary floating point summation errors', () {
      // 0.1 + 0.2 in raw double is 0.30000000000000004
      final result = CurrencyMath.sum([0.1, 0.2]);
      expect(result, equals(0.3));

      final amounts = [450.0, 430.0, 100.0, 100.0, 10.0];
      expect(CurrencyMath.sum(amounts), equals(1090.0));
    });
  });

  group('White Box Testing — VisitorPassService Pass Lifecycle & Code Generation', () {
    test('generatePassCode produces strictly 6-digit numeric string', () {
      for (int i = 0; i < 50; i++) {
        final code = VisitorPassService.generatePassCode();
        expect(code.length, equals(6));
        final val = int.tryParse(code);
        expect(val, isNotNull);
        expect(val! >= 100000 && val <= 999999, isTrue);
      }
    });

    test('evaluatePassStatus detects consumed passes (isUsed, CHECKED_IN, CHECKED_OUT)', () {
      expect(
        VisitorPassService.evaluatePassStatus({'isUsed': true, 'status': 'PENDING'}),
        equals(PassVerificationStatus.alreadyUsed),
      );
      expect(
        VisitorPassService.evaluatePassStatus({'isUsed': false, 'status': 'CHECKED_IN'}),
        equals(PassVerificationStatus.alreadyUsed),
      );
      expect(
        VisitorPassService.evaluatePassStatus({'isUsed': false, 'status': 'CHECKED_OUT'}),
        equals(PassVerificationStatus.alreadyUsed),
      );
    });

    test('evaluatePassStatus detects expired passes', () {
      final now = DateTime(2026, 9, 24, 12, 0);
      final expiredDate = DateTime(2026, 9, 24, 11, 0);

      // Explicit EXPIRED status
      expect(
        VisitorPassService.evaluatePassStatus({'status': 'EXPIRED'}, currentTime: now),
        equals(PassVerificationStatus.expired),
      );

      // Expiration timestamp passed
      expect(
        VisitorPassService.evaluatePassStatus({
          'status': 'PENDING',
          'expiresAt': Timestamp.fromDate(expiredDate),
        }, currentTime: now),
        equals(PassVerificationStatus.expired),
      );

      // Inferred from createdAt > 8 hours ago
      final oldCreated = DateTime(2026, 9, 24, 2, 0); // 10 hours ago
      expect(
        VisitorPassService.evaluatePassStatus({
          'status': 'PENDING',
          'createdAt': Timestamp.fromDate(oldCreated),
        }, currentTime: now),
        equals(PassVerificationStatus.expired),
      );
    });

    test('evaluatePassStatus recognizes valid passes for PENDING and APPROVED', () {
      final now = DateTime(2026, 9, 24, 12, 0);
      final futureExpiry = DateTime(2026, 9, 24, 18, 0);

      expect(
        VisitorPassService.evaluatePassStatus({
          'status': 'PENDING',
          'expiresAt': Timestamp.fromDate(futureExpiry),
        }, currentTime: now),
        equals(PassVerificationStatus.valid),
      );

      expect(
        VisitorPassService.evaluatePassStatus({
          'status': 'APPROVED',
          'expiresAt': Timestamp.fromDate(futureExpiry),
        }, currentTime: now),
        equals(PassVerificationStatus.valid),
      );
    });

    test('evaluatePassStatus returns invalid for rejected or corrupted status', () {
      expect(
        VisitorPassService.evaluatePassStatus({'status': 'REJECTED'}),
        equals(PassVerificationStatus.invalid),
      );
      expect(
        VisitorPassService.evaluatePassStatus({'status': 'CANCELLED'}),
        equals(PassVerificationStatus.invalid),
      );
    });
  });

  group('White Box Testing — AmenityBookingService & AmenityBooking Model', () {
    test('isLeadTimeValid strictly enforces 2-day advance notice', () {
      final today = DateTime(2026, 9, 24);

      // Past date -> invalid
      expect(AmenityBookingService.isLeadTimeValid(DateTime(2026, 9, 23), today), isFalse);

      // Today (0 days notice) -> invalid
      expect(AmenityBookingService.isLeadTimeValid(DateTime(2026, 9, 24), today), isFalse);

      // Tomorrow (1 day notice) -> invalid
      expect(AmenityBookingService.isLeadTimeValid(DateTime(2026, 9, 25), today), isFalse);

      // Exactly 2 days notice -> valid
      expect(AmenityBookingService.isLeadTimeValid(DateTime(2026, 9, 26), today), isTrue);

      // 3 days notice -> valid
      expect(AmenityBookingService.isLeadTimeValid(DateTime(2026, 9, 27), today), isTrue);

      // Boundary: Leap year Feb 29 check
      final leapRef = DateTime(2028, 2, 27);
      expect(AmenityBookingService.isLeadTimeValid(DateTime(2028, 2, 29), leapRef), isTrue);
    });

    test('calculateBookingFee calculates rates and defensive boundaries correctly', () {
      // 1. Community Hall: ₹4000/day, ₹200 advance
      final hall1 = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.communityHall,
        numberOfDays: 1,
      );
      expect(hall1['totalAmount'], equals(4000.0));
      expect(hall1['advancePaid'], equals(200.0));
      expect(hall1['balanceDue'], equals(3800.0));

      final hall3 = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.communityHall,
        numberOfDays: 3,
      );
      expect(hall3['totalAmount'], equals(12000.0));
      expect(hall3['advancePaid'], equals(200.0));
      expect(hall3['balanceDue'], equals(11800.0));

      // 2. Open Ground: Minimum 2 days required (clamped: ₹500 total, ₹200 advance, ₹300 balance)
      final ground1 = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.openGround,
        numberOfDays: 1,
      );
      expect(ground1['totalAmount'], equals(500.0));
      expect(ground1['advancePaid'], equals(200.0));
      expect(ground1['balanceDue'], equals(300.0));

      final ground2 = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.openGround,
        numberOfDays: 2,
      );
      expect(ground2['totalAmount'], equals(500.0));
      expect(ground2['advancePaid'], equals(200.0));
      expect(ground2['balanceDue'], equals(300.0));

      // 3. Gym: Always Free
      final gym = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.gym,
        numberOfDays: 1,
      );
      expect(gym['totalAmount'], equals(0.0));
      expect(gym['advancePaid'], equals(0.0));
      expect(gym['balanceDue'], equals(0.0));

      // 4. Defensive check: negative or zero days clamped to at least 1 day
      final hallDefensive = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.communityHall,
        numberOfDays: 0,
      );
      expect(hallDefensive['totalAmount'], equals(4000.0));
      expect(hallDefensive['balanceDue'], equals(3800.0));
    });

    test('AmenityBooking model serialization, deserialization, and enum parsing', () {
      final now = DateTime(2026, 9, 24, 10, 0);
      final rawMap = {
        'amenityId': 'COMMUNITY_HALL',
        'bookingDate': '2026-09-26',
        'flatNumber': 'C-102',
        'residentUid': 'uid-123',
        'residentName': 'Resident User',
        'residentPhone': '9876543210',
        'occasionPurpose': 'Birthday Party',
        'totalAmount': 4000.0,
        'advancePaid': 200.0,
        'balanceDue': 3800.0,
        'paymentRef': 'UPI-REF-999',
        'status': 'PENDING_APPROVAL',
        'keyStatus': 'KEY_WITH_GUARD',
        'createdAt': Timestamp.fromDate(now),
      };

      final booking = AmenityBooking.fromMap('book-001', rawMap);
      expect(booking.id, equals('book-001'));
      expect(booking.amenityType, equals(AmenityType.communityHall));
      expect(booking.status, equals(BookingStatus.pendingApproval));
      expect(booking.keyStatus, equals(GymKeyStatus.keyWithGuard));
      expect(booking.bookingDate, equals('2026-09-26'));
      expect(booking.totalAmount, equals(4000.0));

      final mapped = booking.toMap();
      expect(mapped['amenityId'], equals('COMMUNITY_HALL'));
      expect(mapped['status'], equals('PENDING_APPROVAL'));
      expect(mapped['keyStatus'], equals('KEY_WITH_GUARD'));

      // Enum fallback checks
      expect(AmenityType.fromId('UNKNOWN_AMENITY'), equals(AmenityType.communityHall));
      expect(BookingStatus.fromString('NON_EXISTENT'), equals(BookingStatus.pendingApproval));
      expect(GymKeyStatus.fromString('INVALID_KEY_STATUS'), equals(GymKeyStatus.keyWithGuard));
      expect(GymKeyStatus.fromString('KEY_ISSUED'), equals(GymKeyStatus.keyIssued));
      expect(GymKeyStatus.fromString('KEY_RETURNED'), equals(GymKeyStatus.keyReturned));
    });
  });

  group('White Box Testing — AccountingConfig Financial Year & Maintenance Formulas', () {
    test('getFinancialYear computes canonical FY across calendar boundaries', () {
      expect(AccountingConfig.getFinancialYear(DateTime(2026, 4, 1)), equals('2026-27'));
      expect(AccountingConfig.getFinancialYear(DateTime(2026, 9, 24)), equals('2026-27'));
      expect(AccountingConfig.getFinancialYear(DateTime(2026, 12, 31)), equals('2026-27'));
      expect(AccountingConfig.getFinancialYear(DateTime(2027, 1, 1)), equals('2026-27'));
      expect(AccountingConfig.getFinancialYear(DateTime(2027, 3, 31)), equals('2026-27'));
      expect(AccountingConfig.getFinancialYear(DateTime(2027, 4, 1)), equals('2027-28'));
    });

    test('calculateMaintenanceBreakdown block rate lookup and car/bike charges', () {
      // Block A: ₹450
      final a = AccountingConfig.calculateMaintenanceBreakdown(flatNumber: 'A-101');
      expect(a.block, equals('A'));
      expect(a.baseMaintenance, equals(450.0));
      expect(a.totalMonthlyDue, equals(450.0));

      // Block B: ₹420
      final b = AccountingConfig.calculateMaintenanceBreakdown(flatNumber: 'B-204');
      expect(b.block, equals('B'));
      expect(b.baseMaintenance, equals(420.0));

      // Block C: ₹390 + 1 Car (₹430) + 1 Bike (₹100) + Fine (₹20)
      final c = AccountingConfig.calculateMaintenanceBreakdown(
        flatNumber: 'C-305',
        carCount: 1,
        bikeCount: 1,
        fine: 20.0,
      );
      expect(c.block, equals('C'));
      expect(c.baseMaintenance, equals(390.0));
      expect(c.carParkingCharges, equals(430.0));
      expect(c.bikeParkingCharges, equals(100.0));
      expect(c.fine, equals(20.0));
      expect(c.totalMonthlyDue, equals(390 + 430 + 100 + 20));

      // Block D: ₹490
      final d = AccountingConfig.calculateMaintenanceBreakdown(flatNumber: 'D-502');
      expect(d.block, equals('D'));
      expect(d.baseMaintenance, equals(490.0));

      // Non-standard prefix safely defaults to Block A
      final fallback = AccountingConfig.calculateMaintenanceBreakdown(flatNumber: '101');
      expect(fallback.block, equals('A'));
      expect(fallback.baseMaintenance, equals(450.0));
    });

    test('calculateFromUserData caps car count at 1 and bike count at 2', () {
      final userWithVehicles = {
        'flatNumber': 'B-102',
        'isCarOwner': true,
        'carReg': 'WB 02 AB 1234',
        'isBikeOwner': true,
        'bikeReg': 'WB 02 XY 5678',
        'hasBike2': true,
        'bike2Reg': 'WB 02 PQ 9999',
      };

      final breakdown = AccountingConfig.calculateFromUserData(userWithVehicles);
      expect(breakdown.block, equals('B'));
      expect(breakdown.carCount, equals(1));
      expect(breakdown.bikeCount, equals(2));
      expect(breakdown.carParkingCharges, equals(430.0));
      expect(breakdown.bikeParkingCharges, equals(200.0));
      expect(breakdown.totalMonthlyDue, equals(420.0 + 430.0 + 200.0));
    });
  });

  group('White Box Testing — FlatUtils Canonical Normalization', () {
    test('Normalizes various casing and spaces', () {
      expect(FlatUtils.normalize(' c - 102 '), equals('C-102'));
      expect(FlatUtils.normalize('a101'), equals('A-101'));
      expect(FlatUtils.normalize('B204'), equals('B-204'));
      expect(FlatUtils.extractBlock('c-102'), equals('C'));
      expect(FlatUtils.extractBlock('D 501'), equals('D'));
    });
  });
}

