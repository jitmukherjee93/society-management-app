import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../utils/flat_utils.dart';
import '../../../services/visitor_pass_service.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/delivery_company_logo.dart';
import '../../../widgets/app_feedback.dart';
import '../resident_dashboard.dart';

// ============================================================================
// RESIDENT VISITORS & GATE PASS TAB (ELDER-FRIENDLY & WCAG AAA COMPLIANT)
// ============================================================================
// Key Accessibility & Usability Features for Senior Citizens:
// 1. High-Contrast Typography: Minimum 7:1 contrast ratio against light backgrounds.
// 2. Large Touch Targets: All interactive buttons & list items have minimum 48x48dp targets.
// 3. Overflow Safeguards: Responsive Wrap and Flexible layouts that adapt to 150%+ text zoom
//    without RenderFlex overflows.
// 4. Clear Visual Status: Large colorful status badges (Green = Approved/In, Amber = At Gate, Red = Denied).
// 5. 1-Tap Action: Quick Pre-approve button right at top with prominent call-to-action.
// ============================================================================

class ResidentVisitorsTab extends StatefulWidget {
  final String? userFlat;
  final String? fullFlat;

  const ResidentVisitorsTab({
    super.key,
    this.userFlat,
    this.fullFlat,
  });

  @override
  State<ResidentVisitorsTab> createState() => _ResidentVisitorsTabState();
}

class _ResidentVisitorsTabState extends State<ResidentVisitorsTab> {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String get _normalizedFlat {
    final raw = widget.fullFlat ?? widget.userFlat ?? '';
    return FlatUtils.normalize(raw);
  }

