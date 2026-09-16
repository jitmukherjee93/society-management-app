import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../models/accounting_heads.dart';
import '../../constants/society_config.dart';
import '../../utils/app_formatters.dart';
import '../../services/billing_service.dart';
import '../../utils/flat_utils.dart';
import 'tabs/community_feed_tab.dart';
import '../../utils/storage_utils.dart';
import '../../services/notification_service.dart';
import '../../services/visitor_pass_service.dart';
import '../../services/push_notification_manager.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../widgets/document_preview_dialog.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/receipt_preview_dialog.dart';
import '../../models/notice_model.dart';
import '../../widgets/notices/two_column_notice_list.dart';
import '../../widgets/maintenance/maintenance_months_calendar.dart';

// ============================================================================
// RESIDENT PORTAL & SELF-SERVICE DASHBOARD
// ============================================================================
// This is the core resident experience for society members.
//
// Key Feature Modules:
// 1. Dues & Multi-Month Payments (Home Tab):
//    - Real-time monthly dues, progressive late fine calculation, and payment status.
//    - Multi-month advance payments (up to 12 consecutive months).
//    - UTR online submission and downloadable PDF maintenance receipts.
//
// 2. Security & Visitor Passes (Visitors Tab):
//    - 6-digit gate passcode generation (valid for 8 hours, single-use).
//    - 1-tap Approve / Deny actions for walk-in visitors and delivery agents at the gate.
//    - Campus entry/exit real-time logs.
//
// 3. Society Helpdesk & Complaints (Helpdesk Tab):
//    - Ticket creation for plumbing, electrical, civil, security, and cleanliness.
//    - Ticket tracking with photo attachments and admin resolution comments.
//
// 4. Community Notices & Feeds (Notices & Community Tabs):
//    - RWA circulars, AGM announcements, emergency notices, and community discussions.
// ============================================================================

/// Evaluates whether a given Firestore notification payload is addressed to the current logged-in resident.
bool _isNotificationForResident(Map<String, dynamic> data, User? user, [String? userFlat, String? fullFlat]) {
  if (user == null) return false;
  final userUid = user.uid;
  final userEmail = user.email?.toLowerCase() ?? '';
  final flatPrefix = userEmail.contains('@') ? userEmail.split('@').first.toUpperCase() : '';

  final targetRole = (data['targetRole'] ?? '').toString().toUpperCase();
  if (targetRole == 'ADMIN' || targetRole == 'GUARD') return false;

  final targetUid = data['targetUid']?.toString().toUpperCase();
  if (targetUid != null) {
    if (targetUid == userUid.toUpperCase()) return true;
    if (flatPrefix.isNotEmpty && targetUid == flatPrefix) return true;
    if (userFlat != null && userFlat.isNotEmpty && (targetUid == userFlat || targetUid.contains(userFlat))) return true;
    if (fullFlat != null && fullFlat.isNotEmpty && (targetUid == fullFlat || targetUid.contains(fullFlat))) return true;
  }

  final targetUids = (data['targetUids'] as List<dynamic>?)?.map((e) => e.toString().toUpperCase()).toList() ?? [];
  if (targetUids.isNotEmpty) {
    if (targetUids.contains(userUid.toUpperCase())) return true;
    if (flatPrefix.isNotEmpty && targetUids.contains(flatPrefix)) return true;
    if (userFlat != null && userFlat.isNotEmpty && targetUids.contains(userFlat)) return true;
    if (fullFlat != null && fullFlat.isNotEmpty && targetUids.contains(fullFlat)) return true;
  }

  final flatNum = (data['flatNumber'] ?? '').toString().toUpperCase();
  if (flatNum.isNotEmpty) {
    if (userFlat != null && userFlat.isNotEmpty && (flatNum == userFlat || flatNum.endsWith(userFlat) || flatNum.contains(userFlat))) return true;
    if (fullFlat != null && fullFlat.isNotEmpty && (flatNum == fullFlat || flatNum.endsWith(fullFlat) || flatNum.contains(fullFlat))) return true;
    if (flatPrefix.isNotEmpty && (flatNum == flatPrefix || flatNum.endsWith(flatPrefix))) return true;
  }

  if (targetRole == 'ALL' || targetRole == 'RESIDENT') {
    if (flatNum.isEmpty) return true;
  }

  return false;
}

