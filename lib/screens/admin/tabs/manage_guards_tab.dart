import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_feedback.dart';

class ManageGuardsTab extends StatefulWidget {
  const ManageGuardsTab({super.key});

  @override
  State<ManageGuardsTab> createState() => _ManageGuardsTabState();
}

class _ManageGuardsTabState extends State<ManageGuardsTab> {
  String _searchQuery = '';
  String _selectedStatusFilter = 'ALL'; // ALL, ON_DUTY, OFF_DUTY, INACTIVE
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── Add / Edit Guard Dialog ─────────────────────────────────────────────

  Future<void> _showAddOrEditGuardDialog({DocumentSnapshot? existingGuard}) async {
    final isEditing = existingGuard != null;
    final data = isEditing ? (existingGuard.data() as Map<String, dynamic>?) : null;

    final nameCtrl = TextEditingController(text: data?['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(
      text: (data?['phone']?.toString() ?? '').replaceAll('+91', '').trim(),
    );
    final gateCtrl = TextEditingController(text: data?['gate']?.toString() ?? 'Main Gate - Gate 1');
    final agencyCtrl = TextEditingController(text: data?['agency']?.toString() ?? 'Direct Society Staff');
    final emailCtrl = TextEditingController(text: data?['email']?.toString() ?? '');
    final passwordCtrl = TextEditingController(text: isEditing ? '' : 'guard123');

    String selectedShift = data?['shift']?.toString() ?? 'Day Shift (8:00 AM – 8:00 PM)';
    String selectedStatus = data?['status']?.toString() ?? 'ON_DUTY';

    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setDialogState) {
            void updateSuggestedEmail() {
              if (!isEditing && emailCtrl.text.isEmpty && phoneCtrl.text.isNotEmpty) {
                final cleanPhone = phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                if (cleanPhone.length >= 4) {
                  emailCtrl.text = 'guard_$cleanPhone@ramkrishnapuram.com';
                }
              }
            }

            return AppDialog(
              title: isEditing ? 'Edit Security Guard' : 'Add Security Guard',
              subtitle: isEditing
                  ? 'Update guard profile, duty gate or shift timing'
                  : 'Provision a new security guard account with gate access',
              icon: Icons.shield_rounded,
              iconColor: AppColors.primary,
              maxWidth: 540,
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Full Name
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Guard Full Name *',
                          hintText: 'e.g. Ramesh Kumar',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          isDense: true,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter guard name' : null,
                      ),
                      const SizedBox(height: 14),

                      // Mobile Number
                      TextFormField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number *',
                          hintText: '10-digit mobile number',
                          prefixText: '+91 ',
                          prefixIcon: Icon(Icons.phone_outlined),
                          isDense: true,
                        ),
                        onChanged: (_) => setDialogState(updateSuggestedEmail),
                        validator: (v) {
                          if (v == null || v.trim().length != 10) {
                            return 'Enter valid 10-digit mobile number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Assigned Gate
                      DropdownButtonFormField<String>(
                        initialValue: ['Main Gate - Gate 1', 'Back Gate - Gate 2', 'North Gate', 'South Gate', 'Clubhouse Gate']
                                .contains(gateCtrl.text)
                            ? gateCtrl.text
                            : 'Main Gate - Gate 1',
                        decoration: const InputDecoration(
                          labelText: 'Gate Assignment *',
                          prefixIcon: Icon(Icons.door_sliding_outlined),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Main Gate - Gate 1', child: Text('Main Gate - Gate 1')),
                          DropdownMenuItem(value: 'Back Gate - Gate 2', child: Text('Back Gate - Gate 2')),
                          DropdownMenuItem(value: 'North Gate', child: Text('North Gate')),
                          DropdownMenuItem(value: 'South Gate', child: Text('South Gate')),
                          DropdownMenuItem(value: 'Clubhouse Gate', child: Text('Clubhouse Gate')),
                        ],
                        onChanged: (v) {
                          if (v != null) gateCtrl.text = v;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Shift Selection
                      DropdownButtonFormField<String>(
                        initialValue: selectedShift,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Shift *',
                          prefixIcon: Icon(Icons.schedule_rounded),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Day Shift (8:00 AM – 8:00 PM)',
                            child: Text('Day Shift (8:00 AM – 8:00 PM)'),
                          ),
                          DropdownMenuItem(
                            value: 'Night Shift (8:00 PM – 8:00 AM)',
                            child: Text('Night Shift (8:00 PM – 8:00 AM)'),
                          ),
                          DropdownMenuItem(
                            value: 'General Shift (9:00 AM – 6:00 PM)',
                            child: Text('General Shift (9:00 AM – 6:00 PM)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setDialogState(() => selectedShift = v);
                        },
                      ),
                      const SizedBox(height: 14),

                      // Agency / Employer
                      TextFormField(
                        controller: agencyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Security Agency / Employer',
                          hintText: 'e.g. Direct Society Staff, SIS Security',
                          prefixIcon: Icon(Icons.business_outlined),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Duty Status
                      DropdownButtonFormField<String>(
                        initialValue: selectedStatus,
                        decoration: const InputDecoration(
                          labelText: 'Duty Status *',
                          prefixIcon: Icon(Icons.shield_outlined),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ON_DUTY', child: Text('ON DUTY (Active at Gate)')),
                          DropdownMenuItem(value: 'OFF_DUTY', child: Text('OFF DUTY (Resting)')),
                          DropdownMenuItem(value: 'INACTIVE', child: Text('INACTIVE (Relieved / On Leave)')),
                        ],
                        onChanged: (v) {
                          if (v != null) setDialogState(() => selectedStatus = v);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Account Credentials Section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cardSurfaceSecondary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.primary),
                                SizedBox(width: 6),
                                Text(
                                  'Gate App Login Credentials',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: emailCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Login Email / Username *',
                                hintText: 'guard_phone@ramkrishnapuram.com',
                                isDense: true,
                                fillColor: Colors.white,
                                filled: true,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter login email' : null,
                            ),
                            if (!isEditing) ...[
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: passwordCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Initial Password *',
                                  hintText: 'Minimum 6 characters',
                                  isDense: true,
                                  fillColor: Colors.white,
                                  filled: true,
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);

                          try {
                            final name = nameCtrl.text.trim();
                            final phone = '+91${phoneCtrl.text.trim()}';
                            final gate = gateCtrl.text.trim();
                            final agency = agencyCtrl.text.trim();
                            final authEmail = emailCtrl.text.trim().toLowerCase();
                            final password = passwordCtrl.text.trim();

                            if (isEditing) {
                              await existingGuard.reference.update({
                                'name': name,
                                'phone': phone,
                                'gate': gate,
                                'shift': selectedShift,
                                'agency': agency,
                                'email': authEmail,
                                'status': selectedStatus,
                                'updatedAt': FieldValue.serverTimestamp(),
                              });
                            } else {
                              // Create Auth account using temporary secondary app
                              String? newUid;
                              FirebaseApp? tempAuthApp;
                              try {
                                final appName = 'GuardAuth_${DateTime.now().microsecondsSinceEpoch}';
                                tempAuthApp = await Firebase.initializeApp(
                                  name: appName,
                                  options: Firebase.app().options,
                                );
                                final tempAuth = FirebaseAuth.instanceFor(app: tempAuthApp);
                                final userCred = await tempAuth.createUserWithEmailAndPassword(
                                  email: authEmail,
                                  password: password,
                                );
                                newUid = userCred.user?.uid;
                              } on FirebaseAuthException catch (authErr) {
                                if (authErr.code == 'email-already-in-use') {
                                  // User already exists in Auth; proceed to set profile
                                } else {
                                  rethrow;
                                }
                              } finally {
                                if (tempAuthApp != null) {
                                  try {
                                    await tempAuthApp.delete();
                                  } catch (_) {}
                                }
                              }

                              final guardData = <String, dynamic>{
                                'name': name,
                                'phone': phone,
                                'gate': gate,
                                'shift': selectedShift,
                                'agency': agency.isEmpty ? 'Direct Society Staff' : agency,
                                'email': authEmail,
                                'username': authEmail,
                                'role': 'GUARD',
                                'status': selectedStatus,
                                'createdAt': FieldValue.serverTimestamp(),
                                'updatedAt': FieldValue.serverTimestamp(),
                              };

                              if (newUid != null) {
                                guardData['uid'] = newUid;
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(newUid)
                                    .set(guardData, SetOptions(merge: true));
                              } else {
                                await FirebaseFirestore.instance.collection('users').add(guardData);
                              }
                            }

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                            }
                            if (mounted) {
                              AppFeedback.showSuccess(
                                context,
                                isEditing ? 'Guard details updated successfully.' : 'Security guard added successfully.',
                              );
                            }
                          } catch (e) {
                            if (dialogCtx.mounted) {
                              setDialogState(() => isSaving = false);
                            }
                            if (mounted) {
                              AppFeedback.showError(context, 'Error saving guard: $e');
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(isEditing ? 'Save Changes' : 'Add Guard'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── Toggle Duty Status ──────────────────────────────────────────────────

  Future<void> _toggleGuardDutyStatus(DocumentSnapshot guardDoc, String currentStatus) async {
    final newStatus = currentStatus == 'ON_DUTY' ? 'OFF_DUTY' : 'ON_DUTY';
    try {
      await guardDoc.reference.update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        AppFeedback.showSuccess(
          context,
          newStatus == 'ON_DUTY' ? 'Guard marked ON DUTY.' : 'Guard marked OFF DUTY.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Failed to update duty status: $e');
      }
    }
  }

  // ─── Delete Guard ────────────────────────────────────────────────────────

  Future<void> _confirmDeleteGuard(DocumentSnapshot guardDoc, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Remove Guard'),
          ],
        ),
        content: Text('Are you sure you want to remove guard "$name"? This will revoke their security gate access.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove Guard'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await guardDoc.reference.delete();
        if (mounted) {
          AppFeedback.showSuccess(context, 'Guard removed from society roster.');
        }
      } catch (e) {
        if (mounted) {
          AppFeedback.showError(context, 'Error removing guard: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'GUARD')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error loading guards: ${snap.error}', style: const TextStyle(color: AppColors.error)));
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data?.docs ?? [];
        final totalGuards = docs.length;
        final onDutyCount = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return (data['status'] ?? 'ON_DUTY') == 'ON_DUTY';
        }).length;
        final dayShiftCount = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return (data['shift'] ?? '').toString().toLowerCase().contains('day');
        }).length;
        final nightShiftCount = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return (data['shift'] ?? '').toString().toLowerCase().contains('night');
        }).length;

        // Apply search and status filter
        final filteredDocs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final name = (data['name'] ?? '').toString().toLowerCase();
          final phone = (data['phone'] ?? '').toString().toLowerCase();
          final gate = (data['gate'] ?? '').toString().toLowerCase();
          final status = (data['status'] ?? 'ON_DUTY').toString().toUpperCase();

          if (_selectedStatusFilter != 'ALL' && status != _selectedStatusFilter) {
            return false;
          }
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            return name.contains(q) || phone.contains(q) || gate.contains(q);
          }
          return true;
        }).toList();

        return Column(
          children: [
            // ─── Top Stats Row ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryPill(
                      label: 'Total Roster',
                      value: '$totalGuards',
                      icon: Icons.shield_rounded,
                      color: AppColors.primary,
                      bgColor: AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryPill(
                      label: 'On Duty Now',
                      value: '$onDutyCount',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success,
                      bgColor: AppColors.successSurface,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryPill(
                      label: 'Day Shift',
                      value: '$dayShiftCount',
                      icon: Icons.wb_sunny_rounded,
                      color: AppColors.warning,
                      bgColor: AppColors.warningSurface,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryPill(
                      label: 'Night Shift',
                      value: '$nightShiftCount',
                      icon: Icons.nightlight_round,
                      color: AppColors.info,
                      bgColor: AppColors.infoSurface,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            // ─── Search & Action Controls ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppColors.background,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search guards by name, phone, or gate...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Filter Chips
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ALL', label: Text('All')),
                      ButtonSegment(value: 'ON_DUTY', label: Text('On Duty')),
                      ButtonSegment(value: 'OFF_DUTY', label: Text('Off Duty')),
                    ],
                    selected: {_selectedStatusFilter},
                    onSelectionChanged: (val) {
                      setState(() => _selectedStatusFilter = val.first);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add Guard', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    onPressed: () => _showAddOrEditGuardDialog(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            // ─── Guard Roster Cards ────────────────────────────────────────
            Expanded(
              child: filteredDocs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shield_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No guards matching "$_searchQuery"'
                                : 'No security guards added yet',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Click "Add Guard" above to register security personnel for gate monitoring.',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredDocs.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final doc = filteredDocs[i];
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data['name'] ?? 'Security Guard';
                        final phone = data['phone'] ?? 'No Phone';
                        final gate = data['gate'] ?? 'Main Gate';
                        final shift = data['shift'] ?? 'Day Shift';
                        final agency = data['agency'] ?? 'Direct Society Staff';
                        final email = data['email'] ?? '';
                        final status = (data['status'] ?? 'ON_DUTY').toString().toUpperCase();
                        final isOnDuty = status == 'ON_DUTY';

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isOnDuty ? AppColors.successBorder : AppColors.border,
                              width: isOnDuty ? 1.2 : 0.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Avatar / Badge
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: isOnDuty ? AppColors.successSurface : AppColors.cardSurfaceSecondary,
                                child: Icon(
                                  Icons.security_rounded,
                                  color: isOnDuty ? AppColors.success : AppColors.textMuted,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Info Column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isOnDuty ? AppColors.successSurface : AppColors.cardSurfaceSecondary,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isOnDuty ? AppColors.successBorder : AppColors.border,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: isOnDuty ? AppColors.success : AppColors.textMuted,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                isOnDuty ? 'ON DUTY' : 'OFF DUTY',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isOnDuty ? AppColors.success : AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 4,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.phone_outlined, size: 14, color: AppColors.textMuted),
                                            const SizedBox(width: 4),
                                            Text(phone, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.door_sliding_outlined, size: 14, color: AppColors.textMuted),
                                            const SizedBox(width: 4),
                                            Text(gate, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textMuted),
                                            const SizedBox(width: 4),
                                            Text(shift, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                          ],
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.business_outlined, size: 14, color: AppColors.textMuted),
                                            const SizedBox(width: 4),
                                            Text(agency, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (email.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Login ID: $email',
                                        style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ],
                                ),
                              ),

                              // Actions
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                      side: BorderSide(color: isOnDuty ? AppColors.warning : AppColors.success),
                                    ),
                                    onPressed: () => _toggleGuardDutyStatus(doc, status),
                                    child: Text(
                                      isOnDuty ? 'Mark Off Duty' : 'Mark On Duty',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isOnDuty ? AppColors.warning : AppColors.success,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                                    tooltip: 'Actions',
                                    onSelected: (action) {
                                      if (action == 'edit') {
                                        _showAddOrEditGuardDialog(existingGuard: doc);
                                      } else if (action == 'delete') {
                                        _confirmDeleteGuard(doc, name);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                                            SizedBox(width: 8),
                                            Text('Edit Guard Details'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                            SizedBox(width: 8),
                                            Text('Remove Guard', style: TextStyle(color: AppColors.error)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryPill({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
