import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/society_config.dart';
import '../services/visitor_pass_service.dart';
import '../services/push_notification_manager.dart';
import '../utils/flat_utils.dart';
import '../widgets/app_feedback.dart';

// ============================================================================
// MYGATE-STYLE FULL-SCREEN VISITOR CLEARANCE POPOUT SCREEN
// ============================================================================
// Provides a full-screen, high-priority popout overlay modeled after MyGate
// with frosted glass background, continuous doorbell ringtone audio,
// visitor photo, headline, and 3 circular action buttons:
// 1. Deny (Red)
// 2. Leave At Gate (White with package icon - automatically creates parcel entry)
// 3. Approve (Green)
// ============================================================================

class VisitorPopoutDialog extends StatefulWidget {
  final Map<String, dynamic> notifData;
  final String? notifDocId;
  final bool playRingtone;

  const VisitorPopoutDialog({
    super.key,
    required this.notifData,
    this.notifDocId,
    this.playRingtone = true,
  });

  /// Displays the full-screen visitor popout dialog over the current context.
  static Future<void> show(
    BuildContext context,
    Map<String, dynamic> notifData, {
    String? notifDocId,
    bool playRingtone = true,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      useSafeArea: false,
      builder: (ctx) => VisitorPopoutDialog(
        notifData: notifData,
        notifDocId: notifDocId,
        playRingtone: playRingtone,
      ),
    );
  }

  @override
  State<VisitorPopoutDialog> createState() => _VisitorPopoutDialogState();
}

class _VisitorPopoutDialogState extends State<VisitorPopoutDialog> {
  AudioPlayer? _audioPlayer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _visitorSub;
  String? _currentApproval;
  String? _visitorDocId;
  bool _isActionLoading = false;

  late String _visitorName;
  late String _flatNumber;
  late String _purpose;
  late String _gateName;
  String? _phone;
  String? _vehicleNumber;
  String? _deliveryApp;
  String? _photoUrl;
  String? _pickupOtp;
  bool _isDelivery = false;

  @override
  void initState() {
    super.initState();
    _extractNotificationMetadata();
    _initRingtone();
    _dismissSystemNotification();
    _resolveAndListenVisitor();
  }

  void _extractNotificationMetadata() {
    final notif = widget.notifData;
    final extra = notif['extraData'] is Map ? Map<String, dynamic>.from(notif['extraData']) : <String, dynamic>{};

    _visitorDocId = notif['visitorDocId']?.toString() ?? extra['visitorDocId']?.toString();
    _currentApproval = notif['approvalStatus']?.toString() ?? extra['approvalStatus']?.toString() ?? 'PENDING';
    _pickupOtp = notif['pickupOtp']?.toString() ?? extra['pickupOtp']?.toString();

    // Parse visitor name
    String rawName = notif['visitorName']?.toString() ?? extra['visitorName']?.toString() ?? '';
    if (rawName.isEmpty) {
      final title = (notif['title'] ?? '').toString();
      if (title.startsWith('Visitor At Gate: ')) {
        rawName = title.replaceFirst('Visitor At Gate: ', '').trim();
      } else if (title.startsWith('Pre-approved Guest Arrived: ')) {
        rawName = title.replaceFirst('Pre-approved Guest Arrived: ', '').trim();
      } else {
        rawName = 'Visitor';
      }
    }
    _visitorName = rawName;

    // Flat number
    _flatNumber = notif['flatNumber']?.toString() ?? extra['flatNumber']?.toString() ?? '';

    // Purpose & Delivery App
    _purpose = notif['purpose']?.toString() ?? extra['purpose']?.toString() ?? 'Guest / Personal';
    _deliveryApp = notif['deliveryApp']?.toString() ?? extra['deliveryApp']?.toString();
    _isDelivery = notif['isDelivery'] == true ||
        extra['isDelivery'] == true ||
        _purpose.toLowerCase().contains('delivery') ||
        _purpose.toLowerCase().contains('courier') ||
        (_deliveryApp != null && _deliveryApp!.isNotEmpty);

    // Gate Name
    _gateName = notif['gateName']?.toString() ?? extra['gateName']?.toString() ?? 'Main Gate';

    // Phone & Vehicle
    _phone = notif['phone']?.toString() ?? extra['phone']?.toString();
    _vehicleNumber = notif['vehicleNumber']?.toString() ?? extra['vehicleNumber']?.toString();
    _photoUrl = notif['photoUrl']?.toString() ?? extra['photoUrl']?.toString();
  }

