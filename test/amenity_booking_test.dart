import 'package:flutter_test/flutter_test.dart';
import 'package:society_management/models/amenity_booking.dart';
import 'package:society_management/services/amenity_booking_service.dart';

// ============================================================================
// AMENITY BOOKING & FACILITY MANAGEMENT UNIT TESTS
// ============================================================================
// Tests the core business logic of the Amenity Booking system:
// 1. Mandatory 2-Day Advance Notice Rule (Hall & Ground)
// 2. Fee & Advance Calculations (Hall ₹4000/day + ₹200 advance, Ground ₹500/2 days, Gym ₹0)
// 3. Serialization and Deserialization of AmenityBooking records
// 4. Gym Key Handover State Transitions
// ============================================================================

void main() {
  group('1. Advance Notice (Lead Time) Validation Tests', () {
    test('Rejects same-day booking (< 2 days notice)', () {
      final now = DateTime(2026, 10, 10, 10, 0);
      final sameDay = DateTime(2026, 10, 10, 18, 0);
      expect(AmenityBookingService.isLeadTimeValid(sameDay, now), isFalse);
    });

    test('Rejects next-day booking (1 day notice < 2 days required)', () {
      final now = DateTime(2026, 10, 10, 10, 0);
      final nextDay = DateTime(2026, 10, 11, 10, 0);
      expect(AmenityBookingService.isLeadTimeValid(nextDay, now), isFalse);
    });

    test('Accepts booking exactly 2 days in advance', () {
      final now = DateTime(2026, 10, 10, 10, 0);
      final twoDaysLater = DateTime(2026, 10, 12, 10, 0);
      expect(AmenityBookingService.isLeadTimeValid(twoDaysLater, now), isTrue);
    });

    test('Accepts booking 10 days in advance', () {
      final now = DateTime(2026, 10, 10, 10, 0);
      final tenDaysLater = DateTime(2026, 10, 20, 10, 0);
      expect(AmenityBookingService.isLeadTimeValid(tenDaysLater, now), isTrue);
    });

    test('Rejects past dates', () {
      final now = DateTime(2026, 10, 10, 10, 0);
      final pastDate = DateTime(2026, 10, 5, 10, 0);
      expect(AmenityBookingService.isLeadTimeValid(pastDate, now), isFalse);
    });
  });

  group('2. Fee and Advance Calculation Tests', () {
    test('Community Hall: ₹4,000 for 1 day with ₹200 advance', () {
      final fees = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.communityHall,
        numberOfDays: 1,
      );
      expect(fees['totalAmount'], equals(4000.0));
      expect(fees['advancePaid'], equals(200.0));
      expect(fees['balanceDue'], equals(3800.0));
    });

    test('Community Hall: ₹8,000 for 2 days with ₹200 advance', () {
      final fees = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.communityHall,
        numberOfDays: 2,
      );
      expect(fees['totalAmount'], equals(8000.0));
      expect(fees['advancePaid'], equals(200.0));
      expect(fees['balanceDue'], equals(7800.0));
    });

    test('Society Ground: ₹500 for 2 days with ₹200 advance', () {
      final fees = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.openGround,
        numberOfDays: 2,
      );
      expect(fees['totalAmount'], equals(500.0));
      expect(fees['advancePaid'], equals(200.0));
      expect(fees['balanceDue'], equals(300.0));
    });

    test('Society Ground: clamps 1 day to 2 days minimum (₹500 total, ₹200 advance, ₹300 balance)', () {
      final fees = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.openGround,
        numberOfDays: 1,
      );
      expect(fees['totalAmount'], equals(500.0));
      expect(fees['advancePaid'], equals(200.0));
      expect(fees['balanceDue'], equals(300.0));
    });

    test('Society Ground: ₹750 for 3 days with ₹200 advance', () {
      final fees = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.openGround,
        numberOfDays: 3,
      );
      expect(fees['totalAmount'], equals(750.0));
      expect(fees['advancePaid'], equals(200.0));
      expect(fees['balanceDue'], equals(550.0));
    });

    test('Society Ground: bookAmenity throws Exception if booked for less than 2 days', () async {
      expect(
        () => AmenityBookingService.bookAmenity(
          amenityType: AmenityType.openGround,
          startDate: DateTime(2026, 12, 1),
          endDate: null, // 1 day
          flatNumber: 'A-101',
          residentUid: 'test_uid',
          residentName: 'Test Resident',
          residentPhone: '9999999999',
          occasionPurpose: 'Cricket Tournament',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Society Ground must be booked for a minimum of 2 days.'),
        )),
      );
    });

    test('Fitness Gym: Free of cost (₹0 total, ₹0 advance, ₹0 balance)', () {
      final fees = AmenityBookingService.calculateBookingFee(
        amenityType: AmenityType.gym,
        numberOfDays: 1,
      );
      expect(fees['totalAmount'], equals(0.0));
      expect(fees['advancePaid'], equals(0.0));
      expect(fees['balanceDue'], equals(0.0));
    });
  });

  group('3. AmenityBooking Model Serialization & Enum Mapping Tests', () {
    test('Serializes and deserializes Community Hall booking correctly', () {
      final booking = AmenityBooking(
        id: 'booking_123',
        amenityType: AmenityType.communityHall,
        bookingDate: '2026-10-15',
        endDate: '2026-10-15',
        flatNumber: 'B-302',
        residentUid: 'user_xyz',
        residentName: 'Anita Sharma',
        residentPhone: '9876543210',
        occasionPurpose: 'Daughter\'s 10th Birthday Party',
        totalAmount: 4000.0,
        advancePaid: 200.0,
        balanceDue: 3800.0,
        paymentRef: 'UPI-REF-992384',
        status: BookingStatus.pendingApproval,
        keyStatus: GymKeyStatus.keyWithGuard,
        createdAt: DateTime(2026, 10, 1),
      );

      final map = booking.toMap();
      expect(map['amenityId'], equals('COMMUNITY_HALL'));
      expect(map['flatNumber'], equals('B-302'));
      expect(map['totalAmount'], equals(4000.0));
      expect(map['advancePaid'], equals(200.0));
      expect(map['balanceDue'], equals(3800.0));
      expect(map['status'], equals('PENDING_APPROVAL'));

      final restored = AmenityBooking.fromMap(map, 'booking_123');
      expect(restored.id, equals('booking_123'));
      expect(restored.amenityType, equals(AmenityType.communityHall));
      expect(restored.bookingDate, equals('2026-10-15'));
      expect(restored.flatNumber, equals('B-302'));
      expect(restored.status, equals(BookingStatus.pendingApproval));
      expect(restored.paymentRef, equals('UPI-REF-992384'));
    });

    test('Enum round-trip parsing matches all cases', () {
      expect(AmenityType.fromString('COMMUNITY_HALL'), equals(AmenityType.communityHall));
      expect(AmenityType.fromString('OPEN_GROUND'), equals(AmenityType.openGround));
      expect(AmenityType.fromString('GYM'), equals(AmenityType.gym));
      expect(AmenityType.fromString('unknown'), equals(AmenityType.communityHall));

      expect(BookingStatus.fromString('PENDING_APPROVAL'), equals(BookingStatus.pendingApproval));
      expect(BookingStatus.fromString('CONFIRMED'), equals(BookingStatus.confirmed));
      expect(BookingStatus.fromString('REJECTED'), equals(BookingStatus.rejected));
      expect(BookingStatus.fromString('COMPLETED'), equals(BookingStatus.completed));
      expect(BookingStatus.fromString('CANCELLED'), equals(BookingStatus.cancelled));

      expect(GymKeyStatus.fromString('KEY_WITH_GUARD'), equals(GymKeyStatus.keyWithGuard));
      expect(GymKeyStatus.fromString('KEY_ISSUED'), equals(GymKeyStatus.keyIssued));
      expect(GymKeyStatus.fromString('KEY_RETURNED'), equals(GymKeyStatus.keyReturned));
    });
  });

  group('4. Gym Key State Transitions & Date Helpers', () {
    test('formatDate and parseDate work symmetrically', () {
      final date = DateTime(2026, 11, 25);
      final formatted = AmenityBookingService.formatDate(date);
      expect(formatted, equals('2026-11-25'));

      final parsed = AmenityBookingService.parseDate(formatted);
      expect(parsed.year, equals(2026));
      expect(parsed.month, equals(11));
      expect(parsed.day, equals(25));
    });

    test('Gym booking key workflow status labels are clear for guards', () {
      expect(GymKeyStatus.keyWithGuard.displayName, equals('Key with Guard'));
      expect(GymKeyStatus.keyIssued.displayName, equals('Key Issued (Active)'));
      expect(GymKeyStatus.keyReturned.displayName, equals('Key Returned (Done)'));
    });
  });

  group('5. Passed Gym Slot Filtering & Time Boundary Tests', () {
    final today = DateTime(2026, 9, 24);
    // Simulated current clock: 1:28 PM on 2026-09-24 (matching the user's screenshot)
    final clockAt128Pm = DateTime(2026, 9, 24, 13, 28);

    test('parseSlotStartTime and parseSlotEndTime parse AM and PM accurately', () {
      final start6Am = AmenityBookingService.parseSlotStartTime(today, '06:00 AM - 07:00 AM');
      expect(start6Am, equals(DateTime(2026, 9, 24, 6, 0)));

      final end6Am = AmenityBookingService.parseSlotEndTime(today, '06:00 AM - 07:00 AM');
      expect(end6Am, equals(DateTime(2026, 9, 24, 7, 0)));

      final start12Pm = AmenityBookingService.parseSlotStartTime(today, '12:00 PM - 01:00 PM');
      expect(start12Pm, equals(DateTime(2026, 9, 24, 12, 0)));

      final end12Pm = AmenityBookingService.parseSlotEndTime(today, '12:00 PM - 01:00 PM');
      expect(end12Pm, equals(DateTime(2026, 9, 24, 13, 0)));

      final start1Pm = AmenityBookingService.parseSlotStartTime(today, '01:00 PM - 02:00 PM');
      expect(start1Pm, equals(DateTime(2026, 9, 24, 13, 0)));

      final end9Pm = AmenityBookingService.parseSlotEndTime(today, '09:00 PM - 10:00 PM');
      expect(end9Pm, equals(DateTime(2026, 9, 24, 22, 0)));
    });

    test('isSlotPassed returns true for all slots on past dates', () {
      final yesterday = DateTime(2026, 9, 23);
      expect(
        AmenityBookingService.isSlotPassed(yesterday, '06:00 AM - 07:00 AM', now: clockAt128Pm),
        isTrue,
      );
      expect(
        AmenityBookingService.isSlotPassed(yesterday, '08:00 PM - 09:00 PM', now: clockAt128Pm),
        isTrue,
      );
    });

    test('isSlotPassed returns false for all slots on future dates', () {
      final tomorrow = DateTime(2026, 9, 25);
      expect(
        AmenityBookingService.isSlotPassed(tomorrow, '06:00 AM - 07:00 AM', now: clockAt128Pm),
        isFalse,
      );
      expect(
        AmenityBookingService.isSlotPassed(tomorrow, '08:00 PM - 09:00 PM', now: clockAt128Pm),
        isFalse,
      );
    });

    test('At 1:28 PM today: morning and elapsed slots are marked passed', () {
      // 06:00 AM - 07:00 AM ended at 7 AM -> passed
      expect(
        AmenityBookingService.isSlotPassed(today, '06:00 AM - 07:00 AM', now: clockAt128Pm),
        isTrue,
      );

      // 12:00 PM - 01:00 PM ended at 1:00 PM -> passed
      expect(
        AmenityBookingService.isSlotPassed(today, '12:00 PM - 01:00 PM', now: clockAt128Pm),
        isTrue,
      );
    });

    test('At 1:28 PM today: ongoing slot 01:00 PM - 02:00 PM behavior', () {
      // Unbooked ongoing slot started at 1:00 PM (< 1:28 PM) -> marked passed so cannot be booked late
      expect(
        AmenityBookingService.isSlotPassed(today, '01:00 PM - 02:00 PM', now: clockAt128Pm, isCurrentResidentBooking: false),
        isTrue,
      );

      // Active ongoing workout booked earlier by this resident -> kept visible until 2:00 PM
      expect(
        AmenityBookingService.isSlotPassed(today, '01:00 PM - 02:00 PM', now: clockAt128Pm, isCurrentResidentBooking: true),
        isFalse,
      );
    });

    test('At 1:28 PM today: future slots remain open and available', () {
      expect(
        AmenityBookingService.isSlotPassed(today, '02:00 PM - 03:00 PM', now: clockAt128Pm),
        isFalse,
      );
      expect(
        AmenityBookingService.isSlotPassed(today, '06:00 PM - 07:00 PM', now: clockAt128Pm),
        isFalse,
      );
    });

    test('bookAmenity rejects reservation attempt for a passed gym slot', () async {
      expect(
        () => AmenityBookingService.bookAmenity(
          amenityType: AmenityType.gym,
          startDate: DateTime(2026, 9, 20), // past date
          slot: '06:00 AM - 07:00 AM',
          flatNumber: 'A-101',
          residentUid: 'user_123',
          residentName: 'Test Resident',
          residentPhone: '9999999999',
          occasionPurpose: 'Gym Workout',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Cannot reserve a gym slot that has already passed'),
        )),
      );
    });
  });
}

