import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/accounting_heads.dart';
import '../../../utils/app_formatters.dart';
import '../../../utils/flat_utils.dart';
import '../../../services/notification_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_decorations.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_feedback.dart';

class GenerateMaintenanceTab extends StatefulWidget {
  const GenerateMaintenanceTab({super.key});

  @override
  State<GenerateMaintenanceTab> createState() => _GenerateMaintenanceTabState();
}

class _GenerateMaintenanceTabState extends State<GenerateMaintenanceTab> {
  final _currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  String _selectedMonth = '';
  bool _isProcessing = false;
  String? _resultMsg;

  // Records filter state
  String _filterStatus = 'ALL';
  String _searchQuery = '';

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

      setState(() => _isProcessing = false);

      // Determine whether to resend to paid flats
      bool resendToPaid = false;

      if (!mounted) return;
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
            'This will automatically calculate each flat\'s maintenance bill using their registered details (Block base rate + Puja subscription + registered 4-wheeler/2-wheeler parking charges as per the FY ${AccountingConfig.currentFinancialYear} budget) and send instant billing notifications to all residents.\n\n'
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
      final batch = FirebaseFirestore.instance.batch();
      final duesRef = FirebaseFirestore.instance.collection('maintenance_dues');
      final notificationsRef = FirebaseFirestore.instance.collection('notifications');

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
          batch.set(newDueDoc, {
            'flatNumber': flatKey,
            'block': breakdown.block,
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
          });
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
            : 'Dear Resident ($flatKey), your maintenance bill for $_selectedMonth is ${AppFormatters.currency(breakdown.totalMonthlyDue)} (Maintenance: ${AppFormatters.currency(breakdown.baseMaintenance)} + Puja: ${AppFormatters.currency(breakdown.pujaSubscription)}$carText$bikeText). Tap to view breakdown and pay.';

        final newNotificationDoc = notificationsRef.doc();
        batch.set(newNotificationDoc, {
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
        });
        notifiedCount++;
      }

      await batch.commit();

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

  Future<void> _resetDueToUnpaid(String docId, String flat) async {
    final confirm = await AppDialog.show<bool>(
      context: context,
      title: 'Reset Bill for Flat $flat?',
      subtitle: 'Month: $_selectedMonth',
      icon: Icons.refresh_rounded,
      iconColor: AppColors.warning,
      iconBgColor: AppColors.warningSurface,
      body: const Text(
        'This will reset the status to UNPAID and remove all recorded payment details (UTR, receipts, verification timestamp). The resident will immediately be able to pay again. Proceed?',
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
      await FirebaseFirestore.instance.collection('maintenance_dues').doc(docId).update({
        'status': 'UNPAID',
        'paidAt': FieldValue.delete(),
        'verifiedAt': FieldValue.delete(),
        'verifiedBy': FieldValue.delete(),
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
      });
      if (mounted) {
        AppFeedback.showSuccess(context, 'Flat $flat bill reset to UNPAID successfully.');
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
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm Cash & Issue Receipt'),
        ),
      ],
    );
    if (confirm != true) return;

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final voucherCode = 'INC-2627-${(timestamp % 100000).toString().padLeft(5, '0')}';
      final normFlat = FlatUtils.normalize(flat);
      final head = FlatUtils.getMaintenanceHead(normFlat);

      // Atomic Batch write: due update + society income transaction + notification
      final batch = FirebaseFirestore.instance.batch();

      // 1. Update maintenance due
      final dueRef = FirebaseFirestore.instance.collection('maintenance_dues').doc(docId);
      batch.update(dueRef, {
        'status': 'PAID_OFFLINE_VERIFIED',
        'receiptNumber': voucherCode,
        'paidAt': FieldValue.serverTimestamp(),
        'verifiedAt': FieldValue.serverTimestamp(),
        'verifiedBy': 'Admin',
        'paymentCategory': 'OFFLINE',
        'paymentMode': 'Cash to Cashier',
        'uniqueId': 'CASH-OFFICE',
        'referenceNumber': 'CASH-OFFICE',
        'cashierNotes': notesController.text.trim(),
      });

      // 2. Post Income transaction into accounts ledger
      final txRef = FirebaseFirestore.instance.collection('society_transactions').doc();
      batch.set(txRef, {
        'type': 'INCOME',
        'voucherNumber': voucherCode,
        'accountHead': head,
        'category': 'Maintenance Collection',
        'amount': amount,
        'paidToOrReceivedFrom': 'Flat $normFlat',
        'paymentDate': FieldValue.serverTimestamp(),
        'paymentMode': 'Cash',
        'referenceNumber': 'CASH-OFFICE',
        'description': 'Cash maintenance collection for $month from Flat $normFlat',
        'linkedDueId': docId,
        'uniqueId': 'CASH-OFFICE',
        'paymentCategory': 'OFFLINE',
        'recordedBy': 'Admin',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3. Dispatch receipt notification to resident
      await NotificationService.notifyResident(
        flatNumber: normFlat,
        title: 'Cash Payment Receipt ($voucherCode)',
        message: 'Your cash maintenance payment of ${AppFormatters.currency(amount)} for $month has been recorded and verified. Receipt Voucher: $voucherCode.',
        type: 'MAINTENANCE_PAYMENT_APPROVED',
        extraData: {
          'dueId': docId,
          'amount': amount,
          'month': month,
          'receiptNumber': voucherCode,
          'uniqueId': 'CASH-OFFICE',
          'paymentCategory': 'OFFLINE',
          'paymentMode': 'Cash to Cashier',
        },
        batch: batch,
      );

      // Commit all writes atomically
      await batch.commit();

      if (mounted) {
        AppFeedback.showSuccess(context, 'Cash payment recorded for Flat $flat ($voucherCode)!');
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
        'This will completely remove this month\'s maintenance bill for this flat from the system. Proceed?',
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
      await FirebaseFirestore.instance.collection('maintenance_dues').doc(docId).delete();
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
          // Main Action Card: Month Selection & Send Notification Button
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

          // Billing Records & Status for Selected Month
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
                      DropdownMenuItem(value: 'UNPAID', child: Text('Unpaid')),
                      DropdownMenuItem(value: 'PAID_ONLINE', child: Text('Paid Online')),
                      DropdownMenuItem(value: 'PAID_OFFLINE_PENDING', child: Text('Offline Pending')),
                      DropdownMenuItem(value: 'PAID_OFFLINE_VERIFIED', child: Text('Offline Verified')),
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
                docs = docs.where((d) => (d.data() as Map<String, dynamic>)['status'] == _filterStatus).toList();
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
                      final data = docs[index].data() as Map<String, dynamic>;
                      final flat = data['flatNumber'] ?? 'Unknown';
                      final amount = data['amount'] ?? 0;
                      final status = data['status'] ?? 'UNPAID';

                      Widget badge;
                      if (status == 'PAYMENT_PENDING_APPROVAL' || status == 'PAID_OFFLINE_PENDING') {
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
                        decoration: AppDecorations.card(),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.slate100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.home_rounded, size: 20, color: AppColors.slate700),
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
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.slate500),
                              tooltip: 'Bill Actions',
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              onSelected: (action) {
                                final docId = docs[index].id;
                                if (action == 'RECORD_CASH') {
                                  _recordCashPayment(docId, flat, (amount as num).toDouble(), _selectedMonth);
                                } else if (action == 'RESET') {
                                  _resetDueToUnpaid(docId, flat);
                                } else if (action == 'DELETE') {
                                  _deleteDue(docId, flat);
                                }
                              },
                              itemBuilder: (ctx) => [
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
