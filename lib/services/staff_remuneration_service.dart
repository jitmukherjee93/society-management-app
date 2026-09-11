import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../models/accounting_heads.dart';
import '../utils/storage_utils.dart';

class StaffPaymentRecordResult {
  final bool success;
  final String? voucherNumber;
  final String? error;

  StaffPaymentRecordResult({
    required this.success,
    this.voucherNumber,
    this.error,
  });
}

class StaffRemunerationStatus {
  final String role;
  final double budgetAmount;
  final bool isPaid;
  final double? paidAmount;
  final String? payeeName;
  final DateTime? paymentDate;
  final String? paymentMode;
  final String? voucherNumber;
  final String? documentUrl;
  final String? documentFileName;
  final String? referenceNumber;
  final String? transactionId;

  StaffRemunerationStatus({
    required this.role,
    required this.budgetAmount,
    required this.isPaid,
    this.paidAmount,
    this.payeeName,
    this.paymentDate,
    this.paymentMode,
    this.voucherNumber,
    this.documentUrl,
    this.documentFileName,
    this.referenceNumber,
    this.transactionId,
  });
}

class StaffRemunerationService {
  final FirebaseFirestore? _customFirestore;

  StaffRemunerationService({FirebaseFirestore? firestore}) : _customFirestore = firestore;

  FirebaseFirestore get firestore => _customFirestore ?? FirebaseFirestore.instance;

  /// Generate standardized expenditure voucher number
  String generateVoucherNumber() => AccountingConfig.generateVoucherCode('EXP');

