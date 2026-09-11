import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/accounting_heads.dart';
import '../../../utils/app_formatters.dart';
import '../../../utils/flat_utils.dart';
import '../../../services/billing_service.dart';
import '../../../services/notification_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_decorations.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_feedback.dart';
import '../../../widgets/receipt_preview_dialog.dart';

class GenerateMaintenanceTab extends StatefulWidget {
  const GenerateMaintenanceTab({super.key});

  @override
  State<GenerateMaintenanceTab> createState() => _GenerateMaintenanceTabState();
}

class _GenerateMaintenanceTabState extends State<GenerateMaintenanceTab> {
  final _currencyFmt = AppFormatters.currencyFormat;

  String _selectedMonth = '';
  bool _isProcessing = false;
  String? _resultMsg;

  // Records filter state
  String _filterStatus = 'ALL';
  String _searchQuery = '';
  final Set<String> _processingDues = {};

  final _lateFineController = TextEditingController();

  List<String> get _monthsList => AccountingConfig.financialYearMonths;

  bool get _isPastMonth => AccountingConfig.isMonthPast(_selectedMonth);

  @override
  void initState() {
    super.initState();
    final now = AccountingConfig.currentDate;
    final currentMonthStr = DateFormat('MMMM yyyy').format(now);
    final months = _monthsList;
    _selectedMonth = months.contains(currentMonthStr)
        ? currentMonthStr
        : (months.isNotEmpty ? months.first : 'December 2026');
    final defaultFine = AccountingConfig.calculateProgressiveLateFine(_selectedMonth);
    _lateFineController.text = defaultFine > 0 ? defaultFine.toStringAsFixed(0) : '10';
  }

  @override
  void dispose() {
    _lateFineController.dispose();
    super.dispose();
  }

  Future<void> _sendMaintenanceNotificationBills() async {
    setState(() {
      _isProcessing = true;
      _resultMsg = null;
    });

    try {
      // 1. Fetch all registered residents
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();

      // 2. Fetch existing dues for selected month
      final existingDuesSnap = await FirebaseFirestore.instance
          .collection('maintenance_dues')
          .where('month', isEqualTo: _selectedMonth)
          .get();

      final existingFlats = <String, DocumentSnapshot>{};
      final displayPaidFlats = <String>{};
      final paidLookupKeys = <String>{};

      for (final doc in existingDuesSnap.docs) {
        final data = doc.data();
        final f = (data['flatNumber'] ?? '').toString().trim().toUpperCase();
        if (f.isNotEmpty) {
          existingFlats[f] = doc;
          final status = (data['status'] ?? '').toString().toUpperCase();
          if (status != 'UNPAID' &&
              (status.startsWith('PAID') ||
               status.contains('VERIFIED') ||
               status.contains('APPROVAL') ||
               status == 'PAYMENT_PENDING_APPROVAL')) {
            displayPaidFlats.add(f);
            paidLookupKeys.add(f);
            if (f.contains('-')) {
              paidLookupKeys.add(f.split('-').last);
              paidLookupKeys.add(f.replaceAll('-', ''));
            }
          }
        }
      }

      if (!mounted) return;
      setState(() => _isProcessing = false);

      // Determine whether to resend to paid flats
      bool resendToPaid = false;

      if (displayPaidFlats.isNotEmpty) {
        final choice = await AppDialog.show<String>(
          context: context,
          title: 'Payment Status: $_selectedMonth',
          subtitle: '${displayPaidFlats.length} flat(s) have recorded payments',
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.info,
          iconBgColor: AppColors.infoSurface,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${displayPaidFlats.length} flat(s) have already paid or submitted payment for $_selectedMonth:',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.slate700),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.successSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.successBorder),
                ),
                child: Text(
                  displayPaidFlats.join(', '),
                  style: const TextStyle(fontSize: 12, color: AppColors.successDark, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Would you like to skip sending billing notifications to these paid flats, or resend to all flats?',
                style: TextStyle(fontSize: 13, color: AppColors.slate600),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'CANCEL'),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.secondary),
              onPressed: () => Navigator.pop(context, 'RESEND_ALL'),
              child: const Text('Resend to All'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, 'SKIP_PAID'),
              child: const Text('Skip Paid (Notify Unpaid)'),
            ),
          ],
        );

