import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/amenity_booking.dart';
import '../services/amenity_booking_service.dart';

// ============================================================================
// AMENITY MONTH CALENDAR WIDGET
// ============================================================================
// Interactive monthly calendar rendering visual availability badges:
// - Green: Open / Available for booking.
// - Red: Confirmed reservation (Blocked).
// - Amber: Pending Admin review.
// - Grey: Past dates or dates within 2-day mandatory lead time window.
// ============================================================================

class AmenityCalendarView extends StatelessWidget {
  final DateTime currentMonth;
  final DateTime selectedDate;
  final List<AmenityBooking> bookings;
  final AmenityType amenityType;
  final ValueChanged<DateTime> onDateSelected;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const AmenityCalendarView({
    super.key,
    required this.currentMonth,
    required this.selectedDate,
    required this.bookings,
    required this.amenityType,
    required this.onDateSelected,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(currentMonth.year, currentMonth.month + 1, 0).day;
    final firstDayWeekday = DateTime(currentMonth.year, currentMonth.month, 1).weekday; // 1 = Mon, 7 = Sun
    final leadingBlanks = (firstDayWeekday - 1) % 7;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Map bookings by date string (YYYY-MM-DD)
    // Multi-day bookings populate all intermediate days between bookingDate and endDate
    final Map<String, List<AmenityBooking>> bookingsByDate = {};
    for (final b in bookings) {
      if (b.status == BookingStatus.cancelled || b.status == BookingStatus.rejected) continue;
      bookingsByDate.putIfAbsent(b.bookingDate, () => []).add(b);
      if (b.endDate != null && b.endDate!.isNotEmpty && b.endDate != b.bookingDate) {
        DateTime curr = AmenityBookingService.parseDate(b.bookingDate).add(const Duration(days: 1));
        final end = AmenityBookingService.parseDate(b.endDate!);
        while (!curr.isAfter(end)) {
          bookingsByDate.putIfAbsent(AmenityBookingService.formatDate(curr), () => []).add(b);
          curr = curr.add(const Duration(days: 1));
        }
      }
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Month Header with navigation
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: onPrevMonth,
                  tooltip: 'Previous Month',
                ),
                Text(
                  DateFormat('MMMM yyyy').format(currentMonth),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: onNextMonth,
                  tooltip: 'Next Month',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Weekday Headers with full screen-reader speech accessibility
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                _WeekdayHeader('M', fullLabel: 'Monday'),
                _WeekdayHeader('T', fullLabel: 'Tuesday'),
                _WeekdayHeader('W', fullLabel: 'Wednesday'),
                _WeekdayHeader('T', fullLabel: 'Thursday'),
                _WeekdayHeader('F', fullLabel: 'Friday'),
                _WeekdayHeader('S', fullLabel: 'Saturday'),
                _WeekdayHeader('S', fullLabel: 'Sunday'),
              ],
            ),
            const Divider(height: 16),

            // Days Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leadingBlanks + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
                if (index < leadingBlanks) {
                  return const SizedBox.shrink();
                }

                final day = index - leadingBlanks + 1;
                final cellDate = DateTime(currentMonth.year, currentMonth.month, day);
                final dateStr = AmenityBookingService.formatDate(cellDate);
                final isSelected = cellDate.year == selectedDate.year &&
                    cellDate.month == selectedDate.month &&
                    cellDate.day == selectedDate.day;
                final isToday = cellDate.year == today.year &&
                    cellDate.month == today.month &&
                    cellDate.day == today.day;
                final isPast = cellDate.isBefore(today);

                // Check 2-day advance notice rule for Hall & Ground
                final isLeadTimeBlocked = amenityType != AmenityType.gym &&
                    !isPast &&
                    !AmenityBookingService.isLeadTimeValid(cellDate, today);

                final dayBookings = bookingsByDate[dateStr] ?? [];
                final hasConfirmed = dayBookings.any((b) => b.status == BookingStatus.confirmed);
                final hasPending = dayBookings.any((b) => b.status == BookingStatus.pendingApproval);

                // Determine tile color & state
                Color tileBg = Colors.white;
                Color textColor = Colors.black87;
                Border? tileBorder;

                if (hasConfirmed && amenityType != AmenityType.gym) {
                  tileBg = Colors.red.shade50;
                  textColor = Colors.red.shade900;
                  tileBorder = Border.all(color: Colors.red.shade300);
                } else if (hasPending && amenityType != AmenityType.gym) {
                  tileBg = Colors.amber.shade50;
                  textColor = Colors.amber.shade900;
                  tileBorder = Border.all(color: Colors.amber.shade300);
                } else if (isPast) {
                  tileBg = Colors.grey.shade100;
                  textColor = Colors.grey.shade500;
                } else if (isLeadTimeBlocked) {
                  tileBg = Colors.grey.shade100;
                  textColor = Colors.grey.shade600;
                } else if (amenityType == AmenityType.gym && dayBookings.isNotEmpty) {
                  // For gym, show blue indicator if slots are reserved
                  tileBg = Colors.teal.shade50;
                  textColor = Colors.teal.shade900;
                  tileBorder = Border.all(color: Colors.teal.shade300);
                } else {
                  tileBg = Colors.green.shade50;
                  textColor = Colors.green.shade900;
                  tileBorder = Border.all(color: Colors.green.shade200);
                }

                if (isSelected) {
                  tileBorder = Border.all(color: const Color(0xFF0F766E), width: 2.5);
                } else if (isToday) {
                  tileBorder = Border.all(color: Colors.blue.shade500, width: 1.5);
                }

                final daySemanticStatus = isPast
                    ? 'Past date'
                    : (hasConfirmed && amenityType != AmenityType.gym
                        ? 'Booked'
                        : (hasPending && amenityType != AmenityType.gym
                            ? 'Pending admin approval'
                            : (isLeadTimeBlocked
                                ? 'Unavailable, within 2 days notice'
                                : (amenityType == AmenityType.gym && dayBookings.isNotEmpty
                                    ? '${dayBookings.length} gym slot(s) reserved'
                                    : 'Available for booking'))));

                return Semantics(
                  button: !isPast,
                  selected: isSelected,
                  label: '${DateFormat('EEEE, d MMMM yyyy').format(cellDate)}, $daySemanticStatus',
                  child: InkWell(
                    onTap: isPast
                        ? null
                        : () => onDateSelected(cellDate),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: tileBg,
                        borderRadius: BorderRadius.circular(10),
                        border: tileBorder,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            '$day',
                            style: TextStyle(
                              fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.w600,
                              color: textColor,
                              fontSize: 13,
                            ),
                          ),
                          // Small indicator dot for booked gym slots or status
                          if (dayBookings.isNotEmpty)
                            Positioned(
                              bottom: 3,
                              child: Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: hasConfirmed ? Colors.red : (hasPending ? Colors.amber.shade800 : Colors.teal),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Calendar Legend
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _LegendPill(color: Colors.green.shade100, label: 'Available'),
                if (amenityType != AmenityType.gym) ...[
                  _LegendPill(color: Colors.red.shade100, label: 'Blocked / Booked'),
                  _LegendPill(color: Colors.amber.shade100, label: 'Pending Review'),
                  _LegendPill(color: Colors.grey.shade200, label: '< 2 Days Lead Time'),
                ] else ...[
                  _LegendPill(color: Colors.teal.shade100, label: 'Has Reserved Slots'),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final String label;
  final String fullLabel;

  const _WeekdayHeader(this.label, {required this.fullLabel});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: fullLabel,
      child: SizedBox(
        width: 32,
        height: 24,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.black12),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

extension ColorExtension on Colors {
  static MaterialColor get emerald => Colors.green;
}
