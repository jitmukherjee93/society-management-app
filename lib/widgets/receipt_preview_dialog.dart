import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/accounting_heads.dart';
import '../utils/currency_math.dart';
import '../services/receipt_pdf_service.dart';
import '../theme/app_colors.dart';
import '../utils/number_to_words.dart';

class ReceiptPreviewDialog extends StatefulWidget {
  final Map<String, dynamic> dueData;
  final String receiptNumber;
  final String dateStr;
  final String residentName;
  final String flatNumber;
  final String block;
  final String month;
  final String financialYear;
  final double baseMaintenance;
  final double carParkingCharges;
  final double bikeParkingCharges;
  final double pujaSubscription;
  final double fine;
  final double totalAmount;
  final String vehicleReg;
  final String paymentMode;
  final String referenceNumber;
  final String? bankName;
  final List<String>? maintenancePaidMonths;
  final List<String>? parkingPaidMonths;
  final List<String>? parkingExcludedMonths;

  const ReceiptPreviewDialog({
    super.key,
    required this.dueData,
    required this.receiptNumber,
    required this.dateStr,
    required this.residentName,
    required this.flatNumber,
    required this.block,
    required this.month,
    required this.financialYear,
    required this.baseMaintenance,
    required this.carParkingCharges,
    required this.bikeParkingCharges,
    required this.pujaSubscription,
    this.fine = 0.0,
    required this.totalAmount,
    required this.vehicleReg,
    required this.paymentMode,
    required this.referenceNumber,
    this.bankName,
    this.maintenancePaidMonths,
    this.parkingPaidMonths,
    this.parkingExcludedMonths,
  });

  /// Helper to format 2-Wheeler (T.W.) and 4-Wheeler (F.W.) vehicle registration numbers cleanly
  /// strictly constrained by what was billed (carCount / bikeCount or parking charges).
  static String formatVehicleNumbers({
    dynamic carReg,
    dynamic bikeReg,
    dynamic bike2Reg,
    String? fallback,
    int? carCount,
    int? bikeCount,
    double? carParkingCharges,
    double? bikeParkingCharges,
  }) {
    // If fallback is provided and contains formatted vehicle strings, check if valid
    bool isValid(String s) {
      if (s.isEmpty) return false;
      final up = s.toUpperCase();
      return up != '-' && up != '—' && up != 'N/A' && up != 'NONE' && up != 'NULL';
    }

    final double carAmt = carParkingCharges ?? (carCount != null ? carCount * 430.0 : 430.0);
    final double bikeAmt = bikeParkingCharges ?? (bikeCount != null ? bikeCount * 100.0 : 100.0);

    // If zero parking billed at all, do NOT show any vehicles
    if (carAmt <= 0 && bikeAmt <= 0) {
      return '—';
    }

    final List<String> parts = [];
    final cleanCar = (carReg ?? '').toString().trim();
    final cleanBike = (bikeReg ?? '').toString().trim();
    final cleanBike2 = (bike2Reg ?? '').toString().trim();

    if (carAmt > 0 && isValid(cleanCar)) {
      parts.add('4W: $cleanCar');
    }
    if (bikeAmt >= 100 && isValid(cleanBike)) {
      parts.add('2W: $cleanBike');
    }
    if (bikeAmt >= 200 && isValid(cleanBike2)) {
      parts.add('2W: $cleanBike2');
    }

    if (parts.isNotEmpty) {
      return parts.join(', ');
    }

    if (fallback != null && isValid(fallback.trim())) {
      return fallback.trim();
    }

    return '—';
  }

