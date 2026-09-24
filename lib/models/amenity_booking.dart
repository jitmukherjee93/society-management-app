import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================================
// AMENITY & FACILITY BOOKING DATA MODEL
// ============================================================================
// Represents a resident's booking for society facilities:
// 1. Community Hall: ₹4,000/day, ₹200 advance, min 2 days advance notice.
// 2. Society Ground: ₹500 for 2 days (₹250/day), min 2 days advance notice.
// 3. Society Gym: Free 1-hour slots, tracked with Guard key handover.
// ============================================================================

/// Identifies the specific society amenity
enum AmenityType {
  communityHall,
  openGround,
  gym;

  String get id {
    switch (this) {
      case AmenityType.communityHall:
        return 'COMMUNITY_HALL';
      case AmenityType.openGround:
        return 'OPEN_GROUND';
      case AmenityType.gym:
        return 'GYM';
    }
  }

  String get displayName {
    switch (this) {
      case AmenityType.communityHall:
        return 'Community Hall';
      case AmenityType.openGround:
        return 'Society Ground';
      case AmenityType.gym:
        return 'Fitness Gym';
    }
  }

  static AmenityType fromId(String id) {
    switch (id.toUpperCase()) {
      case 'OPEN_GROUND':
        return AmenityType.openGround;
      case 'GYM':
        return AmenityType.gym;
      case 'COMMUNITY_HALL':
      default:
        return AmenityType.communityHall;
    }
  }

  static AmenityType fromString(String id) => fromId(id);
}

/// Status of an amenity booking
enum BookingStatus {
  pendingApproval,
  confirmed,
  rejected,
  completed,
  cancelled;

  String get value {
    switch (this) {
      case BookingStatus.pendingApproval:
        return 'PENDING_APPROVAL';
      case BookingStatus.confirmed:
        return 'CONFIRMED';
      case BookingStatus.rejected:
        return 'REJECTED';
      case BookingStatus.completed:
        return 'COMPLETED';
      case BookingStatus.cancelled:
        return 'CANCELLED';
    }
  }

  String get displayName {
    switch (this) {
      case BookingStatus.pendingApproval:
        return 'Pending Approval';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.rejected:
        return 'Rejected';
      case BookingStatus.completed:
        return 'Completed';
      case BookingStatus.cancelled:
        return 'Cancelled';
    }
  }

  static BookingStatus fromString(String? str) {
    switch ((str ?? '').toUpperCase()) {
      case 'CONFIRMED':
        return BookingStatus.confirmed;
      case 'REJECTED':
        return BookingStatus.rejected;
      case 'COMPLETED':
        return BookingStatus.completed;
      case 'CANCELLED':
        return BookingStatus.cancelled;
      case 'PENDING_APPROVAL':
      default:
        return BookingStatus.pendingApproval;
    }
  }
}

/// Status of the Gym physical key held at the security gate
enum GymKeyStatus {
  keyWithGuard,
  keyIssued,
  keyReturned;

  String get value {
    switch (this) {
      case GymKeyStatus.keyWithGuard:
        return 'KEY_WITH_GUARD';
      case GymKeyStatus.keyIssued:
        return 'KEY_ISSUED';
      case GymKeyStatus.keyReturned:
        return 'KEY_RETURNED';
    }
  }

  String get displayName {
    switch (this) {
      case GymKeyStatus.keyWithGuard:
        return 'Key with Guard';
      case GymKeyStatus.keyIssued:
        return 'Key Issued (Active)';
      case GymKeyStatus.keyReturned:
        return 'Key Returned (Done)';
    }
  }

  static GymKeyStatus fromString(String? str) {
    switch ((str ?? '').toUpperCase()) {
      case 'KEY_ISSUED':
        return GymKeyStatus.keyIssued;
      case 'KEY_RETURNED':
        return GymKeyStatus.keyReturned;
      case 'KEY_WITH_GUARD':
      default:
        return GymKeyStatus.keyWithGuard;
    }
  }
}

/// Represents an individual amenity booking document
class AmenityBooking {
  final String id;
  final AmenityType amenityType;
  final String bookingDate; // Canonical format: YYYY-MM-DD
  final String? endDate; // Canonical format: YYYY-MM-DD (for multi-day ground bookings)
  final String? slot; // e.g. "07:00 AM - 08:00 AM" (strictly for Gym)
  final String flatNumber;
  final String residentUid;
  final String residentName;
  final String residentPhone;
  final String occasionPurpose;
  final double totalAmount;
  final double advancePaid;
  final double balanceDue;
  final String? paymentRef;
  final BookingStatus status;
  final GymKeyStatus keyStatus;

  /// Helper getter returning human-readable amenity name
  String get amenityName => amenityType.displayName;

  final DateTime? keyIssuedAt;
  final DateTime? keyReturnedAt;
  final String? keyIssuedByGuard;
  final String? keyReceivedByGuard;
  final String? adminRemarks;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const AmenityBooking({
    required this.id,
    required this.amenityType,
    required this.bookingDate,
    this.endDate,
    this.slot,
    required this.flatNumber,
    required this.residentUid,
    required this.residentName,
    required this.residentPhone,
    required this.occasionPurpose,
    required this.totalAmount,
    required this.advancePaid,
    required this.balanceDue,
    this.paymentRef,
    required this.status,
    this.keyStatus = GymKeyStatus.keyWithGuard,
    this.keyIssuedAt,
    this.keyReturnedAt,
    this.keyIssuedByGuard,
    this.keyReceivedByGuard,
    this.adminRemarks,
    required this.createdAt,
    this.updatedAt,
  });

