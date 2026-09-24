import 'package:flutter/material.dart';
import '../../models/amenity_booking.dart';
import '../../services/amenity_booking_service.dart';
import '../../widgets/app_feedback.dart';

// ============================================================================
// GYM PHYSICAL KEY MANAGEMENT SHEET (SECURITY GUARD)
// ============================================================================
// Allows Security Guards at the main gate to:
// 1. View today's 1-hour Gym bookings and know which resident is authorized.
// 2. Issue the physical gym key to the resident upon arrival (`KEY_ISSUED`).
// 3. Receive and log the returned key when the workout completes (`KEY_RETURNED`).
// ============================================================================

class GymKeyManagementSheet extends StatefulWidget {
  final String guardUid;
  final String guardName;

  const GymKeyManagementSheet({
    super.key,
    required this.guardUid,
    required this.guardName,
  });

  static void show(BuildContext context, {required String guardUid, required String guardName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => GymKeyManagementSheet(
        guardUid: guardUid,
        guardName: guardName,
      ),
    );
  }

  @override
  State<GymKeyManagementSheet> createState() => _GymKeyManagementSheetState();
}

class _GymKeyManagementSheetState extends State<GymKeyManagementSheet> {
  late final Stream<List<AmenityBooking>> _gymBookingsStream;

  @override
  void initState() {
    super.initState();
    // Cache stream in state to strictly prevent redundant Firestore re-subscription on build
    _gymBookingsStream = AmenityBookingService.getTodayGymBookingsStream();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.vpn_key_rounded, color: Colors.teal),
                  SizedBox(width: 8),
                  Text(
                    'Gym Key Handover',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Track physical gym keys issued to and returned by residents.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const Divider(height: 20),

          Expanded(
            child: StreamBuilder<List<AmenityBooking>>(
              stream: _gymBookingsStream,
              builder: (context, snapshot) {
                final bookings = snapshot.data ?? [];

                if (bookings.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fitness_center_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text(
                          'No gym slots reserved for today.',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  );
                }

                // Sort chronologically by slot
                bookings.sort((a, b) => (a.slot ?? '').compareTo(b.slot ?? ''));

                return ListView.separated(
                  itemCount: bookings.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final b = bookings[index];
                    return _buildGymBookingCard(context, b);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGymBookingCard(BuildContext context, AmenityBooking booking) {
    Color cardBg = Colors.white;
    Color borderCol = Colors.grey.shade300;

    switch (booking.keyStatus) {
      case GymKeyStatus.keyWithGuard:
        cardBg = Colors.amber.shade50;
        borderCol = Colors.amber.shade300;
        break;
      case GymKeyStatus.keyIssued:
        cardBg = Colors.blue.shade50;
        borderCol = Colors.blue.shade300;
        break;
      case GymKeyStatus.keyReturned:
        cardBg = Colors.green.shade50;
        borderCol = Colors.green.shade300;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                booking.slot ?? '1-Hour Slot',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              _buildKeyStatusBadge(booking.keyStatus),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.home, size: 16, color: Colors.black54),
              const SizedBox(width: 4),
              Text(
                'Flat ${booking.flatNumber} • ${booking.residentName}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          if (booking.residentPhone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Phone: ${booking.residentPhone}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 12),

          // Action Buttons with minimum 48dp touch targets and clear semantic announcements
          if (booking.keyStatus == GymKeyStatus.keyWithGuard)
            SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: 'Hand over gym key to Flat ${booking.flatNumber}, ${booking.residentName} for slot ${booking.slot}',
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48), // WCAG 48dp minimum target
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.key_rounded, size: 18),
                  label: const Text('Hand Over Key to Resident', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    try {
                      await AmenityBookingService.guardIssueGymKey(
                        bookingId: booking.id,
                        guardUid: widget.guardUid,
                        guardName: widget.guardName,
                      );
                      if (context.mounted) {
                        AppFeedback.showSuccess(context, 'Key handed over to Flat ${booking.flatNumber}');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppFeedback.showError(context, 'Error updating key status: $e');
                      }
                    }
                  },
                ),
              ),
            )
          else if (booking.keyStatus == GymKeyStatus.keyIssued)
            SizedBox(
              width: double.infinity,
              child: Semantics(
                button: true,
                label: 'Receive returned gym key from Flat ${booking.flatNumber}, ${booking.residentName} for slot ${booking.slot}',
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48), // WCAG 48dp minimum target
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Receive Key Back from Resident', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    try {
                      await AmenityBookingService.guardReceiveGymKey(
                        bookingId: booking.id,
                        guardUid: widget.guardUid,
                        guardName: widget.guardName,
                      );
                      if (context.mounted) {
                        AppFeedback.showSuccess(context, 'Key returned by Flat ${booking.flatNumber} and logged');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppFeedback.showError(context, 'Error updating key status: $e');
                      }
                    }
                  },
                ),
              ),
            )
          else
            const Row(
              children: [
                Icon(Icons.done_all_rounded, size: 16, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  'Key safely returned to guard post',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildKeyStatusBadge(GymKeyStatus status) {
    Color bg;
    Color text;
    String label;

    switch (status) {
      case GymKeyStatus.keyWithGuard:
        bg = Colors.amber.shade100;
        text = Colors.amber.shade900;
        label = 'With Guard';
        break;
      case GymKeyStatus.keyIssued:
        bg = Colors.blue.shade100;
        text = Colors.blue.shade900;
        label = 'Issued to Resident';
        break;
      case GymKeyStatus.keyReturned:
        bg = Colors.green.shade100;
        text = Colors.green.shade900;
        label = 'Returned';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }
}
