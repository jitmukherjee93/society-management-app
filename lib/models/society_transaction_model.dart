import 'package:cloud_firestore/cloud_firestore.dart';

/// Strongly-typed model for income and expense transactions in Society Accounts
class SocietyTransactionModel {
  final String id;
  final String type; // 'INCOME' or 'EXPENSE'
  final String voucherNumber;
  final String accountHead;
  final String category;
  final double amount;
  final String paidToOrReceivedFrom;
  final DateTime paymentDate;
  final String paymentMode;
  final String? referenceNumber;
  final String? uniqueId;
  final String? description;
  final String? linkedDueId;
  final String? documentUrl;
  final String? fileName;
  final String? paymentCategory;
  final String recordedBy;
  final DateTime? createdAt;

  SocietyTransactionModel({
    required this.id,
    required this.type,
    required this.voucherNumber,
    required this.accountHead,
    required this.category,
    required this.amount,
    required this.paidToOrReceivedFrom,
    required this.paymentDate,
    required this.paymentMode,
    this.referenceNumber,
    this.uniqueId,
    this.description,
    this.linkedDueId,
    this.documentUrl,
    this.fileName,
    this.paymentCategory,
    this.recordedBy = 'Admin',
    this.createdAt,
  });

  bool get isIncome => type == 'INCOME';
  bool get isExpense => type == 'EXPENSE';

  factory SocietyTransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SocietyTransactionModel(
      id: doc.id,
      type: (data['type'] ?? 'INCOME').toString(),
      voucherNumber: (data['voucherNumber'] ?? '').toString(),
      accountHead: (data['accountHead'] ?? '').toString(),
      category: (data['category'] ?? '').toString(),
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      paidToOrReceivedFrom: (data['paidToOrReceivedFrom'] ?? '').toString(),
      paymentDate: (data['paymentDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      paymentMode: (data['paymentMode'] ?? 'Cash').toString(),
      referenceNumber: data['referenceNumber']?.toString(),
      uniqueId: data['uniqueId']?.toString() ?? data['referenceNumber']?.toString(),
      description: data['description']?.toString(),
      linkedDueId: data['linkedDueId']?.toString(),
      documentUrl: data['documentUrl']?.toString(),
      fileName: data['fileName']?.toString(),
      paymentCategory: data['paymentCategory']?.toString(),
      recordedBy: (data['recordedBy'] ?? 'Admin').toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'voucherNumber': voucherNumber,
      'accountHead': accountHead,
      'category': category,
      'amount': amount,
      'paidToOrReceivedFrom': paidToOrReceivedFrom,
      'paymentDate': Timestamp.fromDate(paymentDate),
      'paymentMode': paymentMode,
      if (referenceNumber != null) 'referenceNumber': referenceNumber,
      if (uniqueId != null) 'uniqueId': uniqueId,
      if (description != null) 'description': description,
      if (linkedDueId != null) 'linkedDueId': linkedDueId,
      if (documentUrl != null) 'documentUrl': documentUrl,
      if (fileName != null) 'fileName': fileName,
      if (paymentCategory != null) 'paymentCategory': paymentCategory,
      'recordedBy': recordedBy,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

