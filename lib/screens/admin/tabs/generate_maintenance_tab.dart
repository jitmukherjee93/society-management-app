import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../models/accounting_heads.dart';

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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send Maintenance Bills for $_selectedMonth'),
        content: Text(
          'This will automatically calculate each flat\'s maintenance bill using their registered details (Block base rate + Puja subscription + registered 4-wheeler/2-wheeler parking charges as per the FY ${AccountingConfig.currentFinancialYear} budget) and send instant billing notifications to all residents.\n\n'
          'Existing bills for $_selectedMonth will be updated/skipped without double-billing. Proceed?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Bills & Notify'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
      for (final doc in existingDuesSnap.docs) {
        final f = (doc.data()['flatNumber'] ?? '').toString().trim().toUpperCase();
        if (f.isNotEmpty) existingFlats[f] = doc;
      }

      int generatedCount = 0;
      int notifiedCount = 0;
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
        if (!existingFlats.containsKey(flatKey)) {
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

        // Send instant notification to resident
        final newNotificationDoc = notificationsRef.doc();
        batch.set(newNotificationDoc, {
          'targetUid': userDoc.id,
          'targetRole': 'RESIDENT',
          'type': 'MAINTENANCE_DUE',
          'title': 'Maintenance Bill Issued: $_selectedMonth',
          'message': 'Your maintenance bill of ${_currencyFmt.format(breakdown.totalMonthlyDue)} for $_selectedMonth has been generated. Please tap to view breakdown and pay.',
          'flatNumber': flatKey,
          'amount': breakdown.totalMonthlyDue,
          'month': _selectedMonth,
          'createdAt': FieldValue.serverTimestamp(),
        });
        notifiedCount++;
      }

      await batch.commit();

      setState(() {
        _resultMsg = 'Successfully issued $generatedCount bill(s) and sent notifications to $notifiedCount flat(s) for $_selectedMonth.';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(_resultMsg!),
          ),
        );
      }
    } catch (e) {
      setState(() => _resultMsg = 'Error sending maintenance bills: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.campaign, color: Colors.deepPurple, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Generate Maintenance Bills',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Auto-calculates from flat registered vehicles and sends instant notification bills',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Month Selector
                  DropdownButtonFormField<String>(
                    initialValue: _selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'Select Billing Month *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_month, color: Colors.deepPurple),
                    ),
                    items: _monthsList.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedMonth = val);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Send Notification Bill Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isProcessing ? null : _sendMaintenanceNotificationBills,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 22),
                      label: Text(
                        _isProcessing ? 'Generating & Sending...' : 'Send Maintenance Notification Bill',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  if (_resultMsg != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _resultMsg!,
                              style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Billing Records & Status for Selected Month
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Billed Records ($_selectedMonth)',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              DropdownButton<String>(
                value: _filterStatus,
                isDense: true,
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
            ],
          ),
          const SizedBox(height: 8),

          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by Flat (e.g. B-201)...',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim().toUpperCase()),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('maintenance_dues')
                .where('month', isEqualTo: _selectedMonth)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
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
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Center(
                    child: Text(
                      'No maintenance bills generated yet for $_selectedMonth.\nTap "Send Maintenance Notification Bill" above to generate.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
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
                if (st == 'PAID_ONLINE' || st == 'PAID_OFFLINE_VERIFIED') {
                  totalCollected += amt;
                }
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepPurple.shade100),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Billed: ${_currencyFmt.format(totalBilled)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text('Collected: ${_currencyFmt.format(totalCollected)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green.shade700)),
                        Text('Pending: ${_currencyFmt.format(totalBilled - totalCollected)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red.shade700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final flat = data['flatNumber'] ?? 'Unknown';
                      final amount = data['amount'] ?? 0;
                      final status = data['status'] ?? 'UNPAID';

                      Color statusColor = Colors.red;
                      String statusLabel = 'UNPAID';
                      if (status == 'PAID_ONLINE') {
                        statusColor = Colors.green;
                        statusLabel = 'PAID (ONLINE)';
                      } else if (status == 'PAID_OFFLINE_PENDING') {
                        statusColor = Colors.orange;
                        statusLabel = 'OFFLINE PENDING';
                      } else if (status == 'PAID_OFFLINE_VERIFIED') {
                        statusColor = Colors.green.shade800;
                        statusLabel = 'PAID (VERIFIED)';
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        child: ListTile(
                          dense: true,
                          title: Text('Flat $flat', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Amount: ${_currencyFmt.format(amount)}'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: statusColor.withOpacity(0.4)),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                            ),
                          ),
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
