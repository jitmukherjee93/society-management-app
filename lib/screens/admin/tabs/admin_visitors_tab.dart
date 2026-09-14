import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/app_dialog.dart';

// ============================================================================
// ADMIN VISITOR & GATE ACTIVITY AUDIT TAB
// ============================================================================
// This screen provides society administrators with real-time surveillance and
// historical audit logs of all gate movements:
//
// 1. Live Inside Campus Tracking:
//    - Tracks all currently present visitors (`status == CHECKED_IN`).
//    - Real-time stay duration counter (`entryTime` to present).
//
// 2. Comprehensive Filter Engine:
//    - By Status: All, Checked-In (Inside), Checked-Out (Exited), Pending Approvals, Vehicle Entries.
//    - By Date Range: All time, Today only, Past 7 days.
//    - By Search Query: Visitor name, host flat number, phone number, vehicle plate, purpose.
//
// 3. Security Audit Details:
//    - Displays gate name, security guard name, check-in and check-out timestamps,
//      visitor vehicle details, and uploaded ID/camera photos.
// ============================================================================

/// Screen displaying visitor tracking, gate logs, and campus occupancy for Admins.
class AdminVisitorsTab extends StatefulWidget {
  /// Optional initial search string (e.g. passed from dashboard quick link).
  final String? initialFilter;

  /// Optional initial status filter (e.g. 'CHECKED_IN').
  final String? initialStatus;

  const AdminVisitorsTab({
    super.key,
    this.initialFilter,
    this.initialStatus,
  });

  @override
  State<AdminVisitorsTab> createState() => _AdminVisitorsTabState();
}