  /// Factory constructor parsing Firestore document snapshot
  factory AmenityBooking.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AmenityBooking.fromMap(doc.id, data);
  }

  /// Flexible factory constructor parsing raw Map data (supports both (id, map) and (map, id))
  factory AmenityBooking.fromMap(dynamic first, [dynamic second]) {
    final String id = first is String ? first : (second is String ? second : '');
    final Map<String, dynamic> data = first is Map<String, dynamic>
        ? first
        : (second is Map<String, dynamic> ? second : {});

    return AmenityBooking(
      id: id,
      amenityType: AmenityType.fromId(data['amenityId']?.toString() ?? ''),
      bookingDate: (data['bookingDate'] ?? '').toString(),
      endDate: data['endDate']?.toString(),
      slot: data['slot']?.toString(),
      flatNumber: (data['flatNumber'] ?? '').toString(),
      residentUid: (data['residentUid'] ?? '').toString(),
      residentName: (data['residentName'] ?? 'Resident').toString(),
      residentPhone: (data['residentPhone'] ?? '').toString(),
      occasionPurpose: (data['occasionPurpose'] ?? 'Personal / Fitness').toString(),
      totalAmount: ((data['totalAmount'] ?? 0.0) as num).toDouble(),
      advancePaid: ((data['advancePaid'] ?? 0.0) as num).toDouble(),
      balanceDue: ((data['balanceDue'] ?? 0.0) as num).toDouble(),
      paymentRef: data['paymentRef']?.toString(),
      status: BookingStatus.fromString(data['status']?.toString()),
      keyStatus: GymKeyStatus.fromString(data['keyStatus']?.toString()),
      keyIssuedAt: data['keyIssuedAt'] is Timestamp ? (data['keyIssuedAt'] as Timestamp).toDate() : null,
      keyReturnedAt: data['keyReturnedAt'] is Timestamp ? (data['keyReturnedAt'] as Timestamp).toDate() : null,
      keyIssuedByGuard: data['keyIssuedByGuard']?.toString(),
      keyReceivedByGuard: data['keyReceivedByGuard']?.toString(),
      adminRemarks: data['adminRemarks']?.toString(),
      // Resilient parsing: accepts both Firestore Timestamps and client DateTime/FieldValue objects without casting errors
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : (data['createdAt'] is DateTime ? data['createdAt'] as DateTime : DateTime.now()),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : (data['updatedAt'] is DateTime ? data['updatedAt'] as DateTime : null),
    );
  }

  /// Converts booking object into a serializable Map for Firestore writes
  Map<String, dynamic> toMap() {
    return {
      'amenityId': amenityType.id,
      'amenityName': amenityType.displayName,
      'bookingDate': bookingDate,
      if (endDate != null) 'endDate': endDate,
      if (slot != null) 'slot': slot,
      'flatNumber': flatNumber,
      'residentUid': residentUid,
      'residentName': residentName,
      'residentPhone': residentPhone,
      'occasionPurpose': occasionPurpose,
      'totalAmount': totalAmount,
      'advancePaid': advancePaid,
      'balanceDue': balanceDue,
      if (paymentRef != null) 'paymentRef': paymentRef,
      'status': status.value,
      'keyStatus': keyStatus.value,
      if (keyIssuedAt != null) 'keyIssuedAt': Timestamp.fromDate(keyIssuedAt!),
      if (keyReturnedAt != null) 'keyReturnedAt': Timestamp.fromDate(keyReturnedAt!),
      if (keyIssuedByGuard != null) 'keyIssuedByGuard': keyIssuedByGuard,
      if (keyReceivedByGuard != null) 'keyReceivedByGuard': keyReceivedByGuard,
      if (adminRemarks != null) 'adminRemarks': adminRemarks,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  AmenityBooking copyWith({
    BookingStatus? status,
    GymKeyStatus? keyStatus,
    DateTime? keyIssuedAt,
    DateTime? keyReturnedAt,
    String? keyIssuedByGuard,
    String? keyReceivedByGuard,
    String? adminRemarks,
    double? advancePaid,
    double? balanceDue,
    String? paymentRef,
  }) {
    return AmenityBooking(
      id: id,
      amenityType: amenityType,
      bookingDate: bookingDate,
      endDate: endDate,
      slot: slot,
      flatNumber: flatNumber,
      residentUid: residentUid,
      residentName: residentName,
      residentPhone: residentPhone,
      occasionPurpose: occasionPurpose,
      totalAmount: totalAmount,
      advancePaid: advancePaid ?? this.advancePaid,
      balanceDue: balanceDue ?? this.balanceDue,
      paymentRef: paymentRef ?? this.paymentRef,
      status: status ?? this.status,
      keyStatus: keyStatus ?? this.keyStatus,
      keyIssuedAt: keyIssuedAt ?? this.keyIssuedAt,
      keyReturnedAt: keyReturnedAt ?? this.keyReturnedAt,
      keyIssuedByGuard: keyIssuedByGuard ?? this.keyIssuedByGuard,
      keyReceivedByGuard: keyReceivedByGuard ?? this.keyReceivedByGuard,
      adminRemarks: adminRemarks ?? this.adminRemarks,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
