import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _visitorData;
  String? _visitorDocId;

  Future<void> _verifyPass() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit code')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _visitorData = null;
      _visitorDocId = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('visitors')
          .where('passCode', isEqualTo: code)
          .where('status', isEqualTo: 'PENDING')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid or already used pass code')),
          );
        }
      } else {
        setState(() {
          _visitorDocId = snapshot.docs.first.id;
          _visitorData = snapshot.docs.first.data();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error verifying pass: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkInVisitor() async {
    if (_visitorDocId == null) return;

    setState(() => _isLoading = true);
    
    try {
      await FirebaseFirestore.instance.collection('visitors').doc(_visitorDocId).update({
        'status': 'CHECKED_IN',
        'entryTime': FieldValue.serverTimestamp(),
        'checkedInBy': FirebaseAuth.instance.currentUser?.uid,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Visitor Checked In Successfully!')),
        );
        setState(() {
          _visitorData = null;
          _visitorDocId = null;
          _codeController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error checking in: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guard Dashboard'),
        backgroundColor: Colors.blueGrey,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Log out', style: TextStyle(color: Colors.white)),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Gate Pass Verification',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Enter 6-digit code',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
              ),
              onPressed: _isLoading ? null : _verifyPass,
              child: _isLoading && _visitorDocId == null
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                  : const Text('Verify Pass', style: TextStyle(fontSize: 18)),
            ),
            
            if (_visitorData != null) ...[
              const SizedBox(height: 32),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Visitor Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      const Divider(),
                      Text('Name: ${_visitorData!['visitorName']}', style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('Purpose: ${_visitorData!['purpose']}', style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 8),
                      Text('Visiting Flat: ${_visitorData!['hostFlatNumber']}', style: const TextStyle(fontSize: 18)),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(16)
                          ),
                          onPressed: _isLoading ? null : _checkInVisitor,
                          icon: const Icon(Icons.check_circle),
                          label: _isLoading && _visitorDocId != null
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white))
                              : const Text('Confirm Entry & Check In', style: TextStyle(fontSize: 18)),
                        ),
                      )
                    ],
                  ),
                ),
              )
            ]
          ],
        ),
      ),
    );
  }
}