class _AdminVisitorsTabState extends State<AdminVisitorsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'ALL'; // ALL, CHECKED_IN, CHECKED_OUT, PENDING, VEHICLES
  String _dateFilter = 'ALL'; // ALL, TODAY, 7_DAYS

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null && widget.initialFilter!.isNotEmpty) {
      _searchController.text = widget.initialFilter!;
      _searchQuery = widget.initialFilter!.trim().toLowerCase();
    }
    if (widget.initialStatus != null && widget.initialStatus!.isNotEmpty) {
      _statusFilter = widget.initialStatus!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool _isPast7Days(DateTime date) {
    final now = DateTime.now();
    return date.isAfter(now.subtract(const Duration(days: 7)));
  }

  DateTime? _getEffectiveTimestamp(Map<String, dynamic> data) {
    return (data['exitTime'] as Timestamp?)?.toDate() ??
        (data['entryTime'] as Timestamp?)?.toDate() ??
        (data['usedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();
  }

  String _formatStayDuration(DateTime? entry, DateTime? exit) {
    if (entry == null) return '';
    final end = exit ?? DateTime.now();
    final diff = end.difference(entry);
    if (diff.isNegative) return '';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    }
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('visitors').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Error loading visitor activities: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];

          // Sort in-memory descending by most recent activity timestamp
          final sortedDocs = allDocs.toList()
            ..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = _getEffectiveTimestamp(aData) ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bTime = _getEffectiveTimestamp(bData) ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

          // Metrics calculation
          final inCampusCount = sortedDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return (data['status'] ?? '').toString().toUpperCase() == 'CHECKED_IN';
          }).length;

          final exitedTodayCount = sortedDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final isCheckedOut = (data['status'] ?? '').toString().toUpperCase() == 'CHECKED_OUT';
            if (!isCheckedOut) return false;
            final exitTime = (data['exitTime'] as Timestamp?)?.toDate();
            return exitTime != null && _isToday(exitTime);
          }).length;

          final preApprovedPendingCount = sortedDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return (data['status'] ?? '').toString().toUpperCase() == 'PENDING';
          }).length;

          final totalCount = sortedDocs.length;

          // Filter documents based on search, status, and date
          final filteredDocs = sortedDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['status'] ?? '').toString().toUpperCase();
            final isComingByCar = data['isComingByCar'] == true ||
                (data['vehicleNumber'] ?? '').toString().trim().isNotEmpty;

            // Status Filter
            if (_statusFilter == 'CHECKED_IN' && status != 'CHECKED_IN') return false;
            if (_statusFilter == 'CHECKED_OUT' && status != 'CHECKED_OUT') return false;
            if (_statusFilter == 'PENDING' && status != 'PENDING') return false;
            if (_statusFilter == 'VEHICLES' && !isComingByCar) return false;

            // Date Filter
            final effectiveTime = _getEffectiveTimestamp(data);
            if (_dateFilter == 'TODAY') {
              if (effectiveTime == null || !_isToday(effectiveTime)) return false;
            } else if (_dateFilter == '7_DAYS') {
              if (effectiveTime == null || !_isPast7Days(effectiveTime)) return false;
            }

            // Search Filter
            if (_searchQuery.isNotEmpty) {
              final name = (data['visitorName'] ?? '').toString().toLowerCase();
              final phone = (data['phone'] ?? '').toString().toLowerCase();
              final flat = (data['hostFlatNumber'] ?? data['flatNumber'] ?? '').toString().toLowerCase();
              final vehicle = (data['vehicleNumber'] ?? '').toString().toLowerCase();
              final purpose = (data['purpose'] ?? '').toString().toLowerCase();
              final guard = (data['guardName'] ?? '').toString().toLowerCase();
              final gate = (data['gateName'] ?? '').toString().toLowerCase();
              final passCode = (data['passCode'] ?? '').toString().toLowerCase();

              final matches = name.contains(_searchQuery) ||
                  phone.contains(_searchQuery) ||
                  flat.contains(_searchQuery) ||
                  vehicle.contains(_searchQuery) ||
                  purpose.contains(_searchQuery) ||
                  guard.contains(_searchQuery) ||
                  gate.contains(_searchQuery) ||
                  passCode.contains(_searchQuery);
              if (!matches) return false;
            }

            return true;
          }).toList();

          return Column(
            children: [
              // Top KPI Summary Cards Bar
              _buildMetricsHeader(
                inCampusCount: inCampusCount,
                exitedTodayCount: exitedTodayCount,
                preApprovedCount: preApprovedPendingCount,
                totalCount: totalCount,
              ),

              // Filter & Search Controls
              _buildFilterToolbar(context),

              // Visitor Activities List
              Expanded(
                child: filteredDocs.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredDocs.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final doc = filteredDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          return _buildVisitorCard(context, doc.id, data);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricsHeader({
    required int inCampusCount,
    required int exitedTodayCount,
    required int preApprovedCount,
    required int totalCount,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          final itemWidth = isNarrow ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4;

          return Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _buildMetricCard(
                width: itemWidth,
                title: 'In-Campus Now',
                count: inCampusCount,
                icon: Icons.shield_rounded,
                color: const Color(0xFF0D9488),
                bgColor: const Color(0xFFF0FDFA),
                isLive: true,
                onTap: () => setState(() => _statusFilter = 'CHECKED_IN'),
              ),
              _buildMetricCard(
                width: itemWidth,
                title: 'Exited Today',
                count: exitedTodayCount,
                icon: Icons.logout_rounded,
                color: const Color(0xFF2563EB),
                bgColor: const Color(0xFFEFF6FF),
                onTap: () {
                  setState(() {
                    _statusFilter = 'CHECKED_OUT';
                    _dateFilter = 'TODAY';
                  });
                },
              ),
              _buildMetricCard(
                width: itemWidth,
                title: 'Expected / Pre-approved',
                count: preApprovedCount,
                icon: Icons.qr_code_rounded,
                color: const Color(0xFFD97706),
                bgColor: const Color(0xFFFFFBEB),
                onTap: () => setState(() => _statusFilter = 'PENDING'),
              ),
              _buildMetricCard(
                width: itemWidth,
                title: 'Total Logs Recorded',
                count: totalCount,
                icon: Icons.history_rounded,
                color: const Color(0xFF475569),
                bgColor: const Color(0xFFF1F5F9),
                onTap: () {
                  setState(() {
                    _statusFilter = 'ALL';
                    _dateFilter = 'ALL';
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required double width,
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    required Color bgColor,
    bool isLive = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                      if (isLive) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search & Date Filter Row
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: 'Search visitor, flat (e.g. B-101), vehicle, phone, guard...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.cardSurfaceSecondary,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Date Filter Dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.cardSurfaceSecondary,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _dateFilter,
                    icon: const Icon(Icons.calendar_today_rounded, size: 15, color: AppColors.textSecondary),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('All Dates')),
                      DropdownMenuItem(value: 'TODAY', child: Text('Today Only')),
                      DropdownMenuItem(value: '7_DAYS', child: Text('Past 7 Days')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _dateFilter = val);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Status Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('ALL', 'All Visitors', Icons.people_alt_outlined),
                const SizedBox(width: 8),
                _buildFilterChip('CHECKED_IN', 'In-Campus Now', Icons.login_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('CHECKED_OUT', 'Checked Out', Icons.logout_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('PENDING', 'Pre-Approved Passes', Icons.qr_code_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('VEHICLES', 'With Car / Vehicle', Icons.directions_car_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final isSelected = _statusFilter == value;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitorCard(BuildContext context, String docId, Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toUpperCase();
    final visitorName = (data['visitorName'] ?? 'Guest').toString().trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final flatNumber = (data['hostFlatNumber'] ?? data['flatNumber'] ?? '').toString().trim();
    final purpose = (data['purpose'] ?? 'Guest / Personal').toString().trim();
    final vehicleNumber = (data['vehicleNumber'] ?? '').toString().trim();
    final isComingByCar = data['isComingByCar'] == true || vehicleNumber.isNotEmpty;
    final photoUrl = data['photoUrl']?.toString();
    final passCode = data['passCode']?.toString();

    final entryTime = (data['entryTime'] as Timestamp?)?.toDate();
    final exitTime = (data['exitTime'] as Timestamp?)?.toDate();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    final entryGate = (data['gateName'] ?? 'Main Gate').toString();
    final checkInGuard = (data['guardName'] ?? 'Security Guard').toString();
    final checkOutGuard = (data['checkedOutByGuard'] ?? data['guardName'] ?? 'Security Guard').toString();

    final isInCampus = status == 'CHECKED_IN';
    final isCheckedOut = status == 'CHECKED_OUT';
    final isPending = status == 'PENDING';

    Color statusColor;
    Color statusBgColor;
    String statusLabel;
    IconData statusIcon;

    if (isInCampus) {
      statusColor = const Color(0xFF0D9488);
      statusBgColor = const Color(0xFFF0FDFA);
      statusLabel = 'IN CAMPUS';
      statusIcon = Icons.check_circle_rounded;
    } else if (isCheckedOut) {
      statusColor = const Color(0xFF475569);
      statusBgColor = const Color(0xFFF1F5F9);
      statusLabel = 'CHECKED OUT';
      statusIcon = Icons.logout_rounded;
    } else if (isPending) {
      statusColor = const Color(0xFFD97706);
      statusBgColor = const Color(0xFFFFFBEB);
      statusLabel = 'PRE-APPROVED';
      statusIcon = Icons.schedule_rounded;
    } else {
      statusColor = AppColors.error;
      statusBgColor = const Color(0xFFFEF2F2);
      statusLabel = status;
      statusIcon = Icons.cancel_rounded;
    }

    final stayDuration = _formatStayDuration(entryTime, exitTime);

    return InkWell(
      onTap: () => _showVisitorDetailsDialog(context, docId, data),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isInCampus ? const Color(0xFF99F6E4) : AppColors.border,
            width: isInCampus ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Flat Badge, Status Chip, and Duration
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.apartment_rounded, size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        flatNumber.isNotEmpty ? 'Flat $flatNumber' : 'General Society',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (stayDuration.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isCheckedOut ? 'Stay: $stayDuration' : 'Inside: $stayDuration',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isInCampus ? const Color(0xFF0D9488) : AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Row 2: Visitor Name, Purpose, and Photo Thumbnail
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photoUrl != null && photoUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      photoUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _buildDefaultAvatar(purpose),
                    ),
                  )
                else
                  _buildDefaultAvatar(purpose),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              visitorName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (phone.isNotEmpty)
                            Text(
                              phone,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              purpose,
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                            ),
                          ),
                          if (isComingByCar && vehicleNumber.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.directions_car_rounded, size: 12, color: Colors.blue),
                                  const SizedBox(width: 4),
                                  Text(
                                    vehicleNumber,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Row 3: Timestamps, Gate & Guard Audit Trail
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.login_rounded, size: 13, color: Colors.teal),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entryTime != null
                              ? 'In: ${DateFormat('hh:mm a, dd MMM').format(entryTime)} ($entryGate - $checkInGuard)'
                              : (createdAt != null
                                  ? 'Pass: ${DateFormat('hh:mm a, dd MMM').format(createdAt)}'
                                  : 'Expected entry'),
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCheckedOut && exitTime != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.logout_rounded, size: 13, color: Colors.blueGrey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Out: ${DateFormat('hh:mm a, dd MMM').format(exitTime)} ($checkOutGuard)',
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (isPending && passCode != null) ...[
                  Text(
                    'OTP: $passCode',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xFFD97706),
                    ),
                  ),
                ],
                const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar(String purpose) {
    final p = purpose.toLowerCase();
    IconData icon = Icons.person_rounded;
    Color iconColor = AppColors.primary;
    Color bgColor = AppColors.primaryLight;

    if (p.contains('delivery') || p.contains('courier') || p.contains('amazon') || p.contains('swiggy')) {
      icon = Icons.local_shipping_rounded;
      iconColor = Colors.deepOrange;
      bgColor = Colors.deepOrange.shade50;
    } else if (p.contains('cab') || p.contains('uber') || p.contains('ola') || p.contains('taxi')) {
      icon = Icons.local_taxi_rounded;
      iconColor = Colors.amber.shade900;
      bgColor = Colors.amber.shade50;
    } else if (p.contains('maintenance') || p.contains('repair') || p.contains('service')) {
      icon = Icons.build_rounded;
      iconColor = Colors.indigo;
      bgColor = Colors.indigo.shade50;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 22, color: iconColor),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.no_accounts_rounded, size: 40, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            const Text(
              'No visitor records match the selected filters.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Guest arrivals and exits logged by gate security will appear here automatically.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _statusFilter = 'ALL';
                  _dateFilter = 'ALL';
                });
              },
              child: const Text('Reset All Filters'),
            ),
          ],
        ),
      ),
    );
  }

  void _showVisitorDetailsDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toUpperCase();
    final visitorName = (data['visitorName'] ?? 'Guest').toString().trim();
    final phone = (data['phone'] ?? 'N/A').toString().trim();
    final flatNumber = (data['hostFlatNumber'] ?? data['flatNumber'] ?? 'N/A').toString().trim();
    final purpose = (data['purpose'] ?? 'Guest / Personal').toString().trim();
    final vehicleNumber = (data['vehicleNumber'] ?? '').toString().trim();
    final isComingByCar = data['isComingByCar'] == true || vehicleNumber.isNotEmpty;
    final photoUrl = data['photoUrl']?.toString();
    final passCode = data['passCode']?.toString();

    final entryTime = (data['entryTime'] as Timestamp?)?.toDate();
    final exitTime = (data['exitTime'] as Timestamp?)?.toDate();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();

    final gateName = (data['gateName'] ?? 'Main Gate').toString();
    final guardName = (data['guardName'] ?? 'Security Guard').toString();
    final checkedInBy = data['checkedInBy']?.toString() ?? 'N/A';
    final checkedOutBy = data['checkedOutBy']?.toString() ?? 'N/A';

    final stayDuration = _formatStayDuration(entryTime, exitTime);

    AppDialog.show(
      context: context,
      title: 'Visitor Activity Record',
      subtitle: 'Audit ID: $docId',
      icon: Icons.badge_rounded,
      iconColor: AppColors.primary,
      maxWidth: 520,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header summary with photo if available
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (photoUrl != null && photoUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      photoUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _buildDefaultAvatar(purpose),
                    ),
                  )
                else
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_rounded, size: 36, color: AppColors.primary),
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visitorName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text('Contact: $phone', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Flat $flatNumber',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),

            // Detailed Audit Fields
            _buildDetailRow('Purpose of Visit', purpose),
            if (isComingByCar || vehicleNumber.isNotEmpty)
              _buildDetailRow('Vehicle Registration', vehicleNumber.isNotEmpty ? vehicleNumber : 'Arrived by car'),
            if (passCode != null)
              _buildDetailRow('Generated Passcode', '$passCode (Single-use OTP)'),
            if (createdAt != null)
              _buildDetailRow('Pass Created At', DateFormat('hh:mm a, dd MMMM yyyy').format(createdAt)),
            if (expiresAt != null)
              _buildDetailRow('Pass Validity Expiry', DateFormat('hh:mm a, dd MMMM yyyy').format(expiresAt)),
            _buildDetailRow('Gate & Post', gateName),
            _buildDetailRow('Gate Guard On Duty', guardName),
            if (entryTime != null)
              _buildDetailRow('Check-In Time', DateFormat('hh:mm:ss a, dd MMMM yyyy').format(entryTime)),
            if (exitTime != null)
              _buildDetailRow('Check-Out Time', DateFormat('hh:mm:ss a, dd MMMM yyyy').format(exitTime)),
            if (stayDuration.isNotEmpty)
              _buildDetailRow('Total Campus Stay', stayDuration),
            if (checkedInBy != 'N/A')
              _buildDetailRow('Check-In Guard UID', checkedInBy),
            if (checkedOutBy != 'N/A')
              _buildDetailRow('Check-Out Guard UID', checkedOutBy),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
