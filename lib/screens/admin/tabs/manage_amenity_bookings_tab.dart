import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../models/amenity_booking.dart';
import '../../../services/amenity_booking_service.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_decorations.dart';
import '../../../widgets/amenity_calendar_view.dart';
import '../../../widgets/app_feedback.dart';

// ============================================================================
// ADMIN AMENITY & FACILITY MANAGEMENT TAB
// ============================================================================
// Provides Society Administrators with full visibility and control over:
// 1. Community Hall bookings (₹4,000/day, ₹200 advance verification)
// 2. Society Ground bookings (₹500 for 2 days, ₹250 for 1 day)
// 3. Fitness Gym reservations (1-hour slots, guard key tracking)
// 4. Balance fee collection and integration into society transactions ledger
// ============================================================================

class ManageAmenityBookingsTab extends StatefulWidget {
  const ManageAmenityBookingsTab({super.key});

  @override
  State<ManageAmenityBookingsTab> createState() => _ManageAmenityBookingsTabState();
}

class _ManageAmenityBookingsTabState extends State<ManageAmenityBookingsTab> {
  // Filter states
  String _selectedStatus = 'ALL';
  String _selectedAmenity = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // Cached Stream to strictly adhere to Firebase listener scoping rules
  late final Stream<List<AmenityBooking>> _bookingsStream;

