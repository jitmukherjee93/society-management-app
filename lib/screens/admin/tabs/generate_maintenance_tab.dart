import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/accounting_heads.dart';
import '../../../utils/app_formatters.dart';
import '../../../utils/flat_utils.dart';
import '../../../services/billing_service.dart';
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

  final List<String> _monthsList = [
    'April 2026',
    'May 2026',
    'June 2026',
    'July 2026',
    'August 2026',
    'September 2026',
    'October 2026',
    'November 2026',
    'December 2026',
    'January 2027',
    'February 2027',
    'March 2027',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final currentMonthStr = DateFormat('MMMM yyyy').format(now);
    _selectedMonth = _monthsList.contains(currentMonthStr) ? currentMonthStr : 'September 2026';
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
          final newDueDoc = duesRef.doc();
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
            'amount': breakdown.totalMonthlyDue,
            'baseMaintenance': breakdown.baseMaintenance,
            'pujaSubscription': breakdown.pujaSubscription,
            'carParkingCharges': breakdown.carParkingCharges,
            'bikeParkingCharges': breakdown.bikeParkingCharges,
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
        final cateredMsg = isFlatPaid
            ? 'Dear Resident ($flatKey), your maintenance bill for $_selectedMonth (${AppFormatters.currency(breakdown.totalMonthlyDue)}) is recorded as paid/under verification.'
            : 'Dear Resident ($flatKey), your maintenance bill for $_selectedMonth is ${AppFormatters.currency(breakdown.totalMonthlyDue)} (Maintenance: ${AppFormatters.currency(breakdown.baseMaintenance)}$carText$bikeText). Tap to view breakdown and pay.';

        final newNotificationDoc = notificationsRef.doc();
        addBatchOp((b) => b.set(newNotificationDoc, {
          'targetUid': targetUid,
          'targetUids': targetUids,
          'targetRole': 'RESIDENT',
          'type': 'MAINTENANCE_DUE',
          'title': isFlatPaid ? 'Maintenance Status: $_selectedMonth' : 'Maintenance Bill Due: $_selectedMonth',
          'message': cateredMsg,
          'flatNumber': flatKey,
          'amount': breakdown.totalMonthlyDue,
          'baseMaintenance': breakdown.baseMaintenance,
          'pujaSubscription': breakdown.pujaSubscription,
          'carParkingCharges': breakdown.carParkingCharges,
          'bikeParkingCharges': breakdown.bikeParkingCharges,
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
        final receiptData = Map<String, dynamic>.from(data);
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

  void _showRejectDialog(String dueId, Map<String, dynamic> data) {
    final reasonController = TextEditingController(text: 'Unique ID / Reference not reflected in Society Bank Statement');
    final flat = (data['flatNumber'] ?? 'Unknown').toString();
    final month = (data['month'] ?? '').toString();
    final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? 'N/A').toString();
    final mode = (data['paymentMode'] ?? 'Payment').toString();

    AppDialog.show(
      context: context,
      title: 'Reject Payment Submission',
      subtitle: 'Flat $flat • $month ($mode)',
      icon: Icons.cancel_outlined,
      iconColor: AppColors.error,
      maxWidth: 480,
      content: Column(
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
                    'Unique ID: $uniqueId\nResetting will mark the bill as UNPAID and notify the resident to re-submit.',
                    style: const TextStyle(fontSize: 11, color: AppColors.error, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason for Rejection *',
              hintText: 'Explain why the payment could not be verified...',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            reasonController.dispose();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            final reason = reasonController.text.trim();
            if (reason.isEmpty) return;
            reasonController.dispose();
            Navigator.pop(context);

            setState(() => _processingDues.add(dueId));
            try {
              await BillingService.rejectPayment(
                dueId: dueId,
                flatNumber: flat,
                month: month,
                paymentMode: mode,
                uniqueId: uniqueId,
                reason: reason,
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
          },
          child: const Text('Confirm Rejection'),
        ),
      ],
    );
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
    final confirm = await AppDialog.show<bool>(
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
          onPressed: () {
            notesController.dispose();
            Navigator.pop(context, false);
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm Cash & Issue Receipt'),
        ),
      ],
    );

    if (confirm != true) {
      notesController.dispose();
      return;
    }

    final notes = notesController.text.trim();
    notesController.dispose();

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
                                        '${pendingDocs.length}',
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
                      itemCount: pendingDocs.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: AppColors.warningBorder),
                      itemBuilder: (context, index) {
                        final d = pendingDocs[index];
                        final data = d.data() as Map<String, dynamic>;
                        final dueId = d.id;
                        final flat = (data['flatNumber'] ?? 'Unknown').toString();
                        final month = (data['month'] ?? '').toString();
                        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
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
                    if (val != null) setState(() => _selectedMonth = val);
                  },
                ),
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

                final bool incParking = d['parkingIncluded'] != false && ((d['carParkingCharges'] as num?)?.toDouble() ?? 0) > 0;
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

              // Filter flats with gap: maintenance months paid where parking was excluded/unpaid, and flat has car
              final gapFlats = <Map<String, dynamic>>[];

              flatMaintMonths.forEach((flat, maintSet) {
                final parkSet = flatParkingMonths[flat] ?? <String>{};
                final info = flatDetails[flat] ?? {};
                final int carCount = ((info['carCount'] as num?)?.toInt() ?? 0);
                final int bikeCount = ((info['bikeCount'] as num?)?.toInt() ?? 0);

                if (carCount > 0 || bikeCount > 0) {
                  final missingParking = maintSet.where((m) => !parkSet.contains(m)).toList();
                  if (missingParking.isNotEmpty) {
                    // Sort missing months by FY order
                    missingParking.sort((a, b) => AccountingConfig.getMonthIndex(a).compareTo(AccountingConfig.getMonthIndex(b)));
                    gapFlats.add({
                      'flat': flat,
                      'residentName': info['residentName'] ?? 'Flat Occupant',
                      'carReg': info['carReg'] ?? '',
                      'bikeReg': info['bikeReg'] ?? '',
                      'carCount': carCount,
                      'bikeCount': bikeCount,
                      'maintMonths': maintSet.toList()..sort((a, b) => AccountingConfig.getMonthIndex(a).compareTo(AccountingConfig.getMonthIndex(b))),
                      'parkingMonths': parkSet.toList()..sort((a, b) => AccountingConfig.getMonthIndex(a).compareTo(AccountingConfig.getMonthIndex(b))),
                      'missingMonths': missingParking,
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
                                  'Flats with active maintenance in advance but lapsed / opted-out vehicle parking charges',
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
                                      '${missing.length} Mo. Parking Unpaid',
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
                                  const Text('Unpaid Parking Months: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.error)),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                    if (action == 'APPROVE') {
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
                                    if (status == 'UNPAID')
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
