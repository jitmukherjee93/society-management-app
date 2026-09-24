import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../models/amenity_booking.dart';
import 'notification_service.dart';

// ============================================================================
// AMENITY BOOKING SERVICE
// ============================================================================
// Central service orchestrating bookings for:
// - Community Hall: ₹4,000/day, ₹200 advance, minimum 2 days prior notice.
// - Society Ground: ₹500 for 2 days (₹250/day), minimum 2 days prior notice.
// - Fitness Gym: Free 1-hour slots, tracked with Guard physical key handover.
// ============================================================================

class AmenityBookingService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// Canonical date string formatter (YYYY-MM-DD)
  static String formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Parses canonical YYYY-MM-DD string back to DateTime
  static DateTime parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length == 3) {
      return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    }
    return DateTime.now();
  }

  /// Extracts the start DateTime for a given slot string on a target date.
  /// Example: slot "01:00 PM - 02:00 PM" on 2026-09-24 -> DateTime(2026, 9, 24, 13, 0)
  static DateTime? parseSlotStartTime(DateTime date, String slot) {
    try {
      final parts = slot.split(' - ');
      if (parts.isEmpty) return null;
      final timeStr = parts[0].trim();
      final parsed = DateFormat('hh:mm a').parse(timeStr);
      return DateTime(date.year, date.month, date.day, parsed.hour, parsed.minute);
    } catch (_) {
      return null;
    }
  }

  /// Extracts the end DateTime for a given slot string on a target date.
  /// Example: slot "01:00 PM - 02:00 PM" on 2026-09-24 -> DateTime(2026, 9, 24, 14, 0)
  static DateTime? parseSlotEndTime(DateTime date, String slot) {
    try {
      final parts = slot.split(' - ');
      if (parts.length < 2) return null;
      final timeStr = parts[1].trim();
      final parsed = DateFormat('hh:mm a').parse(timeStr);
      return DateTime(date.year, date.month, date.day, parsed.hour, parsed.minute);
    } catch (_) {
      return null;
    }
  }

  /// Determines whether a gym slot on a target date has already passed.
  /// - Past dates (before today): All slots are passed (returns true).
  /// - Future dates (after today): No slots are passed (returns false).
  /// - Today:
  ///   - Any slot whose end time has elapsed is strictly passed (returns true).
  ///   - Any unbooked slot whose start time has already passed is passed (returns true).
  ///   - If [isCurrentResidentBooking] is true and the slot's end time hasn't arrived yet,
  ///     returns false so the resident can monitor their active workout and key status.
  static bool isSlotPassed(
    DateTime targetDate,
    String slot, {
    DateTime? now,
    bool isCurrentResidentBooking = false,
  }) {
    final current = now ?? DateTime.now();
    final targetDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final today = DateTime(current.year, current.month, current.day);

    // 1. Entire day is in the past
    if (targetDay.isBefore(today)) {
      return true;
    }

    // 2. Future day: no slots have passed
    if (targetDay.isAfter(today)) {
      return false;
    }

    // 3. Today: evaluate slot boundaries against current clock
    final endTime = parseSlotEndTime(targetDate, slot);
    if (endTime != null && current.isAfter(endTime)) {
      // Slot has completely finished
      return true;
    }

    final startTime = parseSlotStartTime(targetDate, slot);
    if (startTime != null && current.isAfter(startTime)) {
      // Slot has already started.
      // If the current resident has booked this slot and it's currently active, keep it visible.
      if (isCurrentResidentBooking) {
        return false;
      }
      return true;
    }

    return false;
  }

  /// Validates whether a booking date meets the mandatory 2-day advance notice rule.
  /// Rule: Bookings for Community Hall and Society Ground must be made at least 2 days prior.
  static bool isLeadTimeValid(DateTime targetDate, [DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    return target.difference(today).inDays >= 2;
  }

  /// Calculates total charges and advance required for a booking.
  /// - Community Hall: ₹4,000 / day, ₹200 advance.
  /// - Society Ground: Minimum 2 days required (₹500 for first 2 days, ₹250/day thereafter, ₹200 advance).
  /// - Gym: ₹0 (Free).
  static Map<String, double> calculateBookingFee({
    required AmenityType amenityType,
    int numberOfDays = 1,
  }) {
    // Defensively clamp days to at least 1 to prevent negative or zero accounting anomalies
    final int days = numberOfDays.clamp(1, 30);

    switch (amenityType) {
      case AmenityType.communityHall:
        final total = 4000.0 * days;
        const advance = 200.0;
        return {
          'totalAmount': total,
          'advancePaid': advance,
          'balanceDue': total - advance,
        };
      case AmenityType.openGround:
        // Society Ground: Must be booked for at least 2 days (₹500 for 2 days, ₹250/day thereafter)
        final effectiveDays = days < 2 ? 2 : days;
        final total = 250.0 * effectiveDays;
        const advance = 200.0;
        return {
          'totalAmount': total,
          'advancePaid': advance,
          'balanceDue': total - advance,
        };
      case AmenityType.gym:
        return {
          'totalAmount': 0.0,
          'advancePaid': 0.0,
          'balanceDue': 0.0,
        };
    }
  }

  /// Submits an amenity booking request.
  /// Enforces lead-time validation, minimum duration, date/slot collisions, and saves booking.
  static Future<String> bookAmenity({
    required AmenityType amenityType,
    required DateTime startDate,
    DateTime? endDate,
    String? slot,
    required String flatNumber,
    required String residentUid,
    required String residentName,
    required String residentPhone,
    required String occasionPurpose,
    String? paymentRef,
  }) async {
    final dateStr = formatDate(startDate);
    final days = endDate != null ? (endDate.difference(startDate).inDays + 1).clamp(1, 10) : 1;
    final endDateStr = endDate != null ? formatDate(endDate) : dateStr;

    // 1. Enforce minimum 2 days duration rule for Society Ground
    if (amenityType == AmenityType.openGround && days < 2) {
      throw Exception('Society Ground must be booked for a minimum of 2 days.');
    }

    // 2. Enforce 2-day lead time rule for full-day facilities (Hall & Ground)
    if (amenityType != AmenityType.gym) {
      if (!isLeadTimeValid(startDate)) {
        throw Exception(
          'Bookings for ${amenityType.displayName} must be reserved at least 2 days prior to the occasion.',
        );
      }
    }

    // 3. Strictly disallow booking gym time slots that have already passed
    if (amenityType == AmenityType.gym && slot != null) {
      if (isSlotPassed(startDate, slot)) {
        throw Exception('Cannot reserve a gym slot that has already passed ($slot).');
      }
    }

    // 4. Prevent date / slot collisions across the entire requested date range
    final targetStart = DateTime(startDate.year, startDate.month, startDate.day);
    final targetEnd = endDate != null ? DateTime(endDate.year, endDate.month, endDate.day) : targetStart;

    final allSnap = await _fs
        .collection('amenity_bookings')
        .where('amenityId', isEqualTo: amenityType.id)
        .get();

    for (final doc in allSnap.docs) {
      final status = (doc.data()['status'] ?? '').toString().toUpperCase();
      if (status == 'CANCELLED' || status == 'REJECTED') continue;

      if (amenityType == AmenityType.gym) {
        final existingDateStr = (doc.data()['bookingDate'] ?? '').toString();
        final docSlot = (doc.data()['slot'] ?? '').toString();
        if (existingDateStr == dateStr && docSlot == (slot ?? '')) {
          final existingFlat = doc.data()['flatNumber'] ?? 'Another resident';
          throw Exception('This slot ($slot) is already reserved by Flat $existingFlat.');
        }
      } else {
        final existingStartStr = (doc.data()['bookingDate'] ?? '').toString();
        final existingEndStr = (doc.data()['endDate'] ?? existingStartStr).toString();
        if (existingStartStr.isEmpty) continue;

        final existingStart = parseDate(existingStartStr);
        final existingEnd = parseDate(existingEndStr);

        // Date interval overlap check: [targetStart, targetEnd] overlaps [existingStart, existingEnd]
        if (!targetStart.isAfter(existingEnd) && !existingStart.isAfter(targetEnd)) {
          final existingFlat = doc.data()['flatNumber'] ?? 'Another resident';
          final rangeLabel = existingStartStr == existingEndStr ? existingStartStr : '$existingStartStr to $existingEndStr';
          throw Exception(
            '${amenityType.displayName} is already reserved by Flat $existingFlat on $rangeLabel.',
          );
        }
      }
    }

    // 4. Compute fees
    final fees = calculateBookingFee(amenityType: amenityType, numberOfDays: days);

    // Gym bookings are free and auto-confirmed; Hall & Ground require Admin approval of advance
    final initialStatus = amenityType == AmenityType.gym
        ? BookingStatus.confirmed
        : BookingStatus.pendingApproval;

    final docRef = _fs.collection('amenity_bookings').doc();
    final booking = AmenityBooking(
      id: docRef.id,
      amenityType: amenityType,
      bookingDate: dateStr,
      endDate: endDate != null ? endDateStr : null,
      slot: slot,
      flatNumber: flatNumber,
      residentUid: residentUid,
      residentName: residentName,
      residentPhone: residentPhone,
      occasionPurpose: occasionPurpose,
      totalAmount: fees['totalAmount']!,
      advancePaid: fees['advancePaid']!,
      balanceDue: fees['balanceDue']!,
      paymentRef: paymentRef,
      status: initialStatus,
      keyStatus: GymKeyStatus.keyWithGuard,
      createdAt: DateTime.now(),
    );

    await docRef.set(booking.toMap());

    // 4. Notifications
    if (amenityType == AmenityType.gym) {
      await NotificationService.notifyResident(
        flatNumber: flatNumber,
        targetUid: residentUid,
        title: '🏋️ Gym Slot Confirmed: $dateStr',
        message: 'Your 1-hour gym slot ($slot) on $dateStr is confirmed! Please collect the gym key from security gate before starting.',
        type: 'GENERAL',
        extraData: {'bookingId': docRef.id, 'amenity': 'GYM'},
      );
    } else {
      // Alert Admins for review of Hall / Ground booking
      await NotificationService.notifyAdmin(
        title: '🏛️ New Booking Request: ${amenityType.displayName}',
        message: 'Flat $flatNumber requested ${amenityType.displayName} for $dateStr ($occasionPurpose). Advance Ref: ${paymentRef ?? "None"}. Tap to verify and confirm.',
        type: 'ANNOUNCEMENT',
        extraData: {
          'bookingId': docRef.id,
          'flatNumber': flatNumber,
          'amenity': amenityType.id,
          'bookingDate': dateStr,
        },
      );
    }

    return docRef.id;
  }

  /// Cancels an existing booking
  static Future<void> cancelBooking(String bookingId, String reason) async {
    await _fs.collection('amenity_bookings').doc(bookingId).update({
      'status': BookingStatus.cancelled.value,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancellationReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin approval of Community Hall / Ground booking
  static Future<void> adminApproveBooking({
    required String bookingId,
    required String adminUid,
    String? remarks,
  }) async {
    final docRef = _fs.collection('amenity_bookings').doc(bookingId);
    final docSnap = await docRef.get();
    if (!docSnap.exists) throw Exception('Booking document not found');

    final data = docSnap.data() ?? {};
    final flatNumber = (data['flatNumber'] ?? '').toString();
    final residentUid = data['residentUid']?.toString();
    final amenityName = (data['amenityName'] ?? 'Facility').toString();
    final bookingDate = (data['bookingDate'] ?? '').toString();

    final updatePayload = <String, dynamic>{
      'status': BookingStatus.confirmed.value,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (remarks != null && remarks.isNotEmpty) {
      updatePayload['adminRemarks'] = remarks;
    }
    await docRef.update(updatePayload);

    await NotificationService.notifyResident(
      flatNumber: flatNumber,
      targetUid: residentUid,
      title: '🎉 Booking Confirmed: $amenityName',
      message: 'Your booking for $amenityName on $bookingDate has been confirmed by Society Admin! Balance payment can be cleared at the society office.',
      type: 'GENERAL',
      extraData: {'bookingId': bookingId},
    );
  }

  /// Admin rejection of booking
  static Future<void> adminRejectBooking({
    required String bookingId,
    required String adminUid,
    required String reason,
  }) async {
    final docRef = _fs.collection('amenity_bookings').doc(bookingId);
    final docSnap = await docRef.get();
    if (!docSnap.exists) throw Exception('Booking document not found');

    final data = docSnap.data() ?? {};
    final flatNumber = (data['flatNumber'] ?? '').toString();
    final residentUid = data['residentUid']?.toString();
    final amenityName = (data['amenityName'] ?? 'Facility').toString();
    final bookingDate = (data['bookingDate'] ?? '').toString();

    await docRef.update({
      'status': BookingStatus.rejected.value,
      'rejectedAt': FieldValue.serverTimestamp(),
      'rejectedBy': adminUid,
      'adminRemarks': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await NotificationService.notifyResident(
      flatNumber: flatNumber,
      targetUid: residentUid,
      title: '❌ Booking Declined: $amenityName',
      message: 'Your booking for $amenityName on $bookingDate was declined by Admin. Reason: $reason.',
      type: 'GENERAL',
      extraData: {'bookingId': bookingId},
    );
  }

  /// Guard records physical key handover to resident (`KEY_ISSUED`)
  static Future<void> guardIssueGymKey({
    required String bookingId,
    required String guardUid,
    required String guardName,
  }) async {
    await _fs.collection('amenity_bookings').doc(bookingId).update({
      'keyStatus': GymKeyStatus.keyIssued.value,
      'keyIssuedAt': FieldValue.serverTimestamp(),
      'keyIssuedByGuard': guardName,
      'keyIssuedByGuardUid': guardUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Guard records physical key returned by resident (`KEY_RETURNED`)
  static Future<void> guardReceiveGymKey({
    required String bookingId,
    required String guardUid,
    required String guardName,
  }) async {
    await _fs.collection('amenity_bookings').doc(bookingId).update({
      'keyStatus': GymKeyStatus.keyReturned.value,
      'keyReturnedAt': FieldValue.serverTimestamp(),
      'keyReceivedByGuard': guardName,
      'keyReceivedByGuardUid': guardUid,
      'status': BookingStatus.completed.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Allows a resident to unregister / cancel their active gym slot booking.
  /// Validates:
  /// 1. Booking exists and belongs to the resident (or resident is authorized).
  /// 2. Key has not already been physically issued (`KEY_ISSUED`). If key is issued, resident must return it first.
  /// 3. Updates status to `CANCELLED` and notifies resident & guard.
  static Future<void> unregisterGymBooking({
    required String bookingId,
    required String residentUid,
  }) async {
    final docRef = _fs.collection('amenity_bookings').doc(bookingId);
    final snap = await docRef.get();
    if (!snap.exists) throw Exception('Booking not found');

    final data = snap.data() ?? {};
    final existingUid = (data['residentUid'] ?? '').toString();
    if (existingUid.isNotEmpty && existingUid != residentUid) {
      throw Exception('You are not authorized to cancel this reservation.');
    }

    final keyStatus = (data['keyStatus'] ?? '').toString().toUpperCase();
    if (keyStatus == GymKeyStatus.keyIssued.value) {
      throw Exception('Cannot cancel slot: Key has already been issued. Please return key to Guard first.');
    }

    final flatNumber = (data['flatNumber'] ?? '').toString();
    final slot = (data['slot'] ?? '').toString();
    final bookingDate = (data['bookingDate'] ?? '').toString();

    await docRef.update({
      'status': BookingStatus.cancelled.value,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': residentUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await NotificationService.notifyResident(
        flatNumber: flatNumber,
        targetUid: residentUid,
        title: 'Gym Slot Unregistered',
        message: 'Your gym slot reservation ($slot on $bookingDate) has been cancelled.',
        type: 'GENERAL',
        extraData: {'bookingId': bookingId},
      );
    } catch (e) {
      debugPrint('[AmenityBookingService] Error notifying resident on unregister: $e');
    }
  }

  /// Stream of bookings for a specific amenity and month (cached for calendar display)
  static Stream<List<AmenityBooking>> getBookingsStream({
    required AmenityType amenityType,
    required int year,
    required int month,
  }) {
    final startStr = '$year-${month.toString().padLeft(2, '0')}-01';
    final nextMonth = month == 12 ? 1 : month + 1;
    final nextYear = month == 12 ? year + 1 : year;
    final endStr = '$nextYear-${nextMonth.toString().padLeft(2, '0')}-01';

    // Query by amenityId only (single-field index, never requires composite index)
    // and filter date range in memory for maximum speed and zero index prerequisites.
    return _fs
        .collection('amenity_bookings')
        .where('amenityId', isEqualTo: amenityType.id)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AmenityBooking.fromFirestore(d))
            .where((b) => b.bookingDate.compareTo(startStr) >= 0 && b.bookingDate.compareTo(endStr) < 0)
            .toList());
  }

  /// Admin records balance payment collection and closes balance dues
  static Future<void> adminCollectBalancePayment({
    required String bookingId,
    required String adminUid,
    required String adminName,
    required double amountPaid,
    required String paymentMode,
    String? referenceNumber,
  }) async {
    final docRef = _fs.collection('amenity_bookings').doc(bookingId);
    final snap = await docRef.get();
    if (!snap.exists) throw Exception('Booking not found');

    final data = snap.data() ?? {};
    final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
    final advancePaid = (data['advancePaid'] as num?)?.toDouble() ?? 0.0;
    final flatNumber = (data['flatNumber'] ?? '').toString();
    final amenityName = (data['amenityName'] ?? 'Facility').toString();
    final occasionPurpose = (data['occasionPurpose'] ?? '').toString();

    final newAdvancePaid = advancePaid + amountPaid;
    final newBalanceDue = (totalAmount - newAdvancePaid).clamp(0.0, double.infinity);

    // 1. Update booking record
    await docRef.update({
      'advancePaid': newAdvancePaid,
      'balanceDue': newBalanceDue,
      'balancePaidAt': FieldValue.serverTimestamp(),
      'balancePaymentMode': paymentMode,
      'balanceReferenceNumber': referenceNumber,
      'balanceReceivedBy': adminName,
      'balanceReceivedByUid': adminUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 2. Add ledger entry to society_transactions as facility income
    try {
      await _fs.collection('society_transactions').add({
        'type': 'INCOME',
        'category': 'AMENITY_FEE',
        'head': 'Facility & Amenity Charges',
        'amount': amountPaid,
        'description': '$amenityName payment from Flat $flatNumber ($occasionPurpose)',
        'flatNumber': flatNumber,
        'bookingId': bookingId,
        'paymentMode': paymentMode,
        'referenceNumber': referenceNumber ?? 'OFFICE-CASH',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': adminName,
        'createdByUid': adminUid,
      });
    } catch (e) {
      debugPrint('[AmenityBookingService] Note on ledger income write: $e');
    }
  }

  /// Stream of all amenity bookings for the Admin Management interface
  static Stream<List<AmenityBooking>> getAllBookingsStream({int limit = 100}) {
    return _fs
        .collection('amenity_bookings')
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => AmenityBooking.fromFirestore(d)).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list.take(limit).toList();
        });
  }

  /// Stream of today's Gym bookings for the Guard Key Management interface
  static Stream<List<AmenityBooking>> getTodayGymBookingsStream() {
    final todayStr = formatDate(DateTime.now());
    return _fs
        .collection('amenity_bookings')
        .where('amenityId', isEqualTo: AmenityType.gym.id)
        .where('bookingDate', isEqualTo: todayStr)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AmenityBooking.fromFirestore(d)).toList());
  }
}