  /// Helper to fetch user document from Firestore by flat number, UID, or email
  static Future<Map<String, dynamic>?> fetchUserDetails({
    required String flatNumber,
    String? block,
    String? uid,
    String? email,
  }) async {
    final fs = FirebaseFirestore.instance;
    final cleanFlat = flatNumber.trim().toUpperCase();

    // 1. Check direct UID if provided
    if (uid != null && uid.trim().isNotEmpty) {
      try {
        final doc = await fs.collection('users').doc(uid.trim()).get();
        if (doc.exists && doc.data() != null) return doc.data();
      } catch (_) {}
    }

    // 2. Check direct doc with ID = flatNumber (e.g. 'C-102' or '102')
    if (cleanFlat.isNotEmpty) {
      try {
        final doc = await fs.collection('users').doc(cleanFlat).get();
        if (doc.exists && doc.data() != null) return doc.data();
      } catch (_) {}
    }

    // 3. Query by flatNumber
    if (cleanFlat.isNotEmpty) {
      try {
        final snap = await fs.collection('users').where('flatNumber', isEqualTo: cleanFlat).limit(1).get();
        if (snap.docs.isNotEmpty) return snap.docs.first.data();
      } catch (_) {}
    }

    // 4. Query without hyphen or with block prefix
    if (cleanFlat.contains('-')) {
      final numOnly = cleanFlat.split('-').last.trim();
      try {
        final snap = await fs.collection('users').where('flatNumber', isEqualTo: numOnly).limit(1).get();
        if (snap.docs.isNotEmpty) return snap.docs.first.data();
      } catch (_) {}
    } else if (block != null && block.trim().isNotEmpty) {
      final blockFlat = '${block.trim().toUpperCase()}-$cleanFlat';
      try {
        final snap = await fs.collection('users').where('flatNumber', isEqualTo: blockFlat).limit(1).get();
        if (snap.docs.isNotEmpty) return snap.docs.first.data();
      } catch (_) {}
    }

    // 5. Query by email
    if (email != null && email.trim().isNotEmpty) {
      try {
        final snap = await fs.collection('users').where('email', isEqualTo: email.trim()).limit(1).get();
        if (snap.docs.isNotEmpty) return snap.docs.first.data();
      } catch (_) {}
    }

    return null;
  }

