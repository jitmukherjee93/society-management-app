import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/flat_utils.dart';

// ============================================================================
// CENTRAL NOTIFICATION DISPATCH SERVICE
// ============================================================================
// This service provides unified, decoupled notification delivery across all
// actor roles in the society:
//
// 1. Target Roles:
//    - `RESIDENT`: Scoped to a specific resident flat number and/or Firebase UID.
//    - `ADMIN`: Dispatched to managing committee members for actions like payment approvals.
//    - `GUARD`: Dispatched to security gate guards for pass approvals/denials.
//    - `ALL`: Broadcast notices for emergencies, AGM notices, water cuts, etc.
//
// 2. Multi-Key Resident Resolution (`targetUids`):
//    - To allow flexible Firestore security rules and multi-device querying,
//      resident notifications include `targetUid`, email, and normalized flat variants.
//
// 3. Performance & Batching:
//    - Supports optional `WriteBatch` integration for atomic billing/maintenance generation.
//    - Bulk read-receipt updates via `markAllAsRead` batch writes.
// ============================================================================

/// Centralized notification dispatch service for Residents, Admins, and Guards
class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Dispatches a notification to a specific resident identified by [flatNumber] and/or [targetUid].
  ///
  /// - Automatically resolves the resident's user document and email if only [flatNumber] is provided.
  /// - Populates `targetUids` list with flat lookup variants to support secure rule filtering.
  /// - Supports passing an optional [batch] to bundle with parent atomic operations.
  static Future<String?> notifyResident({
    required String flatNumber,
    required String title,
    required String message,
    required String type,
    String? targetUid,
    Map<String, dynamic>? extraData,
    WriteBatch? batch,
  }) async {
    try {
      final normFlat = FlatUtils.normalize(flatNumber);
      final lookupKeys = FlatUtils.getLookupKeys(normFlat);

      String? resolvedUid = targetUid;
      String? resolvedEmail;
      final targetUids = <String>{};
      if (resolvedUid != null) targetUids.add(resolvedUid);

      if (resolvedUid == null && normFlat.isNotEmpty) {
        final usersSnap = await _firestore
            .collection('users')
            .where('flatNumber', isEqualTo: normFlat)
            .limit(1)
            .get();

        if (usersSnap.docs.isNotEmpty) {
          final uDoc = usersSnap.docs.first;
          resolvedUid = uDoc.id;
          targetUids.add(resolvedUid);
          resolvedEmail = uDoc.data()['email']?.toString();
          if (resolvedEmail != null) targetUids.add(resolvedEmail);
        }
      }

      // Add all lookup variants to targetUids for flexible security rule evaluation
      targetUids.addAll(lookupKeys);

      final payload = <String, dynamic>{
        'targetUid': ?resolvedUid,
        'targetUids': targetUids.toList(),
        'targetRole': 'RESIDENT',
        'flatNumber': normFlat,
        'title': title,
        'message': message,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        ...?extraData,
      };

      if (batch != null) {
        final notifDocRef = _firestore.collection('notifications').doc();
        batch.set(notifDocRef, payload);
        return notifDocRef.id;
      } else {
        final docRef = await _firestore.collection('notifications').add(payload);
        return docRef.id;
      }
    } catch (e) {
      // Fallback logging without crashing UI flows
      return null;
    }
  }

  /// Dispatches an action alert to Society Admins (e.g., payment pending approval, helpdesk tickets).
  static Future<String?> notifyAdmin({
    required String title,
    required String message,
    required String type,
    String? flatNumber,
    Map<String, dynamic>? extraData,
    WriteBatch? batch,
  }) async {
    try {
      final payload = <String, dynamic>{
        'targetRole': 'ADMIN',
        'title': title,
        'message': message,
        'type': type,
        'isRead': false,
        if (flatNumber != null) 'flatNumber': FlatUtils.normalize(flatNumber),
        'createdAt': FieldValue.serverTimestamp(),
        ...?extraData,
      };

      if (batch != null) {
        final notifDocRef = _firestore.collection('notifications').doc();
        batch.set(notifDocRef, payload);
        return notifDocRef.id;
      } else {
        final docRef = await _firestore.collection('notifications').add(payload);
        return docRef.id;
      }
    } catch (e) {
      return null;
    }
  }

  /// Dispatches an action alert to Security Guards (e.g., resident approved/denied visitor entry).
  static Future<String?> notifyGuard({
    required String title,
    required String message,
    required String type,
    String? flatNumber,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final payload = <String, dynamic>{
        'targetRole': 'GUARD',
        'title': title,
        'message': message,
        'type': type,
        'isRead': false,
        if (flatNumber != null) 'flatNumber': FlatUtils.normalize(flatNumber),
        'createdAt': FieldValue.serverTimestamp(),
        ...?extraData,
      };
      final docRef = await _firestore.collection('notifications').add(payload);
      return docRef.id;
    } catch (_) {
      return null;
    }
  }

  /// Broadcasts a general notification to all society members (`targetRole: ALL`).
  static Future<void> broadcast({
    required String title,
    required String message,
    required String type,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'targetRole': 'ALL',
        'title': title,
        'message': message,
        'type': type,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        ...?extraData,
      });
    } catch (_) {}
  }

  /// Marks a specific notification as read in Firestore (`isRead: true`, `readAt: serverTimestamp`).
  static Future<void> markAsRead(String notificationId) async {
    if (notificationId.isEmpty) return;
    try {
      debugPrint('[NotificationService] markAsRead: $notificationId');
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[NotificationService] markAsRead succeeded for $notificationId');
    } catch (e) {
      debugPrint('[NotificationService] markAsRead failed for $notificationId: $e');
    }
  }

  /// Marks a list of notification IDs as read in Firestore via an atomic batch write.
  static Future<void> markAllAsRead(List<String> notificationIds) async {
    if (notificationIds.isEmpty) return;
    try {
      debugPrint('[NotificationService] markAllAsRead: ${notificationIds.length} items');
      final batch = _firestore.batch();
      for (final id in notificationIds) {
        if (id.isNotEmpty) {
          batch.update(_firestore.collection('notifications').doc(id), {
            'isRead': true,
            'readAt': FieldValue.serverTimestamp(),
          });
        }
      }
      await batch.commit();
      debugPrint('[NotificationService] markAllAsRead batch commit succeeded');
    } catch (e) {
      debugPrint('[NotificationService] markAllAsRead failed: $e');
    }
  }
}

