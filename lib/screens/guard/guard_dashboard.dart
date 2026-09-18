import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/visitor_pass_service.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_manager.dart';
import '../../utils/flat_utils.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_feedback.dart';

// ============================================================================
// SECURITY GUARD GATE TERMINAL DASHBOARD
// ============================================================================
// This is the primary touchscreen tablet / mobile UI for security personnel at
// the society gate.
//
// Key Tabs & Operational Capabilities:
// 1. Gate Passcode Verification (Tab 0):
//    - 6-digit numeric OTP keypad & text input.
//    - Instant validation of pre-approved resident guest passes.
//    - Real-time single-use enforcement and 8-hour expiry checks.
//
// 2. Walk-In & Delivery Entry Logging (Tab 0 Modal):
//    - Captures visitor name, mobile number, host flat, purpose, and delivery app.
//    - Camera photo capture uploaded to Firebase Storage.
//    - Automatic push notification to resident with 1-tap Approve / Deny buttons.
//
// 3. Live Inside Campus Monitoring (Tab 1):
//    - Real-time list of all visitors currently inside society grounds.
//    - One-tap visitor check-out logging on gate exit.
//
// 4. Gate Parcels / Courier Management (Tab 2):
//    - Logs parcels left at security gate (`gate_parcels` collection).
//    - Notifies resident and marks parcels as collected upon handover.
//
// 5. Emergency SOS Broadcast (Tab 3):
//    - Instant broadcast triggers for Fire, Medical, Intrusion, or Lift Trapped.
// ============================================================================

