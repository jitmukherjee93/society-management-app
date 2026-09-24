import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/amenity_booking.dart';
import '../../services/amenity_booking_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_formatters.dart';
import '../../widgets/amenity_calendar_view.dart';
import '../../widgets/app_feedback.dart';
import '../../widgets/gym_slot_picker.dart';

// ============================================================================
// AMENITY & FACILITY BOOKING SCREEN (RESIDENT)
// ============================================================================
// Complete resident interface for booking:
// - Community Hall: ₹4,000/day, ₹200 advance, minimum 2 days prior notice.
// - Society Ground: ₹500 for 2 days (₹250/day), minimum 2 days prior notice.
// - Fitness Gym: Free 1-hour slots, tracked with Guard physical key handover.
// ============================================================================

class AmenityBookingScreen extends StatefulWidget {
  final String userFlat;
  /// Optional initial amenity to display directly (e.g. AmenityType.gym when clicking gym push notifications)
  final AmenityType? initialAmenity;

  const AmenityBookingScreen({
    super.key,
    required this.userFlat,
    this.initialAmenity,
  });

  @override
  State<AmenityBookingScreen> createState() => _AmenityBookingScreenState();
}

class _AmenityBookingScreenState extends State<AmenityBookingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 2));

  AmenityType _selectedAmenity = AmenityType.communityHall;
  Stream<List<AmenityBooking>>? _bookingsStream;

  @override
  void initState() {
    super.initState();
    // Support deep navigation to Gym or Ground tab directly from notification clicks
    final initialIndex = widget.initialAmenity == AmenityType.gym
        ? 2
        : (widget.initialAmenity == AmenityType.openGround ? 1 : 0);

    _tabController = TabController(length: 3, vsync: this, initialIndex: initialIndex);
    _tabController.addListener(_handleTabChange);

    if (widget.initialAmenity == AmenityType.gym) {
      _selectedAmenity = AmenityType.gym;
      _selectedDate = DateTime.now();
    } else if (widget.initialAmenity == AmenityType.openGround) {
      _selectedAmenity = AmenityType.openGround;
      _selectedDate = DateTime.now().add(const Duration(days: 2));
    }

    _initBookingsStream();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      switch (_tabController.index) {
        case 0:
          _selectedAmenity = AmenityType.communityHall;
          _selectedDate = DateTime.now().add(const Duration(days: 2));
          break;
        case 1:
          _selectedAmenity = AmenityType.openGround;
          _selectedDate = DateTime.now().add(const Duration(days: 2));
          break;
        case 2:
          _selectedAmenity = AmenityType.gym;
          _selectedDate = DateTime.now();
          break;
      }
      _initBookingsStream();
    });
  }

  void _initBookingsStream() {
    // Cache stream in state to strictly prevent redundant Firestore re-subscription on build
    _bookingsStream = AmenityBookingService.getBookingsStream(
      amenityType: _selectedAmenity,
      year: _currentMonth.year,
      month: _currentMonth.month,
    );
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
      _initBookingsStream();
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
      _initBookingsStream();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<List<AmenityBooking>>(
      stream: _bookingsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[AmenityBookingScreen] Stream error: ${snapshot.error}');
        }
        final bookings = snapshot.data ?? [];
        final dateStr = AmenityBookingService.formatDate(_selectedDate);
        // Include bookings where selected date matches bookingDate or falls within [bookingDate, endDate]
        final bookingsForSelectedDate = bookings.where((b) {
          if (b.status == BookingStatus.cancelled || b.status == BookingStatus.rejected) return false;
          if (b.bookingDate == dateStr) return true;
          if (b.endDate != null && b.endDate!.isNotEmpty) {
            return dateStr.compareTo(b.bookingDate) >= 0 && dateStr.compareTo(b.endDate!) <= 0;
          }
          return false;
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Amenity & Facility Booking'),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.history_rounded),
                tooltip: 'My Bookings',
                onPressed: () => _showMyBookingsSheet(context),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: Colors.black54,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(icon: Icon(Icons.celebration_rounded), text: 'Community Hall'),
                Tab(icon: Icon(Icons.park_rounded), text: 'Ground'),
                Tab(icon: Icon(Icons.fitness_center_rounded), text: 'Gym'),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info Banner explaining terms & rates
                _buildAmenityInfoBanner(),
                const SizedBox(height: 16),

                // Calendar View with direct interactive tap feedback
                AmenityCalendarView(
                  currentMonth: _currentMonth,
                  selectedDate: _selectedDate,
                  bookings: bookings,
                  amenityType: _selectedAmenity,
                  onDateSelected: (date) => _handleDateSelected(context, date, bookings),
                  onPrevMonth: _prevMonth,
                  onNextMonth: _nextMonth,
                ),
                const SizedBox(height: 16),

                // Date Details / Booking Actions
                if (_selectedAmenity == AmenityType.gym)
                  GymSlotPicker(
                    selectedDate: _selectedDate,
                    bookings: bookingsForSelectedDate,
                    currentResidentUid: currentUser?.uid,
                    onSlotSelected: (slot) => _promptGymBooking(context, slot),
                    onUnregisterSlot: (booking) => _promptUnregisterGymSlot(context, booking),
                  )
                else
                  _buildDayAmenityBookingCard(context, bookingsForSelectedDate),
                const SizedBox(height: 70), // Bottom padding for sticky bottom bar
              ],
            ),
          ),
          bottomNavigationBar: _selectedAmenity != AmenityType.gym
              ? _buildStickyBottomBar(context, bookingsForSelectedDate)
              : null,
        );
      },
    );
  }

  /// Handles user tapping a date on the calendar with instant feedback and booking modal launch
  void _handleDateSelected(BuildContext context, DateTime date, List<AmenityBooking> allBookings) {
    setState(() => _selectedDate = date);

    if (_selectedAmenity == AmenityType.gym) {
      // For gym, date change refreshes the slot picker below
      return;
    }

    final dateStr = AmenityBookingService.formatDate(date);
    final bookingsOnDate = allBookings.where((b) {
      if (b.status == BookingStatus.cancelled || b.status == BookingStatus.rejected) return false;
      if (b.bookingDate == dateStr) return true;
      if (b.endDate != null && b.endDate!.isNotEmpty) {
        return dateStr.compareTo(b.bookingDate) >= 0 && dateStr.compareTo(b.endDate!) <= 0;
      }
      return false;
    }).toList();
    final confirmed = bookingsOnDate.cast<AmenityBooking?>().firstWhere(
          (b) => b?.status == BookingStatus.confirmed,
          orElse: () => null,
        );
    final pending = bookingsOnDate.cast<AmenityBooking?>().firstWhere(
          (b) => b?.status == BookingStatus.pendingApproval,
          orElse: () => null,
        );
    final isLeadTimeValid = AmenityBookingService.isLeadTimeValid(date);

    if (confirmed != null) {
      _showBookingStatusDialog(
        context,
        title: '🔒 Date Already Reserved',
        message: '${_selectedAmenity.displayName} is already booked on ${DateFormat("EEEE, dd MMM yyyy").format(date)} by Flat ${confirmed.flatNumber} for "${confirmed.occasionPurpose}". Please choose another available date.',
        icon: Icons.lock_clock_rounded,
        iconColor: Colors.red,
      );
    } else if (pending != null) {
      _showBookingStatusDialog(
        context,
        title: '⏳ Pending Admin Review',
        message: 'A booking request by Flat ${pending.flatNumber} for "${pending.occasionPurpose}" is currently under Admin review for this date.',
        icon: Icons.hourglass_top_rounded,
        iconColor: Colors.amber.shade800,
      );
    } else if (!isLeadTimeValid) {
      _showNoticeClosedDialog(context, date);
    } else {
      // Date is open and available: open booking modal immediately!
      _openBookingModal(context);
    }
  }

  /// Informational dialog when user selects a date within the mandatory 48-hour cutoff
  void _showNoticeClosedDialog(BuildContext context, DateTime date) {
    final earliestAvailable = DateTime.now().add(const Duration(days: 2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Expanded(child: Text('Notice Period Closed', style: TextStyle(fontSize: 16))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selected Date: ${DateFormat("EEEE, dd MMMM yyyy").format(date)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Per society rules, bookings for ${_selectedAmenity.displayName} must be made at least 2 days prior to the occasion.',
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available, color: Colors.teal, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Earliest available booking date is ${DateFormat("EEEE, dd MMMM").format(earliestAvailable)}.',
                      style: TextStyle(fontSize: 12, color: Colors.teal.shade900, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _selectedDate = earliestAvailable);
              _openBookingModal(context);
            },
            child: const Text('Book Earliest Available Date'),
          ),
        ],
      ),
    );
  }

  /// Dialog displaying details for blocked or pending dates
  void _showBookingStatusDialog(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Persistent bottom bar providing instant visibility of booking status and call-to-action
  Widget _buildStickyBottomBar(BuildContext context, List<AmenityBooking> bookingsOnDate) {
    final isLeadTimeValid = AmenityBookingService.isLeadTimeValid(_selectedDate);
    final confirmedBooking = bookingsOnDate.cast<AmenityBooking?>().firstWhere(
          (b) => b?.status == BookingStatus.confirmed,
          orElse: () => null,
        );
    final pendingBooking = bookingsOnDate.cast<AmenityBooking?>().firstWhere(
          (b) => b?.status == BookingStatus.pendingApproval,
          orElse: () => null,
        );
    final isBlocked = confirmedBooking != null;
    final isPending = pendingBooking != null;

    final dateFormatted = DateFormat('EEE, dd MMM').format(_selectedDate);

    String btnText = 'Book for $dateFormatted';
    VoidCallback? onTap = () => _openBookingModal(context);
    Color btnColor = AppColors.primary;

    if (isBlocked) {
      btnText = 'Already Reserved';
      onTap = null;
      btnColor = Colors.red.shade700;
    } else if (isPending) {
      btnText = 'Pending Approval';
      onTap = null;
      btnColor = Colors.amber.shade800;
    } else if (!isLeadTimeValid) {
      btnText = 'Notice Closed (< 2 Days)';
      onTap = () => _showNoticeClosedDialog(context, _selectedDate);
      btnColor = Colors.grey.shade600;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            offset: const Offset(0, -3),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateFormatted,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    _selectedAmenity == AmenityType.communityHall
                        ? '₹4,000 / day • ₹200 Adv'
                        : '₹500 / 2 days (Min 2 Days) • ₹200 Adv',
                    style: TextStyle(fontSize: 12, color: Colors.teal.shade800, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: btnColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(
                isBlocked ? Icons.lock_rounded : (isLeadTimeValid ? Icons.calendar_today_rounded : Icons.info_outline),
                size: 18,
              ),
              label: Text(btnText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: onTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmenityInfoBanner() {
    IconData icon;
    String title;
    String rateText;
    String ruleText;

    switch (_selectedAmenity) {
      case AmenityType.communityHall:
        icon = Icons.celebration_rounded;
        title = 'Community Hall';
        rateText = 'Rate: ₹4,000 / day • Advance: ₹200';
        ruleText = 'Booking must be made at least 2 days prior to occasion.';
        break;
      case AmenityType.openGround:
        icon = Icons.park_rounded;
        title = 'Society Ground';
        rateText = 'Rate: ₹500 for 2 days (Min. 2 Days required)';
        ruleText = 'Must be booked for at least 2 days, and at least 2 days prior to occasion.';
        break;
      case AmenityType.gym:
        icon = Icons.fitness_center_rounded;
        title = 'Fitness Gym';
        rateText = 'Free for all residents • 1-Hour Slots';
        ruleText = 'Collect key from Security Guard before workout and return upon exit.';
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.teal,
            radius: 20,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text(rateText, style: TextStyle(fontSize: 12, color: Colors.teal.shade900, fontWeight: FontWeight.w600)),
                Text(ruleText, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayAmenityBookingCard(BuildContext context, List<AmenityBooking> bookingsOnDate) {
    final dateStr = DateFormat('EEEE, dd MMMM yyyy').format(_selectedDate);
    final isLeadTimeValid = AmenityBookingService.isLeadTimeValid(_selectedDate);
    final confirmedBooking = bookingsOnDate.cast<AmenityBooking?>().firstWhere(
          (b) => b?.status == BookingStatus.confirmed,
          orElse: () => null,
        );
    final pendingBooking = bookingsOnDate.cast<AmenityBooking?>().firstWhere(
          (b) => b?.status == BookingStatus.pendingApproval,
          orElse: () => null,
        );
    final isBlocked = confirmedBooking != null;
    final isPending = pendingBooking != null;

    Color cardBg = Colors.white;
    String statusTitle = 'Date Available';
    String statusSubtitle = _selectedAmenity == AmenityType.openGround
        ? 'You can reserve Society Ground (Minimum 2 days booking required).'
        : 'You can reserve ${_selectedAmenity.displayName} for this date.';
    Color statusColor = Colors.green;

    if (isBlocked) {
      statusTitle = 'Blocked / Booked';
      statusSubtitle = 'Reserved by Flat ${confirmedBooking.flatNumber} (${confirmedBooking.occasionPurpose})';
      statusColor = Colors.red.shade700;
      cardBg = Colors.red.shade50;
    } else if (isPending) {
      statusTitle = 'Pending Admin Approval';
      statusSubtitle = 'Requested by Flat ${pendingBooking.flatNumber} (${pendingBooking.occasionPurpose})';
      statusColor = Colors.amber.shade800;
      cardBg = Colors.amber.shade50;
    } else if (!isLeadTimeValid) {
      statusTitle = 'Booking Notice Period Closed';
      statusSubtitle = 'Bookings must be placed at least 2 days prior to the occasion.';
      statusColor = Colors.grey.shade600;
      cardBg = Colors.grey.shade50;
    }

    return Card(
      elevation: 0,
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusTitle,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(statusSubtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const Divider(height: 24),

            if (!isBlocked && !isPending && isLeadTimeValid)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.bookmark_add_rounded),
                  label: Text('Book ${_selectedAmenity.displayName}'),
                  onPressed: () => _openBookingModal(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openBookingModal(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final purposeCtrl = TextEditingController();
    final paymentRefCtrl = TextEditingController();
    // Society Ground strictly requires a minimum of 2 days per society bye-laws.
    // Hall and other amenities default to 1 day.
    int numberOfDays = _selectedAmenity == AmenityType.openGround ? 2 : 1;
    String advanceMode = 'UPI'; // 'UPI' or 'CASH_OFFICE'
    bool isSubmitting = false;
    String? modalErrorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final fees = AmenityBookingService.calculateBookingFee(
              amenityType: _selectedAmenity,
              numberOfDays: numberOfDays,
            );

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Book ${_selectedAmenity.displayName}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // Shows single date for 1-day bookings, or date range [Start - End] for multi-day bookings
                        child: Text(
                          numberOfDays > 1
                              ? 'Booking Dates: ${DateFormat("dd MMM").format(_selectedDate)} – ${DateFormat("dd MMM yyyy").format(_selectedDate.add(Duration(days: numberOfDays - 1)))} ($numberOfDays Days)'
                              : 'Booking Date: ${DateFormat("EEEE, dd MMM yyyy").format(_selectedDate)}',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal.shade900),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // In-Modal Error Banner
                      if (modalErrorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  modalErrorMessage!,
                                  style: TextStyle(color: Colors.red.shade900, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Occasion / Event Purpose
                      TextFormField(
                        controller: purposeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Occasion / Event Purpose *',
                          hintText: 'e.g. Birthday Celebration, Family Ceremony',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the occasion purpose';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Number of Days: Society Ground strictly requires at least 2 days
                      // Choices provide 2 Days (₹500), 3 Days (₹750), and 4 Days (₹1,000)
                      if (_selectedAmenity == AmenityType.openGround) ...[
                        Row(
                          children: [
                            const Text('Duration:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Min 2 Days Required',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.brown),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('2 Days (₹500)'),
                              selected: numberOfDays == 2,
                              onSelected: (val) {
                                if (val) setModalState(() => numberOfDays = 2);
                              },
                            ),
                            ChoiceChip(
                              label: const Text('3 Days (₹750)'),
                              selected: numberOfDays == 3,
                              onSelected: (val) {
                                if (val) setModalState(() => numberOfDays = 3);
                              },
                            ),
                            ChoiceChip(
                              label: const Text('4 Days (₹1,000)'),
                              selected: numberOfDays == 4,
                              onSelected: (val) {
                                if (val) setModalState(() => numberOfDays = 4);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Fee Breakdown Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Facility Charges:'),
                                Text(
                                  AppFormatters.currency(fees['totalAmount']),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Advance Required to Book:'),
                                Text(
                                  AppFormatters.currency(fees['advancePaid']),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Balance Due (at office before event):'),
                                Text(
                                  AppFormatters.currency(fees['balanceDue']),
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Advance Payment Mode Selection
                      const Text(
                        'Advance Payment Mode:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setModalState(() => advanceMode = 'UPI'),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: advanceMode == 'UPI' ? Colors.teal.shade50 : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: advanceMode == 'UPI' ? Colors.teal : Colors.grey.shade300,
                                    width: advanceMode == 'UPI' ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      advanceMode == 'UPI' ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                      color: advanceMode == 'UPI' ? Colors.teal : Colors.grey,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text('UPI / Online', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () => setModalState(() => advanceMode = 'CASH_OFFICE'),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: advanceMode == 'CASH_OFFICE' ? Colors.teal.shade50 : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: advanceMode == 'CASH_OFFICE' ? Colors.teal : Colors.grey.shade300,
                                    width: advanceMode == 'CASH_OFFICE' ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      advanceMode == 'CASH_OFFICE' ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                      color: advanceMode == 'CASH_OFFICE' ? Colors.teal : Colors.grey,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    const Expanded(
                                      child: Text('Cash at Office', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (advanceMode == 'UPI') ...[
                        TextFormField(
                          controller: paymentRefCtrl,
                          decoration: const InputDecoration(
                            labelText: 'UPI Reference / UTR Number *',
                            hintText: 'e.g. 324567890123 or UPI Ref',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (advanceMode == 'UPI' && (value == null || value.trim().isEmpty)) {
                              return 'Please enter the UPI transaction ID / UTR';
                            }
                            return null;
                          },
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: Colors.amber),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Please deposit ₹200 advance at the Society Office. The Admin will verify and confirm your booking.',
                                  style: TextStyle(fontSize: 12, color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) {
                                    return;
                                  }

                                  // Strict validation: Society Ground bookings must be at least 2 days per society rules
                                  if (_selectedAmenity == AmenityType.openGround && numberOfDays < 2) {
                                    setModalState(() {
                                      modalErrorMessage = 'Society Ground must be booked for a minimum of 2 days.';
                                    });
                                    return;
                                  }

                                  final purpose = purposeCtrl.text.trim();
                                  final payRef = advanceMode == 'UPI'
                                      ? paymentRefCtrl.text.trim()
                                      : 'CASH-OFFICE-PENDING';

                                  setModalState(() {
                                    isSubmitting = true;
                                    modalErrorMessage = null;
                                  });

                                  try {
                                    final user = FirebaseAuth.instance.currentUser;
                                    await AmenityBookingService.bookAmenity(
                                      amenityType: _selectedAmenity,
                                      startDate: _selectedDate,
                                      endDate: numberOfDays > 1
                                          ? _selectedDate.add(Duration(days: numberOfDays - 1))
                                          : null,
                                      flatNumber: widget.userFlat,
                                      residentUid: user?.uid ?? '',
                                      residentName: user?.displayName ?? 'Resident',
                                      residentPhone: user?.phoneNumber ?? '',
                                      occasionPurpose: purpose,
                                      paymentRef: payRef,
                                    );

                                    // Close modal and refresh calendar stream immediately
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                    if (mounted) {
                                      setState(() {
                                        _initBookingsStream();
                                      });
                                      AppFeedback.showSuccess(
                                        this.context,
                                        'Booking request for ${_selectedAmenity.displayName} submitted! Admin will verify and confirm.',
                                      );
                                    }
                                  } catch (e) {
                                    setModalState(() {
                                      isSubmitting = false;
                                      modalErrorMessage = e.toString().replaceFirst('Exception: ', '');
                                    });
                                  }
                                },
                          child: isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Confirm & Submit Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _promptGymBooking(BuildContext context, String slot) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.fitness_center_rounded, color: Colors.teal),
            SizedBox(width: 8),
            Text('Reserve Gym Slot'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${DateFormat("EEEE, dd MMM yyyy").format(_selectedDate)}'),
            const SizedBox(height: 4),
            Text('Slot: $slot', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.vpn_key_rounded, size: 16, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Free slot. Please collect the key from the security guard at main gate before entering gym.',
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final user = FirebaseAuth.instance.currentUser;
                await AmenityBookingService.bookAmenity(
                  amenityType: AmenityType.gym,
                  startDate: _selectedDate,
                  slot: slot,
                  flatNumber: widget.userFlat,
                  residentUid: user?.uid ?? '',
                  residentName: user?.displayName ?? 'Resident',
                  residentPhone: user?.phoneNumber ?? '',
                  occasionPurpose: 'Gym Workout',
                );
                if (context.mounted) {
                  AppFeedback.showSuccess(context, 'Gym slot reserved! Collect key from guard.');
                }
              } catch (e) {
                if (context.mounted) {
                  AppFeedback.showError(context, 'Slot reservation failed: $e');
                }
              }
            },
            child: const Text('Confirm Reservation'),
          ),
        ],
      ),
    );
  }

  /// Prompts resident for confirmation before unregistering/cancelling their gym slot.
  /// Prevents cancellation if the physical key is currently in the resident's possession.
  Future<void> _promptUnregisterGymSlot(BuildContext context, AmenityBooking booking) async {
    // 1. Guard check: key issued state requires physical handover first
    if (booking.keyStatus == GymKeyStatus.keyIssued) {
      AppFeedback.showError(
        context,
        'Cannot unregister: The gym key has already been issued to you. Please return the key to the security guard at main gate before cancelling.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.event_busy_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Unregister Gym Slot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel your gym slot reservation on ${booking.bookingDate} (${booking.slot})?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This slot will immediately become free and open for other society residents to book.',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade900, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Keep Slot', style: TextStyle(color: Colors.black87)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Unregister', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        await AmenityBookingService.unregisterGymBooking(
          bookingId: booking.id,
          residentUid: user?.uid ?? '',
        );
        if (mounted) {
          AppFeedback.showSuccess(this.context, 'Gym slot ${booking.slot} cancelled and released.');
        }
      } catch (e) {
        if (mounted) {
          AppFeedback.showError(this.context, e.toString().replaceAll('Exception: ', ''));
        }
      }
    }
  }

  void _showMyBookingsSheet(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Amenity Bookings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(),
              Expanded(
                child: StreamBuilder<List<AmenityBooking>>(
                  stream: AmenityBookingService.getBookingsStream(
                    amenityType: _selectedAmenity,
                    year: _currentMonth.year,
                    month: _currentMonth.month,
                  ),
                  builder: (context, snapshot) {
                    final all = snapshot.data ?? [];
                    final myBookings = all.where((b) => b.residentUid == user?.uid).toList();

                    if (myBookings.isEmpty) {
                      return const Center(
                        child: Text('No bookings found for this month.', style: TextStyle(color: Colors.black54)),
                      );
                    }

                    return ListView.separated(
                      itemCount: myBookings.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final b = myBookings[index];
                        return Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            leading: Icon(
                              b.amenityType == AmenityType.gym
                                  ? Icons.fitness_center
                                  : Icons.celebration,
                              color: Colors.teal,
                            ),
                            title: Text('${b.amenityType.displayName} • ${b.bookingDate}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (b.slot != null) Text('Slot: ${b.slot}'),
                                Text('Status: ${b.status.value}'),
                                if (b.amenityType == AmenityType.gym)
                                  Text('Key: ${b.keyStatus.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            trailing: b.status == BookingStatus.pendingApproval || b.status == BookingStatus.confirmed
                                ? TextButton(
                                    onPressed: () async {
                                      if (b.amenityType == AmenityType.gym) {
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        await _promptUnregisterGymSlot(context, b);
                                      } else {
                                        await AmenityBookingService.cancelBooking(b.id, 'Resident requested cancellation');
                                        if (ctx.mounted) {
                                          Navigator.pop(ctx);
                                          AppFeedback.showSuccess(context, 'Booking cancelled');
                                        }
                                      }
                                    },
                                    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                                  )
                                : null,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