  static void show({
    required BuildContext context,
    required Map<String, dynamic> dueData,
    String? receiptNumber,
    String? dateStr,
    String? residentName,
  }) {
    final rawFlat = (dueData['flatNumber'] ?? 'A-101').toString().trim().toUpperCase();
    final block = (dueData['block'] ?? (rawFlat.contains('-') ? rawFlat.split('-').first : 'A')).toString().trim().toUpperCase();
    final month = (dueData['month'] ?? 'Current Month').toString();
    final fy = (dueData['financialYear'] ?? '2026-2027').toString();

    final isMultiMonth = dueData['isMultiMonthPayment'] == true || dueData['multiMonthTotalAmount'] != null;

    final amt = (dueData['amount'] as num?)?.toDouble() ?? 0.0;
    final car = (dueData['carParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final bike = (dueData['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final carCount = (dueData['carCount'] as num?)?.toInt();
    final bikeCount = (dueData['bikeCount'] as num?)?.toInt();
    final totalParking = car + bike;

    final rawBase = (dueData['baseMaintenance'] as num?)?.toDouble();
    final rawPuja = (dueData['pujaSubscription'] as num?)?.toDouble() ?? 0.0;

    // Merge puja into base maintenance application-wide
    final base = (rawBase != null)
        ? ((rawPuja > 0 && rawBase < 350) ? (rawBase + rawPuja) : rawBase)
        : (amt >= totalParking ? amt - totalParking : amt);
    const puja = 0.0;

    List<String>? maintenancePaidMonths;
    if (dueData['maintenancePaidMonths'] is List) {
      maintenancePaidMonths = (dueData['maintenancePaidMonths'] as List).map((e) => e.toString()).toList();
    }
    List<String>? parkingPaidMonths;
    if (dueData['parkingPaidMonths'] is List) {
      parkingPaidMonths = (dueData['parkingPaidMonths'] as List).map((e) => e.toString()).toList();
    }
    List<String>? parkingExcludedMonths;
    if (dueData['parkingExcludedMonths'] is List) {
      parkingExcludedMonths = (dueData['parkingExcludedMonths'] as List).map((e) => e.toString()).toList();
    }

    final maintMonthsCount = (maintenancePaidMonths != null && maintenancePaidMonths.isNotEmpty)
        ? maintenancePaidMonths.length
        : 1;

    final carRate = (AccountingConfig.parkingRates['Four-Wheeler'] ?? 430).toDouble();
    final bikeRate = (AccountingConfig.parkingRates['Two-Wheeler'] ?? 100).toDouble();
    final effectiveCarCount = carCount ?? ((car > 0) ? 1 : 0);
    final effectiveBikeCount = bikeCount ?? ((bike > 0) ? 1 : 0);

    final double effectiveBaseMaint = isMultiMonth
        ? CurrencyMath.roundPaise(base * maintMonthsCount)
        : base;

    final double effectiveCarParking = isMultiMonth
        ? CurrencyMath.roundPaise(effectiveCarCount * carRate * (parkingPaidMonths?.length ?? 0))
        : car;

    final double effectiveBikeParking = isMultiMonth
        ? CurrencyMath.roundPaise(effectiveBikeCount * bikeRate * (parkingPaidMonths?.length ?? 0))
        : bike;

    final double effectiveFine = (dueData['fine'] as num?)?.toDouble() ?? (dueData['lateFee'] as num?)?.toDouble() ?? 0.0;

    final double effectiveTotalAmount = isMultiMonth
        ? ((dueData['multiMonthTotalAmount'] as num?)?.toDouble() ?? CurrencyMath.roundPaise(effectiveBaseMaint + effectiveCarParking + effectiveBikeParking + effectiveFine))
        : amt;

    final receiptNo = receiptNumber ??
        (dueData['receiptNumber'] ?? 'INC-2627-${(dueData['paidAt'] != null ? dueData['paidAt'].hashCode % 100000 : 10001).toString().padLeft(5, '0')}').toString();

    String formattedDate = dateStr ?? '';
    if (formattedDate.isEmpty) {
      if (dueData['verifiedAt'] != null && dueData['verifiedAt'].toDate != null) {
        formattedDate = DateFormat('dd/MM/yyyy').format(dueData['verifiedAt'].toDate());
      } else if (dueData['paidAt'] != null && dueData['paidAt'].toDate != null) {
        formattedDate = DateFormat('dd/MM/yyyy').format(dueData['paidAt'].toDate());
      } else {
        formattedDate = DateFormat('dd/MM/yyyy').format(DateTime.now());
      }
    }

    final mode = (dueData['paymentMode'] ?? (dueData['paymentCategory'] == 'OFFLINE' ? 'Cash to Cashier' : 'Online Payment')).toString();
    final ref = (dueData['uniqueId'] ?? dueData['utrNumber'] ?? dueData['referenceNumber'] ?? dueData['offlineRef'] ?? 'N/A').toString();

    final initialVReg = formatVehicleNumbers(
      carReg: dueData['carReg'] ?? dueData['carRegistration'] ?? dueData['fourWheelerReg'],
      bikeReg: dueData['bikeReg'] ?? dueData['bike1Registration'] ?? dueData['bikeRegistration'] ?? dueData['twoWheelerReg'],
      bike2Reg: dueData['bike2Reg'] ?? dueData['bike2Registration'],
      fallback: dueData['vehicleReg']?.toString(),
      carCount: effectiveCarCount,
      bikeCount: effectiveBikeCount,
      carParkingCharges: effectiveCarParking,
      bikeParkingCharges: effectiveBikeParking,
    );

    final initialName = residentName ??
        (dueData['residentName'] ??
         dueData['name'] ??
         dueData['ownerName'] ??
         dueData['submittedBy'] ??
         '').toString().trim();

    showDialog(
      context: context,
      builder: (ctx) => ReceiptPreviewDialog(
        dueData: dueData,
        receiptNumber: receiptNo,
        dateStr: formattedDate,
        residentName: initialName.isNotEmpty ? initialName : 'Flat Occupant / Member',
        flatNumber: rawFlat,
        block: block,
        month: month,
        financialYear: fy,
        baseMaintenance: effectiveBaseMaint,
        carParkingCharges: effectiveCarParking,
        bikeParkingCharges: effectiveBikeParking,
        pujaSubscription: puja,
        fine: effectiveFine,
        totalAmount: effectiveTotalAmount,
        vehicleReg: initialVReg,
        paymentMode: mode,
        referenceNumber: ref,
        maintenancePaidMonths: maintenancePaidMonths,
        parkingPaidMonths: parkingPaidMonths,
        parkingExcludedMonths: parkingExcludedMonths,
      ),
    );
  }

  @override
  State<ReceiptPreviewDialog> createState() => _ReceiptPreviewDialogState();
}

class _ReceiptPreviewDialogState extends State<ReceiptPreviewDialog> {
  late String _residentName;
  late String _vehicleReg;
  bool _isFetchingDetails = false;

  @override
  void initState() {
    super.initState();
    _residentName = widget.residentName;
    _vehicleReg = widget.vehicleReg;

    _checkAndFetchMissingDetails();
  }

  Future<void> _checkAndFetchMissingDetails() async {
    final bool nameNeedsFetch = _residentName.isEmpty ||
        _residentName == 'Flat Occupant / Member' ||
        _residentName == 'Resident';
    final bool vehicleNeedsFetch = (_vehicleReg.isEmpty ||
        _vehicleReg == '—' ||
        _vehicleReg == 'N/A' ||
        _vehicleReg == '-') && (widget.carParkingCharges > 0 || widget.bikeParkingCharges > 0);

    if (nameNeedsFetch || vehicleNeedsFetch) {
      setState(() => _isFetchingDetails = true);
      try {
        final uData = await ReceiptPreviewDialog.fetchUserDetails(
          flatNumber: widget.flatNumber,
          block: widget.block,
          uid: widget.dueData['submittedByUid'] ?? widget.dueData['uid'],
          email: widget.dueData['submittedByEmail'] ?? widget.dueData['email'] ?? widget.dueData['username'],
        );

        if (uData != null && mounted) {
          setState(() {
            if (nameNeedsFetch) {
              final fetchedName = (uData['name'] ?? uData['ownerName'] ?? uData['residentName'] ?? uData['submittedBy'] ?? '').toString().trim();
              if (fetchedName.isNotEmpty) {
                _residentName = fetchedName;
              }
            }
            if (vehicleNeedsFetch && (widget.carParkingCharges > 0 || widget.bikeParkingCharges > 0)) {
              final formattedVehicles = ReceiptPreviewDialog.formatVehicleNumbers(
                carReg: uData['carReg'] ?? uData['carRegistration'] ?? uData['fourWheelerReg'] ?? uData['carNo'],
                bikeReg: uData['bikeReg'] ?? uData['bike1Registration'] ?? uData['bikeRegistration'] ?? uData['twoWheelerReg'] ?? uData['bikeNo'],
                bike2Reg: uData['bike2Reg'] ?? uData['bike2Registration'],
                fallback: _vehicleReg,
                carParkingCharges: widget.carParkingCharges,
                bikeParkingCharges: widget.bikeParkingCharges,
              );
              if (formattedVehicles.isNotEmpty && formattedVehicles != '—') {
                _vehicleReg = formattedVehicles;
              }
            }
          });
        }
      } catch (e) {
        debugPrint('ReceiptPreviewDialog fetch error: $e');
      } finally {
        if (mounted) {
          setState(() => _isFetchingDetails = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountInWords = NumberToWords.convert(widget.totalAmount);
    final totalParking = widget.carParkingCharges + widget.bikeParkingCharges;

    final int mCount = (widget.maintenancePaidMonths != null && widget.maintenancePaidMonths!.isNotEmpty)
        ? widget.maintenancePaidMonths!.length
        : 1;
    final int pCount = (widget.parkingPaidMonths != null && widget.parkingPaidMonths!.isNotEmpty)
        ? widget.parkingPaidMonths!.length
        : mCount;
    final double monthlyBaseRate = widget.baseMaintenance / mCount;
    final double monthlyCarRate = (widget.carParkingCharges > 0 && pCount > 0)
        ? (widget.carParkingCharges / pCount)
        : 0.0;
    final double monthlyBikeRate = (widget.bikeParkingCharges > 0 && pCount > 0)
        ? (widget.bikeParkingCharges / pCount)
        : 0.0;

    // Months list for matrix
    const months = [
      'APRIL', 'MAY', 'JUNE', 'JULY', 'AUG.', 'SEPT.',
      'OCT.', 'NOV.', 'DEC.', 'JAN.', 'FEB.', 'MAR.'
    ];

    // Build set of active month codes (support single or multi-month)
    final Set<String> activeMonthCodes = {};

    void addMatchingCodes(String text) {
      final u = text.toUpperCase();
      if (u.contains('APR')) activeMonthCodes.add('APRIL');
      if (u.contains('MAY')) activeMonthCodes.add('MAY');
      if (u.contains('JUN')) activeMonthCodes.add('JUNE');
      if (u.contains('JUL')) activeMonthCodes.add('JULY');
      if (u.contains('AUG')) activeMonthCodes.add('AUG.');
      if (u.contains('SEP')) activeMonthCodes.add('SEPT.');
      if (u.contains('OCT')) activeMonthCodes.add('OCT.');
      if (u.contains('NOV')) activeMonthCodes.add('NOV.');
      if (u.contains('DEC')) activeMonthCodes.add('DEC.');
      if (u.contains('JAN')) activeMonthCodes.add('JAN.');
      if (u.contains('FEB')) activeMonthCodes.add('FEB.');
      if (u.contains('MAR')) activeMonthCodes.add('MAR.');
    }

    if (widget.maintenancePaidMonths != null && widget.maintenancePaidMonths!.isNotEmpty) {
      for (final m in widget.maintenancePaidMonths!) {
        addMatchingCodes(m);
      }
    } else {
      addMatchingCodes(widget.month);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 780),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dialog Action Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Official Receipt Voucher (${widget.receiptNumber})',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        if (_isFetchingDetails) ...[
                          const SizedBox(width: 10),
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                          ),
                        ],
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Printable Voucher View
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDFAF4), // Subtle paper texture tint
                      border: Border.all(color: Colors.black, width: 2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. RECEIPT Title
                        const Center(
                          child: Text(
                            'RECEIPT',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.underline,
                              letterSpacing: 1.5,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // 2. Heavy Box Association Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black, width: 2.2),
                          ),
                          child: const Center(
                            child: Text(
                              "RAMKRISHNAPURAM RESIDENTS' WELFARE ASSOCIATION",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // 3. Address
                        const Center(
                          child: Text(
                            '156/1, MAHARAJA NANDA KUMAR ROAD (S)\nBARANAGAR, KOLKATA - 700 036',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, height: 1.3, color: Colors.black),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 4. Receipt No. & Date Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.black, width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  const Text('No.  ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(widget.receiptNumber, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary)),
                                ],
                              ),
                            ),
                            Text('Dated  ${widget.dateStr}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // 5. Received with thanks
                        Row(
                          children: [
                            const Text('Received with thanks from Sri / Smt.  ', style: TextStyle(fontSize: 12.5)),
                            Expanded(
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.black, width: 1, style: BorderStyle.solid)),
                                ),
                                padding: const EdgeInsets.only(bottom: 2, left: 4),
                                child: Text(
                                  _residentName.isNotEmpty ? _residentName : 'Flat Occupant / Member',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // 6. Block & Flat No.
                        Row(
                          children: [
                            const Text('Block  ', style: TextStyle(fontSize: 12.5)),
                            Container(
                              width: 80,
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.black, width: 1, style: BorderStyle.solid)),
                              ),
                              padding: const EdgeInsets.only(bottom: 2, left: 4),
                              child: Text(widget.block, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                            const Text('   Flat No.  ', style: TextStyle(fontSize: 12.5)),
                            Expanded(
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.black, width: 1, style: BorderStyle.solid)),
                                ),
                                padding: const EdgeInsets.only(bottom: 2, left: 4),
                                child: Text(widget.flatNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ),
                            const Text('   as follows :', style: TextStyle(fontSize: 12.5)),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 7. Middle Matrix & Right Table
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left & Center content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                       // Rates per month
                                       Column(
                                         crossAxisAlignment: CrossAxisAlignment.start,
                                         children: [
                                           const Text('Rate Per Month', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                                           const SizedBox(height: 2),
                                           Text('Maint. :  Rs. ${monthlyBaseRate.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                                           if (monthlyCarRate > 0) ...[
                                             const SizedBox(height: 2),
                                             Text('Car Park : Rs. ${monthlyCarRate.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                                           ],
                                           if (monthlyBikeRate > 0) ...[
                                             const SizedBox(height: 2),
                                             Text('Bike Park : Rs. ${monthlyBikeRate.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                                           ],
                                           if (mCount > 1) ...[
                                             const SizedBox(height: 4),
                                             Text('Total ($mCount Mos):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black87)),
                                             Text('Maint: Rs. ${widget.baseMaintenance.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                                             if (widget.carParkingCharges > 0)
                                               Text('Car Park: Rs. ${widget.carParkingCharges.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                                             if (widget.bikeParkingCharges > 0)
                                               Text('Bike Park: Rs. ${widget.bikeParkingCharges.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                                           ],
                                         ],
                                       ),
                                      const SizedBox(width: 14),

                                      // Center 12-Month Matrix
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            const Text('Maintenance Charge for the month of :', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 3,
                                              runSpacing: 3,
                                              children: months.map((m) {
                                                final isSelected = activeMonthCodes.contains(m);
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isSelected ? Colors.black : Colors.white,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.black, width: 1),
                                                  ),
                                                  child: Text(
                                                    m,
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.normal,
                                                      color: isSelected ? Colors.white : Colors.black,
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                            const SizedBox(height: 3),
                                            Text('YEAR: ${widget.financialYear}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (totalParking > 0) ...[
                                    const SizedBox(height: 8),

                                    // Car / Bike parking line
                                    Row(
                                      children: [
                                        Text(
                                          (widget.carParkingCharges > 0 && widget.bikeParkingCharges > 0)
                                              ? 'Car & Two-Wheeler Parking Charge for: '
                                              : (widget.bikeParkingCharges > 0 && widget.carParkingCharges <= 0)
                                                  ? 'Two-Wheeler Parking Charge for: '
                                                  : 'Car Parking Charge for: ',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        Expanded(
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              border: Border(bottom: BorderSide(color: Colors.black, width: 0.8, style: BorderStyle.solid)),
                                            ),
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Text(
                                              (widget.parkingPaidMonths != null && widget.parkingPaidMonths!.isNotEmpty)
                                                  ? widget.parkingPaidMonths!.join(', ')
                                                  : widget.month,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (widget.parkingExcludedMonths != null && widget.parkingExcludedMonths!.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        'Note: Parking charges opted-out for: ${widget.parkingExcludedMonths!.join(', ')}',
                                        style: const TextStyle(fontSize: 9.5, fontStyle: FontStyle.italic, color: Colors.black54),
                                      ),
                                    ],
                                    const SizedBox(height: 6),

                                    // T.W / F.W line
                                    Row(
                                      children: [
                                        const Text('T.W/F.W. No. ', style: TextStyle(fontSize: 11)),
                                        Expanded(
                                          flex: 5,
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              border: Border(bottom: BorderSide(color: Colors.black, width: 0.8, style: BorderStyle.solid)),
                                            ),
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Text(
                                              _vehicleReg.isNotEmpty ? _vehicleReg : '—',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                        ),
                                        const Text('   Rs. ', style: TextStyle(fontSize: 11)),
                                        Expanded(
                                          flex: 3,
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              border: Border(bottom: BorderSide(color: Colors.black, width: 0.8, style: BorderStyle.solid)),
                                            ),
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Text(
                                              totalParking.toStringAsFixed(2),
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 6),

                                  // Cash / Cheque / Ref Line
                                  Row(
                                    children: [
                                      const Text('Mode / Ref ', style: TextStyle(fontSize: 11)),
                                      Expanded(
                                        flex: 4,
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: Colors.black, width: 0.8, style: BorderStyle.solid)),
                                          ),
                                          padding: const EdgeInsets.only(left: 4),
                                          child: Text(
                                            widget.referenceNumber.isNotEmpty ? widget.referenceNumber : widget.paymentMode,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const Text('   Date ', style: TextStyle(fontSize: 11)),
                                      Container(
                                        width: 75,
                                        decoration: const BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.black, width: 0.8, style: BorderStyle.solid)),
                                        ),
                                        padding: const EdgeInsets.only(left: 2),
                                        child: Text(widget.dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),

                                  // Rupees in words
                                  Row(
                                    children: [
                                      const Text('(Rupees ', style: TextStyle(fontSize: 11)),
                                      Expanded(
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            border: Border(bottom: BorderSide(color: Colors.black, width: 0.8, style: BorderStyle.solid)),
                                          ),
                                          padding: const EdgeInsets.only(left: 4),
                                          child: Text(
                                            amountInWords,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                          ),
                                        ),
                                      ),
                                      const Text(' )', style: TextStyle(fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 14),

                                  // Electronically generated disclaimer
                                  const Text(
                                    '* This is an electronically generated receipt and does not require a physical signature.',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, fontSize: 9.5, color: Colors.black87),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // RIGHT AREA: Labels (Maintenance, Parking, Special Fund, TOTAL) + TABLE (Rs. | P.)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Labels column aligned with rows of table
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const SizedBox(height: 20), // Header spacer
                                    Container(
                                      height: 24,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 6),
                                      child: const Text(
                                        'Maintenance',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                                      ),
                                    ),
                                    Container(
                                      height: 24,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 6),
                                      child: const Text(
                                        'Parking',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                                      ),
                                    ),
                                    Container(
                                      height: 24,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 6),
                                      child: const Text(
                                        'Special Fund',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                                      ),
                                    ),
                                    if (widget.fine > 0)
                                      Container(
                                        height: 24,
                                        alignment: Alignment.centerRight,
                                        padding: const EdgeInsets.only(right: 6),
                                        child: const Text(
                                          'Late Fine',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                                        ),
                                      ),
                                    Container(
                                      height: 24,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 6),
                                      child: const Text(
                                        'TOTAL',
                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),

                                // Right Table Container
                                Container(
                                  width: 110,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.black, width: 1.4),
                                  ),
                                  child: Column(
                                    children: [
                                      // Header
                                      Container(
                                        height: 20,
                                        decoration: const BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.black, width: 1.2)),
                                        ),
                                        child: const Row(
                                          children: [
                                            Expanded(
                                              flex: 65,
                                              child: Center(child: Text('Rs.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                            ),
                                            SizedBox(width: 1, height: 20, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black))),
                                            Expanded(
                                              flex: 35,
                                              child: Center(child: Text('P.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Row 1: Maint
                                      _buildTableAmountRow(widget.baseMaintenance),
                                      // Row 2: Car/Bike Park
                                      _buildTableAmountRow(totalParking),
                                      // Row 3: Special Fund / Puja
                                      _buildTableAmountRow(widget.pujaSubscription),
                                      // Optional Row: Late Fine
                                      if (widget.fine > 0)
                                        _buildTableAmountRow(widget.fine),
                                      // TOTAL Row
                                      Container(
                                        height: 24,
                                        decoration: const BoxDecoration(
                                          border: Border(top: BorderSide(color: Colors.black, width: 1.8)),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              flex: 65,
                                              child: Container(
                                                alignment: Alignment.centerRight,
                                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                                child: Text(
                                                  widget.totalAmount.floor().toString(),
                                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 1, height: 24, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black))),
                                            Expanded(
                                              flex: 35,
                                              child: Container(
                                                alignment: Alignment.center,
                                                child: Text(
                                                  ((widget.totalAmount - widget.totalAmount.floor()) * 100).round().toString().padLeft(2, '0'),
                                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // 8. Footer: Tagline
                        const Center(
                          child: Text(
                            'Regular monthly payment of Maintenance Charge, Makes our Task easy.',
                            style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom Action Bar
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download PDF'),
                      onPressed: () async {
                        DateTime parsedDate = DateTime.now();
                        if (widget.dueData['verifiedAt'] != null && widget.dueData['verifiedAt'].toDate != null) {
                          parsedDate = widget.dueData['verifiedAt'].toDate();
                        } else if (widget.dueData['paidAt'] != null && widget.dueData['paidAt'].toDate != null) {
                          parsedDate = widget.dueData['paidAt'].toDate();
                        }

                        await ReceiptPdfService.downloadReceiptPdf(
                          receiptNumber: widget.receiptNumber,
                          date: parsedDate,
                          residentName: _residentName,
                          block: widget.block,
                          flatNumber: widget.flatNumber,
                          billingMonth: widget.month,
                          financialYear: widget.financialYear,
                          baseMaintenance: widget.baseMaintenance,
                          carParkingCharges: widget.carParkingCharges,
                          bikeParkingCharges: widget.bikeParkingCharges,
                          pujaSubscription: widget.pujaSubscription,
                          fine: widget.fine,
                          totalAmount: widget.totalAmount,
                          vehicleReg: _vehicleReg,
                          paymentMode: widget.paymentMode,
                          referenceNumber: widget.referenceNumber,
                          bankName: widget.bankName,
                          maintenancePaidMonths: widget.maintenancePaidMonths,
                          parkingPaidMonths: widget.parkingPaidMonths,
                          parkingExcludedMonths: widget.parkingExcludedMonths,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print'),
                      onPressed: () async {
                        DateTime parsedDate = DateTime.now();
                        if (widget.dueData['verifiedAt'] != null && widget.dueData['verifiedAt'].toDate != null) {
                          parsedDate = widget.dueData['verifiedAt'].toDate();
                        } else if (widget.dueData['paidAt'] != null && widget.dueData['paidAt'].toDate != null) {
                          parsedDate = widget.dueData['paidAt'].toDate();
                        }

                        await ReceiptPdfService.printReceipt(
                          receiptNumber: widget.receiptNumber,
                          date: parsedDate,
                          residentName: _residentName,
                          block: widget.block,
                          flatNumber: widget.flatNumber,
                          billingMonth: widget.month,
                          financialYear: widget.financialYear,
                          baseMaintenance: widget.baseMaintenance,
                          carParkingCharges: widget.carParkingCharges,
                          bikeParkingCharges: widget.bikeParkingCharges,
                          pujaSubscription: widget.pujaSubscription,
                          fine: widget.fine,
                          totalAmount: widget.totalAmount,
                          vehicleReg: _vehicleReg,
                          paymentMode: widget.paymentMode,
                          referenceNumber: widget.referenceNumber,
                          bankName: widget.bankName,
                          maintenancePaidMonths: widget.maintenancePaidMonths,
                          parkingPaidMonths: widget.parkingPaidMonths,
                          parkingExcludedMonths: widget.parkingExcludedMonths,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableAmountRow(double amount) {
    final rupees = amount.floor();
    final paise = ((amount - rupees) * 100).round();

    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 65,
            child: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text(amount > 0 ? rupees.toString() : '', style: const TextStyle(fontSize: 10.5)),
            ),
          ),
          const SizedBox(width: 1, height: 20, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black))),
          Expanded(
            flex: 35,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(amount > 0 ? paise.toString().padLeft(2, '0') : '', style: const TextStyle(fontSize: 10.5)),
            ),
          ),
        ],
      ),
    );
  }
}
