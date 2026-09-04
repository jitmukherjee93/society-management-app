import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GenerateMaintenanceTab extends StatefulWidget {
  const GenerateMaintenanceTab({super.key});

  @override
  State<GenerateMaintenanceTab> createState() => _GenerateMaintenanceTabState();
}

class _GenerateMaintenanceTabState extends State<GenerateMaintenanceTab> {
  final _formKey = GlobalKey<FormState>();
  final _flatController = TextEditingController();
  final _amountController = TextEditingController();
  final _monthController = TextEditingController();
  bool _isLoading = false;

  Future<void> _generateDue() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance.collection('maintenance_dues').add({
        'flatNumber': _flatController.text.trim(),
        'amount': double.parse(_amountController.text.trim()),
        'month': _monthController.text.trim(),
        'status': 'UNPAID',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maintenance Due Generated Successfully!')),
        );
        _flatController.clear();
        _amountController.clear();
        _monthController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: ListView(
          children: [
            const Text(
              'Issue Maintenance Bill',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _flatController,
              decoration: const InputDecoration(labelText: 'Flat / Villa Number'),
              validator: (val) => val!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _monthController,
              decoration: const InputDecoration(labelText: 'Billing Month (e.g., Aug 2026)'),
              validator: (val) => val!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
              keyboardType: TextInputType.number,
              validator: (val) => val!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16)
              ),
              onPressed: _isLoading ? null : _generateDue,
              child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Generate Bill', style: TextStyle(fontSize: 18)),
            )
          ],
        ),
      ),
    );
  }
}
