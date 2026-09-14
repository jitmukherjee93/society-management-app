import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../utils/flat_utils.dart';
import 'notification_service.dart';

// ============================================================================
// VISITOR PASS & SECURITY MANAGEMENT SERVICE
// ============================================================================
// This service handles the end-to-end security gate workflows:
//
// 1. Resident Pre-Approved Pass Generation:
//    - Residents generate a 6-digit numeric passcode for incoming guests/cabs.
//    - Validity: Strictly 8 hours from generation timestamp.
//    - Single-Use Enforcement: Once verified and checked in at the gate, the pass
//      cannot be used again (`isUsed: true`, `status: CHECKED_IN`).
//
// 2. Security Guard Gate Check-In & Walk-In Logging:
//    - 6-digit OTP verification against the Firestore `visitors` collection.
//    - Walk-in / Delivery agent entry logging with camera photo upload to Firebase Storage.
//    - Real-time resident push notifications on guest entry and exit.
//
// 3. Parcel Management:
//    - Logging parcels left at security gate (`gate_parcels` collection).
//    - Resident handover verification (`status: COLLECTED`).
//
// 4. Emergency Broadcasts (SOS):
//    - Security emergency triggers broadcasted to all residents and admins.
// ============================================================================

/// Pass verification status identifying why a code is accepted or rejected
enum PassVerificationStatus {
  /// Pass is active, within 8-hour validity window, and unused.
  valid,

  /// Pass was already used for entry and cannot be re-used.
  alreadyUsed,

  /// Pass has exceeded the 8-hour validity window.
  expired,

  /// Passcode does not exist or has been invalidated.
  invalid,
}

/// Comprehensive result object returned when a security guard verifies a 6-digit gate pass
class PassVerificationResult {
  /// Categorized verification outcome.
  final PassVerificationStatus status;

  /// Human-readable explanation suitable for display in guard modal/snackbar.
  final String message;

  /// Firestore document snapshot of the verified visitor record.
  final QueryDocumentSnapshot<Map<String, dynamic>>? document;

  /// Parsed visitor data map.
  final Map<String, dynamic>? data;

  const PassVerificationResult({
    required this.status,
    required this.message,
    this.document,
    this.data,
  });

  /// Returns `true` if the pass is valid and eligible for check-in.
  bool get isValid => status == PassVerificationStatus.valid;

  /// Returns `true` if the pass has already been consumed.
  bool get isAlreadyUsed => status == PassVerificationStatus.alreadyUsed;

  /// Returns `true` if the pass has expired.
  bool get isExpired => status == PassVerificationStatus.expired;

  /// Returns `true` if the pass was not found or is invalid.
  bool get isInvalid => status == PassVerificationStatus.invalid;
}