  /// Record a staff remuneration payment with mandatory document attachment
  Future<StaffPaymentRecordResult> recordStaffPayment({
    required String staffRole,
    required String payeeName,
    required String remunerationMonth,
    required double amount,
    required DateTime paymentDate,
    required String paymentMode,
    required PlatformFile voucherFile,
    String? referenceNumber,
    String? description,
    required String recordedBy,
  }) async {
    try {
      final cleanRole = staffRole.trim();
      final cleanMonth = remunerationMonth.trim();

      // 1. Guard against duplicate payments in society_transactions
      final existingSnap = await firestore
          .collection('society_transactions')
          .where('accountHead', isEqualTo: 'Staff Remuneration')
          .where('staffRole', isEqualTo: cleanRole)
          .where('remunerationMonth', isEqualTo: cleanMonth)
          .get();

      final activePaid = existingSnap.docs.where((d) => d.data()['isVoid'] != true).toList();
      if (activePaid.isNotEmpty) {
        final existingVoucher = activePaid.first.data()['voucherNumber'] ?? 'Existing Voucher';
        return StaffPaymentRecordResult(
          success: false,
          error: '$cleanRole has already been paid for $cleanMonth (Voucher: $existingVoucher). Duplicate payment is strictly blocked application-wide.',
        );
      }

      // 2. Deterministic payroll registry document to prevent concurrent duplicate payments
      final registryDocId = 'PAYROLL_${cleanRole.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_')}_${cleanMonth.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_')}';
      final registryRef = firestore.collection('staff_payroll_registry').doc(registryDocId);
      final registrySnap = await registryRef.get();
      if (registrySnap.exists && registrySnap.data()?['isVoid'] != true) {
        final existingVoucher = registrySnap.data()?['voucherNumber'] ?? 'Existing Voucher';
        return StaffPaymentRecordResult(
          success: false,
          error: '$cleanRole has already been paid for $cleanMonth (Voucher: $existingVoucher). Duplicate payment is strictly blocked application-wide.',
        );
      }

      final voucherNumber = generateVoucherNumber();

      // 3. Upload voucher/salary slip
      final docUrl = await uploadFile(
        voucherFile,
        'society_accounts_vouchers/${voucherNumber}_${voucherFile.name}',
      );

      if (docUrl == null) {
        return StaffPaymentRecordResult(
          success: false,
          error: 'Failed to upload salary voucher file to cloud storage.',
        );
      }

      final notes = (description != null && description.trim().isNotEmpty)
          ? description.trim()
          : 'Staff Remuneration - $cleanRole for $cleanMonth';

      final txnData = {
        'type': 'EXPENDITURE',
        'voucherNumber': voucherNumber,
        'accountHead': 'Staff Remuneration',
        'category': 'Staff & Security',
        'amount': amount,
        'paidToOrReceivedFrom': payeeName.trim(),
        'paymentDate': Timestamp.fromDate(paymentDate),
        'paymentMode': paymentMode,
        'referenceNumber': referenceNumber?.trim() ?? '',
        'description': notes,
        'documentUrl': docUrl,
        'documentFileName': voucherFile.name,
        'staffRole': cleanRole,
        'remunerationMonth': cleanMonth,
        'recordedBy': recordedBy,
        'financialYear': AccountingConfig.currentFinancialYear,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 4. Atomically commit to society_transactions ledger AND registry
      final batch = firestore.batch();
      final txnRef = firestore.collection('society_transactions').doc();
      batch.set(txnRef, txnData);
      batch.set(registryRef, {
        ...txnData,
        'transactionId': txnRef.id,
      });
      await batch.commit();

      return StaffPaymentRecordResult(
        success: true,
        voucherNumber: voucherNumber,
      );
    } catch (e) {
      return StaffPaymentRecordResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Find if a staff role is already paid for a given month in a list of transaction docs
  StaffRemunerationStatus? findRoleStatus({
    required String role,
    required String month,
    required Iterable<dynamic> transactions,
  }) {
    final statusList = computeMonthlyStatus(selectedMonth: month, transactions: transactions);
    try {
      return statusList.firstWhere(
        (s) => s.role.trim().toLowerCase() == role.trim().toLowerCase() && s.isPaid,
      );
    } catch (_) {
      return null;
    }
  }

  /// Get status of all 11 staff remuneration positions for a selected month
  List<StaffRemunerationStatus> computeMonthlyStatus({
    required String selectedMonth,
    required Iterable<dynamic> transactions,
  }) {
    // Filter transactions for Staff Remuneration in the given month
    final Map<String, Map<String, dynamic>> paidMap = {};
    final Map<String, String> idMap = {};

    for (final doc in transactions) {
      final Map<String, dynamic> data;
      final String docId;
      if (doc is Map<String, dynamic>) {
        data = doc;
        docId = doc['id']?.toString() ?? '';
      } else if (doc is DocumentSnapshot) {
        data = (doc.data() as Map<String, dynamic>?) ?? {};
        docId = doc.id;
      } else {
        data = (doc.data() as Map<String, dynamic>);
        docId = doc.id?.toString() ?? '';
      }

      if (data['isVoid'] == true) continue;
      final type = (data['type'] ?? '').toString().toUpperCase();
      final head = (data['accountHead'] ?? '').toString();
      final month = (data['remunerationMonth'] ?? '').toString().trim();
      final role = (data['staffRole'] ?? '').toString().trim();

      if (type == 'EXPENDITURE' &&
          head == 'Staff Remuneration' &&
          month.toLowerCase() == selectedMonth.trim().toLowerCase() &&
          role.isNotEmpty) {
        paidMap[role] = data;
        idMap[role] = docId;
      }
    }

    // Build itemized list according to AccountingConfig.staffRemunerationMonthly
    return AccountingConfig.staffRemunerationMonthly.entries.map((entry) {
      final role = entry.key;
      final budgetAmt = entry.value;

      if (paidMap.containsKey(role)) {
        final data = paidMap[role]!;
        final pDate = (data['paymentDate'] as Timestamp?)?.toDate();

        return StaffRemunerationStatus(
          role: role,
          budgetAmount: budgetAmt,
          isPaid: true,
          paidAmount: (data['amount'] as num?)?.toDouble() ?? budgetAmt,
          payeeName: data['paidToOrReceivedFrom'] as String?,
          paymentDate: pDate,
          paymentMode: data['paymentMode'] as String?,
          voucherNumber: data['voucherNumber'] as String?,
          documentUrl: data['documentUrl'] as String?,
          documentFileName: data['documentFileName'] as String?,
          referenceNumber: data['referenceNumber'] as String?,
          transactionId: idMap[role],
        );
      } else {
        return StaffRemunerationStatus(
          role: role,
          budgetAmount: budgetAmt,
          isPaid: false,
        );
      }
    }).toList();
  }
}

