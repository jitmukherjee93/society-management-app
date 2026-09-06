import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VerifyPaymentsTab extends StatelessWidget {
  const VerifyPaymentsTab({super.key});

  Future<void> _verifyPayment(BuildContext context, String dueId, Map<String, dynamic> data) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final flat = (data['flatNumber'] ?? 'Unknown').toString();
      final month = (data['month'] ?? '').toString();
      final double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;

      // Determine budget block head
      String head = 'Monthly Maintenance - Block A';
      final cleanUpper = flat.toUpperCase();
      if (cleanUpper.startsWith('B')) {
        head = 'Monthly Maintenance - Block B';
      } else if (cleanUpper.startsWith('C')) {
        head = 'Monthly Maintenance - Block C';
      } else if (cleanUpper.startsWith('D')) {
        head = 'Monthly Maintenance - Block D';
      }

      await FirebaseFirestore.instance
          .collection('maintenance_dues')
          .doc(dueId)
          .update({'status': 'PAID_OFFLINE_VERIFIED'});

      // Post income entry into society accounts ledger
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final voucherCode = 'INC-2627-${(timestamp % 100000).toString().padLeft(5, '0')}';
      await FirebaseFirestore.instance.collection('society_transactions').add({
        'type': 'INCOME',
        'voucherNumber': voucherCode,
        'accountHead': head,
        'category': 'Maintenance Collection',
        'amount': amount,
        'paidToOrReceivedFrom': 'Flat $flat',
        'paymentDate': FieldValue.serverTimestamp(),
        'paymentMode': 'Cash / Cheque (Offline Verified)',
        'referenceNumber': 'Due ID: $dueId',
        'description': 'Maintenance collection for $month from Flat $flat',
        'linkedDueId': dueId,
        'recordedBy': 'Admin',
        'createdAt': FieldValue.serverTimestamp(),
      });

      scaffoldMessenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('Payment verified & posted to Accounts ($voucherCode)!'),
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error verifying payment: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance_dues')
          .where('status', isEqualTo: 'PAID_OFFLINE_PENDING')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text(
                  'No pending offline payments to verify.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
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
              Text(
                'Pending Offline Maintenance Payments (${docs.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final dueId = docs[index].id;
                    final flat = data['flatNumber'] ?? 'Unknown';
                    final amount = data['amount'] ?? 0;
                    final month = data['month'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orange,
                          child: Icon(Icons.pending_actions, color: Colors.white),
                        ),
                        title: Text('Flat $flat — ₹$amount',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Billing Month: $month\nStatus: Pending Admin Verification'),
                        isThreeLine: true,
                        trailing: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.verified, size: 16),
                          label: const Text('Verify & Post to Accounts'),
                          onPressed: () => _verifyPayment(context, dueId, data),
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