        if (choice == null || choice == 'CANCEL') return;
        resendToPaid = (choice == 'RESEND_ALL');
      } else {
        if (!mounted) return;
        final confirm = await AppDialog.show<bool>(
          context: context,
          title: 'Send Maintenance Bills',
          subtitle: '$_selectedMonth • All Registered Flats',
          icon: Icons.campaign_rounded,
          iconColor: AppColors.primary,
          iconBgColor: AppColors.primarySurface,
          body: Text(
            'This will automatically calculate each flat\'s maintenance bill using their registered details (Block maintenance rate + registered 4-wheeler/2-wheeler parking charges as per the FY ${AccountingConfig.currentFinancialYear} budget) and send instant billing notifications to all residents.\n\n'
            'Existing bills for $_selectedMonth will be updated/skipped without double-billing. Proceed?',
            style: const TextStyle(fontSize: 13, color: AppColors.slate700, height: 1.4),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send Bills & Notify'),
            ),
          ],
        );

        if (confirm != true) return;
      }

      setState(() {
        _isProcessing = true;
        _resultMsg = null;
      });

      final double fineAmt = _isPastMonth ? (double.tryParse(_lateFineController.text.trim()) ?? 0.0) : 0.0;
      if (_isPastMonth && fineAmt <= 0) {
        setState(() => _isProcessing = false);
        if (mounted) {
          AppFeedback.showWarning(
            context,
            'Bills for past month ($_selectedMonth) must include a late fine so residents can settle them.',
            title: 'Late Fine Required',
          );
        }
        return;
      }

      int generatedCount = 0;
      int notifiedCount = 0;
      int skippedPaidCount = 0;
      final duesRef = FirebaseFirestore.instance.collection('maintenance_dues');
      final notificationsRef = FirebaseFirestore.instance.collection('notifications');

      // Chunked batch helper to prevent exceeding Firestore's 500-op batch limit
      var currentBatch = FirebaseFirestore.instance.batch();
      int opCount = 0;
      final batchesToCommit = <WriteBatch>[currentBatch];

      void addBatchOp(void Function(WriteBatch b) action) {
        if (opCount >= 400) {
          currentBatch = FirebaseFirestore.instance.batch();
          batchesToCommit.add(currentBatch);
          opCount = 0;
        }
        action(currentBatch);
        opCount++;
      }

      final processedFlats = <String>{};

      for (final userDoc in usersSnap.docs) {
        final uData = userDoc.data();
        final rawFlat = (uData['flatNumber'] ?? '').toString().trim().toUpperCase();
        if (rawFlat.isEmpty) continue;

        final blockStr = (uData['block'] ?? '').toString().trim().toUpperCase();
        final flatKey = (blockStr.isNotEmpty && !rawFlat.startsWith(blockStr))
            ? '$blockStr-$rawFlat'
            : rawFlat;

        if (processedFlats.contains(flatKey)) continue;
        processedFlats.add(flatKey);

        // Calculate bill strictly from user profile and budget rates
        final breakdown = AccountingConfig.calculateFromUserData(uData);

        // Check if bill already exists
        final existingDoc = existingFlats[flatKey];
        if (existingDoc == null) {
          final canonicalDocId = '${flatKey}_${_selectedMonth.replaceAll(' ', '_')}';
          final newDueDoc = duesRef.doc(canonicalDocId);
          final rName = (uData['name'] ?? uData['ownerName'] ?? '').toString().trim();
          final cReg = (uData['carReg'] ?? uData['carRegistration'] ?? uData['fourWheelerReg'] ?? '').toString().trim();
          final bReg = (uData['bikeReg'] ?? uData['bike1Registration'] ?? uData['bikeRegistration'] ?? uData['twoWheelerReg'] ?? '').toString().trim();
          final b2Reg = (uData['bike2Reg'] ?? uData['bike2Registration'] ?? '').toString().trim();
          final formattedVReg = ReceiptPreviewDialog.formatVehicleNumbers(
            carReg: cReg,
            bikeReg: bReg,
            bike2Reg: b2Reg,
            carCount: breakdown.carCount,
            bikeCount: breakdown.bikeCount,
            carParkingCharges: breakdown.carParkingCharges,
            bikeParkingCharges: breakdown.bikeParkingCharges,
          );

          addBatchOp((b) => b.set(newDueDoc, {
            'flatNumber': flatKey,
            'block': breakdown.block,
            if (rName.isNotEmpty) 'residentName': rName,
            if (cReg.isNotEmpty) 'carReg': cReg,
            if (bReg.isNotEmpty) 'bikeReg': bReg,
            if (b2Reg.isNotEmpty) 'bike2Reg': b2Reg,
            if (formattedVReg.isNotEmpty && formattedVReg != '—') 'vehicleReg': formattedVReg,
            'amount': breakdown.totalMonthlyDue + fineAmt,
            'baseMaintenance': breakdown.baseMaintenance,
            'pujaSubscription': breakdown.pujaSubscription,
            'carParkingCharges': breakdown.carParkingCharges,
            'bikeParkingCharges': breakdown.bikeParkingCharges,
            if (fineAmt > 0) 'fine': fineAmt,
            'carCount': breakdown.carCount,
            'bikeCount': breakdown.bikeCount,
            'month': _selectedMonth,
            'financialYear': AccountingConfig.currentFinancialYear,
            'status': 'UNPAID',
            'createdAt': FieldValue.serverTimestamp(),
          }));
          generatedCount++;
        }

        // Check if flat already paid and if we should skip
        final isFlatPaid = paidLookupKeys.contains(flatKey) || paidLookupKeys.contains(rawFlat);
        if (isFlatPaid && !resendToPaid) {
          skippedPaidCount++;
          continue;
        }

        // Resolve robust target UID and target identifiers
        final authUid = (uData['uid'] != null && uData['uid'].toString().isNotEmpty)
            ? uData['uid'].toString()
            : null;
        final targetUid = authUid ?? userDoc.id;
        final email = uData['email']?.toString();

        final targetUids = <String>{
          targetUid,
          userDoc.id,
          flatKey,
          rawFlat,
          ?authUid,
          ?email,
        }.where((s) => s.isNotEmpty).toList();

        // Send instant tailored notification to resident
        final carText = breakdown.carCount > 0 ? ' + Car (${breakdown.carCount}): ${AppFormatters.currency(breakdown.carParkingCharges)}' : '';
        final bikeText = breakdown.bikeCount > 0 ? ' + Bike (${breakdown.bikeCount}): ${AppFormatters.currency(breakdown.bikeParkingCharges)}' : '';
        final fineText = fineAmt > 0 ? ' + Late Fine: ${AppFormatters.currency(fineAmt)}' : '';
        final cateredMsg = isFlatPaid
            ? 'Dear Resident ($flatKey), your maintenance bill for $_selectedMonth (${AppFormatters.currency(breakdown.totalMonthlyDue + fineAmt)}) is recorded as paid/under verification.'
            : 'Dear Resident ($flatKey), your maintenance bill for $_selectedMonth is ${AppFormatters.currency(breakdown.totalMonthlyDue + fineAmt)} (Maintenance: ${AppFormatters.currency(breakdown.baseMaintenance)}$carText$bikeText$fineText). Tap to view breakdown and pay.';

        final newNotificationDoc = notificationsRef.doc();
        addBatchOp((b) => b.set(newNotificationDoc, {
          'targetUid': targetUid,
          'targetUids': targetUids,
          'targetRole': 'RESIDENT',
          'type': 'MAINTENANCE_DUE',
          'title': isFlatPaid ? 'Maintenance Status: $_selectedMonth' : 'Maintenance Bill Due: $_selectedMonth',
          'message': cateredMsg,
          'flatNumber': flatKey,
          'amount': breakdown.totalMonthlyDue + fineAmt,
          'baseMaintenance': breakdown.baseMaintenance,
          'pujaSubscription': breakdown.pujaSubscription,
          'carParkingCharges': breakdown.carParkingCharges,
          'bikeParkingCharges': breakdown.bikeParkingCharges,
          if (fineAmt > 0) 'fine': fineAmt,
          'carCount': breakdown.carCount,
          'bikeCount': breakdown.bikeCount,
          'month': _selectedMonth,
          'financialYear': AccountingConfig.currentFinancialYear,
          'createdAt': FieldValue.serverTimestamp(),
        }));
        notifiedCount++;
      }

      for (final b in batchesToCommit) {
        await b.commit();
      }

      final skippedText = skippedPaidCount > 0 ? ' ($skippedPaidCount paid flat(s) skipped)' : '';
      final msg = 'Issued $generatedCount new bill(s) and notified $notifiedCount flat(s) for $_selectedMonth$skippedText.';
      setState(() {
        _resultMsg = msg;
      });

      if (mounted) {
        AppFeedback.showSuccess(context, msg);
      }
    } catch (e) {
      setState(() => _resultMsg = 'Error sending maintenance bills: $e');
      if (mounted) {
        AppFeedback.showError(context, 'Error generating maintenance bills: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _verifyPayment(String dueId, Map<String, dynamic> data) async {
    setState(() => _processingDues.add(dueId));

    try {
      final voucherCode = await BillingService.verifyPayment(
        dueId: dueId,
        data: data,
        verifiedBy: 'Admin',
      );

      if (mounted) {
        final rawFlat = (data['flatNumber'] ?? 'Unknown').toString();
        final normFlat = FlatUtils.normalize(rawFlat);
        AppFeedback.showSuccess(
          context,
          'Payment for Flat $normFlat approved & posted to Accounts ($voucherCode)!',
          title: 'Payment Verified & Approved',
        );

        // Open official receipt voucher preview
        final isMulti = data['isMultiMonthPayment'] == true || data['multiMonthTotalAmount'] != null;
        final fullAmount = isMulti
            ? ((data['multiMonthTotalAmount'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble() ?? 0.0)
            : ((data['amount'] as num?)?.toDouble() ?? 0.0);
        final receiptData = Map<String, dynamic>.from(data);
        receiptData['amount'] = fullAmount;
        receiptData['multiMonthTotalAmount'] = fullAmount;
        receiptData['receiptNumber'] = voucherCode;
        receiptData['status'] = 'PAID_VERIFIED';
        ReceiptPreviewDialog.show(
          context: context,
          dueData: receiptData,
          receiptNumber: voucherCode,
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error approving payment: $e', title: 'Approval Failed');
      }
    } finally {
      if (mounted) setState(() => _processingDues.remove(dueId));
    }
  }

  Future<void> _showRejectDialog(String dueId, Map<String, dynamic> data) async {
    final reasonController = TextEditingController();
    final flat = (data['flatNumber'] ?? 'Unknown').toString();
    final month = (data['month'] ?? '').toString();
    final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? 'N/A').toString();
    final mode = (data['paymentMode'] ?? 'Payment').toString();

    String? confirmedReason;
    try {
      confirmedReason = await AppDialog.show<String>(
        context: context,
        title: 'Reject Payment Submission',
        subtitle: 'Flat $flat • $month ($mode)',
        icon: Icons.cancel_outlined,
        iconColor: AppColors.error,
        maxWidth: 480,
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.errorSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.errorBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Unique ID: $uniqueId\nRejecting will mark the bill as UNPAID and notify the resident with the reason.',
                        style: const TextStyle(fontSize: 11, color: AppColors.error, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Quick reasons:', style: TextStyle(fontSize: 11, color: AppColors.slate600, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Reference not in Bank Statement',
                  'Incorrect payment amount',
                  'Illegible payment proof / screenshot',
                  'Wrong bank account credited',
                ].map((preset) => InkWell(
                  onTap: () {
                    reasonController.text = preset;
                    setDialogState(() {});
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: reasonController.text == preset ? AppColors.primarySurface : AppColors.slate100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: reasonController.text == preset ? AppColors.primary : AppColors.slate300),
                    ),
                    child: Text(
                      preset,
                      style: TextStyle(
                        fontSize: 11,
                        color: reasonController.text == preset ? AppColors.primary : AppColors.slate700,
                        fontWeight: reasonController.text == preset ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Reason for Rejection *',
                  hintText: 'Explain why the payment could not be verified...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(context, reason);
            },
            child: const Text('Confirm Rejection'),
          ),
        ],
      );
    } finally {
      reasonController.dispose();
    }

    if (confirmedReason == null || confirmedReason.isEmpty) return;

    setState(() => _processingDues.add(dueId));
    try {
      await BillingService.rejectPayment(
        dueId: dueId,
        flatNumber: flat,
        month: month,
        paymentMode: mode,
        uniqueId: uniqueId,
        reason: confirmedReason,
      );

      if (mounted) {
        AppFeedback.showWarning(
          context,
          'Payment rejected. Resident ($flat) has been notified to meet the authorities in person to resolve conflicts.',
          title: 'Payment Rejected',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error rejecting payment: $e');
      }
    } finally {
      if (mounted) setState(() => _processingDues.remove(dueId));
    }
  }

  Future<void> _resetDueToUnpaid(String docId, String flat) async {
    final confirm = await AppDialog.show<bool>(
      context: context,
      title: 'Reset Bill for Flat $flat?',
      subtitle: 'Month: $_selectedMonth',
      icon: Icons.refresh_rounded,
      iconColor: AppColors.warning,
      iconBgColor: AppColors.warningSurface,
      body: const Text(
        'This will reset the status to UNPAID, remove all recorded payment details (UTR, receipts, verification timestamp), and remove any linked ledger entries. The resident will immediately be able to pay again. Proceed?',
        style: TextStyle(fontSize: 13, color: AppColors.slate700, height: 1.4),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reset to Unpaid'),
        ),
      ],
    );
    if (confirm != true) return;

    try {
      await BillingService.resetDueToUnpaid(
        dueId: docId,
        flatNumber: flat,
      );
      if (mounted) {
        AppFeedback.showSuccess(context, 'Flat $flat bill reset to UNPAID and accounts ledger synchronized.');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error resetting bill: $e');
      }
    }
  }

  Future<void> _recordCashPayment(String docId, String flat, double amount, String month) async {
    final notesController = TextEditingController(text: 'Received cash at Society Office');
    bool? confirm;
    String notes = '';
    try {
      confirm = await AppDialog.show<bool>(
        context: context,
        title: 'Record Cash: Flat $flat',
        subtitle: '$month • Amount: ${AppFormatters.currency(amount)}',
        icon: Icons.payments_rounded,
        iconColor: AppColors.success,
        iconBgColor: AppColors.successSurface,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Maintenance Amount:', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                  Text(AppFormatters.currency(amount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Cashier Notes / Handover Ref',
                hintText: 'e.g. Received cash at Society Office',
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm Cash & Issue Receipt'),
          ),
        ],
      );
      notes = notesController.text.trim();
    } finally {
      notesController.dispose();
    }

    if (confirm != true) return;

    try {
      final voucherCode = await BillingService.recordCashPayment(
        dueId: docId,
        flatNumber: flat,
        month: month,
        amount: amount,
        notes: notes.isNotEmpty ? notes : 'Received cash at Society Office',
        recordedBy: 'Admin',
      );

      if (mounted) {
        AppFeedback.showSuccess(context, 'Cash payment recorded for Flat $flat ($voucherCode)!');
        ReceiptPreviewDialog.show(
          context: context,
          dueData: {
            'flatNumber': flat,
            'amount': amount,
            'month': month,
            'receiptNumber': voucherCode,
            'paymentMode': 'Cash to Cashier',
            'paymentCategory': 'OFFLINE',
            'uniqueId': 'CASH-OFFICE',
            'status': 'PAID_OFFLINE_VERIFIED',
            'verifiedAt': Timestamp.now(),
          },
          receiptNumber: voucherCode,
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error recording cash payment: $e');
      }
    }
  }

  Future<void> _deleteDue(String docId, String flat) async {
    final confirm = await AppDialog.show<bool>(
      context: context,
      title: 'Delete Bill for Flat $flat?',
      subtitle: 'Month: $_selectedMonth',
      icon: Icons.delete_outline_rounded,
      iconColor: AppColors.error,
      iconBgColor: AppColors.errorSurface,
      body: const Text(
        'This will completely remove this month\'s maintenance bill for this flat from the system and clean up any linked transaction entries. Proceed?',
        style: TextStyle(fontSize: 13, color: AppColors.slate700),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Bill'),
        ),
      ],
    );
    if (confirm != true) return;

    try {
      // 1. Fetch any linked ledger entries
      final txSnap = await FirebaseFirestore.instance
          .collection('society_transactions')
          .where('linkedDueId', isEqualTo: docId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      batch.delete(FirebaseFirestore.instance.collection('maintenance_dues').doc(docId));
      for (final txDoc in txSnap.docs) {
        batch.delete(txDoc.reference);
      }
      await batch.commit();

      if (mounted) {
        AppFeedback.showSuccess(context, 'Flat $flat bill deleted.');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error deleting bill: $e');
      }
    }
  }

  Future<void> _showEditFineDialog(String dueId, Map<String, dynamic> data) async {
    final bool isParkingOnly = data['isParkingOnlyBill'] == true ||
        ((data['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0;
    if (isParkingOnly) {
      AppFeedback.showInfo(
        context,
        'Late fines cannot be assessed on parking-only dues. Late fines apply exclusively to flat maintenance.',
        title: 'Parking Dues Exempt',
      );
      return;
    }

    final currentFine = (data['fine'] as num?)?.toDouble() ?? (data['lateFee'] as num?)?.toDouble() ?? 0.0;
    final flat = (data['flatNumber'] ?? 'Unknown').toString();
    final month = (data['month'] ?? '').toString();
    final progressiveFine = AccountingConfig.calculateProgressiveLateFine(month);
    final overdueMonths = AccountingConfig.getOverdueMonths(month);
    final defaultFine = currentFine > 0 ? currentFine : (progressiveFine > 0 ? progressiveFine : 10.0);
    final fineCtrl = TextEditingController(text: defaultFine.toStringAsFixed(0));

    final baseMaint = (data['baseMaintenance'] as num?)?.toDouble() ?? 0.0;
    final carCharges = (data['carParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final bikeCharges = (data['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final puja = (data['pujaSubscription'] as num?)?.toDouble() ?? 0.0;
    final subTotal = baseMaint + puja + carCharges + bikeCharges;

    bool? confirm;
    String fineText = '';
    try {
      confirm = await AppDialog.show<bool>(
        context: context,
        title: 'Assess Late Fine',
        subtitle: 'Flat $flat • $month',
        icon: Icons.gavel_rounded,
        iconColor: AppColors.warning,
        iconBgColor: AppColors.warningSurface,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.slate200),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Base Maintenance + Parking:', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                      Text(AppFormatters.currency(subTotal), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.slate800)),
                    ],
                  ),
                  if (currentFine > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Current Assessed Fine:', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                        Text(AppFormatters.currency(currentFine), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.warningDark)),
                      ],
                    ),
                  ],
                  if (overdueMonths > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Overdue Duration:', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                        Text('$overdueMonths mo. (₹10/mo = ₹${(overdueMonths * 10).toStringAsFixed(0)})',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.warningDark)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fineCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Late Fine Amount (₹) *',
                hintText: 'e.g. 10',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Standard late fine is ₹10 per month of delay. You can adjust or override this amount if needed.',
              style: TextStyle(fontSize: 11, color: AppColors.slate500, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update Fine & Total'),
          ),
        ],
      );
      fineText = fineCtrl.text.trim();
    } finally {
      fineCtrl.dispose();
    }

    if (confirm != true) return;

    final newFine = double.tryParse(fineText) ?? 0.0;

    setState(() => _processingDues.add(dueId));
    try {
      final newTotal = subTotal + newFine;
      await FirebaseFirestore.instance.collection('maintenance_dues').doc(dueId).update({
        'fine': newFine,
        'amount': newTotal,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Also create a notification for resident
      await FirebaseFirestore.instance.collection('notifications').add({
        'targetRole': 'RESIDENT',
        'flatNumber': flat,
        'type': 'MAINTENANCE_DUE',
        'title': 'Late Fine Assessed: $month',
        'message': 'A late fine of ${AppFormatters.currency(newFine)} has been applied to your $month maintenance bill for Flat $flat. Total payable: ${AppFormatters.currency(newTotal)}. Tap to view and pay.',
        'month': month,
        'fine': newFine,
        'amount': newTotal,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        AppFeedback.showSuccess(
          context,
          'Late fine of ${AppFormatters.currency(newFine)} applied to Flat $flat ($month). Total: ${AppFormatters.currency(newTotal)}.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error updating late fine: $e');
      }
    } finally {
      if (mounted) setState(() => _processingDues.remove(dueId));
    }
  }

  Future<void> _issueParkingGapBill(Map<String, dynamic> gapInfo) async {
    final flat = (gapInfo['flat'] ?? '').toString();
    final missing = List<String>.from(gapInfo['missingMonths'] ?? []);
    final int carCount = (gapInfo['carCount'] as num?)?.toInt() ?? 0;
    final int bikeCount = (gapInfo['bikeCount'] as num?)?.toInt() ?? 0;
    final double carMonthly = carCount * (AccountingConfig.parkingRates['Four-Wheeler'] ?? 430).toDouble();
    final double bikeMonthly = bikeCount * (AccountingConfig.parkingRates['Two-Wheeler'] ?? 100).toDouble();
    final double monthlyParking = carMonthly + bikeMonthly;
    final double totalPayable = monthlyParking * missing.length;

    final confirm = await AppDialog.show<bool>(
      context: context,
      title: 'Issue Parking Gap Bill',
      subtitle: 'Flat $flat • ${missing.length} Month(s)',
      icon: Icons.directions_car_rounded,
      iconColor: AppColors.primary,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will generate an official parking dues bill for Flat $flat for the following unbilled/opted-out months:',
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate700),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Registered Vehicles:', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                    Text('$carCount Car(s), $bikeCount Bike(s)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Monthly Rate:', style: TextStyle(fontSize: 12, color: AppColors.slate600)),
                    Text(AppFormatters.currency(monthlyParking), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Payable (${missing.length} Mos):', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.slate800)),
                    Text(AppFormatters.currency(totalPayable), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Months: ${missing.join(', ')}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.slate600, fontStyle: FontStyle.italic),
          ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm & Issue Bill'),
        ),
      ],
    );

    if (confirm != true) return;

    setState(() => _isProcessing = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final m in missing) {
        final docId = '${flat}_${m.replaceAll(' ', '_')}_parking';
        final dRef = FirebaseFirestore.instance.collection('maintenance_dues').doc(docId);
        batch.set(dRef, {
          'flatNumber': flat,
          'block': FlatUtils.extractBlock(flat),
          'month': m,
          'residentName': gapInfo['residentName'],
          'amount': monthlyParking,
          'baseMaintenance': 0.0,
          'pujaSubscription': 0.0,
          'carParkingCharges': carMonthly,
          'bikeParkingCharges': bikeMonthly,
          'carCount': carCount,
          'bikeCount': bikeCount,
          'parkingIncluded': true,
          'isParkingOnlyBill': true,
          'status': 'UNPAID',
          'financialYear': AccountingConfig.currentFinancialYear,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await NotificationService.notifyResident(
        flatNumber: flat,
        title: 'Parking Dues Bill Issued: ${missing.join(', ')}',
        message: 'An official parking dues bill of ${AppFormatters.currency(totalPayable)} for ${missing.length} month(s) has been issued for Flat $flat. Tap to view and pay.',
        type: 'MAINTENANCE_DUE',
        extraData: {
          'flatNumber': flat,
          'amount': totalPayable,
          'months': missing,
        },
        batch: batch,
      );

      await batch.commit();

      if (mounted) {
        AppFeedback.showSuccess(context, 'Parking dues bill issued for Flat $flat (${missing.length} month(s)).');
      }
    } catch (e) {
      if (mounted) AppFeedback.showError(context, 'Error issuing parking bill: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Pending Approvals Section (Live Stream across all pending approval dues)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('maintenance_dues')
                .where('status', whereIn: ['PAYMENT_PENDING_APPROVAL', 'PAID_OFFLINE_PENDING'])
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const SizedBox.shrink();
              }

              final pendingDocs = snap.data!.docs.toList();
              // Sort by submittedAt descending
              pendingDocs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = (aData['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                final bTime = (bData['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                return bTime.compareTo(aTime);
              });

              // Group pending dues by transaction so multi-month payments only show 1 card
              final Map<String, QueryDocumentSnapshot> groupedPendingMap = {};
              for (final doc in pendingDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final uid = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? '').toString().trim();
                final parentId = (data['multiMonthParentDueId'] ?? '').toString().trim();
                final flat = (data['flatNumber'] ?? '').toString().trim();

                String groupKey;
                if (parentId.isNotEmpty) {
                  groupKey = 'PARENT_${flat}_$parentId';
                } else if (uid.isNotEmpty && uid != 'N/A' && uid != 'CASH-OFFICE') {
                  groupKey = 'UID_${flat}_$uid';
                } else {
                  groupKey = 'DOC_${doc.id}';
                }

                if (!groupedPendingMap.containsKey(groupKey)) {
                  groupedPendingMap[groupKey] = doc;
                } else {
                  // Prefer doc that has isMultiMonthPayment == true or has multiMonthTotalAmount as the primary representative
                  final existingData = groupedPendingMap[groupKey]!.data() as Map<String, dynamic>;
                  if ((data['isMultiMonthPayment'] == true || data['multiMonthTotalAmount'] != null) &&
                      existingData['isMultiMonthPayment'] != true && existingData['multiMonthTotalAmount'] == null) {
                    groupedPendingMap[groupKey] = doc;
                  }
                }
              }

              final displayPendingDocs = groupedPendingMap.values.toList();

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.warningSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warningBorder, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.verified_outlined, size: 20, color: AppColors.warningDark),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Pending Payment Verifications',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${displayPendingDocs.length}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                const Text(
                                  'Review Unique ID / UTR against bank statement and approve to credit accounts',
                                  style: TextStyle(fontSize: 11, color: AppColors.slate600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.warningBorder),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: displayPendingDocs.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.warningBorder),
                      itemBuilder: (context, index) {
                        final d = displayPendingDocs[index];
                        final data = d.data() as Map<String, dynamic>;
                        final dueId = d.id;
                        final flat = (data['flatNumber'] ?? 'Unknown').toString();
                        final month = (data['month'] ?? '').toString();
                        final isMultiMonth = data['isMultiMonthPayment'] == true || data['multiMonthTotalAmount'] != null;
                        final amount = isMultiMonth
                            ? ((data['multiMonthTotalAmount'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble() ?? 0.0)
                            : ((data['amount'] as num?)?.toDouble() ?? 0.0);
                        final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? 'N/A').toString();
                        final paymentMode = (data['paymentMode'] ?? 'Online Payment').toString();
                        final paymentCategory = (data['paymentCategory'] ?? (paymentMode.contains('Cheque') || paymentMode.contains('Cash') ? 'OFFLINE' : 'ONLINE')).toString();
                        final isProcessing = _processingDues.contains(dueId);

                        String submittedStr = 'Recently';
                        if (data['submittedAt'] is Timestamp) {
                          submittedStr = AppFormatters.dateTime((data['submittedAt'] as Timestamp).toDate());
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                       Text(
                                         'Flat $flat • ${(data['multiMonthSummary'] ?? month)}',
                                         style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900),
                                       ),
                                       const SizedBox(width: 8),
                                       AppBadge.category(paymentCategory, isOnline: paymentCategory == 'ONLINE'),
                                       if (data['isMultiMonthPayment'] == true) ...[
                                         const SizedBox(width: 6),
                                         Container(
                                           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                           decoration: BoxDecoration(
                                             color: AppColors.primarySurface,
                                             borderRadius: BorderRadius.circular(4),
                                             border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                                           ),
                                           child: const Text('MULTI-MONTH', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 9)),
                                         ),
                                       ],
                                     ],
                                   ),
                                   Text(
                                     AppFormatters.currency(amount),
                                     style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.primary),
                                   ),
                                 ],
                               ),
                               const SizedBox(height: 4),
                               Text(
                                 'Submitted: $submittedStr via $paymentMode',
                                 style: const TextStyle(fontSize: 11, color: AppColors.slate600),
                               ),
                               if (data['parkingExcludedMonths'] != null && (data['parkingExcludedMonths'] as List).isNotEmpty) ...[
                                 const SizedBox(height: 4),
                                 Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                   decoration: BoxDecoration(
                                     color: AppColors.warningSurface,
                                     borderRadius: BorderRadius.circular(4),
                                     border: Border.all(color: AppColors.warningBorder),
                                   ),
                                   child: Row(
                                     mainAxisSize: MainAxisSize.min,
                                     children: [
                                       const Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.warningDark),
                                       const SizedBox(width: 4),
                                       Text(
                                         'Parking Excluded for: ${(data['parkingExcludedMonths'] as List).join(', ')}',
                                         style: const TextStyle(fontSize: 10.5, color: AppColors.warningDark, fontWeight: FontWeight.w600),
                                       ),
                                     ],
                                   ),
                                 ),
                               ],
                               const SizedBox(height: 8),
                               // UTR Chip
                               Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                 decoration: BoxDecoration(
                                   color: Colors.white,
                                   borderRadius: BorderRadius.circular(6),
                                   border: Border.all(color: AppColors.slate300),
                                 ),
                                 child: Row(
                                   children: [
                                     const Icon(Icons.tag_rounded, color: AppColors.info, size: 16),
                                     const SizedBox(width: 6),
                                     Text(
                                       paymentCategory == 'ONLINE' ? 'UTR / Ref:' : 'Cheque / Ref:',
                                       style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppColors.slate700),
                                     ),
                                     const SizedBox(width: 6),
                                     Expanded(
                                       child: SelectableText(
                                         uniqueId,
                                         style: const TextStyle(
                                           fontWeight: FontWeight.bold,
                                           fontSize: 12,
                                           color: AppColors.info,
                                           letterSpacing: 0.5,
                                         ),
                                       ),
                                     ),
                                     InkWell(
                                       borderRadius: BorderRadius.circular(4),
                                       onTap: () {
                                         Clipboard.setData(ClipboardData(text: uniqueId));
                                         AppFeedback.showInfo(context, 'Copied Unique ID ($uniqueId)');
                                       },
                                       child: const Padding(
                                         padding: EdgeInsets.all(2.0),
                                         child: Icon(Icons.copy_rounded, size: 15, color: AppColors.info),
                                       ),
                                     ),
                                   ],
                                 ),
                               ),
                              const SizedBox(height: 10),
                              // Actions
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.error,
                                      side: const BorderSide(color: AppColors.errorBorder),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: const Size(0, 32),
                                    ),
                                    icon: const Icon(Icons.close_rounded, size: 14),
                                    label: const Text('Reject', style: TextStyle(fontSize: 11)),
                                    onPressed: isProcessing ? null : () => _showRejectDialog(dueId, data),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      minimumSize: const Size(0, 32),
                                    ),
                                    icon: isProcessing
                                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
                                        : const Icon(Icons.verified_rounded, size: 14),
                                    label: Text(
                                      isProcessing ? 'Posting...' : 'Approve & Post to Income',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: isProcessing ? null : () => _verifyPayment(dueId, data),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          // 2. Main Action Card: Month Selection & Send Notification Button
          Container(
            padding: const EdgeInsets.all(18),
            decoration: AppDecorations.card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppDecorations.iconContainer(
                      icon: Icons.campaign_rounded,
                      color: AppColors.primary,
                      surfaceColor: AppColors.primarySurface,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Generate Maintenance Bills',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.slate900),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Calculates budget-approved rates and sends notifications to residents',
                            style: TextStyle(fontSize: 12, color: AppColors.slate500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.slate200),
                const SizedBox(height: 16),

                // Month Selector
                DropdownButtonFormField<String>(
                  initialValue: _selectedMonth,
                  decoration: const InputDecoration(
                    labelText: 'Billing Month',
                    prefixIcon: Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 20),
                  ),
                  items: _monthsList.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedMonth = val;
                        final progressive = AccountingConfig.calculateProgressiveLateFine(val);
                        _lateFineController.text = progressive > 0 ? progressive.toStringAsFixed(0) : '10';
                      });
                    }
                  },
                ),
                if (_isPastMonth) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final overdueMonths = AccountingConfig.getOverdueMonths(_selectedMonth);
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warningSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.warningBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warningDark),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Past Billing Month ($_selectedMonth)${overdueMonths > 0 ? ' • $overdueMonths Month(s) Overdue' : ''}',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.warningDark),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Overdue bills incur a late fine (₹10/month of delay${overdueMonths > 0 ? ' • $overdueMonths mo. = ₹${(overdueMonths * 10).toStringAsFixed(0)}' : ''}). Set or confirm the penalty per flat below:',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.slate700),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _lateFineController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(
                                labelText: 'Late Fine / Penalty per flat (₹) *',
                                hintText: 'e.g. 10',
                                prefixText: '₹ ',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 14),

                // Send Notification Bill Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isProcessing ? null : _sendMaintenanceNotificationBills,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _isProcessing ? 'Generating & Sending...' : 'Send Maintenance Notification Bill',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),

                if (_resultMsg != null) ...[
                  const SizedBox(height: 12),
                  _resultMsg!.startsWith('Error')
                      ? AppBanner.error(message: _resultMsg!)
                      : AppBanner.success(message: _resultMsg!),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 3. Parking Coverage Gaps & Alerts (Flats with maintenance paid in advance but parking lapsed)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('maintenance_dues')
                .where('status', whereIn: ['PAID_VERIFIED', 'PAID_ONLINE', 'PAID_OFFLINE_VERIFIED'])
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();

              // Map of Flat -> Set of paid maintenance months and Set of paid parking months
              final Map<String, Set<String>> flatMaintMonths = {};
              final Map<String, Set<String>> flatParkingMonths = {};
              final Map<String, Map<String, dynamic>> flatDetails = {};

              for (final doc in snap.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                final flat = (d['flatNumber'] ?? '').toString().trim().toUpperCase();
                if (flat.isEmpty) continue;

                flatDetails.putIfAbsent(flat, () => d);

                flatMaintMonths.putIfAbsent(flat, () => <String>{});
                flatParkingMonths.putIfAbsent(flat, () => <String>{});

                final m = (d['month'] ?? '').toString().trim();
                if (m.isNotEmpty) flatMaintMonths[flat]!.add(m);

                final double carParking = ((d['carParkingCharges'] as num?)?.toDouble() ?? 0);
                final double bikeParking = ((d['bikeParkingCharges'] as num?)?.toDouble() ?? 0);
                final bool incParking = d['parkingIncluded'] != false && (carParking > 0 || bikeParking > 0);
                if (incParking && m.isNotEmpty) {
                  flatParkingMonths[flat]!.add(m);
                }

                // If multi-month explicit arrays present
                if (d['maintenancePaidMonths'] != null) {
                  flatMaintMonths[flat]!.addAll(List<String>.from(d['maintenancePaidMonths'] as List));
                }
                if (d['parkingPaidMonths'] != null) {
                  flatParkingMonths[flat]!.addAll(List<String>.from(d['parkingPaidMonths'] as List));
                }
              }

              final now = AccountingConfig.currentDate;
              final curMonthStr = DateFormat('MMMM yyyy').format(now);
              final curMonthIdx = AccountingConfig.getMonthIndex(curMonthStr);

              // Filter flats with gap: maintenance months paid where parking was excluded/unpaid, and flat has car
              // Only alert for months that have actually arrived (curMonthIdx or _selectedMonth)
              final gapFlats = <Map<String, dynamic>>[];

              flatMaintMonths.forEach((flat, maintSet) {
                final parkSet = flatParkingMonths[flat] ?? <String>{};
                final info = flatDetails[flat] ?? {};
                final int carCount = ((info['carCount'] as num?)?.toInt() ?? 0);
                final int bikeCount = ((info['bikeCount'] as num?)?.toInt() ?? 0);

                if (carCount > 0 || bikeCount > 0) {
                  final missingParking = maintSet.where((m) => !parkSet.contains(m)).toList();
                  // A month is due only if the calendar has reached it OR the admin has selected it for billing
                  final dueMissingParking = missingParking.where((m) {
                    final mIdx = AccountingConfig.getMonthIndex(m);
                    if (mIdx == -1) return false;
                    return mIdx <= curMonthIdx || m == _selectedMonth;
                  }).toList();

                  if (dueMissingParking.isNotEmpty) {
                    // Sort missing months by FY order
                    dueMissingParking.sort((a, b) => AccountingConfig.getMonthIndex(a).compareTo(AccountingConfig.getMonthIndex(b)));
                    gapFlats.add({
                      'flat': flat,
                      'residentName': info['residentName'] ?? 'Flat Occupant',
                      'carReg': info['carReg'] ?? '',
                      'bikeReg': info['bikeReg'] ?? '',
                      'carCount': carCount,
                      'bikeCount': bikeCount,
                      'maintMonths': maintSet.toList()..sort((a, b) => AccountingConfig.getMonthIndex(a).compareTo(AccountingConfig.getMonthIndex(b))),
                      'parkingMonths': parkSet.toList()..sort((a, b) => AccountingConfig.getMonthIndex(a).compareTo(AccountingConfig.getMonthIndex(b))),
                      'missingMonths': dueMissingParking,
                    });
                  }
                }
              });

              if (gapFlats.isEmpty) return const SizedBox.shrink();

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.errorSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.errorBorder, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.directions_car_filled_rounded, size: 20, color: AppColors.error),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Parking Coverage Gaps & Alerts',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.error,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${gapFlats.length}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                const Text(
                                  'Flats with active maintenance in advance but vehicle parking charges now due',
                                  style: TextStyle(fontSize: 11, color: AppColors.slate600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.errorBorder),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: gapFlats.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.errorBorder),
                      itemBuilder: (context, index) {
                        final g = gapFlats[index];
                        final flat = g['flat'];
                        final rName = g['residentName'];
                        final missing = List<String>.from(g['missingMonths']);
                        final maint = List<String>.from(g['maintMonths']);
                        final park = List<String>.from(g['parkingMonths']);
                        final carReg = (g['carReg'] ?? '').toString();

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Flat $flat ($rName)',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900),
                                      ),
                                      if (carReg.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Text('• $carReg', style: const TextStyle(fontSize: 11, color: AppColors.slate600, fontWeight: FontWeight.w500)),
                                      ],
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.error,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${missing.length} Mo. Parking Due',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Maintenance Paid Through: ${maint.isNotEmpty ? maint.last : 'N/A'} • Parking Paid Through: ${park.isNotEmpty ? park.last : 'None'}',
                                style: const TextStyle(fontSize: 11.5, color: AppColors.slate700, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  const Text('Due Parking Months: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.error)),
                                  ...missing.map((m) => Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.errorBorder),
                                    ),
                                    child: Text(m, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.error)),
                                  )),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.receipt_long_rounded, size: 14),
                                  label: Text(
                                    'Issue Parking Bill (${missing.length} Mo)',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(color: AppColors.errorBorder),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: const Size(0, 30),
                                  ),
                                  onPressed: () => _issueParkingGapBill(g),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          // 4. Billing Records & Status for Selected Month
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                'Billed Records ($_selectedMonth)',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.slate800),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.slate300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _filterStatus,
                    isDense: true,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate700),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'PENDING_APPROVAL', child: Text('Pending Approval')),
                      DropdownMenuItem(value: 'UNPAID', child: Text('Unpaid')),
                      DropdownMenuItem(value: 'PAID_ONLINE', child: Text('Paid Online')),
                      DropdownMenuItem(value: 'PAID_OFFLINE_PENDING', child: Text('Offline Pending')),
                      DropdownMenuItem(value: 'PAID_OFFLINE_VERIFIED', child: Text('Offline Verified')),
                      DropdownMenuItem(value: 'PAID_VERIFIED', child: Text('Verified')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _filterStatus = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by Flat (e.g. B-201)...',
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppColors.slate400),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim().toUpperCase()),
          ),
          const SizedBox(height: 14),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('maintenance_dues')
                .where('month', isEqualTo: _selectedMonth)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                ));
              }

              var docs = snapshot.data?.docs ?? [];

              if (_filterStatus != 'ALL') {
                if (_filterStatus == 'PENDING_APPROVAL') {
                  docs = docs.where((d) {
                    final st = (d.data() as Map<String, dynamic>)['status'] ?? '';
                    return st == 'PAYMENT_PENDING_APPROVAL' || st == 'PAID_OFFLINE_PENDING';
                  }).toList();
                } else {
                  docs = docs.where((d) => (d.data() as Map<String, dynamic>)['status'] == _filterStatus).toList();
                }
              }

              if (_searchQuery.isNotEmpty) {
                docs = docs.where((d) {
                  final f = ((d.data() as Map<String, dynamic>)['flatNumber'] ?? '').toString().toUpperCase();
                  return f.contains(_searchQuery);
                }).toList();
              }

              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: const Center(
                    child: Text(
                      'No maintenance bills found for this filter.\nTap "Send Maintenance Notification Bill" above to generate.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.slate500, fontSize: 13, height: 1.4),
                    ),
                  ),
                );
              }

              double totalBilled = 0;
              double totalCollected = 0;
              for (final d in docs) {
                final data = d.data() as Map<String, dynamic>;
                final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
                totalBilled += amt;
                final st = data['status'] ?? 'UNPAID';
                if (st == 'PAID_ONLINE' || st == 'PAID_OFFLINE_VERIFIED' || st == 'PAID_VERIFIED') {
                  totalCollected += amt;
                }
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Billed: ${_currencyFmt.format(totalBilled)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.slate800)),
                        Text('Collected: ${_currencyFmt.format(totalCollected)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.successDark)),
                        Text('Pending: ${_currencyFmt.format(totalBilled - totalCollected)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.errorDark)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final docId = doc.id;
                      final data = doc.data() as Map<String, dynamic>;
                      final flat = data['flatNumber'] ?? 'Unknown';
                      final amount = data['amount'] ?? 0;
                      final status = data['status'] ?? 'UNPAID';
                      final fineAmt = AccountingConfig.getEffectiveFine(data);
                      final dueMonth = (data['month'] ?? _selectedMonth).toString();
                      final isDuePast = AccountingConfig.isMonthPast(dueMonth);
                      final isPending = status == 'PAYMENT_PENDING_APPROVAL' || status == 'PAID_OFFLINE_PENDING';
                      final isProcessing = _processingDues.contains(docId);
                      final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? '').toString();

                      Widget badge;
                      if (isPending) {
                        badge = AppBadge.warning('VERIFICATION PENDING');
                      } else if (status == 'PAID_ONLINE') {
                        badge = AppBadge.success('PAID (ONLINE)');
                      } else if (status == 'PAID_OFFLINE_VERIFIED' || status == 'PAID_VERIFIED') {
                        badge = AppBadge.success('PAID (VERIFIED)');
                      } else if (isDuePast) {
                        final bool isParking = data['isParkingOnlyBill'] == true ||
                            ((data['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0;
                        badge = isParking
                            ? AppBadge.warning('PARKING DUE (OVERDUE)')
                            : (fineAmt > 0
                                ? AppBadge.warning('PAST DUE • FINE: ${_currencyFmt.format(fineAmt)}')
                                : AppBadge.error('PAST DUE • NO FINE'));
                      } else {
                        badge = AppBadge.error('UNPAID');
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: isPending
                            ? BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.warningBorder, width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.warning.withValues(alpha: 0.06),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              )
                            : AppDecorations.card(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isPending ? AppColors.warningSurface : AppColors.slate100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isPending ? Icons.pending_actions_rounded : Icons.home_rounded,
                                    size: 20,
                                    color: isPending ? AppColors.warningDark : AppColors.slate700,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Flat $flat', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900)),
                                      const SizedBox(height: 2),
                                      Text('Amount: ${_currencyFmt.format(amount)}', style: const TextStyle(fontSize: 12, color: AppColors.slate600)),
                                    ],
                                  ),
                                ),
                                badge,
                                if (status == 'PAID_ONLINE' || status == 'PAID_OFFLINE_VERIFIED' || status == 'PAID_VERIFIED') ...[
                                  const SizedBox(width: 6),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.receipt_long_rounded, size: 14),
                                    label: const Text('Receipt', style: TextStyle(fontSize: 11)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 28),
                                      side: const BorderSide(color: AppColors.primary, width: 0.8),
                                    ),
                                    onPressed: () => ReceiptPreviewDialog.show(context: context, dueData: data),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.slate500),
                                  tooltip: 'Bill Actions',
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  onSelected: (action) {
                                    if (action == 'EDIT_FINE') {
                                      _showEditFineDialog(docId, data);
                                    } else if (action == 'APPROVE') {
                                      _verifyPayment(docId, data);
                                    } else if (action == 'REJECT') {
                                      _showRejectDialog(docId, data);
                                    } else if (action == 'VIEW_RECEIPT') {
                                      ReceiptPreviewDialog.show(context: context, dueData: data);
                                    } else if (action == 'RECORD_CASH') {
                                      _recordCashPayment(docId, flat, (amount as num).toDouble(), _selectedMonth);
                                    } else if (action == 'RESET') {
                                      _resetDueToUnpaid(docId, flat);
                                    } else if (action == 'DELETE') {
                                      _deleteDue(docId, flat);
                                    }
                                  },
                                  itemBuilder: (ctx) => [
                                    if (isPending) ...[
                                      const PopupMenuItem(
                                        value: 'APPROVE',
                                        child: Row(
                                          children: [
                                            Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                                            SizedBox(width: 8),
                                            Text('Approve & Post to Income', style: TextStyle(color: AppColors.successDark, fontWeight: FontWeight.bold, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'REJECT',
                                        child: Row(
                                          children: [
                                            Icon(Icons.close_rounded, color: AppColors.error, size: 18),
                                            SizedBox(width: 8),
                                            Text('Reject Submission', style: TextStyle(color: AppColors.error, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (status == 'PAID_ONLINE' || status == 'PAID_OFFLINE_VERIFIED' || status == 'PAID_VERIFIED')
                                      const PopupMenuItem(
                                        value: 'VIEW_RECEIPT',
                                        child: Row(
                                          children: [
                                            Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 18),
                                            SizedBox(width: 8),
                                            Text('View Official Receipt', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    if (status == 'UNPAID') ...[
                                      if (data['isParkingOnlyBill'] != true && ((data['baseMaintenance'] as num?)?.toDouble() ?? 0.0) > 0)
                                        PopupMenuItem(
                                          value: 'EDIT_FINE',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.gavel_rounded, color: AppColors.warningDark, size: 18),
                                              const SizedBox(width: 8),
                                              Text(
                                                fineAmt > 0 ? 'Edit Late Fine' : 'Assess Late Fine',
                                                style: const TextStyle(color: AppColors.warningDark, fontWeight: FontWeight.w600, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        ),
                                      const PopupMenuItem(
                                        value: 'RECORD_CASH',
                                        child: Row(
                                          children: [
                                            Icon(Icons.payments_rounded, color: AppColors.success, size: 18),
                                            SizedBox(width: 8),
                                            Text('Record Cash Payment', style: TextStyle(color: AppColors.successDark, fontWeight: FontWeight.w600, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (status != 'UNPAID')
                                      const PopupMenuItem(
                                        value: 'RESET',
                                        child: Row(
                                          children: [
                                            Icon(Icons.refresh_rounded, color: AppColors.warning, size: 18),
                                            SizedBox(width: 8),
                                            Text('Reset to Unpaid', style: TextStyle(color: AppColors.warningDark, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    const PopupMenuItem(
                                      value: 'DELETE',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                                          SizedBox(width: 8),
                                          Text('Delete Bill', style: TextStyle(color: AppColors.error, fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // If pending, render quick actions bar
                            if (isPending) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.slate50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.slate200),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.tag_rounded, size: 14, color: AppColors.info),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Ref / UTR: ${uniqueId.isNotEmpty ? uniqueId : "N/A"}',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate700),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (uniqueId.isNotEmpty)
                                      InkWell(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: uniqueId));
                                          AppFeedback.showInfo(context, 'Copied Ref ($uniqueId)');
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(2.0),
                                          child: Icon(Icons.copy_rounded, size: 13, color: AppColors.info),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.error,
                                        side: const BorderSide(color: AppColors.errorBorder),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        minimumSize: const Size(0, 26),
                                      ),
                                      onPressed: isProcessing ? null : () => _showRejectDialog(docId, data),
                                      child: const Text('Reject', style: TextStyle(fontSize: 10)),
                                    ),
                                    const SizedBox(width: 6),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        minimumSize: const Size(0, 26),
                                      ),
                                      onPressed: isProcessing ? null : () => _verifyPayment(docId, data),
                                      child: isProcessing
                                          ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
                                          : const Text('Approve', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
