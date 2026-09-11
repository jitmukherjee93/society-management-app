import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/flat_utils.dart';
import 'notification_service.dart';

/// Centralized service for generating, validating, and managing security visitor gate passes
class VisitorPassService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// Generates a random 6-digit numeric OTP code
  static String generatePassCode() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  /// Creates a visitor pass entry in Firestore
  static Future<Map<String, dynamic>> createVisitorPass({
    required String residentUid,
    required String flatNumber,
    required String visitorName,
    required String phone,
    String purpose = 'Guest / Personal',
  }) async {
    final code = generatePassCode();

    final docRef = await _fs.collection('visitors').add({
      'visitorName': visitorName,
      'phone': phone,
      'flatNumber': flatNumber,
      'hostFlatNumber': flatNumber,
      'residentUid': residentUid,
      'hostUid': residentUid,
      'purpose': purpose,
      'passCode': code,
      'status': 'PENDING', // PENDING -> CHECKED_IN
      'createdAt': FieldValue.serverTimestamp(),
    });

    return {
      'id': docRef.id,
      'passCode': code,
    };
  }

  /// Verifies a 6-digit passcode for guard gate check-in
  static Future<QueryDocumentSnapshot<Map<String, dynamic>>?> verifyPassCode(String code) async {
    final snap = await _fs
        .collection('visitors')
        .where('passCode', isEqualTo: code.trim())
        .where('status', isEqualTo: 'PENDING')
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return snap.docs.first;
  }

  /// Marks a visitor pass as checked-in
  static Future<void> checkInVisitor({
    required String visitorDocId,
    required String? guardUid,
    String? guardName,
    String? gateName,
  }) async {
    await _fs.collection('visitors').doc(visitorDocId).update({
      'status': 'CHECKED_IN',
      'approvalStatus': 'APPROVED',
      'entryTime': FieldValue.serverTimestamp(),
      'checkedInBy': guardUid,
      'guardName': guardName,
      'gateName': gateName,
    });
  }

  /// Logs a walk-in / unscheduled visitor directly by the guard
  static Future<String> logWalkInVisitor({
    required String visitorName,
    required String phone,
    required String flatNumber,
    required String purpose,
    String? vehicleNumber,
    required String guardUid,
    String? guardName,
    String? gateName,
  }) async {
    final normFlat = FlatUtils.normalize(flatNumber);

    final docRef = await _fs.collection('visitors').add({
      'visitorName': visitorName.trim(),
      'phone': phone.trim(),
      'flatNumber': normFlat,
      'hostFlatNumber': normFlat,
      'purpose': purpose,
      'vehicleNumber': vehicleNumber?.trim().toUpperCase() ?? '',
      'status': 'CHECKED_IN',
      'approvalStatus': 'PENDING',
      'isWalkIn': true,
      'entryTime': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'checkedInBy': guardUid,
      'guardName': guardName ?? 'Security Guard',
      'gateName': gateName ?? 'Main Gate',
    });

    // Notify resident of the visiting flat
    await NotificationService.notifyResident(
      flatNumber: normFlat,
      title: 'Visitor At Gate: ${visitorName.trim()}',
      message: '${visitorName.trim()} ($purpose) has checked in at ${gateName ?? 'Security Gate'}.',
      type: 'VISITOR_CHECK_IN',
      extraData: {
        'visitorDocId': docRef.id,
        'visitorName': visitorName.trim(),
        'phone': phone.trim(),
        'purpose': purpose,
        'gateName': gateName ?? 'Security Gate',
        'guardName': guardName ?? 'Security Guard',
        'vehicleNumber': vehicleNumber?.trim().toUpperCase() ?? '',
      },
    );

    return docRef.id;
  }

  /// Marks a visitor as checked-out upon leaving campus
  static Future<void> checkOutVisitor({
    required String visitorDocId,
    required String? guardUid,
  }) async {
    await _fs.collection('visitors').doc(visitorDocId).update({
      'status': 'CHECKED_OUT',
      'exitTime': FieldValue.serverTimestamp(),
      'checkedOutBy': guardUid,
    });
  }

  /// Stream of active visitors currently inside campus
  static Stream<QuerySnapshot<Map<String, dynamic>>> getActiveVisitorsStream() {
    return _fs
        .collection('visitors')
        .where('status', isEqualTo: 'CHECKED_IN')
        .snapshots();
  }

  // ─── Gate Parcels & Delivery Operations ───────────────────────────────────

  /// Logs a parcel left at the gate by courier/delivery agents
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

  /// Marks a parcel as collected / handed over to resident
  static Future<void> markParcelCollected({
    required String parcelDocId,
    required String? guardUid,
    String? collectedBy,
  }) async {
    await _fs.collection('gate_parcels').doc(parcelDocId).update({
      'status': 'COLLECTED',
      'collectedAt': FieldValue.serverTimestamp(),
      'handedOverBy': guardUid,
      'collectedBy': collectedBy ?? 'Resident',
    });
  }

  /// Stream of parcels waiting at security gate
  static Stream<QuerySnapshot<Map<String, dynamic>>> getPendingParcelsStream() {
    return _fs
        .collection('gate_parcels')
        .where('status', isEqualTo: 'HELD_AT_GATE')
        .snapshots();
  }

  // ─── Emergency Security SOS ───────────────────────────────────────────────

  /// Broadcasts an emergency alert from the guard gate
  static Future<void> triggerEmergencyAlert({
    required String emergencyType,
    required String guardName,
    required String gateName,
    String? details,
  }) async {
    final title = 'EMERGENCY ALERT: $emergencyType';
    final message = '$emergencyType emergency reported at $gateName by $guardName. ${details ?? ''}'.trim();

    await NotificationService.notifyAdmin(
      title: title,
      message: message,
      type: 'EMERGENCY',
    );

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

  /// Approves a visitor's entry by resident and alerts gate security
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
            .get();
        final matches = q.docs.where((d) {
          final data = d.data();
          final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
          final vStatus = data['status']?.toString();
          return vStatus == 'CHECKED_IN' &&
                 (vN == visitorName.trim().toLowerCase() ||
                  vN.contains(visitorName.trim().toLowerCase()) ||
                  visitorName.trim().toLowerCase().contains(vN));
        }).toList();
        if (matches.isNotEmpty) {
          targetDocId = matches.first.id;
        } else {
          final checkedIn = q.docs.where((d) => d.data()['status'] == 'CHECKED_IN').toList();
          if (checkedIn.isNotEmpty) {
            targetDocId = checkedIn.last.id;
          }
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
            .get();
        final matches = q.docs.where((d) {
          final data = d.data();
          final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
          final vStatus = data['status']?.toString();
          return vStatus == 'CHECKED_IN' &&
                 (vN == visitorName.trim().toLowerCase() ||
                  vN.contains(visitorName.trim().toLowerCase()) ||
                  visitorName.trim().toLowerCase().contains(vN));
        }).toList();
        if (matches.isNotEmpty) {
          targetDocId = matches.first.id;
        } else {
          final checkedIn = q.docs.where((d) => d.data()['status'] == 'CHECKED_IN').toList();
          if (checkedIn.isNotEmpty) {
            targetDocId = checkedIn.last.id;
          }
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
