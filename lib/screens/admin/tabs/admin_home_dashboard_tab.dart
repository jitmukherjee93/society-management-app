import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_decorations.dart';
import '../../../models/accounting_heads.dart';
import '../../../services/staff_remuneration_service.dart';

class AdminHomeDashboardTab extends StatefulWidget {
  final void Function(int tabIndex, {String? subTab, String? filter}) onNavigateToTab;
  final VoidCallback? onOpenRecordExpense;
  final VoidCallback? onOpenPayStaffRemuneration;
  final VoidCallback? onOpenNotifications;

  const AdminHomeDashboardTab({
    super.key,
    required this.onNavigateToTab,
    this.onOpenRecordExpense,
    this.onOpenPayStaffRemuneration,
    this.onOpenNotifications,
  });

  @override
  State<AdminHomeDashboardTab> createState() => _AdminHomeDashboardTabState();
}

class _AdminHomeDashboardTabState extends State<AdminHomeDashboardTab> {
  DateTime _lastRefreshed = DateTime.now();

  void _refreshData() {
    setState(() {
      _lastRefreshed = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 1050;
    final isMobile = screenWidth < 600;
    final timeStr = DateFormat('hh:mm a').format(_lastRefreshed);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 14 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left 2/3: Action Cards & Society Stats
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildActionsPendingSection(timeStr),
                        const SizedBox(height: 20),
                        _buildSocietyOverviewSection(timeStr),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Right 1/3: What's New & Shortcuts
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWhatsNewCard(),
                        const SizedBox(height: 20),
                        _buildShortcutsCard(),
                        const SizedBox(height: 20),
                        _buildRecentActivityCard(),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildActionsPendingSection(timeStr),
                  const SizedBox(height: 20),
                  _buildSocietyOverviewSection(timeStr),
                  const SizedBox(height: 20),
                  _buildShortcutsCard(),
                  const SizedBox(height: 20),
                  _buildWhatsNewCard(),
                  const SizedBox(height: 20),
                  _buildRecentActivityCard(),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ─── Section 1: Actions Pending ─────────────────────────────────────────────
  Widget _buildActionsPendingSection(String timeStr) {
    return Container(
      decoration: AppDecorations.card(borderRadius: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.drag_indicator_rounded, size: 16, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'ACTIONS PENDING',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _refreshData,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        'Refresh Data',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.refresh_rounded, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Last Refreshed: $timeStr',
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Responsive Grid for Actions Pending (1 column on mobile, 2 columns on tablet/desktop)
          LayoutBuilder(
            builder: (context, constraints) {
              final isSingleCol = constraints.maxWidth < 480;
              final crossAxisCount = isSingleCol ? 1 : 2;
              const spacing = 12.0;
              final itemWidth = (constraints.maxWidth - ((crossAxisCount - 1) * spacing)) / crossAxisCount;
              return Wrap(
                spacing: spacing,
                runSpacing: 12,
                children: [
                  // 1. Payment Intimations / Approvals
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('maintenance_dues')
                        .where('status', isEqualTo: 'PAYMENT_PENDING_APPROVAL')
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Payment Intimations',
                        icon: Icons.payments_rounded,
                        count: count,
                        highlight: count > 0,
                        highlightColor: Colors.amber.shade700,
                        onTap: () => widget.onNavigateToTab(5), // Bills Tab
                      );
                    },
                  ),

                  // 2. Member / Move In / Vehicle Requests
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('notifications')
                        .where('targetRole', isEqualTo: 'ADMIN')
                        .where('type', isEqualTo: 'VEHICLE_UPDATE_REQUEST')
                        .limit(50)
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.where((d) => (d.data() as Map)['isRead'] != true).length ?? 0;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Member / Vehicle Reqs',
                        icon: Icons.directions_car_rounded,
                        count: count,
                        highlight: count > 0,
                        highlightColor: Colors.indigo,
                        onTap: () {
                          if (widget.onOpenNotifications != null) {
                            widget.onOpenNotifications!();
                          } else {
                            widget.onNavigateToTab(1); // Society/Flats Tab
                          }
                        },
                      );
                    },
                  ),

                  // 3. Escalated / Open Complaints
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('complaints')
                        .where('status', whereIn: ['OPEN', 'PENDING', 'IN_PROGRESS', 'ESCALATED'])
                        .limit(50)
                        .snapshots(),
                    builder: (context, snap) {
                      final openCount = snap.data?.docs.length ?? 0;

                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Escalated Tickets',
                        icon: Icons.support_agent_rounded,
                        count: openCount,
                        highlight: openCount > 0,
                        highlightColor: Colors.red.shade700,
                        onTap: () => widget.onNavigateToTab(4), // Helpdesk Tab
                      );
                    },
                  ),

                  // 4. Overdue Defaulter Bills
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('maintenance_dues')
                        .where('status', isEqualTo: 'UNPAID')
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Overdue Maintenance Dues',
                        icon: Icons.receipt_long_rounded,
                        count: count,
                        highlight: count > 0,
                        highlightColor: Colors.deepOrange,
                        onTap: () => widget.onNavigateToTab(5), // Bills Tab
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

  // ─── Section 2: Society Overview / Stats ──────────────────────────────────
  Widget _buildSocietyOverviewSection(String timeStr) {
    return Container(
      decoration: AppDecorations.card(borderRadius: 12),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.drag_indicator_rounded, size: 16, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'SOCIETY OVERVIEW & STATS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _refreshData,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        'Refresh Data',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.refresh_rounded, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Last Refreshed: $timeStr',
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Responsive Grid for Society Stats (1 col on mobile, 2 cols on tablet/desktop, 3 cols on wide screens)
          LayoutBuilder(
            builder: (context, constraints) {
              final isSingleCol = constraints.maxWidth < 480;
              final isThreeCol = constraints.maxWidth >= 820;
              final crossAxisCount = isSingleCol ? 1 : (isThreeCol ? 3 : 2);
              const spacing = 12.0;
              final itemWidth = (constraints.maxWidth - ((crossAxisCount - 1) * spacing)) / crossAxisCount;
              return Wrap(
                spacing: spacing,
                runSpacing: 12,
                children: [
                  // 1. Active Flats
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('flats').snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Active Flats',
                        icon: Icons.apartment_rounded,
                        iconColor: Colors.blue.shade700,
                        count: count > 0 ? count : 130,
                        onTap: () => widget.onNavigateToTab(1), // Society/Flats
                      );
                    },
                  ),

                  // 2. Active Residents / Users
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Active Residents',
                        icon: Icons.people_alt_rounded,
                        iconColor: const Color(0xFF059669),
                        count: count,
                        onTap: () => widget.onNavigateToTab(1), // Society/Flats
                      );
                    },
                  ),

                  // 3. Active Security Guards
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('role', isEqualTo: 'GUARD')
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      final onDutyCount = docs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return (data['status'] ?? 'ON_DUTY') == 'ON_DUTY';
                      }).length;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Active Guards on Duty',
                        icon: Icons.security_rounded,
                        iconColor: Colors.cyan.shade800,
                        count: onDutyCount,
                        onTap: () => widget.onNavigateToTab(1, subTab: 'guards'),
                      );
                    },
                  ),

                  // 4. Staff Payroll Progress for Current Month
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('society_transactions')
                        .where('accountHead', isEqualTo: 'Staff Remuneration')
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      final curMonth = DateFormat('MMMM yyyy').format(AccountingConfig.currentDate);
                      final service = StaffRemunerationService();
                      final statuses = service.computeMonthlyStatus(
                        selectedMonth: curMonth,
                        transactions: docs,
                      );
                      final paidCount = statuses.where((s) => s.isPaid).length;
                      final percent = ((paidCount / 11) * 100).toInt();

                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Staff Payroll ($curMonth)',
                        icon: Icons.badge_rounded,
                        iconColor: Colors.indigo.shade700,
                        countString: '$paidCount/11',
                        badgeText: '$percent%',
                        badgeColor: paidCount == 11 ? Colors.green : Colors.indigo,
                        onTap: () => widget.onNavigateToTab(2), // Accounts Tab
                      );
                    },
                  ),

                  // 5. Visitors Currently In-Campus
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('visitors')
                        .where('status', isEqualTo: 'CHECKED_IN')
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Visitors In-Campus',
                        icon: Icons.directions_walk_rounded,
                        count: count,
                        highlight: count > 0,
                        highlightColor: const Color(0xFF0D9488),
                        onTap: () => widget.onNavigateToTab(6), // Visitors Tab
                      );
                    },
                  ),

                  // 6. Pending Facility & Amenity Bookings (Community Hall & Society Ground advance approvals)
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('amenity_bookings')
                        .where('status', isEqualTo: 'PENDING_APPROVAL')
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Facility Bookings',
                        icon: Icons.event_available_rounded,
                        count: count,
                        highlight: count > 0,
                        highlightColor: Colors.deepPurple,
                        onTap: () => widget.onNavigateToTab(7), // Amenity Bookings Tab
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

  // ─── Reusable Metric / Action Tile (MyGate Style) ───────────────────────────
  Widget _buildActionTile({
    required double width,
    required String title,
    IconData? icon,
    Color? iconColor,
    int? count,
    String? countString,
    String? badgeText,
    Color? badgeColor,
    bool highlight = false,
    Color? highlightColor,
    required VoidCallback onTap,
  }) {
    final effectiveColor = highlightColor ?? iconColor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      hoverColor: effectiveColor.withValues(alpha: 0.04),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlight
                ? effectiveColor.withValues(alpha: 0.35)
                : AppColors.border,
            width: highlight ? 1.2 : 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: highlight
                  ? effectiveColor.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: effectiveColor),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (badgeText != null) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: (badgeColor ?? effectiveColor).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: (badgeColor ?? effectiveColor).withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: badgeColor ?? effectiveColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              countString ?? '${count ?? 0}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: highlight ? effectiveColor : AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: effectiveColor.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  // ─── Section 3: What's New / Announcements Feed ─────────────────────────────
  Widget _buildWhatsNewCard() {
    return Container(
      decoration: AppDecorations.card(borderRadius: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_rounded, size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Text(
                    "What's New & Notices",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              InkWell(
                onTap: () => widget.onNavigateToTab(3), // Announcements Tab
                child: const Row(
                  children: [
                    Text('See All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
                    Icon(Icons.chevron_right, size: 14, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('announcements')
                .orderBy('createdAt', descending: true)
                .limit(3)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text('No active society notices.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ),
                );
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] ?? 'Notice';
                  final desc = data['description'] ?? data['content'] ?? '';
                  final isUrgent = (data['priority'] ?? '').toString().toUpperCase() == 'URGENT';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isUrgent ? Colors.red.shade50 : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: isUrgent ? Colors.red.shade200 : Colors.teal.shade200),
                          ),
                          child: Text(
                            isUrgent ? 'URGENT' : 'NOTICE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isUrgent ? Colors.red.shade700 : Colors.teal.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  desc,
                                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Section 4: Quick Action Shortcuts (MyGate Style) ──────────────────────
  Widget _buildShortcutsCard() {
    final shortcuts = [
      _ShortcutItem(
        icon: Icons.campaign_rounded,
        label: 'Notices',
        color: Colors.blue.shade700,
        backgroundColor: Colors.blue.shade50,
        onTap: () => widget.onNavigateToTab(3),
      ),
      _ShortcutItem(
        icon: Icons.support_agent_rounded,
        label: 'Helpdesk',
        color: Colors.purple.shade700,
        backgroundColor: Colors.purple.shade50,
        onTap: () => widget.onNavigateToTab(4),
      ),
      _ShortcutItem(
        icon: Icons.receipt_long_rounded,
        label: 'Bills',
        color: Colors.teal.shade700,
        backgroundColor: Colors.teal.shade50,
        onTap: () => widget.onNavigateToTab(5),
      ),
      _ShortcutItem(
        icon: Icons.account_balance_wallet_rounded,
        label: 'Accounts',
        color: Colors.indigo.shade700,
        backgroundColor: Colors.indigo.shade50,
        onTap: () => widget.onNavigateToTab(2),
      ),
      _ShortcutItem(
        icon: Icons.apartment_rounded,
        label: 'Flats',
        color: Colors.deepOrange.shade700,
        backgroundColor: Colors.deepOrange.shade50,
        onTap: () => widget.onNavigateToTab(1),
      ),
      _ShortcutItem(
        icon: Icons.badge_rounded,
        label: 'Pay Staff',
        color: Colors.green.shade800,
        backgroundColor: Colors.green.shade50,
        onTap: () {
          if (widget.onOpenPayStaffRemuneration != null) {
            widget.onOpenPayStaffRemuneration!();
          } else {
            widget.onNavigateToTab(2);
          }
        },
      ),
      // Quick access shortcut to Amenity bookings management
      _ShortcutItem(
        icon: Icons.event_available_rounded,
        label: 'Amenities',
        color: Colors.deepPurple.shade700,
        backgroundColor: Colors.deepPurple.shade50,
        onTap: () => widget.onNavigateToTab(7),
      ),
    ];

    return Container(
      decoration: AppDecorations.card(borderRadius: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SHORTCUTS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            alignment: WrapAlignment.start,
            children: shortcuts.map((s) {
              return InkWell(
                onTap: s.onTap,
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 68,
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: s.backgroundColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: s.color.withValues(alpha: 0.2)),
                        ),
                        child: Icon(s.icon, size: 20, color: s.color),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.label,
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─── Section 5: Recent Financial Activity ──────────────────────────────────
  Widget _buildRecentActivityCard() {
    return Container(
      decoration: AppDecorations.card(borderRadius: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'RECENT ACTIVITY',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textPrimary),
              ),
              InkWell(
                onTap: () => widget.onNavigateToTab(2), // Accounts Tab
                child: const Text('All Ledger →', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('society_transactions')
                .orderBy('paymentDate', descending: true)
                .limit(4)
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('No recent ledger transactions.', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  ),
                );
              }

              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final type = (data['type'] ?? '').toString().toUpperCase();
                  final isIncome = type == 'INCOME';
                  final head = data['accountHead'] ?? 'General';
                  final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                  final voucher = data['voucherNumber'] ?? 'EXP-000';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isIncome ? Colors.green.shade50 : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                            size: 14,
                            color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(head, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1),
                              Text(voucher, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        Text(
                          '${isIncome ? '+' : '-'} ₹${amount.toInt()}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ShortcutItem {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  _ShortcutItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });
}

