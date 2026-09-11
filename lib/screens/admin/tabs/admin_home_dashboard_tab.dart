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
    final isDesktop = MediaQuery.sizeOf(context).width >= 1050;
    final timeStr = DateFormat('hh:mm a').format(_lastRefreshed);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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

          // 2x2 Grid for Actions Pending
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 14) / 2;
              return Wrap(
                spacing: 14,
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
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Member / Vehicle Reqs',
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
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];
                      final openCount = docs.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final status = (data['status'] ?? '').toString().toUpperCase();
                        return status != 'RESOLVED' && status != 'CLOSED';
                      }).length;

                      return _buildActionTile(
                        width: itemWidth,
                        title: 'Escalated Tickets',
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

          // 2x2 Grid for Society Stats
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 14) / 2;
              return Wrap(
                spacing: 14,
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
                        title: 'Active Residents / Users',
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
                        countString: '$paidCount/11',
                        badgeText: '$percent%',
                        badgeColor: paidCount == 11 ? Colors.green : Colors.indigo,
                        onTap: () => widget.onNavigateToTab(2), // Accounts Tab
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
    int? count,
    String? countString,
    String? badgeText,
    Color? badgeColor,
    bool highlight = false,
    Color? highlightColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      hoverColor: Colors.grey.shade50,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlight ? (highlightColor ?? AppColors.primary).withValues(alpha: 0.35) : AppColors.border,
            width: highlight ? 1.2 : 0.9,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badgeText != null) ...[
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (badgeColor ?? AppColors.primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (badgeColor ?? AppColors.primary).withValues(alpha: 0.3)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor ?? AppColors.primary,
                  ),
                ),
              ),
            ],
            Text(
              countString ?? '${count ?? 0}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: highlight ? (highlightColor ?? AppColors.primary) : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
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

