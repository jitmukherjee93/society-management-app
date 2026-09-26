import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/pdf_iframe.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../widgets/app_dialog.dart';
import '../../services/notification_service.dart';
import '../../services/push_notification_manager.dart';
import 'package:intl/intl.dart';
import '../../models/accounting_heads.dart';
import 'tabs/admin_home_dashboard_tab.dart';
import 'tabs/manage_society_tab.dart';
import 'tabs/accounts_tab.dart';
import 'tabs/generate_maintenance_tab.dart';
import 'tabs/manage_announcements_tab.dart';
import 'tabs/manage_complaints_tab.dart';
import 'tabs/admin_visitors_tab.dart';
// Admin tab for approving Community Hall, Ground & Gym reservations
import 'tabs/manage_amenity_bookings_tab.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  String? _selectedFlatQuery;
  String? _selectedSubTab;
  bool _isSidebarCollapsed = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Register Push Notification Click Delegate for instant admin tab navigation and modal review
    PushNotificationManager.instance.onNotificationClick = (ctx, payload) {
      final notifDocRef = FirebaseFirestore.instance.collection('notifications').doc(payload.id);
      _handleNotificationClick(payload.extraData, notifDocRef);
    };
  }

  @override
  void dispose() {
    // Clean up delegate on screen unmount
    if (PushNotificationManager.instance.onNotificationClick != null) {
      PushNotificationManager.instance.onNotificationClick = null;
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchSubmit(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _selectedFlatQuery = trimmed;
      _currentIndex = 1; // Manage Society & Flats Tab
    });
    _searchController.clear();
  }

  void _showNotificationsDialog(BuildContext context) {
    AppDialog.show(
      context: context,
      title: 'Admin Notifications',
      subtitle: 'Real-time alerts and resident submissions',
      icon: Icons.notifications_active_rounded,
      iconColor: AppColors.primary,
      maxWidth: 540,
      content: SizedBox(
        height: 380,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('targetRole', isEqualTo: 'ADMIN')
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text(
                  'Error loading notifications: ${snap.error}',
                  style: const TextStyle(color: AppColors.error),
                ),
              );
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            final docs = (snap.data?.docs ?? []).toList();
            docs.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = (aData['createdAt'] as Timestamp?)?.toDate() ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              final bTime = (bData['createdAt'] as Timestamp?)?.toDate() ??
                  DateTime.fromMillisecondsSinceEpoch(0);
              return bTime.compareTo(aTime);
            });

            if (docs.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 40, color: AppColors.textMuted),
                    SizedBox(height: 8),
                    Text('No pending admin notifications.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              );
            }

            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final notif = docs[i].data() as Map<String, dynamic>;
                final isRead = notif['isRead'] == true;
                final title = notif['title'] ?? 'Notification';
                final msg = notif['message'] ?? '';
                final type = (notif['type'] ?? '').toString().toUpperCase();
                final isVehicleReq = type == 'VEHICLE_UPDATE_REQUEST';

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  leading: AppDecorations.iconContainer(
                    icon: isVehicleReq ? Icons.directions_car_rounded : Icons.info_outline_rounded,
                    color: isVehicleReq ? AppColors.warning : AppColors.primary,
                    size: 18,
                    padding: 8,
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(msg, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        isVehicleReq ? 'Tap to review & approve request →' : 'Tap to view in dashboard →',
                        style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
                    tooltip: 'Dismiss',
                    onPressed: () => docs[i].reference.delete(),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _handleNotificationClick(notif, docs[i].reference);
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('targetRole', isEqualTo: 'ADMIN')
              .snapshots(),
          builder: (context, snap) {
            final unread = (snap.data?.docs ?? [])
                .where((d) => (d.data() as Map)['isRead'] != true)
                .map((d) => d.id)
                .toList();
            if (unread.isEmpty) return const SizedBox.shrink();
            return TextButton.icon(
              onPressed: () async {
                await NotificationService.markAllAsRead(unread);
              },
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: const Text('Mark all read'),
            );
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _handleNotificationClick(
      Map<String, dynamic> notif, DocumentReference notifDocRef) {
    if (notif['isRead'] != true) {
      NotificationService.markAsRead(notifDocRef.id);
    }
    final type = (notif['type'] ?? '').toString().toUpperCase();
    final title = (notif['title'] ?? '').toString().toLowerCase();
    final message = (notif['message'] ?? '').toString().toLowerCase();

    if (type == 'VEHICLE_UPDATE_REQUEST' ||
        title.contains('vehicle') ||
        title.contains('car') ||
        title.contains('bike')) {
      final flat = notif['flatNumber']?.toString();
      setState(() {
        _selectedFlatQuery = flat;
        _currentIndex = 1; // Manage Society & Flats Tab
      });
      _showVehicleReviewDialog(notif, notifDocRef);
    } else if (type == 'COMPLAINT' ||
        title.contains('complaint') ||
        message.contains('complaint')) {
      setState(() => _currentIndex = 4); // Manage Complaints Tab
    } else if (type == 'MAINTENANCE_PAYMENT_APPROVAL_REQUEST' ||
        type == 'OFFLINE_PAYMENT_SUBMITTED' ||
        type == 'PAYMENT' ||
        title.contains('payment') ||
        message.contains('payment') ||
        title.contains('utr') ||
        message.contains('utr') ||
        type == 'MAINTENANCE' ||
        title.contains('maintenance') ||
        message.contains('maintenance')) {
      setState(() => _currentIndex = 5); // Bills Tab (Payment Verification & Billing)
    } else if (type == 'ANNOUNCEMENT' ||
        title.contains('announcement') ||
        message.contains('announcement')) {
      setState(() => _currentIndex = 3); // Manage Announcements Tab
    } else if (type == 'ACCOUNT' ||
        title.contains('account') ||
        title.contains('expense') ||
        title.contains('income')) {
      setState(() => _currentIndex = 2); // Accounts Tab
    } else if (type.contains('VISITOR') ||
        title.contains('visitor') ||
        message.contains('visitor')) {
      setState(() => _currentIndex = 6); // Visitors Tab
    } else if (type.contains('AMENITY') ||
        title.contains('booking') ||
        message.contains('booking') ||
        notif['amenity'] != null) {
      // Direct navigation to Amenity Bookings Tab for reviewing pending requests and verifying advance payments
      setState(() => _currentIndex = 7); // Amenity Bookings Tab
    } else if (notif['flatNumber'] != null) {
      setState(() {
        _selectedFlatQuery = notif['flatNumber']?.toString();
        _currentIndex = 1;
      });
    }
  }

  Future<void> _showVehicleReviewDialog(
    Map<String, dynamic> notif,
    DocumentReference notifDocRef,
  ) async {
    final userId = notif['userId']?.toString();
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resident user ID not attached to this notification.')),
      );
      return;
    }

    // Fetch resident user record
    DocumentSnapshot userSnap;
    try {
      userSnap = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading resident record: $e')),
      );
      return;
    }

    if (!mounted) return;

    if (!userSnap.exists) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Record Not Found'),
          content: const Text('The resident record for this notification no longer exists.'),
          actions: [
            TextButton(
              onPressed: () {
                notifDocRef.delete();
                Navigator.pop(ctx);
              },
              child: const Text('Dismiss Notification'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    final userData = userSnap.data() as Map<String, dynamic>;
    final residentName = userData['name']?.toString() ?? 'Resident';
    final flatNumber = notif['flatNumber']?.toString() ?? userData['flatNumber']?.toString() ?? 'N/A';
    final vehicleType = notif['vehicleType']?.toString() ?? 'Car';

    String? pendingReg;
    String? rcUrl;
    String? rcFileName;

    if (vehicleType == 'Car') {
      pendingReg = userData['pendingCarReg']?.toString().trim();
      rcUrl = userData['pendingCarRcUrl']?.toString();
      rcFileName = userData['pendingCarRcFileName']?.toString();
    } else if (vehicleType == 'Bike 1' || vehicleType == 'Bike') {
      pendingReg = userData['pendingBikeReg']?.toString().trim();
      rcUrl = userData['pendingBikeRcUrl']?.toString();
      rcFileName = userData['pendingBikeRcFileName']?.toString();
    } else if (vehicleType == 'Bike 2') {
      pendingReg = userData['pendingBike2Reg']?.toString().trim();
      rcUrl = userData['pendingBike2RcUrl']?.toString();
      rcFileName = userData['pendingBike2RcFileName']?.toString();
    }

    pendingReg ??= notif['requestedReg']?.toString().trim();

    if (pendingReg == null || pendingReg.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Request Already Handled'),
          content: Text(
            'The $vehicleType update request for $residentName (Flat $flatNumber) has already been approved or rejected.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                notifDocRef.delete();
                Navigator.pop(ctx);
              },
              child: const Text('Dismiss Notification'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              vehicleType == 'Car' ? Icons.directions_car : Icons.two_wheeler,
              color: Colors.deepPurple,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Review $vehicleType Request')),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.sizeOf(ctx).width.clamp(0.0, 480.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  color: Colors.deepPurple.shade50,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _detailRow('Flat No.', flatNumber, isBold: true),
                        const Divider(height: 12),
                        _detailRow('Resident', residentName),
                        const Divider(height: 12),
                        _detailRow('Vehicle Type', vehicleType),
                        const Divider(height: 12),
                        _detailRow(
                          'Requested Reg No.',
                          pendingReg ?? 'N/A',
                          isBold: true,
                          highlight: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (rcUrl != null && rcUrl.isNotEmpty) ...[
                  const Text(
                    'Uploaded RC / Blue Book Document:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _showRcPreviewDialog(
                      rcUrl!,
                      rcFileName ?? 'RC_Document',
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.deepPurple.shade200),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf,
                              color: Colors.red, size: 28),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rcFileName ?? 'RC Document',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Text(
                                  'Click to preview document',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.visibility, color: Colors.deepPurple),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'No RC document uploaded with this request.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Reject'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _promptRejectVehicle(userId, userData, vehicleType, notifDocRef);
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Approve'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _executeApproveVehicle(
                userId,
                userData,
                vehicleType,
                pendingReg!,
                notifDocRef,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value,
      {bool isBold = false, bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: highlight ? Colors.deepPurple : Colors.black87,
            fontSize: highlight ? 14 : 13,
          ),
        ),
      ],
    );
  }

  Future<void> _executeApproveVehicle(
    String userId,
    Map<String, dynamic> userData,
    String vehicleType,
    String approvedReg,
    DocumentReference notifDocRef,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      // Re-verify flat vehicle quotas to prevent race conditions
      final flatNumber = userData['flatNumber']?.toString();
      if (flatNumber != null && flatNumber.isNotEmpty) {
        final flatMembersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('flatNumber', isEqualTo: flatNumber)
            .get();

        int otherCars = 0;
        int otherBikes = 0;
        for (final doc in flatMembersSnap.docs) {
          final d = doc.data();
          if (doc.id != userId) {
            if (d['isCarOwner'] == true && (d['carReg']?.toString().trim().isNotEmpty ?? false)) {
              otherCars++;
            }
            if (d['isBikeOwner'] == true && (d['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
              otherBikes++;
            }
            if (d['hasBike2'] == true && (d['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
              otherBikes++;
            }
          } else {
            if (vehicleType == 'Bike 2') {
              if (d['isBikeOwner'] == true && (d['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
                otherBikes++;
              }
            } else if (vehicleType == 'Bike 1' || vehicleType == 'Bike') {
              if (d['hasBike2'] == true && (d['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
                otherBikes++;
              }
            }
          }
        }

        if (vehicleType == 'Car' && otherCars >= 1) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Flat Quota Exceeded'),
                content: Text(
                  'Cannot approve Car update. Flat $flatNumber already has 1 approved Car registered to an occupant.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        }

        if ((vehicleType == 'Bike 1' || vehicleType == 'Bike' || vehicleType == 'Bike 2') && otherBikes >= 2) {
          if (mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Flat Quota Exceeded'),
                content: Text(
                  'Cannot approve $vehicleType update. Flat $flatNumber already has 2 approved Bikes registered.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }

      final updateData = <String, dynamic>{};
      if (vehicleType == 'Car') {
        updateData['carReg'] = approvedReg;
        updateData['isCarOwner'] = true;
        updateData['pendingCarReg'] = FieldValue.delete();
        updateData['pendingCarRcUrl'] = FieldValue.delete();
        updateData['pendingCarRcFileName'] = FieldValue.delete();
        updateData['carRejectionReason'] = FieldValue.delete();
      } else if (vehicleType == 'Bike 1' || vehicleType == 'Bike') {
        updateData['bikeReg'] = approvedReg;
        updateData['isBikeOwner'] = true;
        updateData['pendingBikeReg'] = FieldValue.delete();
        updateData['pendingBikeRcUrl'] = FieldValue.delete();
        updateData['pendingBikeRcFileName'] = FieldValue.delete();
        updateData['bikeRejectionReason'] = FieldValue.delete();
      } else if (vehicleType == 'Bike 2') {
        updateData['bike2Reg'] = approvedReg;
        updateData['hasBike2'] = true;
        updateData['pendingBike2Reg'] = FieldValue.delete();
        updateData['pendingBike2RcUrl'] = FieldValue.delete();
        updateData['pendingBike2RcFileName'] = FieldValue.delete();
        updateData['bike2RejectionReason'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance.collection('users').doc(userId).update(updateData);

      // Notify resident with clear push notification message
      final targetUid = userData['uid']?.toString();
      final residentFlat = userData['flatNumber']?.toString() ?? '';
      if (targetUid != null && targetUid.isNotEmpty) {
        await NotificationService.notifyResident(
          flatNumber: residentFlat,
          targetUid: targetUid,
          title: '🚗 $vehicleType Registration Approved',
          message: 'Your vehicle update request for $vehicleType ($approvedReg) has been approved by Society Management.',
          type: 'VEHICLE_APPROVED',
          extraData: {
            'vehicleType': vehicleType,
            'regNumber': approvedReg,
            'flatNumber': residentFlat,
          },
        );
      }

      // Dismiss admin notification
      await notifDocRef.delete();

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('$vehicleType number update approved successfully!')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to approve update: $e')),
      );
    }
  }

  Future<void> _promptRejectVehicle(
    String userId,
    Map<String, dynamic> userData,
    String vehicleType,
    DocumentReference notifDocRef,
  ) async {
    final reasonController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reject $vehicleType Update'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please specify the reason for rejecting this $vehicleType update:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Invalid RC document, number mismatch...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter a rejection reason.')),
                );
                return;
              }
              Navigator.pop(ctx, reason);
            },
            child: const Text('Reject Update'),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return;
    final reason = result.trim();
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final updateData = <String, dynamic>{};
      if (vehicleType == 'Car') {
        updateData['pendingCarReg'] = FieldValue.delete();
        updateData['pendingCarRcUrl'] = FieldValue.delete();
        updateData['pendingCarRcFileName'] = FieldValue.delete();
        updateData['carRejectionReason'] = reason;
      } else if (vehicleType == 'Bike 1' || vehicleType == 'Bike') {
        updateData['pendingBikeReg'] = FieldValue.delete();
        updateData['pendingBikeRcUrl'] = FieldValue.delete();
        updateData['pendingBikeRcFileName'] = FieldValue.delete();
        updateData['bikeRejectionReason'] = reason;
      } else if (vehicleType == 'Bike 2') {
        updateData['pendingBike2Reg'] = FieldValue.delete();
        updateData['pendingBike2RcUrl'] = FieldValue.delete();
        updateData['pendingBike2RcFileName'] = FieldValue.delete();
        updateData['bike2RejectionReason'] = reason;
      }

      await FirebaseFirestore.instance.collection('users').doc(userId).update(updateData);

      // Notify resident with clear push notification message
      final targetUid = userData['uid']?.toString();
      final residentFlat = userData['flatNumber']?.toString() ?? '';
      if (targetUid != null && targetUid.isNotEmpty) {
        await NotificationService.notifyResident(
          flatNumber: residentFlat,
          targetUid: targetUid,
          title: '⚠️ $vehicleType Registration Update Rejected',
          message: 'Your request to update $vehicleType registration was rejected: $reason. Please contact the society office if you need assistance.',
          type: 'VEHICLE_REJECTED',
          extraData: {
            'vehicleType': vehicleType,
            'rejectionReason': reason,
            'flatNumber': residentFlat,
          },
        );
      }

      // Dismiss admin notification
      await notifDocRef.delete();

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('$vehicleType number update rejected.')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to reject update: $e')),
      );
    }
  }

  void _showRcPreviewDialog(String url, String fileName) {
    final isPdf = fileName.toLowerCase().endsWith('.pdf') ||
        url.toLowerCase().contains('.pdf');
    final isImage = fileName.toLowerCase().endsWith('.png') ||
        fileName.toLowerCase().endsWith('.jpg') ||
        fileName.toLowerCase().endsWith('.jpeg') ||
        url.toLowerCase().contains('.png') ||
        url.toLowerCase().contains('.jpg') ||
        url.toLowerCase().contains('.jpeg');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Preview: $fileName',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.sizeOf(ctx).width.clamp(0.0, 600.0),
          height: (MediaQuery.sizeOf(ctx).height * 0.65).clamp(280.0, 480.0),
          child: isPdf
              ? buildPdfIframe(url)
              : isImage
                  ? InteractiveViewer(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                              child: CircularProgressIndicator());
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Text(
                              'Failed to load image. Please download to view.'),
                        ),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.description,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'Document: $fileName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Preview is only available for images and PDFs. Please download to view other formats.',
                        ),
                      ],
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download / Open'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }

  String _getTabTitle(int index) {
    switch (index) {
      case 0:
        return 'Dashboard Overview';
      case 1:
        return 'Flats & Residents';
      case 2:
        return 'Accounts & Ledger';
      case 3:
        return 'Notices & Broadcasts';
      case 4:
        return 'Helpdesk Tickets';
      case 5:
        return 'Maintenance Bills';
      case 6:
        return 'Visitors & Gate';
      case 7:
        return 'Amenity Bookings';
      default:
        return 'Admin Portal';
    }
  }

  // ─── Desktop / Laptop Sidebar ─────────────────────────────────────────────

  Widget _buildDesktopSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: _isSidebarCollapsed ? 76 : 246,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header branding & collapse button
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: _isSidebarCollapsed ? 12 : 16),
            alignment: _isSidebarCollapsed ? Alignment.center : Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
            ),
            child: _isSidebarCollapsed
                ? IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded, size: 20, color: Colors.white),
                    ),
                    tooltip: 'Expand sidebar',
                    onPressed: () => setState(() => _isSidebarCollapsed = false),
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded, size: 20, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Ramkrishnapuram',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'RWA Admin Portal',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.chevron_left_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        tooltip: 'Collapse sidebar',
                        onPressed: () => setState(() => _isSidebarCollapsed = true),
                      ),
                    ],
                  ),
          ),

          // Categorized Navigation List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              children: [
                _buildSidebarSectionHeader('OVERVIEW'),
                _buildSidebarNavItem(
                  0,
                  'Dashboard',
                  Icons.dashboard_outlined,
                  Icons.dashboard_rounded,
                ),
                const SizedBox(height: 12),

                _buildSidebarSectionHeader('COMMUNITY & ACCESS'),
                _buildSidebarNavItem(
                  1,
                  'Flats & Units',
                  Icons.apartment_outlined,
                  Icons.apartment_rounded,
                ),
                _buildSidebarNavItem(
                  6,
                  'Visitors & Gate',
                  Icons.badge_outlined,
                  Icons.badge_rounded,
                ),
                _buildSidebarNavItem(
                  7,
                  'Amenity Bookings',
                  Icons.event_available_outlined,
                  Icons.event_available_rounded,
                  trailing: _buildPendingAmenityBadge(),
                ),
                const SizedBox(height: 12),

                _buildSidebarSectionHeader('FINANCE & LEDGER'),
                _buildSidebarNavItem(
                  5,
                  'Maintenance Bills',
                  Icons.receipt_long_outlined,
                  Icons.receipt_long_rounded,
                  trailing: _buildPendingPaymentsBadge(),
                ),
                _buildSidebarNavItem(
                  2,
                  'Accounts & Ledger',
                  Icons.account_balance_wallet_outlined,
                  Icons.account_balance_wallet_rounded,
                ),
                const SizedBox(height: 12),

                _buildSidebarSectionHeader('COMMUNICATION'),
                _buildSidebarNavItem(
                  3,
                  'Notices & Broadcasts',
                  Icons.campaign_outlined,
                  Icons.campaign_rounded,
                ),
                _buildSidebarNavItem(
                  4,
                  'Helpdesk Tickets',
                  Icons.support_agent_outlined,
                  Icons.support_agent_rounded,
                  trailing: _buildOpenComplaintsBadge(),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Sidebar Footer with System Status
          Container(
            padding: EdgeInsets.all(_isSidebarCollapsed ? 12 : 16),
            child: _isSidebarCollapsed
                ? const Center(
                    child: Tooltip(
                      message: 'Ramkrishnapuram RWA\nVersion 1.2.0 • Online',
                      child: Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.success.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'System Online',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'v1.2.0 • Admin Portal',
                        style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarSectionHeader(String title) {
    if (_isSidebarCollapsed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(height: 1, color: AppColors.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 4, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildSidebarNavItem(
    int index,
    String title,
    IconData icon,
    IconData activeIcon, {
    Widget? trailing,
  }) {
    final isSelected = _currentIndex == index;
    final content = Semantics(
      button: true,
      selected: isSelected,
      label: '$title tab',
      child: InkWell(
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 46), // WCAG touch target
          padding: EdgeInsets.symmetric(
            horizontal: _isSidebarCollapsed ? 8 : 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: AppColors.primaryBorder.withValues(alpha: 0.8), width: 1)
                : null,
          ),
          child: Row(
            mainAxisAlignment: _isSidebarCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                size: 20,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              if (!_isSidebarCollapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[
                  trailing,
                  const SizedBox(width: 4),
                ],
                if (isSelected && trailing == null)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    if (_isSidebarCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Tooltip(
          message: title,
          preferBelow: false,
          child: content,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: content,
    );
  }

  // Live badge helpers for sidebar and mobile drawer
  Widget _buildPendingPaymentsBadge() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('maintenance_dues')
          .where('status', isEqualTo: 'PAYMENT_PENDING_APPROVAL')
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade300, width: 0.8),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
          ),
        );
      },
    );
  }

  Widget _buildPendingAmenityBadge() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('amenity_bookings')
          .where('status', isEqualTo: 'PENDING_APPROVAL')
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.purple.shade300, width: 0.8),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple.shade900),
          ),
        );
      },
    );
  }

  Widget _buildOpenComplaintsBadge() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('complaints')
          .where('status', whereIn: ['OPEN', 'PENDING', 'ESCALATED'])
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade300, width: 0.8),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade900),
          ),
        );
      },
    );
  }

  // ─── Desktop Header with Breadcrumb & Search Shortcut ───────────────────────

  Widget _buildDesktopHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Section Breadcrumb
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Admin Portal',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Text(
                _getTabTitle(_currentIndex),
                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w700),
              ),
            ],
          ),

          const SizedBox(width: 24),

          // Search Input with Ctrl + K Shortcut
          Container(
            width: 320,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onSubmitted: _handleSearchSubmit,
                    style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Search flats, units... (Ctrl + K)',
                      hintStyle: TextStyle(fontSize: 12, color: AppColors.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'Ctrl K',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Society badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardSurfaceSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_city_rounded, size: 15, color: AppColors.textSecondary),
                SizedBox(width: 6),
                Text(
                  'Ramkrishnapuram RWA',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // FY Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primaryBorder),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_month_rounded, size: 14, color: AppColors.primary),
                SizedBox(width: 5),
                Text(
                  'FY 2026-27',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                ),
              ],
            ),
          ),

          if (AccountingConfig.simulatedDate != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warningSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warningBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.warningDark),
                  const SizedBox(width: 5),
                  Text(
                    'Simulated: ${DateFormat('dd MMM yyyy').format(AccountingConfig.currentDate)}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.warningDark),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(width: 12),

          // Notifications Bell
          _AdminNotificationBadge(
            onPressed: () => _showNotificationsDialog(context),
          ),

          const SizedBox(width: 8),

          // Admin Profile Avatar & Popup Menu
          PopupMenuButton<String>(
            tooltip: 'Admin Account',
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'logout') {
                FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Signed in as', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    Text('Admin Office', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    Divider(),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 16, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.cardSurfaceSecondary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.primary,
                    child: Text('AD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  SizedBox(width: 8),
                  Text('Admin', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Icon(Icons.arrow_drop_down_rounded, size: 18, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Mobile Drawer ─────────────────────────────────────────────────────────

  Widget _buildMobileDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header with Society Logo & Admin Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded, size: 24, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ramkrishnapuram',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'RWA Admin Portal',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, size: 13, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'Signed in as Administrator • FY 26-27',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Modules Menu List
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                children: [
                  _buildDrawerNavItem(
                    0,
                    'Dashboard Overview',
                    'Key metrics & quick actions',
                    Icons.dashboard_rounded,
                  ),
                  _buildDrawerNavItem(
                    1,
                    'Flats & Residents',
                    'Flats directory, owners, vehicles',
                    Icons.apartment_rounded,
                  ),
                  _buildDrawerNavItem(
                    6,
                    'Visitors & Gate',
                    'Entry logs & overstay clearances',
                    Icons.badge_rounded,
                  ),
                  _buildDrawerNavItem(
                    7,
                    'Amenity Bookings',
                    'Community Hall, Ground & Gym',
                    Icons.event_available_rounded,
                    trailing: _buildPendingAmenityBadge(),
                  ),
                  const Divider(height: 16, color: AppColors.border),
                  _buildDrawerNavItem(
                    5,
                    'Maintenance Bills',
                    'Billing generation & payment approvals',
                    Icons.receipt_long_rounded,
                    trailing: _buildPendingPaymentsBadge(),
                  ),
                  _buildDrawerNavItem(
                    2,
                    'Accounts & Ledger',
                    'Income, expenses & financial vouchers',
                    Icons.account_balance_wallet_rounded,
                  ),
                  const Divider(height: 16, color: AppColors.border),
                  _buildDrawerNavItem(
                    3,
                    'Notices & Broadcasts',
                    'Society notices & alerts',
                    Icons.campaign_rounded,
                  ),
                  _buildDrawerNavItem(
                    4,
                    'Helpdesk Tickets',
                    'Resident grievances & tracking',
                    Icons.support_agent_rounded,
                    trailing: _buildOpenComplaintsBadge(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.border),

            // Drawer Footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Online • v1.2.0',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      FirebaseAuth.instance.signOut();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 16, color: AppColors.error),
                    label: const Text('Logout', style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerNavItem(
    int index,
    String title,
    String subtitle,
    IconData icon, {
    Widget? trailing,
  }) {
    final isSelected = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        selected: isSelected,
        selectedTileColor: AppColors.primaryLight,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.cardSurfaceSecondary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: trailing,
        onTap: () {
          Navigator.pop(context);
          setState(() => _currentIndex = index);
        },
      ),
    );
  }

  // ─── Main Scaffold Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pages = [
      AdminHomeDashboardTab(
        onNavigateToTab: (index, {subTab, filter}) {
          setState(() {
            _currentIndex = index;
            _selectedSubTab = subTab;
            if (filter != null && filter.isNotEmpty) {
              _selectedFlatQuery = filter;
            }
          });
        },
        onOpenNotifications: () => _showNotificationsDialog(context),
      ),
      ManageSocietyTab(
        key: ValueKey('${_selectedFlatQuery ?? 'society_default'}_$_selectedSubTab'),
        initialSearchQuery: _selectedFlatQuery,
        initialSubTab: _selectedSubTab,
      ),
      const AccountsTab(),
      const ManageAnnouncementsTab(),
      const ManageComplaintsTab(),
      const GenerateMaintenanceTab(),
      const AdminVisitorsTab(),
      // Tab 7: Amenity booking approval, schedule tracking, and balance payment collection
      const ManageAmenityBookingsTab(),
    ];

    final isDesktop = MediaQuery.sizeOf(context).width >= 960;

    if (isDesktop) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
            _searchFocusNode.requestFocus();
          },
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Row(
            children: [
              _buildDesktopSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _buildDesktopHeader(),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.015),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey<int>(_currentIndex),
                          child: pages[_currentIndex],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile / Tablet layout (< 960px)
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      drawer: _buildMobileDrawer(context),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
            tooltip: 'Open navigation menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getTabTitle(_currentIndex),
                    style: TextStyle(
                      fontSize: isMobile ? 14 : 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Ramkrishnapuram RWA',
                    style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
        actions: [
          if (AccountingConfig.simulatedDate != null)
            Tooltip(
              message: 'Simulated Date: ${DateFormat('dd MMMM yyyy').format(AccountingConfig.currentDate)}',
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warningSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.warningBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.warningDark),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd MMM').format(AccountingConfig.currentDate),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.warningDark),
                    ),
                  ],
                ),
              ),
            ),
          _AdminNotificationBadge(
            onPressed: () => _showNotificationsDialog(context),
            tooltip: 'Notifications',
          ),
          PopupMenuButton<String>(
            tooltip: 'Admin Options',
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
            onSelected: (val) {
              if (val == 'logout') {
                FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 16, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Logout', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.015),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<int>(_currentIndex),
          child: pages[_currentIndex],
        ),
      ),
      bottomNavigationBar: _buildMobileBottomNav(),
    );
  }

  // ─── Mobile Bottom Navigation (Ergonomic 5-Item Navigation) ───────────────

  Widget _buildMobileBottomNav() {
    // Indices in bottom bar:
    // 0: Dashboard (Index 0)
    // 1: Flats (Index 1)
    // 2: Accounts (Index 2)
    // 3: Bills (Index 5)
    // 4: More / Menu (opens drawer or represents remaining tabs 3, 4, 6, 7)
    final isSecondaryTabActive = [3, 4, 6, 7].contains(_currentIndex);
    final secondaryLabel = isSecondaryTabActive ? _getTabShortLabel(_currentIndex) : 'More';

    return SafeArea(
      child: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildMobileNavItem(0, 'Dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded, targetIndex: 0),
            _buildMobileNavItem(1, 'Flats', Icons.apartment_outlined, Icons.apartment_rounded, targetIndex: 1),
            _buildMobileNavItem(2, 'Accounts', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, targetIndex: 2),
            _buildMobileNavItem(5, 'Bills', Icons.receipt_long_outlined, Icons.receipt_long_rounded, targetIndex: 5),
            Builder(
              builder: (ctx) => _buildMobileNavActionItem(
                label: secondaryLabel,
                icon: isSecondaryTabActive ? _getTabIcon(_currentIndex) : Icons.grid_view_rounded,
                isActive: isSecondaryTabActive,
                onTap: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTabShortLabel(int index) {
    switch (index) {
      case 3:
        return 'Notices';
      case 4:
        return 'Helpdesk';
      case 6:
        return 'Visitors';
      case 7:
        return 'Amenities';
      default:
        return 'More';
    }
  }

  IconData _getTabIcon(int index) {
    switch (index) {
      case 3:
        return Icons.campaign_rounded;
      case 4:
        return Icons.support_agent_rounded;
      case 6:
        return Icons.badge_rounded;
      case 7:
        return Icons.event_available_rounded;
      default:
        return Icons.grid_view_rounded;
    }
  }

  Widget _buildMobileNavItem(
    int matchIndex,
    String label,
    IconData icon,
    IconData activeIcon, {
    required int targetIndex,
  }) {
    final isSelected = _currentIndex == matchIndex;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label tab',
      child: InkWell(
        onTap: () => setState(() => _currentIndex = targetIndex),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: const BoxConstraints(minHeight: 48, minWidth: 58),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                size: 20,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileNavActionItem({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isActive,
      label: '$label menu',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: const BoxConstraints(minHeight: 48, minWidth: 58),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? AppColors.primaryDark : AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reusable Admin Notification Bell & Badge ──────────────────────────────

class _AdminNotificationBadge extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const _AdminNotificationBadge({
    required this.onPressed,
    this.tooltip = 'Admin Notifications',
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('targetRole', isEqualTo: 'ADMIN')
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        final count = (snap.data?.docs ?? []).where((d) {
          final data = d.data() as Map<String, dynamic>?;
          return data?['isRead'] != true;
        }).length;

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary),
              tooltip: tooltip,
              onPressed: onPressed,
            ),
            if (count > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

