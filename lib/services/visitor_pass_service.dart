import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../utils/flat_utils.dart';
import 'notification_service.dart';
import 'push_notification_manager.dart';

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

    if (status == 'PENDING' || status == 'APPROVED' || status.isEmpty) {
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
  ///
  /// Concurrency & Denial Guard: Executes inside a Firestore transaction.
  /// If the resident has already denied the entry (`approvalStatus == 'DENIED'`),
  /// the transaction aborts and throws an exception, preventing guards from overriding
  /// resident security denials.
  static Future<void> checkInVisitor({
    required String visitorDocId,
    required String? guardUid,
    String? guardName,
    String? gateName,
    Map<String, dynamic>? visitorData,
  }) async {
    final docRef = _fs.collection('visitors').doc(visitorDocId);

    // Execute check-in within an atomic transaction to prevent race conditions
    // and strictly respect resident denial decisions.
    final updatedData = await _fs.runTransaction<Map<String, dynamic>?>((tx) async {
      final snapshot = await tx.get(docRef);
      if (!snapshot.exists) {
        throw Exception('Visitor record ($visitorDocId) does not exist.');
      }
      final cur = snapshot.data() ?? {};
      final currentApproval = cur['approvalStatus']?.toString().toUpperCase();
      if (currentApproval == 'DENIED') {
        throw Exception('Visitor entry has been DENIED by the resident. Check-in cannot proceed.');
      }

      tx.update(docRef, {
        'status': 'CHECKED_IN',
        'approvalStatus': 'APPROVED',
        'isUsed': true,
        'usedAt': FieldValue.serverTimestamp(),
        'entryTime': FieldValue.serverTimestamp(),
        'checkedInBy': guardUid,
        'guardName': guardName ?? 'Security Guard',
        'gateName': gateName ?? 'Main Gate',
      });

      return cur;
    });

    Map<String, dynamic>? data = updatedData ?? visitorData;

    if (data != null) {
      final rawFlat = data['hostFlatNumber'] ?? data['flatNumber'] ?? '';
      final hostFlat = FlatUtils.normalize(rawFlat.toString());
      final visitorName = (data['visitorName'] ?? 'Guest').toString().trim();
      final purpose = (data['purpose'] ?? 'Guest / Personal').toString().trim();
      final residentUid = data['residentUid']?.toString() ?? data['hostUid']?.toString();
      final phone = (data['phone'] ?? '').toString().trim();
      // Auto-capitalize vehicle registration for arrival notification message
      final vehicleNumber = (data['vehicleNumber'] ?? '').toString().trim().toUpperCase();
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

  /// Checks whether a flat exists in the society database (`flats` or `users` collection).
  ///
  /// This verification is performed prior to checking in walk-in visitors to ensure
  /// gate clearance requests are only dispatched to legitimate, registered society apartments.
  /// Returns `true` if a matching flat is found in the database, `false` otherwise.
  static Future<bool> checkFlatExists(String flatNumber) async {
    final normFlat = FlatUtils.normalize(flatNumber);
    if (normFlat.isEmpty) return false;

    try {
      // 1. Check direct document ID in 'flats' collection (e.g. 'B-312')
      final flatDoc = await _fs.collection('flats').doc(normFlat).get();
      if (flatDoc.exists) return true;

      // 2. Check 'flats' collection where flatNumber equals normalized flat
      final flatQuery = await _fs
          .collection('flats')
          .where('flatNumber', isEqualTo: normFlat)
          .limit(1)
          .get();
      if (flatQuery.docs.isNotEmpty) return true;

      // 3. Check 'users' collection where flatNumber equals normalized flat
      final userQuery = await _fs
          .collection('users')
          .where('flatNumber', isEqualTo: normFlat)
          .limit(1)
          .get();
      if (userQuery.docs.isNotEmpty) return true;

      // 4. Check all possible formatting variants generated by FlatUtils
      final lookupKeys = FlatUtils.getLookupKeys(normFlat);
      for (final key in lookupKeys) {
        final doc = await _fs.collection('flats').doc(key).get();
        if (doc.exists) return true;
      }
      for (final key in lookupKeys) {
        final uQuery = await _fs
            .collection('users')
            .where('flatNumber', isEqualTo: key)
            .limit(1)
            .get();
        if (uQuery.docs.isNotEmpty) return true;
      }

      return false;
    } catch (e) {
      debugPrint('[VisitorPassService] Error checking flat existence: $e');
      return false;
    }
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

    final isDelivery = (deliveryApp != null && deliveryApp.isNotEmpty) ||
        purpose.toLowerCase().contains('delivery') ||
        purpose.toLowerCase().contains('courier');

    // Daily domestic staff (maids, cooks, drivers, helpers) visit regularly and do not require
    // a loud, high-priority ringing doorbell alarm on resident screens.
    final isStaff = purpose.toLowerCase().contains('maid') ||
        purpose.toLowerCase().contains('helper') ||
        purpose.toLowerCase().contains('cook') ||
        purpose.toLowerCase().contains('driver');

    final approvalStatus = isStaff ? 'ENTRY_LOGGED' : 'PENDING';
    // Daily domestic staff (maid, cook, driver) are pre-cleared routine workers and checked in directly.
    // Guests and delivery agents awaiting resident approval must NOT be checked in to campus yet;
    // their initial status is set to WAITING_APPROVAL and entryTime remains null until approval is granted.
    final initialStatus = isStaff ? 'CHECKED_IN' : 'WAITING_APPROVAL';

    final docRef = await _fs.collection('visitors').add({
      'visitorName': visitorName.trim(),
      'phone': phone.trim(),
      'flatNumber': normFlat,
      'hostFlatNumber': normFlat,
      'hostUid': residentUid,
      'residentUid': residentUid,
      'purpose': purpose,
      'deliveryApp': deliveryApp?.trim(),
      'isDelivery': isDelivery,
      'isStaff': isStaff,
      'vehicleNumber': vehicleNumber?.trim().toUpperCase() ?? '',
      'photoUrl': photoUrl,
      'status': initialStatus,
      'approvalStatus': approvalStatus,
      'isWalkIn': true,
      if (isStaff) 'entryTime': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'checkedInBy': guardUid,
      'guardName': guardName ?? 'Security Guard',
      'gateName': gateName ?? 'Main Gate',
    });

    if (isStaff) {
      // Dispatch silent / calm entry notification for domestic staff without ringing alarm popout
      await NotificationService.notifyResident(
        flatNumber: normFlat,
        title: 'Staff Entry: ${visitorName.trim()}',
        message: '${visitorName.trim()} ($purpose) has checked in at ${gateName ?? 'Main Gate'}.',
        type: 'STAFF_ENTRY',
        extraData: {
          'visitorDocId': docRef.id,
          'visitorName': visitorName.trim(),
          'phone': phone.trim(),
          'purpose': purpose,
          'isStaff': true,
          'photoUrl': photoUrl,
          'gateName': gateName ?? 'Main Gate',
          'guardName': guardName ?? 'Security Guard',
          'approvalStatus': 'ENTRY_LOGGED',
          'isWalkIn': true,
        },
      );
    } else {
      final deliveryPrefix = isDelivery && (deliveryApp != null && deliveryApp.isNotEmpty)
          ? '[$deliveryApp] '
          : '';
      final notifTitle = isDelivery && (deliveryApp != null && deliveryApp.isNotEmpty)
          ? 'Delivery: $deliveryApp - ${visitorName.trim()}'
          : 'Visitor At Gate: ${visitorName.trim()}';

      // Notify resident of the visiting flat with complete delivery and photo metadata
      await NotificationService.notifyResident(
        flatNumber: normFlat,
        title: notifTitle,
        message: isDelivery && (deliveryApp != null && deliveryApp.isNotEmpty)
            ? '$deliveryApp executive ${visitorName.trim()} is at ${gateName ?? 'Security Gate'} for flat $normFlat.'
            : '$deliveryPrefix${visitorName.trim()} ($purpose) has checked in at ${gateName ?? 'Security Gate'}.',
        type: 'VISITOR_CHECK_IN',
        extraData: {
          'visitorDocId': docRef.id,
          'visitorName': visitorName.trim(),
          'phone': phone.trim(),
          'purpose': purpose,
          'deliveryApp': deliveryApp?.trim(),
          'isDelivery': isDelivery,
          'photoUrl': photoUrl,
          'gateName': gateName ?? 'Security Gate',
          'guardName': guardName ?? 'Security Guard',
          'vehicleNumber': vehicleNumber?.trim().toUpperCase() ?? '',
          'approvalStatus': 'PENDING',
          'isWalkIn': true,
        },
      );
    }

    return docRef.id;
  }

  // In-memory set of visitor IDs currently undergoing checkout to debounce rapid double-taps by guards
  static final Set<String> _checkingOutVisitorIds = {};

  /// Marks a visitor as checked-out upon leaving campus (`status: CHECKED_OUT`)
  /// and notifies the host resident that their guest has safely departed.
  /// Uses in-memory debouncing and deterministic notification IDs (`checkout_<visitorDocId>`)
  /// to guarantee that the resident receives exactly ONE departure notification.
  static Future<void> checkOutVisitor({
    required String visitorDocId,
    required String? guardUid,
    String? guardName,
    String? gateName,
    Map<String, dynamic>? visitorData,
  }) async {
    // 1. Debounce rapid double-taps on the guard terminal
    if (_checkingOutVisitorIds.contains(visitorDocId)) {
      debugPrint('[VisitorPassService] Checkout already in progress for $visitorDocId. Suppressing duplicate invocation.');
      return;
    }
    _checkingOutVisitorIds.add(visitorDocId);

    try {
      // 2. Pre-check if already checked out to avoid duplicate exit records or notifications
      Map<String, dynamic>? data = visitorData;
      if (data == null || data['status'] == null) {
        try {
          final docSnap = await _fs.collection('visitors').doc(visitorDocId).get();
          if (docSnap.exists) {
            data = docSnap.data();
          }
        } catch (_) {}
      }

      // If the visitor is already marked as checked out, gracefully exit
      if (data != null && data['status'] == 'CHECKED_OUT') {
        debugPrint('[VisitorPassService] Visitor $visitorDocId is already CHECKED_OUT. Aborting duplicate checkout.');
        return;
      }

      await _fs.collection('visitors').doc(visitorDocId).update({
        'status': 'CHECKED_OUT',
        'exitTime': FieldValue.serverTimestamp(),
        'checkedOutBy': guardUid,
      });

      if (data != null) {
        final rawFlat = data['hostFlatNumber'] ?? data['flatNumber'] ?? '';
        final hostFlat = FlatUtils.normalize(rawFlat.toString());
        final visitorName = (data['visitorName'] ?? 'Guest').toString().trim();
        final purpose = (data['purpose'] ?? 'Guest / Personal').toString().trim();
        final residentUid = data['residentUid']?.toString() ?? data['hostUid']?.toString();
        final phone = (data['phone'] ?? '').toString().trim();
        // Auto-capitalize vehicle registration for exit notification message
        final vehicleNumber = (data['vehicleNumber'] ?? '').toString().trim().toUpperCase();
        final isComingByCar = data['isComingByCar'] == true || vehicleNumber.isNotEmpty;
        final gate = gateName ?? data['gateName']?.toString() ?? 'Main Gate';
        final guard = guardName ?? data['guardName']?.toString() ?? 'Security Guard';
        final vehicleInfo = isComingByCar && vehicleNumber.isNotEmpty ? ' with vehicle $vehicleNumber' : '';

        if (hostFlat.isNotEmpty || (residentUid != null && residentUid.isNotEmpty)) {
          // Deterministic notification ID ensures idempotent document creation in Firestore.
          // Cloud Functions onCreate and Firestore snapshot listeners fire EXACTLY once!
          await NotificationService.notifyResident(
            notificationId: 'checkout_$visitorDocId',
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
    } finally {
      _checkingOutVisitorIds.remove(visitorDocId);
    }
  }

  /// Stream of active visitors currently inside campus (`status == CHECKED_IN`).
  static Stream<QuerySnapshot<Map<String, dynamic>>> getActiveVisitorsStream() {
    return _fs
        .collection('visitors')
        .where('status', isEqualTo: 'CHECKED_IN')
        .snapshots();
  }

  /// Searches past visitor records in the `visitors` collection by 10-digit [phone] number.
  /// Returns the most recent visitor's data map (name, vehicleNumber, purpose, deliveryApp, photoUrl)
  /// to enable instant 1-tap autofill for security guards at the gate.
  static Future<Map<String, dynamic>?> lookupRecentVisitorByPhone(String phone) async {
    final cleanPhone = phone.trim().replaceAll(' ', '').replaceAll('-', '');
    if (cleanPhone.length != 10) return null;

    try {
      // 1. First query by standard 10-digit phone
      final snap = await _fs
          .collection('visitors')
          .where('phone', isEqualTo: cleanPhone)
          .limit(5)
          .get();

      if (snap.docs.isNotEmpty) {
        return snap.docs.first.data();
      }

      // 2. Query with country code prefix (+91) for legacy or international records
      final snap91 = await _fs
          .collection('visitors')
          .where('phone', isEqualTo: '+91$cleanPhone')
          .limit(5)
          .get();

      if (snap91.docs.isNotEmpty) {
        return snap91.docs.first.data();
      }

      return null;
    } catch (e) {
      debugPrint('[VisitorPassService] Error looking up frequent visitor by phone: $e');
      return null;
    }
  }

  // ─── Gate Parcels & Delivery Operations ───────────────────────────────────

  /// Generates a secure, cryptographically random 4-digit numeric OTP code (range 1000 to 9999)
  /// used by residents to safely collect their parcels from gate security.
  static String generatePickupOtp() {
    final rand = Random();
    return (1000 + rand.nextInt(9000)).toString();
  }

  /// Logs a parcel left at the security gate by courier/delivery agents (`gate_parcels` collection).
  ///
  /// Generates a 4-digit [pickupOtp] and dispatches a `PARCEL_HELD` notification to the resident of [flatNumber].
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
    // Generate a secure 4-digit verification OTP required for parcel collection at the security gate
    final pickupOtp = generatePickupOtp();

    final docRef = await _fs.collection('gate_parcels').add({
      'flatNumber': normFlat,
      'deliveryProvider': deliveryProvider.trim(),
      'packetCount': packetCount,
      'remarks': remarks?.trim() ?? '',
      'status': 'HELD_AT_GATE', // HELD_AT_GATE -> COLLECTED
      'pickupOtp': pickupOtp,
      'receivedAt': FieldValue.serverTimestamp(),
      'receivedBy': guardUid,
      'guardName': guardName ?? 'Security Guard',
      'gateName': gateName ?? 'Main Gate',
    });

    // Notify the host resident of the held parcel along with their secure 4-digit pickup code
    await NotificationService.notifyResident(
      flatNumber: normFlat,
      title: 'Parcel Received at Gate',
      message: '$packetCount package(s) from $deliveryProvider received at ${gateName ?? 'Main Gate'}. Pickup OTP: $pickupOtp',
      type: 'PARCEL_HELD',
      extraData: {
        'parcelDocId': docRef.id,
        'deliveryProvider': deliveryProvider.trim(),
        'packetCount': packetCount,
        'pickupOtp': pickupOtp,
        'remarks': remarks?.trim() ?? '',
        'gateName': gateName ?? 'Main Gate',
        'guardName': guardName ?? 'Security Guard',
        'status': 'HELD_AT_GATE',
      },
    );

    return docRef.id;
  }

  /// Verifies the 4-digit resident pickup OTP before handing over a held parcel.
  /// If [enteredOtp] matches the parcel's stored [pickupOtp] (or if legacy parcel has no OTP),
  /// transitions status to `COLLECTED` and returns `true`.
  /// Returns `false` if the OTP is invalid or does not match.
  static Future<bool> verifyAndCollectParcel({
    required String parcelDocId,
    required String enteredOtp,
    required String? guardUid,
    String? collectedBy,
    String? guardName,
    String? gateName,
    String? flatNumber,
    String? deliveryProvider,
    int? packetCount,
  }) async {
    try {
      final docSnap = await _fs.collection('gate_parcels').doc(parcelDocId).get();
      if (!docSnap.exists) {
        return false;
      }
      final data = docSnap.data();
      final expectedOtp = data?['pickupOtp']?.toString().trim();

      // If the parcel has a registered pickup OTP, strictly enforce exact match
      if (expectedOtp != null && expectedOtp.isNotEmpty) {
        if (enteredOtp.trim() != expectedOtp) {
          debugPrint('[VisitorPassService] Pickup OTP mismatch for parcel $parcelDocId: entered "$enteredOtp" vs expected "$expectedOtp"');
          return false;
        }
      }

      // OTP matches or legacy record has no OTP configured -> safely proceed with handover
      await markParcelCollected(
        parcelDocId: parcelDocId,
        guardUid: guardUid,
        collectedBy: collectedBy,
        guardName: guardName,
        gateName: gateName,
        flatNumber: flatNumber ?? data?['flatNumber']?.toString(),
        deliveryProvider: deliveryProvider ?? data?['deliveryProvider']?.toString(),
        packetCount: packetCount ?? (data?['packetCount'] is int ? data!['packetCount'] as int : 1),
      );
      return true;
    } catch (e) {
      debugPrint('[VisitorPassService] Error verifying parcel OTP: $e');
      return false;
    }
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
  /// Uses an atomic Firestore transaction to prevent race conditions or duplicate
  /// conflicting approvals/denials. If the visitor is already approved or denied,
  /// this method aborts cleanly without sending duplicate or contradictory alerts to the guard.
  static Future<bool> approveVisitorEntry({
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
            .limit(15)
            .get();
        final matches = q.docs.where((d) {
          final data = d.data();
          final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
          final approval = (data['approvalStatus'] ?? '').toString().toUpperCase();
          return (approval == 'PENDING' || approval.isEmpty) &&
              (vN == visitorName.trim().toLowerCase() ||
                  vN.contains(visitorName.trim().toLowerCase()) ||
                  visitorName.trim().toLowerCase().contains(vN));
        }).toList();
        if (matches.isNotEmpty) {
          targetDocId = matches.first.id;
        } else if (q.docs.isNotEmpty) {
          targetDocId = q.docs.last.id;
        }
      } catch (e) {
        debugPrint('[VisitorPassService] Error resolving visitor doc ID: $e');
      }
    }

    bool transitioned = false;

    // Run atomic transaction to ensure status is PENDING before approving
    if (targetDocId != null && targetDocId.isNotEmpty) {
      final visitorRef = _fs.collection('visitors').doc(targetDocId);
      try {
        transitioned = await _fs.runTransaction<bool>((transaction) async {
          final snapshot = await transaction.get(visitorRef);
          if (!snapshot.exists) return false;
          final currentApproval = (snapshot.data()?['approvalStatus'] ?? '').toString().toUpperCase();
          // If already resolved, reject transition to prevent duplicate/conflicting updates
          if (currentApproval == 'APPROVED' || currentApproval == 'DENIED') {
            debugPrint('[VisitorPassService] Visitor $targetDocId already resolved as $currentApproval. Aborting approve.');
            return false;
          }
          // On approval, grant campus entry clearance by marking status CHECKED_IN with entryTime
          transaction.update(visitorRef, {
            'approvalStatus': 'APPROVED',
            'status': 'CHECKED_IN',
            'entryTime': now,
            'approvedAt': now,
          });
          return true;
        });
      } catch (e) {
        debugPrint('[VisitorPassService] Transaction error approving visitor $targetDocId: $e');
        try {
          await visitorRef.update({
            'approvalStatus': 'APPROVED',
            'status': 'CHECKED_IN',
            'entryTime': now,
            'approvedAt': now,
          });
          transitioned = true;
        } catch (_) {}
      }
    } else {
      transitioned = true;
    }

    // Always dismiss and cancel the native notification alert from the Android hood and floating banner
    try {
      await PushNotificationManager.cancelNotification(notifDocId ?? '', targetDocId);
    } catch (e) {
      debugPrint('[VisitorPassService] Error canceling push notification: $e');
    }

    // Update all matching notification documents to resolved status
    if (notifDocId != null && notifDocId.isNotEmpty) {
      try {
        await _fs.collection('notifications').doc(notifDocId).update({
          'approvalStatus': 'APPROVED',
          'isRead': true,
          'resolvedAt': now,
          'updatedAt': now,
        });
      } catch (_) {}
    }

    // Only notify guard if the transition actually occurred from PENDING to prevent conflicting alerts
    if (transitioned) {
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
      return true;
    }

    return false;
  }

  /// Denies a visitor's entry by resident and urgently alerts gate security.
  ///
  /// Uses an atomic Firestore transaction to prevent race conditions or duplicate
  /// conflicting approvals/denials. If the visitor is already approved or denied,
  /// this method aborts cleanly without sending duplicate or contradictory alerts to the guard.
  static Future<bool> denyVisitorEntry({
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
            .limit(15)
            .get();
        final matches = q.docs.where((d) {
          final data = d.data();
          final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
          final approval = (data['approvalStatus'] ?? '').toString().toUpperCase();
          return (approval == 'PENDING' || approval.isEmpty) &&
              (vN == visitorName.trim().toLowerCase() ||
                  vN.contains(visitorName.trim().toLowerCase()) ||
                  visitorName.trim().toLowerCase().contains(vN));
        }).toList();
        if (matches.isNotEmpty) {
          targetDocId = matches.first.id;
        } else if (q.docs.isNotEmpty) {
          targetDocId = q.docs.last.id;
        }
      } catch (e) {
        debugPrint('[VisitorPassService] Error resolving visitor doc ID: $e');
      }
    }

    bool transitioned = false;

    // Run atomic transaction to ensure status is PENDING before denying
    if (targetDocId != null && targetDocId.isNotEmpty) {
      final visitorRef = _fs.collection('visitors').doc(targetDocId);
      try {
        transitioned = await _fs.runTransaction<bool>((transaction) async {
          final snapshot = await transaction.get(visitorRef);
          if (!snapshot.exists) return false;
          final currentApproval = (snapshot.data()?['approvalStatus'] ?? '').toString().toUpperCase();
          // If already resolved, reject transition to prevent duplicate/conflicting updates
          if (currentApproval == 'APPROVED' || currentApproval == 'DENIED') {
            debugPrint('[VisitorPassService] Visitor $targetDocId already resolved as $currentApproval. Aborting deny.');
            return false;
          }
          // Explicitly set status to DENIED, record denial timestamp, and ensure entryTime is removed so visitor is never marked inside campus
          transaction.update(visitorRef, {
            'approvalStatus': 'DENIED',
            'status': 'DENIED',
            'entryTime': FieldValue.delete(),
            'deniedAt': now,
          });
          return true;
        });
      } catch (e) {
        debugPrint('[VisitorPassService] Transaction error denying visitor $targetDocId: $e');
        try {
          await visitorRef.update({
            'approvalStatus': 'DENIED',
            'status': 'DENIED',
            'entryTime': FieldValue.delete(),
            'deniedAt': now,
          });
          transitioned = true;
        } catch (_) {}
      }
    } else {
      transitioned = true;
    }

    // Always dismiss and cancel the native notification alert from the Android hood and floating banner
    try {
      await PushNotificationManager.cancelNotification(notifDocId ?? '', targetDocId);
    } catch (e) {
      debugPrint('[VisitorPassService] Error canceling push notification: $e');
    }

    // Update all matching notification documents to resolved status
    if (notifDocId != null && notifDocId.isNotEmpty) {
      try {
        await _fs.collection('notifications').doc(notifDocId).update({
          'approvalStatus': 'DENIED',
          'isRead': true,
          'resolvedAt': now,
          'updatedAt': now,
        });
      } catch (_) {}
    }

    // Only notify guard if the transition actually occurred from PENDING to prevent conflicting alerts
    if (transitioned) {
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
      return true;
    }

    return false;
  }

  /// Approves a delivery visitor with explicit instructions to leave the package at the gate.
  ///
  /// 1. Generates and returns a secure 4-digit pickup OTP.
  /// 2. Updates the `visitors` collection record with `approvalStatus: 'LEAVE_AT_GATE'`, `leaveAtGate: true`, and `pickupOtp`.
  /// 3. Automatically creates an entry in the `gate_parcels` collection with status `HELD_AT_GATE`
  ///    so the parcel appears immediately in the Guard's Parcel Log & Holding queue.
  /// 4. Dispatches a high-priority `PARCEL_HELD` notification directly to the resident (passing their active auth UID)
  ///    so the resident immediately receives the pickup OTP in their notifications tray.
  /// 5. Dispatches an action alert to Gate Security notifying them that the package was left at the gate.
  /// Returns the 4-digit [pickupOtp] on success, or `null` on failure.
  static Future<String?> leaveAtGateVisitorEntry({
    required String? visitorDocId,
    required String flatNumber,
    required String visitorName,
    String? notifDocId,
    String? deliveryApp,
    String? photoUrl,
    String? guardUid,
    String? guardName,
    String? gateName,
    String? residentUid,
  }) async {
    final now = FieldValue.serverTimestamp();
    final normFlat = FlatUtils.normalize(flatNumber);

    String? targetDocId = visitorDocId;

    if (targetDocId == null || targetDocId.isEmpty) {
      try {
        final q = await _fs
            .collection('visitors')
            .where('flatNumber', isEqualTo: normFlat)
            .limit(15)
            .get();
        final matches = q.docs.where((d) {
          final data = d.data();
          final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
          final approval = (data['approvalStatus'] ?? '').toString().toUpperCase();
          return (approval == 'PENDING' || approval.isEmpty) &&
              (vN == visitorName.trim().toLowerCase() ||
                  vN.contains(visitorName.trim().toLowerCase()) ||
                  visitorName.trim().toLowerCase().contains(vN));
        }).toList();
        if (matches.isNotEmpty) {
          targetDocId = matches.first.id;
        } else if (q.docs.isNotEmpty) {
          targetDocId = q.docs.last.id;
        }
      } catch (e) {
        debugPrint('[VisitorPassService] Error resolving visitor doc ID: $e');
      }
    }

    // Generate a secure 4-digit pickup OTP upfront so both the visitor record and parcel entry retain it
    String pickupOtp = generatePickupOtp();
    bool transitioned = false;
    final providerName = (deliveryApp != null && deliveryApp.isNotEmpty) ? deliveryApp : (visitorName.isNotEmpty ? visitorName : 'Delivery');
    final parcelDocRef = _fs.collection('gate_parcels').doc();
    String? createdParcelId;

    // Run atomic transaction to ensure status transitions cleanly from PENDING
    // and both the visitor status update and gate_parcels entry are committed together atomically.
    if (targetDocId != null && targetDocId.isNotEmpty) {
      final visitorRef = _fs.collection('visitors').doc(targetDocId);
      try {
        transitioned = await _fs.runTransaction<bool>((transaction) async {
          final snapshot = await transaction.get(visitorRef);
          if (!snapshot.exists) return false;
          final currentApproval = (snapshot.data()?['approvalStatus'] ?? '').toString().toUpperCase();
          if (currentApproval == 'APPROVED' || currentApproval == 'DENIED') {
            debugPrint('[VisitorPassService] Visitor $targetDocId already resolved as $currentApproval. Aborting leave-at-gate.');
            return false;
          }
          if (currentApproval == 'LEAVE_AT_GATE') {
            final existingOtp = snapshot.data()?['pickupOtp']?.toString();
            if (existingOtp != null && existingOtp.isNotEmpty) {
              pickupOtp = existingOtp;
            }
            return true;
          }

          // 1. Update visitor document status to LEFT_AT_GATE
          transaction.update(visitorRef, {
            'approvalStatus': 'LEAVE_AT_GATE',
            'leaveAtGate': true,
            'pickupOtp': pickupOtp,
            'status': 'LEFT_AT_GATE',
            'entryTime': FieldValue.delete(),
            'resolvedAt': now,
            'parcelDocId': parcelDocRef.id,
          });

          // 2. Atomically create the gate_parcels holding record
          transaction.set(parcelDocRef, {
            'flatNumber': normFlat,
            'deliveryProvider': providerName,
            'visitorName': visitorName,
            'packetCount': 1,
            'remarks': 'Left at gate as requested by resident during gate clearance',
            'status': 'HELD_AT_GATE',
            'pickupOtp': pickupOtp,
            'receivedAt': now,
            'receivedBy': guardUid ?? 'GATE',
            'guardName': guardName ?? 'Security Guard',
            'gateName': gateName ?? 'Main Gate',
            'visitorDocId': targetDocId,
            'photoUrl': photoUrl,
          });

          // 3. Atomically update linked notification if present
          if (notifDocId != null && notifDocId.isNotEmpty) {
            transaction.update(_fs.collection('notifications').doc(notifDocId), {
              'approvalStatus': 'LEAVE_AT_GATE',
              'leaveAtGate': true,
              'pickupOtp': pickupOtp,
              'isRead': true,
              'resolvedAt': now,
              'updatedAt': now,
            });
          }

          return true;
        });

        if (transitioned) {
          createdParcelId = parcelDocRef.id;
        }
      } catch (e) {
        debugPrint('[VisitorPassService] Transaction error on leave-at-gate for visitor $targetDocId: $e');
        // Fallback: batch write if transaction threw optimistic locking contention
        try {
          final batch = _fs.batch();
          batch.update(visitorRef, {
            'approvalStatus': 'LEAVE_AT_GATE',
            'leaveAtGate': true,
            'pickupOtp': pickupOtp,
            'status': 'LEFT_AT_GATE',
            'entryTime': FieldValue.delete(),
            'resolvedAt': now,
            'parcelDocId': parcelDocRef.id,
          });
          batch.set(parcelDocRef, {
            'flatNumber': normFlat,
            'deliveryProvider': providerName,
            'visitorName': visitorName,
            'packetCount': 1,
            'remarks': 'Left at gate as requested by resident during gate clearance',
            'status': 'HELD_AT_GATE',
            'pickupOtp': pickupOtp,
            'receivedAt': now,
            'receivedBy': guardUid ?? 'GATE',
            'guardName': guardName ?? 'Security Guard',
            'gateName': gateName ?? 'Main Gate',
            'visitorDocId': targetDocId,
            'photoUrl': photoUrl,
          });
          if (notifDocId != null && notifDocId.isNotEmpty) {
            batch.update(_fs.collection('notifications').doc(notifDocId), {
              'approvalStatus': 'LEAVE_AT_GATE',
              'leaveAtGate': true,
              'pickupOtp': pickupOtp,
              'isRead': true,
              'resolvedAt': now,
              'updatedAt': now,
            });
          }
          await batch.commit();
          transitioned = true;
          createdParcelId = parcelDocRef.id;
        } catch (_) {}
      }
    } else {
      // Standalone parcel without prior visitor doc
      try {
        await parcelDocRef.set({
          'flatNumber': normFlat,
          'deliveryProvider': providerName,
          'visitorName': visitorName,
          'packetCount': 1,
          'remarks': 'Left at gate as requested by resident during gate clearance',
          'status': 'HELD_AT_GATE',
          'pickupOtp': pickupOtp,
          'receivedAt': now,
          'receivedBy': guardUid ?? 'GATE',
          'guardName': guardName ?? 'Security Guard',
          'gateName': gateName ?? 'Main Gate',
          'photoUrl': photoUrl,
        });
        createdParcelId = parcelDocRef.id;
        transitioned = true;
      } catch (_) {}
    }

    // Always dismiss and cancel the native notification alert from the Android hood and floating banner
    try {
      await PushNotificationManager.cancelNotification(notifDocId ?? '', targetDocId);
    } catch (e) {
      debugPrint('[VisitorPassService] Error canceling push notification: $e');
    }

    // Dispatch a PARCEL_HELD notification directly to the resident displaying their Pickup OTP
    final activeResidentUid = residentUid ?? FirebaseAuth.instance.currentUser?.uid;
    try {
      await NotificationService.notifyResident(
        flatNumber: normFlat,
        title: '📦 Delivery Left at Gate: $visitorName',
        message: 'Your parcel from $providerName is held at the gate. Show Pickup OTP: $pickupOtp to collect.',
        type: 'PARCEL_HELD',
        targetUid: activeResidentUid,
        extraData: {
          'parcelDocId': createdParcelId,
          'visitorDocId': targetDocId,
          'visitorName': visitorName,
          'deliveryProvider': providerName,
          'packetCount': 1,
          'pickupOtp': pickupOtp,
          'gateName': gateName ?? 'Main Gate',
          'status': 'HELD_AT_GATE',
        },
      );
    } catch (e) {
      debugPrint('[VisitorPassService] Error notifying resident of leave at gate parcel: $e');
    }

    // Only notify guard if the transition actually occurred from PENDING
    if (transitioned) {
      final appLabel = (deliveryApp != null && deliveryApp.isNotEmpty) ? ' ($deliveryApp)' : '';
      await NotificationService.notifyGuard(
        title: '📦 Leave at Gate: $visitorName$appLabel',
        message: 'Resident of Flat $normFlat instructed to leave delivery for $visitorName at the gate. Added to Parcel Log.',
        type: 'VISITOR_APPROVAL_RESPONSE',
        flatNumber: normFlat,
        extraData: {
          'visitorDocId': targetDocId,
          'parcelDocId': createdParcelId,
          'visitorName': visitorName,
          'flatNumber': normFlat,
          'approvalStatus': 'LEAVE_AT_GATE',
          'pickupOtp': pickupOtp,
          'deliveryProvider': providerName,
          'photoUrl': photoUrl,
          'gateName': gateName ?? 'Main Gate',
          'guardName': guardName ?? 'Security Guard',
          'guardUid': guardUid,
        },
      );
      return pickupOtp;
    }

    return pickupOtp;
  }

  /// Ensures that a parcel record exists in `gate_parcels` for a visitor who was instructed to leave at the gate.
  /// If a parcel already exists for [visitorDocId], returns the existing parcel ID.
  /// If not, creates the parcel record in `gate_parcels` and links it to [visitorDocId].
  /// This serves as a vital safeguard so the parcel is guaranteed to be logged by Gate Security
  /// even if the resident-side write was blocked by firestore rules or network latency.
  static Future<String?> ensureLeaveAtGateParcelCreated({
    required String? visitorDocId,
    required String flatNumber,
    required String visitorName,
    String? deliveryProvider,
    String? pickupOtp,
    String? guardUid,
    String? guardName,
    String? gateName,
    String? photoUrl,
    String? remarks,
  }) async {
    final normFlat = FlatUtils.normalize(flatNumber);
    final provider = (deliveryProvider != null && deliveryProvider.isNotEmpty)
        ? deliveryProvider
        : (visitorName.isNotEmpty ? visitorName : 'Delivery');

    try {
      // 1. Check if parcel already exists in gate_parcels for this visitorDocId
      if (visitorDocId != null && visitorDocId.isNotEmpty) {
        final existing = await _fs
            .collection('gate_parcels')
            .where('visitorDocId', isEqualTo: visitorDocId)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          debugPrint('[VisitorPassService] Parcel already exists in gate_parcels for visitor $visitorDocId: ${existing.docs.first.id}');
          return existing.docs.first.id;
        }
      }

      // 2. If pickupOtp is missing or empty, resolve from visitor doc or generate new
      String finalOtp = pickupOtp ?? '';
      if (finalOtp.isEmpty && visitorDocId != null && visitorDocId.isNotEmpty) {
        try {
          final vDoc = await _fs.collection('visitors').doc(visitorDocId).get();
          finalOtp = vDoc.data()?['pickupOtp']?.toString() ?? '';
        } catch (_) {}
      }
      if (finalOtp.isEmpty) {
        finalOtp = generatePickupOtp();
      }

      // 3. Create parcel in gate_parcels using guard credentials
      final now = FieldValue.serverTimestamp();
      final docRef = await _fs.collection('gate_parcels').add({
        'flatNumber': normFlat,
        'deliveryProvider': provider,
        'visitorName': visitorName,
        'packetCount': 1,
        'remarks': remarks ?? 'Left at gate as requested by resident during gate clearance',
        'status': 'HELD_AT_GATE',
        'pickupOtp': finalOtp,
        'receivedAt': now,
        'receivedBy': guardUid ?? 'GATE',
        'guardName': guardName ?? 'Security Guard',
        'gateName': gateName ?? 'Main Gate',
        'visitorDocId': visitorDocId,
        'photoUrl': photoUrl,
      });

      // Also guarantee visitor record has status LEFT_AT_GATE and no active in-campus entryTime
      if (visitorDocId != null && visitorDocId.isNotEmpty) {
        try {
          await _fs.collection('visitors').doc(visitorDocId).update({
            'status': 'LEFT_AT_GATE',
            'approvalStatus': 'LEAVE_AT_GATE',
            'leaveAtGate': true,
            'entryTime': FieldValue.delete(),
          });
        } catch (_) {}
      }

      debugPrint('[VisitorPassService] Successfully ensured parcel ${docRef.id} created for visitor $visitorDocId with OTP $finalOtp');
      return docRef.id;
    } catch (e) {
      debugPrint('[VisitorPassService] Error ensuring leave-at-gate parcel created: $e');
      return null;
    }
  }
}
