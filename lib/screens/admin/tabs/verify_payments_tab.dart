import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VerifyPaymentsTab extends StatelessWidget {
  const VerifyPaymentsTab({super.key});

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
          return const Center(child: Text('No pending offline payments to verify.'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                title: Text('Flat ${data['flatNumber']} - ₹${data['amount']}'),
                subtitle: Text('Month: ${data['month']}'),
                trailing: ElevatedButton(
                  onPressed: () {
                    FirebaseFirestore.instance
                        .collection('maintenance_dues')
                        .doc(docs[index].id)
                        .update({'status': 'PAID_OFFLINE_VERIFIED'});
                  },
                  child: const Text('Verify'),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