  Future<void> _initRingtone() async {
    // Only play doorbell ringtone if requested and status is still pending visitor gate clearance
    if (!widget.playRingtone || _currentApproval != 'PENDING') return;

    try {
      final player = AudioPlayer();
      _audioPlayer = player;

      // Configure audio attributes specifically for notification ringtones on mobile
      await player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
        ),
      );

      // Pre-set the audio asset source first before configuring looping to avoid Android MediaPlayer error -38
      await player.setSource(AssetSource('audio/cell_phone_ring_std.mp3'));
      await player.setReleaseMode(ReleaseMode.loop);
      await player.resume();
    } catch (e) {
      debugPrint('[VisitorPopoutDialog] Ringtone audio playback note: $e');
    }
  }

  void _stopRingtone() {
    if (_audioPlayer != null) {
      _audioPlayer!.stop().catchError((_) {});
      _audioPlayer!.dispose().catchError((_) {});
      _audioPlayer = null;
    }
  }

  void _dismissSystemNotification() {
    PushNotificationManager.cancelNotification(widget.notifDocId ?? '', _visitorDocId);
  }

  Future<void> _resolveAndListenVisitor() async {
    // If visitorDocId is already present, bind snapshot stream immediately
    if (_visitorDocId != null && _visitorDocId!.isNotEmpty) {
      _bindVisitorStream(_visitorDocId!);
      return;
    }

    // Resolve visitorDocId from Firestore by querying matching checked-in visitor
    try {
      final snap = await FirebaseFirestore.instance
          .collection('visitors')
          .where('flatNumber', isEqualTo: FlatUtils.normalize(_flatNumber))
          .get();

      if (snap.docs.isNotEmpty) {
        final matches = snap.docs.where((d) {
          final data = d.data();
          final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
          final vStatus = data['status']?.toString();
          return vStatus == 'CHECKED_IN' &&
              (vN == _visitorName.trim().toLowerCase() ||
                  vN.contains(_visitorName.trim().toLowerCase()) ||
                  _visitorName.trim().toLowerCase().contains(vN));
        }).toList();

        if (matches.isNotEmpty) {
          _visitorDocId = matches.first.id;
          _photoUrl ??= matches.first.data()['photoUrl']?.toString();
          _bindVisitorStream(_visitorDocId!);
          return;
        }

        final checkedIn = snap.docs.where((d) => d.data()['status'] == 'CHECKED_IN').toList();
        if (checkedIn.isNotEmpty) {
          _visitorDocId = checkedIn.last.id;
          _photoUrl ??= checkedIn.last.data()['photoUrl']?.toString();
          _bindVisitorStream(_visitorDocId!);
        }
      }
    } catch (_) {}
  }

  void _bindVisitorStream(String docId) {
    _visitorSub?.cancel();
    _visitorSub = FirebaseFirestore.instance.collection('visitors').doc(docId).snapshots().listen((snap) {
      if (snap.exists && mounted) {
        final liveApproval = (snap.data()?['approvalStatus'] ?? '').toString().toUpperCase();
        final liveOtp = snap.data()?['pickupOtp']?.toString();
        if (liveApproval == 'APPROVED' || liveApproval == 'DENIED' || liveApproval == 'LEAVE_AT_GATE') {
          _stopRingtone();
          if (_currentApproval != liveApproval || (_pickupOtp == null && liveOtp != null && liveOtp.isNotEmpty)) {
            setState(() {
              _currentApproval = liveApproval;
              if (liveOtp != null && liveOtp.isNotEmpty) {
                _pickupOtp = liveOtp;
              }
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _stopRingtone();
    _visitorSub?.cancel();
    _dismissSystemNotification();
    super.dispose();
  }

  Future<void> _handleDeny() async {
    if (_isActionLoading || _currentApproval == 'APPROVED' || _currentApproval == 'DENIED' || _currentApproval == 'LEAVE_AT_GATE') return;

    _stopRingtone();
    setState(() => _isActionLoading = true);

    try {
      await VisitorPassService.denyVisitorEntry(
        visitorDocId: _visitorDocId,
        flatNumber: _flatNumber,
        visitorName: _visitorName,
        notifDocId: widget.notifDocId,
      );
      if (mounted) {
        setState(() {
          _currentApproval = 'DENIED';
          _isActionLoading = false;
        });
        AppFeedback.showSuccess(context, 'Entry denied for $_visitorName.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionLoading = false);
        AppFeedback.showError(context, 'Failed to deny entry: $e');
      }
    }
  }

  Future<void> _handleLeaveAtGate() async {
    if (_isActionLoading || _currentApproval == 'APPROVED' || _currentApproval == 'DENIED' || _currentApproval == 'LEAVE_AT_GATE') return;

    _stopRingtone();
    setState(() => _isActionLoading = true);

    try {
      // Execute leave at gate and retrieve the 4-digit pickup OTP
      final otp = await VisitorPassService.leaveAtGateVisitorEntry(
        visitorDocId: _visitorDocId,
        flatNumber: _flatNumber,
        visitorName: _visitorName,
        notifDocId: widget.notifDocId,
        deliveryApp: _deliveryApp,
        photoUrl: _photoUrl,
        gateName: _gateName,
        residentUid: FirebaseAuth.instance.currentUser?.uid,
      );
      if (mounted) {
        setState(() {
          _pickupOtp = otp;
          _currentApproval = 'LEAVE_AT_GATE';
          _isActionLoading = false;
        });
        AppFeedback.showSuccess(context, 'Delivery marked to leave at gate. Pickup OTP generated!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionLoading = false);
        AppFeedback.showError(context, 'Failed to update leave at gate: $e');
      }
    }
  }

  Future<void> _handleApprove() async {
    if (_isActionLoading || _currentApproval == 'APPROVED' || _currentApproval == 'DENIED' || _currentApproval == 'LEAVE_AT_GATE') return;

    _stopRingtone();
    setState(() => _isActionLoading = true);

    try {
      await VisitorPassService.approveVisitorEntry(
        visitorDocId: _visitorDocId,
        flatNumber: _flatNumber,
        visitorName: _visitorName,
        notifDocId: widget.notifDocId,
      );
      if (mounted) {
        setState(() {
          _currentApproval = 'APPROVED';
          _isActionLoading = false;
        });
        AppFeedback.showSuccess(context, 'Entry approved for $_visitorName.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isActionLoading = false);
        AppFeedback.showError(context, 'Failed to approve entry: $e');
      }
    }
  }

  Future<void> _callVisitor() async {
    if (_phone == null || _phone!.isEmpty) return;
    final uri = Uri.parse('tel:$_phone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) AppFeedback.showInfo(context, 'Phone: $_phone');
      }
    } catch (_) {
      if (mounted) AppFeedback.showInfo(context, 'Phone: $_phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isResolved = _currentApproval == 'APPROVED' ||
        _currentApproval == 'DENIED' ||
        _currentApproval == 'LEAVE_AT_GATE';

    // Headline generation
    String headline;
    if (_isDelivery) {
      final appName = _deliveryApp != null && _deliveryApp!.isNotEmpty ? _deliveryApp! : 'Delivery Executive';
      headline = '$appName is waiting at the $_gateName';
    } else if (_purpose.toLowerCase().contains('cab') || _purpose.toLowerCase().contains('taxi')) {
      headline = 'Cab ($_visitorName) is waiting at the $_gateName';
    } else {
      headline = '$_visitorName is waiting at the $_gateName';
    }

    // Top overlapping icon badge selection
    IconData badgeIcon;
    if (_isDelivery) {
      badgeIcon = Icons.delivery_dining_rounded;
    } else if (_purpose.toLowerCase().contains('cab') || _purpose.toLowerCase().contains('taxi')) {
      badgeIcon = Icons.local_taxi_rounded;
    } else if (_purpose.toLowerCase().contains('service') || _purpose.toLowerCase().contains('help')) {
      badgeIcon = Icons.handyman_rounded;
    } else {
      badgeIcon = Icons.person_rounded;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Frosted Glass Blur Backdrop
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.black.withValues(alpha: 0.78),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Main SafeArea Content
          SafeArea(
            child: Column(
              children: [
                // ─── Top Bar: Close Button & Society/Flat Label ─────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    children: [
                      // Circular Close '✕' Button
                      GestureDetector(
                        onTap: () {
                          _stopRingtone();
                          _dismissSystemNotification();
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.22),
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _flatNumber.isNotEmpty
                              ? 'Flat $_flatNumber • ${SocietyConfig.societyName}'
                              : SocietyConfig.societyName,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ─── Center MyGate Floating Card ────────────────────────────
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      children: [
                        // White Rounded Card
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 32),
                          padding: const EdgeInsets.fromLTRB(22, 44, 22, 24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Bold Headline
                              Text(
                                headline,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Visitor Info Details Row
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    // Visitor Photo Avatar
                                    _buildAvatar(),
                                    const SizedBox(width: 14),

                                    // Name, Phone Dialer, and Company/Purpose
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  _visitorName,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 15.5,
                                                    color: Color(0xFF0F172A),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (_phone != null && _phone!.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: _callVisitor,
                                                  child: Container(
                                                    padding: const EdgeInsets.all(5),
                                                    decoration: const BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: Color(0xFFDCFCE7),
                                                    ),
                                                    child: const Icon(
                                                      Icons.phone_rounded,
                                                      size: 14,
                                                      color: Color(0xFF16A34A),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),

                                          // Purpose or Delivery Brand Tag
                                          _buildPurposeBadge(),

                                          // Vehicle tag if registered
                                          if (_vehicleNumber != null && _vehicleNumber!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              '🚗 $_vehicleNumber',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Status Confirmation Banner when resolved
                              if (isResolved) ...[
                                const SizedBox(height: 18),
                                _buildResolvedBanner(),
                                const SizedBox(height: 14),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                  ),
                                  onPressed: () {
                                    _stopRingtone();
                                    _dismissSystemNotification();
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Overlapping Yellow Circular Top Badge
                        Positioned(
                          top: 0,
                          child: Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFFD54F),
                              border: Border.all(color: Colors.white, width: 3.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(badgeIcon, size: 34, color: const Color(0xFF1E293B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ─── Bottom Action Buttons: Deny, Leave At Gate, Approve ─────
                if (!isResolved)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Deny Button (Red Circle)
                          _buildActionButton(
                            icon: Icons.close_rounded,
                            label: 'Deny',
                            buttonColor: Colors.white,
                            borderColor: const Color(0xFFEF4444),
                            iconColor: const Color(0xFFEF4444),
                            onTap: _isActionLoading ? null : _handleDeny,
                          ),

                          // 2. Leave At Gate Button (White Circle with Box Icon)
                          // Strictly reserved for Delivery / Courier visitors; omitted for Guests & other visitors!
                          if (_isDelivery)
                            _buildActionButton(
                              icon: Icons.inventory_2_outlined,
                              label: 'Leave\nAt Gate',
                              buttonColor: Colors.white,
                              borderColor: const Color(0xFF334155),
                              iconColor: const Color(0xFF0F172A),
                              onTap: _isActionLoading ? null : _handleLeaveAtGate,
                            ),

                          // 3. Approve Button (Green Circle)
                          _buildActionButton(
                            icon: Icons.check_rounded,
                            label: 'Approve',
                            buttonColor: const Color(0xFF22C55E),
                            borderColor: const Color(0xFF22C55E),
                            iconColor: Colors.white,
                            onTap: _isActionLoading ? null : _handleApprove,
                          ),
                        ],
                      ),
                    ),
                  ),

                const Spacer(flex: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Image.network(
          _photoUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildFallbackAvatar(),
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 56,
              height: 56,
              color: Colors.grey.shade200,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        ),
      );
    }
    return _buildFallbackAvatar();
  }

  Widget _buildFallbackAvatar() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE2E8F0),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.person_rounded, color: Color(0xFF64748B), size: 30),
    );
  }

  Widget _buildPurposeBadge() {
    if (_deliveryApp != null && _deliveryApp!.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_shipping_rounded, size: 12, color: Colors.amber.shade900),
                const SizedBox(width: 4),
                Text(
                  _deliveryApp!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Text(
        _purpose,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildResolvedBanner() {
    if (_currentApproval == 'APPROVED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 18),
            const SizedBox(width: 6),
            Text(
              'Entry Approved',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    } else if (_currentApproval == 'DENIED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_rounded, color: Colors.red.shade700, size: 18),
            const SizedBox(width: 6),
            Text(
              'Entry Denied',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    } else if (_currentApproval == 'LEAVE_AT_GATE') {
      final otpToDisplay = _pickupOtp ?? '';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.shade400, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined, color: Colors.amber.shade900, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Package Left at Gate',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.shade900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            // Prominent Gate Pickup OTP Card
            if (otpToDisplay.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.shade200.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'GATE PICKUP OTP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Colors.brown.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          otpToDisplay,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          color: Colors.amber.shade900,
                          tooltip: 'Copy OTP',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: otpToDisplay));
                            AppFeedback.showSuccess(context, 'Pickup OTP $otpToDisplay copied to clipboard!');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Show this 4-digit code to gate security to collect your package.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.brown.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color buttonColor,
    required Color borderColor,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: buttonColor,
              border: Border.all(color: borderColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isActionLoading && onTap == null
                ? Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: iconColor,
                      ),
                    ),
                  )
                : Icon(icon, color: iconColor, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
