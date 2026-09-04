import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tabs/community_feed_tab.dart';

class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomeTab(),
    const CommunityFeedTab(),
    const NotificationsTab(),
    const ResidentHelpdeskTab(),
    const MaintenanceTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resident Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'Community'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.support_agent), label: 'Helpdesk'),
          BottomNavigationBarItem(icon: Icon(Icons.payment), label: 'Maintenance'),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PreApproveVisitorScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Pre-approve Visitor'),
            )
          : null,
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: const [
        Text(
          'Quick Actions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Icon(Icons.security, size: 40, color: Colors.teal),
            title: Text('Gate Pass System'),
            subtitle: Text('Manage your visitors securely.'),
          ),
        ),
      ],
    );
  }
}

class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No announcements yet.'));
        }

        docs.sort((a, b) {
          final aPinned = (a.data() as Map<String, dynamic>)['isPinned'] ?? false;
          final bPinned = (b.data() as Map<String, dynamic>)['isPinned'] ?? false;
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          return 0; // retain createdAt sort order
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final isPinned = data['isPinned'] ?? false;
            
            return Card(
              elevation: isPinned ? 4 : 1,
              color: isPinned ? Colors.teal.shade50 : null,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isPinned) const Icon(Icons.push_pin, color: Colors.teal, size: 20),
                        if (isPinned) const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            data['title'] ?? '',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(data['message'] ?? '', style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class MaintenanceTab extends StatelessWidget {
  const MaintenanceTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final flatNumber = userSnapshot.data?.get('flatNumber');
        
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('maintenance_dues')
              .where('flatNumber', isEqualTo: flatNumber)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(child: Text('No maintenance dues found.'));
            }

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final status = data['status'];
                final amount = data['amount'];
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long, size: 40, color: Colors.teal),
                    title: Text('Month: ${data['month']}'),
                    subtitle: Text('Amount: ₹$amount\nStatus: $status'),
                    isThreeLine: true,
                    trailing: status == 'UNPAID' 
                      ? ElevatedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Pay Maintenance'),
                                content: const Text('Choose payment method:'),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      // Mock Offline Payment Submission
                                      FirebaseFirestore.instance
                                          .collection('maintenance_dues')
                                          .doc(docs[index].id)
                                          .update({'status': 'PAID_OFFLINE_PENDING'});
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Offline payment submitted for verification.')),
                                      );
                                    },
                                    child: const Text('Offline (Cash/Cheque)'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      // Mock Online Payment
                                      FirebaseFirestore.instance
                                          .collection('maintenance_dues')
                                          .doc(docs[index].id)
                                          .update({'status': 'PAID_ONLINE'});
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Online payment successful!')),
                                      );
                                    },
                                    child: const Text('Pay Online'),
                                  ),
                                ],
                              )
                            );
                          },
                          child: const Text('Pay Now'),
                        )
                      : const Icon(Icons.check_circle, color: Colors.green),
                  ),
                );
              },
            );
          },
        );
      }
    );
  }
}

// ------ Pre-Approve Visitor Screen ------
class PreApproveVisitorScreen extends StatefulWidget {
  const PreApproveVisitorScreen({super.key});

  @override
  State<PreApproveVisitorScreen> createState() => _PreApproveVisitorScreenState();
}

class _PreApproveVisitorScreenState extends State<PreApproveVisitorScreen> {
  final _formKey = GlobalKey<FormState>();
  String _visitorName = '';
  String _purpose = 'Guest';

  bool _isLoading = false;

  Future<void> _generatePass() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      setState(() => _isLoading = true);
      
      try {
        final user = FirebaseAuth.instance.currentUser!;
        // Fetch host flat number
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final flatNumber = userDoc.data()?['flatNumber'] ?? 'Unknown';
        
        // Generate random 6-digit code
        final passCode = (100000 + DateTime.now().microsecondsSinceEpoch % 900000).toString();

        await FirebaseFirestore.instance.collection('visitors').add({
          'visitorName': _visitorName,
          'purpose': _purpose,
          'hostFlatNumber': flatNumber,
          'hostUid': user.uid,
          'passCode': passCode,
          'status': 'PENDING', // PENDING, CHECKED_IN, CHECKED_OUT
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Gate Pass Generated'),
            content: Text(
              'Share this code with $_visitorName:\n\n$passCode',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(); // Close dialog
                  Navigator.of(context).pop(); // Close screen
                },
                child: const Text('Done'),
              )
            ],
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pre-Approve Visitor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Visitor Name'),
                validator: (val) => val!.isEmpty ? 'Required' : null,
                onSaved: (val) => _visitorName = val!,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _purpose,
                decoration: const InputDecoration(labelText: 'Purpose'),
                items: const [
                  DropdownMenuItem(value: 'Guest', child: Text('Guest')),
                  DropdownMenuItem(value: 'Delivery', child: Text('Delivery')),
                  DropdownMenuItem(value: 'Service', child: Text('Service/Repair')),
                ],
                onChanged: (val) => setState(() => _purpose = val!),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _generatePass,
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator()) 
                    : const Text('Generate Pass Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResidentHelpdeskTab extends StatefulWidget {
  const ResidentHelpdeskTab({super.key});

  @override
  State<ResidentHelpdeskTab> createState() => _ResidentHelpdeskTabState();
}

class _ResidentHelpdeskTabState extends State<ResidentHelpdeskTab> {
  void _showRaiseTicketDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String category = 'Maintenance';
    bool isLoading = false;
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Raise a Ticket'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                      DropdownMenuItem(value: 'Security', child: Text('Security')),
                      DropdownMenuItem(value: 'Cleanliness', child: Text('Cleanliness')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (val) => setState(() => category = val!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  if (titleController.text.trim().isEmpty || descController.text.trim().isEmpty) return;
                  setState(() => isLoading = true);
                  
                  try {
                    final uid = FirebaseAuth.instance.currentUser!.uid;
                    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                    final flatNumber = userDoc.data()?['flatNumber'] ?? 'Unknown';
                    
                    await FirebaseFirestore.instance.collection('complaints').add({
                      'title': titleController.text.trim(),
                      'description': descController.text.trim(),
                      'category': category,
                      'status': 'OPEN',
                      'residentUid': uid,
                      'flatNumber': flatNumber,
                      'createdAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    
                    if (context.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    setState(() => isLoading = false);
                  }
                },
                child: isLoading ? const CircularProgressIndicator() : const Text('Submit'),
              )
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('complaints')
            .where('residentUid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('You have not raised any tickets.'));
          }
          
          // Sort by createdAt locally
          docs.sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime); // descending
          });

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
                child: ListTile(
                  title: Text(data['title'] ?? 'No Title', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Category: ${data['category'] ?? 'General'}'),
                  trailing: Container(
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
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRaiseTicketDialog,
        icon: const Icon(Icons.add),
        label: const Text('Raise Ticket'),
      ),
    );
  }
}