/// Centralized service for generating, validating, and managing security visitor gate passes
class VisitorPassService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// Default validity period for generated visitor gate passcodes (8 hours).
  static const int passValidityHours = 8;

  /// Generates a random 6-digit numeric OTP code (range 100000 to 999999).
  static String generatePassCode() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  /// Evaluates whether a visitor pass data map is active, expired, or already used.
  /// 
  /// Respects:
  /// - `isUsed == true` or `status == CHECKED_IN / CHECKED_OUT` -> [PassVerificationStatus.alreadyUsed]
  /// - `expiresAt` or 8 hours past `createdAt` -> [PassVerificationStatus.expired]
  /// - `status == PENDING` or empty -> [PassVerificationStatus.valid]
  static PassVerificationStatus evaluatePassStatus(Map<String, dynamic> data, {DateTime? currentTime}) {
    final now = currentTime ?? DateTime.now();
    final status = (data['status'] ?? '').toString().toUpperCase();
    final isUsed = data['isUsed'] == true || status == 'CHECKED_IN' || status == 'CHECKED_OUT';

    if (isUsed) {
      return PassVerificationStatus.alreadyUsed;
    }

    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate() ??
        createdAt?.add(const Duration(hours: passValidityHours));

    if (status == 'EXPIRED' || (expiresAt != null && now.isAfter(expiresAt))) {
      return PassVerificationStatus.expired;
    }

    if (status == 'PENDING' || status.isEmpty) {
      return PassVerificationStatus.valid;
    }

    return PassVerificationStatus.invalid;
  }

  /// Creates a pre-approved visitor pass entry in Firestore (`visitors` collection).
  ///
  /// The pass is generated with:
  /// - 6-digit numeric passcode.
  /// - 8-hour expiry timestamp.
  /// - Single-use flag initialized to `false`.
  /// - Status initialized to `PENDING`.
  static Future<Map<String, dynamic>> createVisitorPass({
    required String residentUid,
    required String flatNumber,
    required String visitorName,
    required String phone,
    String purpose = 'Guest / Personal',
    bool isComingByCar = false,
    String? vehicleNumber,
  }) async {
    final code = generatePassCode();
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: passValidityHours));
    final cleanVehicle = (vehicleNumber ?? '').trim().toUpperCase();
    final hasVehicle = isComingByCar || cleanVehicle.isNotEmpty;

    final docRef = await _fs.collection('visitors').add({
      'visitorName': visitorName.trim(),
      'phone': phone.trim(),
      'flatNumber': flatNumber.trim(),
      'hostFlatNumber': flatNumber.trim(),
      'residentUid': residentUid,
      'hostUid': residentUid,
      'purpose': purpose,
      'passCode': code,
      'isComingByCar': hasVehicle,
      'vehicleNumber': hasVehicle ? cleanVehicle : '',
      'status': 'PENDING', // PENDING -> CHECKED_IN (used) -> CHECKED_OUT, or EXPIRED
      'isUsed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'validForHours': passValidityHours,
    });

    return {
      'id': docRef.id,
      'passCode': code,
      'expiresAt': expiresAt,
      'validForHours': passValidityHours,
      'isComingByCar': hasVehicle,
      'vehicleNumber': cleanVehicle,
    };
  }

  // ─── Gate Passcode Verification & Check-In ──────────────────────────────────
  
  /// Verifies a 6-digit passcode for guard gate check-in.
  ///
  /// Checks against Firestore `visitors` collection matching `passCode`.
  /// Returns a [PassVerificationResult] classifying whether the pass is:
  /// - `valid`: Active and available for immediate entry.
  /// - `alreadyUsed`: Previously checked in.
  /// - `expired`: Beyond 8-hour issuance window.
  /// - `invalid`: Non-existent code.
  static Future<PassVerificationResult> verifyPassCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.length != 6) {
      return const PassVerificationResult(
        status: PassVerificationStatus.invalid,
        message: 'Passcode must be a 6-digit numeric code.',
      );
    }

    final snap = await _fs
        .collection('visitors')
        .where('passCode', isEqualTo: trimmed)
        .get();

    if (snap.docs.isEmpty) {
      return const PassVerificationResult(
        status: PassVerificationStatus.invalid,
        message: 'Invalid passcode. No matching gate pass found.',
      );
    }

    // Sort documents by createdAt descending in case of multiple passes
    final docs = snap.docs.toList();
    docs.sort((a, b) {
      final aTime = (a.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = (b.data()['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    final doc = docs.first;
    final data = doc.data();
    final vName = (data['visitorName'] ?? 'Guest').toString().trim();
    final flat = (data['hostFlatNumber'] ?? data['flatNumber'] ?? '').toString().trim();
    final now = DateTime.now();

    final status = evaluatePassStatus(data, currentTime: now);

    switch (status) {
      case PassVerificationStatus.alreadyUsed:
        final usedTime = (data['usedAt'] as Timestamp?)?.toDate() ??
            (data['entryTime'] as Timestamp?)?.toDate();
        final usedStr = usedTime != null ? DateFormat('hh:mm a, dd MMM').format(usedTime) : '';
        return PassVerificationResult(
          status: PassVerificationStatus.alreadyUsed,
          message: 'Passcode already used${usedStr.isNotEmpty ? ' at $usedStr' : ''} for $vName (Flat $flat). Gate passcodes are strictly single-use only.',
          document: doc,
          data: data,
        );

      case PassVerificationStatus.expired:
        // Update Firestore status to EXPIRED if not already marked
        if (data['status'] != 'EXPIRED') {
          try {
            await doc.reference.update({'status': 'EXPIRED'});
          } catch (_) {}
        }
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        final createdStr = createdAt != null ? DateFormat('hh:mm a, dd MMM').format(createdAt) : '';
        return PassVerificationResult(
          status: PassVerificationStatus.expired,
          message: 'Passcode expired (valid for 8 hours only${createdStr.isNotEmpty ? ', issued $createdStr' : ''}) for $vName (Flat $flat). Please ask resident to generate a new pass.',
          document: doc,
          data: data,
        );

      case PassVerificationStatus.valid:
        return PassVerificationResult(
          status: PassVerificationStatus.valid,
          message: 'Valid pass verified! Single-use pass active for entry.',
          document: doc,
          data: data,
        );

      case PassVerificationStatus.invalid:
        return const PassVerificationResult(
          status: PassVerificationStatus.invalid,
          message: 'Invalid or deactivated passcode.',
        );
    }
  }

  /// Marks a visitor pass as checked-in (`isUsed: true`, `status: CHECKED_IN`)
  /// and dispatches an instant push notification to the resident of the host flat.
  static Future<void> checkInVisitor({
    required String visitorDocId,
    required String? guardUid,
    String? guardName,
    String? gateName,
    Map<String, dynamic>? visitorData,
  }) async {
    await _fs.collection('visitors').doc(visitorDocId).update({
      'status': 'CHECKED_IN',
      'approvalStatus': 'APPROVED',
      'isUsed': true,
      'usedAt': FieldValue.serverTimestamp(),
      'entryTime': FieldValue.serverTimestamp(),
      'checkedInBy': guardUid,
      'guardName': guardName ?? 'Security Guard',
      'gateName': gateName ?? 'Main Gate',
    });

    Map<String, dynamic>? data = visitorData;
    if (data == null) {
      try {
        final docSnap = await _fs.collection('visitors').doc(visitorDocId).get();
        if (docSnap.exists) {
          data = docSnap.data();
        }
      } catch (_) {}
    }

    if (data != null) {
      final rawFlat = data['hostFlatNumber'] ?? data['flatNumber'] ?? '';
      final hostFlat = FlatUtils.normalize(rawFlat.toString());
      final visitorName = (data['visitorName'] ?? 'Guest').toString().trim();
      final purpose = (data['purpose'] ?? 'Guest / Personal').toString().trim();
      final residentUid = data['residentUid']?.toString() ?? data['hostUid']?.toString();
      final phone = (data['phone'] ?? '').toString().trim();
      final vehicleNumber = (data['vehicleNumber'] ?? '').toString().trim();
      final isComingByCar = data['isComingByCar'] == true || vehicleNumber.isNotEmpty;
      final gate = gateName ?? 'Main Gate';
      final guard = guardName ?? 'Security Guard';
      final vehicleInfo = isComingByCar && vehicleNumber.isNotEmpty ? ' with vehicle $vehicleNumber' : '';

      if (hostFlat.isNotEmpty || (residentUid != null && residentUid.isNotEmpty)) {
        await NotificationService.notifyResident(
          flatNumber: hostFlat,
          targetUid: residentUid,
          title: 'Pre-approved Guest Arrived: $visitorName',
          message: 'Your pre-approved guest $visitorName ($purpose) has checked in at $gate$vehicleInfo.',
          type: 'VISITOR_CHECK_IN',
          extraData: {
            'visitorDocId': visitorDocId,
            'visitorName': visitorName,
            'purpose': purpose,
            'phone': phone,
            'isComingByCar': isComingByCar,
            'vehicleNumber': vehicleNumber,
            'gateName': gate,
            'guardName': guard,
            'isPreApproved': true,
            'status': 'CHECKED_IN',
            'approvalStatus': 'APPROVED',
            'entryTime': DateTime.now().toIso8601String(),
          },
        );
      }
    }
  }

  // ─── Guard Walk-In & Photo Logging ───────────────────────────────────────

  /// Uploads a visitor verification photo to Firebase Storage and returns the public download URL.
  ///
  /// - Storage path: `visitors/{timestamp}_{guardUidPrefix}_{fileName}`
  /// - Sets `contentType: image/jpeg` and custom metadata for auditing.
  static Future<String> uploadVisitorPhoto({
    required Uint8List bytes,
    required String guardUid,
    String? fileName,
  }) async {
    final name = fileName ?? 'visitor_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance
        .ref()
        .child('visitors')
        .child('${DateTime.now().millisecondsSinceEpoch}_${guardUid.substring(0, min(8, guardUid.length))}_$name');
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'uploadedBy': guardUid},
    );
    final task = await ref.putData(bytes, metadata);
    return await task.ref.getDownloadURL();
  }

  /// Logs a walk-in / unscheduled visitor or delivery agent directly at the gate.
  ///
  /// 1. Saves a document in `visitors` with `isWalkIn: true`, `status: CHECKED_IN`, and `approvalStatus: PENDING`.
  /// 2. Dispatches an immediate high-priority push notification to the resident of [flatNumber]
  ///    giving them one-tap Approve / Deny buttons directly on their dashboard and notification tray.
  static Future<String> logWalkInVisitor({
    required String visitorName,
    required String phone,
    required String flatNumber,
    required String purpose,
    String? deliveryApp,
    String? vehicleNumber,
    String? photoUrl,
    required String guardUid,
    String? guardName,
    String? gateName,
  }) async {
    final normFlat = FlatUtils.normalize(flatNumber);

    // Look up resident account UID corresponding to the destination flat number
    // This ensures both UID-based ownership checks and flat-based security rules pass cleanly.
    String? residentUid;
    try {
      final userSnap = await _fs
          .collection('users')
          .where('flatNumber', isEqualTo: normFlat)
          .limit(1)
          .get();
      if (userSnap.docs.isNotEmpty) {
        residentUid = userSnap.docs.first.id;
      }
    } catch (_) {
      // Fallback gracefully if lookup fails or lacks read access
    }

    final docRef = await _fs.collection('visitors').add({
      'visitorName': visitorName.trim(),
      'phone': phone.trim(),
      'flatNumber': normFlat,
      'hostFlatNumber': normFlat,
      'hostUid': residentUid,
      'residentUid': residentUid,
      'purpose': purpose,
      'deliveryApp': deliveryApp?.trim(),
      'vehicleNumber': vehicleNumber?.trim().toUpperCase() ?? '',
      'photoUrl': photoUrl,
      'status': 'CHECKED_IN',
      'approvalStatus': 'PENDING',
      'isWalkIn': true,
      'entryTime': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'checkedInBy': guardUid,
      'guardName': guardName ?? 'Security Guard',
      'gateName': gateName ?? 'Main Gate',
    });

    final deliveryPrefix = (deliveryApp != null && deliveryApp.isNotEmpty) ? '[$deliveryApp] ' : '';

    // Notify resident of the visiting flat
    await NotificationService.notifyResident(
      flatNumber: normFlat,
      title: 'Visitor At Gate: $deliveryPrefix${visitorName.trim()}',
      message: '$deliveryPrefix${visitorName.trim()} ($purpose) has checked in at ${gateName ?? 'Security Gate'}.',
      type: 'VISITOR_CHECK_IN',
      extraData: {
        'visitorDocId': docRef.id,
        'visitorName': visitorName.trim(),
        'phone': phone.trim(),
        'purpose': purpose,
        'deliveryApp': deliveryApp?.trim(),
        'photoUrl': photoUrl,
        'gateName': gateName ?? 'Security Gate',
        'guardName': guardName ?? 'Security Guard',
        'vehicleNumber': vehicleNumber?.trim().toUpperCase() ?? '',
        'approvalStatus': 'PENDING',
        'isWalkIn': true,
      },
    );

    return docRef.id;
  }

  /// Marks a visitor as checked-out upon leaving campus (`status: CHECKED_OUT`)
  /// and notifies the host resident that their guest has safely departed.
  static Future<void> checkOutVisitor({
    required String visitorDocId,
    required String? guardUid,
    String? guardName,
    String? gateName,
    Map<String, dynamic>? visitorData,
  }) async {
    await _fs.collection('visitors').doc(visitorDocId).update({
      'status': 'CHECKED_OUT',
      'exitTime': FieldValue.serverTimestamp(),
      'checkedOutBy': guardUid,
    });

    Map<String, dynamic>? data = visitorData;
    if (data == null) {
      try {
        final docSnap = await _fs.collection('visitors').doc(visitorDocId).get();
        if (docSnap.exists) {
          data = docSnap.data();
        }
      } catch (_) {}
    }

    if (data != null) {
      final rawFlat = data['hostFlatNumber'] ?? data['flatNumber'] ?? '';
      final hostFlat = FlatUtils.normalize(rawFlat.toString());
      final visitorName = (data['visitorName'] ?? 'Guest').toString().trim();
      final purpose = (data['purpose'] ?? 'Guest / Personal').toString().trim();
      final residentUid = data['residentUid']?.toString() ?? data['hostUid']?.toString();
      final phone = (data['phone'] ?? '').toString().trim();
      final vehicleNumber = (data['vehicleNumber'] ?? '').toString().trim();
      final isComingByCar = data['isComingByCar'] == true || vehicleNumber.isNotEmpty;
      final gate = gateName ?? data['gateName']?.toString() ?? 'Main Gate';
      final guard = guardName ?? data['guardName']?.toString() ?? 'Security Guard';
      final vehicleInfo = isComingByCar && vehicleNumber.isNotEmpty ? ' with vehicle $vehicleNumber' : '';

      if (hostFlat.isNotEmpty || (residentUid != null && residentUid.isNotEmpty)) {
        await NotificationService.notifyResident(
          flatNumber: hostFlat,
          targetUid: residentUid,
          title: 'Guest Departed: $visitorName',
          message: 'Your guest $visitorName ($purpose) has checked out and exited from $gate$vehicleInfo.',
          type: 'VISITOR_CHECK_OUT',
          extraData: {
            'visitorDocId': visitorDocId,
            'visitorName': visitorName,
            'purpose': purpose,
            'phone': phone,
            'isComingByCar': isComingByCar,
            'vehicleNumber': vehicleNumber,
            'gateName': gate,
            'guardName': guard,
            'status': 'CHECKED_OUT',
            'exitTime': DateTime.now().toIso8601String(),
          },
        );
      }
    }
  }

  /// Stream of active visitors currently inside campus (`status == CHECKED_IN`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> getActiveVisitorsStream() {
    return _fs
        .collection('visitors')
        .where('status', isEqualTo: 'CHECKED_IN')
        .snapshots();
  }

  // ─── Gate Parcels & Delivery Operations ───────────────────────────────────

  /// Logs a parcel left at the security gate by courier/delivery agents (`gate_parcels` collection).
  ///
  /// Dispatches a `PARCEL_HELD` notification to the resident of [flatNumber].
  static Future<String> logParcel({
    required String flatNumber,
    required String deliveryProvider,
    required int packetCount,
    String? remarks,
    required String guardUid,
    String? guardName,
    String? gateName,
  }) async {
    final normFlat = FlatUtils.normalize(flatNumber);

    final docRef = await _fs.collection('gate_parcels').add({
      'flatNumber': normFlat,
      'deliveryProvider': deliveryProvider.trim(),
      'packetCount': packetCount,
      'remarks': remarks?.trim() ?? '',
      'status': 'HELD_AT_GATE', // HELD_AT_GATE -> COLLECTED
      'receivedAt': FieldValue.serverTimestamp(),
      'receivedBy': guardUid,
      'guardName': guardName ?? 'Security Guard',
      'gateName': gateName ?? 'Main Gate',
    });

    await NotificationService.notifyResident(
      flatNumber: normFlat,
      title: 'Parcel Received at Gate',
      message: '$packetCount package(s) from $deliveryProvider received at ${gateName ?? 'Main Gate'}.',
      type: 'PARCEL_HELD',
      extraData: {
        'parcelDocId': docRef.id,
        'deliveryProvider': deliveryProvider.trim(),
        'packetCount': packetCount,
        'remarks': remarks?.trim() ?? '',
        'gateName': gateName ?? 'Main Gate',
        'guardName': guardName ?? 'Security Guard',
      },
    );

    return docRef.id;
  }

  /// Marks a parcel as collected / handed over to resident (`status: COLLECTED`)
  /// and automatically dispatches a push notification to the resident to acknowledge receipt.
  static Future<void> markParcelCollected({
    required String parcelDocId,
    required String? guardUid,
    String? collectedBy,
    String? guardName,
    String? gateName,
    String? flatNumber,
    String? deliveryProvider,
    int? packetCount,
  }) async {
    // 1. Mark parcel status as COLLECTED in gate_parcels collection
    await _fs.collection('gate_parcels').doc(parcelDocId).update({
      'status': 'COLLECTED',
      'collectedAt': FieldValue.serverTimestamp(),
      'handedOverBy': guardUid,
      'collectedBy': collectedBy ?? 'Resident',
    });

    // 2. Resolve flat and delivery metadata if not explicitly provided
    String targetFlat = flatNumber ?? '';
    String provider = deliveryProvider ?? 'Courier';
    int count = packetCount ?? 1;

    if (targetFlat.isEmpty) {
      try {
        final pDoc = await _fs.collection('gate_parcels').doc(parcelDocId).get();
        final pData = pDoc.data();
        if (pData != null) {
          targetFlat = pData['flatNumber']?.toString() ?? '';
          provider = pData['deliveryProvider']?.toString() ?? provider;
          count = pData['packetCount'] is int
              ? pData['packetCount'] as int
              : (int.tryParse(pData['packetCount']?.toString() ?? '') ?? count);
        }
      } catch (_) {}
    }

    // 3. Dispatch parcel handover notification to the resident so they can acknowledge receipt
    if (targetFlat.isNotEmpty) {
      final normFlat = FlatUtils.normalize(targetFlat);
      await NotificationService.notifyResident(
        flatNumber: normFlat,
        title: 'Parcel Delivered: $provider',
        message: '$count package(s) from $provider have been handed over by ${guardName ?? 'Gate Security'} at ${gateName ?? 'Main Gate'}. Tap to acknowledge receipt.',
        type: 'PARCEL_DELIVERED',
        extraData: {
          'parcelDocId': parcelDocId,
          'deliveryProvider': provider,
          'packetCount': count,
          'guardName': guardName ?? 'Security Guard',
          'gateName': gateName ?? 'Main Gate',
          'flatNumber': normFlat,
          'status': 'COLLECTED',
          'requiresAcknowledgment': true,
          'acknowledged': false,
        },
      );
    }
  }

  /// Acknowledges receipt of a delivered or gate-held parcel by the resident.
  /// Updates the gate_parcels doc, marks the notification as acknowledged,
  /// and sends a confirmation alert back to Gate Security.
  static Future<void> acknowledgeParcelReceipt({
    required String parcelDocId,
    required String flatNumber,
    required String deliveryProvider,
    required int packetCount,
    String? notifDocId,
    String? residentName,
  }) async {
    final normFlat = FlatUtils.normalize(flatNumber);

    // 1. Record resident acknowledgment in gate_parcels collection
    if (parcelDocId.isNotEmpty) {
      try {
        await _fs.collection('gate_parcels').doc(parcelDocId).update({
          // Flag indicating the resident has confirmed receiving the package
          'residentAcknowledged': true,
          // Server timestamp when resident confirmed receipt
          'acknowledgedAt': FieldValue.serverTimestamp(),
          // Include resident's display name for audit trails if available
          'acknowledgedByName': ?residentName,
        });
      } catch (e) {
        debugPrint('[VisitorPassService] Note on gate_parcels update: $e');
      }
    }

    // 2. Mark the resident notification as acknowledged and read
    if (notifDocId != null && notifDocId.isNotEmpty) {
      try {
        await _fs.collection('notifications').doc(notifDocId).update({
          'acknowledged': true,
          'isRead': true,
          'receiptStatus': 'RECEIVED',
          'acknowledgedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[VisitorPassService] Note on notification update: $e');
      }
    }

    // 3. Dispatch an alert to Gate Security confirming resident has received the parcel
    await NotificationService.notifyGuard(
      title: 'Receipt Confirmed: Flat $normFlat',
      message: 'Resident of flat $normFlat has confirmed receipt of $packetCount package(s) from $deliveryProvider.',
      type: 'PARCEL_ACKNOWLEDGED',
      flatNumber: normFlat,
      extraData: {
        'parcelDocId': parcelDocId,
        'flatNumber': normFlat,
        'deliveryProvider': deliveryProvider,
        'packetCount': packetCount,
        'acknowledged': true,
        'receiptStatus': 'RECEIVED',
      },
    );
  }

  /// Reports a parcel as NOT received by the resident (disputed handover).
  /// Updates the resident notification and gate parcel records, and immediately
  /// raises a high-priority dispute alert to Gate Security for physical verification.
  static Future<void> reportParcelNotReceived({
    required String parcelDocId,
    required String flatNumber,
    required String deliveryProvider,
    required int packetCount,
    String? notifDocId,
    String? residentName,
    String? reason,
  }) async {
    final normFlat = FlatUtils.normalize(flatNumber);

    // 1. Record dispute flag on the resident's notification record
    if (notifDocId != null && notifDocId.isNotEmpty) {
      try {
        await _fs.collection('notifications').doc(notifDocId).update({
          // Clear positive acknowledgment
          'acknowledged': false,
          // Flag as disputed for UI rendering and follow-up
          'disputed': true,
          'receiptStatus': 'NOT_RECEIVED',
          'isRead': true,
          'disputeReason': reason ?? 'Resident reported package NOT received',
          'disputedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('[VisitorPassService] Note on notification dispute update: $e');
      }
    }

    // 2. Dispatch a high-priority alert to Gate Security terminal
    await NotificationService.notifyGuard(
      title: '⚠️ Parcel Not Received: Flat $normFlat',
      message: 'Resident of flat $normFlat reported they did NOT receive the $packetCount package(s) from $deliveryProvider. Please verify with delivery agent.',
      type: 'PARCEL_NOT_RECEIVED',
      flatNumber: normFlat,
      extraData: {
        'parcelDocId': parcelDocId,
        'flatNumber': normFlat,
        'deliveryProvider': deliveryProvider,
        'packetCount': packetCount,
        'acknowledged': false,
        'disputed': true,
        'receiptStatus': 'NOT_RECEIVED',
      },
    );
  }

  /// Stream of parcels currently waiting at the security gate (`status == HELD_AT_GATE`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> getPendingParcelsStream() {
    return _fs
        .collection('gate_parcels')
        .where('status', isEqualTo: 'HELD_AT_GATE')
        .snapshots();
  }

  /// Stream of all gate parcels (including held, delivered, acknowledged, and disputed),
  /// ordered by reception timestamp descending to support historical auditing and search.
  static Stream<QuerySnapshot<Map<String, dynamic>>> getAllParcelsStream({int limit = 150}) {
    return _fs
        .collection('gate_parcels')
        .orderBy('receivedAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  // ─── Emergency Security SOS ───────────────────────────────────────────────

  /// Broadcasts an emergency alert from the guard gate to all society residents and admins.
  static Future<void> triggerEmergencyAlert({
    required String emergencyType,
    required String guardName,
    required String gateName,
    String? details,
  }) async {
    final title = 'EMERGENCY ALERT: $emergencyType';
    final message = '$emergencyType emergency reported at $gateName by $guardName. ${details ?? ''}'.trim();

    await NotificationService.broadcast(
      title: title,
      message: message,
      type: 'EMERGENCY',
    );

    await _fs.collection('security_alerts').add({
      'emergencyType': emergencyType,
      'guardName': guardName,
      'gateName': gateName,
      'details': details ?? '',
      'status': 'ACTIVE',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Resident Visitor Approval & Denial ───────────────────────────────────

  /// Approves a visitor's entry request by the resident and alerts gate security.
  ///
  /// Updates both the `visitors` and `notifications` documents to `approvalStatus: APPROVED`
  /// and sends an alert back to the guard app.
  static Future<void> approveVisitorEntry({
    required String? visitorDocId,
    required String flatNumber,
    required String visitorName,
    String? notifDocId,
  }) async {
    final now = FieldValue.serverTimestamp();
    final normFlat = FlatUtils.normalize(flatNumber);

    String? targetDocId = visitorDocId;

    // Auto-resolve visitor doc id if not directly provided
    if (targetDocId == null || targetDocId.isEmpty) {
      try {
        final q = await _fs
            .collection('visitors')
            .where('flatNumber', isEqualTo: normFlat)
            .where('status', isEqualTo: 'CHECKED_IN')
            .limit(10)
            .get();
        final matches = q.docs.where((d) {
          final data = d.data();
          final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
          return (vN == visitorName.trim().toLowerCase() ||
                  vN.contains(visitorName.trim().toLowerCase()) ||
                  visitorName.trim().toLowerCase().contains(vN));
        }).toList();
        if (matches.isNotEmpty) {
          targetDocId = matches.first.id;
        } else if (q.docs.isNotEmpty) {
          targetDocId = q.docs.last.id;
        }
      } catch (e) {
        // ignore
      }
    }

    if (targetDocId != null && targetDocId.isNotEmpty) {
      try {
        await _fs.collection('visitors').doc(targetDocId).update({
          'approvalStatus': 'APPROVED',
          'approvedAt': now,
        });
      } catch (e) {
        // ignore: avoid_print
        print('Error updating visitor document $targetDocId: $e');
        rethrow;
      }
    }

    if (notifDocId != null && notifDocId.isNotEmpty) {
      try {
        await _fs.collection('notifications').doc(notifDocId).update({
          'approvalStatus': 'APPROVED',
          'updatedAt': now,
        });
      } catch (_) {}
    }

    await NotificationService.notifyGuard(
      title: '✅ Entry Approved: $visitorName',
      message: 'Resident of $normFlat has APPROVED entry for $visitorName.',
      type: 'VISITOR_APPROVAL_RESPONSE',
      flatNumber: normFlat,
      extraData: {
        'visitorDocId': targetDocId,
        'visitorName': visitorName,
        'approvalStatus': 'APPROVED',
      },
    );
  }

  /// Denies a visitor's entry by resident and urgently alerts gate security
  static Future<void> denyVisitorEntry({
    required String? visitorDocId,
    required String flatNumber,
    required String visitorName,
    String? notifDocId,
  }) async {
    final now = FieldValue.serverTimestamp();
    final normFlat = FlatUtils.normalize(flatNumber);

    String? targetDocId = visitorDocId;

    if (targetDocId == null || targetDocId.isEmpty) {
      try {
        final q = await _fs
            .collection('visitors')
            .where('flatNumber', isEqualTo: normFlat)
            .where('status', isEqualTo: 'CHECKED_IN')
            .limit(10)
            .get();
        final matches = q.docs.where((d) {
          final data = d.data();
          final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
          return (vN == visitorName.trim().toLowerCase() ||
                  vN.contains(visitorName.trim().toLowerCase()) ||
                  visitorName.trim().toLowerCase().contains(vN));
        }).toList();
        if (matches.isNotEmpty) {
          targetDocId = matches.first.id;
        } else if (q.docs.isNotEmpty) {
          targetDocId = q.docs.last.id;
        }
      } catch (e) {
        // ignore
      }
    }

    if (targetDocId != null && targetDocId.isNotEmpty) {
      try {
        await _fs.collection('visitors').doc(targetDocId).update({
          'approvalStatus': 'DENIED',
          'status': 'DENIED',
          'deniedAt': now,
        });
      } catch (e) {
        // ignore: avoid_print
        print('Error updating visitor document denial $targetDocId: $e');
        rethrow;
      }
    }

    if (notifDocId != null && notifDocId.isNotEmpty) {
      try {
        await _fs.collection('notifications').doc(notifDocId).update({
          'approvalStatus': 'DENIED',
          'updatedAt': now,
        });
      } catch (_) {}
    }

    await NotificationService.notifyGuard(
      title: '⛔ ENTRY DENIED: $visitorName',
      message: 'Resident of $normFlat has DENIED entry for $visitorName. Do NOT allow access!',
      type: 'VISITOR_APPROVAL_RESPONSE',
      flatNumber: normFlat,
      extraData: {
        'visitorDocId': targetDocId,
        'visitorName': visitorName,
        'approvalStatus': 'DENIED',
      },
    );
  }
}