  @override
  void initState() {
    super.initState();
    // Initialize stream once in initState to avoid redundant subscriptions on rebuild
    _bookingsStream = AmenityBookingService.getAllBookingsStream(limit: 100);
    // Retroactively sync any confirmed bookings whose advance payment was not posted to ledger
    AmenityBookingService.syncApprovedBookingsToLedger();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<List<AmenityBooking>>(
        stream: _bookingsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allBookings = snapshot.data ?? [];

          // Compute quick metric counts for admin dashboard header
          final pendingCount = allBookings.where((b) => b.status == BookingStatus.pendingApproval).length;
          final confirmedCount = allBookings.where((b) => b.status == BookingStatus.confirmed).length;
          final completedCount = allBookings.where((b) => b.status == BookingStatus.completed).length;

          // Apply user filters
          final filteredBookings = allBookings.where((b) {
            if (_selectedStatus != 'ALL' && b.status.value != _selectedStatus) {
              return false;
            }
            if (_selectedAmenity != 'ALL' && b.amenityType.id != _selectedAmenity) {
              return false;
            }
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final matchesFlat = b.flatNumber.toLowerCase().contains(q);
              final matchesName = b.residentName.toLowerCase().contains(q);
              final matchesPurpose = b.occasionPurpose.toLowerCase().contains(q);
              if (!matchesFlat && !matchesName && !matchesPurpose) return false;
            }
            return true;
          }).toList();

          return CustomScrollView(
            slivers: [
              // Header & Quick Metric Counters
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Amenity & Facility Bookings',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Review Community Hall, Ground & Gym reservations',
                                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.calendar_month_rounded, size: 18),
                            label: const Text('Blocked Dates Calendar'),
                            onPressed: () => _showBlockedCalendarDialog(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Metric counter cards
                      Row(
                        children: [
                          _buildMetricCard(
                            label: 'Pending Review',
                            count: pendingCount,
                            color: Colors.orange.shade700,
                            bgColor: Colors.orange.shade50,
                            icon: Icons.hourglass_top_rounded,
                            isActive: _selectedStatus == BookingStatus.pendingApproval.value,
                            onTap: () {
                              setState(() {
                                _selectedStatus = _selectedStatus == BookingStatus.pendingApproval.value
                                    ? 'ALL'
                                    : BookingStatus.pendingApproval.value;
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          _buildMetricCard(
                            label: 'Confirmed',
                            count: confirmedCount,
                            color: Colors.green.shade700,
                            bgColor: Colors.green.shade50,
                            icon: Icons.check_circle_outline_rounded,
                            isActive: _selectedStatus == BookingStatus.confirmed.value,
                            onTap: () {
                              setState(() {
                                _selectedStatus = _selectedStatus == BookingStatus.confirmed.value
                                    ? 'ALL'
                                    : BookingStatus.confirmed.value;
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          _buildMetricCard(
                            label: 'Completed',
                            count: completedCount,
                            color: Colors.teal.shade700,
                            bgColor: Colors.teal.shade50,
                            icon: Icons.task_alt_rounded,
                            isActive: _selectedStatus == BookingStatus.completed.value,
                            onTap: () {
                              setState(() {
                                _selectedStatus = _selectedStatus == BookingStatus.completed.value
                                    ? 'ALL'
                                    : BookingStatus.completed.value;
                              });
                            },
                          ),
                          const SizedBox(width: 12),
                          _buildMetricCard(
                            label: 'Total Bookings',
                            count: allBookings.length,
                            color: AppColors.primaryDark,
                            bgColor: AppColors.primaryLight,
                            icon: Icons.event_available_rounded,
                            isActive: _selectedStatus == 'ALL',
                            onTap: () => setState(() => _selectedStatus = 'ALL'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Search and Filter controls
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Search by flat, resident name, or occasion...',
                                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppColors.border),
                                ),
                              ),
                              onChanged: (v) => setState(() => _searchQuery = v.trim()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Amenity dropdown filter
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedAmenity,
                                icon: const Icon(Icons.arrow_drop_down_rounded),
                                items: const [
                                  DropdownMenuItem(value: 'ALL', child: Text('All Amenities')),
                                  DropdownMenuItem(value: 'COMMUNITY_HALL', child: Text('Community Hall')),
                                  DropdownMenuItem(value: 'OPEN_GROUND', child: Text('Society Ground')),
                                  DropdownMenuItem(value: 'GYM', child: Text('Gymnasium')),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _selectedAmenity = v);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Booking list items
              if (filteredBookings.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_busy_rounded, size: 48, color: AppColors.textMuted),
                          SizedBox(height: 12),
                          Text(
                            'No amenity bookings found for this filter.',
                            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final booking = filteredBookings[index];
                        return _buildBookingCard(context, booking);
                      },
                      childCount: filteredBookings.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ─── Metric Counter Card ──────────────────────────────────────────────────
  Widget _buildMetricCard({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? color : color.withValues(alpha: 0.25),
              width: isActive ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Booking Card Item ────────────────────────────────────────────────────
  Widget _buildBookingCard(BuildContext context, AmenityBooking b) {
    final statusColor = _getStatusColor(b.status);
    final isPending = b.status == BookingStatus.pendingApproval;
    final isConfirmed = b.status == BookingStatus.confirmed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppDecorations.card(borderRadius: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Amenity Name + Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getAmenityColor(b.amenityType).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getAmenityIcon(b.amenityType),
                      size: 20,
                      color: _getAmenityColor(b.amenityType),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.amenityName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Flat ${b.flatNumber} • ${b.residentName}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  b.status.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Details Grid: Date/Slot, Purpose, Charges
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RESERVATION DATE / SLOT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      b.slot != null
                          ? '${b.bookingDate} (${b.slot})'
                          : (b.endDate != null && b.endDate != b.bookingDate
                              ? '${b.bookingDate} to ${b.endDate}'
                              : b.bookingDate),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text('OCCASION / PURPOSE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      b.occasionPurpose,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('CONTACT PHONE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text(
                      b.residentPhone.isNotEmpty ? b.residentPhone : 'Not provided',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    if (b.amenityType == AmenityType.gym) ...[
                      const Text('KEY STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                      const SizedBox(height: 2),
                      Text(
                        b.keyStatus.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: b.keyStatus == GymKeyStatus.keyIssued ? Colors.orange.shade800 : Colors.teal.shade800,
                        ),
                      ),
                    ] else ...[
                      const Text('PAYMENT REF / UTR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted)),
                      const SizedBox(height: 2),
                      Text(
                        b.paymentRef?.isNotEmpty == true ? b.paymentRef! : 'Pending',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurfaceSecondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text('₹${b.totalAmount.toInt()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Advance:', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                          Text('₹${b.advancePaid.toInt()}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                        ],
                      ),
                      const Divider(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Balance:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          Text(
                            '₹${b.balanceDue.toInt()}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: b.balanceDue > 0 ? Colors.red.shade700 : Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Action Buttons Bar
          if (isPending || (isConfirmed && b.balanceDue > 0)) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isPending) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Decline'),
                    onPressed: () => _showRejectDialog(context, b),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Approve Booking'),
                    onPressed: () => _executeApproveBooking(context, b),
                  ),
                ],
                if (isConfirmed && b.balanceDue > 0) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.payments_rounded, size: 16),
                    label: Text('Collect Balance (₹${b.balanceDue.toInt()})'),
                    onPressed: () => _showCollectBalanceDialog(context, b),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── Approve Booking Flow ─────────────────────────────────────────────────
  Future<void> _executeApproveBooking(BuildContext context, AmenityBooking b) async {
    final currentAdmin = FirebaseAuth.instance.currentUser;
    final adminUid = currentAdmin?.uid ?? 'ADMIN';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Facility Booking'),
        content: Text(
          'Confirm booking for ${b.amenityName} on ${b.bookingDate} for Flat ${b.flatNumber}?\n\n'
          'Advance Paid: ₹${b.advancePaid.toInt()} (Ref: ${b.paymentRef ?? "None"})\n'
          'Balance Remaining: ₹${b.balanceDue.toInt()}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Approval'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await AmenityBookingService.adminApproveBooking(
          bookingId: b.id,
          adminUid: adminUid,
          adminName: currentAdmin?.displayName ?? 'Society Office',
        );
        if (context.mounted) {
          AppFeedback.showSuccess(context, 'Booking for Flat ${b.flatNumber} has been confirmed!');
        }
      } catch (e) {
        if (context.mounted) {
          AppFeedback.showError(context, 'Failed to approve booking: $e');
        }
      }
    }
  }

  // ─── Reject Booking Flow ──────────────────────────────────────────────────
  void _showRejectDialog(BuildContext context, AmenityBooking b) {
    final currentAdmin = FirebaseAuth.instance.currentUser;
    final adminUid = currentAdmin?.uid ?? 'ADMIN';
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Facility Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Specify reason for declining Flat ${b.flatNumber}\'s booking for ${b.amenityName}:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. Facility under maintenance / advance payment not received',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) {
                AppFeedback.showError(ctx, 'Please enter a reason for declining.');
                return;
              }
              Navigator.pop(ctx);
              try {
                await AmenityBookingService.adminRejectBooking(
                  bookingId: b.id,
                  adminUid: adminUid,
                  reason: reason,
                );
                if (context.mounted) {
                  AppFeedback.showSuccess(context, 'Booking declined. Date block released.');
                }
              } catch (e) {
                if (context.mounted) {
                  AppFeedback.showError(context, 'Error declining booking: $e');
                }
              }
            },
            child: const Text('Decline & Release Date'),
          ),
        ],
      ),
    );
  }

  // ─── Collect Balance Payment Modal ────────────────────────────────────────
  void _showCollectBalanceDialog(BuildContext context, AmenityBooking b) {
    final currentAdmin = FirebaseAuth.instance.currentUser;
    final adminUid = currentAdmin?.uid ?? 'ADMIN';
    final adminName = currentAdmin?.displayName ?? 'Society Office';
    final amountCtrl = TextEditingController(text: b.balanceDue.toInt().toString());
    final refCtrl = TextEditingController();
    String paymentMode = 'CASH';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Record Balance Payment (${b.amenityName})'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flat ${b.flatNumber} • ${b.residentName}\n'
                  'Occasion Date: ${b.bookingDate}\n'
                  'Total Fee: ₹${b.totalAmount.toInt()} | Already Paid: ₹${b.advancePaid.toInt()}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                const Text('Payment Mode:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                // Modern SegmentedButton for choosing between Office Cash and Online UPI
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'CASH', label: Text('Cash in Office')),
                    ButtonSegment(value: 'ONLINE_UPI', label: Text('UPI / NetBanking')),
                  ],
                  selected: {paymentMode},
                  onSelectionChanged: (set) => setDialogState(() => paymentMode = set.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount Received (₹)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: refCtrl,
                  decoration: InputDecoration(
                    labelText: paymentMode == 'CASH' ? 'Office Cash Receipt No.' : 'UPI Transaction UTR',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (amt <= 0) {
                  AppFeedback.showError(ctx, 'Please enter a valid amount.');
                  return;
                }
                Navigator.pop(ctx);
                try {
                  await AmenityBookingService.adminCollectBalancePayment(
                    bookingId: b.id,
                    adminUid: adminUid,
                    adminName: adminName,
                    amountPaid: amt,
                    paymentMode: paymentMode,
                    referenceNumber: refCtrl.text.trim(),
                  );
                  if (context.mounted) {
                    AppFeedback.showSuccess(context, 'Balance of ₹${amt.toInt()} recorded and logged into society transactions!');
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppFeedback.showError(context, 'Failed to record balance: $e');
                  }
                }
              },
              child: const Text('Save & Post to Ledger'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Blocked Dates Calendar Overview Modal ────────────────────────────────
  void _showBlockedCalendarDialog(BuildContext context) {
    AmenityType calendarAmenity = AmenityType.communityHall;
    DateTime calendarMonth = DateTime.now();
    DateTime calendarSelectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 580,
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Facility Booking Calendar',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Segmented switch to inspect Hall or Ground availability calendars
                  SegmentedButton<AmenityType>(
                    segments: const [
                      ButtonSegment(value: AmenityType.communityHall, label: Text('Community Hall')),
                      ButtonSegment(value: AmenityType.openGround, label: Text('Ground')),
                      ButtonSegment(value: AmenityType.gym, label: Text('Gym')),
                    ],
                    selected: {calendarAmenity},
                    onSelectionChanged: (set) {
                      setDialogState(() => calendarAmenity = set.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  // StreamBuilder listening to month-scoped bookings for real-time calendar updates
                  StreamBuilder<List<AmenityBooking>>(
                    stream: AmenityBookingService.getBookingsStream(
                      amenityType: calendarAmenity,
                      year: calendarMonth.year,
                      month: calendarMonth.month,
                    ),
                    builder: (context, snap) {
                      return AmenityCalendarView(
                        currentMonth: calendarMonth,
                        selectedDate: calendarSelectedDate,
                        bookings: snap.data ?? [],
                        amenityType: calendarAmenity,
                        onDateSelected: (date) {
                          setDialogState(() => calendarSelectedDate = date);
                        },
                        onPrevMonth: () {
                          setDialogState(() {
                            calendarMonth = DateTime(calendarMonth.year, calendarMonth.month - 1, 1);
                          });
                        },
                        onNextMonth: () {
                          setDialogState(() {
                            calendarMonth = DateTime(calendarMonth.year, calendarMonth.month + 1, 1);
                          });
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  Color _getStatusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pendingApproval:
        return Colors.orange.shade800;
      case BookingStatus.confirmed:
        return Colors.green.shade800;
      case BookingStatus.completed:
        return Colors.teal.shade800;
      case BookingStatus.rejected:
      case BookingStatus.cancelled:
        return Colors.red.shade800;
    }
  }

  Color _getAmenityColor(AmenityType type) {
    switch (type) {
      case AmenityType.communityHall:
        return Colors.indigo;
      case AmenityType.openGround:
        return Colors.teal;
      case AmenityType.gym:
        return Colors.orange.shade800;
    }
  }

  IconData _getAmenityIcon(AmenityType type) {
    switch (type) {
      case AmenityType.communityHall:
        return Icons.celebration_rounded;
      case AmenityType.openGround:
        return Icons.park_rounded;
      case AmenityType.gym:
        return Icons.fitness_center_rounded;
    }
  }
}