/// Touchscreen gate operations terminal for society security guards.
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
  PassVerificationResult? _passVerificationResult;

  // Walk-in visitor state
  final _walkInNameCtrl = TextEditingController();
  final _walkInPhoneCtrl = TextEditingController();
  String _walkInBlock = 'A';
  final _walkInFlatNoCtrl = TextEditingController();
  final _walkInVehicleCtrl = TextEditingController();
  String _walkInPurpose = 'Delivery / Courier';
  String _deliveryApp = 'Blinkit';
  final _customDeliveryAppCtrl = TextEditingController();
  bool _isLoggingWalkIn = false;
  Uint8List? _walkInPhotoBytes;
  String? _walkInPhotoName;
  final ImagePicker _imagePicker = ImagePicker();

  /// Captures a walk-in visitor's photo strictly using the device camera.
  /// Gallery upload is intentionally disallowed to ensure physical on-spot verification at the gate kiosk.
  Future<void> _pickWalkInPhoto([ImageSource source = ImageSource.camera]) async {
    try {
      // Strictly enforce ImageSource.camera for live visitor capture at security gate
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 75,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        setState(() {
          _walkInPhotoBytes = bytes;
          _walkInPhotoName = file.name;
        });
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Could not access camera: $e');
      }
    }
  }

  void _removeWalkInPhoto() {
    setState(() {
      _walkInPhotoBytes = null;
      _walkInPhotoName = null;
    });
  }

  // Campus search & filter state
  String _campusSearchQuery = '';
  final _campusSearchCtrl = TextEditingController();
  String _campusFilter = 'ALL'; // 'ALL' | 'OVERSTAY'

  // Parcel state
  final _parcelFlatCtrl = TextEditingController();
  final _parcelCountCtrl = TextEditingController(text: '1');
  final _parcelRemarksCtrl = TextEditingController();
  String _parcelProvider = 'Amazon';
  bool _isLoggingParcel = false;

  // Parcel log search & status filter state
  // Filter values: 'ALL', 'HELD_AT_GATE', 'COLLECTED', 'CONFIRMED', 'DISPUTED'
  String _parcelSearchQuery = '';
  final _parcelSearchCtrl = TextEditingController();
  String _parcelStatusFilter = 'ALL';

  // Directory search
  String _directorySearchQuery = '';
  final _directorySearchCtrl = TextEditingController();

  // Frequent visitor lookup state
  Map<String, dynamic>? _frequentVisitorData;
  bool _isLookingUpPhone = false;

  void _onWalkInPhoneChanged() {
    final phone = _walkInPhoneCtrl.text.trim();
    if (phone.length == 10) {
      _lookupFrequentVisitor(phone);
    } else {
      if (_frequentVisitorData != null) {
        setState(() {
          _frequentVisitorData = null;
        });
      }
    }
  }

  Future<void> _lookupFrequentVisitor(String phone) async {
    setState(() => _isLookingUpPhone = true);
    final data = await VisitorPassService.lookupRecentVisitorByPhone(phone);
    if (mounted) {
      setState(() {
        _isLookingUpPhone = false;
        _frequentVisitorData = data;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Register phone change listener to auto-detect frequent/past visitors as soon as 10 digits are entered
    _walkInPhoneCtrl.addListener(_onWalkInPhoneChanged);

    // Register Push Notification Click Delegate for instant gate clearance dialog / tab routing
    PushNotificationManager.instance.onNotificationClick = (ctx, payload) {
      _handleNotificationClick(ctx, payload.extraData, payload.id);
    };

    // Reconcile and auto-log any parcels for visitors with LEAVE_AT_GATE status using guard authority
    _syncLeaveAtGateParcels();
  }

  StreamSubscription? _leaveAtGateSubscription;

  /// Automatically monitors and reconciles visitors whose delivery was instructed to be left at the gate.
  /// Ensures every LEAVE_AT_GATE visitor is registered in `gate_parcels` with a secure pickup OTP
  /// using the security guard's credentials.
  void _syncLeaveAtGateParcels() {
    _leaveAtGateSubscription = FirebaseFirestore.instance
        .collection('visitors')
        .where('approvalStatus', isEqualTo: 'LEAVE_AT_GATE')
        .limit(30)
        .snapshots()
        .listen((snap) {
      for (final doc in snap.docs) {
        final data = doc.data();
        final rawFlat = (data['flatNumber'] ?? data['hostFlatNumber'] ?? '').toString();
        final name = (data['visitorName'] ?? 'Delivery').toString();
        final provider = (data['deliveryApp'] ?? data['purpose'] ?? 'Delivery').toString();
        final otp = data['pickupOtp']?.toString();
        final photo = data['photoUrl']?.toString();
        final gate = data['gateName']?.toString();
        final guard = data['guardName']?.toString();

        if (rawFlat.isNotEmpty) {
          VisitorPassService.ensureLeaveAtGateParcelCreated(
            visitorDocId: doc.id,
            flatNumber: rawFlat,
            visitorName: name,
            deliveryProvider: provider,
            pickupOtp: otp,
            photoUrl: photo,
            gateName: gate,
            guardName: guard,
            guardUid: _currentGuardUid,
          );
        }
      }
    }, onError: (e) {
      debugPrint('[GuardDashboard] Note on leave-at-gate auto-reconciliation: $e');
    });
  }

  @override
  void dispose() {
    // Clean up phone listener, leave-at-gate listener, and push notification delegate on screen unmount
    _walkInPhoneCtrl.removeListener(_onWalkInPhoneChanged);
    _leaveAtGateSubscription?.cancel();
    if (PushNotificationManager.instance.onNotificationClick != null) {
      PushNotificationManager.instance.onNotificationClick = null;
    }
    _codeController.dispose();
    _walkInNameCtrl.dispose();
    _walkInPhoneCtrl.dispose();
    _walkInFlatNoCtrl.dispose();
    _walkInVehicleCtrl.dispose();
    _customDeliveryAppCtrl.dispose();
    _campusSearchCtrl.dispose();
    _parcelFlatCtrl.dispose();
    _parcelCountCtrl.dispose();
    _parcelRemarksCtrl.dispose();
    _parcelSearchCtrl.dispose();
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
      _passVerificationResult = null;
    });

    try {
      final result = await VisitorPassService.verifyPassCode(code);
      if (mounted) {
        setState(() {
          _passVerificationResult = result;
          if (result.isValid) {
            _verifiedVisitorDocId = result.document?.id;
            _verifiedVisitorData = result.data;
          }
        });

        if (result.isValid) {
          AppFeedback.showSuccess(context, result.message);
        } else {
          AppFeedback.showError(context, result.message);
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
        visitorData: _verifiedVisitorData,
      );

      if (mounted) {
        AppFeedback.showSuccess(context, 'Visitor checked in successfully!');
        setState(() {
          _verifiedVisitorData = null;
          _verifiedVisitorDocId = null;
          _passVerificationResult = null;
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
    final flatNo = _walkInFlatNoCtrl.text.trim();
    final vehicle = _walkInVehicleCtrl.text.trim().toUpperCase();
    final isDelivery = _walkInPurpose == 'Delivery / Courier';
    final isCab = _walkInPurpose == 'Cab / Taxi';

    // 1. Visitor Full Name is always mandatory
    if (name.isEmpty) {
      AppFeedback.showError(context, 'Please enter visitor full name.');
      return;
    }

    // 2. Mobile Number Validation:
    // - Mandatory 10-digit number for Delivery, Maid, Guest, Maintenance, and Other.
    // - Optional for Cab / Taxi, but if entered, must be strictly 10 digits.
    final bool isPhoneMandatory = !isCab;
    if (isPhoneMandatory && phone.isEmpty) {
      AppFeedback.showError(context, 'Please enter visitor 10-digit mobile number.');
      return;
    }
    if (phone.isNotEmpty) {
      if (phone.length != 10) {
        AppFeedback.showError(context, 'Please enter a valid 10-digit mobile number.');
        return;
      }
    }

    // 3. Flat Number Validation:
    // - Flat No is always mandatory and must be strictly 3 digits (e.g. 101, 312).
    if (flatNo.isEmpty) {
      AppFeedback.showError(context, 'Please enter flat number.');
      return;
    }
    if (flatNo.length != 3) {
      AppFeedback.showError(context, 'Flat number must be strictly 3 digits (e.g. 101, 312).');
      return;
    }

    // Form concatenated canonical flat identifier: e.g. "B-312"
    final flat = '$_walkInBlock-$flatNo';

    // 4. Vehicle Number Validation:
    // - Mandatory for Delivery Guy and Cab / Taxi.
    // - Optional for Maid, Guest, Maintenance, Other.
    if (isDelivery && vehicle.isEmpty) {
      AppFeedback.showError(context, 'Vehicle number is mandatory for delivery personnel.');
      return;
    }
    if (isCab && vehicle.isEmpty) {
      AppFeedback.showError(context, 'Vehicle number is mandatory for cab / taxi.');
      return;
    }

    // 5. Delivery App Validation:
    String? effectiveDeliveryApp;
    if (isDelivery) {
      effectiveDeliveryApp = _deliveryApp == 'Other Delivery'
          ? _customDeliveryAppCtrl.text.trim()
          : _deliveryApp;

      if (effectiveDeliveryApp.isEmpty) {
        AppFeedback.showError(context, 'Please specify the delivery app name.');
        return;
      }
    }

    // 6. Mandatory Live Photo Verification:
    // Security policy strictly mandates capturing a live photo of the visitor using the camera
    // before sending a walk-in clearance notification to the resident flat.
    if (_walkInPhotoBytes == null) {
      AppFeedback.showError(
        context,
        'Visitor photo is strictly mandatory. Please capture a live photo of the visitor using the camera before notifying the resident.',
      );
      return;
    }

    setState(() => _isLoggingWalkIn = true);

    try {
      // 7. Society Database Flat Existence Verification:
      // Verify that the specified flat exists in the society records before logging and notifying.
      // Throws a clear error to the guard if the flat does not exist.
      final bool flatExists = await VisitorPassService.checkFlatExists(flat);
      if (!flatExists) {
        if (mounted) {
          AppFeedback.showError(
            context,
            'Flat $flat does not exist in society database. Please verify the block and flat number.',
          );
        }
        return;
      }

      String? uploadedPhotoUrl;
      if (_walkInPhotoBytes != null) {
        uploadedPhotoUrl = await VisitorPassService.uploadVisitorPhoto(
          bytes: _walkInPhotoBytes!,
          guardUid: _currentGuardUid,
          fileName: _walkInPhotoName,
        );
      }

      await VisitorPassService.logWalkInVisitor(
        visitorName: name,
        phone: phone,
        flatNumber: flat,
        purpose: _walkInPurpose,
        deliveryApp: isDelivery ? effectiveDeliveryApp : null,
        vehicleNumber: vehicle,
        photoUrl: uploadedPhotoUrl,
        guardUid: _currentGuardUid,
        guardName: guardName,
        gateName: gateName,
      );

      if (mounted) {
        final label = isDelivery && effectiveDeliveryApp != null ? '$name ($effectiveDeliveryApp)' : name;
        final bool isStaff = _walkInPurpose.toLowerCase().contains('maid') ||
            _walkInPurpose.toLowerCase().contains('helper') ||
            _walkInPurpose.toLowerCase().contains('cook') ||
            _walkInPurpose.toLowerCase().contains('driver');

        // Domestic staff are checked in directly to campus; guests and deliveries require resident clearance
        // and must remain at the gate until approval is received.
        if (isStaff) {
          AppFeedback.showSuccess(context, 'Staff $label checked in at $flat.');
          setState(() => _currentTab = 2); // Switch to In-Campus view for routine staff
        } else {
          AppFeedback.showSuccess(context, 'Walk-in request for $label sent to flat $flat. Awaiting resident approval.');
        }

        _walkInNameCtrl.clear();
        _walkInPhoneCtrl.clear();
        _walkInFlatNoCtrl.clear();
        _walkInVehicleCtrl.clear();
        _customDeliveryAppCtrl.clear();
        _walkInBlock = 'A'; // Reset selected block back to default Block A
        _walkInPhotoBytes = null;
        _walkInPhotoName = null;
        _frequentVisitorData = null; // Clear frequent visitor suggestion
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
                // Emergency Nature Dropdown with isExpanded: true to prevent horizontal overflow on compact screens
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Emergency Nature *',
                    prefixIcon: Icon(Icons.emergency_rounded, color: AppColors.error),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Fire Emergency',
                      child: Text('🔥 Fire Emergency', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Medical Emergency',
                      child: Text('🚑 Medical Emergency', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Security Disturbance',
                      child: Text('🚨 Security Disturbance / Intrusion', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Lift Entrapment',
                      child: Text('🛗 Lift Entrapment / Power Failure', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'Water / Infrastructure',
                      child: Text('💧 Water Pipeline / Structural Leak', overflow: TextOverflow.ellipsis),
                    ),
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
                // Delivery Provider Dropdown with isExpanded: true to prevent horizontal overflow on compact screens
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _parcelProvider,
                  decoration: const InputDecoration(
                    labelText: 'Delivery Provider *',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Amazon', child: Text('Amazon', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Flipkart', child: Text('Flipkart', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Swiggy Instamart', child: Text('Swiggy Instamart', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Zomato / Blinkit', child: Text('Zomato / Blinkit', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Blue Dart / Courier', child: Text('Blue Dart / Courier', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'India Post', child: Text('India Post', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Other Delivery', child: Text('Other Delivery', overflow: TextOverflow.ellipsis)),
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

  /// Displays a secure OTP verification modal requiring the security guard to enter
  /// the 4-digit Pickup OTP shown on the resident's mobile app before handing over a parcel.
  void _showHandoverOtpDialog({
    required String parcelDocId,
    required String flatNumber,
    required String provider,
    required int packetCount,
    required String guardName,
    required String gateName,
  }) {
    final otpCtrl = TextEditingController();
    bool isVerifying = false;
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (sheetCtx, setDialogState) => AppDialog(
          title: 'Verify Pickup OTP',
          subtitle: 'Handing over $packetCount package(s) • $provider to Flat $flatNumber',
          icon: Icons.security_rounded,
          iconColor: AppColors.primary,
          maxWidth: 420,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primaryBorder),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ask the resident for their 4-digit Pickup OTP displayed in their app notification or Parcels tab.',
                        style: const TextStyle(fontSize: 12, color: AppColors.primaryDark, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Enter 4-Digit Pickup OTP',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: otpCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 4,
                autofocus: true,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8, color: AppColors.primary),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '• • • •',
                  hintStyle: TextStyle(fontSize: 22, letterSpacing: 6, color: Colors.grey.shade400),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: errorMessage,
                ),
                onChanged: (_) {
                  if (errorMessage != null) {
                    setDialogState(() => errorMessage = null);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isVerifying ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              icon: isVerifying
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.verified_rounded, size: 18),
              label: const Text('Verify & Hand Over', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: isVerifying
                  ? null
                  : () async {
                      final entered = otpCtrl.text.trim();
                      if (entered.length != 4) {
                        setDialogState(() => errorMessage = 'Please enter a valid 4-digit OTP');
                        return;
                      }

                      setDialogState(() {
                        isVerifying = true;
                        errorMessage = null;
                      });

                      final success = await VisitorPassService.verifyAndCollectParcel(
                        parcelDocId: parcelDocId,
                        enteredOtp: entered,
                        guardUid: _currentGuardUid,
                        guardName: guardName,
                        gateName: gateName,
                        flatNumber: flatNumber,
                        deliveryProvider: provider,
                        packetCount: packetCount,
                      );

                      if (dialogCtx.mounted) {
                        if (success) {
                          Navigator.pop(dialogCtx);
                          if (mounted) {
                            AppFeedback.showSuccess(context, 'Parcel verified with OTP & handed over to Flat $flatNumber!');
                          }
                        } else {
                          setDialogState(() {
                            isVerifying = false;
                            errorMessage = 'Incorrect OTP! Please verify with resident.';
                          });
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Society Notices Modal ────────────────────────────────────────────────

  void _showNoticesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.campaign_rounded, color: AppColors.primary, size: 24),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Society Announcements & Circulars',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('announcements').orderBy('createdAt', descending: true).snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(child: Text('No announcements posted yet.', style: TextStyle(color: Colors.grey)));
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, idx) {
                        final data = docs[idx].data() as Map<String, dynamic>;
                        final title = data['title']?.toString() ?? 'Notice';
                        final msg = data['message']?.toString() ?? '';
                        final priority = data['priority']?.toString() ?? 'NORMAL';
                        final isPinned = data['isPinned'] == true;
                        final ts = (data['createdAt'] as Timestamp?)?.toDate();
                        final timeStr = ts != null ? DateFormat('dd MMM yyyy, hh:mm a').format(ts) : '';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isPinned ? Colors.amber.shade50 : AppColors.cardSurfaceSecondary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isPinned ? Colors.amber.shade300 : AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (isPinned) ...[
                                    const Icon(Icons.push_pin_rounded, size: 14, color: Colors.amber),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: priority == 'HIGH' ? Colors.red.shade100 : Colors.teal.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      priority,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: priority == 'HIGH' ? Colors.red.shade900 : Colors.teal.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (timeStr.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                              const SizedBox(height: 8),
                              Text(msg, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary)),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Gate Security Alerts Modal ───────────────────────────────────────────

  void _showGuardAlertsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded, color: AppColors.primary, size: 24),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Gate Security & Clearance Alerts',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('notifications')
                      .where('targetRole', isEqualTo: 'GUARD')
                      .limit(50)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text('No gate clearance alerts yet.', style: TextStyle(color: Colors.grey)),
                      );
                    }
                    final sortedDocs = docs.toList()
                      ..sort((a, b) {
                        final aD = a.data() as Map<String, dynamic>;
                        final bD = b.data() as Map<String, dynamic>;
                        final aT = (aD['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                        final bT = (bD['createdAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
                        return bT.compareTo(aT);
                      });

                    final unreadDocs = sortedDocs.where((d) => (d.data() as Map)['isRead'] != true).toList();

                    return Column(
                      children: [
                        if (unreadDocs.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Wrapped in Expanded to ensure unread text never causes RenderFlex overflow against the action button
                                Expanded(
                                  child: Text(
                                    '${unreadDocs.length} unread alert${unreadDocs.length > 1 ? 's' : ''}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    await NotificationService.markAllAsRead(unreadDocs.map((d) => d.id).toList());
                                  },
                                  icon: const Icon(Icons.done_all_rounded, size: 16, color: AppColors.primary),
                                  label: const Text('Mark all read', style: TextStyle(fontSize: 12, color: AppColors.primary)),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: sortedDocs.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, idx) {
                              final data = sortedDocs[idx].data() as Map<String, dynamic>;
                              final isRead = data['isRead'] == true;
                              final title = data['title']?.toString() ?? 'Alert';
                              final msg = data['message']?.toString() ?? '';
                              final isDenied = title.contains('DENIED');
                              final isApproved = title.contains('Approved');
                              final ts = (data['createdAt'] as Timestamp?)?.toDate();
                              final timeStr = ts != null ? DateFormat('hh:mm a, dd MMM').format(ts) : 'Just now';

                              return InkWell(
                                onTap: () {
                                  // Mark notification as read and show clearance status dialog
                                  _handleNotificationClick(context, data, sortedDocs[idx].id);
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDenied
                                        ? Colors.red.shade50
                                        : (isApproved ? Colors.green.shade50 : AppColors.cardSurfaceSecondary),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isDenied
                                          ? Colors.red.shade300
                                          : (isApproved ? Colors.green.shade300 : AppColors.border),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        isDenied
                                            ? Icons.cancel_rounded
                                            : (isApproved ? Icons.check_circle_rounded : Icons.info_rounded),
                                        color: isDenied ? Colors.red : (isApproved ? Colors.green : AppColors.primary),
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          title,
                                                          style: TextStyle(
                                                            fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                                            fontSize: 13,
                                                            color: isDenied ? Colors.red.shade900 : (isApproved ? Colors.green.shade900 : AppColors.textPrimary),
                                                          ),
                                                        ),
                                                      ),
                                                      if (!isRead)
                                                        Container(
                                                          margin: const EdgeInsets.only(left: 6, right: 6),
                                                          width: 8,
                                                          height: 8,
                                                          decoration: const BoxDecoration(
                                                            color: AppColors.primary,
                                                            shape: BoxShape.circle,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(msg, style: const TextStyle(fontSize: 12, height: 1.3, color: AppColors.textPrimary)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handles routing and dialog presentation when a notification is clicked on the guard screen.
  void _handleNotificationClick(BuildContext context, Map<String, dynamic> notif, String docId) {
    // Auto-mark notification as read
    if (notif['isRead'] != true) {
      NotificationService.markAsRead(docId);
    }

    final type = (notif['type'] ?? '').toString().toUpperCase();
    final title = (notif['title'] ?? '').toString();

    // 1. Visitor clearance responses (Approved, Denied, or Leave at Gate by resident)
    final approvalStatus = (notif['approvalStatus'] ?? '').toString().toUpperCase();
    if (type == 'VISITOR_APPROVAL_RESPONSE' ||
        type == 'VISITOR_LEAVE_AT_GATE' ||
        type.startsWith('VISITOR') ||
        approvalStatus.isNotEmpty ||
        title.contains('Approved') ||
        title.contains('DENIED') ||
        title.contains('Leave at Gate')) {
      _showVisitorApprovalStatusDialog(context, notif);
    }
    // 2. Gate parcel alerts -> switch to Parcels tab (index 3)
    else if (type.contains('PARCEL') || title.toLowerCase().contains('parcel')) {
      setState(() => _currentTab = 3);
    }
    // 3. Emergency SOS broadcast alerts
    else if (type == 'EMERGENCY' || title.toLowerCase().contains('emergency') || title.toLowerCase().contains('sos')) {
      _showEmergencyAlertDialog(context, notif);
    }
    // 4. Passcode / guest pre-approval alerts -> switch to verification tab
    else if (type == 'PASSCODE' || title.toLowerCase().contains('passcode') || title.toLowerCase().contains('guest')) {
      setState(() => _currentTab = 0);
    }
  }

  /// Displays the official gate clearance dialog showing Approved or Denied status for security action.
  void _showVisitorApprovalStatusDialog(BuildContext context, Map<String, dynamic> notif) {
    final title = notif['title']?.toString() ?? 'Visitor Clearance';
    final msg = notif['message']?.toString() ?? '';
    final type = (notif['type'] ?? '').toString().toUpperCase();
    final approvalStatus = (notif['approvalStatus'] ?? '').toString().toUpperCase();

    // Check explicit enum status first, then fallback to title content (BUG-29)
    final isDenied = approvalStatus == 'DENIED' || type == 'VISITOR_APPROVAL_DENIED' || title.contains('DENIED');
    final isLeaveAtGate = approvalStatus == 'LEAVE_AT_GATE' || type == 'VISITOR_LEAVE_AT_GATE' || title.contains('Leave at Gate');
    final isApproved = !isLeaveAtGate && (approvalStatus == 'APPROVED' || type == 'VISITOR_APPROVAL_APPROVED' || title.contains('Approved'));
    final visitorName = notif['visitorName']?.toString() ?? 'Visitor';
    final flatNumber = notif['flatNumber']?.toString() ?? '';
    final ts = (notif['createdAt'] as Timestamp?)?.toDate();
    final timeStr = ts != null ? DateFormat('hh:mm a, dd MMM').format(ts) : 'Just now';

    // Proactively ensure parcel is logged in gate_parcels under guard credentials if resident opted for Leave at Gate
    if (isLeaveAtGate) {
      VisitorPassService.ensureLeaveAtGateParcelCreated(
        visitorDocId: notif['visitorDocId']?.toString(),
        flatNumber: flatNumber,
        visitorName: visitorName,
        deliveryProvider: notif['deliveryProvider']?.toString(),
        pickupOtp: notif['pickupOtp']?.toString(),
        photoUrl: notif['photoUrl']?.toString(),
        gateName: notif['gateName']?.toString(),
        guardName: notif['guardName']?.toString(),
        guardUid: _currentGuardUid,
      );
    }

    // Use global navigatorKey context if available to guarantee Navigator ancestor exists
    final targetCtx = PushNotificationManager.navigatorKey.currentContext ?? context;
    if (!targetCtx.mounted) return;

    showDialog(
      context: targetCtx,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDenied
                    ? Colors.red.shade50
                    : (isLeaveAtGate
                        ? Colors.orange.shade50
                        : (isApproved ? Colors.green.shade50 : AppColors.primarySurface)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isDenied
                    ? Icons.cancel_rounded
                    : (isLeaveAtGate
                        ? Icons.inventory_2_outlined
                        : (isApproved ? Icons.check_circle_rounded : Icons.info_rounded)),
                color: isDenied
                    ? Colors.red
                    : (isLeaveAtGate
                        ? Colors.orange.shade800
                        : (isApproved ? Colors.green : AppColors.primary)),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isDenied
                        ? 'Entry Denied'
                        : (isLeaveAtGate
                            ? 'Leave at Gate'
                            : (isApproved ? 'Entry Approved' : 'Clearance Update')),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDenied
                          ? Colors.red.shade900
                          : (isLeaveAtGate
                              ? Colors.orange.shade900
                              : (isApproved ? Colors.green.shade900 : AppColors.textPrimary)),
                    ),
                  ),
                  Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        // Wrap content in SingleChildScrollView so tall messages or narrow screen keyboards never trigger RenderFlex overflow
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDenied
                      ? Colors.red.shade50
                      : (isLeaveAtGate
                          ? Colors.orange.shade50
                          : (isApproved ? Colors.green.shade50 : AppColors.cardSurfaceSecondary)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDenied
                        ? Colors.red.shade300
                        : (isLeaveAtGate
                            ? Colors.orange.shade400
                            : (isApproved ? Colors.green.shade300 : AppColors.border)),
                  ),
                ),
                child: Text(
                  isDenied
                      ? '⛔ ACTION REQUIRED: Turn visitor away immediately. Resident of flat $flatNumber has DENIED gate clearance for $visitorName. No campus entry permitted.'
                      : (isLeaveAtGate
                          ? '📦 ACTION REQUIRED: Do NOT allow delivery agent inside campus. Collect parcel from $visitorName for flat $flatNumber and place it in the gate holding rack. A 4-digit pickup code has been sent to the resident. Delivery agent must not enter campus.'
                          : '✅ CLEARANCE GRANTED: Resident of flat $flatNumber has APPROVED entry for $visitorName. Allow entry.'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDenied
                        ? Colors.red.shade900
                        : (isLeaveAtGate
                            ? Colors.orange.shade900
                            : (isApproved ? Colors.green.shade900 : AppColors.textPrimary)),
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(msg, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          if (isLeaveAtGate)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _currentTab = 3); // Switch to Parcels tab
              },
              child: Text(
                'View Parcels Tab',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
              ),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDenied
                  ? Colors.red.shade700
                  : (isLeaveAtGate ? Colors.orange.shade800 : AppColors.primary),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              isDenied
                  ? 'Acknowledge (Turn Away)'
                  : (isLeaveAtGate ? 'Acknowledge (Keep at Gate)' : 'Acknowledge (Allow Entry)'),
            ),
          ),
        ],
      ),
    );
  }

  /// Displays the emergency security alert dialog on the gate terminal.
  void _showEmergencyAlertDialog(BuildContext context, Map<String, dynamic> notif) {
    final title = notif['title']?.toString() ?? 'Emergency Alert';
    final msg = notif['message']?.toString() ?? '';
    final ts = (notif['createdAt'] as Timestamp?)?.toDate();
    final timeStr = ts != null ? DateFormat('hh:mm a, dd MMM').format(ts) : 'Just now';

    // Use global navigatorKey context if available to guarantee Navigator ancestor exists
    final targetCtx = PushNotificationManager.navigatorKey.currentContext ?? context;
    if (!targetCtx.mounted) return;

    showDialog(
      context: targetCtx,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_rounded, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                  Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
        // SingleChildScrollView ensures emergency alert descriptions never overflow on compact screen displays
        content: SingleChildScrollView(
          child: Text(msg, style: const TextStyle(fontSize: 13, height: 1.4)),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Acknowledge'),
          ),
        ],
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
            // Optimized title spacing to grant maximum horizontal width to title on narrow screens
            titleSpacing: 8,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield_rounded, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        guardName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        '$gateName • $shift',
                        style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.8)),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Duty Status Pill Toggle - compact layout ensures no crowding on narrow phone screens
              Tooltip(
                message: isOnDuty ? 'Status: On Duty (Tap to switch Off Duty)' : 'Status: Off Duty (Tap to switch On Duty)',
                child: InkWell(
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
                    margin: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOnDuty ? AppColors.success : AppColors.cardSurfaceSecondary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isOnDuty ? Colors.white : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isOnDuty ? 'ON' : 'OFF',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isOnDuty ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Security Alerts Bell with unread badge
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('targetRole', isEqualTo: 'GUARD')
                    .limit(50)
                    .snapshots(),
                builder: (context, alertSnap) {
                  final unreadCount = alertSnap.data?.docs.where((d) => (d.data() as Map)['isRead'] != true).length ?? 0;
                  return IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    icon: Badge(
                      isLabelVisible: unreadCount > 0,
                      label: Text('$unreadCount', style: const TextStyle(fontSize: 8)),
                      child: const Icon(Icons.notifications_rounded, size: 19, color: Colors.white),
                    ),
                    tooltip: 'Security Alerts',
                    onPressed: () => _showGuardAlertsModal(context),
                  );
                },
              ),
              // Emergency SOS Button (Compact with badge style)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 12, color: Colors.white),
                      SizedBox(width: 2),
                      Text('SOS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                tooltip: 'Emergency SOS Alert',
                onPressed: () => _showEmergencyDialog(guardName, gateName),
              ),
              // Overflow Menu for Notices & Logout
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
                tooltip: 'More actions',
                onSelected: (value) {
                  if (value == 'notices') {
                    _showNoticesModal(context);
                  } else if (value == 'logout') {
                    FirebaseAuth.instance.signOut();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'notices',
                    child: Row(
                      children: [
                        Icon(Icons.campaign_rounded, size: 18, color: AppColors.textPrimary),
                        SizedBox(width: 8),
                        Text('Society Notices', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, size: 18, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Log out', style: TextStyle(fontSize: 13, color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: IndexedStack(
            index: _currentTab,
            children: [
              _buildVerifyPassTab(guardName, gateName),
              _buildWalkInTab(guardName, gateName),
              _buildInCampusTab(guardName, gateName),
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
                    // Center aligned with responsive font size ensures no overflow or awkward wrapping on narrow screens
                    const Text(
                      'Resident Gate Pass Verification',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Enter the 6-digit OTP code shared by visiting guest',
                      textAlign: TextAlign.center,
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
                        if (_passVerificationResult != null && v.trim().length != 6) {
                          setState(() {
                            _passVerificationResult = null;
                            _verifiedVisitorData = null;
                            _verifiedVisitorDocId = null;
                          });
                        }
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
              if (_passVerificationResult != null && !_passVerificationResult!.isValid) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _passVerificationResult!.isExpired
                        ? Colors.amber.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _passVerificationResult!.isExpired
                          ? Colors.amber.shade400
                          : Colors.red.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _passVerificationResult!.isExpired
                              ? Colors.amber.shade100
                              : Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _passVerificationResult!.isAlreadyUsed
                              ? Icons.block_rounded
                              : (_passVerificationResult!.isExpired
                                  ? Icons.timer_off_outlined
                                  : Icons.error_outline_rounded),
                          color: _passVerificationResult!.isExpired
                              ? Colors.amber.shade900
                              : Colors.red.shade800,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _passVerificationResult!.isAlreadyUsed
                                  ? 'Passcode Already Used (Single-Use Only)'
                                  : (_passVerificationResult!.isExpired
                                      ? 'Passcode Expired (8-Hour Limit)'
                                      : 'Invalid Passcode'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _passVerificationResult!.isExpired
                                    ? Colors.amber.shade900
                                    : Colors.red.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _passVerificationResult!.message,
                              style: TextStyle(
                                fontSize: 12,
                                color: _passVerificationResult!.isExpired
                                    ? Colors.brown.shade800
                                    : Colors.red.shade900,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                      Row(
                        children: [
                          const Icon(Icons.verified_rounded, color: AppColors.success, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Passcode Verified • Ready for Entry', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.success, fontSize: 14)),
                                Text('Single-use gate pass active (valid for 8 hours)', style: TextStyle(fontSize: 11, color: Colors.green.shade800)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      _buildDetailRow('Visitor Name', _verifiedVisitorData!['visitorName']?.toString() ?? 'Guest'),
                      _buildDetailRow('Visiting Flat', _verifiedVisitorData!['flatNumber']?.toString() ?? 'Unknown'),
                      _buildDetailRow('Purpose', _verifiedVisitorData!['purpose']?.toString() ?? 'Visit'),
                      if ((_verifiedVisitorData!['phone']?.toString() ?? '').isNotEmpty)
                        _buildDetailRow('Mobile', _verifiedVisitorData!['phone'].toString()),
                      if ((_verifiedVisitorData!['vehicleNumber']?.toString() ?? '').isNotEmpty)
                        _buildDetailRow('Vehicle', _verifiedVisitorData!['vehicleNumber'].toString())
                      else if (_verifiedVisitorData!['isComingByCar'] == true)
                        _buildDetailRow('Vehicle', 'Arriving by Car (No reg entered)'),
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
                    // Wrapped in Expanded with ellipsis for safe rendering on compact phone widths
                    Expanded(
                      child: Text(
                        'Direct / Walk-In Gate Entry',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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

                // Mobile Number (10 digits strictly enforced; mandatory except for Cab)
                TextFormField(
                  controller: _walkInPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    // Concise label avoids truncation on small screens while retaining clarity
                    labelText: _walkInPurpose == 'Cab / Taxi'
                        ? 'Visitor Mobile (Optional)'
                        : 'Mobile Number (10 Digits) *',
                    hintText: '10-digit mobile number',
                    counterText: '',
                    prefixText: '+91 ',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    isDense: true,
                  ),
                ),

                // ─── Frequent Visitor Auto-Fill Suggestion / Lookup Status ───
                // Displays real-time lookup feedback or a 1-tap autofill card when a recognized phone number is entered
                if (_isLookingUpPhone) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary)),
                      const SizedBox(width: 8),
                      // Expanded with ellipsis prevents status label overflow during async phone lookup
                      Expanded(
                        child: Text(
                          'Checking past visitor records...',
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600, fontStyle: FontStyle.italic),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_frequentVisitorData != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.blue.shade100,
                          child: const Icon(Icons.history_rounded, size: 18, color: Colors.blue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recognized: ${_frequentVisitorData!['visitorName'] ?? 'Frequent Visitor'}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_frequentVisitorData!['purpose'] ?? 'Visitor'} • ${_frequentVisitorData!['deliveryApp'] ?? _frequentVisitorData!['vehicleNumber'] ?? 'Frequent'}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // 1-Tap Autofill Button to populate name, vehicle, purpose, and provider
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            setState(() {
                              final sName = _frequentVisitorData!['visitorName']?.toString() ?? '';
                              if (sName.isNotEmpty) _walkInNameCtrl.text = sName;

                              final sVehicle = _frequentVisitorData!['vehicleNumber']?.toString() ?? '';
                              if (sVehicle.isNotEmpty) _walkInVehicleCtrl.text = sVehicle;

                              final sPurpose = _frequentVisitorData!['purpose']?.toString() ?? '';
                              if (sPurpose.isNotEmpty) _walkInPurpose = sPurpose;

                              final sApp = _frequentVisitorData!['deliveryApp']?.toString() ?? '';
                              if (sApp.isNotEmpty) _deliveryApp = sApp;

                              _frequentVisitorData = null; // Dismiss chip once autofilled
                            });
                            if (mounted) {
                              AppFeedback.showSuccess(context, 'Autofilled visitor details!');
                            }
                          },
                          child: const Text('Autofill', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16, color: Colors.blueGrey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Dismiss suggestion',
                          onPressed: () => setState(() => _frequentVisitorData = null),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // Bifurcated Flat Identification: Block Dropdown and 3-Digit Flat No side-by-side with labels above.
                // Using equal flex: 5 ratio and removing inner prefixIcon so that 'Block A', 'Block B', 'Block C', 'Block D'
                // have plenty of horizontal width and are never clipped to just their first letter 'B'.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Block Selector Dropdown (Block A, B, C, D)
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.domain_rounded, size: 14, color: AppColors.primary),
                              SizedBox(width: 4),
                              Text(
                                'Block *',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            // ValueKey ensures widget rebuilds cleanly whenever _walkInBlock changes
                            key: ValueKey('walkInBlock_$_walkInBlock'),
                            initialValue: _walkInBlock,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              // Standard horizontal padding without bulky prefix icon ensures full text visibility
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'A', child: Text('Block A', style: TextStyle(fontWeight: FontWeight.w500))),
                              DropdownMenuItem(value: 'B', child: Text('Block B', style: TextStyle(fontWeight: FontWeight.w500))),
                              DropdownMenuItem(value: 'C', child: Text('Block C', style: TextStyle(fontWeight: FontWeight.w500))),
                              DropdownMenuItem(value: 'D', child: Text('Block D', style: TextStyle(fontWeight: FontWeight.w500))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _walkInBlock = val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Flat Number Entry (Strictly limited to 3 digits)
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.apartment_rounded, size: 14, color: AppColors.primary),
                              SizedBox(width: 4),
                              // Expanded with ellipsis prevents label overflow on small mobile widths
                              Expanded(
                                child: Text(
                                  'Flat No. (3 Digits) *',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _walkInFlatNoCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: 3,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            decoration: const InputDecoration(
                              hintText: 'e.g. 101 or 312',
                              counterText: '',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Purpose Selection Dropdown
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _walkInPurpose,
                  decoration: const InputDecoration(
                    labelText: 'Purpose of Visit *',
                    prefixIcon: Icon(Icons.assignment_outlined),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Delivery / Courier', child: Text('Delivery / Courier', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Guest / Personal', child: Text('Guest / Personal', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Cab / Taxi', child: Text('Cab / Taxi', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Maid / Domestic Helper', child: Text('Maid / Domestic Helper', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Maintenance / Repair', child: Text('Maintenance / Repair', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Other', child: Text('Other', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _walkInPurpose = val);
                  },
                ),
                const SizedBox(height: 14),

                // Delivery App Selection (Mandatory for Delivery / Courier)
                if (_walkInPurpose == 'Delivery / Courier') ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _deliveryApp,
                    decoration: const InputDecoration(
                      labelText: 'Delivery App / Company *',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Blinkit', child: Text('Blinkit', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Swiggy / Instamart', child: Text('Swiggy / Instamart', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Zomato', child: Text('Zomato', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Zepto', child: Text('Zepto', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Amazon', child: Text('Amazon', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Flipkart', child: Text('Flipkart', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'BigBasket', child: Text('BigBasket', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Blue Dart / Courier', child: Text('Blue Dart / Courier', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'India Post', child: Text('India Post', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Other Delivery', child: Text('Other Delivery (Custom)', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _deliveryApp = val);
                    },
                  ),
                  if (_deliveryApp == 'Other Delivery') ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _customDeliveryAppCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Enter App / Courier Name *',
                        hintText: 'e.g. DTDC, Dunzo, Shadowfax',
                        prefixIcon: Icon(Icons.storefront_outlined),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                ],

                // Vehicle Number (Mandatory for Delivery & Cab; Optional for Maid, Guest, etc.)
                TextFormField(
                  controller: _walkInVehicleCtrl,
                  decoration: InputDecoration(
                    labelText: (_walkInPurpose == 'Delivery / Courier' || _walkInPurpose == 'Cab / Taxi')
                        ? 'Vehicle Number (Mandatory) *'
                        : 'Vehicle Number (Optional)',
                    hintText: 'e.g. DL 01 AB 1234',
                    prefixIcon: const Icon(Icons.directions_car_outlined),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 18),

                // Visitor Photo Capture Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _walkInPhotoBytes != null
                        ? Colors.green.shade50
                        : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _walkInPhotoBytes != null
                          ? Colors.green.shade300
                          : Colors.amber.shade400,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _walkInPhotoBytes != null
                                ? Icons.check_circle_rounded
                                : Icons.camera_alt_rounded,
                            size: 18,
                            color: _walkInPhotoBytes != null
                                ? Colors.green
                                : Colors.amber.shade800,
                          ),
                          const SizedBox(width: 8),
                          // Expanded with ellipsis guarantees title never causes overflow
                          Expanded(
                            child: Text(
                              _walkInPhotoBytes != null
                                  ? 'Visitor Photo Captured'
                                  : 'Visitor Photo (Mandatory) *',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _walkInPhotoBytes != null
                                    ? Colors.green.shade900
                                    : Colors.amber.shade900,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _walkInPhotoBytes != null
                            ? 'Photo captured and will be sent with resident approval alert.'
                            : 'Mandatory: Guard must capture visitor photo via camera before notifying resident.',
                        style: TextStyle(
                          fontSize: 11,
                          color: _walkInPhotoBytes != null
                              ? AppColors.textMuted
                              : Colors.amber.shade900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_walkInPhotoBytes != null) ...[
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _walkInPhotoBytes!,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      side: const BorderSide(color: AppColors.primary),
                                    ),
                                    icon: const Icon(Icons.refresh_rounded, size: 14),
                                    label: const Text('Retake Photo', style: TextStyle(fontSize: 11)),
                                    onPressed: () => _pickWalkInPhoto(ImageSource.camera),
                                  ),
                                  const SizedBox(height: 6),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.error,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    ),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                                    label: const Text('Remove Photo', style: TextStyle(fontSize: 11)),
                                    onPressed: _removeWalkInPhoto,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Strictly Camera-Only option for gate kiosk walk-in visitors (gallery upload disabled)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded, size: 18),
                            label: const Text(
                              'Take Photo (Camera Only)',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            onPressed: () => _pickWalkInPhoto(ImageSource.camera),
                          ),
                        ),
                      ],
                    ],
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

  /// Evaluates whether a visitor has exceeded normal stay duration.
  /// Delivery/Cab/Courier: warning threshold is 25 minutes.
  /// Guests/Personal/Other: warning threshold is 6 hours (360 minutes).
  static bool _isVisitorOverstaying(Map<String, dynamic> data) {
    final entryTime = (data['entryTime'] as Timestamp?)?.toDate();
    if (entryTime == null) return false;
    final diffMinutes = DateTime.now().difference(entryTime).inMinutes;
    final purpose = (data['purpose'] ?? '').toString().toLowerCase();
    final isDeliveryOrCab = purpose.contains('delivery') ||
        purpose.contains('courier') ||
        purpose.contains('cab') ||
        purpose.contains('taxi') ||
        purpose.contains('service');
    return isDeliveryOrCab ? diffMinutes >= 25 : diffMinutes >= 360;
  }

  /// Evaluates whether a visitor has exceeded critical stay duration.
  /// Delivery/Cab/Courier: critical threshold is 45 minutes.
  /// Guests/Personal/Other: critical threshold is 10 hours (600 minutes).
  static bool _isVisitorOverstayCritical(Map<String, dynamic> data) {
    final entryTime = (data['entryTime'] as Timestamp?)?.toDate();
    if (entryTime == null) return false;
    final diffMinutes = DateTime.now().difference(entryTime).inMinutes;
    final purpose = (data['purpose'] ?? '').toString().toLowerCase();
    final isDeliveryOrCab = purpose.contains('delivery') ||
        purpose.contains('courier') ||
        purpose.contains('cab') ||
        purpose.contains('taxi') ||
        purpose.contains('service');
    return isDeliveryOrCab ? diffMinutes >= 45 : diffMinutes >= 600;
  }

  Widget _buildInCampusTab(String guardName, String gateName) {
    return Column(
      children: [
        // Search Bar
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

        // Live Active Visitors List with Overstay Tracking
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
              final totalCount = allDocs.length;
              final overstayCount = allDocs.where((d) => _isVisitorOverstaying(d.data())).length;

              final docs = allDocs.where((d) {
                final data = d.data();
                // Filter by overstay status if OVERSTAY filter chip is selected
                if (_campusFilter == 'OVERSTAY' && !_isVisitorOverstaying(data)) {
                  return false;
                }
                // Filter by text search query
                if (_campusSearchQuery.isEmpty) return true;
                final name = (data['visitorName'] ?? '').toString().toLowerCase();
                final flat = (data['flatNumber'] ?? '').toString().toLowerCase();
                final purpose = (data['purpose'] ?? '').toString().toLowerCase();
                return name.contains(_campusSearchQuery) ||
                    flat.contains(_campusSearchQuery) ||
                    purpose.contains(_campusSearchQuery);
              }).toList();

              return Column(
                children: [
                  // Filter Chips: All Active vs Overstaying - wrapped horizontally to prevent chip overflows on narrow phones
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text('All ($totalCount)'),
                            selected: _campusFilter == 'ALL',
                            onSelected: (_) => setState(() => _campusFilter = 'ALL'),
                            selectedColor: AppColors.primaryLight,
                            labelStyle: TextStyle(
                              color: _campusFilter == 'ALL' ? AppColors.primary : AppColors.textSecondary,
                              fontWeight: _campusFilter == 'ALL' ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ChoiceChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: _campusFilter == 'OVERSTAY'
                                      ? Colors.amber.shade900
                                      : (overstayCount > 0 ? Colors.orange.shade800 : Colors.grey),
                                ),
                                const SizedBox(width: 4),
                                Text('Overstaying ($overstayCount)'),
                              ],
                            ),
                            selected: _campusFilter == 'OVERSTAY',
                            onSelected: (_) => setState(() => _campusFilter = 'OVERSTAY'),
                            selectedColor: Colors.amber.shade100,
                            backgroundColor: Colors.grey.shade100,
                            labelStyle: TextStyle(
                              color: _campusFilter == 'OVERSTAY'
                                  ? Colors.amber.shade900
                                  : (overstayCount > 0 ? Colors.orange.shade900 : AppColors.textSecondary),
                              fontWeight: _campusFilter == 'OVERSTAY' ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),

                  // Content: Empty State or Visitor Cards List
                  Expanded(
                    child: docs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.door_front_door_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(
                                  _campusSearchQuery.isNotEmpty
                                      ? 'No active visitors matching "$_campusSearchQuery"'
                                      : (_campusFilter == 'OVERSTAY'
                                          ? 'No overstaying visitors currently inside campus'
                                          : 'No visitors currently inside campus'),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _campusFilter == 'OVERSTAY'
                                      ? 'All visitors are currently within acceptable time limits.'
                                      : 'When guests check in at the gate, they will appear here.',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: docs.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data();
                              final name = data['visitorName'] ?? 'Visitor';
                              final phone = (data['phone'] ?? '').toString().trim();
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

                              final isWarning = _isVisitorOverstaying(data);
                              final isCritical = _isVisitorOverstayCritical(data);

                              // Visual card styling based on overstay status
                              Color cardBorderColor = AppColors.border;
                              Color cardBgColor = Colors.white;
                              if (isCritical) {
                                cardBorderColor = Colors.red.shade400;
                                cardBgColor = const Color(0xFFFFF1F2);
                              } else if (isWarning) {
                                cardBorderColor = Colors.amber.shade500;
                                cardBgColor = const Color(0xFFFFFBEB);
                              }

                              // Duration / Overstay Status Badge Pill
                              Widget durationBadge;
                              if (isCritical) {
                                durationBadge = Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.red.shade400),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.warning_rounded, size: 12, color: Colors.red.shade900),
                                      const SizedBox(width: 4),
                                      Text(
                                        'CRITICAL OVERSTAY: $durationStr',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                                      ),
                                    ],
                                  ),
                                );
                              } else if (isWarning) {
                                durationBadge = Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber.shade400),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.schedule_rounded, size: 12, color: Colors.amber.shade900),
                                      const SizedBox(width: 4),
                                      Text(
                                        'OVERSTAY: $durationStr',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                durationBadge = Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySurface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: AppColors.primaryBorder),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.timer_outlined, size: 12, color: AppColors.primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        durationStr.isNotEmpty ? durationStr : 'Inside',
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final photoUrl = data['photoUrl']?.toString();

                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cardBgColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cardBorderColor, width: isCritical ? 1.5 : 1.0),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (photoUrl != null && photoUrl.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: Image.network(
                                          photoUrl,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => CircleAvatar(
                                            radius: 22,
                                            backgroundColor: AppColors.primaryLight,
                                            child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
                                          ),
                                        ),
                                      )
                                    else
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: AppColors.primaryLight,
                                        child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
                                      ),
                                    const SizedBox(width: 10),
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
                                            spacing: 8,
                                            runSpacing: 2,
                                            children: [
                                              Text(purpose, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                              if (phone.isNotEmpty) Text('•  $phone', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                              if (vehicle.isNotEmpty) Text('•  🚗 $vehicle', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          // Using Wrap instead of Row ensures duration badge and entry timestamp wrap gracefully on narrow phone screens without overflow stripes
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            children: [
                                              durationBadge,
                                              Text('In: $entryStr', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
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
                                              guardName: guardName,
                                              gateName: gateName,
                                              visitorData: data,
                                            );
                                            if (context.mounted) {
                                              AppFeedback.showSuccess(context, '$name checked out and resident notified.');
                                            }
                                          },
                                        ),
                                        if (phone.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              side: const BorderSide(color: AppColors.primary),
                                            ),
                                            icon: const Icon(Icons.phone_rounded, size: 13, color: AppColors.primary),
                                            label: const Text('Call', style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold)),
                                            onPressed: () async {
                                              final uri = Uri.parse('tel:$phone');
                                              if (await canLaunchUrl(uri)) {
                                                await launchUrl(uri);
                                              } else if (context.mounted) {
                                                AppFeedback.showError(context, 'Could not initiate call to $phone');
                                              }
                                            },
                                          ),
                                        ],
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
            // Concise label prevents line wrapping and overflow on small screens
            Text(
              'APPROVED',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade800),
            ),
          ],
        ),
      );
    } else if (status == 'ENTRY_LOGGED' || status == 'AUTO_APPROVED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.teal.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_rounded, size: 12, color: Colors.teal.shade700),
            const SizedBox(width: 4),
            Text(
              'STAFF',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
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
              'DENIED',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800),
            ),
          ],
        ),
      );
    } else if (status == 'LEAVE_AT_GATE') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.orange.shade400),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 12, color: Colors.orange.shade900),
            const SizedBox(width: 4),
            Text(
              '📦 LEAVE AT GATE',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade900),
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
              'AWAITING',
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
        // ─── Header & Action Bar ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Title and descriptive subtitle with overflow safety
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gate Parcel Log & Holding',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Search, filter, and track all incoming, held, and delivered packages',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Button to log incoming parcels held at gate security
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_box_rounded, size: 16),
                label: const Text('Log Parcel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _showLogParcelDialog(guardName, gateName),
              ),
            ],
          ),
        ),

        // ─── Search by Flat Number Field ─────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: TextField(
            controller: _parcelSearchCtrl,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search by Flat Number (e.g. C-102, 102, B-301)...',
              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textSecondary),
              suffixIcon: _parcelSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear search',
                      onPressed: () {
                        setState(() {
                          _parcelSearchCtrl.clear();
                          _parcelSearchQuery = '';
                        });
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.cardSurfaceSecondary,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            onChanged: (val) {
              setState(() {
                _parcelSearchQuery = val.trim();
              });
            },
          ),
        ),

        // ─── Live Stream & Filter Engine ─────────────────────────────────────
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: VisitorPassService.getAllParcelsStream(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text('Error loading parcels: ${snap.error}', style: const TextStyle(color: AppColors.error)),
                );
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allDocs = snap.data?.docs ?? [];

              // Compute aggregate counts across all status categories
              int heldCount = 0;
              int deliveredCount = 0;
              int confirmedCount = 0;
              int disputedCount = 0;

              for (final doc in allDocs) {
                final d = doc.data();
                final st = (d['status'] ?? '').toString();
                final isAck = d['residentAcknowledged'] == true;
                final isDisp = d['disputed'] == true || d['receiptStatus'] == 'NOT_RECEIVED';

                if (st == 'HELD_AT_GATE') {
                  heldCount++;
                } else if (isDisp) {
                  disputedCount++;
                } else if (isAck) {
                  confirmedCount++;
                } else if (st == 'COLLECTED') {
                  deliveredCount++;
                }
              }

              // Apply Search & Status Filters to the parcel stream
              final filteredDocs = allDocs.where((doc) {
                final d = doc.data();
                final rawFlat = (d['flatNumber'] ?? '').toString();
                final normFlat = FlatUtils.normalize(rawFlat).toLowerCase();
                final st = (d['status'] ?? '').toString();
                final isAck = d['residentAcknowledged'] == true;
                final isDisp = d['disputed'] == true || d['receiptStatus'] == 'NOT_RECEIVED';

                // 1. Flat Number Search filter (matches raw flat or normalized format)
                if (_parcelSearchQuery.isNotEmpty) {
                  final q = _parcelSearchQuery.toLowerCase().replaceAll('flat', '').trim();
                  final cleanRaw = rawFlat.toLowerCase().replaceAll('flat', '').trim();
                  if (!cleanRaw.contains(q) && !normFlat.contains(q)) {
                    return false;
                  }
                }

                // 2. Status Category filter
                switch (_parcelStatusFilter) {
                  case 'HELD_AT_GATE':
                    return st == 'HELD_AT_GATE';
                  case 'COLLECTED':
                    return st == 'COLLECTED' && !isAck && !isDisp;
                  case 'CONFIRMED':
                    return isAck;
                  case 'DISPUTED':
                    return isDisp;
                  case 'ALL':
                  default:
                    return true;
                }
              }).toList();

              return Column(
                children: [
                  // ─── Status Filter Horizontal Scroll Bar ───────────────────
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStatusFilterChip('ALL', 'All', allDocs.length, Colors.blueGrey),
                          const SizedBox(width: 8),
                          _buildStatusFilterChip('HELD_AT_GATE', 'Held at Gate', heldCount, Colors.amber.shade800),
                          const SizedBox(width: 8),
                          _buildStatusFilterChip('COLLECTED', 'Handed Over', deliveredCount, AppColors.primary),
                          const SizedBox(width: 8),
                          _buildStatusFilterChip('CONFIRMED', 'Receipt Confirmed', confirmedCount, AppColors.success),
                          const SizedBox(width: 8),
                          _buildStatusFilterChip('DISPUTED', 'Disputed', disputedCount, AppColors.error),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),

                  // ─── Filtered Parcels List View ────────────────────────────
                  Expanded(
                    child: filteredDocs.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.textMuted.withValues(alpha: 0.5)),
                                  const SizedBox(height: 12),
                                  Text(
                                    _parcelSearchQuery.isNotEmpty
                                        ? 'No parcels found for Flat "$_parcelSearchQuery"'
                                        : 'No parcels found under selected filter',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textSecondary),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _parcelSearchQuery.isNotEmpty
                                        ? 'Check the flat number format or clear the search.'
                                        : 'Parcels logged or delivered will appear here.',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(14),
                            itemCount: filteredDocs.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final doc = filteredDocs[index];
                              final data = doc.data();
                              final flat = data['flatNumber'] ?? 'Unknown';
                              final provider = data['deliveryProvider'] ?? 'Courier';
                              final count = data['packetCount'] ?? 1;
                              final remarks = data['remarks'] ?? '';
                              final status = (data['status'] ?? '').toString();
                              final isAck = data['residentAcknowledged'] == true;
                              final isDisputed = data['disputed'] == true || data['receiptStatus'] == 'NOT_RECEIVED';

                              // Timestamps
                              final recvTime = (data['receivedAt'] as Timestamp?)?.toDate();
                              final recvTimeStr = recvTime != null ? DateFormat('dd MMM, hh:mm a').format(recvTime) : 'Recent';
                              final colTime = (data['collectedAt'] as Timestamp?)?.toDate();
                              final colTimeStr = colTime != null ? DateFormat('dd MMM, hh:mm a').format(colTime) : null;
                              final ackTime = (data['acknowledgedAt'] as Timestamp?)?.toDate();
                              final ackTimeStr = ackTime != null ? DateFormat('dd MMM, hh:mm a').format(ackTime) : null;

                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDisputed
                                        ? Colors.red.shade300
                                        : (isAck
                                            ? Colors.green.shade200
                                            : (status == 'HELD_AT_GATE' ? Colors.amber.shade300 : AppColors.border)),
                                    width: (isDisputed || isAck) ? 1.2 : 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Card Top Header: Flat badge, Provider, and Status badge
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Flat Number Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.primarySurface,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AppColors.primaryBorder),
                                          ),
                                          child: Text(
                                            'Flat $flat',
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Package Count & Provider
                                        Expanded(
                                          child: Text(
                                            '$count Packet(s) • $provider',
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Status Badge Pill
                                        _buildParcelCardStatusBadge(status: status, isAck: isAck, isDisputed: isDisputed),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    // Reception details
                                    Row(
                                      children: [
                                        const Icon(Icons.door_sliding_outlined, size: 14, color: AppColors.textMuted),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'Received: $recvTimeStr at ${data['gateName'] ?? 'Main Gate'} (${data['guardName'] ?? 'Security'})',
                                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),

                                    // Handover / Delivery details (if collected)
                                    if (colTimeStr != null) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.outbox_rounded, size: 14, color: AppColors.textMuted),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Handed over: $colTimeStr to ${data['collectedBy'] ?? 'Resident'}',
                                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],

                                    // Resident Acknowledgment details (if confirmed)
                                    if (isAck) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.verified_rounded, size: 14, color: Colors.green.shade700),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              ackTimeStr != null
                                                  ? 'Confirmed by resident on $ackTimeStr'
                                                  : 'Receipt confirmed by resident',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],

                                    // Dispute details (if reported not received)
                                    if (isDisputed) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.red.shade200),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade700),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                data['disputeReason']?.toString() ?? 'Resident reported package NOT received',
                                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade800),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // Remarks if provided
                                    if (remarks.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Note: $remarks',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                                      ),
                                    ],

                                    // Hand Over Action Button (only if parcel is still held at gate)
                                    if (status == 'HELD_AT_GATE') ...[
                                      const SizedBox(height: 10),
                                      // Full width button prevents overflow on narrow screen displays and improves touch accessibility for gate security
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.success,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: const Icon(Icons.check_rounded, size: 16),
                                          label: const Text('Hand Over to Resident (Enter OTP)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                          onPressed: () {
                                            final parsedCount = count is int ? count : (int.tryParse(count.toString()) ?? 1);
                                            // Open OTP verification modal requiring guard to enter resident's 4-digit pickup code
                                            _showHandoverOtpDialog(
                                              parcelDocId: doc.id,
                                              flatNumber: flat,
                                              provider: provider,
                                              packetCount: parsedCount,
                                              guardName: guardName,
                                              gateName: gateName,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Helper widget to build selectable status filter chips with live counts
  Widget _buildStatusFilterChip(String filterKey, String label, int count, Color activeColor) {
    final isSelected = _parcelStatusFilter == filterKey;
    return InkWell(
      onTap: () {
        setState(() {
          _parcelStatusFilter = filterKey;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.25) : AppColors.cardSurfaceSecondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper widget to render status pill on each parcel card
  Widget _buildParcelCardStatusBadge({
    required String status,
    required bool isAck,
    required bool isDisputed,
  }) {
    if (status == 'HELD_AT_GATE') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Text(
          'HELD AT GATE',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.brown.shade800),
        ),
      );
    } else if (isDisputed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 11, color: Colors.red.shade800),
            const SizedBox(width: 3),
            Text(
              'DISPUTED',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade900),
            ),
          ],
        ),
      );
    } else if (isAck) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 11, color: Colors.green.shade800),
            const SizedBox(width: 3),
            Text(
              'CONFIRMED',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade900),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blue.shade300),
        ),
        child: Text(
          'DELIVERED',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
        ),
      );
    }
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

        // Emergency & Society Helplines Quick Dial
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.phone_in_talk_rounded, color: Colors.red.shade800, size: 16),
                  const SizedBox(width: 6),
                  // Expanded ensures the emergency intercom header text never causes horizontal overflow
                  const Expanded(
                    child: Text(
                      'Emergency Helplines & Intercom',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.error),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildHelplineChip('Police: 112', '112'),
                  _buildHelplineChip('Fire: 101', '101'),
                  _buildHelplineChip('Ambulance: 108', '108'),
                  _buildHelplineChip('Lift Helpline', '1800120120'),
                  _buildHelplineChip('Estate Office', '9876543210'),
                ],
              ),
            ],
          ),
        ),

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
                              Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$occupantType • $phone',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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

  Widget _buildHelplineChip(String label, String phone) {
    return ActionChip(
      avatar: const Icon(Icons.call_rounded, size: 13, color: AppColors.primary),
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.border),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: () async {
        final uri = Uri.parse('tel:$phone');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
    );
  }

  // Detail row with safe layout: Expanded value ensures long text (e.g. visitor names, vehicles) never overflows
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}


