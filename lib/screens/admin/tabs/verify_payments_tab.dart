import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/app_formatters.dart';
import '../../../utils/flat_utils.dart';
import '../../../services/notification_service.dart';

class VerifyPaymentsTab extends StatefulWidget {
  const VerifyPaymentsTab({super.key});

  @override
  State<VerifyPaymentsTab> createState() => _VerifyPaymentsTabState();
}

class _VerifyPaymentsTabState extends State<VerifyPaymentsTab> {
  final Set<String> _processingDues = {};

  Future<void> _verifyPayment(BuildContext context, String dueId, Map<String, dynamic> data) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
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

      scaffoldMessenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('Payment for Flat $normFlat approved & posted to Accounts ($voucherCode)!'),
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Error approving payment: $e')),
      );
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
              child: const Icon(Icons.cancel_outlined, color: Colors.red),
            ),
            const SizedBox(width: 10),
            const Text('Reject Payment Submission', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flat: $flat • Month: $month\nMode: $mode\nUnique ID / Ref: $uniqueId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for Rejection *',
                hintText: 'Explain why the payment could not be verified...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(ctx);

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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: Colors.orange.shade800, content: Text('Payment rejected. Resident ($flat) has been notified.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
                  );
                }
              } finally {
                if (mounted) setState(() => _processingDues.remove(dueId));
              }
            },
            child: const Text('Confirm Rejection'),
          ),
        ],
      ),
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

                    return Card(
                      margin: const EdgeInsets.only(bottom: 14),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.amber.shade400, width: 1.2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.pending_actions_rounded, color: Colors.deepOrange, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Flat $flat • $month',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: paymentCategory == 'ONLINE' ? Colors.blue.shade50 : Colors.purple.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: paymentCategory == 'ONLINE' ? Colors.blue.shade200 : Colors.purple.shade200),
                                              ),
                                              child: Text(
                                                paymentCategory,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: paymentCategory == 'ONLINE' ? Colors.blue.shade800 : Colors.purple.shade800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          'Submitted: $submittedDateStr via $paymentMode',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Text(
                                  AppFormatters.currency(amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 10),

                            // Unique ID Highlight Box
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.tag, color: Colors.blue, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    paymentCategory == 'ONLINE' ? 'Unique ID (16-Char UTR / Ref):' : 'Unique ID (Cheque / Ref):',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: SelectableText(
                                      uniqueId,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.blue,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18, color: Colors.blue),
                                    tooltip: 'Copy Unique ID',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: uniqueId));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          duration: const Duration(seconds: 2),
                                          content: Text('Copied Unique ID ($uniqueId) to clipboard!'),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            // Itemized Breakdown Wrap
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (baseMaint != null)
                                  Chip(
                                    label: Text('Base: ${AppFormatters.currency(baseMaint)}', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: Colors.grey.shade100,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                Chip(
                                  label: Text('Puja: ${AppFormatters.currency(puja)}', style: const TextStyle(fontSize: 11)),
                                  backgroundColor: Colors.grey.shade100,
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                if (carCharges > 0)
                                  Chip(
                                    label: Text('Car ($carCount): ${AppFormatters.currency(carCharges)}', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: Colors.grey.shade100,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                if (bikeCharges > 0)
                                  Chip(
                                    label: Text('Bike ($bikeCount): ${AppFormatters.currency(bikeCharges)}', style: const TextStyle(fontSize: 11)),
                                    backgroundColor: Colors.grey.shade100,
                                    padding: EdgeInsets.zero,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            // Action Buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                  icon: const Icon(Icons.close, size: 16),
                                  label: const Text('Reject Submission'),
                                  onPressed: isProcessing ? null : () => _showRejectDialog(context, dueId, data),
                                ),
                                const SizedBox(width: 10),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                  ),
                                  icon: isProcessing
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : const Icon(Icons.verified, size: 18),
                                  label: Text(isProcessing ? 'Posting to Accounts...' : 'Approve & Post to Income'),
                                  onPressed: isProcessing ? null : () => _verifyPayment(context, dueId, data),
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
