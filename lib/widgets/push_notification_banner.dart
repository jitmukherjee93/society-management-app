import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// ============================================================================
// IN-APP HEADS-UP PUSH NOTIFICATION BANNER WIDGET
// ============================================================================
// This widget renders a floating heads-up push notification banner that slides
// down smoothly from the top of the screen when any notification arrives.
//
// Key Capabilities:
// 1. High-Visibility Styling:
//    - Elevation, rounded borders, backdrop shadow, and category-specific icons.
//    - Distinct styling for Emergency alerts (crimson red, pulsing, sticky).
// 2. Interactive Action Buttons:
//    - e.g. "Approve" / "Deny" for gate visitors.
//    - "View Receipt" for approved payments.
// 3. Gesture Controls:
//    - Swipe up to dismiss immediately.
//    - Tap body to trigger callback / view details.
// ============================================================================

/// Payload data model describing an incoming push notification event.
class PushNotificationPayload {
  /// Unique identifier of the notification document in Firestore.
  final String id;

  /// Clear, human-readable notification title.
  final String title;

  /// Clear, descriptive notification message body.
  final String message;

  /// Categorical notification type (e.g., 'EMERGENCY', 'VISITOR_CHECK_IN', 'PAYMENT_APPROVED').
  final String type;

  /// Associated flat number, if applicable.
  final String? flatNumber;

  /// Additional metadata (e.g., `visitorDocId`, `receiptNumber`, `dueDocId`).
  final Map<String, dynamic> extraData;

  /// Timestamp when notification was generated.
  final DateTime receivedAt;

  PushNotificationPayload({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.flatNumber,
    this.extraData = const {},
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  /// Returns `true` if this is a high-priority emergency alert.
  bool get isEmergency =>
      type.toUpperCase() == 'EMERGENCY' ||
      type.toUpperCase().contains('SOS') ||
      title.toUpperCase().contains('EMERGENCY');

  /// Returns `true` if this is a gate visitor entry request requiring resident action.
  bool get isVisitorApprovalRequest =>
      type == 'VISITOR_CHECK_IN' &&
      (extraData['approvalStatus'] == 'PENDING' || extraData['isWalkIn'] == true || extraData['isWalkIn'] == 'true');

  /// Returns `true` if this is a maintenance bill or payment confirmation.
  bool get isPaymentOrBill =>
      type.startsWith('PAYMENT') ||
      type.startsWith('BILL') ||
      type.startsWith('MAINTENANCE') ||
      type == 'PARKING_GAP_ALERT';

  /// Returns `true` if this is a courier/parcel notification.
  bool get isParcel => type.startsWith('PARCEL_');

  /// Returns `true` if this is a helpdesk complaint update.
  bool get isComplaint => type.startsWith('COMPLAINT_');

  /// Returns `true` if this is a daily domestic staff or helper check-in event.
  bool get isStaffEntry =>
      type == 'STAFF_ENTRY' ||
      type == 'STAFF_CHECK_IN' ||
      (extraData['isStaff'] == true || extraData['isStaff'] == 'true');

  /// Returns `true` if this visitor is a delivery executive / courier.
  bool get isDelivery {
    if (extraData['isDelivery'] == true || extraData['isDelivery'] == 'true') return true;
    final purpose = (extraData['purpose'] ?? '').toString().toLowerCase();
    if (purpose.contains('delivery') || purpose.contains('courier')) return true;
    final deliveryApp = (extraData['deliveryApp'] ?? '').toString();
    if (deliveryApp.isNotEmpty) return true;
    return false;
  }

  /// Returns the delivery company / provider brand name (e.g. Blinkit, Swiggy, Amazon), if present.
  String? get deliveryCompany {
    final app = (extraData['deliveryApp'] ?? '').toString().trim();
    if (app.isNotEmpty) return app;
    final prov = (extraData['deliveryProvider'] ?? '').toString().trim();
    if (prov.isNotEmpty) return prov;
    return null;
  }

  /// Returns the visitor's live photo URL captured at the gate, if available.
  String? get photoUrl {
    final url = (extraData['photoUrl'] ?? '').toString().trim();
    return url.isNotEmpty ? url : null;
  }
}

/// Floating Heads-up Push Notification Banner Widget.
class PushNotificationBanner extends StatefulWidget {
  final PushNotificationPayload payload;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onLeaveAtGate;
  final VoidCallback? onDeny;

  const PushNotificationBanner({
    super.key,
    required this.payload,
    required this.onDismiss,
    this.onTap,
    this.onApprove,
    this.onLeaveAtGate,
    this.onDeny,
  });

  @override
  State<PushNotificationBanner> createState() => _PushNotificationBannerState();
}

class _PushNotificationBannerState extends State<PushNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // Initialize slide-down transition animation (duration 350ms)
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeIn,
    );

