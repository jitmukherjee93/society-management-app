import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tabs/manage_society_tab.dart';
import 'tabs/generate_maintenance_tab.dart';
import 'tabs/verify_payments_tab.dart';
import 'tabs/manage_announcements_tab.dart';
import 'tabs/manage_complaints_tab.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const ManageSocietyTab(),
    const ManageAnnouncementsTab(),
    const ManageComplaintsTab(),
    const GenerateMaintenanceTab(),
    const VerifyPaymentsTab(),
  ];

  void _showNotificationsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Admin Notifications'),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('targetRole', isEqualTo: 'ADMIN')
                .orderBy('createdAt', descending: true)
                .limit(30)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('No new notifications.', style: TextStyle(color: Colors.grey)),
                );
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final notif = docs[i].data() as Map<String, dynamic>;
                  final title = notif['title'] ?? 'Notification';
                  final msg = notif['message'] ?? '';
                  final isVehicleReq = notif['type'] == 'VEHICLE_UPDATE_REQUEST';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: isVehicleReq ? Colors.orange.shade100 : Colors.deepPurple.shade100,
                      child: Icon(
                        isVehicleReq ? Icons.directions_car : Icons.info_outline,
                        color: isVehicleReq ? Colors.orange.shade900 : Colors.deepPurple,
                      ),
                    ),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(msg, style: const TextStyle(fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                      onPressed: () => docs[i].reference.delete(),
                      tooltip: 'Dismiss',
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.deepPurple,
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('targetRole', isEqualTo: 'ADMIN')
                .snapshots(),
            builder: (context, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications, color: Colors.white),
                    tooltip: 'Notifications',
                    onPressed: () => _showNotificationsDialog(context),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Log out', style: TextStyle(color: Colors.white)),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.deepPurple,
        type: BottomNavigationBarType.fixed,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.apartment), label: 'Flats'),
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'Notices'),
          BottomNavigationBarItem(icon: Icon(Icons.support_agent), label: 'Helpdesk'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'Bills'),
          BottomNavigationBarItem(icon: Icon(Icons.fact_check), label: 'Payments'),
        ],
      ),
    );
  }
}

