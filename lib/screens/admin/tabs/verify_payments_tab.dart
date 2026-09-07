import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/app_formatters.dart';
import '../../../utils/flat_utils.dart';
import '../../../services/notification_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_decorations.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_feedback.dart';

class VerifyPaymentsTab extends StatefulWidget {
  const VerifyPaymentsTab({super.key});

  @override
  State<VerifyPaymentsTab> createState() => _VerifyPaymentsTabState();
}

class _VerifyPaymentsTabState extends State<VerifyPaymentsTab> {
  final Set<String> _processingDues = {};

  Future<void> _verifyPayment(String dueId, Map<String, dynamic> data) async {
    setState(() => _processingDues.add(dueId));

    try {
      final rawFlat = (data['flatNumber'] ?? 'Unknown').toString();
      final normFlat = FlatUtils.normalize(rawFlat);
      final month = (data['month'] ?? 'Current Month').toString();
      final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? 'N/A').toString().trim();
      final paymentCategory = (data['paymentCategory'] ?? 'ONLINE').toString();
      final paymentMode = (data['paymentMode'] ?? 'Online Payment').toString();

      // Determine budget block head via FlatUtils
      final head = FlatUtils.getMaintenanceHead(normFlat);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final voucherCode = 'INC-2627-${(timestamp % 100000).toString().padLeft(5, '0')}';

      // Atomic Batch write: update due + post transaction + dispatch notification
      final batch = FirebaseFirestore.instance.batch();

      // 1. Update maintenance due document
      final dueRef = FirebaseFirestore.instance.collection('maintenance_dues').doc(dueId);
      batch.update(dueRef, {
        'status': 'PAID_VERIFIED',
        'receiptNumber': voucherCode,
        'approvedAt': FieldValue.serverTimestamp(),
        'verifiedAt': FieldValue.serverTimestamp(),
        'verifiedBy': 'Admin',
        'paymentCategory': paymentCategory,
        'paymentMode': paymentMode,
        'uniqueId': uniqueId,
        'utrNumber': uniqueId,
        'referenceNumber': uniqueId,
      });

      // 2. Post income entry into society accounts ledger
      final txnRef = FirebaseFirestore.instance.collection('society_transactions').doc();
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
        'description': 'Maintenance collection for $month from Flat $normFlat (Unique ID: $uniqueId)',
        'linkedDueId': dueId,
        'uniqueId': uniqueId,
        'utrNumber': uniqueId,
        'paymentCategory': paymentCategory,
        'recordedBy': 'Admin',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 3. Dispatch notification in the same atomic batch
      await NotificationService.notifyResident(
        flatNumber: normFlat,
        title: 'Maintenance Payment Approved ($voucherCode)',
        message: 'Your maintenance payment of ${AppFormatters.currency(amount)} for $month (Unique ID: $uniqueId) has been verified and posted to Society Accounts. Receipt: $voucherCode.',
        type: 'MAINTENANCE_PAYMENT_APPROVED',
        extraData: {
          'dueId': dueId,
          'amount': amount,
          'month': month,
          'receiptNumber': voucherCode,
          'uniqueId': uniqueId,
          'paymentCategory': paymentCategory,
          'paymentMode': paymentMode,
        },
        batch: batch,
      );

      // Commit all 3 writes atomically!
      await batch.commit();

      if (mounted) {
        AppFeedback.showSuccess(
          context,
          'Payment for Flat $normFlat approved & posted to Accounts ($voucherCode)!',
          title: 'Payment Verified & Approved',
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

  void _showRejectDialog(BuildContext context, String dueId, Map<String, dynamic> data) {
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
          onPressed: () => Navigator.pop(context),
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
            Navigator.pop(context);

            setState(() => _processingDues.add(dueId));
            try {
              // Reset status back to UNPAID
              await FirebaseFirestore.instance.collection('maintenance_dues').doc(dueId).update({
                'status': 'UNPAID',
                'rejectionReason': reason,
                'rejectedAt': FieldValue.serverTimestamp(),
              });

              // Notify resident via NotificationService
              await NotificationService.notifyResident(
                flatNumber: flat,
                title: 'Payment Submission Rejected ($month)',
                message: 'Your payment submission for $month ($mode, Unique ID: $uniqueId) was rejected by Admin. Reason: $reason. Please re-submit with valid reference.',
                type: 'MAINTENANCE_PAYMENT_REJECTED',
                extraData: {
                  'dueId': dueId,
                  'uniqueId': uniqueId,
                  'rejectionReason': reason,
                },
              );

              if (context.mounted) {
                AppFeedback.showWarning(
                  context,
                  'Payment rejected. Resident ($flat) has been notified to re-submit.',
                  title: 'Payment Rejected',
                );
              }
            } catch (e) {
              if (context.mounted) {
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance_dues')
          .where('status', whereIn: ['PAYMENT_PENDING_APPROVAL', 'PAID_OFFLINE_PENDING'])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading pending payments: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
          );
        }

        final docs = (snapshot.data?.docs ?? []).toList();

        // Sort by submittedAt descending
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = (aData['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = (bData['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.verified_outlined, size: 64, color: Colors.green.shade700),
                ),
                const SizedBox(height: 16),
                const Text(
                  'All Maintenance Payments Verified!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'No pending payment approval requests at this time.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Payment Approvals (${docs.length})',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Verify Unique IDs against Society Bank Statement / Cheque receipts and approve entries into accounts.',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final dueId = docs[index].id;
                    final flat = data['flatNumber'] ?? 'Unknown';
                    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                    final month = data['month'] ?? '';
                    final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? 'N/A').toString();
                    final paymentMode = data['paymentMode'] ?? 'Online Payment';
                    final paymentCategory = data['paymentCategory'] ?? (paymentMode.toString().contains('Cheque') || paymentMode.toString().contains('Cash') ? 'OFFLINE' : 'ONLINE');
                    final isProcessing = _processingDues.contains(dueId);

                    final baseMaint = (data['baseMaintenance'] as num?)?.toDouble();
                    final puja = (data['pujaSubscription'] as num?)?.toDouble() ?? 90.0;
                    final carCharges = (data['carParkingCharges'] as num?)?.toDouble() ?? 0.0;
                    final bikeCharges = (data['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0;
                    final carCount = (data['carCount'] as num?)?.toInt() ?? 0;
                    final bikeCount = (data['bikeCount'] as num?)?.toInt() ?? 0;

                    String submittedDateStr = 'Just now';
                    if (data['submittedAt'] is Timestamp) {
                      submittedDateStr = AppFormatters.dateTime((data['submittedAt'] as Timestamp).toDate());
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: AppDecorations.card(
                        borderColor: AppColors.warningBorder,
                        borderRadius: 12,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    AppDecorations.iconContainer(
                                      icon: Icons.pending_actions_rounded,
                                      color: AppColors.warning,
                                      size: 20,
                                      padding: 8,
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Flat $flat • $month',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                                            ),
                                            const SizedBox(width: 8),
                                            AppBadge.category(paymentCategory, isOnline: paymentCategory == 'ONLINE'),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Submitted: $submittedDateStr via $paymentMode',
                                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Text(
                                  AppFormatters.currency(amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: AppColors.primary,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            // Unique ID Highlight Box
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.infoSurface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.infoBorder),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.tag_rounded, color: AppColors.info, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    paymentCategory == 'ONLINE' ? '16-Char UTR / Ref:' : 'Cheque / Ref:',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textPrimary),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText(
                                      uniqueId,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.info,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: uniqueId));
                                      AppFeedback.showInfo(context, 'Copied Unique ID ($uniqueId) to clipboard');
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.all(4.0),
                                      child: Icon(Icons.copy_rounded, size: 16, color: AppColors.info),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Itemized Breakdown Wrap
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (baseMaint != null)
                                  AppBadge(
                                    label: 'Base: ${AppFormatters.currency(baseMaint)}',
                                    textColor: AppColors.textSecondary,
                                    backgroundColor: AppColors.cardSurfaceSecondary,
                                    borderColor: AppColors.border,
                                    fontSize: 10,
                                  ),
                                AppBadge(
                                  label: 'Puja: ${AppFormatters.currency(puja)}',
                                  textColor: AppColors.textSecondary,
                                  backgroundColor: AppColors.cardSurfaceSecondary,
                                  borderColor: AppColors.border,
                                  fontSize: 10,
                                ),
                                if (carCharges > 0)
                                  AppBadge(
                                    label: 'Car ($carCount): ${AppFormatters.currency(carCharges)}',
                                    textColor: AppColors.textSecondary,
                                    backgroundColor: AppColors.cardSurfaceSecondary,
                                    borderColor: AppColors.border,
                                    fontSize: 10,
                                  ),
                                if (bikeCharges > 0)
                                  AppBadge(
                                    label: 'Bike ($bikeCount): ${AppFormatters.currency(bikeCharges)}',
                                    textColor: AppColors.textSecondary,
                                    backgroundColor: AppColors.cardSurfaceSecondary,
                                    borderColor: AppColors.border,
                                    fontSize: 10,
                                  ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Action Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(color: AppColors.errorBorder),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: const Size(0, 36),
                                  ),
                                  icon: const Icon(Icons.close_rounded, size: 15),
                                  label: const Text('Reject Submission', style: TextStyle(fontSize: 12)),
                                  onPressed: isProcessing ? null : () => _showRejectDialog(context, dueId, data),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    minimumSize: const Size(0, 36),
                                  ),
                                  icon: isProcessing
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Icon(Icons.verified_rounded, size: 16),
                                  label: Text(
                                    isProcessing ? 'Posting to Accounts...' : 'Approve & Post to Income',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  onPressed: isProcessing ? null : () => _verifyPayment(dueId, data),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
