import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/visitor_pass_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_feedback.dart';

class GuardDashboard extends StatefulWidget {
  const GuardDashboard({super.key});

  @override
  State<GuardDashboard> createState() => _GuardDashboardState();
}

class _GuardDashboardState extends State<GuardDashboard> {
  int _currentTab = 0;

  // Passcode verification state
  final _codeController = TextEditingController();
  bool _isVerifyingPass = false;
  bool _isCheckingIn = false;
  Map<String, dynamic>? _verifiedVisitorData;
  String? _verifiedVisitorDocId;

  // Walk-in visitor state
  final _walkInNameCtrl = TextEditingController();
  final _walkInPhoneCtrl = TextEditingController();
  final _walkInFlatCtrl = TextEditingController();
  final _walkInVehicleCtrl = TextEditingController();
  String _walkInPurpose = 'Guest / Personal';
  bool _isLoggingWalkIn = false;

  // Campus search
  String _campusSearchQuery = '';
  final _campusSearchCtrl = TextEditingController();

  // Parcel state
  final _parcelFlatCtrl = TextEditingController();
  final _parcelCountCtrl = TextEditingController(text: '1');
  final _parcelRemarksCtrl = TextEditingController();
  String _parcelProvider = 'Amazon';
  bool _isLoggingParcel = false;

