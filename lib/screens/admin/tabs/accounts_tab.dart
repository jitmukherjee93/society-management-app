import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../../models/accounting_heads.dart';
import '../../../services/staff_remuneration_service.dart';
import '../../../utils/storage_utils.dart';
import '../../../utils/file_downloader.dart';
import '../../../widgets/document_preview_dialog.dart';

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  final dateFmt = DateFormat('dd MMM yyyy');

  String _searchQuery = '';
  String? _filterHead;
  String? _filterType; // 'ALL', 'INCOME', 'EXPENDITURE'
  String _selectedRemunerationMonth = 'April 2026';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── Helpers: File Upload ──────────────────────────────────────────────────
  Future<String?> _uploadVoucherFile(PlatformFile file, String voucherId) async {
    return uploadFile(file, 'society_accounts_vouchers/${voucherId}_${file.name}');
  }

  Future<String?> _uploadMomFile(PlatformFile file, String headName) async {
    final headSlug = headName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return uploadFile(file, 'society_budget_moms/${headSlug}_${timestamp}_${file.name}');
  }

  // ─── Dialog: Document Preview ──────────────────────────────────────────────
  void _showDocumentPreview(String url, String fileName) {
    showDocumentPreviewDialog(context, url, fileName);
  }

  // ─── Annual Budget Plan: Lock Check & Dialogs ──────────────────────────────
  void _handleAnnualBudgetUpload(
    dynamic annualBudgetDocOrData,
    double totalApprovedAnnualBudget,
    double totalApprovedMonthlyBudget,
  ) {
    Map<String, dynamic>? data;
    if (annualBudgetDocOrData is DocumentSnapshot) {
      data = annualBudgetDocOrData.data() as Map<String, dynamic>?;
    } else if (annualBudgetDocOrData is Map<String, dynamic>) {
      data = annualBudgetDocOrData;
    }

    if (data != null && (data['isLocked'] == true || data.isNotEmpty)) {
      _showBudgetAlreadyLockedDialog(data);
    } else {
      _openUploadAnnualBudgetDialog(totalApprovedAnnualBudget, totalApprovedMonthlyBudget);
    }
  }

  // ─── Dialog: Annual Budget Already Locked (Nice Error / Notice) ─────────────
  void _showBudgetAlreadyLockedDialog(Map<String, dynamic> budgetData) {
    final uploadedAt = (budgetData['uploadedAt'] as Timestamp?)?.toDate();
    final meetingDate = (budgetData['meetingDate'] as Timestamp?)?.toDate();
    final meetingAuthority = budgetData['approvedInMeeting'] ?? 'Annual General Meeting (AGM)';
    final uploadedBy = budgetData['uploadedBy'] ?? 'Admin';
    final resolutionNotes = budgetData['resolutionNotes'] ?? '';
    final budgetDocUrl = budgetData['budgetDocumentUrl'] as String?;
    final budgetDocName = budgetData['budgetDocumentName'] as String?;
    final double outlay = (budgetData['totalExpenditureOutlay'] as num?)?.toDouble() ?? 0.0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Premium Header with Lock Icon
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.amber.shade900, Colors.orange.shade800],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_person_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Annual Budget Plan Already Uploaded',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'FY ${AccountingConfig.currentFinancialYear} • One-Time Annual Master Budget',
                            style: TextStyle(
                              color: Colors.amber.shade100,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Prominent Error & Policy Notice Banner
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade400, width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 26),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Budget upload is a one-time job for a year.',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.brown.shade900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'The master annual budget plan for FY ${AccountingConfig.currentFinancialYear} has already been registered and locked in the system. Re-uploading an entire annual plan is restricted to preserve financial consistency and audit history.',
                                  style: TextStyle(fontSize: 12, color: Colors.brown.shade800, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Current Locked Plan Details
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Registered Master Budget Details',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'STATUS: LOCKED & ACTIVE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Approved In / Authority', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text(meetingAuthority, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    if (meetingDate != null)
                                      Text('Date: ${dateFmt.format(meetingDate)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Approved Annual Outlay', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text(
                                      outlay > 0
                                          ? currencyFmt.format(outlay)
                                          : currencyFmt.format(AccountingConfig.totalAnnualBudget),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                                    ),
                                    if (uploadedAt != null)
                                      Text('Uploaded: ${dateFmt.format(uploadedAt)} by $uploadedBy', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (resolutionNotes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Resolution: "$resolutionNotes"',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey.shade800),
                            ),
                          ],
                          if (budgetDocUrl != null && budgetDocUrl.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            InkWell(
                              onTap: () => _showDocumentPreview(budgetDocUrl, budgetDocName ?? 'Annual_Budget_Plan.pdf'),
                              child: Row(
                                children: [
                                  const Icon(Icons.picture_as_pdf, size: 16, color: Colors.deepPurple),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'View Master Document (${budgetDocName ?? "Annual_Budget.pdf"})',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.deepPurple,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Next Steps Guide Callout
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.deepPurple.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Colors.deepPurple, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Please make updates from the Update Budget page:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'To revise allocations or adjust funds for any specific head, navigate to the "Budget vs Actual" tab. Click the edit icon on the relevant budget head and attach the supporting Minutes of Meeting (MoM) resolution.',
                                  style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade900, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Action Buttons Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      icon: const Icon(Icons.pie_chart_outline, size: 18),
                      label: const Text('Go to Update Budget Page'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _tabController.animateTo(3); // Switch to Tab 4: Budget vs Actual
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Dialog: One-Time Annual Budget Plan Upload ─────────────────────────────
  void _openUploadAnnualBudgetDialog(
    double totalApprovedAnnualBudget,
    double totalApprovedMonthlyBudget,
  ) {
    final formKey = GlobalKey<FormState>();
    String selectedFY = AccountingConfig.currentFinancialYear;
    String meetingType = AccountingConfig.meetingTypes.first;
    DateTime meetingDate = DateTime.now();
    final notesCtrl = TextEditingController(text: 'Annual budget plan for FY 2026-27 approved in AGM');
    PlatformFile? masterDocFile;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.upload_file, color: Colors.deepPurple, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload Annual Budget Plan (One-Time)',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Register & Lock Master Financial Budget for the Year',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Financial Year & Authority
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: selectedFY,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Financial Year',
                                prefixIcon: Icon(Icons.calendar_today),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: meetingType,
                              decoration: const InputDecoration(
                                labelText: 'Approval Authority *',
                                prefixIcon: Icon(Icons.groups),
                                border: OutlineInputBorder(),
                              ),
                              items: AccountingConfig.meetingTypes
                                  .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setDS(() => meetingType = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Meeting Date
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: meetingDate,
                            firstDate: DateTime(2025, 1, 1),
                            lastDate: DateTime(2030, 12, 31),
                          );
                          if (picked != null) {
                            setDS(() => meetingDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Approval / Meeting Date *',
                            prefixIcon: Icon(Icons.date_range),
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            dateFmt.format(meetingDate),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Remarks / Resolution Notes
                      TextFormField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Resolution Summary / Notes *',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                          hintText: 'e.g. Annual Budget 2026-27 approved in Annual General Meeting #14',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().length < 5) {
                            return 'Please enter a brief resolution note';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Master Budget Document Upload (PDF / Image / Excel)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: masterDocFile == null ? Colors.deepPurple.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: masterDocFile == null ? Colors.deepPurple.shade200 : Colors.green.shade300,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  masterDocFile == null ? Icons.attach_file : Icons.check_circle,
                                  color: masterDocFile == null ? Colors.deepPurple : Colors.green.shade800,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Master Budget Document (PDF / Image / Excel)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: masterDocFile == null ? Colors.deepPurple.shade900 : Colors.green.shade900,
                                        ),
                                      ),
                                      const Text(
                                        'Attach the official signed budget document or AGM resolution copy.',
                                        style: TextStyle(fontSize: 11, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: masterDocFile == null ? Colors.deepPurple : Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.upload_file, size: 16),
                                  label: Text(masterDocFile == null ? 'Attach Document' : 'Change'),
                                  onPressed: () async {
                                    final file = await pickFile(context: context, extensions: ['pdf', 'png', 'jpg', 'jpeg', 'csv', 'xlsx']);
                                    if (file != null) {
                                      setDS(() => masterDocFile = file);
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (masterDocFile != null) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  Icon(
                                    masterDocFile!.name.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.description,
                                    size: 18,
                                    color: Colors.green.shade800,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      masterDocFile!.name,
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                    onPressed: () => setDS(() => masterDocFile = null),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Budget Plan Summary Preview
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Budget Plan Configuration (FY 2026-27)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Expenditure Heads: ${AccountingConfig.expenditureHeads.length}',
                                    style: const TextStyle(fontSize: 12)),
                                Text('Annual Outlay: ${currencyFmt.format(totalApprovedAnnualBudget)}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Projected Annual Inflow:', style: TextStyle(fontSize: 12)),
                                Text(currencyFmt.format(AccountingConfig.totalProjectedIncomeYearly),
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: Colors.amber),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Note: Once submitted, the master budget plan is locked for the year. Subsequent adjustments must be done per-head with an MoM.',
                              style: TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white))
                    : const Icon(Icons.lock),
                label: const Text('Save & Lock Annual Budget Plan'),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final dialogNav = Navigator.of(ctx);

                        setDS(() => isSubmitting = true);
                        try {
                          final adminUser = FirebaseAuth.instance.currentUser;
                          String? docUrl;
                          String? docName;

                          if (masterDocFile != null) {
                            docName = masterDocFile!.name;
                            final timestamp = DateTime.now().millisecondsSinceEpoch;
                            docUrl = await uploadFile(
                              masterDocFile!,
                              'society_annual_budgets/budget_${selectedFY.replaceAll("-", "_")}_${timestamp}_${masterDocFile!.name}',
                            );
                          }

                          // Save master annual budget document
                          await FirebaseFirestore.instance
                              .collection('society_annual_budgets')
                              .doc(selectedFY)
                              .set({
                            'financialYear': selectedFY,
                            'isLocked': true,
                            'uploadedAt': FieldValue.serverTimestamp(),
                            'uploadedBy': adminUser?.email ?? adminUser?.uid ?? 'Admin',
                            'approvedInMeeting': meetingType,
                            'meetingDate': Timestamp.fromDate(meetingDate),
                            'resolutionNotes': notesCtrl.text.trim(),
                            'budgetDocumentUrl': docUrl,
                            'budgetDocumentName': docName,
                            'totalExpenditureOutlay': totalApprovedAnnualBudget,
                            'totalProjectedInflow': AccountingConfig.totalProjectedIncomeYearly,
                            'headsCount': AccountingConfig.expenditureHeads.length,
                            'status': 'ACTIVE',
                          }, SetOptions(merge: true));

                          dialogNav.pop();
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green.shade700,
                              content: Text('Annual Budget Plan for FY $selectedFY successfully registered and locked!'),
                            ),
                          );
                        } catch (e, st) {
                          debugPrint('Error uploading annual budget: $e\n$st');
                          setDS(() => isSubmitting = false);
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade800,
                              content: Text('Failed to upload budget plan: $e'),
                              duration: const Duration(seconds: 6),
                            ),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Dialog: Edit Budget Head (Requires MoM) ──────────────────────────────
  void _openEditBudgetHeadDialog(BudgetHead head) {
    final formKey = GlobalKey<FormState>();
    final yearlyCtrl = TextEditingController(text: head.yearlyBudget.toStringAsFixed(0));
    final monthlyCtrl = TextEditingController(text: head.monthlyBudget.toStringAsFixed(0));
    final reasonCtrl = TextEditingController(text: head.revisionReason ?? '');
    String meetingType = head.meetingType ?? AccountingConfig.meetingTypes.first;
    DateTime meetingDate = head.meetingDate ?? DateTime.now();
    PlatformFile? momFile;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_calendar, color: Colors.deepPurple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Revise Budget: ${head.name}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis),
                      Text('Category: ${head.category} • Base: ₹${head.yearlyBudget.toStringAsFixed(0)}/yr',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Alert Banner regarding MoM requirement
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.gavel, color: Colors.brown, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Society Governance Rule: Any revision to approved budget allocations strictly requires an attached Minutes of Meeting (MoM) resolution copy.',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.brown),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Allocation Inputs
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: yearlyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'New Annual Budget (₹) *',
                                prefixIcon: Icon(Icons.currency_rupee),
                                border: OutlineInputBorder(),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Enter annual budget';
                                final num? n = num.tryParse(val.trim());
                                if (n == null || n < 0) return 'Enter valid positive amount';
                                return null;
                              },
                              onChanged: (val) {
                                final n = double.tryParse(val.trim());
                                if (n != null) {
                                  setDS(() {
                                    monthlyCtrl.text = (n / 12).round().toString();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: monthlyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'New Monthly Outlay (₹) *',
                                prefixIcon: Icon(Icons.calendar_month),
                                border: OutlineInputBorder(),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Enter monthly budget';
                                final num? n = num.tryParse(val.trim());
                                if (n == null || n < 0) return 'Enter valid positive amount';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Meeting Details
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: meetingType,
                              decoration: const InputDecoration(
                                labelText: 'Meeting / Resolution Authority *',
                                prefixIcon: Icon(Icons.groups),
                                border: OutlineInputBorder(),
                              ),
                              items: AccountingConfig.meetingTypes
                                  .map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setDS(() => meetingType = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: meetingDate,
                                  firstDate: DateTime(2025, 1, 1),
                                  lastDate: DateTime(2030, 12, 31),
                                );
                                if (picked != null) {
                                  setDS(() => meetingDate = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Meeting Date *',
                                  prefixIcon: Icon(Icons.date_range),
                                  border: OutlineInputBorder(),
                                ),
                                child: Text(
                                  DateFormat('dd MMM yyyy').format(meetingDate),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Reason / Justification
                      TextFormField(
                        controller: reasonCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Reason & Resolution Summary *',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                          hintText: 'e.g. Pump breakdown requiring emergency pump rewinding approved in AGM #14',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().length < 8) {
                            return 'Please explain the reason for this budget revision (min 8 chars)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // ─── Mandatory Minutes of Meeting (MoM) Upload ─────────
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: momFile == null ? Colors.red.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: momFile == null ? Colors.red.shade300 : Colors.green.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  momFile == null ? Icons.assignment_late : Icons.assignment_turned_in,
                                  color: momFile == null ? Colors.red.shade900 : Colors.green.shade900,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Minutes of Meeting (MoM) / Resolution Document *',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: momFile == null ? Colors.red.shade900 : Colors.green.shade900,
                                        ),
                                      ),
                                      const Text(
                                        'Upload PDF, scanned copy, or photo of signed meeting minutes.',
                                        style: TextStyle(fontSize: 11, color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: momFile == null ? Colors.red.shade800 : Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.upload_file, size: 16),
                                  label: Text(momFile == null ? 'Upload MoM *' : 'Change MoM'),
                                  onPressed: () async {
                                    final file = await pickFile(context: context);
                                    if (file != null) {
                                      setDS(() => momFile = file);
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (momFile != null) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  Icon(
                                    momFile!.name.toLowerCase().endsWith('.pdf')
                                        ? Icons.picture_as_pdf
                                        : Icons.image,
                                    size: 20,
                                    color: Colors.green.shade800,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      momFile!.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade900,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                    tooltip: 'Remove',
                                    onPressed: () => setDS(() => momFile = null),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 6),
                              const Text(
                                '⚠️ Cannot revise budget without uploading supporting MoM document.',
                                style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                            ],
                            if (head.isRevised && head.momDocumentUrl != null && momFile == null) ...[
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => _showDocumentPreview(head.momDocumentUrl!, head.momFileName ?? 'MoM_Resolution.pdf'),
                                child: Row(
                                  children: [
                                    const Icon(Icons.link, size: 14, color: Colors.deepPurple),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Current Active MoM: ${head.momFileName ?? "View Document"}',
                                      style: const TextStyle(fontSize: 11, color: Colors.deepPurple, decoration: TextDecoration.underline),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text('Save Budget Revision'),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final dialogNav = Navigator.of(ctx);

                        // STRICT RULE: If no new momFile AND no existing momDocumentUrl, block!
                        if (momFile == null && head.momDocumentUrl == null) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade800,
                              content: const Text('Minutes of Meeting (MoM) document is strictly mandatory to revise budget allocations.'),
                            ),
                          );
                          return;
                        }

                        setDS(() => isSubmitting = true);
                        try {
                          final double newYearly = double.parse(yearlyCtrl.text.trim());
                          final double newMonthly = double.parse(monthlyCtrl.text.trim());
                          final adminUser = FirebaseAuth.instance.currentUser;

                          String? momUrl = head.momDocumentUrl;
                          String? momName = head.momFileName;
                          if (momFile != null) {
                            momName = momFile!.name;
                            momUrl = await _uploadMomFile(momFile!, head.name);
                          }

                          // 1. Update society_budget_heads
                          await FirebaseFirestore.instance
                              .collection('society_budget_heads')
                              .doc(head.name)
                              .set({
                            'name': head.name,
                            'category': head.category,
                            'yearlyBudget': newYearly,
                            'monthlyBudget': newMonthly,
                            'isDocRequired': head.isDocRequired,
                            'description': head.description,
                            'isRevised': true,
                            'momDocumentUrl': momUrl,
                            'momFileName': momName,
                            'meetingType': meetingType,
                            'meetingDate': Timestamp.fromDate(meetingDate),
                            'revisionReason': reasonCtrl.text.trim(),
                            'revisedBy': adminUser?.email ?? adminUser?.uid ?? 'Admin',
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                          // 2. Audit Trail in society_budget_revisions
                          await FirebaseFirestore.instance
                              .collection('society_budget_revisions')
                              .add({
                            'headName': head.name,
                            'category': head.category,
                            'oldYearlyBudget': head.yearlyBudget,
                            'oldMonthlyBudget': head.monthlyBudget,
                            'newYearlyBudget': newYearly,
                            'newMonthlyBudget': newMonthly,
                            'momDocumentUrl': momUrl,
                            'momFileName': momName,
                            'meetingType': meetingType,
                            'meetingDate': Timestamp.fromDate(meetingDate),
                            'revisionReason': reasonCtrl.text.trim(),
                            'revisedBy': adminUser?.email ?? adminUser?.uid ?? 'Admin',
                            'createdAt': FieldValue.serverTimestamp(),
                          });

                          dialogNav.pop();
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green.shade700,
                              content: Text('Budget for "${head.name}" successfully revised with MoM attached!'),
                            ),
                          );
                        } catch (e) {
                          setDS(() => isSubmitting = false);
                          scaffoldMessenger.showSnackBar(
                            SnackBar(content: Text('Failed to update budget: $e')),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Dialog: Record New Expenditure ────────────────────────────────────────
  void _openRecordExpenseDialog(Map<String, double> currentSpentMap, [List<BudgetHead>? availableHeads]) {
    final formKey = GlobalKey<FormState>();
    final headsList = availableHeads ?? AccountingConfig.expenditureHeads;
    String selectedHead = headsList.first.name;
    final amountCtrl = TextEditingController();
    final paidToCtrl = TextEditingController();
    DateTime paymentDate = DateTime.now();
    String paymentMode = AccountingConfig.paymentModes.first;
    final refCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    PlatformFile? voucherFile;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {
          final isDocMandatory = AccountingConfig.requiresSupportingDocument(selectedHead);
          final headInfo = headsList.cast<BudgetHead?>().firstWhere(
                (h) => h?.name == selectedHead,
                orElse: () => AccountingConfig.getBudgetHead(selectedHead),
              );
          final double allocated = headInfo?.yearlyBudget ?? 0.0;
          final double alreadySpent = currentSpentMap[selectedHead] ?? 0.0;
          final double remaining = allocated - alreadySpent;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_upward, color: Colors.red, size: 24),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Record Society Expenditure',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Budget 2026-27 Payment Voucher',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Budget Head Selector
                      DropdownButtonFormField<String>(
                        initialValue: selectedHead,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Head of Account *',
                          prefixIcon: Icon(Icons.account_tree),
                          border: OutlineInputBorder(),
                        ),
                        items: headsList.map((head) {
                          return DropdownMenuItem<String>(
                            value: head.name,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    head.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  ' (Budget: ${currencyFmt.format(head.yearlyBudget)}${head.isRevised ? " • Revised" : ""})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: head.isRevised ? Colors.deepPurple : Colors.grey.shade600,
                                    fontWeight: head.isRevised ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDS(() => selectedHead = val);
                          }
                        },
                      ),
                      const SizedBox(height: 8),

                      // Budget Status Indicator for chosen head
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: remaining < 0
                              ? Colors.red.shade50
                              : (remaining < allocated * 0.2
                                  ? Colors.amber.shade50
                                  : Colors.blue.shade50),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: remaining < 0
                                ? Colors.red.shade200
                                : (remaining < allocated * 0.2
                                    ? Colors.amber.shade300
                                    : Colors.blue.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              remaining < 0
                                  ? Icons.warning_amber
                                  : Icons.pie_chart_outline,
                              size: 18,
                              color: remaining < 0 ? Colors.red : Colors.blue.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Budget: ${currencyFmt.format(allocated)}  |  Spent so far: ${currencyFmt.format(alreadySpent)}  |  Remaining: ${currencyFmt.format(remaining)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: remaining < 0 ? Colors.red.shade900 : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Amount & Paid To
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Amount (₹) *',
                                prefixIcon: Icon(Icons.currency_rupee),
                                border: OutlineInputBorder(),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter amount';
                                }
                                final num = double.tryParse(val.trim());
                                if (num == null || num <= 0) {
                                  return 'Valid amount';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 7,
                            child: TextFormField(
                              controller: paidToCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Paid To (Payee / Vendor / Staff) *',
                                prefixIcon: Icon(Icons.person),
                                border: OutlineInputBorder(),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Payee name required';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Payment Date & Payment Mode
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: paymentDate,
                                  firstDate: DateTime(2025, 4, 1),
                                  lastDate: DateTime(2028, 3, 31),
                                );
                                if (picked != null) {
                                  setDS(() => paymentDate = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Payment Date *',
                                  prefixIcon: Icon(Icons.calendar_today),
                                  border: OutlineInputBorder(),
                                ),
                                child: Text(dateFmt.format(paymentDate),
                                    style: const TextStyle(fontSize: 14)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: paymentMode,
                              decoration: const InputDecoration(
                                labelText: 'Payment Mode *',
                                prefixIcon: Icon(Icons.payments),
                                border: OutlineInputBorder(),
                              ),
                              items: AccountingConfig.paymentModes
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setDS(() => paymentMode = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Transaction Ref & Description
                      TextFormField(
                        controller: refCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cheque No. / UTR / Transaction ID (Optional)',
                          prefixIcon: Icon(Icons.numbers),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes / Bill Description',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                          hintText: 'e.g. Pump rewinding service bill no. 452',
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ─── Mandatory Supporting Document Section ─────────────────
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDocMandatory
                              ? (voucherFile == null ? Colors.red.shade50 : Colors.green.shade50)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDocMandatory
                                ? (voucherFile == null ? Colors.red.shade300 : Colors.green.shade300)
                                : Colors.grey.shade400,
                            width: isDocMandatory && voucherFile == null ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isDocMandatory ? Icons.attach_file : Icons.attachment_outlined,
                                  color: isDocMandatory
                                      ? (voucherFile == null ? Colors.red.shade900 : Colors.green.shade900)
                                      : Colors.grey.shade700,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isDocMandatory
                                            ? 'Supporting Bill / Receipt / Voucher (MANDATORY) *'
                                            : 'Supporting Document (Optional for Misc Head)',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDocMandatory
                                              ? (voucherFile == null ? Colors.red.shade900 : Colors.green.shade900)
                                              : Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        isDocMandatory
                                            ? 'Every payment from society must have supporting bill attached.'
                                            : 'Miscellaneous expenses can be saved without receipt if unavailable.',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: voucherFile == null ? Colors.deepPurple : Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.upload_file, size: 16),
                                  label: Text(voucherFile == null ? 'Attach File' : 'Change'),
                                  onPressed: () async {
                                    final file = await pickFile(context: context);
                                    if (file != null) {
                                      setDS(() => voucherFile = file);
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (voucherFile != null) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Selected: ${voucherFile!.name}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                    tooltip: 'Remove',
                                    onPressed: () => setDS(() => voucherFile = null),
                                  ),
                                ],
                              ),
                            ] else if (isDocMandatory) ...[
                              const SizedBox(height: 6),
                              const Text(
                                '⚠️ Cannot proceed without supporting invoice/receipt.',
                                style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text('Confirm & Post Payment'),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final dialogNav = Navigator.of(ctx);

                        // STRICT RULE VALIDATION
                        if (isDocMandatory && voucherFile == null) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade800,
                              content: Text(
                                  'Supporting document is strictly mandatory for "$selectedHead". Please attach a receipt/bill.'),
                            ),
                          );
                          return;
                        }

                        setDS(() => isSubmitting = true);
                        try {
                          final double amount = double.parse(amountCtrl.text.trim());
                          final timestamp = DateTime.now().millisecondsSinceEpoch;
                          final voucherCode = 'EXP-2627-${(timestamp % 100000).toString().padLeft(5, '0')}';

                          String? docUrl;
                          String? docFileName;
                          if (voucherFile != null) {
                            docFileName = voucherFile!.name;
                            docUrl = await _uploadVoucherFile(voucherFile!, voucherCode);
                          }

                          final adminUser = FirebaseAuth.instance.currentUser;
                          await FirebaseFirestore.instance.collection('society_transactions').add({
                            'type': 'EXPENDITURE',
                            'voucherNumber': voucherCode,
                            'accountHead': selectedHead,
                            'category': headInfo?.category ?? 'General',
                            'amount': amount,
                            'paidToOrReceivedFrom': paidToCtrl.text.trim(),
                            'paymentDate': Timestamp.fromDate(paymentDate),
                            'paymentMode': paymentMode,
                            'referenceNumber': refCtrl.text.trim(),
                            'description': descCtrl.text.trim(),
                            'documentUrl': docUrl,
                            'documentFileName': docFileName,
                            'recordedBy': adminUser?.email ?? adminUser?.uid ?? 'Admin',
                            'createdAt': FieldValue.serverTimestamp(),
                          });

                          dialogNav.pop();
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green.shade700,
                              content: Text('Expenditure $voucherCode (₹$amount) recorded successfully!'),
                            ),
                          );
                        } catch (e) {
                          setDS(() => isSubmitting = false);
                          scaffoldMessenger.showSnackBar(
                            SnackBar(content: Text('Failed to save expenditure: $e')),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Dialog: Pay Staff Remuneration (Voucher & Budget Aligned) ─────────────
  void _openPayStaffRemunerationDialog({
    String? preselectedRole,
    String? preselectedMonth,
    Map<String, double>? currentSpentMap,
  }) {
    final formKey = GlobalKey<FormState>();
    final staffRoles = AccountingConfig.staffRemunerationMonthly.keys.toList();
    final months = [
      'April 2026', 'May 2026', 'June 2026', 'July 2026',
      'August 2026', 'September 2026', 'October 2026', 'November 2026',
      'December 2026', 'January 2027', 'February 2027', 'March 2027',
    ];

    String selectedRole = (preselectedRole != null && staffRoles.contains(preselectedRole))
        ? preselectedRole
        : staffRoles.first;
    String selectedMonth = (preselectedMonth != null && months.contains(preselectedMonth))
        ? preselectedMonth
        : _selectedRemunerationMonth;

    final defaultAmt = AccountingConfig.staffRemunerationMonthly[selectedRole] ?? 0.0;
    final amountCtrl = TextEditingController(text: defaultAmt.toStringAsFixed(0));
    final paidToCtrl = TextEditingController(text: selectedRole);
    DateTime paymentDate = DateTime.now();
    String paymentMode = 'Bank Transfer / NEFT / IMPS';
    final refCtrl = TextEditingController();
    final descCtrl = TextEditingController(text: 'Staff Remuneration - $selectedRole ($selectedMonth)');
    PlatformFile? voucherFile;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) {
          final double allocated = AccountingConfig.staffRemunerationMonthly[selectedRole] ?? 0.0;
          final double totalHeadSpent = currentSpentMap?['Staff Remuneration'] ?? 0.0;
          final double totalHeadBudget = AccountingConfig.getBudgetHead('Staff Remuneration')?.yearlyBudget ?? 630468.0;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.badge, color: Colors.indigo, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pay Staff Remuneration',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Staff & Security Payroll Budget (FY 2026-27)',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Role & Month Selector
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedRole,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Staff Position / Role *',
                                prefixIcon: Icon(Icons.engineering),
                                border: OutlineInputBorder(),
                              ),
                              items: staffRoles.map((role) {
                                final rAmt = AccountingConfig.staffRemunerationMonthly[role] ?? 0.0;
                                return DropdownMenuItem(
                                  value: role,
                                  child: Text(
                                    '$role (₹${rAmt.toInt()}/mo)',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDS(() {
                                    selectedRole = val;
                                    final amt = AccountingConfig.staffRemunerationMonthly[val] ?? 0.0;
                                    amountCtrl.text = amt.toStringAsFixed(0);
                                    paidToCtrl.text = val;
                                    descCtrl.text = 'Staff Remuneration - $val ($selectedMonth)';
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedMonth,
                              decoration: const InputDecoration(
                                labelText: 'Salary Month *',
                                prefixIcon: Icon(Icons.calendar_month),
                                border: OutlineInputBorder(),
                              ),
                              items: months
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDS(() {
                                    selectedMonth = val;
                                    descCtrl.text = 'Staff Remuneration - $selectedRole ($selectedMonth)';
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Budget Rate Info Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 18, color: Colors.indigo),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Budget Rate: ${currencyFmt.format(allocated)}/month  |  Annual Head Spent: ${currencyFmt.format(totalHeadSpent)} of ${currencyFmt.format(totalHeadBudget)}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Amount & Payee Name
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Amount (₹) *',
                                prefixIcon: Icon(Icons.currency_rupee),
                                border: OutlineInputBorder(),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Enter amount';
                                final n = double.tryParse(val.trim());
                                if (n == null || n <= 0) return 'Valid amount';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 7,
                            child: TextFormField(
                              controller: paidToCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Staff Name / Payee *',
                                prefixIcon: Icon(Icons.person),
                                border: OutlineInputBorder(),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Payee name required';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Payment Date & Payment Mode
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: paymentDate,
                                  firstDate: DateTime(2025, 4, 1),
                                  lastDate: DateTime(2028, 3, 31),
                                );
                                if (picked != null) {
                                  setDS(() => paymentDate = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Payment Date *',
                                  prefixIcon: Icon(Icons.calendar_today),
                                  border: OutlineInputBorder(),
                                ),
                                child: Text(dateFmt.format(paymentDate), style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: paymentMode,
                              decoration: const InputDecoration(
                                labelText: 'Payment Mode *',
                                prefixIcon: Icon(Icons.payments),
                                border: OutlineInputBorder(),
                              ),
                              items: AccountingConfig.paymentModes
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 12))))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) setDS(() => paymentMode = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Reference Number & Description
                      TextFormField(
                        controller: refCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Cheque No. / Bank UTR / Ref (Optional)',
                          prefixIcon: Icon(Icons.numbers),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes / Remuneration Details',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Mandatory Salary Slip / Voucher Upload
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: voucherFile == null ? Colors.red.shade50 : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: voucherFile == null ? Colors.red.shade300 : Colors.green.shade300,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  voucherFile == null ? Icons.attach_file : Icons.check_circle,
                                  color: voucherFile == null ? Colors.red.shade900 : Colors.green.shade900,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Salary Voucher / Signed Receipt / Slip (MANDATORY) *',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: voucherFile == null ? Colors.red.shade900 : Colors.green.shade900,
                                        ),
                                      ),
                                      Text(
                                        'Attach signed payment voucher, salary slip, or bank debit advice.',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: voucherFile == null ? Colors.indigo : Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                  icon: const Icon(Icons.upload_file, size: 16),
                                  label: Text(voucherFile == null ? 'Attach Slip' : 'Change'),
                                  onPressed: () async {
                                    final file = await pickFile(context: context);
                                    if (file != null) {
                                      setDS(() => voucherFile = file);
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (voucherFile != null) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Selected: ${voucherFile!.name}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                    tooltip: 'Remove',
                                    onPressed: () => setDS(() => voucherFile = null),
                                  ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 6),
                              const Text(
                                '⚠️ Cannot proceed without supporting salary voucher / payment slip.',
                                style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text('Confirm & Post Staff Remuneration'),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        final dialogNav = Navigator.of(ctx);

                        if (voucherFile == null) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade800,
                              content: const Text('Supporting document / voucher is strictly mandatory for Staff Remuneration.'),
                            ),
                          );
                          return;
                        }

                        setDS(() => isSubmitting = true);
                        final double amount = double.parse(amountCtrl.text.trim());
                        final adminUser = FirebaseAuth.instance.currentUser;
                        final recordedBy = adminUser?.email ?? adminUser?.uid ?? 'Admin';

                        final service = StaffRemunerationService();
                        final result = await service.recordStaffPayment(
                          staffRole: selectedRole,
                          payeeName: paidToCtrl.text.trim(),
                          remunerationMonth: selectedMonth,
                          amount: amount,
                          paymentDate: paymentDate,
                          paymentMode: paymentMode,
                          voucherFile: voucherFile!,
                          referenceNumber: refCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                          recordedBy: recordedBy,
                        );

                        if (result.success) {
                          dialogNav.pop();
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green.shade700,
                              content: Text('Staff Remuneration for $selectedRole ($selectedMonth) of ₹$amount posted successfully! Voucher: ${result.voucherNumber}'),
                            ),
                          );
                        } else {
                          setDS(() => isSubmitting = false);
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade800,
                              content: Text(result.error ?? 'Failed to record staff payment'),
                            ),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── UI Component: Staff Remuneration Monthly Status Tracker ───────────────
  Widget _buildStaffRemunerationTrackerCard(
    List<QueryDocumentSnapshot> allDocs,
    Map<String, double> headExpenditures, [
    List<BudgetHead>? activeHeads,
  ]) {
    final service = StaffRemunerationService();
    final statusList = service.computeMonthlyStatus(
      selectedMonth: _selectedRemunerationMonth,
      transactions: allDocs,
    );

    final months = [
      'April 2026', 'May 2026', 'June 2026', 'July 2026',
      'August 2026', 'September 2026', 'October 2026', 'November 2026',
      'December 2026', 'January 2027', 'February 2027', 'March 2027',
    ];

    const double totalMonthlyBudget = 52539.0;
    double disbursedThisMonth = 0.0;
    int paidCount = 0;

    for (final s in statusList) {
      if (s.isPaid) {
        disbursedThisMonth += (s.paidAmount ?? s.budgetAmount);
        paidCount++;
      }
    }

    final double pct = (disbursedThisMonth / totalMonthlyBudget).clamp(0.0, 1.0);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row with Month Selector
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.people_alt, color: Colors.indigo, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Staff Remuneration & Payroll Tracker',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '11 Staff & Security Positions • Monthly Budget ₹52,539',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Month Selector Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRemunerationMonth,
                      icon: const Icon(Icons.calendar_month, size: 18, color: Colors.indigo),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      items: months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedRemunerationMonth = val);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress Bar & Stats
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$_selectedRemunerationMonth Disbursement: $paidCount / 11 Positions Paid',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${currencyFmt.format(disbursedThisMonth)} / ${currencyFmt.format(totalMonthlyBudget)} (${(pct * 100).toStringAsFixed(0)}%)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: paidCount == 11 ? Colors.green.shade800 : Colors.indigo.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        paidCount == 11 ? Colors.green : Colors.indigo.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Itemized Staff Grid / List
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: statusList.map((s) {
                return SizedBox(
                  width: 340,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: s.isPaid ? Colors.green.shade50 : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: s.isPaid ? Colors.green.shade200 : Colors.grey.shade300,
                        width: s.isPaid ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: s.isPaid ? Colors.green.shade100 : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            s.isPaid ? Icons.check_circle : Icons.person_outline,
                            size: 18,
                            color: s.isPaid ? Colors.green.shade800 : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.role,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Budget: ${currencyFmt.format(s.budgetAmount)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                              ),
                              if (s.isPaid && s.payeeName != null) ...[
                                Text(
                                  'Paid to: ${s.payeeName}',
                                  style: TextStyle(fontSize: 10, color: Colors.green.shade900),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (s.isPaid) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Paid',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ),
                          if (s.documentUrl != null && s.documentUrl!.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.description, size: 18, color: Colors.indigo),
                              tooltip: 'View Attached Voucher (${s.documentFileName ?? "Slip"})',
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () => _showDocumentPreview(
                                s.documentUrl!,
                                s.documentFileName ?? 'Salary_Voucher.pdf',
                              ),
                            ),
                          ],
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Pending',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Dialog: Record Other Income ───────────────────────────────────────────
  void _openRecordIncomeDialog() {
    final formKey = GlobalKey<FormState>();
    String selectedHead = AccountingConfig.incomeHeads.first;
    final amountCtrl = TextEditingController();
    final receivedFromCtrl = TextEditingController();
    DateTime receivedDate = DateTime.now();
    String paymentMode = 'Bank Transfer / NEFT / IMPS';
    final refCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    PlatformFile? receiptFile;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_downward, color: Colors.green, size: 24),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Record Society Income / Collection',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text('Tower Rent / CESC Rent / Parking / Other Inflow',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedHead,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Income Head *',
                        prefixIcon: Icon(Icons.savings),
                        border: OutlineInputBorder(),
                      ),
                      items: AccountingConfig.incomeHeads
                          .map((h) => DropdownMenuItem(value: h, child: Text(h)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setDS(() => selectedHead = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: TextFormField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Amount (₹) *',
                              prefixIcon: Icon(Icons.currency_rupee),
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Enter amount';
                              final num = double.tryParse(val.trim());
                              if (num == null || num <= 0) return 'Valid amount';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 7,
                          child: TextFormField(
                            controller: receivedFromCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Received From (Company / Tenant / Resident) *',
                              prefixIcon: Icon(Icons.business),
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: receivedDate,
                                firstDate: DateTime(2025, 4, 1),
                                lastDate: DateTime(2028, 3, 31),
                              );
                              if (picked != null) setDS(() => receivedDate = picked);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Received Date *',
                                prefixIcon: Icon(Icons.calendar_today),
                                border: OutlineInputBorder(),
                              ),
                              child: Text(dateFmt.format(receivedDate)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: paymentMode,
                            decoration: const InputDecoration(
                              labelText: 'Payment Mode *',
                              prefixIcon: Icon(Icons.payments),
                              border: OutlineInputBorder(),
                            ),
                            items: AccountingConfig.paymentModes
                                .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setDS(() => paymentMode = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Transaction Ref / Cheque No. (Optional)',
                        prefixIcon: Icon(Icons.numbers),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description / Month reference',
                        prefixIcon: Icon(Icons.notes),
                        border: OutlineInputBorder(),
                        hintText: 'e.g. Tower rent for month of August 2026',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            receiptFile == null
                                ? 'Upload Deposit Slip / Acknowledgement (Optional)'
                                : 'Selected: ${receiptFile!.name}',
                            style: TextStyle(
                              fontSize: 12,
                              color: receiptFile == null ? Colors.grey.shade700 : Colors.teal,
                              fontWeight: receiptFile == null ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                          icon: const Icon(Icons.attach_file, size: 16),
                          label: Text(receiptFile == null ? 'Attach' : 'Change'),
                          onPressed: () async {
                            final file = await pickFile(context: context);
                            if (file != null) {
                              setDS(() => receiptFile = file);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              icon: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white))
                  : const Icon(Icons.check),
              label: const Text('Record Income'),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      final dialogNav = Navigator.of(ctx);

                      setDS(() => isSubmitting = true);
                      try {
                        final double amount = double.parse(amountCtrl.text.trim());
                        final timestamp = DateTime.now().millisecondsSinceEpoch;
                        final voucherCode = 'INC-2627-${(timestamp % 100000).toString().padLeft(5, '0')}';

                        String? docUrl;
                        String? docFileName;
                        if (receiptFile != null) {
                          docFileName = receiptFile!.name;
                          docUrl = await _uploadVoucherFile(receiptFile!, voucherCode);
                        }

                        final adminUser = FirebaseAuth.instance.currentUser;
                        await FirebaseFirestore.instance.collection('society_transactions').add({
                          'type': 'INCOME',
                          'voucherNumber': voucherCode,
                          'accountHead': selectedHead,
                          'category': 'Income',
                          'amount': amount,
                          'paidToOrReceivedFrom': receivedFromCtrl.text.trim(),
                          'paymentDate': Timestamp.fromDate(receivedDate),
                          'paymentMode': paymentMode,
                          'referenceNumber': refCtrl.text.trim(),
                          'description': descCtrl.text.trim(),
                          'documentUrl': docUrl,
                          'documentFileName': docFileName,
                          'recordedBy': adminUser?.email ?? adminUser?.uid ?? 'Admin',
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                        dialogNav.pop();
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.green.shade700,
                            content: Text('Income $voucherCode (₹$amount) recorded successfully!'),
                          ),
                        );
                      } catch (e) {
                        setDS(() => isSubmitting = false);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('Failed to save income: $e')),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Delete Transaction ────────────────────────────────────────────────────
  Future<void> _deleteTransaction(String docId, Map<String, dynamic> data) async {
    final voucher = data['voucherNumber'] ?? 'Transaction';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 8),
            Text('Void / Delete $voucher?'),
          ],
        ),
        content: Text(
          'Are you sure you want to void $voucher (${data['type']}: ₹${data['amount']})?\n\n'
          'This will permanently remove this entry from the society accounts ledger.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Void Transaction'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final docUrl = data['documentUrl']?.toString();
      if (docUrl != null && docUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(docUrl).delete();
        } catch (_) {}
      }
      await FirebaseFirestore.instance.collection('society_transactions').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$voucher voided successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error voiding transaction: $e')),
        );
      }
    }
  }

  // ─── Export CSV ────────────────────────────────────────────────────────────
  void _exportTransactionsCsv(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No transactions to export.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln(
        'Voucher No,Type,Date,Head of Account,Category,Amount (INR),Paid To / Received From,Payment Mode,Reference No,Description,Supporting Document URL,Recorded By');

    for (final doc in docs) {
      final d = doc.data() as Map<String, dynamic>;
      final voucher = d['voucherNumber'] ?? '';
      final type = d['type'] ?? '';
      final pDate = (d['paymentDate'] as Timestamp?)?.toDate();
      final dateStr = pDate != null ? DateFormat('yyyy-MM-dd').format(pDate) : '';
      final head = '"${(d['accountHead'] ?? '').toString().replaceAll('"', '""')}"';
      final category = '"${(d['category'] ?? '').toString().replaceAll('"', '""')}"';
      final amount = (d['amount'] ?? 0).toString();
      final entity = '"${(d['paidToOrReceivedFrom'] ?? '').toString().replaceAll('"', '""')}"';
      final mode = '"${(d['paymentMode'] ?? '').toString().replaceAll('"', '""')}"';
      final ref = '"${(d['referenceNumber'] ?? '').toString().replaceAll('"', '""')}"';
      final desc = '"${(d['description'] ?? '').toString().replaceAll('"', '""')}"';
      final docUrl = d['documentUrl'] ?? '';
      final recordedBy = d['recordedBy'] ?? '';

      buffer.writeln(
          '$voucher,$type,$dateStr,$head,$category,$amount,$entity,$mode,$ref,$desc,$docUrl,$recordedBy');
    }

    final bytes = utf8.encode(buffer.toString());
    final fileName = 'Ramkrishnapuram_Accounts_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
    downloadBytes(bytes, fileName, mimeType: 'text/csv;charset=utf-8');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transactions exported to CSV successfully!')),
    );
  }

  // ─── Main Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('society_annual_budgets')
          .doc(AccountingConfig.currentFinancialYear)
          .snapshots(),
      builder: (context, annualBudgetSnap) {
        final annualBudgetDoc = annualBudgetSnap.data;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('society_budget_heads').snapshots(),
          builder: (context, budgetSnapshot) {
            final Map<String, BudgetHead> revisedHeadsMap = {};
            for (final doc in budgetSnapshot.data?.docs ?? []) {
              final d = doc.data() as Map<String, dynamic>;
              final name = d['name'] ?? doc.id;
              final yearly = (d['yearlyBudget'] as num?)?.toDouble() ?? 0.0;
              final monthly = (d['monthlyBudget'] as num?)?.toDouble() ?? (yearly / 12);
              revisedHeadsMap[name] = BudgetHead(
                name: name,
                category: d['category'] ?? 'General',
                yearlyBudget: yearly,
                monthlyBudget: monthly,
                isDocRequired: d['isDocRequired'] ?? true,
                description: d['description'] ?? '',
                isRevised: true,
                momDocumentUrl: d['momDocumentUrl'],
                momFileName: d['momFileName'],
                meetingType: d['meetingType'],
                meetingDate: (d['meetingDate'] as Timestamp?)?.toDate(),
                revisionReason: d['revisionReason'],
                revisedBy: d['revisedBy'],
                revisedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
              );
            }

            final activeExpenditureHeads = AccountingConfig.expenditureHeads.map((defaultHead) {
              if (revisedHeadsMap.containsKey(defaultHead.name)) {
                final rev = revisedHeadsMap[defaultHead.name]!;
                return defaultHead.copyWith(
                  yearlyBudget: rev.yearlyBudget,
                  monthlyBudget: rev.monthlyBudget,
                  isRevised: true,
                  momDocumentUrl: rev.momDocumentUrl,
                  momFileName: rev.momFileName,
                  meetingType: rev.meetingType,
                  meetingDate: rev.meetingDate,
                  revisionReason: rev.revisionReason,
                  revisedBy: rev.revisedBy,
                  revisedAt: rev.revisedAt,
                );
              }
              return defaultHead;
            }).toList();

            final totalApprovedAnnualBudget = activeExpenditureHeads.fold(0.0, (acc, h) => acc + h.yearlyBudget);
            final totalApprovedMonthlyBudget = activeExpenditureHeads.fold(0.0, (acc, h) => acc + h.monthlyBudget);

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('society_transactions')
                  .orderBy('paymentDate', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocs = snapshot.data?.docs ?? [];

                // Aggregations
                double totalIncome = 0;
                double totalExpense = 0;
                final Map<String, double> headExpenditures = {};
                final Map<String, double> headIncomes = {};

                for (final doc in allDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final double amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
                  final String type = (data['type'] ?? '').toString().toUpperCase();
                  final String head = data['accountHead'] ?? 'Uncategorized';

                  if (type == 'EXPENDITURE') {
                    totalExpense += amt;
                    headExpenditures[head] = (headExpenditures[head] ?? 0.0) + amt;
                  } else if (type == 'INCOME') {
                    totalIncome += amt;
                    headIncomes[head] = (headIncomes[head] ?? 0.0) + amt;
                  }
                }

                final double netSurplus = totalIncome - totalExpense;

                return Scaffold(
                  body: Column(
                    children: [
                      // Top Financial Summary Bar
                      _buildTopSummaryBar(totalIncome, totalExpense, netSurplus),

                      // Tab Selector
                      Container(
                        color: Colors.white,
                        child: TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          labelColor: Colors.deepPurple,
                          unselectedLabelColor: Colors.grey.shade700,
                          indicatorColor: Colors.deepPurple,
                          indicatorWeight: 3,
                          tabs: const [
                            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
                            Tab(icon: Icon(Icons.arrow_upward, color: Colors.red), text: 'Expenditures'),
                            Tab(icon: Icon(Icons.arrow_downward, color: Colors.green), text: 'Incomes'),
                            Tab(icon: Icon(Icons.pie_chart_outline), text: 'Budget vs Actual (2026-27)'),
                            Tab(icon: Icon(Icons.menu_book), text: 'Daybook & Ledger'),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      // Tab Views
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Tab 1: Overview
                            _buildOverviewTab(
                              allDocs,
                              totalIncome,
                              totalExpense,
                              netSurplus,
                              headExpenditures,
                              activeExpenditureHeads,
                              totalApprovedAnnualBudget,
                              totalApprovedMonthlyBudget,
                              annualBudgetDoc,
                            ),

                            // Tab 2: Expenditures
                            _buildExpendituresTab(allDocs, headExpenditures, activeExpenditureHeads),

                            // Tab 3: Incomes
                            _buildIncomesTab(allDocs, headIncomes),

                            // Tab 4: Budget vs Actual
                            _buildBudgetVsActualTab(
                              headExpenditures,
                              activeExpenditureHeads,
                              totalApprovedAnnualBudget,
                              totalApprovedMonthlyBudget,
                              annualBudgetDoc,
                            ),

                            // Tab 5: Daybook
                            _buildDaybookTab(allDocs),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ─── UI Component: Top Financial Summary ───────────────────────────────────
  Widget _buildTopSummaryBar(double totalIncome, double totalExpense, double netSurplus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade900,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Society Accounts & Treasury',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Ramkrishnapuram Welfare Association (FY ${AccountingConfig.currentFinancialYear})',
                      style: TextStyle(color: Colors.deepPurple.shade100, fontSize: 11)),
                ],
              ),
            ],
          ),
          Wrap(
            spacing: 16,
            children: [
              _buildSummaryPill('Total Collections', currencyFmt.format(totalIncome), Colors.greenAccent),
              _buildSummaryPill('Total Expenditures', currencyFmt.format(totalExpense), Colors.redAccent),
              _buildSummaryPill(
                'Net Balance / Surplus',
                currencyFmt.format(netSurplus),
                netSurplus >= 0 ? Colors.cyanAccent : Colors.orangeAccent,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPill(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 10)),
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ─── UI Tab 1: Overview ────────────────────────────────────────────────────
  Widget _buildOverviewTab(
    List<QueryDocumentSnapshot> allDocs,
    double totalIncome,
    double totalExpense,
    double netSurplus,
    Map<String, double> headExpenditures,
    List<BudgetHead> activeHeads,
    double approvedAnnualBudget,
    double approvedMonthlyBudget,
    DocumentSnapshot? annualBudgetDoc,
  ) {
    final recentDocs = allDocs.take(8).toList();
    final annualBudgetData = annualBudgetDoc?.data() as Map<String, dynamic>?;
    final bool isLocked = annualBudgetData?['isLocked'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action Buttons Bar
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.badge, size: 18),
                label: const Text('Pay Staff Remuneration',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _openPayStaffRemunerationDialog(
                  preselectedMonth: _selectedRemunerationMonth,
                  currentSpentMap: headExpenditures,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: const Text('Record New Expense (Outflow)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _openRecordExpenseDialog(headExpenditures, activeHeads),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.savings_outlined, size: 18),
                label: const Text('Record Other Income (Inflow)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _openRecordIncomeDialog,
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLocked ? Colors.deepPurple.shade700 : Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: Icon(isLocked ? Icons.lock : Icons.upload_file, size: 18),
                label: Text(
                  isLocked
                      ? 'Master Budget (${AccountingConfig.currentFinancialYear}) [Locked]'
                      : 'Upload Annual Budget Plan',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () => _handleAnnualBudgetUpload(
                  annualBudgetDoc,
                  approvedAnnualBudget,
                  approvedMonthlyBudget,
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Export CSV'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: () => _exportTransactionsCsv(allDocs),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // High Priority Budget Warning Alert (if any head exceeded)
          _buildBudgetAlertBanner(headExpenditures, activeHeads),
          const SizedBox(height: 20),

          // Quick Stat Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Projected Budget (2026-27)',
                  currencyFmt.format(approvedAnnualBudget),
                  'Annual expenditure outlay approved',
                  Icons.account_balance_wallet,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Actual Spent Outlay',
                  currencyFmt.format(totalExpense),
                  '${(approvedAnnualBudget > 0 ? ((totalExpense / approvedAnnualBudget) * 100) : 0.0).toStringAsFixed(1)}% of annual budget utilized',
                  Icons.trending_up,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Total Collections',
                  currencyFmt.format(totalIncome),
                  'Maintenance & commercial inflows',
                  Icons.payments,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Recent Activity Table
          const Text('Recent Accounting Vouchers & Ledger Entries',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: recentDocs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No accounting transactions recorded yet.')),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: recentDocs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _buildTransactionListTile(recentDocs[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetAlertBanner(Map<String, double> headExpenditures, List<BudgetHead> activeHeads) {
    final exceededHeads = <String>[];
    for (final head in activeHeads) {
      final spent = headExpenditures[head.name] ?? 0.0;
      if (spent > head.yearlyBudget) {
        exceededHeads.add('${head.name} (Spent: ₹$spent / Budget: ₹${head.yearlyBudget.toInt()})');
      }
    }

    if (exceededHeads.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 12),
            Text(
              'All society expenses are currently within budgeted allocations for FY 2026-27.',
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade300, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Text(
                'CRITICAL: ${exceededHeads.length} Budget Head(s) Exceeded Allocation Limit!',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...exceededHeads.map((h) => Text('• $h', style: const TextStyle(fontSize: 12, color: Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, String subtitle, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── UI Tab 2: Expenditures ────────────────────────────────────────────────
  Widget _buildExpendituresTab(
    List<QueryDocumentSnapshot> allDocs,
    Map<String, double> headExpenditures,
    List<BudgetHead> activeHeads,
  ) {
    final expenseDocs = allDocs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return (data['type'] ?? '').toString().toUpperCase() == 'EXPENDITURE';
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Society Expenditures & Outflows',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.badge, size: 18),
                label: const Text('Pay Staff Remuneration',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => _openPayStaffRemunerationDialog(
                  preselectedMonth: _selectedRemunerationMonth,
                  currentSpentMap: headExpenditures,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Record New Expense'),
                onPressed: () => _openRecordExpenseDialog(headExpenditures, activeHeads),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Monthly Staff Remuneration & Payroll Tracker
          _buildStaffRemunerationTrackerCard(allDocs, headExpenditures, activeHeads),
          const SizedBox(height: 24),

          // All Expenditure Entries
          const Text('All Expenditure Vouchers & Entries',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          expenseDocs.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No expenditures recorded yet.')),
                  ),
                )
              : Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: expenseDocs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _buildTransactionListTile(expenseDocs[i]),
                  ),
                ),
        ],
      ),
    );
  }

  // ─── UI Tab 3: Incomes ─────────────────────────────────────────────────────
  Widget _buildIncomesTab(
    List<QueryDocumentSnapshot> allDocs,
    Map<String, double> headIncomes,
  ) {
    final incomeDocs = allDocs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return (data['type'] ?? '').toString().toUpperCase() == 'INCOME';
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Society Collections & Inflows',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Record Other Income'),
                onPressed: _openRecordIncomeDialog,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: incomeDocs.isEmpty
                ? const Center(child: Text('No income or collections recorded yet.'))
                : Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListView.separated(
                      itemCount: incomeDocs.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) => _buildTransactionListTile(incomeDocs[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── UI Tab 4: Budget vs Actual Analysis ───────────────────────────────────
  Widget _buildBudgetVsActualTab(
    Map<String, double> headExpenditures,
    List<BudgetHead> activeHeads,
    double approvedAnnualBudget,
    double approvedMonthlyBudget,
    DocumentSnapshot? annualBudgetDoc,
  ) {
    final liveSurplus = AccountingConfig.totalProjectedIncomeMonthly - approvedMonthlyBudget;
    final annualBudgetData = annualBudgetDoc?.data() as Map<String, dynamic>?;
    final bool isLocked = annualBudgetData?['isLocked'] == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Budget vs Actual Outlay Tracker (2026-27)',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                      'Annual Approved Outlay: ${currencyFmt.format(approvedAnnualBudget)} (${currencyFmt.format(approvedMonthlyBudget)}/mo) • Net Surplus: ₹${liveSurplus.toStringAsFixed(0)}/mo',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLocked ? Colors.deepPurple.shade700 : Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: Icon(isLocked ? Icons.lock : Icons.upload_file, size: 16),
                label: Text(
                  isLocked ? 'Master Plan (Locked)' : 'Upload Budget Plan',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () => _handleAnnualBudgetUpload(
                  annualBudgetDoc,
                  approvedAnnualBudget,
                  approvedMonthlyBudget,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Master Budget Status Banner
          if (isLocked)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock, color: Colors.deepPurple, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Master Annual Budget Plan (FY ${AccountingConfig.currentFinancialYear}) Locked',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.deepPurple.shade900,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.shade200,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                annualBudgetData?['approvedInMeeting'] ?? 'General Body / AGM',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Master plan is locked for the year. Individual heads can be adjusted below by attaching supporting Minutes of Meeting (MoM).',
                          style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade800),
                        ),
                      ],
                    ),
                  ),
                  if (annualBudgetData?['budgetDocumentUrl'] != null) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: const Text('View Master Document', style: TextStyle(fontSize: 12)),
                      onPressed: () => _showDocumentPreview(
                        annualBudgetData!['budgetDocumentUrl'],
                        annualBudgetData['budgetDocumentName'] ?? 'Annual_Budget_${AccountingConfig.currentFinancialYear}.pdf',
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Annual Budget Plan for FY ${AccountingConfig.currentFinancialYear} has not been officially locked yet. You can register and lock the master budget plan for the year.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('Lock Master Plan', style: TextStyle(fontSize: 12)),
                    onPressed: () => _openUploadAnnualBudgetDialog(approvedAnnualBudget, approvedMonthlyBudget),
                  ),
                ],
              ),
            ),

          // Legend chips
          Wrap(
            spacing: 8,
            children: [
              Chip(
                backgroundColor: Colors.green.shade50,
                avatar: const Icon(Icons.circle, size: 12, color: Colors.green),
                label: const Text('< 80% Spent', style: TextStyle(fontSize: 11)),
              ),
              Chip(
                backgroundColor: Colors.amber.shade50,
                avatar: const Icon(Icons.circle, size: 12, color: Colors.amber),
                label: const Text('80% - 100% Spent', style: TextStyle(fontSize: 11)),
              ),
              Chip(
                backgroundColor: Colors.red.shade50,
                avatar: const Icon(Icons.circle, size: 12, color: Colors.red),
                label: const Text('> 100% Over Budget', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Budget Heads Grid
          LayoutBuilder(
            builder: (ctx, constraints) {
              final crossAxisCount = constraints.maxWidth > 900 ? 2 : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent: 175,
                ),
                itemCount: activeHeads.length,
                itemBuilder: (ctx, i) {
                  final head = activeHeads[i];
                  final double allocated = head.yearlyBudget;
                  final double spent = headExpenditures[head.name] ?? 0.0;
                  final double remaining = allocated - spent;
                  final double pct = allocated > 0 ? (spent / allocated) : 0.0;

                  Color statusColor = Colors.green;
                  String statusLabel = 'On Track';
                  if (pct > 1.0) {
                    statusColor = Colors.red;
                    statusLabel = 'OVER BUDGET';
                  } else if (pct >= 0.8) {
                    statusColor = Colors.amber.shade800;
                    statusLabel = 'Near Limit';
                  }

                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: pct > 1.0 ? Colors.red.shade300 : (head.isRevised ? Colors.blue.shade300 : Colors.grey.shade200),
                        width: pct > 1.0 || head.isRevised ? 1.5 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        head.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (head.isRevised) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.blue.shade200),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.verified, size: 11, color: Colors.blue),
                                            SizedBox(width: 3),
                                            Text('Revised', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (head.isRevised && head.momDocumentUrl != null)
                                IconButton(
                                  icon: const Icon(Icons.description_outlined, size: 20, color: Colors.deepPurple),
                                  tooltip: 'View Minutes of Meeting (MoM) Resolution',
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _showDocumentPreview(head.momDocumentUrl!, head.momFileName ?? 'MoM_Resolution.pdf'),
                                ),
                              if (head.name == 'Staff Remuneration')
                                IconButton(
                                  icon: const Icon(Icons.badge, size: 18, color: Colors.indigo),
                                  tooltip: 'Pay Staff Remuneration',
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _openPayStaffRemunerationDialog(
                                    preselectedMonth: _selectedRemunerationMonth,
                                    currentSpentMap: headExpenditures,
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 17, color: Colors.blueGrey),
                                tooltip: 'Edit Budget Head (MoM Required)',
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                constraints: const BoxConstraints(),
                                onPressed: () => _openEditBudgetHeadDialog(head),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            head.description,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Budget: ${currencyFmt.format(allocated)} (${currencyFmt.format(head.monthlyBudget)}/mo)',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Text('Spent: ${currencyFmt.format(spent)} (${(pct * 100).toStringAsFixed(1)}%)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  )),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct.clamp(0.0, 1.0),
                              backgroundColor: Colors.grey.shade200,
                              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                remaining >= 0
                                    ? 'Remaining: ${currencyFmt.format(remaining)}'
                                    : 'Deficit / Overspent: ${currencyFmt.format(-remaining)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: remaining >= 0 ? Colors.grey.shade700 : Colors.red,
                                ),
                              ),
                              if (head.isRevised)
                                Flexible(
                                  child: Text(
                                    head.meetingType != null ? 'Resolution: ${head.meetingType}' : 'MoM Resolution Attached',
                                    style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.deepPurple),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── UI Tab 5: Daybook & Audit Trail ───────────────────────────────────────
  Widget _buildDaybookTab(List<QueryDocumentSnapshot> allDocs) {
    // Apply Filters
    final filtered = allDocs.where((doc) {
      final d = doc.data() as Map<String, dynamic>;
      final type = (d['type'] ?? '').toString().toUpperCase();
      final head = (d['accountHead'] ?? '').toString();
      final entity = (d['paidToOrReceivedFrom'] ?? '').toString().toLowerCase();
      final voucher = (d['voucherNumber'] ?? '').toString().toLowerCase();
      final ref = (d['referenceNumber'] ?? '').toString().toLowerCase();

      if (_filterType != null && _filterType != 'ALL' && type != _filterType) {
        return false;
      }
      if (_filterHead != null && _filterHead != 'ALL' && head != _filterHead) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!entity.contains(q) && !voucher.contains(q) && !ref.contains(q) && !head.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Filter Bar
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search by voucher, payee, head, ref...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _filterType ?? 'ALL',
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Transactions')),
                      DropdownMenuItem(value: 'EXPENDITURE', child: Text('Expenditures Only')),
                      DropdownMenuItem(value: 'INCOME', child: Text('Incomes Only')),
                    ],
                    onChanged: (val) => setState(() => _filterType = val),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.download),
                    label: const Text('Export Daybook CSV'),
                    onPressed: () => _exportTransactionsCsv(filtered),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Transactions List
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No matching transactions found in Daybook.'))
                : Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx, i) => _buildTransactionListTile(filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Reusable Tile: Transaction Row ────────────────────────────────────────
  Widget _buildTransactionListTile(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final isExpense = (data['type'] ?? '').toString().toUpperCase() == 'EXPENDITURE';
    final pDate = (data['paymentDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final voucher = data['voucherNumber'] ?? 'VOUCHER';
    final head = data['accountHead'] ?? 'General';
    final entity = data['paidToOrReceivedFrom'] ?? 'N/A';
    final mode = data['paymentMode'] ?? 'N/A';
    final ref = data['referenceNumber']?.toString() ?? '';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final docUrl = data['documentUrl']?.toString();
    final docFileName = data['documentFileName']?.toString() ?? 'Document';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: isExpense ? Colors.red.shade100 : Colors.green.shade100,
        child: Icon(
          isExpense ? Icons.arrow_upward : Icons.arrow_downward,
          color: isExpense ? Colors.red.shade800 : Colors.green.shade800,
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              voucher,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              head,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${isExpense ? '-' : '+'} ${currencyFmt.format(amount)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isExpense ? Colors.red.shade800 : Colors.green.shade800,
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${isExpense ? 'Paid To:' : 'From:'} $entity  •  Date: ${dateFmt.format(pDate)}  •  Mode: $mode ${ref.isNotEmpty ? "($ref)" : ""}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (data['staffRole'] != null && data['staffRole'].toString().isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Text(
                            'Staff: ${data['staffRole']}${data['remunerationMonth'] != null ? " (${data['remunerationMonth']})" : ""}',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if ((data['description']?.toString() ?? '').isNotEmpty)
                    Text(
                      'Note: ${data['description']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            if (docUrl != null && docUrl.isNotEmpty) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  foregroundColor: Colors.teal.shade800,
                  side: BorderSide(color: Colors.teal.shade400),
                ),
                icon: const Icon(Icons.receipt_long, size: 14),
                label: const Text('View Bill / Receipt', style: TextStyle(fontSize: 11)),
                onPressed: () => _showDocumentPreview(docUrl, docFileName),
              ),
            ],
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
              tooltip: 'Void / Delete Entry',
              onPressed: () => _deleteTransaction(doc.id, data),
            ),
          ],
        ),
      ),
    );
  }
}

