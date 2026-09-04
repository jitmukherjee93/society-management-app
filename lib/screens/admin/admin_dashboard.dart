import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.deepPurple,
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

