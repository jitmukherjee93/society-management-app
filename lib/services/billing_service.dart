import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/accounting_heads.dart';
import '../utils/flat_utils.dart';
import '../utils/app_formatters.dart';
import '../utils/currency_math.dart';
import 'notification_service.dart';

/// Centralized service for society maintenance generation, verification,
/// cash collection, rejection, and atomic ledger reconciliation.
class BillingService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// Generates a unique voucher number for accounting entries
  static String generateVoucherCode() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'INC-2627-${(timestamp % 100000).toString().padLeft(5, '0')}';
  }

  /// Verifies an online/offline payment submission, marks due as PAID_VERIFIED,
  /// posts an income transaction to the society ledger, and notifies the resident.
  static Future<String> verifyPayment({
    required String dueId,
    required Map<String, dynamic> data,
    String verifiedBy = 'Admin',
  }) async {
    final rawFlat = (data['flatNumber'] ?? 'Unknown').toString();
    final normFlat = FlatUtils.normalize(rawFlat);
    final month = (data['month'] ?? 'Current Month').toString();
    final double amount = CurrencyMath.roundPaise((data['amount'] as num?)?.toDouble() ?? 0.0);
    final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? 'N/A').toString().trim();
    final paymentCategory = (data['paymentCategory'] ?? 'ONLINE').toString();
    final paymentMode = (data['paymentMode'] ?? 'Online Payment').toString();

    // Determine budget block head via FlatUtils
    final head = FlatUtils.getMaintenanceHead(normFlat);
    final voucherCode = generateVoucherCode();

    final batch = _fs.batch();

    // 1. Update maintenance due document
    final dueRef = _fs.collection('maintenance_dues').doc(dueId);
    batch.update(dueRef, {
      'status': 'PAID_VERIFIED',
      'receiptNumber': voucherCode,
      'approvedAt': FieldValue.serverTimestamp(),
      'verifiedAt': FieldValue.serverTimestamp(),
      'verifiedBy': verifiedBy,
      'paymentCategory': paymentCategory,
      'paymentMode': paymentMode,
      'uniqueId': uniqueId,
      'utrNumber': uniqueId,
      'referenceNumber': uniqueId,
    });

    // 2. Post income entry into society accounts ledger
    final txnRef = _fs.collection('society_transactions').doc();
    batch.set(txnRef, {
      'type': 'INCOME',
      'voucherNumber': voucherCode,
      'accountHead': head,
      'category': 'Maintenance Collection',
      'amount': amount,
      'paidToOrReceivedFrom': 'Flat $normFlat',
      'paymentDate': FieldValue.serverTimestamp(),
      'paymentMode': paymentMode,
      'referenceNumber': uniqueId,
      'description': 'Maintenance collection for $month from Flat $normFlat (Ref: $uniqueId)',
      'linkedDueId': dueId,
      'uniqueId': uniqueId,
      'utrNumber': uniqueId,
      'paymentCategory': paymentCategory,
      'recordedBy': verifiedBy,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 3. Dispatch notification in the same atomic batch
    await NotificationService.notifyResident(
      flatNumber: normFlat,
      title: 'Maintenance Payment Approved ($voucherCode)',
      message: 'Your maintenance payment of ${AppFormatters.currency(amount)} for $month (Ref: $uniqueId) has been verified and posted to Society Accounts. Receipt No: $voucherCode. Tap to view and download your official receipt.',
      type: 'MAINTENANCE_PAYMENT_APPROVED',
      extraData: {
        'dueId': dueId,
        'amount': amount,
        'month': month,
        'receiptNumber': voucherCode,
        'uniqueId': uniqueId,
        'paymentCategory': paymentCategory,
        'paymentMode': paymentMode,
        'flatNumber': normFlat,
      },
      batch: batch,
    );

    // Commit all operations atomically
    await batch.commit();
    return voucherCode;
  }

  /// Records an offline cash collection at the society office, generates a receipt voucher,
  /// posts the ledger entry, and notifies the resident.
  static Future<String> recordCashPayment({
    required String dueId,
    required String flatNumber,
    required String month,
    required double amount,
    String notes = 'Received cash at Society Office',
    String recordedBy = 'Admin',
  }) async {
    final voucherCode = generateVoucherCode();
    final normFlat = FlatUtils.normalize(flatNumber);
    final head = FlatUtils.getMaintenanceHead(normFlat);
    final roundedAmount = CurrencyMath.roundPaise(amount);

    final batch = _fs.batch();

    // 1. Update maintenance due
    final dueRef = _fs.collection('maintenance_dues').doc(dueId);
    batch.update(dueRef, {
      'status': 'PAID_OFFLINE_VERIFIED',
      'receiptNumber': voucherCode,
      'paidAt': FieldValue.serverTimestamp(),
      'verifiedAt': FieldValue.serverTimestamp(),
      'verifiedBy': recordedBy,
      'paymentCategory': 'OFFLINE',
      'paymentMode': 'Cash to Cashier',
      'uniqueId': 'CASH-OFFICE',
      'referenceNumber': 'CASH-OFFICE',
      'cashierNotes': notes,
    });

    // 2. Post transaction entry in society ledger
    final txnRef = _fs.collection('society_transactions').doc();
    batch.set(txnRef, {
      'type': 'INCOME',
      'voucherNumber': voucherCode,
      'accountHead': head,
      'category': 'Maintenance Collection (Cash)',
      'amount': roundedAmount,
      'paidToOrReceivedFrom': 'Flat $normFlat',
      'paymentDate': FieldValue.serverTimestamp(),
      'paymentMode': 'Cash',
      'referenceNumber': 'CASH-OFFICE',
      'description': 'Cash collection for $month from Flat $normFlat ($notes)',
      'linkedDueId': dueId,
      'uniqueId': 'CASH-OFFICE',
      'paymentCategory': 'OFFLINE',
      'recordedBy': recordedBy,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 3. Dispatch notification in batch
    await NotificationService.notifyResident(
      flatNumber: normFlat,
      title: 'Cash Payment Receipt ($voucherCode)',
      message: 'Cash payment of ${AppFormatters.currency(roundedAmount)} for $month has been collected at Society Office and confirmed. Receipt No: $voucherCode. Tap to view and download your official receipt.',
      type: 'MAINTENANCE_PAYMENT_APPROVED',
      extraData: {
        'dueId': dueId,
        'amount': roundedAmount,
        'month': month,
        'receiptNumber': voucherCode,
        'paymentCategory': 'OFFLINE',
        'paymentMode': 'Cash',
        'flatNumber': normFlat,
      },
      batch: batch,
    );

    await batch.commit();
    return voucherCode;
  }

  /// Rejects a payment submission, resets status to UNPAID with reason, and alerts resident.
  static Future<void> rejectPayment({
    required String dueId,
    required String flatNumber,
    required String month,
    required String paymentMode,
    required String uniqueId,
    required String reason,
  }) async {
    final normFlat = FlatUtils.normalize(flatNumber);

    await _fs.collection('maintenance_dues').doc(dueId).update({
      'status': 'UNPAID',
      'rejectionReason': reason,
      'rejectedAt': FieldValue.serverTimestamp(),
    });

    await NotificationService.notifyResident(
      flatNumber: normFlat,
      title: 'Payment Submission Rejected ($month)',
      message: 'Your payment submission for $month ($paymentMode, Ref: $uniqueId) was rejected by Admin. Reason: $reason. Please meet the society authorities in person to resolve conflicts.',
      type: 'MAINTENANCE_PAYMENT_REJECTED',
      extraData: {
        'dueId': dueId,
        'uniqueId': uniqueId,
        'rejectionReason': reason,
        'month': month,
        'flatNumber': normFlat,
        'actionRequired': 'MEET_AUTHORITIES_IN_PERSON',
      },
    );
  }

  /// Resets a bill back to UNPAID and removes all corresponding ledger entries to prevent orphan records.
  static Future<void> resetDueToUnpaid({
    required String dueId,
    required String flatNumber,
  }) async {
    // 1. Fetch any linked ledger entries
    final txSnap = await _fs
        .collection('society_transactions')
        .where('linkedDueId', isEqualTo: dueId)
        .get();

    final batch = _fs.batch();

    // 2. Reset the maintenance due document
    final dueRef = _fs.collection('maintenance_dues').doc(dueId);
    batch.update(dueRef, {
      'status': 'UNPAID',
      'paidAt': FieldValue.delete(),
      'verifiedAt': FieldValue.delete(),
      'verifiedBy': FieldValue.delete(),
      'approvedAt': FieldValue.delete(),
      'uniqueId': FieldValue.delete(),
      'utrNumber': FieldValue.delete(),
      'referenceNumber': FieldValue.delete(),
      'chequeNumber': FieldValue.delete(),
      'chequeBank': FieldValue.delete(),
      'paymentCategory': FieldValue.delete(),
      'offlineRef': FieldValue.delete(),
      'receiptNumber': FieldValue.delete(),
      'submittedBy': FieldValue.delete(),
      'submittedByEmail': FieldValue.delete(),
      'rejectionReason': FieldValue.delete(),
      'paymentMode': FieldValue.delete(),
      'cashierNotes': FieldValue.delete(),
    });

    // 3. Atomically remove linked ledger transaction records to maintain accounting integrity
    for (final doc in txSnap.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  /// Calculates total breakdown for a given flat based on block and vehicle ownership
  static Map<String, double> calculateFlatBreakdown({
    required String block,
    int carCount = 0,
    int bikeCount = 0,
  }) {
    final cleanBlock = block.trim().toUpperCase();
    final baseMaintenance = (AccountingConfig.blockRateBreakup[cleanBlock]?['total'] ?? 450).toDouble();
    final carParkingRate = (AccountingConfig.parkingRates['Four-Wheeler'] ?? 430).toDouble();
    final bikeParkingRate = (AccountingConfig.parkingRates['Two-Wheeler'] ?? 100).toDouble();
    final carParking = carCount * carParkingRate;
    final bikeParking = bikeCount * bikeParkingRate;
    final total = CurrencyMath.roundPaise(baseMaintenance + carParking + bikeParking);

    return {
      'baseMaintenance': baseMaintenance,
      'pujaSubscription': 0.0,
      'carParkingCharges': carParking,
      'bikeParkingCharges': bikeParking,
      'totalAmount': total,
    };
  }
}
