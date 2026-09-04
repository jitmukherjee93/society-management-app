import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManageComplaintsTab extends StatefulWidget {
  const ManageComplaintsTab({super.key});

  @override
  State<ManageComplaintsTab> createState() => _ManageComplaintsTabState();
}

class _ManageComplaintsTabState extends State<ManageComplaintsTab> {
  String _filterStatus = 'ALL'; // ALL, OPEN, IN_PROGRESS, RESOLVED

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Helpdesk', style: TextStyle(fontSize: 18)),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButton<String>(
              value: _filterStatus,
              dropdownColor: Colors.deepPurple.shade50,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All Tickets')),
                DropdownMenuItem(value: 'OPEN', child: Text('Open')),
                DropdownMenuItem(value: 'IN_PROGRESS', child: Text('In Progress')),
                DropdownMenuItem(value: 'RESOLVED', child: Text('Resolved')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _filterStatus = val);
              },
            ),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('complaints').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          var docs = snapshot.data?.docs ?? [];
          
          // Filter locally
          if (_filterStatus != 'ALL') {
            docs = docs.where((doc) {
              final status = (doc.data() as Map<String, dynamic>)['status'] ?? 'OPEN';
              return status == _filterStatus;
            }).toList();
          }

          if (docs.isEmpty) {
            return const Center(child: Text('No complaints found.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final status = data['status'] ?? 'OPEN';
              
              Color statusColor = Colors.red;
              if (status == 'IN_PROGRESS') statusColor = Colors.orange;
              if (status == 'RESOLVED') statusColor = Colors.green;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Flat: ${data['flatNumber'] ?? 'Unknown'}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: statusColor),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data['title'] ?? 'No Title',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Category: ${data['category'] ?? 'General'}',
                        style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 8),
                      Text(data['description'] ?? ''),
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Text('Update Status: '),
                          DropdownButton<String>(
                            value: status,
                            items: const [
                              DropdownMenuItem(value: 'OPEN', child: Text('OPEN')),
                              DropdownMenuItem(value: 'IN_PROGRESS', child: Text('IN PROGRESS')),
                              DropdownMenuItem(value: 'RESOLVED', child: Text('RESOLVED')),
                            ],
                            onChanged: (newStatus) {
                              if (newStatus != null && newStatus != status) {
                                FirebaseFirestore.instance
                                    .collection('complaints')
                                    .doc(docs[index].id)
                                    .update({'status': newStatus, 'updatedAt': FieldValue.serverTimestamp()});
                              }
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