  // Directory search
  String _directorySearchQuery = '';
  final _directorySearchCtrl = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _walkInNameCtrl.dispose();
    _walkInPhoneCtrl.dispose();
    _walkInFlatCtrl.dispose();
    _walkInVehicleCtrl.dispose();
    _campusSearchCtrl.dispose();
    _parcelFlatCtrl.dispose();
    _parcelCountCtrl.dispose();
    _parcelRemarksCtrl.dispose();
    _directorySearchCtrl.dispose();
    super.dispose();
  }

  // ─── Guard Profile & Context Helper ────────────────────────────────────────

  String get _currentGuardUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  // ─── Passcode Verification & Check-in ──────────────────────────────────────

  Future<void> _verifyPass() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      AppFeedback.showError(context, 'Please enter a valid 6-digit gate passcode.');
      return;
    }

    setState(() {
      _isVerifyingPass = true;
      _verifiedVisitorData = null;
      _verifiedVisitorDocId = null;
    });

    try {
      final doc = await VisitorPassService.verifyPassCode(code);
      if (doc == null) {
        if (mounted) {
          AppFeedback.showError(context, 'Invalid code or pass already checked in.');
        }
      } else {
        if (mounted) {
          setState(() {
            _verifiedVisitorDocId = doc.id;
            _verifiedVisitorData = doc.data();
          });
          AppFeedback.showSuccess(context, 'Valid pass verified! Review details below.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error verifying passcode: $e');
      }
    } finally {
      if (mounted) setState(() => _isVerifyingPass = false);
    }
  }

  Future<void> _confirmPassCheckIn(String guardName, String gateName) async {
    if (_verifiedVisitorDocId == null) return;
    setState(() => _isCheckingIn = true);

    try {
      await VisitorPassService.checkInVisitor(
        visitorDocId: _verifiedVisitorDocId!,
        guardUid: _currentGuardUid,
        guardName: guardName,
        gateName: gateName,
      );

      if (mounted) {
        AppFeedback.showSuccess(context, 'Visitor checked in successfully!');
        setState(() {
          _verifiedVisitorData = null;
          _verifiedVisitorDocId = null;
          _codeController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error checking in visitor: $e');
      }
    } finally {
      if (mounted) setState(() => _isCheckingIn = false);
    }
  }

  // ─── Walk-In Visitor Registration ──────────────────────────────────────────

  Future<void> _submitWalkIn(String guardName, String gateName) async {
    final name = _walkInNameCtrl.text.trim();
    final phone = _walkInPhoneCtrl.text.trim();
    final flat = _walkInFlatCtrl.text.trim();

    if (name.isEmpty) {
      AppFeedback.showError(context, 'Please enter visitor name.');
      return;
    }
    if (phone.length < 10) {
      AppFeedback.showError(context, 'Please enter a valid 10-digit mobile number.');
      return;
    }
    if (flat.isEmpty) {
      AppFeedback.showError(context, 'Please enter or select visiting flat number.');
      return;
    }

    setState(() => _isLoggingWalkIn = true);

    try {
      await VisitorPassService.logWalkInVisitor(
        visitorName: name,
        phone: phone,
        flatNumber: flat,
        purpose: _walkInPurpose,
        vehicleNumber: _walkInVehicleCtrl.text,
        guardUid: _currentGuardUid,
        guardName: guardName,
        gateName: gateName,
      );

      if (mounted) {
        AppFeedback.showSuccess(context, 'Walk-in visitor $name checked in at $flat.');
        _walkInNameCtrl.clear();
        _walkInPhoneCtrl.clear();
        _walkInFlatCtrl.clear();
        _walkInVehicleCtrl.clear();
        setState(() => _currentTab = 2); // Switch to In-Campus view
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Failed to log walk-in visitor: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoggingWalkIn = false);
    }
  }

  // ─── Emergency SOS Broadcast ───────────────────────────────────────────────

  void _showEmergencyDialog(String guardName, String gateName) {
    String selectedType = 'Security Disturbance';
    final notesCtrl = TextEditingController();
    bool isBroadcasting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (sheetCtx, setDialogState) {
          return AppDialog(
            title: 'EMERGENCY SOS ALERT',
            subtitle: 'Broadcast real-time critical security alert to All Residents & Admins',
            icon: Icons.warning_rounded,
            iconColor: AppColors.error,
            maxWidth: 480,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.errorBorder),
                  ),
                  child: const Text(
                    'Triggering this alert will immediately notify all residents and society management. Use strictly for genuine security/safety incidents.',
                    style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Emergency Nature *',
                    prefixIcon: Icon(Icons.emergency_rounded, color: AppColors.error),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Fire Emergency', child: Text('🔥 Fire Emergency')),
                    DropdownMenuItem(value: 'Medical Emergency', child: Text('🚑 Medical Emergency')),
                    DropdownMenuItem(value: 'Security Disturbance', child: Text('🚨 Security Disturbance / Intrusion')),
                    DropdownMenuItem(value: 'Lift Entrapment', child: Text('🛗 Lift Entrapment / Power Failure')),
                    DropdownMenuItem(value: 'Water / Infrastructure', child: Text('💧 Water Pipeline / Structural Leak')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedType = v);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Incident Location / Brief Details',
                    hintText: 'e.g. Near Block B ground parking or Lift 2',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isBroadcasting ? null : () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                icon: isBroadcasting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.broadcast_on_personal_rounded, size: 18),
                label: const Text('BROADCAST SOS ALERT'),
                onPressed: isBroadcasting
                    ? null
                    : () async {
                        setDialogState(() => isBroadcasting = true);
                        try {
                          await VisitorPassService.triggerEmergencyAlert(
                            emergencyType: selectedType,
                            guardName: guardName,
                            gateName: gateName,
                            details: notesCtrl.text,
                          );
                          if (dialogCtx.mounted) {
                            Navigator.pop(dialogCtx);
                          }
                          if (mounted) {
                            AppFeedback.showSuccess(context, 'Emergency alert broadcasted to society members.');
                          }
                        } catch (e) {
                          if (dialogCtx.mounted) {
                            setDialogState(() => isBroadcasting = false);
                          }
                          if (mounted) {
                            AppFeedback.showError(context, 'Failed to trigger SOS: $e');
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Log Parcel Dialog ─────────────────────────────────────────────────────

  void _showLogParcelDialog(String guardName, String gateName) {
    _parcelFlatCtrl.clear();
    _parcelCountCtrl.text = '1';
    _parcelRemarksCtrl.clear();
    _parcelProvider = 'Amazon';

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (sheetCtx, setDialogState) => AppDialog(
          title: 'Receive Parcel at Gate',
          subtitle: 'Log incoming courier or delivery held at gate security',
          icon: Icons.inventory_2_rounded,
          iconColor: AppColors.primary,
          maxWidth: 480,
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _parcelFlatCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Flat Number *',
                    hintText: 'e.g. B-312',
                    prefixIcon: Icon(Icons.apartment_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter flat number' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _parcelProvider,
                  decoration: const InputDecoration(
                    labelText: 'Delivery Provider *',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Amazon', child: Text('Amazon')),
                    DropdownMenuItem(value: 'Flipkart', child: Text('Flipkart')),
                    DropdownMenuItem(value: 'Swiggy Instamart', child: Text('Swiggy Instamart')),
                    DropdownMenuItem(value: 'Zomato / Blinkit', child: Text('Zomato / Blinkit')),
                    DropdownMenuItem(value: 'Blue Dart / Courier', child: Text('Blue Dart / Courier')),
                    DropdownMenuItem(value: 'India Post', child: Text('India Post')),
                    DropdownMenuItem(value: 'Other Delivery', child: Text('Other Delivery')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => _parcelProvider = v);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _parcelCountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Packet Count *',
                    prefixIcon: Icon(Icons.numbers_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter count' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _parcelRemarksCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Remarks / Tracking (Optional)',
                    hintText: 'e.g. Large box left on rack 3',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isLoggingParcel ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: _isLoggingParcel
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => _isLoggingParcel = true);

                      try {
                        await VisitorPassService.logParcel(
                          flatNumber: _parcelFlatCtrl.text,
                          deliveryProvider: _parcelProvider,
                          packetCount: int.tryParse(_parcelCountCtrl.text) ?? 1,
                          remarks: _parcelRemarksCtrl.text,
                          guardUid: _currentGuardUid,
                          guardName: guardName,
                          gateName: gateName,
                        );

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          AppFeedback.showSuccess(context, 'Parcel logged and resident notified!');
                        }
                      } catch (e) {
                        if (dialogCtx.mounted) {
                          setDialogState(() => _isLoggingParcel = false);
                        }
                        if (mounted) {
                          AppFeedback.showError(context, 'Failed to log parcel: $e');
                        }
                      }
                    },
              child: _isLoggingParcel
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save & Alert Resident'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Main Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(_currentGuardUid).snapshots(),
      builder: (_, snap) {
        final guardData = (snap.data?.data() as Map<String, dynamic>?) ?? {};
        final guardName = guardData['name']?.toString() ?? 'Security Guard';
        final gateName = guardData['gate']?.toString() ?? 'Main Gate - Gate 1';
        final shift = guardData['shift']?.toString() ?? 'Day Shift';
        final status = (guardData['status']?.toString() ?? 'ON_DUTY').toUpperCase();
        final isOnDuty = status == 'ON_DUTY';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            elevation: 1,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield_rounded, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guardName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '$gateName • $shift',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Duty Status Pill Toggle
              InkWell(
                onTap: () async {
                  final newStatus = isOnDuty ? 'OFF_DUTY' : 'ON_DUTY';
                  await snap.data?.reference.update({
                    'status': newStatus,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  if (!context.mounted) return;
                  AppFeedback.showSuccess(
                    context,
                    newStatus == 'ON_DUTY' ? 'You are marked ON DUTY.' : 'You are marked OFF DUTY.',
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOnDuty ? AppColors.success : AppColors.cardSurfaceSecondary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnDuty ? Colors.white : AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnDuty ? 'ON DUTY' : 'OFF DUTY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isOnDuty ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Emergency SOS Button
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text('SOS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                tooltip: 'Emergency SOS Alert',
                onPressed: () => _showEmergencyDialog(guardName, gateName),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, size: 20, color: Colors.white),
                tooltip: 'Log out',
                onPressed: () => FirebaseAuth.instance.signOut(),
              ),
            ],
          ),
          body: IndexedStack(
            index: _currentTab,
            children: [
              _buildVerifyPassTab(guardName, gateName),
              _buildWalkInTab(guardName, gateName),
              _buildInCampusTab(),
              _buildParcelsTab(guardName, gateName),
              _buildDirectoryTab(),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border, width: 0.9)),
            ),
            child: NavigationBar(
              selectedIndex: _currentTab,
              height: 64,
              backgroundColor: Colors.white,
              indicatorColor: AppColors.primaryLight,
              onDestinationSelected: (index) => setState(() => _currentTab = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner_rounded, size: 20),
                  label: 'Verify Pass',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_add_alt_1_rounded, size: 20),
                  label: 'Walk-In',
                ),
                NavigationDestination(
                  icon: Icon(Icons.badge_rounded, size: 20),
                  label: 'In-Campus',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_rounded, size: 20),
                  label: 'Parcels',
                ),
                NavigationDestination(
                  icon: Icon(Icons.contact_phone_rounded, size: 20),
                  label: 'Directory',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── TAB 0: Verify Pass ────────────────────────────────────────────────────

  Widget _buildVerifyPassTab(String guardName, String gateName) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.qr_code_2_rounded, size: 48, color: AppColors.primary),
                    const SizedBox(height: 8),
                    const Text(
                      'Resident Gate Pass Verification',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Enter the 6-digit OTP code shared by visiting guest',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 8, color: AppColors.primaryDark),
                      decoration: InputDecoration(
                        hintText: '••••••',
                        hintStyle: const TextStyle(fontSize: 28, letterSpacing: 8, color: AppColors.textMuted),
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.cardSurfaceSecondary,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      ),
                      onChanged: (v) {
                        if (v.trim().length == 6) {
                          _verifyPass();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: _isVerifyingPass
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Verify Passcode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        onPressed: _isVerifyingPass ? null : _verifyPass,
                      ),
                    ),
                  ],
                ),
              ),
              if (_verifiedVisitorData != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.successBorder, width: 1.5),
                    boxShadow: [
                      BoxShadow(color: AppColors.success.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.verified_rounded, color: AppColors.success, size: 22),
                          SizedBox(width: 8),
                          Text('Passcode Verified • Ready for Entry', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 14)),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildDetailRow('Visitor Name', _verifiedVisitorData!['visitorName']?.toString() ?? 'Guest'),
                      _buildDetailRow('Visiting Flat', _verifiedVisitorData!['flatNumber']?.toString() ?? 'Unknown'),
                      _buildDetailRow('Purpose', _verifiedVisitorData!['purpose']?.toString() ?? 'Visit'),
                      if ((_verifiedVisitorData!['phone']?.toString() ?? '').isNotEmpty)
                        _buildDetailRow('Mobile', _verifiedVisitorData!['phone'].toString()),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: _isCheckingIn
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.login_rounded, size: 22),
                          label: const Text('Confirm Entry & Check-In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          onPressed: _isCheckingIn ? null : () => _confirmPassCheckIn(guardName, gateName),
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
    );
  }

  // ─── TAB 1: Walk-In Entry ──────────────────────────────────────────────────

  Widget _buildWalkInTab(String guardName, String gateName) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 24),
                    SizedBox(width: 10),
                    Text('Direct / Walk-In Gate Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Log unscheduled visitors, delivery boys, cabs, or helpers', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const Divider(height: 24),

                // Visitor Name
                TextFormField(
                  controller: _walkInNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Visitor Full Name *',
                    hintText: 'e.g. Rahul Sharma',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),

                // Mobile Number
                TextFormField(
                  controller: _walkInPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Visitor Mobile Number *',
                    hintText: '10-digit mobile number',
                    prefixText: '+91 ',
                    prefixIcon: Icon(Icons.phone_outlined),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),

                // Visiting Flat
                TextFormField(
                  controller: _walkInFlatCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Visiting Flat *',
                    hintText: 'e.g. B-312 or A-101',
                    prefixIcon: Icon(Icons.apartment_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),

                // Purpose Selection Chips
                const Text('Purpose of Visit *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    'Delivery / Courier',
                    'Cab / Taxi',
                    'Guest / Personal',
                    'Maid / Domestic',
                    'Maintenance / Repair',
                    'Other',
                  ].map((p) {
                    final isSel = _walkInPurpose == p;
                    return ChoiceChip(
                      label: Text(p, style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                      selected: isSel,
                      selectedColor: AppColors.primaryLight,
                      onSelected: (val) {
                        if (val) setState(() => _walkInPurpose = p);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Vehicle Number
                TextFormField(
                  controller: _walkInVehicleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Number (Optional)',
                    hintText: 'e.g. DL 01 AB 1234',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 24),

                // Submit Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isLoggingWalkIn
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle_rounded, size: 20),
                  label: const Text('Check In & Notify Resident', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: _isLoggingWalkIn ? null : () => _submitWalkIn(guardName, gateName),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── TAB 2: In-Campus Active Visitors Log ──────────────────────────────────

  Widget _buildInCampusTab() {
    return Column(
      children: [
        // Search & Count Bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _campusSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search active visitors by flat or name...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _campusSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _campusSearchCtrl.clear();
                              setState(() => _campusSearchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: AppColors.cardSurfaceSecondary,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  onChanged: (v) => setState(() => _campusSearchQuery = v.trim().toLowerCase()),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        // Live Active Visitors List
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: VisitorPassService.getActiveVisitorsStream(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error loading campus log: ${snap.error}', style: const TextStyle(color: AppColors.error)));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allDocs = snap.data?.docs ?? [];
              final docs = allDocs.where((d) {
                if (_campusSearchQuery.isEmpty) return true;
                final data = d.data();
                final name = (data['visitorName'] ?? '').toString().toLowerCase();
                final flat = (data['flatNumber'] ?? '').toString().toLowerCase();
                return name.contains(_campusSearchQuery) || flat.contains(_campusSearchQuery);
              }).toList();

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.door_front_door_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text(
                        _campusSearchQuery.isNotEmpty
                            ? 'No active visitors matching "$_campusSearchQuery"'
                            : 'No visitors currently inside campus',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      const Text('When guests check in at the gate, they will appear here.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final name = data['visitorName'] ?? 'Visitor';
                  final phone = data['phone'] ?? '';
                  final flat = data['flatNumber'] ?? 'General';
                  final purpose = data['purpose'] ?? 'Guest';
                  final vehicle = data['vehicleNumber'] ?? '';
                  final entryTime = (data['entryTime'] as Timestamp?)?.toDate();
                  final entryStr = entryTime != null ? DateFormat('hh:mm a').format(entryTime) : 'Just now';

                  String durationStr = '';
                  if (entryTime != null) {
                    final diff = DateTime.now().difference(entryTime);
                    if (diff.inMinutes < 60) {
                      durationStr = '${diff.inMinutes}m inside';
                    } else {
                      durationStr = '${diff.inHours}h ${diff.inMinutes % 60}m inside';
                    }
                  }

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primaryLight,
                          child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primarySurface,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.primaryBorder),
                                    ),
                                    child: Text('Flat $flat', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                  ),
                                  _buildApprovalBadge(data['approvalStatus']?.toString()),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 10,
                                children: [
                                  Text(purpose, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  if (phone.isNotEmpty) Text('•  $phone', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                  if (vehicle.isNotEmpty) Text('•  🚗 $vehicle', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('In at $entryStr ${durationStr.isNotEmpty ? '($durationStr)' : ''}', style: const TextStyle(fontSize: 11, color: AppColors.warningDark, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warningSurface,
                            foregroundColor: AppColors.warningDark,
                            side: const BorderSide(color: AppColors.warningBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text('Mark Exit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () async {
                            await VisitorPassService.checkOutVisitor(
                              visitorDocId: doc.id,
                              guardUid: _currentGuardUid,
                            );
                            if (context.mounted) {
                              AppFeedback.showSuccess(context, '$name checked out.');
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildApprovalBadge(String? status) {
    if (status == 'APPROVED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 12, color: Colors.green.shade700),
            const SizedBox(width: 4),
            Text(
              'RESIDENT APPROVED',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
            ),
          ],
        ),
      );
    } else if (status == 'DENIED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel_rounded, size: 12, color: Colors.red.shade700),
            const SizedBox(width: 4),
            Text(
              'DENIED BY RESIDENT',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 12, color: Colors.amber.shade800),
            const SizedBox(width: 4),
            Text(
              'AWAITING RESIDENT',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.brown.shade700),
            ),
          ],
        ),
      );
    }
  }

  // ─── TAB 3: Deliveries & Gate Parcels ──────────────────────────────────────

  Widget _buildParcelsTab(String guardName, String gateName) {
    return Column(
      children: [
        // Action Bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Gate Parcel Holding', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary)),
                  Text('Parcels received and waiting for resident pickup', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_box_rounded, size: 18),
                label: const Text('Log Parcel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => _showLogParcelDialog(guardName, gateName),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        // Live Stream of Parcels
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: VisitorPassService.getPendingParcelsStream(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error loading parcels: ${snap.error}', style: const TextStyle(color: AppColors.error)));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      const Text('No parcels currently held at the gate', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      const Text('When couriers leave packages at security, log them here.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final flat = data['flatNumber'] ?? 'Unknown';
                  final provider = data['deliveryProvider'] ?? 'Courier';
                  final count = data['packetCount'] ?? 1;
                  final remarks = data['remarks'] ?? '';
                  final time = (data['receivedAt'] as Timestamp?)?.toDate();
                  final timeStr = time != null ? DateFormat('dd MMM, hh:mm a').format(time) : 'Recent';

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.local_shipping_rounded, color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primarySurface,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.primaryBorder),
                                    ),
                                    child: Text(
                                      'Flat $flat',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$count Packet(s) • $provider',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('Received at $timeStr', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              if (remarks.isNotEmpty)
                                Text('Note: $remarks', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Hand Over', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () async {
                            await VisitorPassService.markParcelCollected(
                              parcelDocId: doc.id,
                              guardUid: _currentGuardUid,
                            );
                            if (context.mounted) {
                              AppFeedback.showSuccess(context, 'Parcel handed over to resident of $flat.');
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── TAB 4: Intercom Directory & Emergency Contacts ────────────────────────

  Widget _buildDirectoryTab() {
    return Column(
      children: [
        // Directory Search
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: TextField(
            controller: _directorySearchCtrl,
            decoration: InputDecoration(
              hintText: 'Search resident directory by flat (e.g. B-312) or name...',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _directorySearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _directorySearchCtrl.clear();
                        setState(() => _directorySearchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true,
              fillColor: AppColors.cardSurfaceSecondary,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            ),
            onChanged: (v) => setState(() => _directorySearchQuery = v.trim().toLowerCase()),
          ),
        ),
        const Divider(height: 1, color: AppColors.border),

        // Stream of Flats / Users
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'RESIDENT')
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}', style: const TextStyle(color: AppColors.error)));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allDocs = snap.data?.docs ?? [];
              final docs = allDocs.where((d) {
                if (_directorySearchQuery.isEmpty) return true;
                final data = d.data() as Map<String, dynamic>;
                final name = (data['name'] ?? '').toString().toLowerCase();
                final flat = (data['flatNumber'] ?? '').toString().toLowerCase();
                return name.contains(_directorySearchQuery) || flat.contains(_directorySearchQuery);
              }).toList();

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final name = data['name'] ?? 'Resident';
                  final flat = data['flatNumber'] ?? 'Unknown';
                  final phone = data['phone'] ?? '';
                  final occupantType = data['occupantType'] ?? 'Resident';

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.primaryBorder),
                          ),
                          child: Text(
                            flat,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryDark),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                              Text('$occupantType • $phone', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        if (phone.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.phone_rounded, color: AppColors.primary, size: 20),
                            tooltip: 'Call Resident',
                            onPressed: () async {
                              final uri = Uri.parse('tel:$phone');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}


