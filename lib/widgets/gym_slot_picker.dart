import 'dart:async';
import 'package:flutter/material.dart';
import '../models/amenity_booking.dart';
import '../services/amenity_booking_service.dart';

// ============================================================================
// GYM SLOT PICKER WIDGET
// ============================================================================
// Displays 1-hour slots from 06:00 AM to 10:00 PM for the selected date.
// Dynamically filters out passed time slots based on the real-time clock.
// For each available slot:
// - Shows availability (Free vs Reserved).
// - Identifies resident name & flat number for transparency across society.
// - Displays Guard key handover status (Key with Guard / Issued / Returned).
// - Preserves active ongoing workouts for the current resident until conclusion.
// ============================================================================

class GymSlotPicker extends StatefulWidget {
  final DateTime selectedDate;
  final List<AmenityBooking> bookings;
  final ValueChanged<String> onSlotSelected;
  final void Function(AmenityBooking booking)? onUnregisterSlot;
  final String? currentResidentUid;

  static const List<String> allSlots = [
    '06:00 AM - 07:00 AM',
    '07:00 AM - 08:00 AM',
    '08:00 AM - 09:00 AM',
    '09:00 AM - 10:00 AM',
    '10:00 AM - 11:00 AM',
    '11:00 AM - 12:00 PM',
    '12:00 PM - 01:00 PM',
    '01:00 PM - 02:00 PM',
    '02:00 PM - 03:00 PM',
    '03:00 PM - 04:00 PM',
    '04:00 PM - 05:00 PM',
    '05:00 PM - 06:00 PM',
    '06:00 PM - 07:00 PM',
    '07:00 PM - 08:00 PM',
    '08:00 PM - 09:00 PM',
    '09:00 PM - 10:00 PM',
  ];

  const GymSlotPicker({
    super.key,
    required this.selectedDate,
    required this.bookings,
    required this.onSlotSelected,
    this.onUnregisterSlot,
    this.currentResidentUid,
  });

  @override
  State<GymSlotPicker> createState() => _GymSlotPickerState();
}

class _GymSlotPickerState extends State<GymSlotPicker> {
  Timer? _slotClockTimer;

  @override
  void initState() {
    super.initState();
    // Periodically re-evaluate passed slots every 30 seconds so expired slots disappear in real time
    _slotClockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _slotClockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Map bookings by slot name
    final Map<String, AmenityBooking> bookingsBySlot = {};
    for (final b in widget.bookings) {
      if (b.status == BookingStatus.cancelled || b.status == BookingStatus.rejected) continue;
      if (b.slot != null && b.slot!.isNotEmpty) {
        bookingsBySlot[b.slot!] = b;
      }
    }

    // Filter out passed time slots based on the selected date and current clock
    final visibleSlots = GymSlotPicker.allSlots.where((slot) {
      final booking = bookingsBySlot[slot];
      final isMyBooking = booking != null && booking.residentUid == widget.currentResidentUid;
      return !AmenityBookingService.isSlotPassed(
        widget.selectedDate,
        slot,
        isCurrentResidentBooking: isMyBooking,
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '1-Hour Gym Slots',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.vpn_key_rounded, size: 14, color: Colors.teal),
                  SizedBox(width: 4),
                  Text(
                    'Key with Security Guard',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // If all slots have passed for the selected day, display friendly empty state
        if (visibleSlots.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'No Upcoming Slots Available',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey.shade800),
                ),
                const SizedBox(height: 4),
                Text(
                  'All gym slots for this date have passed. Please select a future date on the calendar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ] else ...[
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visibleSlots.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final slot = visibleSlots[index];
              final booking = bookingsBySlot[slot];
              final isBooked = booking != null;
              final isMyBooking = booking != null && booking.residentUid == widget.currentResidentUid;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isBooked
                      ? (isMyBooking ? Colors.teal.shade50 : Colors.grey.shade50)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isBooked
                        ? (isMyBooking ? Colors.teal.shade300 : Colors.grey.shade300)
                        : Colors.green.shade200,
                    width: isMyBooking ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Slot Time Icon & Text
                    Icon(
                      Icons.access_time_rounded,
                      size: 20,
                      color: isBooked ? Colors.grey.shade700 : Colors.green.shade700,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            slot,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isBooked ? Colors.black87 : Colors.green.shade900,
                            ),
                          ),
                          if (isBooked) ...[
                            const SizedBox(height: 4),
                            Text(
                              isMyBooking
                                  ? 'Your Booking (Flat ${booking.flatNumber})'
                                  : 'Booked by Flat ${booking.flatNumber} • ${booking.residentName}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isMyBooking ? Colors.teal.shade800 : Colors.black54,
                                fontWeight: isMyBooking ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildKeyStatusChip(booking.keyStatus),
                          ] else ...[
                            const SizedBox(height: 2),
                            const Text(
                              'Open for booking',
                              style: TextStyle(fontSize: 11, color: Colors.green),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Action Button
                    if (!isBooked)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        onPressed: () => widget.onSlotSelected(slot),
                        child: const Text('Reserve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    else if (isMyBooking)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Reserved',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal),
                            ),
                          ),
                          // Allow resident to unregister slot if the key hasn't been physically taken yet
                          if (widget.onUnregisterSlot != null && booking.keyStatus != GymKeyStatus.keyIssued) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Unregister slot',
                              icon: const Icon(Icons.cancel_outlined, size: 20, color: Colors.red),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => widget.onUnregisterSlot!(booking),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildKeyStatusChip(GymKeyStatus status) {
    Color bg;
    Color text;
    String label;
    IconData icon;

    switch (status) {
      case GymKeyStatus.keyWithGuard:
        bg = Colors.amber.shade50;
        text = Colors.amber.shade900;
        label = 'Key at Security Gate';
        icon = Icons.vpn_key_rounded;
        break;
      case GymKeyStatus.keyIssued:
        bg = Colors.blue.shade50;
        text = Colors.blue.shade900;
        label = 'Key Issued to Resident';
        icon = Icons.key_rounded;
        break;
      case GymKeyStatus.keyReturned:
        bg = Colors.green.shade50;
        text = Colors.green.shade900;
        label = 'Key Returned to Guard';
        icon = Icons.check_circle_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: text.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: text),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: text),
          ),
        ],
      ),
    );
  }
}