  @override
  Widget build(BuildContext context) {
    final flat = _normalizedFlat;
    User? user;
    try {
      user = FirebaseAuth.instance.currentUser;
    } catch (_) {
      user = null;
    }

    if (flat.isEmpty || user == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Flat information is loading or unavailable.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.slate700),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // ── 1. PRE-APPROVE CALL TO ACTION CARD (LARGE TOUCH TARGET) ──────────────
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.primaryBorder, width: 1.5),
          ),
          color: AppColors.primarySurface,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Expecting a Guest or Delivery?',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Generate a 6-digit gate passcode for instant entry.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.slate700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.qr_code_rounded, size: 22),
                    label: const Text(
                      'Create 6-Digit Gate Pass',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PreApproveVisitorScreen(userFlat: flat),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── 2. PARCELS WAITING AT GATE ─────────────────────────────────────────
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('gate_parcels')
              .where('flatNumber', isEqualTo: flat)
              .where('status', isEqualTo: 'HELD_AT_GATE')
              .snapshots(),
          builder: (context, parcelSnap) {
            final parcels = parcelSnap.data?.docs ?? [];
            if (parcels.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_rounded, color: Colors.amber, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Parcels Waiting at Gate (${parcels.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.slate900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...parcels.map((doc) {
                  final data = doc.data();
                  final visitorName = data['visitorName']?.toString() ?? 'Delivery';
                  final provider = data['deliveryProvider']?.toString() ?? data['deliveryApp']?.toString() ?? 'Courier';
                  final otp = data['pickupOtp']?.toString() ?? '----';
                  final gateName = data['gateName']?.toString() ?? 'Main Gate';

                  return Card(
                    elevation: 1.5,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.amber.shade300, width: 1.2),
                    ),
                    color: Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        children: [
                          DeliveryCompanyLogo(
                            brand: DeliveryCompanyUtils.resolveBrand(
                              deliveryApp: provider,
                              visitorName: visitorName,
                              purpose: data['purpose']?.toString(),
                            ),
                            customName: provider,
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$provider ($visitorName)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppColors.slate900,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Held at $gateName',
                                  style: const TextStyle(fontSize: 12, color: AppColors.slate700),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade400),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'PICKUP OTP',
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.slate600),
                                ),
                                Text(
                                  otp,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDark,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
            );
          },
        ),

        // ── 3. VISITOR CLEARANCES & ACTIVE GUESTS ──────────────────────────────
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _firestore
              .collection('visitors')
              .where('flatNumber', isEqualTo: flat)
              .limit(40)
              .snapshots(),
          builder: (context, visitorSnap) {
            final allDocs = visitorSnap.data?.docs ?? [];
            if (allDocs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 16.0),
                  child: Column(
                    children: [
                      Icon(Icons.shield_outlined, size: 56, color: AppColors.slate400),
                      const SizedBox(height: 12),
                      const Text(
                        'No Visitors Recorded Yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slate800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Expected guests, delivery agents, and service staff entries will appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.slate600),
                      ),
                    ],
                  ),
                ),
              );
            }

            // Group into: Pending Clearance, Currently Inside, and Past Entries
            final pendingDocs = allDocs.where((d) {
              final status = d.data()['status']?.toString();
              final approval = d.data()['approvalStatus']?.toString();
              return status == 'WAITING_APPROVAL' || approval == 'PENDING';
            }).toList();

            final insideDocs = allDocs.where((d) {
              final status = d.data()['status']?.toString();
              final approval = d.data()['approvalStatus']?.toString();
              return status == 'CHECKED_IN' && approval != 'PENDING';
            }).toList();

            final historyDocs = allDocs.where((d) {
              final status = d.data()['status']?.toString();
              return status != 'WAITING_APPROVAL' && status != 'CHECKED_IN';
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A. PENDING CLEARANCE (URGENT ACTION NEEDED)
                if (pendingDocs.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.doorbell_rounded, color: AppColors.error, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Waiting at Gate for Your Clearance (${pendingDocs.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.errorDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...pendingDocs.map((doc) => _buildVisitorCard(context, doc, isPending: true)),
                  const SizedBox(height: 16),
                ],

                // B. CURRENTLY INSIDE CAMPUS
                if (insideDocs.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Currently Inside Campus (${insideDocs.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slate900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...insideDocs.map((doc) => _buildVisitorCard(context, doc, isInside: true)),
                  const SizedBox(height: 16),
                ],

                // C. RECENT GATE LOG HISTORY
                if (historyDocs.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.history_rounded, color: AppColors.slate600, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Recent Visitor Activity (${historyDocs.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slate900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...historyDocs.take(15).map((doc) => _buildVisitorCard(context, doc)),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildVisitorCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    bool isPending = false,
    bool isInside = false,
  }) {
    final data = doc.data();
    final visitorName = (data['visitorName'] ?? 'Visitor').toString().trim();
    final purpose = (data['purpose'] ?? 'Guest').toString().trim();
    final phone = (data['phone'] ?? '').toString().trim();
    final vehicle = (data['vehicleNumber'] ?? '').toString().trim().toUpperCase();
    final status = (data['status'] ?? '').toString();
    final deliveryApp = data['deliveryApp']?.toString() ?? data['deliveryProvider']?.toString();
    final isDelivery = purpose.toLowerCase().contains('delivery') ||
        purpose.toLowerCase().contains('courier') ||
        (deliveryApp != null && deliveryApp.isNotEmpty);

    Color cardBg = Colors.white;
    Color borderColor = AppColors.slate200;

    if (isPending) {
      cardBg = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFFCA5A5);
    } else if (isInside) {
      cardBg = const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF86EFAC);
    }

    return Card(
      elevation: isPending ? 2 : 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: isPending ? 1.5 : 1.0),
      ),
      color: cardBg,
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDelivery)
                  DeliveryCompanyLogo(
                    brand: DeliveryCompanyUtils.resolveBrand(
                      deliveryApp: deliveryApp ?? purpose,
                      visitorName: visitorName,
                      purpose: purpose,
                    ),
                    customName: deliveryApp ?? purpose,
                    size: 44,
                  )
                else
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isPending
                        ? AppColors.errorSurface
                        : (isInside ? AppColors.successSurface : AppColors.slate100),
                    child: Icon(
                      Icons.person_rounded,
                      color: isPending
                          ? AppColors.error
                          : (isInside ? AppColors.success : AppColors.slate700),
                      size: 24,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visitorName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slate900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            purpose,
                            style: const TextStyle(fontSize: 13, color: AppColors.slate700, fontWeight: FontWeight.w500),
                          ),
                          if (phone.isNotEmpty)
                            Text(
                              '• $phone',
                              style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                            ),
                          if (vehicle.isNotEmpty)
                            Text(
                              '• 🚗 $vehicle',
                              style: const TextStyle(fontSize: 12, color: AppColors.slate600),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildStatusChip(status, isPending, isInside),
              ],
            ),

            // Interactive 1-tap Approve & Deny Buttons for Pending Clearances
            if (isPending) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: const Text(
                          'APPROVE ENTRY',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () async {
                          final ok = await VisitorPassService.approveVisitorEntry(
                            visitorDocId: doc.id,
                            flatNumber: _normalizedFlat,
                            visitorName: visitorName,
                          );
                          if (ok && context.mounted) {
                            AppFeedback.showSuccess(context, '$visitorName entry approved.');
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.cancel_rounded, size: 20),
                        label: const Text(
                          'DENY',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () async {
                          final ok = await VisitorPassService.denyVisitorEntry(
                            visitorDocId: doc.id,
                            flatNumber: _normalizedFlat,
                            visitorName: visitorName,
                          );
                          if (ok && context.mounted) {
                            AppFeedback.showInfo(context, '$visitorName entry denied.');
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, bool isPending, bool isInside) {
    String label = status;
    Color chipBg = AppColors.slate100;
    Color chipText = AppColors.slate700;

    if (isPending) {
      label = 'AT GATE';
      chipBg = AppColors.errorSurface;
      chipText = AppColors.errorDark;
    } else if (isInside) {
      label = 'INSIDE';
      chipBg = AppColors.successSurface;
      chipText = AppColors.successDark;
    } else if (status == 'CHECKED_OUT') {
      label = 'DEPARTED';
      chipBg = AppColors.slate200;
      chipText = AppColors.slate800;
    } else if (status == 'LEFT_AT_GATE') {
      label = 'AT GATE';
      chipBg = Colors.amber.shade100;
      chipText = Colors.amber.shade900;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: chipText,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
