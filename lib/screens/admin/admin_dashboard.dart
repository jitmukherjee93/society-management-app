import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/pdf_iframe.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_decorations.dart';
import '../../widgets/app_dialog.dart';
import 'package:intl/intl.dart';
import '../../models/accounting_heads.dart';
import 'tabs/admin_home_dashboard_tab.dart';
import 'tabs/manage_society_tab.dart';
import 'tabs/accounts_tab.dart';
import 'tabs/generate_maintenance_tab.dart';
import 'tabs/manage_announcements_tab.dart';
import 'tabs/manage_complaints_tab.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
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
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  void _handleNotificationClick(
      Map<String, dynamic> notif, DocumentReference notifDocRef) {
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

      // Notify resident
      final targetUid = userData['uid']?.toString();
      if (targetUid != null && targetUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'targetUid': targetUid,
          'targetRole': 'RESIDENT',
          'type': 'VEHICLE_APPROVED',
          'title': '$vehicleType Number Approved',
          'message':
              'Your request to update $vehicleType number to $approvedReg has been approved by the Admin.',
          'createdAt': FieldValue.serverTimestamp(),
        });
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

      // Notify resident
      final targetUid = userData['uid']?.toString();
      if (targetUid != null && targetUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'targetUid': targetUid,
          'targetRole': 'RESIDENT',
          'type': 'VEHICLE_REJECTED',
          'title': '$vehicleType Number Rejected',
          'message': 'Your request to update $vehicleType number was rejected: $reason',
          'rejectionReason': reason,
          'createdAt': FieldValue.serverTimestamp(),
        });
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

  Widget _buildDesktopSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _isSidebarCollapsed ? 72 : 230,
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
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(horizontal: _isSidebarCollapsed ? 8 : 16),
            alignment: _isSidebarCollapsed ? Alignment.center : Alignment.centerLeft,
            child: _isSidebarCollapsed
                ? IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.admin_panel_settings_rounded, size: 20, color: AppColors.primary),
                    ),
                    tooltip: 'Expand sidebar',
                    onPressed: () {
                      setState(() {
                        _isSidebarCollapsed = false;
                      });
                    },
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded, size: 20, color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
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
                                letterSpacing: 0.3,
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
                        onPressed: () {
                          setState(() {
                            _isSidebarCollapsed = true;
                          });
                        },
                      ),
                    ],
                  ),
          ),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _buildSidebarNavItem(0, 'Dashboard', Icons.dashboard_outlined, Icons.dashboard_rounded),
                _buildSidebarNavItem(1, 'Flats & Units', Icons.apartment_outlined, Icons.apartment_rounded),
                _buildSidebarNavItem(2, 'Accounts', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded),
                _buildSidebarNavItem(3, 'Notices', Icons.campaign_outlined, Icons.campaign_rounded),
                _buildSidebarNavItem(4, 'Helpdesk', Icons.support_agent_outlined, Icons.support_agent_rounded),
                _buildSidebarNavItem(5, 'Maintenance', Icons.receipt_long_outlined, Icons.receipt_long_rounded),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Container(
            padding: EdgeInsets.all(_isSidebarCollapsed ? 12 : 16),
            child: _isSidebarCollapsed
                ? const Center(
                    child: Tooltip(
                      message: 'Ramkrishnapuram RWA\nVersion 1.2.0',
                      child: Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textMuted),
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
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
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
                        'Ramkrishnapuram RWA',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
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

  Widget _buildSidebarNavItem(int index, String title, IconData icon, IconData activeIcon) {
    final isSelected = _currentIndex == index;
    final content = InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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
              if (isSelected)
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
    );

    if (_isSidebarCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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

  Widget _buildDesktopHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 320,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardSurfaceSecondary,
              borderRadius: BorderRadius.circular(6),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
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
                borderRadius: BorderRadius.circular(6),
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
          const SizedBox(width: 10),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('targetRole', isEqualTo: 'ADMIN')
                .snapshots(),
            builder: (context, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary),
                    tooltip: 'Admin Notifications',
                    onPressed: () => _showNotificationsDialog(context),
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
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Admin Account',
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (value) {
              if (value == 'logout') {
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    ];

    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Row(
          children: [
            _buildDesktopSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildDesktopHeader(),
                  Expanded(
                    child: IndexedStack(
                      index: _currentIndex,
                      children: pages,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile / Tablet layout (< 900px)
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      appBar: AppBar(
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
                    isMobile ? 'Admin Portal' : 'Admin Management Portal',
                    style: TextStyle(fontSize: isMobile ? 15 : 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isMobile)
                    const Text(
                      'Ramkrishnapuram RWA',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
            isMobile
                ? Tooltip(
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
                  )
                : Container(
                    margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.warningSurface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.warningBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.warningDark),
                        const SizedBox(width: 6),
                        Text(
                          'Simulated Date: ${DateFormat('dd MMMM yyyy').format(AccountingConfig.currentDate)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.warningDark),
                        ),
                      ],
                    ),
                  ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('targetRole', isEqualTo: 'ADMIN')
                .snapshots(),
            builder: (context, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary),
                    tooltip: 'Notifications',
                    onPressed: () => _showNotificationsDialog(context),
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
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.error),
            tooltip: 'Logout',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border, width: 0.9)),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          height: 62,
          backgroundColor: Colors.white,
          indicatorColor: AppColors.primaryLight,
          onDestinationSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, size: 20),
              selectedIcon: Icon(Icons.dashboard_rounded, size: 20, color: AppColors.primary),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.apartment_outlined, size: 20),
              selectedIcon: Icon(Icons.apartment_rounded, size: 20, color: AppColors.primary),
              label: 'Flats',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined, size: 20),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded, size: 20, color: AppColors.primary),
              label: 'Accounts',
            ),
            NavigationDestination(
              icon: Icon(Icons.campaign_outlined, size: 20),
              selectedIcon: Icon(Icons.campaign_rounded, size: 20, color: AppColors.primary),
              label: 'Notices',
            ),
            NavigationDestination(
              icon: Icon(Icons.support_agent_outlined, size: 20),
              selectedIcon: Icon(Icons.support_agent_rounded, size: 20, color: AppColors.primary),
              label: 'Helpdesk',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined, size: 20),
              selectedIcon: Icon(Icons.receipt_long_rounded, size: 20, color: AppColors.primary),
              label: 'Bills',
            ),
          ],
        ),
      ),
    );
  }
}

