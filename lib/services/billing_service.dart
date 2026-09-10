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

    final isMultiMonth = data['isMultiMonthPayment'] == true;
    final List<String> maintMonths = data['maintenancePaidMonths'] != null
        ? List<String>.from(data['maintenancePaidMonths'] as List)
        : [month];
    final List<String> parkMonths = data['parkingPaidMonths'] != null
        ? List<String>.from(data['parkingPaidMonths'] as List)
        : (data['parkingIncluded'] != false && ((data['carParkingCharges'] as num?)?.toDouble() ?? 0) > 0 ? [month] : []);
    final int cCount = ((data['carCount'] as num?)?.toInt() ?? 0);
    final int bCount = ((data['bikeCount'] as num?)?.toInt() ?? 0);

    // 1. Update primary maintenance due document
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

    // If multi-month, update sibling dues matching this reference/parent
    if (isMultiMonth) {
      final siblingSnap = await _fs
          .collection('maintenance_dues')
          .where('flatNumber', isEqualTo: normFlat)
          .where('uniqueId', isEqualTo: uniqueId)
          .get();

      for (final sDoc in siblingSnap.docs) {
        if (sDoc.id != dueId) {
          batch.update(sDoc.reference, {
            'status': 'PAID_VERIFIED',
            'receiptNumber': voucherCode,
            'approvedAt': FieldValue.serverTimestamp(),
            'verifiedAt': FieldValue.serverTimestamp(),
            'verifiedBy': verifiedBy,
            'paymentCategory': paymentCategory,
            'paymentMode': paymentMode,
          });
        }
      }
    }

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
      'description': 'Maintenance collection for ${data['multiMonthSummary'] ?? month} from Flat $normFlat (Ref: $uniqueId)',
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
      message: 'Your maintenance payment of ${AppFormatters.currency(amount)} for ${data['multiMonthSummary'] ?? month} (Ref: $uniqueId) has been verified and posted to Society Accounts. Receipt No: $voucherCode. Tap to view and download your official receipt.',
      type: 'MAINTENANCE_PAYMENT_APPROVED',
      extraData: {
        'dueId': dueId,
        'amount': amount,
        'month': data['multiMonthSummary'] ?? month,
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

    // 4. Trigger asynchronous parking gap check if applicable
    if (maintMonths.length > parkMonths.length && (cCount > 0 || bCount > 0)) {
      await checkAndAlertParkingGaps(
        flatNumber: normFlat,
        maintenanceMonths: maintMonths,
        parkingMonths: parkMonths,
        carCount: cCount,
        bikeCount: bCount,
      );
    }

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

  /// Calculates itemized totals for multiple selected months with per-month parking toggles.
  static Map<String, dynamic> calculateMultiMonthBreakdown({
    required String block,
    int carCount = 0,
    int bikeCount = 0,
    required List<Map<String, dynamic>> monthConfigs, // [{'month': 'September 2026', 'includeParking': true}]
    double fine = 0.0,
  }) {
    final cleanBlock = block.trim().toUpperCase();
    final baseMaintenanceRate = (AccountingConfig.blockRateBreakup[cleanBlock]?['total'] ?? 450).toDouble();
    final carRate = (AccountingConfig.parkingRates['Four-Wheeler'] ?? 430).toDouble();
    final bikeRate = (AccountingConfig.parkingRates['Two-Wheeler'] ?? 100).toDouble();
    final monthlyParkingRate = (carCount * carRate) + (bikeCount * bikeRate);

    double totalBaseMaintenance = 0.0;
    double totalCarParking = 0.0;
    double totalBikeParking = 0.0;
    final List<String> maintenanceMonths = [];
    final List<String> parkingMonths = [];
    final List<String> parkingExcludedMonths = [];

    for (final cfg in monthConfigs) {
      final m = cfg['month']?.toString() ?? '';
      if (m.isEmpty) continue;
      maintenanceMonths.add(m);
      totalBaseMaintenance += baseMaintenanceRate;

      final bool incPark = cfg['includeParking'] == true;
      if (incPark && (carCount > 0 || bikeCount > 0)) {
        parkingMonths.add(m);
        totalCarParking += carCount * carRate;
        totalBikeParking += bikeCount * bikeRate;
      } else if (carCount > 0 || bikeCount > 0) {
        parkingExcludedMonths.add(m);
      }
    }

    final double totalAmount = CurrencyMath.roundPaise(totalBaseMaintenance + totalCarParking + totalBikeParking + fine);

    return {
      'baseMaintenanceRate': baseMaintenanceRate,
      'monthlyParkingRate': monthlyParkingRate,
      'totalBaseMaintenance': CurrencyMath.roundPaise(totalBaseMaintenance),
      'totalCarParking': CurrencyMath.roundPaise(totalCarParking),
      'totalBikeParking': CurrencyMath.roundPaise(totalBikeParking),
      'totalParking': CurrencyMath.roundPaise(totalCarParking + totalBikeParking),
      'fine': CurrencyMath.roundPaise(fine),
      'totalAmount': totalAmount,
      'maintenanceMonths': maintenanceMonths,
      'parkingMonths': parkingMonths,
      'parkingExcludedMonths': parkingExcludedMonths,
      'monthCount': maintenanceMonths.length,
    };
  }

  /// Submits a multi-month payment for resident approval. Updates primary due and creates/updates
  /// future monthly dues, atomically linking them to the payment reference.
  static Future<void> submitMultiMonthPayment({
    required String primaryDueId,
    required String flatNumber,
    required String block,
    required List<Map<String, dynamic>> monthConfigs,
    required String paymentMode,
    required String paymentCategory, // 'ONLINE' or 'OFFLINE'
    required String uniqueId,
    required double totalAmount,
    String? submittedByUid,
    String? submittedByEmail,
    String? chequeNumber,
    String? chequeBank,
    Map<String, dynamic>? extraResidentData,
  }) async {
    final normFlat = FlatUtils.normalize(flatNumber);
    final userCarCount = ((extraResidentData?['carCount'] ?? (extraResidentData?['isCarOwner'] == true ? 1 : 0)) as num).toInt();
    final userBikeCount = ((extraResidentData?['bikeCount'] ?? ((extraResidentData?['isBikeOwner'] == true ? 1 : 0) + (extraResidentData?['hasBike2'] == true ? 1 : 0))) as num).toInt();

    final double dueFine = ((extraResidentData?['fine'] as num?)?.toDouble() ?? 0.0);

    final currentCalMonth = AppFormatters.monthYear(DateTime.now());
    final int curMonthIdx = AccountingConfig.getMonthIndex(currentCalMonth);

    // Rule 1: User can only pay an old month's maintenance when Admin issues it with fine.
    for (final cfg in monthConfigs) {
      final m = cfg['month']?.toString() ?? '';
      final mIdx = AccountingConfig.getMonthIndex(m);
      if (curMonthIdx != -1 && mIdx != -1 && mIdx < curMonthIdx) {
        if (dueFine <= 0) {
          throw Exception("Past month ($m) maintenance can only be paid when Admin issues it with a late fine.");
        }
      }
    }

    // Rule 2: If primary month is an overdue past month, do not allow multi-month advance payment.
    if (monthConfigs.length > 1) {
      final firstMonth = monthConfigs.first['month']?.toString() ?? '';
      final firstIdx = AccountingConfig.getMonthIndex(firstMonth);
      if (curMonthIdx != -1 && firstIdx != -1 && firstIdx < curMonthIdx) {
        throw Exception("Multi-month advance payment is locked for overdue accounts. Please settle past dues first.");
      }
    }

    final breakdown = calculateMultiMonthBreakdown(
      block: block,
      carCount: userCarCount,
      bikeCount: userBikeCount,
      monthConfigs: monthConfigs,
      fine: dueFine,
    );

    final maintenanceMonths = List<String>.from(breakdown['maintenanceMonths'] as List);
    final parkingMonths = List<String>.from(breakdown['parkingMonths'] as List);
    final parkingExcludedMonths = List<String>.from(breakdown['parkingExcludedMonths'] as List);

    final cleanBlock = block.trim().toUpperCase();
    final baseRate = (AccountingConfig.blockRateBreakup[cleanBlock]?['total'] ?? 450).toDouble();
    final carRate = (AccountingConfig.parkingRates['Four-Wheeler'] ?? 430).toDouble();
    final bikeRate = (AccountingConfig.parkingRates['Two-Wheeler'] ?? 100).toDouble();

    final batch = _fs.batch();

    // 1. Fetch any existing due records for these months to update them in batch
    final existingDuesSnap = await _fs
        .collection('maintenance_dues')
        .where('flatNumber', isEqualTo: normFlat)
        .where('month', whereIn: maintenanceMonths.take(10).toList())
        .get();

    final existingMap = <String, DocumentSnapshot>{};
    for (final doc in existingDuesSnap.docs) {
      final m = (doc.data()['month'] ?? '').toString();
      if (m.isNotEmpty) existingMap[m] = doc;
    }

    final String primaryMonth = maintenanceMonths.isNotEmpty ? maintenanceMonths.first : 'Multiple Months';
    final existingPrimaryDoc = existingMap[primaryMonth];
    final String effectivePrimaryDueId = (existingPrimaryDoc != null)
        ? existingPrimaryDoc.id
        : (primaryDueId.trim().isNotEmpty ? primaryDueId.trim() : _fs.collection('maintenance_dues').doc().id);

    final String monthSummary = maintenanceMonths.length > 1
        ? '${maintenanceMonths.first} – ${maintenanceMonths.last} (${maintenanceMonths.length} Months)'
        : primaryMonth;

    for (final cfg in monthConfigs) {
      final m = cfg['month']?.toString() ?? '';
      if (m.isEmpty) continue;
      final bool incPark = cfg['includeParking'] == true;
      final double mCar = incPark ? userCarCount * carRate : 0.0;
      final double mBike = incPark ? userBikeCount * bikeRate : 0.0;
      final double mFine = (m == primaryMonth) ? dueFine : 0.0;
      final double mTotal = CurrencyMath.roundPaise(baseRate + mCar + mBike + mFine);

      final existingDoc = existingMap[m];
      final docRef = (existingDoc != null)
          ? existingDoc.reference
          : (m == primaryMonth ? _fs.collection('maintenance_dues').doc(effectivePrimaryDueId) : _fs.collection('maintenance_dues').doc());

      final payload = <String, dynamic>{
        'flatNumber': normFlat,
        'block': cleanBlock,
        'month': m,
        'financialYear': AccountingConfig.currentFinancialYear,
        'amount': mTotal,
        'baseMaintenance': baseRate,
        'pujaSubscription': 0.0,
        'carParkingCharges': mCar,
        'bikeParkingCharges': mBike,
        if (mFine > 0) 'fine': mFine,
        'carCount': userCarCount,
        'bikeCount': userBikeCount,
        'parkingIncluded': incPark,
        'status': 'PAYMENT_PENDING_APPROVAL',
        'paymentCategory': paymentCategory,
        'paymentMode': paymentMode,
        'uniqueId': uniqueId,
        'utrNumber': uniqueId,
        'referenceNumber': uniqueId,
        'submittedAt': FieldValue.serverTimestamp(),
        'submittedByUid': ?submittedByUid,
        'submittedByEmail': ?submittedByEmail,
        if (chequeNumber != null && chequeNumber.isNotEmpty) 'chequeNumber': chequeNumber,
        if (chequeBank != null && chequeBank.isNotEmpty) 'chequeBank': chequeBank,
        'isMultiMonthPayment': maintenanceMonths.length > 1,
        'multiMonthParentDueId': effectivePrimaryDueId,
        'multiMonthSummary': monthSummary,
        'multiMonthTotalAmount': totalAmount,
        'maintenancePaidMonths': maintenanceMonths,
        'parkingPaidMonths': parkingMonths,
        'parkingExcludedMonths': parkingExcludedMonths,
        'rejectionReason': FieldValue.delete(),
      };

      if (extraResidentData?['residentName'] != null) {
        payload['residentName'] = extraResidentData!['residentName'];
      }

      batch.set(docRef, payload, SetOptions(merge: true));
    }

    // 2. Alert Admin with multi-month details
    String notifMsg = 'Flat $normFlat submitted $paymentCategory payment ($paymentMode) of ${AppFormatters.currency(totalAmount)} for $monthSummary with Ref: $uniqueId.';
    if (parkingExcludedMonths.isNotEmpty && (userCarCount > 0 || userBikeCount > 0)) {
      notifMsg += ' (Note: Parking charges excluded for: ${parkingExcludedMonths.join(', ')})';
    }

    await NotificationService.notifyAdmin(
      title: 'Multi-Month Payment Approval: Flat $normFlat',
      message: notifMsg,
      type: 'MAINTENANCE_PAYMENT_APPROVAL_REQUEST',
      flatNumber: normFlat,
      extraData: {
        'dueId': effectivePrimaryDueId,
        'amount': totalAmount,
        'month': monthSummary,
        'months': maintenanceMonths,
        'parkingMonths': parkingMonths,
        'parkingExcludedMonths': parkingExcludedMonths,
        'uniqueId': uniqueId,
        'paymentCategory': paymentCategory,
        'paymentMode': paymentMode,
        'isMultiMonth': maintenanceMonths.length > 1,
      },
      batch: batch,
    );

    await batch.commit();
  }

  /// Dispatches an alert to Admins if a flat has maintenance paid through future months,
  /// but car or bike parking charges are lapsed or unpaid.
  static Future<void> checkAndAlertParkingGaps({
    required String flatNumber,
    required List<String> maintenanceMonths,
    required List<String> parkingMonths,
    required int carCount,
    required int bikeCount,
  }) async {
    if (carCount == 0 && bikeCount == 0) return; // No vehicle owned

    final missingParking = maintenanceMonths.where((m) => !parkingMonths.contains(m)).toList();
    if (missingParking.isEmpty) return; // All covered

    final normFlat = FlatUtils.normalize(flatNumber);
    final lastMaint = maintenanceMonths.isNotEmpty ? maintenanceMonths.last : 'Unknown';
    final lastPark = parkingMonths.isNotEmpty ? parkingMonths.last : 'None';

    await NotificationService.notifyAdmin(
      title: 'Parking Lapsed Alert: Flat $normFlat',
      message: 'Flat $normFlat has maintenance covered through $lastMaint, but vehicle parking is only paid through $lastPark (Unpaid parking for: ${missingParking.join(', ')}). Committee check advised.',
      type: 'PARKING_LAPSED_ALERT',
      flatNumber: normFlat,
      extraData: {
        'flatNumber': normFlat,
        'maintenanceCoveredUntil': lastMaint,
        'parkingCoveredUntil': lastPark,
        'unpaidParkingMonths': missingParking,
        'carCount': carCount,
        'bikeCount': bikeCount,
      },
    );
  }
}
