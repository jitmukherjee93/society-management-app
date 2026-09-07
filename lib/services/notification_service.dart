import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/flat_utils.dart';

/// Centralized notification dispatch service for Residents, Admins, and Guards
class NotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Dispatches a notification to a specific resident by Flat Number or UID
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
        if (resolvedUid != null) 'targetUid': resolvedUid,
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

  /// Dispatches an action alert to Society Admins
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

  /// Broadcasts a general notification to all society members
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
}