/// Primary resident self-service portal screen.
class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  int _currentIndex = 0;
  String? _selectedMaintenanceMonth;
  Future<DocumentReference?>? _userDocRefFuture;
  bool _isWarningBannerCollapsed = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userEmail = user.email?.toLowerCase();
      final flatPrefix = userEmail?.contains('@') == true
          ? userEmail!.split('@').first.toLowerCase()
          : null;
      _userDocRefFuture = _resolveUserDocRef(user.uid, userEmail, flatPrefix);
    }

    // Register Push Notification Click Delegate for instant navigation/dialogs
    // When resident taps an in-app heads-up push banner or system notification, route directly to the target modal or tab
    PushNotificationManager.instance.onNotificationClick = (ctx, payload) {
      NotificationsTab.handleNotificationClick(
        context: ctx,
        notif: payload.extraData,
        docId: payload.id,
        onNavigateTab: (idx, [monthPayload]) {
          setState(() {
            _currentIndex = idx;
            if (monthPayload != null && idx == 4) {
              _selectedMaintenanceMonth = monthPayload;
            }
          });
        },
      );
    };

    // Register automatic incoming visitor approval modal trigger with custom ringtone
    // When a guard checks in a walk-in visitor while resident is in-app, automatically present the modal with ringtone
    PushNotificationManager.instance.onIncomingVisitorApproval = (ctx, payload) {
      final targetContext = PushNotificationManager.navigatorKey.currentContext ?? ctx;
      if (targetContext.mounted) {
        NotificationsTab.showVisitorNotificationDialog(
          targetContext,
          payload.extraData,
          notifDocId: payload.id,
          playRingtone: true,
        );
      }
    };
  }

  @override
  void dispose() {
    // Clean up push notification callbacks when dashboard is unmounted
    if (PushNotificationManager.instance.onNotificationClick != null) {
      PushNotificationManager.instance.onNotificationClick = null;
    }
    if (PushNotificationManager.instance.onIncomingVisitorApproval != null) {
      PushNotificationManager.instance.onIncomingVisitorApproval = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Please log in.')));
    }

    return FutureBuilder<DocumentReference?>(
      future: _userDocRefFuture,
      builder: (context, docRefSnap) {
        final docRef = docRefSnap.data;
        if (docRef == null) {
          return _buildDashboardScaffold(context, user, null, null, null, null);
        }
        return StreamBuilder<DocumentSnapshot>(
          stream: docRef.snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
            final userFlat = (userData['flatNumber'] ?? '').toString().trim().toUpperCase();
            final blockStr = (userData['block'] ?? '').toString().trim().toUpperCase();
            final fullFlat = (blockStr.isNotEmpty && !userFlat.startsWith(blockStr))
                ? '$blockStr-$userFlat'
                : userFlat;

            return _buildDashboardScaffold(context, user, userFlat, fullFlat, userData, docRef);
          },
        );
      },
    );
  }

  Widget _buildDashboardScaffold(
    BuildContext context,
    User user,
    String? userFlat,
    String? fullFlat, [
    Map<String, dynamic>? userData,
    DocumentReference? userDocRef,
  ]) {
    final uData = userData ?? {};
    final personalEmail = (uData['personalEmail'] ?? '').toString().trim();
    final docEmail = (uData['email'] ?? '').toString().trim().toLowerCase();
    final authEmail = (user.email ?? '').trim().toLowerCase();

    final bool hasValidPersonalEmail = personalEmail.isNotEmpty &&
        personalEmail.contains('@') &&
        !personalEmail.toLowerCase().endsWith('@ramkrishnapuram.com');

    final bool isDefaultSocietyEmail = authEmail.endsWith('@ramkrishnapuram.com') ||
        docEmail.endsWith('@ramkrishnapuram.com') ||
        docEmail.isEmpty;

    final bool showEmailWarning = !hasValidPersonalEmail && isDefaultSocietyEmail;
    final bool isDefaultPassword = (uData['defaultPasswordRevoked'] != true) &&
        ((uData['isDefaultPassword'] ?? true) == true);
    final bool showPasswordRevocationWarning = !showEmailWarning && isDefaultPassword;
    final defaultLoginId = authEmail.isNotEmpty
        ? authEmail
        : (docEmail.isNotEmpty
            ? docEmail
            : '${(fullFlat ?? userFlat ?? 'flat').toLowerCase()}@ramkrishnapuram.com');

    final pages = [
      HomeTab(
        onNavigateTab: (idx, [payload]) {
          setState(() {
            _currentIndex = idx;
            if (payload != null && idx == 4) {
              _selectedMaintenanceMonth = payload;
            }
          });
        },
      ),
      const CommunityFeedTab(),
      NotificationsTab(
        userFlat: userFlat,
        fullFlat: fullFlat,
        onNavigateTab: (idx, [payload]) {
          setState(() {
            _currentIndex = idx;
            if (payload != null && idx == 4) {
              _selectedMaintenanceMonth = payload;
            }
          });
        },
      ),
      ResidentHelpdeskTab(userFlat: userFlat),
      MaintenanceTab(
        key: ValueKey(_selectedMaintenanceMonth ?? 'maint_default'),
        initialSelectedMonth: _selectedMaintenanceMonth,
      ),
    ];

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('targetRole', whereIn: ['RESIDENT', 'ALL'])
          .limit(100)
          .snapshots(),
      builder: (context, notifSnap) {
        final docs = (notifSnap.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _isNotificationForResident(data, user, userFlat, fullFlat);
        }).toList();
        final notifCount = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['isRead'] != true;
        }).length;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 1,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.apartment_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Resident Portal',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.slate900),
                    ),
                    if (fullFlat != null && fullFlat.isNotEmpty)
                      Text(
                        'Flat $fullFlat',
                        style: const TextStyle(fontSize: 11, color: AppColors.slate500, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.shield_outlined, color: AppColors.slate700),
                tooltip: 'Account & Security Settings',
                onPressed: () => _showUpdateEmailDialog(
                  context,
                  user,
                  userDocRef,
                  uData,
                  defaultLoginId,
                ),
              ),
              IconButton(
                icon: Badge(
                  isLabelVisible: notifCount > 0,
                  backgroundColor: AppColors.error,
                  label: Text('$notifCount', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  child: const Icon(Icons.notifications_outlined, color: AppColors.slate700),
                ),
                tooltip: 'Alerts',
                onPressed: () => setState(() => _currentIndex = 2),
              ),
              if (MediaQuery.sizeOf(context).width < 600)
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
                  tooltip: 'Log out',
                  onPressed: () async {
                    final confirm = await AppDialog.show<bool>(
                      context: context,
                      title: 'Sign Out',
                      subtitle: 'Are you sure you want to log out?',
                      icon: Icons.logout_rounded,
                      iconColor: AppColors.error,
                      iconBgColor: AppColors.errorSurface,
                      body: const Text('You will need to sign in again to access your resident portal.'),
                      actions: [
                        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Sign Out'),
                        ),
                      ],
                    );
                    if (confirm == true) {
                      await FirebaseAuth.instance.signOut();
                    }
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    onPressed: () async {
                      final confirm = await AppDialog.show<bool>(
                        context: context,
                        title: 'Sign Out',
                        subtitle: 'Are you sure you want to log out?',
                        icon: Icons.logout_rounded,
                        iconColor: AppColors.error,
                        iconBgColor: AppColors.errorSurface,
                        body: const Text('You will need to sign in again to access your resident portal.'),
                        actions: [
                          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Sign Out'),
                          ),
                        ],
                      );
                      if (confirm == true) {
                        await FirebaseAuth.instance.signOut();
                      }
                    },
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (showEmailWarning)
                _buildEmailWarningBanner(
                  context,
                  user,
                  defaultLoginId,
                  userDocRef,
                  uData,
                )
              else if (showPasswordRevocationWarning)
                _buildPasswordRevocationBanner(
                  context,
                  user,
                  defaultLoginId,
                  userDocRef,
                  uData,
                ),
              Expanded(
                child: IndexedStack(index: _currentIndex, children: pages),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            indicatorColor: AppColors.primarySurface,
            onDestinationSelected: (index) => setState(() => _currentIndex = index),
            destinations: [
              const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.primary), label: 'Home'),
              const NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum, color: AppColors.primary), label: 'Community'),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: notifCount > 0,
                  backgroundColor: AppColors.error,
                  label: Text('$notifCount'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: const Icon(Icons.notifications, color: AppColors.primary),
                label: 'Alerts',
              ),
              const NavigationDestination(icon: Icon(Icons.support_agent_outlined), selectedIcon: Icon(Icons.support_agent, color: AppColors.primary), label: 'Helpdesk'),
              const NavigationDestination(icon: Icon(Icons.payment_outlined), selectedIcon: Icon(Icons.payment, color: AppColors.primary), label: 'Maintenance'),
            ],
          ),
          floatingActionButton: _currentIndex == 0
              ? FloatingActionButton.extended(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PreApproveVisitorScreen(userFlat: userFlat),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add_rounded, size: 20),
                  label: const Text('Pre-approve Visitor', style: TextStyle(fontWeight: FontWeight.w600)),
                )
              : null,
        );
      },
    );
  }

  Widget _buildEmailWarningBanner(
    BuildContext context,
    User user,
    String defaultLoginId,
    DocumentReference? userDocRef,
    Map<String, dynamic> userData,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF87171), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: _isWarningBannerCollapsed
          ? Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFDC2626),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Action Required: Update email address ($defaultLoginId)',
                    style: const TextStyle(
                      color: Color(0xFF991B1B),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _showUpdateEmailDialog(
                    context,
                    user,
                    userDocRef,
                    userData,
                    defaultLoginId,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Update',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF991B1B)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Expand details',
                  onPressed: () => setState(() => _isWarningBannerCollapsed = false),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFDC2626),
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Action Required: Update Email Address',
                        style: TextStyle(
                          color: Color(0xFF991B1B),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Color(0xFF991B1B)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Collapse banner',
                      onPressed: () => setState(() => _isWarningBannerCollapsed = true),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 27),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            color: Color(0xFF7F1D1D),
                            fontSize: 11,
                            height: 1.3,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Update your email to secure your account and revoke default password (Password@123). Login ID will update from ',
                            ),
                            TextSpan(
                              text: defaultLoginId,
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.mark_email_read_outlined, size: 13),
                          label: const Text(
                            'Update Email & Secure Account',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 26),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => _showUpdateEmailDialog(
                            context,
                            user,
                            userDocRef,
                            userData,
                            defaultLoginId,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPasswordRevocationBanner(
    BuildContext context,
    User user,
    String defaultLoginId,
    DocumentReference? userDocRef,
    Map<String, dynamic> userData,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCD34D), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: _isWarningBannerCollapsed
          ? Row(
              children: [
                const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFFD97706),
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Security Alert: Default password active',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => _showUpdateEmailDialog(
                    context,
                    user,
                    userDocRef,
                    userData,
                    defaultLoginId,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD97706),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Secure',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Color(0xFF92400E)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Expand details',
                  onPressed: () => setState(() => _isWarningBannerCollapsed = false),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF3C7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFFD97706),
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Security Alert: Default Password Active',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: Color(0xFF92400E)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Collapse banner',
                      onPressed: () => setState(() => _isWarningBannerCollapsed = true),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 27),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your account is using default password (Password@123). Set a private password or request a reset email to secure your account.',
                        style: TextStyle(
                          color: Color(0xFF78350F),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.lock_reset_rounded, size: 13),
                          label: const Text(
                            'Change Password & Secure',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD97706),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(0, 26),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => _showUpdateEmailDialog(
                            context,
                            user,
                            userDocRef,
                            userData,
                            defaultLoginId,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showUpdateEmailDialog(
    BuildContext context,
    User user,
    DocumentReference? userDocRef,
    Map<String, dynamic> userData,
    String defaultLoginId,
  ) async {
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final initialPersonal = (userData['personalEmail'] ?? userData['email'] ?? '').toString().trim();
    if (initialPersonal.isNotEmpty && !initialPersonal.toLowerCase().endsWith('@ramkrishnapuram.com')) {
      emailCtrl.text = initialPersonal;
    }

    final bool isDefaultPasswordRevoked = userData['defaultPasswordRevoked'] == true;
    bool isSaving = false;
    bool triggerPasswordReset = !isDefaultPasswordRevoked;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDefaultPasswordRevoked ? const Color(0xFFDEF7EC) : const Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDefaultPasswordRevoked ? Icons.shield_rounded : Icons.security,
                  color: isDefaultPasswordRevoked ? const Color(0xFF03543F) : const Color(0xFFDC2626),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Account Security & Email',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width.clamp(0.0, 480.0),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Login ID: $defaultLoginId',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          const SizedBox(height: 3),
                          if (isDefaultPasswordRevoked)
                            const Row(
                              children: [
                                Icon(Icons.check_circle, color: Color(0xFF059669), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Private Password Active',
                                  style: TextStyle(color: Color(0xFF059669), fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                              ],
                            )
                          else
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Initial Password: Password@123 (Default - Should be revoked)',
                                  style: TextStyle(color: Color(0xFFDC2626), fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Your registered personal email address is used to sign in, receive society notices, and reset your password.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate700, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Personal Email Address *',
                        hintText: 'e.g. name@gmail.com',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Please enter your email address';
                        if (!RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                          return 'Please enter a valid email address';
                        }
                        if (val.toLowerCase().endsWith('@ramkrishnapuram.com')) {
                          return 'Please enter your personal email address, not the society placeholder';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: triggerPasswordReset,
                      onChanged: (val) => setDS(() => triggerPasswordReset = val ?? false),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text(
                        'Send password reset email to verify email address & set password',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Dispatches an official password reset link directly to your inbox.',
                        style: TextStyle(fontSize: 11, color: AppColors.slate500),
                      ),
                      activeColor: const Color(0xFFDC2626),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(triggerPasswordReset ? Icons.send_rounded : Icons.check_circle_outline, size: 16),
              label: Text(triggerPasswordReset ? 'Save & Send Reset Email' : 'Save & Update'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDS(() => isSaving = true);
                      final newEmail = emailCtrl.text.trim().toLowerCase();

                      try {
                        final willRevokeDefault = triggerPasswordReset;

                        // 1. Update Firestore user doc
                        final updates = <String, dynamic>{
                          'email': newEmail,
                          'personalEmail': newEmail,
                          'emailUpdatedAt': FieldValue.serverTimestamp(),
                        };
                        if (willRevokeDefault) {
                          updates['isDefaultPassword'] = false;
                          updates['defaultPasswordRevoked'] = true;
                        }

                        if (userDocRef != null) {
                          await userDocRef.update(updates);
                        } else {
                          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
                            updates,
                            SetOptions(merge: true),
                          );
                        }

                        // 2. Email update / verification in Firebase Auth
                        if (newEmail != (user.email ?? '').toLowerCase()) {
                          try {
                            await user.verifyBeforeUpdateEmail(newEmail);
                          } catch (authErr) {
                            debugPrint('verifyBeforeUpdateEmail note: $authErr');
                          }
                        }

                        // 3. Trigger password reset email if requested
                        bool resetEmailSent = false;
                        if (triggerPasswordReset) {
                          try {
                            await FirebaseAuth.instance.sendPasswordResetEmail(email: newEmail);
                            resetEmailSent = true;
                          } on FirebaseAuthException catch (resetErr) {
                            debugPrint('sendPasswordResetEmail note: $resetErr');
                            if (resetErr.code != 'user-not-found') {
                              throw Exception('Password reset email error: ${resetErr.message ?? resetErr.code}');
                            }
                          }
                        }

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          String msg = 'Email updated to $newEmail!';
                          if (resetEmailSent) {
                            msg = 'Password reset email sent to $newEmail! Please check your inbox (and Spam/Promotions).';
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green.shade700,
                              content: Text(msg),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } catch (e) {
                        setDS(() => isSaving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.red.shade700,
                              content: Text('Error: $e'),
                            ),
                          );
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
    emailCtrl.dispose();
  }
}

Future<DocumentReference?> _resolveUserDocRef(String uid, String? userEmail, String? flatPrefix) async {
  final usersRef = FirebaseFirestore.instance.collection('users');

  // 1. Direct doc by UID
  final directDoc = await usersRef.doc(uid).get();
  if (directDoc.exists) return usersRef.doc(uid);

  // 2. Query by email
  if (userEmail != null && userEmail.isNotEmpty) {
    final emailSnap = await usersRef.where('email', isEqualTo: userEmail).limit(1).get();
    if (emailSnap.docs.isNotEmpty) return emailSnap.docs.first.reference;
  }

  // 3. Query by personalEmail
  if (userEmail != null && userEmail.isNotEmpty) {
    final pEmailSnap = await usersRef.where('personalEmail', isEqualTo: userEmail).limit(1).get();
    if (pEmailSnap.docs.isNotEmpty) return pEmailSnap.docs.first.reference;
  }

  // 4. Query by username
  if (userEmail != null && userEmail.isNotEmpty) {
    final userSnap = await usersRef.where('username', isEqualTo: userEmail).limit(1).get();
    if (userSnap.docs.isNotEmpty) return userSnap.docs.first.reference;
  }

  // 5. Query by flatPrefix / flatNumber
  if (flatPrefix != null && flatPrefix.isNotEmpty) {
    final flatSnap = await usersRef.where('flatNumber', isEqualTo: flatPrefix.toUpperCase()).limit(1).get();
    if (flatSnap.docs.isNotEmpty) return flatSnap.docs.first.reference;

    final docByFlat = await usersRef.doc(flatPrefix.toUpperCase()).get();
    if (docByFlat.exists) return usersRef.doc(flatPrefix.toUpperCase());
  }

  return usersRef.doc(uid);
}

class HomeTab extends StatefulWidget {
  final Function(int, [String?])? onNavigateTab;
  const HomeTab({super.key, this.onNavigateTab});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // Store the future so it's computed ONCE and never re-runs on rebuild
  late Future<DocumentReference?> _docRefFuture;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userEmail = user.email?.toLowerCase();
      final flatPrefix = userEmail?.contains('@') == true
          ? userEmail!.split('@').first.toLowerCase()
          : null;
      _docRefFuture = _resolveUserDocRef(user.uid, userEmail, flatPrefix);
    } else {
      _docRefFuture = Future.value(null);
    }
  }

  Future<void> _editDetailsDialog(BuildContext context, String docId, Map<String, dynamic> data) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();

    // Calculate flat vehicle quota across other members of this flat
    final flatId = data['flatNumber']?.toString() ?? '';
    int flatOtherCars = 0;
    int flatOtherBikes = 0;
    try {
      final querySnap = await FirebaseFirestore.instance
          .collection('users')
          .where('flatNumber', isEqualTo: flatId)
          .get();
      for (final doc in querySnap.docs) {
        if (doc.id == docId) continue;
        final d = doc.data();
        if (d['isCarOwner'] == true && (d['carReg']?.toString().trim().isNotEmpty ?? false)) {
          flatOtherCars++;
        } else if (d['pendingCarReg']?.toString().trim().isNotEmpty ?? false) {
          flatOtherCars++;
        }
        if (d['isBikeOwner'] == true && (d['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
          flatOtherBikes++;
        } else if (d['pendingBikeReg']?.toString().trim().isNotEmpty ?? false) {
          flatOtherBikes++;
        }
        if (d['hasBike2'] == true && (d['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
          flatOtherBikes++;
        } else if (d['pendingBike2Reg']?.toString().trim().isNotEmpty ?? false) {
          flatOtherBikes++;
        }
      }
    } catch (e) {
      debugPrint('Error calculating flat vehicle quota: $e');
    }

    final bool canAddCar = flatOtherCars < 1;
    final int maxBikesAddable = 2 - flatOtherBikes;

    String rawPhone = data['phone']?.toString() ?? '';
    if (rawPhone.startsWith('+91')) rawPhone = rawPhone.substring(3);

    final mobileCtrl = TextEditingController(text: rawPhone);
    final waCtrl = TextEditingController(text: data['whatsapp']?.toString() ?? '');
    final personalEmail = data['personalEmail']?.toString().trim() ?? '';
    final existingEmail = data['email']?.toString().trim() ?? '';
    final initialEmail = (personalEmail.isNotEmpty && !personalEmail.endsWith('@ramkrishnapuram.com'))
        ? personalEmail
        : (!existingEmail.endsWith('@ramkrishnapuram.com') ? existingEmail : '');
    final emailCtrl = TextEditingController(text: initialEmail);
    final bool isUsingDefaultEmail = (personalEmail.isEmpty || personalEmail.endsWith('@ramkrishnapuram.com')) &&
        (existingEmail.isEmpty || existingEmail.endsWith('@ramkrishnapuram.com'));

    final pendingCarReg = data['pendingCarReg']?.toString().trim() ?? '';
    final pendingBikeReg = data['pendingBikeReg']?.toString().trim() ?? '';
    final pendingBike2Reg = data['pendingBike2Reg']?.toString().trim() ?? '';

    bool isCarOwner = data['isCarOwner'] == true || pendingCarReg.isNotEmpty;
    bool isBikeOwner = data['isBikeOwner'] == true || pendingBikeReg.isNotEmpty;
    bool hasBike2 = data['hasBike2'] == true || pendingBike2Reg.isNotEmpty;

    final currentCarReg = data['carReg']?.toString().trim() ?? '';
    final currentBikeReg = data['bikeReg']?.toString().trim() ?? '';
    final currentBike2Reg = data['bike2Reg']?.toString().trim() ?? '';

    final carRegCtrl = TextEditingController(
        text: currentCarReg.isNotEmpty ? currentCarReg : pendingCarReg);
    final bikeRegCtrl = TextEditingController(
        text: currentBikeReg.isNotEmpty ? currentBikeReg : pendingBikeReg);
    final bike2RegCtrl = TextEditingController(
        text: currentBike2Reg.isNotEmpty ? currentBike2Reg : pendingBike2Reg);

    PlatformFile? carRcFile;
    PlatformFile? bikeRcFile;
    PlatformFile? bike2RcFile;
    bool isSaving = false;

    Future<String?> uploadRcDoc(PlatformFile file, String prefix) async {
      final fileName = file.name;
      return uploadFile(
        file,
        'vehicle_rc/${prefix}_${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );
    }

    if (!context.mounted) return;

    try {
      await showDialog(
        context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: Colors.teal),
              SizedBox(width: 8),
              Text('Edit My Details'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width.clamp(0.0, 500.0),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contact Information',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: mobileCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number *',
                        prefixIcon: Icon(Icons.phone),
                        prefixText: '+91 ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Mobile number is required';
                        if (val.length != 10 || !RegExp(r'^[0-9]+$').hasMatch(val)) {
                          return 'Enter a valid 10-digit number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: waCtrl,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp Number *',
                        prefixIcon: Icon(Icons.chat),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'WhatsApp number is required';
                        if (val.length != 10 || !RegExp(r'^[0-9]+$').hasMatch(val)) {
                          return 'Enter a valid 10-digit number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    if (isUsingDefaultEmail)
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF87171)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFDC2626)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '* Please update your email id with a valid email address. Post that you will be able to reset your password and your login user id will be updated to your email id from flatno@ramkrishnapuram.com.',
                                style: TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextFormField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        hintText: 'e.g. yourname@gmail.com',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Email is required';
                        if (!val.contains('@')) return 'Enter a valid email address';
                        if (val.toLowerCase().endsWith('@ramkrishnapuram.com')) {
                          return 'Please enter your personal email address, not the society placeholder';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 4),
                    const Text(
                      'Vehicle Details (Max 1 Car & 2 Bikes per Flat)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Note: Updating vehicle numbers requires uploading RC/Blue Book copy for Admin approval.',
                      style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),
                    if (!canAddCar && !isCarOwner)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.red),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'This flat already has 1 Car assigned (Quota full).',
                                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Do you own a 4-Wheeler (Car)?'),
                      secondary: const Icon(Icons.directions_car, color: Colors.teal),
                      value: isCarOwner,
                      activeThumbColor: Colors.teal,
                      onChanged: (canAddCar || isCarOwner)
                          ? (val) {
                              setDS(() => isCarOwner = val);
                            }
                          : null,
                    ),
                    if (isCarOwner) ...[
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: carRegCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Car Registration No. *',
                          hintText: 'e.g. WB 02 AB 1234',
                          prefixIcon: Icon(Icons.pin),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) {
                          if (isCarOwner && (v == null || v.trim().isEmpty)) {
                            return 'Please enter car registration number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      // RC upload button for Car if reg changed or newly added
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.upload_file, size: 20, color: Colors.teal),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Upload Car RC / Blue Book Copy *',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.attach_file, size: 16),
                                  label: Text(carRcFile == null ? 'Select File' : 'Change'),
                                  onPressed: () async {
                                    final file = await pickFile(context: context);
                                    if (file != null) {
                                      setDS(() => carRcFile = file);
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (carRcFile != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Selected: ${carRcFile!.name}',
                                  style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                                ),
                              )
                            else if (data['pendingCarReg'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Pending approval: ${data['pendingCarReg']}',
                                  style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (maxBikesAddable <= 0 && !isBikeOwner)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.red),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'This flat already has 2 Bikes assigned (Quota full).',
                                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Do you own a 2-Wheeler (Bike/Scooter)?'),
                      secondary: const Icon(Icons.two_wheeler, color: Colors.teal),
                      value: isBikeOwner,
                      activeThumbColor: Colors.teal,
                      onChanged: (maxBikesAddable > 0 || isBikeOwner)
                          ? (val) {
                              setDS(() {
                                isBikeOwner = val;
                                if (!val) hasBike2 = false;
                              });
                            }
                          : null,
                    ),
                    if (isBikeOwner) ...[
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: bikeRegCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Bike 1 Registration No. *',
                          hintText: 'e.g. WB 02 CD 5678',
                          prefixIcon: Icon(Icons.pin),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) {
                          if (isBikeOwner && (v == null || v.trim().isEmpty)) {
                            return 'Please enter bike registration number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      // RC upload button for Bike 1
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.upload_file, size: 20, color: Colors.teal),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Upload Bike 1 RC / Blue Book Copy *',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.attach_file, size: 16),
                                  label: Text(bikeRcFile == null ? 'Select File' : 'Change'),
                                  onPressed: () async {
                                    final file = await pickFile(context: context);
                                    if (file != null) {
                                      setDS(() => bikeRcFile = file);
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (bikeRcFile != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Selected: ${bikeRcFile!.name}',
                                  style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                                ),
                              )
                            else if (data['pendingBikeReg'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Pending approval: ${data['pendingBikeReg']}',
                                  style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!hasBike2 && maxBikesAddable >= 1)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.teal),
                            label: const Text(
                              'Add Another Bike (Max 2)',
                              style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600),
                            ),
                            onPressed: () => setDS(() => hasBike2 = true),
                          ),
                        ),
                      if (hasBike2) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: bike2RegCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Bike 2 Registration No. *',
                                  hintText: 'e.g. WB 02 EF 9012',
                                  prefixIcon: Icon(Icons.pin),
                                  border: OutlineInputBorder(),
                                ),
                                textCapitalization: TextCapitalization.characters,
                                validator: (v) {
                                  if (isBikeOwner && hasBike2 && (v == null || v.trim().isEmpty)) {
                                    return 'Please enter Bike 2 registration number';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              tooltip: 'Remove Bike 2',
                              onPressed: () {
                                setDS(() {
                                  hasBike2 = false;
                                  bike2RegCtrl.clear();
                                  bike2RcFile = null;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.upload_file, size: 20, color: Colors.teal),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Upload Bike 2 RC / Blue Book Copy *',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.attach_file, size: 16),
                                    label: Text(bike2RcFile == null ? 'Select File' : 'Change'),
                                    onPressed: () async {
                                      final file = await pickFile(context: context);
                                      if (file != null) {
                                        setDS(() => bike2RcFile = file);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              if (bike2RcFile != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Selected: ${bike2RcFile!.name}',
                                    style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                                  ),
                                )
                              else if (data['pendingBike2Reg'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Pending approval: ${data['pendingBike2Reg']}',
                                    style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;

                      final newCarReg = isCarOwner ? carRegCtrl.text.trim().toUpperCase() : '';
                      final newBikeReg = isBikeOwner ? bikeRegCtrl.text.trim().toUpperCase() : '';
                      final newBike2Reg = (isBikeOwner && hasBike2) ? bike2RegCtrl.text.trim().toUpperCase() : '';

                      final existingPendingCar = data['pendingCarReg']?.toString().trim() ?? '';
                      final isNewCarSubmission = newCarReg.isNotEmpty && (newCarReg != currentCarReg || carRcFile != null);
                      final carChanged = isNewCarSubmission && (newCarReg != existingPendingCar || carRcFile != null);

                      final existingPendingBike = data['pendingBikeReg']?.toString().trim() ?? '';
                      final isNewBikeSubmission = newBikeReg.isNotEmpty && (newBikeReg != currentBikeReg || bikeRcFile != null);
                      final bikeChanged = isNewBikeSubmission && (newBikeReg != existingPendingBike || bikeRcFile != null);

                      final existingPendingBike2 = data['pendingBike2Reg']?.toString().trim() ?? '';
                      final isNewBike2Submission = newBike2Reg.isNotEmpty && (newBike2Reg != currentBike2Reg || bike2RcFile != null);
                      final bike2Changed = isNewBike2Submission && (newBike2Reg != existingPendingBike2 || bike2RcFile != null);

                      if (carChanged && carRcFile == null && data['pendingCarRcUrl'] == null) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Please upload RC / Blue Book copy for Car update.')),
                        );
                        return;
                      }
                      if (bikeChanged && bikeRcFile == null && data['pendingBikeRcUrl'] == null) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Please upload RC / Blue Book copy for Bike 1 update.')),
                        );
                        return;
                      }
                      if (bike2Changed && bike2RcFile == null && data['pendingBike2RcUrl'] == null) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Please upload RC / Blue Book copy for Bike 2 update.')),
                        );
                        return;
                      }

                      // Quota enforcement
                      if (isCarOwner && !canAddCar && currentCarReg.isEmpty && (data['pendingCarReg'] == null || data['pendingCarReg'].toString().isEmpty)) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Cannot add Car: Flat quota of 1 car already reached.')),
                        );
                        return;
                      }
                      int requestedBikes = (isBikeOwner ? 1 : 0) + ((isBikeOwner && hasBike2) ? 1 : 0);
                      if (flatOtherBikes + requestedBikes > 2) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Cannot exceed flat quota of 2 bikes.')),
                        );
                        return;
                      }

                      setDS(() => isSaving = true);
                      try {
                        final newEmail = emailCtrl.text.trim().toLowerCase();
                        final isNewPersonalEmail = newEmail.isNotEmpty && !newEmail.endsWith('@ramkrishnapuram.com');
                        final updatePayload = <String, dynamic>{
                          'phone': '+91${mobileCtrl.text.trim()}',
                          'whatsapp': waCtrl.text.trim(),
                          'email': newEmail,
                          if (isNewPersonalEmail) 'personalEmail': newEmail,
                          if (isNewPersonalEmail) 'defaultPasswordRevoked': true,
                          if (isNewPersonalEmail) 'isDefaultPassword': false,
                        };

                        final residentName = data['name'] ?? 'Resident';
                        final flatNum = data['flatNumber'] ?? 'Unknown Flat';
                        final blockStr = data['block'] ?? '';
                        final flatDisplay = blockStr.isNotEmpty && !flatNum.toString().contains('-')
                            ? '$blockStr-$flatNum'
                            : flatNum.toString();

                        if (!isCarOwner) {
                          updatePayload['isCarOwner'] = false;
                          updatePayload['carReg'] = '';
                          updatePayload['pendingCarReg'] = FieldValue.delete();
                          updatePayload['pendingCarRcUrl'] = FieldValue.delete();
                          updatePayload['pendingCarRcFileName'] = FieldValue.delete();
                          updatePayload['carRejectionReason'] = FieldValue.delete();
                        } else if (carChanged) {
                          String? carRcUrl;
                          if (carRcFile != null) {
                            carRcUrl = await uploadRcDoc(carRcFile!, 'car');
                          }
                          updatePayload['pendingCarReg'] = newCarReg;
                          if (carRcUrl != null) {
                            updatePayload['pendingCarRcUrl'] = carRcUrl;
                            updatePayload['pendingCarRcFileName'] = carRcFile!.name;
                          }
                          updatePayload['carRejectionReason'] = FieldValue.delete();

                          // Notify admin with clear push notification message
                          await NotificationService.notifyAdmin(
                            title: '🚗 Car Number Update Request',
                            message: '$residentName ($flatDisplay) requested to update Car number to $newCarReg with RC copy.',
                            type: 'VEHICLE_UPDATE_REQUEST',
                            flatNumber: flatDisplay,
                            extraData: {
                              'userId': docId,
                              'vehicleType': 'Car',
                              'requestedReg': newCarReg,
                              'flatNumber': flatDisplay,
                            },
                          );
                        }

                        if (!isBikeOwner) {
                          updatePayload['isBikeOwner'] = false;
                          updatePayload['bikeReg'] = '';
                          updatePayload['pendingBikeReg'] = FieldValue.delete();
                          updatePayload['pendingBikeRcUrl'] = FieldValue.delete();
                          updatePayload['pendingBikeRcFileName'] = FieldValue.delete();
                          updatePayload['bikeRejectionReason'] = FieldValue.delete();

                          updatePayload['hasBike2'] = false;
                          updatePayload['bike2Reg'] = '';
                          updatePayload['pendingBike2Reg'] = FieldValue.delete();
                          updatePayload['pendingBike2RcUrl'] = FieldValue.delete();
                          updatePayload['pendingBike2RcFileName'] = FieldValue.delete();
                          updatePayload['bike2RejectionReason'] = FieldValue.delete();
                        } else {
                          if (bikeChanged) {
                            String? bikeRcUrl;
                            if (bikeRcFile != null) {
                              bikeRcUrl = await uploadRcDoc(bikeRcFile!, 'bike');
                            }
                            updatePayload['pendingBikeReg'] = newBikeReg;
                            if (bikeRcUrl != null) {
                              updatePayload['pendingBikeRcUrl'] = bikeRcUrl;
                              updatePayload['pendingBikeRcFileName'] = bikeRcFile!.name;
                            }
                            updatePayload['bikeRejectionReason'] = FieldValue.delete();

                            // Notify admin with clear push notification message
                            await NotificationService.notifyAdmin(
                              title: '🏍️ Bike 1 Number Update Request',
                              message: '$residentName ($flatDisplay) requested to update Bike 1 number to $newBikeReg with RC copy.',
                              type: 'VEHICLE_UPDATE_REQUEST',
                              flatNumber: flatDisplay,
                              extraData: {
                                'userId': docId,
                                'vehicleType': 'Bike 1',
                                'requestedReg': newBikeReg,
                                'flatNumber': flatDisplay,
                              },
                            );
                          }

                          if (!hasBike2) {
                            updatePayload['hasBike2'] = false;
                            updatePayload['bike2Reg'] = '';
                            updatePayload['pendingBike2Reg'] = FieldValue.delete();
                            updatePayload['pendingBike2RcUrl'] = FieldValue.delete();
                            updatePayload['pendingBike2RcFileName'] = FieldValue.delete();
                            updatePayload['bike2RejectionReason'] = FieldValue.delete();
                          } else if (bike2Changed) {
                            String? bike2RcUrl;
                            if (bike2RcFile != null) {
                              bike2RcUrl = await uploadRcDoc(bike2RcFile!, 'bike2');
                            }
                            updatePayload['hasBike2'] = true;
                            updatePayload['pendingBike2Reg'] = newBike2Reg;
                            if (bike2RcUrl != null) {
                              updatePayload['pendingBike2RcUrl'] = bike2RcUrl;
                              updatePayload['pendingBike2RcFileName'] = bike2RcFile!.name;
                            }
                            updatePayload['bike2RejectionReason'] = FieldValue.delete();

                            // Notify admin with clear push notification message
                            await NotificationService.notifyAdmin(
                              title: '🏍️ Bike 2 Number Update Request',
                              message: '$residentName ($flatDisplay) requested to update Bike 2 number to $newBike2Reg with RC copy.',
                              type: 'VEHICLE_UPDATE_REQUEST',
                              flatNumber: flatDisplay,
                              extraData: {
                                'userId': docId,
                                'vehicleType': 'Bike 2',
                                'requestedReg': newBike2Reg,
                                'flatNumber': flatDisplay,
                              },
                            );
                          }
                        }

                        // If user only checked isCarOwner/isBikeOwner without reg change
                        if (isCarOwner && !carChanged && data['carReg'] == null) {
                          updatePayload['isCarOwner'] = true;
                          updatePayload['carReg'] = newCarReg;
                        }
                        if (isBikeOwner && !bikeChanged && data['bikeReg'] == null) {
                          updatePayload['isBikeOwner'] = true;
                          updatePayload['bikeReg'] = newBikeReg;
                        }

                        await FirebaseFirestore.instance.collection('users').doc(docId).update(updatePayload);

                        if (isNewPersonalEmail) {
                          final currentUser = FirebaseAuth.instance.currentUser;
                          if (currentUser != null) {
                            try {
                              await currentUser.verifyBeforeUpdateEmail(newEmail);
                            } catch (_) {}
                          }
                        }

                        if (ctx.mounted) Navigator.pop(ctx);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              carChanged || bikeChanged || bike2Changed
                                  ? 'Details saved! Vehicle update submitted for Admin approval.'
                                  : 'Details updated successfully!',
                            ),
                          ),
                        );
                      } catch (e) {
                        setDS(() => isSaving = false);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('Failed to update details: $e')),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  } finally {
      mobileCtrl.dispose();
      waCtrl.dispose();
      emailCtrl.dispose();
      carRegCtrl.dispose();
      bikeRegCtrl.dispose();
      bike2RegCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('No logged in user'));
    }

    return FutureBuilder<DocumentReference?>(
      future: _docRefFuture, // use stored future — never re-runs on rebuild
      builder: (context, futureSnap) {
        if (futureSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docRef = futureSnap.data;
        if (docRef == null) {
          return _buildHomeLayout(context, null, null);
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: docRef.snapshots(),
          builder: (context, docSnap) {
            if (docSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!docSnap.hasData || !docSnap.data!.exists) {
              return _buildHomeLayout(context, null, null);
            }
            final doc = docSnap.data!;
            return _buildHomeLayout(context, doc.id, doc.data() as Map<String, dynamic>);
          },
        );
      },
    );
  }

  /// One-time async lookup: finds the user's Firestore document reference via uid,
  /// username, email, or flat-prefix document ID. Also writes the uid back to the
  /// document so future lookups always use the fast uid path.
  Future<DocumentReference?> _resolveUserDocRef(
    String uid,
    String? userEmail,
    String? flatPrefix,
  ) async {
    final fs = FirebaseFirestore.instance;

    // 1. Try uid field match
    final uidSnap = await fs.collection('users').where('uid', isEqualTo: uid).limit(1).get();
    if (uidSnap.docs.isNotEmpty) return uidSnap.docs.first.reference;

    if (userEmail == null) return null;

    // 2. Try username == userEmail (flat email like b-312@ramkrishnapuram.com)
    final usernameSnap =
        await fs.collection('users').where('username', isEqualTo: userEmail).limit(1).get();
    if (usernameSnap.docs.isNotEmpty) {
      final ref = usernameSnap.docs.first.reference;
      ref.update({'uid': uid}).catchError((_) {});
      return ref;
    }

    // 3. Try email == userEmail (personal email)
    final emailSnap =
        await fs.collection('users').where('email', isEqualTo: userEmail).limit(1).get();
    if (emailSnap.docs.isNotEmpty) {
      final ref = emailSnap.docs.first.reference;
      ref.update({'uid': uid}).catchError((_) {});
      return ref;
    }

    // 4. Try document ID == flatPrefix (e.g. "b-312")
    if (flatPrefix != null) {
      final docSnap = await fs.collection('users').doc(flatPrefix).get();
      if (docSnap.exists) {
        docSnap.reference.update({'uid': uid}).catchError((_) {});
        return docSnap.reference;
      }
    }

    return null;
  }

  Widget _buildHomeLayout(BuildContext context, String? docId, Map<String, dynamic>? data) {
    final name = data?['name'] ?? 'Resident';
    final flatNumber = data?['flatNumber'] ?? 'N/A';
    final block = data?['block'] ?? '';
    final flatLabel = block.isNotEmpty && !flatNumber.toString().contains('-')
        ? '$block-$flatNumber'
        : flatNumber.toString();
    final role = (data?['isRentee'] == true || data?['occupantType'] == 'Rentee')
        ? 'Rentee'
        : 'Owner';
    final mobile = data?['phone'] ?? 'N/A';
    final whatsapp = data?['whatsapp'] ?? 'N/A';
    final email = data?['email'] ?? 'N/A';
    final bool isCarOwner = data?['isCarOwner'] == true;
    final String carReg = data?['carReg']?.toString().trim() ?? '';
    final bool isBikeOwner = data?['isBikeOwner'] == true;
    final String bikeReg = data?['bikeReg']?.toString().trim() ?? '';
    final bool hasBike2 = data?['hasBike2'] == true;
    final String bike2Reg = data?['bike2Reg']?.toString().trim() ?? '';

    final String? pendingCarReg = data?['pendingCarReg']?.toString().trim();
    final String? pendingCarRcUrl = data?['pendingCarRcUrl']?.toString();
    final String? carRejectionReason = data?['carRejectionReason']?.toString();

    final String? pendingBikeReg = data?['pendingBikeReg']?.toString().trim();
    final String? pendingBikeRcUrl = data?['pendingBikeRcUrl']?.toString();
    final String? bikeRejectionReason = data?['bikeRejectionReason']?.toString();

    final String? pendingBike2Reg = data?['pendingBike2Reg']?.toString().trim();
    final String? pendingBike2RcUrl = data?['pendingBike2RcUrl']?.toString();
    final String? bike2RejectionReason = data?['bike2RejectionReason']?.toString();

    void showRcDocDialog(String url, String title) {
      showDocumentPreviewDialog(context, url, title);
    }

    String vehicleSummary;
    final hasAnyBike = isBikeOwner || hasBike2 || (pendingBike2Reg != null && pendingBike2Reg.isNotEmpty);
    if (isCarOwner && hasAnyBike) {
      vehicleSummary = 'Both (4-Wheeler & 2-Wheeler)';
    } else if (isCarOwner) {
      vehicleSummary = 'Car (4-Wheeler)';
    } else if (hasAnyBike) {
      vehicleSummary = 'Bike (2-Wheeler)';
    } else {
      vehicleSummary = 'None';
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.teal.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.teal,
                            child: Icon(
                              role == 'Rentee' ? Icons.key : Icons.home,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Flat: $flatLabel • $role',
                                  style: TextStyle(color: Colors.teal.shade900),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (docId != null && data != null)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.teal),
                        onPressed: () => _editDetailsDialog(context, docId, data),
                        tooltip: 'Edit My Details',
                      ),
                  ],
                ),
                const Divider(height: 24),
                const Text(
                  'Contact Information',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Text('Mobile: $mobile'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.chat, size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Text('WhatsApp: $whatsapp'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.email, size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Email: $email',
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (email.endsWith('@ramkrishnapuram.com') ||
                              (data?['personalEmail'] == null ||
                                  data!['personalEmail'].toString().trim().isEmpty))
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '* Action Required: Please update your email ID with a valid address to secure your account and revoke the default password.',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    const Text(
                      'Registered Vehicles',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        vehicleSummary,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!isCarOwner && !isBikeOwner && !hasBike2 && (pendingCarReg == null || pendingCarReg.isEmpty) && (pendingBikeReg == null || pendingBikeReg.isEmpty) && (pendingBike2Reg == null || pendingBike2Reg.isEmpty))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      'No vehicles registered yet.',
                      style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic),
                    ),
                  )
                else ...[
                  if (isCarOwner || (pendingCarReg != null && pendingCarReg.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.directions_car, size: 18, color: Colors.teal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Car: ${carReg.isNotEmpty ? carReg : "Registered (No Reg. No.)"}',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      if (pendingCarReg != null && pendingCarReg.isNotEmpty)
                                        const TextSpan(
                                          text: ' (Update pending Admin approval)',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pendingCarReg != null && pendingCarReg.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 2),
                              child: Row(
                                children: [
                                  Text(
                                    'Requested: $pendingCarReg',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                  ),
                                  if (pendingCarRcUrl != null) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => showRcDocDialog(pendingCarRcUrl, 'Car RC / Blue Book'),
                                      child: const Text(
                                        'View Uploaded RC',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.teal,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (carRejectionReason != null && carRejectionReason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Last request rejected: $carRejectionReason',
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (isBikeOwner || (pendingBikeReg != null && pendingBikeReg.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.two_wheeler, size: 18, color: Colors.teal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Bike 1: ${bikeReg.isNotEmpty ? bikeReg : "Registered (No Reg. No.)"}',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      if (pendingBikeReg != null && pendingBikeReg.isNotEmpty)
                                        const TextSpan(
                                          text: ' (Update pending Admin approval)',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pendingBikeReg != null && pendingBikeReg.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 2),
                              child: Row(
                                children: [
                                  Text(
                                    'Requested: $pendingBikeReg',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                  ),
                                  if (pendingBikeRcUrl != null) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => showRcDocDialog(pendingBikeRcUrl, 'Bike 1 RC / Blue Book'),
                                      child: const Text(
                                        'View Uploaded RC',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.teal,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (bikeRejectionReason != null && bikeRejectionReason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Last request rejected: $bikeRejectionReason',
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (hasBike2 || (pendingBike2Reg != null && pendingBike2Reg.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.two_wheeler, size: 18, color: Colors.teal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Bike 2: ${bike2Reg.isNotEmpty ? bike2Reg : "Registered (No Reg. No.)"}',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      if (pendingBike2Reg != null && pendingBike2Reg.isNotEmpty)
                                        const TextSpan(
                                          text: ' (Update pending Admin approval)',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pendingBike2Reg != null && pendingBike2Reg.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 2),
                              child: Row(
                                children: [
                                  Text(
                                    'Requested: $pendingBike2Reg',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                  ),
                                  if (pendingBike2RcUrl != null) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => showRcDocDialog(pendingBike2RcUrl, 'Bike 2 RC / Blue Book'),
                                      child: const Text(
                                        'View Uploaded RC',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.teal,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (bike2RejectionReason != null && bike2RejectionReason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Last request rejected: $bike2RejectionReason',
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                                ),
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
        const SizedBox(height: 20),
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.payment_rounded, size: 36, color: AppColors.primary),
            title: const Text('Pay Maintenance Bill', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: const Text('Pay monthly maintenance, vehicle parking or advance bills.'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () => widget.onNavigateTab?.call(4),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.security, size: 40, color: Colors.teal),
            title: const Text('Gate Pass System', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: const Text('Pre-approve visitors, view gate clearances & deliveries.'),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PreApproveVisitorScreen(userFlat: flatLabel),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class NotificationsTab extends StatelessWidget {
  final Function(int, [String?])? onNavigateTab;
  final String? userFlat;
  final String? fullFlat;
  const NotificationsTab({
    super.key,
    this.onNavigateTab,
    this.userFlat,
    this.fullFlat,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // Provide bottom padding so notification cards at the bottom are not hidden behind NavigationBar
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        if (user != null) ...[
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('targetRole', whereIn: ['RESIDENT', 'ALL'])
                .limit(100)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('Error loading alerts: ${snap.error}',
                    style: const TextStyle(color: Colors.red));
              }
              final docs = (snap.data?.docs ?? []).where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return _isNotificationForResident(data, user, userFlat, fullFlat);
              }).toList();
              // Sort in memory by createdAt descending
              docs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = (aData['createdAt'] as Timestamp?)?.toDate() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final bTime = (bData['createdAt'] as Timestamp?)?.toDate() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return bTime.compareTo(aTime);
              });

              if (docs.isEmpty) return const SizedBox.shrink();

              final unreadDocs = docs.where((d) => (d.data() as Map)['isRead'] != true).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active,
                          color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Personal Alerts (${docs.length})',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal),
                      ),
                      if (unreadDocs.isNotEmpty) ...[
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            await NotificationService.markAllAsRead(
                              unreadDocs.map((d) => d.id).toList(),
                            );
                          },
                          icon: const Icon(Icons.done_all, size: 16, color: Colors.teal),
                          label: const Text('Mark all read', style: TextStyle(fontSize: 12, color: Colors.teal)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...docs.map((doc) {
                    final notif = doc.data() as Map<String, dynamic>;
                    final isRead = notif['isRead'] == true;
                    final title = notif['title'] ?? 'Notification';
                    final msg = notif['message'] ?? '';
                    final type =
                        (notif['type'] ?? '').toString().toUpperCase();

                    final isApproved = type.contains('APPROVED');
                    final isRejected = type.contains('REJECTED');
                    final isPaymentApproved = type == 'MAINTENANCE_PAYMENT_APPROVED';
                    final isPaymentRejected = type == 'MAINTENANCE_PAYMENT_REJECTED';
                    final isVehicle = type.contains('VEHICLE');
                    final isComplaint = type.contains('COMPLAINT');
                    final isMaintenance =
                        type.contains('MAINTENANCE') || type.contains('PAYMENT');
                    final isVisitor = type.contains('VISITOR');
                    final isParcel = type.contains('PARCEL');
                    final isEmergency = type.contains('EMERGENCY');

                    final cardColor = isEmergency
                        ? Colors.red.shade50
                        : isVisitor
                            ? Colors.teal.shade50
                            : isParcel
                                ? Colors.amber.shade50
                                : isApproved
                                    ? Colors.green.shade50
                                    : isRejected
                                        ? Colors.red.shade50
                                        : Colors.teal.shade50;

                    final borderColor = isEmergency
                        ? Colors.red.shade200
                        : isVisitor
                            ? Colors.teal.shade200
                            : isParcel
                                ? Colors.amber.shade300
                                : isApproved
                                    ? Colors.green.shade200
                                    : isRejected
                                        ? Colors.red.shade200
                                        : Colors.teal.shade200;

                    final iconBgColor = isEmergency
                        ? Colors.red.shade100
                        : isVisitor
                            ? Colors.teal.shade100
                            : isParcel
                                ? Colors.amber.shade100
                                : isApproved
                                    ? Colors.green.shade100
                                    : isRejected
                                        ? Colors.red.shade100
                                        : Colors.teal.shade100;

                    final iconColor = isEmergency
                        ? Colors.red.shade800
                        : isVisitor
                            ? Colors.teal.shade800
                            : isParcel
                                ? Colors.amber.shade900
                                : isApproved
                                    ? Colors.green.shade800
                                    : isRejected
                                        ? Colors.red.shade800
                                        : Colors.teal.shade800;

                    final isCheckOut = type == 'VISITOR_CHECK_OUT';
                    final iconData = isEmergency
                        ? Icons.warning_rounded
                        : isCheckOut
                            ? Icons.logout_rounded
                            : isVisitor
                                ? Icons.person_pin_circle_rounded
                                : isParcel
                                    ? Icons.inventory_2_rounded
                                    : isApproved
                                        ? Icons.check_circle
                                        : isRejected
                                            ? Icons.cancel
                                            : Icons.info;

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: borderColor),
                      ),
                      color: cardColor,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: iconBgColor,
                          child: Icon(iconData, color: iconColor),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (!isRead)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.teal,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(msg, style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              isPaymentApproved
                                  ? 'Tap to view & download official receipt'
                                  : isPaymentRejected
                                      ? '⚠️ Please meet authorities in person to resolve conflicts'
                                      : isVehicle
                                          ? 'Tap to view in Vehicle Details'
                                          : isComplaint
                                              ? 'Tap to open Helpdesk'
                                              : isMaintenance
                                                  ? 'Tap to view & pay Maintenance'
                                                  : isVisitor
                                                      ? 'Tap to view visitor details'
                                                      : isParcel
                                                          ? 'Tap to view parcel & courier details'
                                                          : isEmergency
                                                              ? '⚠️ Tap to view emergency alert'
                                                              : 'Tap to view',
                              style: TextStyle(
                                fontSize: 11,
                                color: iconColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // Quick Action Buttons & Status Badges for Parcel Notifications
                            if (isParcel) ...[
                              if (notif['acknowledged'] == true || notif['residentAcknowledged'] == true) ...[
                                // Status badge when parcel receipt is already confirmed
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.green.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle_rounded, size: 13, color: Colors.green.shade800),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Receipt Confirmed',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else if (notif['disputed'] == true || notif['receiptStatus'] == 'NOT_RECEIVED') ...[
                                // Status badge when resident has reported parcel not received
                                Container(
                                  margin: const EdgeInsets.only(top: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.red.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.warning_amber_rounded, size: 13, color: Colors.red.shade800),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Reported Not Received',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade900),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                // 1-Tap Action buttons: Received & Not Received for easy resident confirmation.
                                // We use a Wrap widget with compact button padding so that buttons fit side-by-side
                                // on normal screens, and wrap gracefully without ANY RenderFlex overflow on narrow screens.
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      // "Received" confirmation button
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          elevation: 0,
                                        ),
                                        icon: const Icon(Icons.check_circle_rounded, size: 13),
                                        label: const Text('Received', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        onPressed: () async {
                                          final pDocId = notif['parcelDocId']?.toString() ?? '';
                                          final fNum = notif['flatNumber']?.toString() ?? userFlat ?? fullFlat ?? '';
                                          final prov = notif['deliveryProvider']?.toString() ?? 'Courier';
                                          final pCount = int.tryParse(notif['packetCount']?.toString() ?? '1') ?? 1;

                                          await VisitorPassService.acknowledgeParcelReceipt(
                                            parcelDocId: pDocId,
                                            flatNumber: fNum,
                                            deliveryProvider: prov,
                                            packetCount: pCount,
                                            notifDocId: doc.id,
                                          );
                                          if (context.mounted) {
                                            AppFeedback.showSuccess(context, 'Receipt confirmed! Gate security notified.');
                                          }
                                        },
                                      ),
                                      // "Not Received" dispute button
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red.shade700,
                                          side: BorderSide(color: Colors.red.shade400),
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        icon: const Icon(Icons.cancel_outlined, size: 13),
                                        label: const Text('Not Received', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        onPressed: () async {
                                          final pDocId = notif['parcelDocId']?.toString() ?? '';
                                          final fNum = notif['flatNumber']?.toString() ?? userFlat ?? fullFlat ?? '';
                                          final prov = notif['deliveryProvider']?.toString() ?? 'Courier';
                                          final pCount = int.tryParse(notif['packetCount']?.toString() ?? '1') ?? 1;

                                          await VisitorPassService.reportParcelNotReceived(
                                            parcelDocId: pDocId,
                                            flatNumber: fNum,
                                            deliveryProvider: prov,
                                            packetCount: pCount,
                                            notifDocId: doc.id,
                                          );
                                          if (context.mounted) {
                                            AppFeedback.showWarning(context, 'Alert sent to Gate Security.');
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                        // Trailing section with compact constraints to maximize horizontal room for subtitle
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              icon: const Icon(Icons.close,
                                  size: 18, color: Colors.grey),
                              onPressed: () async {
                                try {
                                  await doc.reference.delete();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Failed to dismiss notification: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              tooltip: 'Dismiss',
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
                          ],
                        ),
                        onTap: () async {
                          // Mark notification as read when clicked in the tray
                          if (!isRead) {
                            NotificationService.markAsRead(doc.id);
                          }
                          // Route click to the corresponding section / modal
                          await handleNotificationClick(
                            context: context,
                            notif: notif,
                            docId: doc.id,
                            onNavigateTab: onNavigateTab,
                            userFlat: userFlat,
                            fullFlat: fullFlat,
                          );
                        },
                      ),
                    );
                  }),
                  const Divider(height: 24),
                ],
              );
            },
          ),
        ],
        Row(
          children: const [
            Icon(Icons.campaign, color: Colors.teal, size: 20),
            SizedBox(width: 8),
            Text(
              'Society Announcements',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('announcements')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No announcements yet.',
                      style: TextStyle(color: Colors.grey)),
                ),
              );
            }

            final notices = docs.map((d) => NoticeModel.fromFirestore(d)).toList();

            notices.sort((a, b) {
              if (a.isPinned && !b.isPinned) return -1;
              if (!a.isPinned && b.isPinned) return 1;
              return b.createdAt.compareTo(a.createdAt);
            });

            return LayoutBuilder(
              builder: (context, constraints) {
                final isTwoColumn = constraints.maxWidth >= 600;
                return TwoColumnNoticeList(
                  notices: notices,
                  isTwoColumn: isTwoColumn,
                  isAdmin: false,
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// Handles routing and modal presentation when a notification is clicked either from
  /// the in-app heads-up push banner or from the notification drawer list.
  static Future<void> handleNotificationClick({
    required BuildContext context,
    required Map<String, dynamic> notif,
    required String docId,
    Function(int, [String?])? onNavigateTab,
    String? userFlat,
    String? fullFlat,
  }) async {
    final type = (notif['type'] ?? '').toString().toUpperCase();
    final title = (notif['title'] ?? '').toString().toLowerCase();
    final message = (notif['message'] ?? '').toString().toLowerCase();

    final isPaymentApproved = type == 'MAINTENANCE_PAYMENT_APPROVED' ||
        (title.contains('payment') && title.contains('approved'));
    final isPaymentRejected = type == 'MAINTENANCE_PAYMENT_REJECTED' ||
        (title.contains('payment') && title.contains('rejected'));
    final isMaintenance = type == 'MAINTENANCE' ||
        type == 'MAINTENANCE_DUE' ||
        title.contains('maintenance') ||
        title.contains('bill') ||
        title.contains('dues') ||
        message.contains('maintenance');
    final isVisitor = type.startsWith('VISITOR') ||
        title.contains('visitor') ||
        title.contains('guest') ||
        message.contains('visitor') ||
        message.contains('guest') ||
        message.contains('arrived') ||
        message.contains('checked in');
    final isParcel = type.startsWith('PARCEL') ||
        title.contains('parcel') ||
        title.contains('courier') ||
        message.contains('parcel') ||
        message.contains('courier') ||
        message.contains('delivery');
    final isEmergency = type == 'EMERGENCY' ||
        title.contains('emergency') ||
        title.contains('sos') ||
        title.contains('alert') ||
        message.contains('emergency');
    final isComplaint = type == 'COMPLAINT' ||
        type == 'HELPDESK' ||
        title.contains('complaint') ||
        title.contains('ticket') ||
        message.contains('complaint');
    final isVehicle = type == 'VEHICLE' ||
        type == 'VEHICLE_UPDATE_REQUEST' ||
        title.contains('vehicle') ||
        title.contains('car') ||
        title.contains('bike');

    if (isPaymentApproved) {
      final dueId = notif['dueId']?.toString();
      final receiptNo = notif['receiptNumber']?.toString();
      if (dueId != null && dueId.isNotEmpty) {
        try {
          final dueDoc = await FirebaseFirestore.instance.collection('maintenance_dues').doc(dueId).get();
          if (dueDoc.exists && context.mounted) {
            ReceiptPreviewDialog.show(
              context: context,
              dueData: dueDoc.data()!,
              receiptNumber: receiptNo,
            );
            return;
          }
        } catch (_) {}
      }
      final month = notif['month']?.toString();
      onNavigateTab?.call(4, month); // Fallback to Maintenance tab
    } else if (isPaymentRejected) {
      final month = notif['month']?.toString();
      onNavigateTab?.call(4, month); // Maintenance tab
    } else if (isVehicle) {
      onNavigateTab?.call(0); // Home tab
    } else if (isComplaint) {
      onNavigateTab?.call(3); // Helpdesk tab
    } else if (isMaintenance) {
      final month = notif['month']?.toString();
      onNavigateTab?.call(4, month); // Maintenance tab with month payload
    } else if (isVisitor) {
      final isPending = notif['approvalStatus'] == 'PENDING' || notif['isWalkIn'] == true;
      showVisitorNotificationDialog(
        context,
        notif,
        notifDocId: docId,
        userFlat: userFlat,
        fullFlat: fullFlat,
        playRingtone: isPending,
      );
    } else if (isParcel) {
      showParcelNotificationDialog(context, notif, docId, userFlat, fullFlat);
    } else if (isEmergency) {
      showEmergencyNotificationDialog(context, notif);
    } else if (type == 'ANNOUNCEMENT' || title.contains('announcement') || message.contains('announcement')) {
      onNavigateTab?.call(2); // Notifications & Announcements tab
    }
  }

  static String? _activeVisitorDialogKey;

  /// Displays the interactive visitor clearance & photo verification dialog with Approve/Deny buttons,
  /// with automatic ringtone audio playback for incoming gate approval requests.
  static void showVisitorNotificationDialog(
    BuildContext context,
    Map<String, dynamic> notif, {
    String? notifDocId,
    String? userFlat,
    String? fullFlat,
    bool playRingtone = false,
  }) {
    final title = notif['title']?.toString() ?? 'Visitor at Gate';
    final msg = notif['message']?.toString() ?? '';

    String vName = notif['visitorName']?.toString() ?? '';
    if (vName.isEmpty) {
      if (title.startsWith('Visitor At Gate: ')) {
        vName = title.replaceFirst('Visitor At Gate: ', '').trim();
      } else if (title.startsWith('Pre-approved Guest Arrived: ')) {
        vName = title.replaceFirst('Pre-approved Guest Arrived: ', '').trim();
      } else {
        vName = 'Visitor';
      }
    }

    // Deduplication key: prevent multiple stacked dialogs if stream fires repeatedly for the same visitor
    final String dialogKey = notifDocId ?? notif['visitorDocId']?.toString() ?? vName;
    if (_activeVisitorDialogKey == dialogKey) {
      debugPrint('[ResidentDashboard] Visitor clearance dialog already active for $dialogKey');
      return;
    }
    _activeVisitorDialogKey = dialogKey;

    String vPurpose = notif['purpose']?.toString() ?? '';
    if (vPurpose.isEmpty) {
      final match = RegExp(r'\((.*?)\)').firstMatch(msg);
      vPurpose = match?.group(1) ?? 'Guest / Personal';
    }

    String vGate = notif['gateName']?.toString() ?? '';
    if (vGate.isEmpty) {
      final match = RegExp(r'(?:checked in at|exited from)\s+([^\.]+?)(?:\.|\s+with|\s+\()').firstMatch(msg);
      vGate = match?.group(1) ?? 'Security Gate';
    }

    final guardName = notif['guardName']?.toString() ?? 'Security Guard';
    final phone = notif['phone']?.toString() ??
        (notif['extraData'] is Map ? (notif['extraData'] as Map)['phone']?.toString() : null);
    final vehicle = notif['vehicleNumber']?.toString() ??
        (notif['extraData'] is Map ? (notif['extraData'] as Map)['vehicleNumber']?.toString() : null);
    final deliveryApp = notif['deliveryApp']?.toString() ??
        (notif['extraData'] is Map ? (notif['extraData'] as Map)['deliveryApp']?.toString() : null);
    final flatNumber = notif['flatNumber']?.toString() ?? userFlat ?? fullFlat ?? '';
    final createdAt = (notif['createdAt'] as Timestamp?)?.toDate();
    final timeStr = createdAt != null ? DateFormat('hh:mm a, dd MMM yyyy').format(createdAt) : 'Just now';

    final isCheckedOut = notif['type'] == 'VISITOR_CHECK_OUT' || notif['status'] == 'CHECKED_OUT';
    String? currentApproval = notif['approvalStatus']?.toString();
    bool isActionLoading = false;
    String? visitorDocId = notif['visitorDocId']?.toString();
    String? photoUrl = notif['photoUrl']?.toString() ??
        (notif['extraData'] is Map ? (notif['extraData'] as Map)['photoUrl']?.toString() : null);

    // Continuous doorbell ringtone audio player for incoming clearance requests
    AudioPlayer? audioPlayer;
    if (playRingtone && currentApproval == 'PENDING' && !isCheckedOut) {
      try {
        audioPlayer = AudioPlayer();
        audioPlayer.setReleaseMode(ReleaseMode.loop);
        audioPlayer.play(AssetSource('audio/cell_phone_ring_std.mp3')).catchError((err) {
          debugPrint('[ResidentDashboard] AudioPlayer ringtone playback error: $err');
        });
      } catch (e) {
        debugPrint('[ResidentDashboard] AudioPlayer initialization error: $e');
      }
    }

    void stopRingtone() {
      if (audioPlayer != null) {
        audioPlayer!.stop().catchError((_) {});
        audioPlayer!.dispose().catchError((_) {});
        audioPlayer = null;
      }
    }

    Future<String?> resolveVisitorDocId() async {
      if (visitorDocId != null && visitorDocId!.isNotEmpty) return visitorDocId;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('visitors')
            .where('flatNumber', isEqualTo: FlatUtils.normalize(flatNumber))
            .get();
        if (snap.docs.isNotEmpty) {
          final matches = snap.docs.where((d) {
            final data = d.data();
            final vN = (data['visitorName'] ?? '').toString().trim().toLowerCase();
            final vStatus = data['status']?.toString();
            return vStatus == 'CHECKED_IN' &&
                   (vN == vName.trim().toLowerCase() ||
                    vN.contains(vName.trim().toLowerCase()) ||
                    vName.trim().toLowerCase().contains(vN));
          }).toList();
          if (matches.isNotEmpty) {
            visitorDocId = matches.first.id;
            photoUrl ??= matches.first.data()['photoUrl']?.toString();
            return visitorDocId;
          }
          final checkedIn = snap.docs.where((d) => d.data()['status'] == 'CHECKED_IN').toList();
          if (checkedIn.isNotEmpty) {
            visitorDocId = checkedIn.last.id;
            photoUrl ??= checkedIn.last.data()['photoUrl']?.toString();
            return visitorDocId;
          }
        }
      } catch (e) {
        // ignore
      }
      return null;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isApproved = currentApproval == 'APPROVED';
          final isDenied = currentApproval == 'DENIED';

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isCheckedOut
                                ? AppColors.primarySurface
                                : isApproved
                                    ? Colors.green.shade50
                                    : (isDenied ? Colors.red.shade50 : Colors.teal.shade50),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isCheckedOut
                                ? Icons.logout_rounded
                                : isApproved
                                    ? Icons.check_circle_rounded
                                    : (isDenied ? Icons.cancel_rounded : Icons.person_pin_circle_rounded),
                            color: isCheckedOut
                                ? AppColors.primary
                                : isApproved
                                    ? Colors.green
                                    : (isDenied ? Colors.red : Colors.teal),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(vName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              Text(
                                isCheckedOut
                                    ? 'Guest Checked Out'
                                    : isApproved
                                        ? (notif['isPreApproved'] == true ? 'Pre-Approved Guest Entry' : 'Entry Approved')
                                        : (isDenied ? 'Entry Denied' : 'Visitor Gate Clearance'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isCheckedOut || isApproved || isDenied ? FontWeight.bold : FontWeight.normal,
                                  color: isCheckedOut
                                      ? AppColors.primary
                                      : isApproved
                                          ? Colors.green
                                          : (isDenied ? Colors.red : Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (isCheckedOut)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.logout_rounded, color: AppColors.primary, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'GUEST CHECKED OUT',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Your guest $vName has checked out and departed campus from $vGate.',
                                    style: const TextStyle(fontSize: 11, color: AppColors.primaryDark),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (isApproved)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_rounded, color: Colors.green, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    notif['isPreApproved'] == true
                                        ? 'PRE-APPROVED GUEST CHECKED IN'
                                        : 'ENTRY APPROVED BY YOU',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    notif['isPreApproved'] == true
                                        ? 'Your pre-approved guest $vName has checked in at $vGate.'
                                        : 'Gate security has been notified that $vName is cleared to enter.',
                                    style: TextStyle(fontSize: 11, color: Colors.green.shade900),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (isDenied)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.block_rounded, color: Colors.red, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ENTRY DENIED BY YOU',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Gate security has been instructed to turn $vName away.',
                                    style: TextStyle(fontSize: 11, color: Colors.red.shade900),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.security_rounded, color: Colors.brown, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'CLEARANCE REQUIRED',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Visitor waiting at $vGate • $timeStr',
                                    style: TextStyle(fontSize: 11, color: Colors.brown.shade800),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (photoUrl != null && photoUrl!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.camera_alt_outlined, size: 14, color: AppColors.primary),
                              SizedBox(width: 6),
                              Text('Visitor Photo (Gate Verification)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  insetPadding: const EdgeInsets.all(16),
                                  child: Stack(
                                    children: [
                                      InteractiveViewer(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.network(
                                            photoUrl!,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: CircleAvatar(
                                          backgroundColor: Colors.black54,
                                          radius: 18,
                                          child: IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                                            onPressed: () => Navigator.pop(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 180,
                                    width: double.infinity,
                                    color: AppColors.cardSurfaceSecondary,
                                    child: Image.network(
                                      photoUrl!,
                                      height: 180,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (_, child, progress) {
                                        if (progress == null) return child;
                                        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                                      },
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Icon(Icons.broken_image_rounded, size: 40, color: Colors.grey),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text('Tap to zoom', style: TextStyle(color: Colors.white, fontSize: 10)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    _buildDialogRow('Purpose', vPurpose),
                    if (deliveryApp != null && deliveryApp.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildDialogRow('Delivery App', deliveryApp),
                    ],
                    if (phone != null && phone.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildDialogRow('Phone', phone),
                    ],
                    if (vehicle != null && vehicle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildDialogRow('Vehicle', vehicle),
                    ],
                    const SizedBox(height: 8),
                    _buildDialogRow('Gate & Guard', '$vGate • $guardName'),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurfaceSecondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        msg,
                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.3),
                      ),
                    ),
                    if (isActionLoading) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text('Notifying gate security...', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (isCheckedOut || isApproved || isDenied)
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            stopRingtone();
                            Navigator.pop(ctx);
                          },
                          child: const Text('Close'),
                        ),
                      )
                    else
                      Row(
                        children: [
                          TextButton(
                            onPressed: isActionLoading
                                ? null
                                : () {
                                    stopRingtone();
                                    Navigator.pop(ctx);
                                  },
                            child: const Text('Dismiss', style: TextStyle(color: Colors.grey)),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade400),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            label: const Text('Deny Entry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            onPressed: isActionLoading
                                ? null
                                : () async {
                                    stopRingtone();
                                    setDialogState(() => isActionLoading = true);
                                    try {
                                      final docId = await resolveVisitorDocId();
                                      await VisitorPassService.denyVisitorEntry(
                                        visitorDocId: docId,
                                        flatNumber: flatNumber,
                                        visitorName: vName,
                                        notifDocId: notifDocId,
                                      );
                                      setDialogState(() {
                                        currentApproval = 'DENIED';
                                        isActionLoading = false;
                                      });
                                    } catch (e) {
                                      setDialogState(() => isActionLoading = false);
                                      if (context.mounted) {
                                        AppFeedback.showError(context, 'Failed to deny entry: $e');
                                      }
                                    }
                                  },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: const Text('Approve Entry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            onPressed: isActionLoading
                                ? null
                                : () async {
                                    stopRingtone();
                                    setDialogState(() => isActionLoading = true);
                                    try {
                                      final docId = await resolveVisitorDocId();
                                      await VisitorPassService.approveVisitorEntry(
                                        visitorDocId: docId,
                                        flatNumber: flatNumber,
                                        visitorName: vName,
                                        notifDocId: notifDocId,
                                      );
                                      setDialogState(() {
                                        currentApproval = 'APPROVED';
                                        isActionLoading = false;
                                      });
                                    } catch (e) {
                                      setDialogState(() => isActionLoading = false);
                                      if (context.mounted) {
                                        AppFeedback.showError(context, 'Failed to approve entry: $e');
                                      }
                                    }
                                  },
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      stopRingtone();
      _activeVisitorDialogKey = null;
    });
  }

  /// Displays parcel & courier handover details when parcel notifications are tapped,
  /// and provides a 1-tap "Acknowledge Receipt" action when parcels have been delivered.
  static void showParcelNotificationDialog(
    BuildContext context,
    Map<String, dynamic> notif, [
    String? notifDocId,
    String? userFlat,
    String? fullFlat,
  ]) {
    final msg = notif['message']?.toString() ?? '';
    final deliveryProvider = notif['deliveryProvider']?.toString() ?? 'Courier';
    final packetCount = notif['packetCount']?.toString() ?? '1';
    final parsedCount = int.tryParse(packetCount) ?? 1;
    final gateName = notif['gateName']?.toString() ?? 'Main Gate';
    final remarks = notif['remarks']?.toString();
    final flatNumber = notif['flatNumber']?.toString() ?? userFlat ?? fullFlat ?? '';
    final parcelDocId = notif['parcelDocId']?.toString() ?? '';
    final type = (notif['type'] ?? '').toString().toUpperCase();
    final isDelivered = type == 'PARCEL_DELIVERED' ||
        notif['status'] == 'COLLECTED' ||
        notif['requiresAcknowledgment'] == true;
    final createdAt = (notif['createdAt'] as Timestamp?)?.toDate();
    final timeStr = createdAt != null ? DateFormat('hh:mm a, dd MMM yyyy').format(createdAt) : 'Just now';

    // Determine if the parcel receipt has already been acknowledged or disputed
    bool isAcknowledged = notif['acknowledged'] == true || notif['residentAcknowledged'] == true;
    bool isDisputed = notif['disputed'] == true || notif['receiptStatus'] == 'NOT_RECEIVED';
    bool isProcessingAction = false;

    // Use global navigatorKey to ensure ancestor Navigator exists
    final targetCtx = PushNotificationManager.navigatorKey.currentContext ?? context;
    if (!targetCtx.mounted) return;

    showDialog(
      context: targetCtx,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isAcknowledged
                        ? Colors.green.shade50
                        : (isDisputed
                            ? Colors.red.shade50
                            : (isDelivered ? AppColors.primarySurface : Colors.amber.shade50)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isAcknowledged
                        ? Icons.verified_rounded
                        : (isDisputed
                            ? Icons.report_problem_rounded
                            : (isDelivered ? Icons.mark_email_read_rounded : Icons.inventory_2_rounded)),
                    color: isAcknowledged
                        ? Colors.green
                        : (isDisputed
                            ? Colors.red.shade800
                            : (isDelivered ? AppColors.primary : Colors.amber.shade800)),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$deliveryProvider Delivery', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        isAcknowledged
                            ? 'Receipt Confirmed'
                            : (isDisputed
                                ? 'Reported Not Received'
                                : (isDelivered
                                    ? 'Delivered • Confirmation Required'
                                    : 'At Gate • Confirmation Required')),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: (!isAcknowledged && !isDisputed) ? FontWeight.bold : FontWeight.normal,
                          color: isAcknowledged
                              ? Colors.green.shade800
                              : (isDisputed
                                  ? Colors.red.shade800
                                  : (isDelivered ? AppColors.primary : Colors.amber.shade900)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Banner Container reflecting current acknowledgment / dispute state
                  if (isAcknowledged)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'RECEIPT CONFIRMED',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'You have confirmed receipt of this delivery. Gate security has been notified.',
                                  style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isDisputed)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.report_problem_rounded, color: Colors.red.shade800, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'REPORTED NOT RECEIVED',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'You reported that you did not receive this parcel. Gate security has been alerted to verify with the courier.',
                                  style: TextStyle(fontSize: 11, color: Colors.red.shade900),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDelivered ? AppColors.primarySurface : Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDelivered ? AppColors.primaryBorder : Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isDelivered ? Icons.mark_email_read_rounded : Icons.inventory_2_rounded,
                            color: isDelivered ? AppColors.primary : Colors.amber.shade800,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isDelivered ? 'DELIVERED TO YOUR FLAT' : 'PARCEL AT SECURITY GATE',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDelivered ? AppColors.primaryDark : Colors.brown.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isDelivered
                                      ? 'Security has handed over $packetCount packet(s). Please confirm whether you received them.'
                                      : 'Received at $gateName • $timeStr. Did you receive this parcel?',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDelivered ? AppColors.primaryDark : Colors.brown.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  _buildDialogRow('Packages', '$packetCount packet(s)'),
                  const SizedBox(height: 8),
                  _buildDialogRow('Delivery Provider', deliveryProvider),
                  const SizedBox(height: 8),
                  _buildDialogRow('Gate / Security Point', gateName),
                  if (flatNumber.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildDialogRow('Destination Flat', 'Flat $flatNumber'),
                  ],
                  if (remarks != null && remarks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildDialogRow('Remarks', remarks),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurfaceSecondary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      msg,
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (!isAcknowledged && !isDisputed) ...[
                // Close/Later option
                TextButton(
                  onPressed: isProcessingAction ? null : () => Navigator.pop(ctx),
                  child: const Text('Later', style: TextStyle(color: Colors.grey)),
                ),
                // "Not Received" Dispute button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade400),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: isProcessingAction
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                      : const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Not Received'),
                  onPressed: isProcessingAction
                      ? null
                      : () async {
                          setDialogState(() => isProcessingAction = true);
                          try {
                            await VisitorPassService.reportParcelNotReceived(
                              parcelDocId: parcelDocId,
                              flatNumber: flatNumber,
                              deliveryProvider: deliveryProvider,
                              packetCount: parsedCount,
                              notifDocId: notifDocId,
                            );
                            setDialogState(() {
                              isDisputed = true;
                              isProcessingAction = false;
                            });
                            if (targetCtx.mounted) {
                              AppFeedback.showWarning(targetCtx, 'Alert sent to Gate Security.');
                            }
                          } catch (e) {
                            setDialogState(() => isProcessingAction = false);
                            if (targetCtx.mounted) {
                              AppFeedback.showError(targetCtx, 'Failed to report: $e');
                            }
                          }
                        },
                ),
                // "Received" Confirmation button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: isProcessingAction
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 16),
                  label: const Text('Received'),
                  onPressed: isProcessingAction
                      ? null
                      : () async {
                          setDialogState(() => isProcessingAction = true);
                          try {
                            await VisitorPassService.acknowledgeParcelReceipt(
                              parcelDocId: parcelDocId,
                              flatNumber: flatNumber,
                              deliveryProvider: deliveryProvider,
                              packetCount: parsedCount,
                              notifDocId: notifDocId,
                            );

                            setDialogState(() {
                              isAcknowledged = true;
                              isProcessingAction = false;
                            });

                            if (targetCtx.mounted) {
                              AppFeedback.showSuccess(targetCtx, 'Parcel receipt acknowledged! Security notified.');
                            }
                          } catch (e) {
                            setDialogState(() => isProcessingAction = false);
                            if (targetCtx.mounted) {
                              AppFeedback.showError(targetCtx, 'Failed to acknowledge receipt: $e');
                            }
                          }
                        },
                ),
              ] else
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Displays urgent society-wide emergency broadcasts.
  static void showEmergencyNotificationDialog(BuildContext context, Map<String, dynamic> notif) {
    final title = notif['title']?.toString() ?? 'Emergency Alert';
    final msg = notif['message']?.toString() ?? '';
    final createdAt = (notif['createdAt'] as Timestamp?)?.toDate();
    final timeStr = createdAt != null ? DateFormat('hh:mm a, dd MMM yyyy').format(createdAt) : 'Just now';

    showDialog(
      context: context,
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
        content: Text(msg, style: const TextStyle(fontSize: 13, height: 1.4)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss Alert'),
          ),
        ],
      ),
    );
  }

  static Widget _buildDialogRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
      ],
    );
  }
}

class MaintenanceTab extends StatefulWidget {
  final String? initialSelectedMonth;
  const MaintenanceTab({super.key, this.initialSelectedMonth});

  @override
  State<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<MaintenanceTab> {
  final _currencyFmt = AppFormatters.currencyFormat;

  void _showReceiptDialog(BuildContext context, Map<String, dynamic> dueData, String receiptNumber, String? paidDateStr) {
    ReceiptPreviewDialog.show(
      context: context,
      dueData: dueData,
      receiptNumber: receiptNumber,
      dateStr: paidDateStr,
    );
  }

  void _openMaintenancePayment({
    required BuildContext context,
    required String userFlat,
    required String blockStr,
    required FlatMaintenanceBreakdown breakdown,
    required Map<String, dynamic> userData,
    required List<QueryDocumentSnapshot> allDocs,
    required List<QueryDocumentSnapshot> unpaidDocs,
    bool isDefaulter = false,
  }) {
    if (unpaidDocs.isNotEmpty) {
      // Find first payable unpaid doc (current/future month OR past month with fine)
      QueryDocumentSnapshot? payableDoc;
      for (final doc in unpaidDocs) {
        final d = doc.data() as Map<String, dynamic>;
        final m = d['month']?.toString() ?? '';
        final bool isPast = AccountingConfig.isMonthPast(m);
        final bool isParkingOnly = d['isParkingOnlyBill'] == true ||
            ((d['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0;
        final fine = AccountingConfig.getEffectiveFine(d);
        if (!isPast || isParkingOnly || fine > 0) {
          payableDoc = doc;
          break;
        }
      }

      if (payableDoc == null) {
        AppFeedback.showWarning(
          context,
          'Past month maintenance can only be paid when Admin issues it with a late fine. Please contact Society Admin.',
          title: 'Late Fine Required',
        );
        return;
      }

      final dueId = payableDoc.id;
      final dueData = payableDoc.data() as Map<String, dynamic>;
      final paidOrPendingMonths = allDocs
          .where((d) => d.id != dueId)
          .map((d) => (d.data() as Map<String, dynamic>)['month']?.toString() ?? '')
          .where((m) => m.isNotEmpty)
          .toSet();

      _showPaymentModal(
        context,
        dueId,
        dueData,
        userData,
        disabledMonths: paidOrPendingMonths.toList(),
        isDefaulter: isDefaulter,
      );
      return;
    }

    if (isDefaulter) {
      AppFeedback.showWarning(
        context,
        'Advance payments are locked because you have uncleared past maintenance. Please settle your overdue bills first.',
        title: 'Defaulter Account',
      );
      return;
    }

    // When no unpaid bills exist, find the next un-billed month of FY 2026-27
    final paidOrPendingMonths = allDocs
        .map((d) => (d.data() as Map<String, dynamic>)['month']?.toString() ?? '')
        .where((m) => m.isNotEmpty)
        .toSet();

    final currentCalMonth = AppFormatters.monthYear(AccountingConfig.currentDate);
    String? nextMonth;
    if (AccountingConfig.financialYearMonths.contains(currentCalMonth) && !paidOrPendingMonths.contains(currentCalMonth)) {
      nextMonth = currentCalMonth;
    } else {
      final curIdx = AccountingConfig.getMonthIndex(currentCalMonth);
      if (curIdx != -1) {
        for (int i = curIdx; i < AccountingConfig.financialYearMonths.length; i++) {
          final m = AccountingConfig.financialYearMonths[i];
          if (!paidOrPendingMonths.contains(m)) {
            nextMonth = m;
            break;
          }
        }
      }
    }

    if (nextMonth == null) {
      AppFeedback.showInfo(
        context,
        'All maintenance for FY ${AccountingConfig.currentFinancialYear} has already been paid in advance!',
        title: 'Fully Paid',
      );
      return;
    }

    final advanceDueData = <String, dynamic>{
      'flatNumber': userFlat,
      'block': blockStr.isNotEmpty ? blockStr : breakdown.block,
      'month': nextMonth,
      'amount': breakdown.totalMonthlyDue,
      'baseMaintenance': breakdown.baseMaintenance,
      'pujaSubscription': 0.0,
      'carParkingCharges': breakdown.carParkingCharges,
      'bikeParkingCharges': breakdown.bikeParkingCharges,
      'carCount': breakdown.carCount,
      'bikeCount': breakdown.bikeCount,
      'financialYear': AccountingConfig.currentFinancialYear,
      'status': 'UNPAID',
      'residentName': userData['name'],
    };

    _showPaymentModal(
      context,
      '',
      advanceDueData,
      userData,
      disabledMonths: paidOrPendingMonths.toList(),
      isDefaulter: false,
    );
  }

  void _showPaymentModal(
    BuildContext context,
    String dueId,
    Map<String, dynamic> dueData,
    Map<String, dynamic> userData, {
    List<String> disabledMonths = const [],
    bool isDefaulter = false,
  }) {
    final flat = (dueData['flatNumber'] ?? userData['flatNumber'] ?? 'Unknown').toString();
    final month = (dueData['month'] ?? 'Current Month').toString();
    final double fineAmt = AccountingConfig.getEffectiveFine(dueData);
    final double baseAmt = (dueData['baseMaintenance'] as num?)?.toDouble() ?? 0.0;
    final double carAmt = (dueData['carParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final double bikeAmt = (dueData['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final double computedTotal = baseAmt + carAmt + bikeAmt + fineAmt;
    final double amount = computedTotal > 0 ? computedTotal : ((dueData['amount'] as num?)?.toDouble() ?? 0.0);

    final effectiveDueData = {
      ...dueData,
      'fine': fineAmt,
      if (computedTotal > 0) 'amount': computedTotal,
    };

    final bool isParkingOnly = dueData['isParkingOnlyBill'] == true ||
        ((dueData['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0;
    final bool isPastMonth = AccountingConfig.isMonthPast(month);
    if (isPastMonth && fineAmt <= 0 && !isParkingOnly) {
      AppFeedback.showWarning(
        context,
        'Past month maintenance for $month can only be paid when Admin issues it with a late fine. Please contact Society Admin.',
        title: 'Late Fine Required',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PaymentModalSheet(
        dueId: dueId,
        dueData: effectiveDueData,
        userData: userData,
        flat: flat,
        month: month,
        amount: amount,
        currencyFmt: _currencyFmt,
        disabledMonths: disabledMonths,
        isDefaulter: isDefaulter,
        onPaymentComplete: (receiptNo) {
          Navigator.pop(ctx);
          final nowStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
          _showReceiptDialog(context, dueData, receiptNo, nowStr);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Please log in.'));

    final userEmail = user.email?.toLowerCase();
    final flatPrefix = userEmail?.contains('@') == true
        ? userEmail!.split('@').first.toLowerCase()
        : null;

    return FutureBuilder<DocumentReference?>(
      future: _resolveUserDocRef(user.uid, userEmail, flatPrefix),
      builder: (context, docRefSnap) {
        if (docRefSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docRef = docRefSnap.data;
        if (docRef == null) {
          return const Center(child: Text('User profile not found.'));
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: docRef.snapshots(),
          builder: (context, userSnapshot) {
            if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());

            final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final breakdown = AccountingConfig.calculateFromUserData(userData);
            final userFlat = (userData['flatNumber'] ?? 'A-101').toString().trim().toUpperCase();
            final blockStr = (userData['block'] ?? '').toString().trim().toUpperCase();
            final flatDisplay = (blockStr.isNotEmpty && !userFlat.startsWith(blockStr))
                ? '$blockStr-$userFlat'
                : userFlat;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Focused Notification Alert Banner if navigated from notification
                  if (widget.initialSelectedMonth != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.shade300, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.notifications_active, color: Colors.teal, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Active Bill Alert: ${widget.initialSelectedMonth}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal),
                                ),
                                const Text(
                                  'Viewing catered maintenance bill details including flat rate and vehicle parking charges.',
                                  style: TextStyle(fontSize: 11, color: Colors.black87),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // FY 2026-27 Approved Maintenance Schedule Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade800, Colors.teal.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'MY MONTHLY MAINTENANCE',
                                    style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Flat $flatDisplay (Block ${breakdown.block})',
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'FY ${AccountingConfig.currentFinancialYear}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 8),

                        // Itemized Breakdown
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '• Maintenance (Block ${breakdown.block})',
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_currencyFmt.format(breakdown.baseMaintenance), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        if (breakdown.carCount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '• 4-Wheeler Parking (${breakdown.carCount} Car @ ₹430)',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(_currencyFmt.format(breakdown.carParkingCharges), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                        if (breakdown.bikeCount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '• 2-Wheeler Parking (${breakdown.bikeCount} Bike @ ₹100)',
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(_currencyFmt.format(breakdown.bikeParkingCharges), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 4),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text('Total Fixed Monthly Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(
                              '${_currencyFmt.format(breakdown.totalMonthlyDue)} / month',
                              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Dues Stream Section
                  Builder(
                    builder: (context) {
                      final flatCandidates = <String>{
                        userFlat,
                        flatDisplay,
                        userFlat.replaceAll('-', ''),
                        flatDisplay.replaceAll('-', ''),
                        if (blockStr.isNotEmpty) '$blockStr-$userFlat',
                        if (blockStr.isNotEmpty) '$blockStr$userFlat',
                        if (userFlat.contains('-')) userFlat.split('-').last,
                      }.where((s) => s.trim().isNotEmpty).toList();

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('maintenance_dues')
                            .where('flatNumber', whereIn: flatCandidates)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                'Error loading maintenance dues: ${snapshot.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            );
                          }
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final allDocs = snapshot.data?.docs ?? [];
                          var unpaidDocs = allDocs.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'UNPAID').toList();
                          final pendingApprovalDocs = allDocs.where((d) {
                            final st = (d.data() as Map<String, dynamic>)['status'];
                            return st == 'PAYMENT_PENDING_APPROVAL' || st == 'PAID_OFFLINE_PENDING';
                          }).toList();
                          final paidDocs = allDocs.where((d) {
                            final st = (d.data() as Map<String, dynamic>)['status'];
                            return st == 'PAID_VERIFIED' || st == 'PAID_ONLINE' || st == 'PAID_OFFLINE_VERIFIED';
                          }).toList();

                      // Prioritize initialSelectedMonth if provided
                      if (widget.initialSelectedMonth != null) {
                        unpaidDocs.sort((a, b) {
                          final aMonth = (a.data() as Map<String, dynamic>)['month']?.toString() ?? '';
                          final bMonth = (b.data() as Map<String, dynamic>)['month']?.toString() ?? '';
                          if (aMonth == widget.initialSelectedMonth) return -1;
                          if (bMonth == widget.initialSelectedMonth) return 1;
                          return 0;
                        });
                      }

                      // Check if resident has historical arrears or opening balance carried over
                      final double openingArrears = (userData['openingBalance'] as num?)?.toDouble() ??
                          (userData['arrears'] as num?)?.toDouble() ?? 0.0;
                      final bool hasHistoricalArrears = openingArrears > 0 || userData['hasArrears'] == true;

                      // Defaulter check: user has uncleared dues for any past month (excluding parking-only bills) or opening arrears
                      final bool isDefaulter = hasHistoricalArrears || unpaidDocs.any((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final m = data['month']?.toString() ?? '';
                        final bool isParking = data['isParkingOnlyBill'] == true ||
                            ((data['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0;
                        return !isParking && AccountingConfig.isMonthPast(m);
                      });

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Interactive 12-Month Financial Year Calendar
                          MaintenanceMonthsCalendar(
                            duesDocs: allDocs,
                            breakdown: breakdown,
                            userData: userData,
                            flatDisplay: flatDisplay,
                            onPayMonth: (month, dueId) {
                              _openMaintenancePayment(
                                context: context,
                                userFlat: userFlat,
                                blockStr: blockStr,
                                breakdown: breakdown,
                                userData: userData,
                                allDocs: allDocs,
                                unpaidDocs: unpaidDocs,
                                isDefaulter: isDefaulter,
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // Outstanding Dues Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                child: Text(
                                  'Outstanding Maintenance Dues',
                                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.add_card_rounded, size: 16),
                                label: Text(
                                  unpaidDocs.isNotEmpty ? (isDefaulter ? 'Pay Due Bill' : 'Pay Bill') : 'Pay Advance',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                onPressed: () => _openMaintenancePayment(
                                  context: context,
                                  userFlat: userFlat,
                                  blockStr: blockStr,
                                  breakdown: breakdown,
                                  userData: userData,
                                  allDocs: allDocs,
                                  unpaidDocs: unpaidDocs,
                                  isDefaulter: isDefaulter,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          if (isDefaulter)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Defaulter Notice: Uncleared Past Dues',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Advance & multi-month payment is locked until all maintenance is settled and cleared up to last month.',
                                          style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (unpaidDocs.isEmpty && pendingApprovalDocs.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.check_circle, color: Colors.green.shade700, size: 36),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'All Dues Cleared!',
                                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade900),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'You have no pending maintenance bills for Flat $flatDisplay.',
                                              style: TextStyle(color: Colors.green.shade800, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green.shade700,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(vertical: 10),
                                      ),
                                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                      label: const Text('Pay Advance Maintenance (Multi-Month)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      onPressed: () => _openMaintenancePayment(
                                        context: context,
                                        userFlat: userFlat,
                                        blockStr: blockStr,
                                        breakdown: breakdown,
                                        userData: userData,
                                        allDocs: allDocs,
                                        unpaidDocs: unpaidDocs,
                                        isDefaulter: isDefaulter,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            if (unpaidDocs.isEmpty && pendingApprovalDocs.isNotEmpty)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.teal.shade200),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Bills pending approval. Want to pay advance for upcoming months?',
                                        style: TextStyle(fontSize: 12, color: Colors.teal.shade900, fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal.shade700,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.add_rounded, size: 16),
                                      label: const Text('Pay Advance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      onPressed: () => _openMaintenancePayment(
                                        context: context,
                                        userFlat: userFlat,
                                        blockStr: blockStr,
                                        breakdown: breakdown,
                                        userData: userData,
                                        allDocs: allDocs,
                                        unpaidDocs: unpaidDocs,
                                        isDefaulter: isDefaulter,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            // Unpaid Bills
                            ...unpaidDocs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final dueId = doc.id;
                              final month = data['month'] ?? 'Current Month';
                              final isFocusMonth = widget.initialSelectedMonth != null && month == widget.initialSelectedMonth;

                              final rawBase = (data['baseMaintenance'] as num?)?.toDouble() ?? breakdown.baseMaintenance;
                              final rawPuja = (data['pujaSubscription'] as num?)?.toDouble() ?? 0.0;
                              final baseMaint = (rawPuja > 0 && rawBase < 350) ? (rawBase + rawPuja) : rawBase;
                              final carCharges = (data['carParkingCharges'] as num?)?.toDouble() ?? breakdown.carParkingCharges;
                              final bikeCharges = (data['bikeParkingCharges'] as num?)?.toDouble() ?? breakdown.bikeParkingCharges;

                              final bool isParkingOnly = data['isParkingOnlyBill'] == true ||
                                  ((data['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0;

                              final bool isPastMonth = AccountingConfig.isMonthPast(month);
                              final fineAmt = AccountingConfig.getEffectiveFine(data);
                              final amt = isParkingOnly
                                  ? (carCharges + bikeCharges)
                                  : (baseMaint + carCharges + bikeCharges + fineAmt);
                              final bool canPayPastMonth = isParkingOnly || !isPastMonth || fineAmt > 0;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isParkingOnly
                                        ? Colors.amber.shade400
                                        : (isFocusMonth ? Colors.teal : Colors.red.shade200),
                                    width: (isFocusMonth || isParkingOnly) ? 2 : 1,
                                  ),
                                ),
                                elevation: (isFocusMonth || isParkingOnly) ? 4 : 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: isParkingOnly
                                                        ? Colors.amber.shade50
                                                        : (isFocusMonth ? Colors.teal.shade50 : Colors.red.shade50),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Icon(
                                                    isParkingOnly
                                                        ? Icons.local_parking_rounded
                                                        : (isFocusMonth ? Icons.star_rate_rounded : Icons.receipt_long),
                                                    color: isParkingOnly
                                                        ? Colors.amber.shade800
                                                        : (isFocusMonth ? Colors.teal : Colors.red),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              isParkingOnly ? 'Parking Dues: $month' : 'Maintenance Bill: $month',
                                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                          if (isParkingOnly) ...[
                                                            const SizedBox(width: 6),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: Colors.amber.shade100,
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: Text('PARKING ONLY', style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 9)),
                                                            ),
                                                          ] else if (isFocusMonth) ...[
                                                            const SizedBox(width: 6),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                              decoration: BoxDecoration(
                                                                color: Colors.teal.shade100,
                                                                borderRadius: BorderRadius.circular(4),
                                                              ),
                                                              child: const Text('ALERTED', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 9)),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                      Text(
                                                        'FY ${data['financialYear'] ?? AccountingConfig.currentFinancialYear}',
                                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _currencyFmt.format(amt),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 17,
                                              color: isParkingOnly
                                                  ? Colors.amber.shade900
                                                  : (isFocusMonth ? Colors.teal.shade800 : Colors.red),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),

                                      // Itemized Breakdown Line
                                      Builder(
                                        builder: (context) {
                                          final breakdownText = isParkingOnly
                                              ? 'Breakdown: Car Parking: ${_currencyFmt.format(carCharges)}${bikeCharges > 0 ? ' • Bike Parking: ${_currencyFmt.format(bikeCharges)}' : ''}${fineAmt > 0 ? ' • Late Fine: ${_currencyFmt.format(fineAmt)}' : ''}'
                                              : 'Breakdown: Maintenance: ${_currencyFmt.format(baseMaint)}${carCharges > 0 ? ' • Car Parking: ${_currencyFmt.format(carCharges)}' : ''}${bikeCharges > 0 ? ' • Bike Parking: ${_currencyFmt.format(bikeCharges)}' : ''}${fineAmt > 0 ? ' • Late Fine: ${_currencyFmt.format(fineAmt)}' : ''}';
                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isParkingOnly ? Colors.amber.shade50.withValues(alpha: 0.5) : Colors.grey.shade50,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: isParkingOnly ? Colors.amber.shade200 : Colors.grey.shade200),
                                            ),
                                            child: Text(
                                              breakdownText,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isParkingOnly ? Colors.amber.shade900 : Colors.grey.shade800,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          );
                                        },
                                      ),

                                      if (!canPayPastMonth) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.amber.shade300),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Past month dues can only be paid when Admin issues the bill with a late fine. Please contact Society Admin.',
                                                  style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],

                                      if (data['rejectionReason'] != null && data['rejectionReason'].toString().isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.red.shade200),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.info_outline, color: Colors.red, size: 16),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Previous Submission Rejected: ${data['rejectionReason']}',
                                                  style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],

                                      const SizedBox(height: 12),
                                      const Divider(),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          canPayPastMonth
                                              ? (isParkingOnly
                                                  ? (isPastMonth ? AppBadge.warning('PARKING DUE (OVERDUE)') : AppBadge.warning('PARKING DUE'))
                                                  : (fineAmt > 0
                                                      ? AppBadge.warning('PAST DUE • FINE: ${_currencyFmt.format(fineAmt)}')
                                                      : AppBadge.error('PAYMENT DUE')))
                                              : AppBadge.warning('PAST DUE • AWAITING FINE'),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: canPayPastMonth
                                                  ? (isParkingOnly ? Colors.amber.shade800 : AppColors.primary)
                                                  : Colors.grey.shade400,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            icon: Icon(canPayPastMonth ? (isParkingOnly ? Icons.local_parking_rounded : Icons.payment_rounded) : Icons.lock_clock_rounded, size: 16),
                                            label: Text(
                                              canPayPastMonth
                                                  ? (isParkingOnly ? 'Pay Parking Bill' : 'Pay Maintenance Bill')
                                                  : 'Awaiting Admin Late Fine',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            onPressed: canPayPastMonth
                                                ? () => _showPaymentModal(context, dueId, data, userData, isDefaulter: isDefaulter)
                                                : () => AppFeedback.showWarning(
                                                    context,
                                                    'Old month maintenance can only be paid when Admin issues it with a late fine. Please contact Society Admin.',
                                                    title: 'Late Fine Required',
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),

                            // Pending Approval Bills (Displaying Unique ID: 16-Char UTR / Bank Ref / Cheque)
                            ...(() {
                              final Map<String, QueryDocumentSnapshot> groupedPending = {};
                              for (final doc in pendingApprovalDocs) {
                                final data = doc.data() as Map<String, dynamic>;
                                final uid = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? '').toString().trim();
                                final parentId = (data['multiMonthParentDueId'] ?? '').toString().trim();

                                String key;
                                if (parentId.isNotEmpty) {
                                  key = 'PARENT_$parentId';
                                } else if (uid.isNotEmpty && uid != 'N/A' && uid != 'CASH-OFFICE') {
                                  key = 'UID_$uid';
                                } else {
                                  key = 'DOC_${doc.id}';
                                }

                                if (!groupedPending.containsKey(key)) {
                                  groupedPending[key] = doc;
                                } else {
                                  final existingData = groupedPending[key]!.data() as Map<String, dynamic>;
                                  if ((data['isMultiMonthPayment'] == true || data['multiMonthTotalAmount'] != null) &&
                                      existingData['isMultiMonthPayment'] != true && existingData['multiMonthTotalAmount'] == null) {
                                    groupedPending[key] = doc;
                                  }
                                }
                              }
                              return groupedPending.values;
                            })().map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final isMultiMonth = data['isMultiMonthPayment'] == true || data['multiMonthTotalAmount'] != null;
                              final month = (isMultiMonth && data['multiMonthSummary'] != null)
                                  ? data['multiMonthSummary'].toString()
                                  : (data['month'] ?? '').toString();
                              final amt = isMultiMonth
                                  ? ((data['multiMonthTotalAmount'] as num?)?.toDouble() ?? (data['amount'] as num?)?.toDouble() ?? 0.0)
                                  : ((data['amount'] as num?)?.toDouble() ?? 0.0);
                              final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? 'N/A').toString();
                              final mode = data['paymentMode'] ?? 'Online Payment';
                              final category = data['paymentCategory'] ?? (mode.contains('Cheque') || mode.contains('Cash') ? 'OFFLINE' : 'ONLINE');

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(14),
                                decoration: AppDecorations.card(
                                  borderColor: AppColors.warningBorder,
                                  color: AppColors.warningSurface,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              AppDecorations.iconContainer(
                                                icon: Icons.hourglass_top_rounded,
                                                color: AppColors.warningDark,
                                                surfaceColor: AppColors.warning.withValues(alpha: 0.15),
                                                size: 20,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Maintenance Bill: $month',
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      'Amount: ${_currencyFmt.format(amt)}',
                                                      style: const TextStyle(fontSize: 12, color: AppColors.slate600, fontWeight: FontWeight.w500),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        AppBadge.category(category, isOnline: category == 'ONLINE'),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.warningBorder.withValues(alpha: 0.8)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              uniqueId,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.infoDark, letterSpacing: 0.8),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          AppBadge.warning('VERIFICATION PENDING'),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Payment reference submitted. Approval request has been sent to Admin.',
                                      style: TextStyle(fontSize: 11, color: AppColors.slate500, fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],

                          const SizedBox(height: 20),

                          // Payment History & Receipts Section
                          const Text(
                            'Payment History & Receipts',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.slate900),
                          ),
                          const SizedBox(height: 10),

                          if (paidDocs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No previous payment receipts recorded yet.', style: TextStyle(color: AppColors.slate400, fontSize: 13)),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: paidDocs.length,
                              itemBuilder: (context, index) {
                                final data = paidDocs[index].data() as Map<String, dynamic>;
                                final month = data['month'] ?? '';
                                final amount = data['amount'] ?? 0;
                                final receiptNo = data['receiptNumber'] ?? 'REC-2627-${(data['paidAt'] != null ? data['paidAt'].hashCode.abs() % 10000 : 1001)}';
                                final uniqueId = (data['uniqueId'] ?? data['utrNumber'] ?? data['referenceNumber'] ?? data['offlineRef'] ?? '').toString();
                                
                                String dateStr = 'Recently Paid';
                                if (data['verifiedAt'] is Timestamp) {
                                  dateStr = DateFormat('dd MMM yyyy').format((data['verifiedAt'] as Timestamp).toDate());
                                } else if (data['paidAt'] is Timestamp) {
                                  dateStr = DateFormat('dd MMM yyyy').format((data['paidAt'] as Timestamp).toDate());
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: AppDecorations.card(),
                                  child: Row(
                                    children: [
                                      AppDecorations.iconContainer(
                                        icon: Icons.check_rounded,
                                        color: AppColors.successDark,
                                        surfaceColor: AppColors.successSurface,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$month — ${_currencyFmt.format(amount)}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Receipt: $receiptNo • $dateStr',
                                              style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (uniqueId.isNotEmpty)
                                              Text(
                                                'ID: $uniqueId • Verified in Accounts',
                                                style: const TextStyle(fontSize: 11, color: AppColors.successDark, fontWeight: FontWeight.w500),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.receipt_rounded, size: 15),
                                        label: const Text('Receipt', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.primary,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                        onPressed: () {
                                           final receiptData = Map<String, dynamic>.from(data);
                                           if ((receiptData['residentName'] == null || receiptData['residentName'].toString().isEmpty) &&
                                               userData['name'] != null &&
                                               userData['name'].toString().isNotEmpty) {
                                             receiptData['residentName'] = userData['name'];
                                           }
                                           _showReceiptDialog(context, receiptData, receiptNo, dateStr);
                                         },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  },
);
  }
}

class _PaymentModalSheet extends StatefulWidget {
  final String dueId;
  final Map<String, dynamic> dueData;
  final Map<String, dynamic> userData;
  final String flat;
  final String month;
  final double amount;
  final NumberFormat currencyFmt;
  final List<String> disabledMonths;
  final bool isDefaulter;
  final Function(String receiptNo) onPaymentComplete;

  const _PaymentModalSheet({
    required this.dueId,
    required this.dueData,
    required this.userData,
    required this.flat,
    required this.month,
    required this.amount,
    required this.currencyFmt,
    this.disabledMonths = const [],
    this.isDefaulter = false,
    required this.onPaymentComplete,
  });

  @override
  State<_PaymentModalSheet> createState() => _PaymentModalSheetState();
}

class _PaymentModalSheetState extends State<_PaymentModalSheet> {
  final _onlineFormKey = GlobalKey<FormState>();
  final _offlineFormKey = GlobalKey<FormState>();

  // Online Fields
  String _onlineMode = 'UPI'; // 'UPI' or 'Bank Transfer / NEFT'
  final _onlineUtrController = TextEditingController();

  // Offline Fields
  String _offlineMode = 'Cheque'; // 'Cheque' or 'Cash'
  final _chequeNoController = TextEditingController();
  final _chequeBankController = TextEditingController();

  bool _isProcessing = false;

  // Multi-Month & Parking configuration state
  late List<Map<String, dynamic>> _monthConfigs;
  late String _block;
  late int _carCount;
  late int _bikeCount;
  late double _baseMaintenanceRate;
  late double _carRate;
  late double _bikeRate;
  int _selectedDurationMonths = 1;

  bool get isExistingDue => widget.dueId.isNotEmpty;
  bool get isParkingOnlyDue =>
      isExistingDue &&
      (widget.dueData['isParkingOnlyBill'] == true ||
          ((widget.dueData['baseMaintenance'] as num?)?.toDouble() ?? 0.0) == 0.0);

  double get _existingDueFine => isParkingOnlyDue ? 0.0 : AccountingConfig.getEffectiveFine(widget.dueData);

  double get _existingDueAmount {
    if (widget.dueData['status'] == 'PAID' && widget.dueData['amount'] != null) {
      return (widget.dueData['amount'] as num).toDouble();
    }
    final base = (widget.dueData['baseMaintenance'] as num?)?.toDouble() ?? 0.0;
    final car = (widget.dueData['carParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final bike = (widget.dueData['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final computed = isParkingOnlyDue ? (car + bike) : (base + car + bike + _existingDueFine);
    return computed > 0 ? computed : widget.amount;
  }

  double get _existingDueBaseMaint =>
      (widget.dueData['baseMaintenance'] as num?)?.toDouble() ?? 0.0;
  double get _existingDueCarParking =>
      (widget.dueData['carParkingCharges'] as num?)?.toDouble() ?? 0.0;
  double get _existingDueBikeParking =>
      (widget.dueData['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0;

  @override
  void initState() {
    super.initState();
    // Resolve block
    final userBlock = (widget.userData['block'] ?? widget.dueData['block'] ?? '').toString().trim().toUpperCase();
    _block = userBlock.isNotEmpty
        ? userBlock
        : (widget.flat.isNotEmpty ? widget.flat.split('-').first.trim().toUpperCase() : 'A');
    if (!AccountingConfig.blockRateBreakup.containsKey(_block)) _block = 'A';

    _baseMaintenanceRate = (AccountingConfig.blockRateBreakup[_block]?['total'] ?? 450).toDouble();
    _carRate = (AccountingConfig.parkingRates['Four-Wheeler'] ?? 430).toDouble();
    _bikeRate = (AccountingConfig.parkingRates['Two-Wheeler'] ?? 100).toDouble();

    // Vehicles
    final bool isCar = widget.userData['isCarOwner'] == true || (widget.userData['carReg']?.toString().trim().isNotEmpty ?? false);
    final bool isBike = widget.userData['isBikeOwner'] == true || (widget.userData['bikeReg']?.toString().trim().isNotEmpty ?? false);
    final bool hasBike2 = widget.userData['hasBike2'] == true || (widget.userData['bike2Reg']?.toString().trim().isNotEmpty ?? false);

    _carCount = isCar ? 1 : ((widget.dueData['carCount'] as num?)?.toInt() ?? 0);
    _bikeCount = (isBike ? 1 : 0) + (hasBike2 ? 1 : 0);
    if (_bikeCount == 0 && widget.dueData['bikeCount'] != null) {
      _bikeCount = (widget.dueData['bikeCount'] as num).toInt();
    }

    // Default primary month configuration
    final bool defaultParking = isExistingDue
        ? (_existingDueCarParking > 0 || _existingDueBikeParking > 0)
        : ((_carCount > 0 || _bikeCount > 0) && (widget.dueData['parkingIncluded'] != false));
    _monthConfigs = [
      {
        'month': widget.month,
        'includeParking': defaultParking,
      }
    ];
    _selectedDurationMonths = 1;
  }

  List<String> _buildConsecutiveSchedule() {
    final String startMonth = widget.month;
    final int startIdx = AccountingConfig.getMonthIndex(startMonth);
    final bool isPast = AccountingConfig.isMonthPast(startMonth);

    // If paying an existing due, defaulter, or past overdue month, only 1 single month is allowed
    if (isExistingDue || widget.isDefaulter || isPast || startIdx == -1) {
      return [startMonth];
    }

    final schedule = <String>[startMonth];
    for (int i = startIdx + 1; i < AccountingConfig.financialYearMonths.length; i++) {
      final m = AccountingConfig.financialYearMonths[i];
      if (widget.disabledMonths.contains(m)) {
        break; // Consecutive chain stops if already paid/pending
      }
      schedule.add(m);
    }
    return schedule;
  }

  void _setDurationMonths(int count) {
    if (isExistingDue) return;
    final schedule = _buildConsecutiveSchedule();
    final clampedCount = count.clamp(1, schedule.length);
    setState(() {
      _selectedDurationMonths = clampedCount;
      final newConfigs = <Map<String, dynamic>>[];
      for (int i = 0; i < clampedCount; i++) {
        final m = schedule[i];
        final existing = _monthConfigs.firstWhere(
          (c) => c['month'] == m,
          orElse: () => {'month': m, 'includeParking': _hasVehicles},
        );
        newConfigs.add({
          'month': m,
          'includeParking': existing['includeParking'] == true,
        });
      }
      _monthConfigs = newConfigs;
    });
  }

  bool get _hasVehicles => _carCount > 0 || _bikeCount > 0;

  double get _dueFine => isParkingOnlyDue ? 0.0 : AccountingConfig.getEffectiveFine(widget.dueData);

  Map<String, dynamic> get _multiMonthCalculation {
    return BillingService.calculateMultiMonthBreakdown(
      block: _block,
      carCount: _carCount,
      bikeCount: _bikeCount,
      monthConfigs: _monthConfigs,
      fine: _dueFine,
    );
  }

  double get _currentPayableTotal => isExistingDue
      ? _existingDueAmount
      : (_multiMonthCalculation['totalAmount'] as num).toDouble();

  void _toggleParking(int index, bool val) {
    if (isExistingDue) return;
    setState(() {
      _monthConfigs[index]['includeParking'] = val;
    });
  }

  @override
  void dispose() {
    _onlineUtrController.dispose();
    _chequeNoController.dispose();
    _chequeBankController.dispose();
    super.dispose();
  }

  Future<void> _submitOnlinePayment() async {
    if (_isProcessing) return;
    if (!_onlineFormKey.currentState!.validate()) return;

    final utr = _onlineUtrController.text.trim();
    setState(() => _isProcessing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userEmail = user?.email ?? '';
      final userUid = user?.uid ?? '';
      final paymentModeName = _onlineMode == 'UPI' ? 'UPI (GPay / PhonePe / Paytm / BHIM)' : 'Bank Transfer (NEFT / IMPS / RTGS)';
      final payable = _currentPayableTotal;

      final billMonthConfigs = isExistingDue
          ? [
              {
                'month': widget.month,
                'includeParking': (_existingDueCarParking > 0 || _existingDueBikeParking > 0),
              }
            ]
          : _monthConfigs;

      await BillingService.submitMultiMonthPayment(
        primaryDueId: widget.dueId,
        flatNumber: widget.flat,
        block: _block,
        monthConfigs: billMonthConfigs,
        paymentMode: paymentModeName,
        paymentCategory: 'ONLINE',
        uniqueId: utr,
        totalAmount: payable,
        submittedByUid: userUid,
        submittedByEmail: userEmail,
        extraResidentData: {
          'residentName': widget.userData['name'] ?? widget.dueData['residentName'],
          'carCount': _carCount,
          'bikeCount': _bikeCount,
          'fine': isExistingDue ? _existingDueFine : _dueFine,
          'isParkingOnlyBill': isParkingOnlyDue,
          'baseMaintenance': isExistingDue ? _existingDueBaseMaint : _baseMaintenanceRate,
          'carParkingCharges': isExistingDue ? _existingDueCarParking : (_carCount * _carRate),
          'bikeParkingCharges': isExistingDue ? _existingDueBikeParking : (_bikeCount * _bikeRate),
          'amount': isExistingDue ? _existingDueAmount : payable,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        final billDesc = isExistingDue
            ? (isParkingOnlyDue ? 'parking dues for ${widget.month}' : 'maintenance bill for ${widget.month}')
            : '${_monthConfigs.length} month(s)';
        AppFeedback.showSuccess(
          context,
          'Online payment with 16-digit Unique ID ($utr) for $billDesc submitted for Admin approval!',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Submission error: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _submitOfflineCheque() async {
    if (_isProcessing) return;
    if (!_offlineFormKey.currentState!.validate()) return;

    final chqNo = _chequeNoController.text.trim();
    final chqBank = _chequeBankController.text.trim();
    final uniqueId = 'CHQ-$chqNo ($chqBank)';
    setState(() => _isProcessing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final userEmail = user?.email ?? '';
      final userUid = user?.uid ?? '';
      final payable = _currentPayableTotal;

      final billMonthConfigs = isExistingDue
          ? [
              {
                'month': widget.month,
                'includeParking': (_existingDueCarParking > 0 || _existingDueBikeParking > 0),
              }
            ]
          : _monthConfigs;

      await BillingService.submitMultiMonthPayment(
        primaryDueId: widget.dueId,
        flatNumber: widget.flat,
        block: _block,
        monthConfigs: billMonthConfigs,
        paymentMode: 'Cheque to Cashier',
        paymentCategory: 'OFFLINE',
        uniqueId: uniqueId,
        totalAmount: payable,
        chequeNumber: chqNo,
        chequeBank: chqBank,
        submittedByUid: userUid,
        submittedByEmail: userEmail,
        extraResidentData: {
          'residentName': widget.userData['name'] ?? widget.dueData['residentName'],
          'carCount': _carCount,
          'bikeCount': _bikeCount,
          'fine': isExistingDue ? _existingDueFine : _dueFine,
          'isParkingOnlyBill': isParkingOnlyDue,
          'baseMaintenance': isExistingDue ? _existingDueBaseMaint : _baseMaintenanceRate,
          'carParkingCharges': isExistingDue ? _existingDueCarParking : (_carCount * _carRate),
          'bikeParkingCharges': isExistingDue ? _existingDueBikeParking : (_bikeCount * _bikeRate),
          'amount': isExistingDue ? _existingDueAmount : payable,
        },
      );

      if (mounted) {
        Navigator.pop(context);
        final billDesc = isExistingDue
            ? (isParkingOnlyDue ? 'parking dues for ${widget.month}' : 'maintenance bill for ${widget.month}')
            : '${_monthConfigs.length} month(s)';
        AppFeedback.showSuccess(
          context,
          'Cheque details ($uniqueId) for $billDesc submitted for Admin approval!',
        );
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Submission error: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final calc = _multiMonthCalculation;
    final totalPayable = (calc['totalAmount'] as num).toDouble();
    final totalMaint = (calc['totalBaseMaintenance'] as num).toDouble();
    final totalPark = (calc['totalParking'] as num).toDouble();
    final int mCount = _monthConfigs.length;

    final schedule = _buildConsecutiveSchedule();

    final String currentCalMonth = AppFormatters.monthYear(AccountingConfig.currentDate);

    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Modal Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        AppDecorations.iconContainer(
                          icon: Icons.account_balance_wallet_rounded,
                          color: AppColors.primary,
                          surfaceColor: AppColors.primarySurface,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isExistingDue
                                ? (isParkingOnlyDue ? 'Pay Parking Dues' : 'Pay Maintenance Bill')
                                : 'Pay Advance Maintenance',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.slate900),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.slate500, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // If Paying an Existing Due: Show single bill summary card without multi-month or future month options
              if (isExistingDue) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isParkingOnlyDue ? Colors.amber.shade50 : AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isParkingOnlyDue ? Colors.amber.shade300 : AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  isParkingOnlyDue ? Icons.local_parking_rounded : Icons.home_rounded,
                                  size: 18,
                                  color: isParkingOnlyDue ? Colors.amber.shade900 : AppColors.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Flat ${widget.flat} (Block $_block)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isParkingOnlyDue ? Colors.amber.shade100 : Colors.indigo.shade100,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              isParkingOnlyDue ? 'PARKING DUE' : 'MAINTENANCE DUE',
                              style: TextStyle(
                                color: isParkingOnlyDue ? Colors.amber.shade900 : Colors.indigo.shade900,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Billing Month: ${widget.month}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.slate800),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isParkingOnlyDue
                                      ? 'Car: ${widget.currencyFmt.format(_existingDueCarParking)}${_existingDueBikeParking > 0 ? ' • Bike: ${widget.currencyFmt.format(_existingDueBikeParking)}' : ''}${_existingDueFine > 0 ? ' • Fine: ${widget.currencyFmt.format(_existingDueFine)}' : ''}'
                                      : 'Maint: ${widget.currencyFmt.format(_existingDueBaseMaint)}${_existingDueCarParking > 0 ? ' • Car: ${widget.currencyFmt.format(_existingDueCarParking)}' : ''}${_existingDueBikeParking > 0 ? ' • Bike: ${widget.currencyFmt.format(_existingDueBikeParking)}' : ''}${_existingDueFine > 0 ? ' • Fine: ${widget.currencyFmt.format(_existingDueFine)}' : ''}',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.slate600),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Total Payable', style: TextStyle(fontSize: 10.5, color: AppColors.slate600)),
                              Text(
                                widget.currencyFmt.format(_existingDueAmount),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isParkingOnlyDue ? Colors.amber.shade900 : AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // If Defaulter: Show warning notice banner for voluntary advance
                if (widget.isDefaulter) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Defaulter Notice: Multi-Month Advance Locked',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.amber.shade900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Multi-month advance payment is locked until maintenance is settled and cleared up to last month.',
                                style: TextStyle(fontSize: 11.5, color: Colors.amber.shade900),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Multi-Month Advance Payment Selector Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.slate200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.date_range_rounded, size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Billing Months ($mCount Selected)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.slate900),
                              ),
                            ],
                          ),
                          if (widget.isDefaulter)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('LOCKED TO 1 MONTH', style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 10)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // "How many months would you like to pay?" Dropdown Selector
                      if (!widget.isDefaulter && schedule.length > 1) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.event_repeat_rounded, size: 16, color: AppColors.primary),
                                  SizedBox(width: 6),
                                  Text(
                                    'How many months would you like to pay?',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: AppColors.slate900),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<int>(
                                initialValue: _selectedDurationMonths,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.slate300)),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.slate300)),
                                  fillColor: AppColors.slate50,
                                  filled: true,
                                ),
                                items: List.generate(schedule.length, (i) {
                                  final count = i + 1;
                                  final startM = schedule.first;
                                  final endM = schedule[i];
                                  final label = count == 1
                                      ? '1 Month ($startM)'
                                      : '$count Months ($startM – $endM)';
                                  return DropdownMenuItem<int>(
                                    value: count,
                                    child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.slate800)),
                                  );
                                }),
                                onChanged: (val) {
                                  if (val != null) _setDurationMonths(val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],

                      // List of selected months with per-month parking toggles
                      ..._monthConfigs.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final cfg = entry.value;
                        final mName = cfg['month'].toString();
                        final incParking = cfg['includeParking'] == true;

                        final bool isCurrentCalMonth = (mName == currentCalMonth);
                        final bool isPastDue = AccountingConfig.isMonthPast(mName);
                        final bool isAdvance = !isPastDue && !isCurrentCalMonth;

                        final double mCarAmt = incParking ? _carCount * _carRate : 0.0;
                        final double mBikeAmt = incParking ? _bikeCount * _bikeRate : 0.0;
                        final double monthTotal = _baseMaintenanceRate + mCarAmt + mBikeAmt + (idx == 0 ? _dueFine : 0.0);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.slate200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        mName,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.slate800),
                                      ),
                                      const SizedBox(width: 6),
                                      if (isCurrentCalMonth)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: AppColors.primarySurface,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('CURRENT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                        )
                                      else if (isPastDue)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade100,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('PAST DUE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                                        )
                                      else if (isAdvance)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text('ADVANCE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    widget.currencyFmt.format(monthTotal),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.slate900),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),

                              // Maintenance & Vehicle Parking breakdown
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Base Maintenance: ${widget.currencyFmt.format(_baseMaintenanceRate)}${idx == 0 && _dueFine > 0 ? ' • Late Fine: ${widget.currencyFmt.format(_dueFine)}' : ''}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.slate600),
                                  ),
                                  if (_hasVehicles)
                                    InkWell(
                                      onTap: () => _toggleParking(idx, !incParking),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: Checkbox(
                                              value: incParking,
                                              onChanged: (val) => _toggleParking(idx, val ?? false),
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Include Parking (${widget.currencyFmt.format((_carCount * _carRate) + (_bikeCount * _bikeRate))})',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: incParking ? FontWeight.bold : FontWeight.normal,
                                              color: incParking ? AppColors.primary : AppColors.slate500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    const Text('No Vehicle Registered', style: TextStyle(fontSize: 10.5, color: AppColors.slate400)),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Total Summary Banner Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Flat ${widget.flat} • $mCount Month${mCount > 1 ? 's' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.slate900),
                            ),
                            Text(
                              'Maint: ${widget.currencyFmt.format(totalMaint)}${totalPark > 0 ? ' • Park: ${widget.currencyFmt.format(totalPark)}' : ''}${_dueFine > 0 ? ' • Late Fine: ${widget.currencyFmt.format(_dueFine)}' : ''}',
                              style: const TextStyle(fontSize: 11, color: AppColors.slate600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Total Payable', style: TextStyle(fontSize: 10, color: AppColors.slate600)),
                          Text(
                            widget.currencyFmt.format(totalPayable),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // TabBar Navigation (Online vs Offline)
              Container(
                decoration: BoxDecoration(
                  color: AppColors.slate100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.slate200),
                ),
                child: TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.slate600,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
                    ],
                  ),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.language_rounded, size: 16),
                      text: 'Online Payments',
                    ),
                    Tab(
                      icon: Icon(Icons.storefront_outlined, size: 16),
                      text: 'Offline to Cashier',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // TabBar View Content
              SizedBox(
                height: 390,
                child: TabBarView(
                  children: [
                    // Tab 1: Online Payments
                    _buildOnlineTab(),

                    // Tab 2: Offline Payments
                    _buildOfflineTab(totalPayable),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineTab() {
    return Form(
      key: _onlineFormKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode Switcher: UPI vs Bank Transfer
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('UPI (GPay/Paytm)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    selected: _onlineMode == 'UPI',
                    selectedColor: AppColors.primarySurface,
                    onSelected: (sel) {
                      if (sel) setState(() => _onlineMode = 'UPI');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Bank / NEFT / IMPS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    selected: _onlineMode == 'Bank Transfer / NEFT',
                    selectedColor: AppColors.primarySurface,
                    onSelected: (sel) {
                      if (sel) setState(() => _onlineMode = 'Bank Transfer / NEFT');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Bank / UPI Details Card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.infoSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.infoBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance_rounded, size: 16, color: AppColors.info),
                      const SizedBox(width: 6),
                      Text(
                        _onlineMode == 'UPI' ? 'Society UPI Details' : 'Society Bank Account Details',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.infoDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_onlineMode == 'UPI') ...[
                    Text('UPI ID: ${SocietyConfig.upiId}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate800)),
                    Text('Name: ${SocietyConfig.accountHolderName}', style: const TextStyle(fontSize: 11, color: AppColors.slate600)),
                  ] else ...[
                    Text('Bank: ${SocietyConfig.bankName} • A/C: ${SocietyConfig.accountNumber}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate800)),
                    Text('IFSC: ${SocietyConfig.ifscCode} • Branch: ${SocietyConfig.branchName}', style: const TextStyle(fontSize: 11, color: AppColors.slate600)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 16-Character UTR Input Field
            TextFormField(
              controller: _onlineUtrController,
              maxLength: 16,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: _onlineMode == 'UPI' ? '16-Character UTR Number *' : '16-Character Bank Reference Number *',
                hintText: 'e.g. UPI202609071234',
                prefixIcon: const Icon(Icons.tag_rounded, size: 18),
                helperText: 'Enter exact 16-character alphanumeric UTR / Reference ID',
                helperMaxLines: 2,
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter the 16-character UTR / Ref number';
                }
                final clean = val.trim();
                if (clean.length != 16) {
                  return 'Must be exactly 16 characters (Current: ${clean.length})';
                }
                if (!RegExp(r'^[a-zA-Z0-9]{16}$').hasMatch(clean)) {
                  return 'Only letters and numbers allowed (no special characters)';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),

            // Submit Online Payment Button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isProcessing ? null : _submitOnlinePayment,
                icon: _isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _isProcessing ? 'Submitting Online Payment...' : 'Submit Online Payment for Approval',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineTab(double totalPayable) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Switcher for Cheque vs Cash
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('Cheque to Cashier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  selected: _offlineMode == 'Cheque',
                  selectedColor: AppColors.secondarySurface,
                  onSelected: (sel) {
                    if (sel) setState(() => _offlineMode = 'Cheque');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.payments_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Cash to Cashier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  selected: _offlineMode == 'Cash',
                  selectedColor: AppColors.successSurface,
                  onSelected: (sel) {
                    if (sel) setState(() => _offlineMode = 'Cash');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_offlineMode == 'Cheque') ...[
            // Cheque Submission Form
            Form(
              key: _offlineFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.secondarySurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: AppColors.secondary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Please issue Cheque in favor of "Society Maintenance Account" and hand over to Treasurer/Cashier.',
                            style: TextStyle(fontSize: 11, color: AppColors.secondaryDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _chequeNoController,
                    keyboardType: TextInputType.number,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'Cheque Number *',
                      hintText: 'e.g. 049210',
                      prefixIcon: Icon(Icons.numbers_rounded, size: 18),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter the cheque number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  TextFormField(
                    controller: _chequeBankController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Issuing Bank Name *',
                      hintText: 'e.g. SBI, HDFC, ICICI, Axis Bank',
                      prefixIcon: Icon(Icons.account_balance_rounded, size: 18),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter your bank name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _isProcessing ? null : _submitOfflineCheque,
                      icon: _isProcessing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        _isProcessing ? 'Submitting Cheque...' : 'Submit Cheque Details for Admin Approval',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Cash Handover Instructions Card (No doc submission required)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.successSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.successBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), shape: BoxShape.circle),
                        child: const Icon(Icons.payments_rounded, color: AppColors.successDark, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cash to Cashier / Treasurer',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.successDark),
                            ),
                            Text(
                              'No app document submission required',
                              style: TextStyle(fontSize: 11, color: AppColors.slate600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: AppColors.successBorder),
                  const SizedBox(height: 8),
                  Text(
                    '1. Please visit the Society Office and hand over the exact cash of ${widget.currencyFmt.format(totalPayable)} to the Society Cashier / Treasurer.',
                    style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.slate800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '2. Office Hours: ${SocietyConfig.officeHours}. Location: ${SocietyConfig.officeAddress}.',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate800),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '3. Admin / Cashier will directly record the payment in Accounts and an official receipt voucher will be generated for your flat automatically.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.slate800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade800,
                  side: BorderSide(color: Colors.green.shade400),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('I Understand / Close', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------ Pre-Approve Visitor Screen ------
class PreApproveVisitorScreen extends StatefulWidget {
  final String? userFlat;
  const PreApproveVisitorScreen({super.key, this.userFlat});

  @override
  State<PreApproveVisitorScreen> createState() => _PreApproveVisitorScreenState();
}

class _PreApproveVisitorScreenState extends State<PreApproveVisitorScreen> {
  final _formKey = GlobalKey<FormState>();
  String _visitorName = '';
  String _purpose = 'Guest';
  bool _isComingByCar = false;
  late final TextEditingController _vehicleCtrl;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _vehicleCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _vehicleCtrl.dispose();
    super.dispose();
  }

  Future<void> _generatePass() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      setState(() => _isLoading = true);
      
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          throw Exception('User is not logged in');
        }
        // Fetch host flat number
        String flatNumber = widget.userFlat ?? '';
        if (flatNumber.isEmpty) {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          flatNumber = userDoc.data()?['flatNumber'] ?? 'Unknown';
        }

        final vehicleNumber = _isComingByCar ? _vehicleCtrl.text.trim().toUpperCase() : '';

        final passResult = await VisitorPassService.createVisitorPass(
          residentUid: user.uid,
          flatNumber: flatNumber,
          visitorName: _visitorName,
          phone: '',
          purpose: _purpose,
          isComingByCar: _isComingByCar,
          vehicleNumber: vehicleNumber,
        );

        final passCode = passResult['passCode'] as String;

        if (!mounted) return;
        
        await AppDialog.show(
          context: context,
          title: 'Gate Pass Generated',
          subtitle: 'Share code with $_visitorName (valid for 8 hours • single-use only)',
          icon: Icons.qr_code_2_rounded,
          iconColor: AppColors.primary,
          iconBgColor: AppColors.primarySurface,
          body: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Text('6-Digit Security Pass Code', style: TextStyle(fontSize: 12, color: AppColors.slate600, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    Text(
                      passCode,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 4, color: AppColors.primaryDark),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.timer_outlined, size: 13, color: Colors.amber.shade900),
                          const SizedBox(width: 5),
                          Text(
                            'Active for 8 hours • Single-use only',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                          ),
                        ],
                      ),
                    ),
                    if (vehicleNumber.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.directions_car_rounded, size: 13, color: AppColors.primary),
                            const SizedBox(width: 5),
                            Text(
                              'Vehicle: $vehicleNumber',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Visitor: $_visitorName • Purpose: $_purpose • Flat: $flatNumber${vehicleNumber.isNotEmpty ? ' • Vehicle: $vehicleNumber' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.slate600),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(); // Close screen
              },
              child: const Text('Done & Return'),
            ),
          ],
        );
      } catch (e) {
        if (!mounted) return;
        AppFeedback.showError(context, 'Error generating visitor pass: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-Approve Visitor'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: AppDecorations.card(),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppDecorations.iconContainer(
                      icon: Icons.person_add_rounded,
                      color: AppColors.primary,
                      surfaceColor: AppColors.primarySurface,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pre-approve Entry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.slate900)),
                          Text('Generate an instant gate pass code for the security gate', style: TextStyle(fontSize: 12, color: AppColors.slate500)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.slate200),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Visitor Name *',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  validator: (val) => val == null || val.trim().isEmpty ? 'Please enter visitor name' : null,
                  onSaved: (val) => _visitorName = val!.trim(),
                ),
                // Visit Purpose Dropdown with isExpanded to prevent horizontal overflow
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _purpose,
                  decoration: const InputDecoration(
                    labelText: 'Purpose of Visit',
                    prefixIcon: Icon(Icons.work_outline_rounded, size: 20),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Guest', child: Text('Guest / Family', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Delivery', child: Text('Delivery (Amazon/Swiggy/Zomato)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Service', child: Text('Service / Repair / Electrician', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) => setState(() => _purpose = val!),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: _isComingByCar ? AppColors.primarySurface.withValues(alpha: 0.5) : AppColors.slate50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isComingByCar ? AppColors.primary.withValues(alpha: 0.4) : AppColors.slate200,
                    ),
                  ),
                  child: SwitchListTile.adaptive(
                    title: const Text(
                      'Arriving by car / vehicle?',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.slate800),
                    ),
                    subtitle: Text(
                      _isComingByCar ? 'Vehicle details will be verified at gate' : 'Enable if your guest is driving a car or bike',
                      style: const TextStyle(fontSize: 12, color: AppColors.slate500),
                    ),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isComingByCar ? AppColors.primarySurface : AppColors.slate100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.directions_car_rounded,
                        color: _isComingByCar ? AppColors.primary : AppColors.slate500,
                        size: 22,
                      ),
                    ),
                    value: _isComingByCar,
                    activeTrackColor: AppColors.primary,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    onChanged: (val) {
                      setState(() {
                        _isComingByCar = val;
                        if (!_isComingByCar) {
                          _vehicleCtrl.clear();
                        }
                      });
                    },
                  ),
                ),
                if (_isComingByCar) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _vehicleCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Vehicle Number *',
                      hintText: 'e.g. WB 06 A 1234',
                      prefixIcon: Icon(Icons.pin_outlined, size: 20),
                    ),
                    validator: (val) {
                      if (_isComingByCar && (val == null || val.trim().isEmpty)) {
                        return 'Please enter vehicle registration number';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isLoading ? null : _generatePass,
                    icon: _isLoading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.qr_code_2_rounded, size: 20),
                    label: Text(
                      _isLoading ? 'Generating Pass...' : 'Generate Pass Code',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ResidentHelpdeskTab extends StatefulWidget {
  final String? userFlat;
  const ResidentHelpdeskTab({super.key, this.userFlat});

  @override
  State<ResidentHelpdeskTab> createState() => _ResidentHelpdeskTabState();
}

class _ResidentHelpdeskTabState extends State<ResidentHelpdeskTab> {
  Future<void> _showRaiseTicketDialog() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String category = 'Maintenance';
    final formKey = GlobalKey<FormState>();

    try {
      await AppDialog.show(
        context: context,
        title: 'Raise a Helpdesk Ticket',
        subtitle: 'Submit a complaint or service request to Society Admin',
        icon: Icons.support_agent_rounded,
        iconColor: AppColors.primary,
        iconBgColor: AppColors.primarySurface,
        body: StatefulBuilder(
          builder: (ctx, setDlgState) {
            return Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Helpdesk Category Dropdown with isExpanded to prevent horizontal overflow
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category *'),
                    items: const [
                      DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance / Electrical / Plumbing', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Security', child: Text('Security & Gate', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Cleanliness', child: Text('Cleanliness & Waste Management', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'Other', child: Text('Other / General Query', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setDlgState(() => category = val!),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Issue Subject / Title *',
                      hintText: 'e.g. Water seepage in master bedroom balcony',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Detailed Description *',
                      hintText: 'Describe the issue clearly...',
                    ),
                    maxLines: 4,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Description is required' : null,
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) {
                  if (context.mounted) AppFeedback.showError(context, 'Session expired. Please log in again.');
                  return;
                }
                final uid = user.uid;
                String flatNumber = widget.userFlat ?? '';
                if (flatNumber.isEmpty) {
                  final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                  flatNumber = userDoc.data()?['flatNumber'] ?? 'Unknown';
                }
                
                await FirebaseFirestore.instance.collection('complaints').add({
                  'title': titleController.text.trim(),
                  'description': descController.text.trim(),
                  'category': category,
                  'status': 'OPEN',
                  'residentUid': uid,
                  'flatNumber': flatNumber,
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                
                if (mounted) {
                  Navigator.pop(context);
                  AppFeedback.showSuccess(context, 'Ticket submitted successfully!');
                }
              } catch (e) {
                if (mounted) {
                  AppFeedback.showError(context, 'Error raising ticket: $e');
                }
              }
            },
            child: const Text('Submit Ticket'),
          ),
        ],
      );
    } finally {
      titleController.dispose();
      descController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('complaints')
            .where('residentUid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: AppColors.error)));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5));
          }
          var docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppDecorations.iconContainer(
                      icon: Icons.support_agent_rounded,
                      color: AppColors.slate400,
                      surfaceColor: AppColors.slate100,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No tickets raised yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.slate700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap "Raise Ticket" below to report an issue or request maintenance assistance.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.slate500, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }
          
          // Sort by createdAt locally
          docs.sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime); // descending
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final status = (data['status'] ?? 'OPEN').toString().toUpperCase();
              
              Widget badge;
              if (status == 'RESOLVED') {
                badge = AppBadge.success('RESOLVED');
              } else if (status == 'IN_PROGRESS') {
                badge = AppBadge.warning('IN PROGRESS');
              } else {
                badge = AppBadge.error('OPEN');
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppDecorations.card(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            data['title'] ?? 'No Title',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slate900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        badge,
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data['description'] ?? '',
                      style: const TextStyle(fontSize: 13, color: AppColors.slate600, height: 1.3),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.slate100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            data['category'] ?? 'General',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate700),
                          ),
                        ),
                        if (data['createdAt'] is Timestamp)
                          Text(
                            DateFormat('dd MMM yyyy, hh:mm a').format((data['createdAt'] as Timestamp).toDate()),
                            style: const TextStyle(fontSize: 11, color: AppColors.slate400),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _showRaiseTicketDialog,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Raise Ticket', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}
