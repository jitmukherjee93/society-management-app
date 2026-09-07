import 'package:cloud_firestore/cloud_firestore.dart';

/// Strongly-typed model representing a Flat Maintenance Due document
class MaintenanceDueModel {
  final String id;
  final String flatNumber;
  final String month;
  final double amount;
  final String status; // 'UNPAID', 'PAYMENT_PENDING_APPROVAL', 'PAID_ONLINE', 'PAID_OFFLINE_VERIFIED', 'PAID_VERIFIED'
  final String? paymentCategory; // 'ONLINE' or 'OFFLINE'
  final String? paymentMode;
  final String? uniqueId;
  final String? utrNumber;
  final String? referenceNumber;
  final String? receiptNumber;
  final String? rejectionReason;
  final double? baseMaintenance;
  final double? pujaSubscription;
  final double? carParkingCharges;
  final double? bikeParkingCharges;
  final int? carCount;
  final int? bikeCount;
  final DateTime? submittedAt;
  final DateTime? paidAt;
  final DateTime? verifiedAt;
  final String? verifiedBy;
  final DateTime? createdAt;

  MaintenanceDueModel({
    required this.id,
    required this.flatNumber,
    required this.month,
    required this.amount,
    required this.status,
    this.paymentCategory,
    this.paymentMode,
    this.uniqueId,
    this.utrNumber,
    this.referenceNumber,
    this.receiptNumber,
    this.rejectionReason,
    this.baseMaintenance,
    this.pujaSubscription,
    this.carParkingCharges,
    this.bikeParkingCharges,
    this.carCount,
    this.bikeCount,
    this.submittedAt,
    this.paidAt,
    this.verifiedAt,
    this.verifiedBy,
    this.createdAt,
  });

  bool get isPaid =>
      status == 'PAID_ONLINE' ||
      status == 'PAID_OFFLINE_VERIFIED' ||
      status == 'PAID_VERIFIED';

  bool get isUnderVerification =>
      status == 'PAYMENT_PENDING_APPROVAL' ||
      status == 'PAID_OFFLINE_PENDING';

  bool get isUnpaid => status == 'UNPAID';

  factory MaintenanceDueModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MaintenanceDueModel(
      id: doc.id,
      flatNumber: (data['flatNumber'] ?? '').toString(),
      month: (data['month'] ?? '').toString(),
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      status: (data['status'] ?? 'UNPAID').toString(),
      paymentCategory: data['paymentCategory']?.toString(),
      paymentMode: data['paymentMode']?.toString(),
      uniqueId: data['uniqueId']?.toString() ?? data['utrNumber']?.toString() ?? data['referenceNumber']?.toString() ?? data['offlineRef']?.toString(),
      utrNumber: data['utrNumber']?.toString(),
      referenceNumber: data['referenceNumber']?.toString(),
      receiptNumber: data['receiptNumber']?.toString(),
      rejectionReason: data['rejectionReason']?.toString(),
      baseMaintenance: (data['baseMaintenance'] as num?)?.toDouble(),
      pujaSubscription: (data['pujaSubscription'] as num?)?.toDouble(),
      carParkingCharges: (data['carParkingCharges'] as num?)?.toDouble(),
      bikeParkingCharges: (data['bikeParkingCharges'] as num?)?.toDouble(),
      carCount: (data['carCount'] as num?)?.toInt(),
      bikeCount: (data['bikeCount'] as num?)?.toInt(),
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate(),
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      verifiedAt: (data['verifiedAt'] as Timestamp?)?.toDate(),
      verifiedBy: data['verifiedBy']?.toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'flatNumber': flatNumber,
      'month': month,
      'amount': amount,
      'status': status,
      if (paymentCategory != null) 'paymentCategory': paymentCategory,
      if (paymentMode != null) 'paymentMode': paymentMode,
      if (uniqueId != null) 'uniqueId': uniqueId,
      if (utrNumber != null) 'utrNumber': utrNumber,
      if (referenceNumber != null) 'referenceNumber': referenceNumber,
      if (receiptNumber != null) 'receiptNumber': receiptNumber,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      if (baseMaintenance != null) 'baseMaintenance': baseMaintenance,
      if (pujaSubscription != null) 'pujaSubscription': pujaSubscription,
      if (carParkingCharges != null) 'carParkingCharges': carParkingCharges,
      if (bikeParkingCharges != null) 'bikeParkingCharges': bikeParkingCharges,
      if (carCount != null) 'carCount': carCount,
      if (bikeCount != null) 'bikeCount': bikeCount,
      if (verifiedBy != null) 'verifiedBy': verifiedBy,
    };
  }
}

