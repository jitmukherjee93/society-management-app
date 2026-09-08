import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  }) async {
    await _fs.collection('visitors').doc(visitorDocId).update({
      'status': 'CHECKED_IN',
      'entryTime': FieldValue.serverTimestamp(),
      'checkedInBy': guardUid,
    });
  }
}