    // Trigger forward animation to slide banner in
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Resolves the primary background color based on notification severity.
  Color _getHeaderColor() {
    if (widget.payload.isEmergency) return const Color(0xFFDC2626); // Crimson Red
    if (widget.payload.isVisitorApprovalRequest) return const Color(0xFFD97706); // Amber Alert
    if (widget.payload.isPaymentOrBill) return const Color(0xFF059669); // Emerald Green
    if (widget.payload.isStaffEntry) return const Color(0xFF0D9488); // Teal for Domestic Help / Staff
    if (widget.payload.isParcel) return const Color(0xFF4F46E5); // Indigo
    if (widget.payload.isComplaint) return const Color(0xFF2563EB); // Royal Blue
    return AppColors.primary; // Default Navy
  }

  /// Resolves the category icon for the push banner.
  IconData _getCategoryIcon() {
    if (widget.payload.isEmergency) return Icons.warning_amber_rounded;
    if (widget.payload.isVisitorApprovalRequest) return Icons.sensor_door_outlined;
    if (widget.payload.isPaymentOrBill) return Icons.account_balance_wallet_outlined;
    if (widget.payload.isStaffEntry) return Icons.badge_outlined;
    if (widget.payload.isParcel) return Icons.inventory_2_outlined;
    if (widget.payload.isComplaint) return Icons.build_circle_outlined;
    return Icons.notifications_active_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final headerColor = _getHeaderColor();
    final isEmergency = widget.payload.isEmergency;
    final isVisitorAction = widget.payload.isVisitorApprovalRequest &&
        (widget.onApprove != null || widget.onDeny != null);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Dismissible(
          key: Key(widget.payload.id),
          direction: DismissDirection.up,
          onDismissed: (_) => widget.onDismiss(),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: isEmergency ? Colors.red.shade400 : headerColor.withValues(alpha: 0.35),
                width: isEmergency ? 2.0 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isEmergency
                      ? Colors.red.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18.0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16.0),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row: Icon + Title + Close Button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category Avatar Badge or Live Visitor Photo
                          if (widget.payload.photoUrl != null && widget.payload.photoUrl!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20.0),
                              child: Image.network(
                                widget.payload.photoUrl!,
                                width: 40.0,
                                height: 40.0,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  padding: const EdgeInsets.all(8.0),
                                  decoration: BoxDecoration(
                                    color: headerColor.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_getCategoryIcon(), color: headerColor, size: 20.0),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(8.0),
                              decoration: BoxDecoration(
                                color: headerColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getCategoryIcon(),
                                color: headerColor,
                                size: 20.0,
                              ),
                            ),
                          const SizedBox(width: 12.0),
                          // Title & Tag
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.payload.title,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.5,
                                          color: isEmergency ? Colors.red.shade800 : const Color(0xFF1E293B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6.0),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                      decoration: BoxDecoration(
                                        color: headerColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6.0),
                                      ),
                                      child: Text(
                                        'JUST NOW',
                                        style: TextStyle(
                                          fontSize: 9.0,
                                          fontWeight: FontWeight.w700,
                                          color: headerColor,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (widget.payload.isDelivery && widget.payload.deliveryCompany != null) ...[
                                  const SizedBox(height: 3.0),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(4.0),
                                      border: Border.all(color: Colors.amber.shade300),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.local_shipping_rounded, size: 11.0, color: Colors.amber.shade900),
                                        const SizedBox(width: 3.0),
                                        Text(
                                          widget.payload.deliveryCompany!,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4.0),
                                // Body Message Text
                                Text(
                                  widget.payload.message,
                                  style: const TextStyle(
                                    fontSize: 12.8,
                                    color: Color(0xFF475569),
                                    height: 1.35,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          // Dismiss Button
                          GestureDetector(
                            onTap: widget.onDismiss,
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.close,
                                size: 18.0,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Optional Interactive Action Buttons (for Gate Visitor approvals)
                      if (isVisitorAction) ...[
                        const SizedBox(height: 12.0),
                        Row(
                          children: [
                            if (widget.onDeny != null)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: widget.onDeny,
                                  icon: const Icon(Icons.block, size: 14.0, color: Colors.red),
                                  label: const Text(
                                    'DENY',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red, width: 1.2),
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                  ),
                                ),
                              ),
                            if (widget.onLeaveAtGate != null && widget.payload.isDelivery) ...[
                              const SizedBox(width: 6.0),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: widget.onLeaveAtGate,
                                  icon: const Icon(Icons.inventory_2_outlined, size: 14.0, color: Color(0xFF0F172A)),
                                  label: const Text(
                                    'GATE',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFF334155), width: 1.2),
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (widget.onApprove != null) ...[
                              const SizedBox(width: 6.0),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: widget.onApprove,
                                  icon: const Icon(Icons.check_circle_outline, size: 14.0, color: Colors.white),
                                  label: const Text(
                                    'APPROVE',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

