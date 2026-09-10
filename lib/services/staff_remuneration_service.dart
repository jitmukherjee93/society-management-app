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
      // 1. Guard against duplicate payments for the same role + month
      final existingSnap = await firestore
          .collection('society_transactions')
          .where('accountHead', isEqualTo: 'Staff Remuneration')
          .where('staffRole', isEqualTo: staffRole)
          .where('remunerationMonth', isEqualTo: remunerationMonth)
          .get();

      final activePaid = existingSnap.docs.where((d) => d.data()['isVoid'] != true).toList();
      if (activePaid.isNotEmpty) {
        final existingVoucher = activePaid.first.data()['voucherNumber'] ?? 'Existing Voucher';
        return StaffPaymentRecordResult(
          success: false,
          error: '$staffRole has already been paid for $remunerationMonth ($existingVoucher).',
        );
      }

      final voucherNumber = generateVoucherNumber();

      // 2. Upload voucher/salary slip
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
          : 'Staff Remuneration - $staffRole for $remunerationMonth';

      // 2. Post atomic transaction to society_transactions ledger
      await firestore.collection('society_transactions').add({
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
        'staffRole': staffRole,
        'remunerationMonth': remunerationMonth,
        'recordedBy': recordedBy,
        'createdAt': FieldValue.serverTimestamp(),
      });

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

  /// Get status of all 11 staff remuneration positions for a selected month
  List<StaffRemunerationStatus> computeMonthlyStatus({
    required String selectedMonth,
    required List<QueryDocumentSnapshot> transactions,
  }) {
    // Filter transactions for Staff Remuneration in the given month
    final Map<String, QueryDocumentSnapshot> paidMap = {};

    for (final doc in transactions) {
      final data = doc.data() as Map<String, dynamic>;
      final type = (data['type'] ?? '').toString().toUpperCase();
      final head = (data['accountHead'] ?? '').toString();
      final month = (data['remunerationMonth'] ?? '').toString();
      final role = (data['staffRole'] ?? '').toString();

      if (type == 'EXPENDITURE' &&
          head == 'Staff Remuneration' &&
          month == selectedMonth &&
          role.isNotEmpty) {
        paidMap[role] = doc;
      }
    }

    // Build itemized list according to AccountingConfig.staffRemunerationMonthly
    return AccountingConfig.staffRemunerationMonthly.entries.map((entry) {
      final role = entry.key;
      final budgetAmt = entry.value;

      if (paidMap.containsKey(role)) {
        final doc = paidMap[role]!;
        final data = doc.data() as Map<String, dynamic>;
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
          transactionId: doc.id,
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

