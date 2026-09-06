import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/pdf_iframe.dart';
import 'tabs/manage_society_tab.dart';
import 'tabs/accounts_tab.dart';
import 'tabs/generate_maintenance_tab.dart';
import 'tabs/verify_payments_tab.dart';
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

  void _showNotificationsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.notifications, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Admin Notifications'),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 420,
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
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = (snap.data?.docs ?? []).toList();
              // Sort in memory by createdAt descending to avoid composite index requirement
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
                  child: Text(
                    'No new notifications.',
                    style: TextStyle(color: Colors.grey),
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
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: isVehicleReq
                          ? Colors.orange.shade100
                          : Colors.deepPurple.shade100,
                      child: Icon(
                        isVehicleReq
                            ? Icons.directions_car
                            : Icons.info_outline,
                        color: isVehicleReq
                            ? Colors.orange.shade900
                            : Colors.deepPurple,
                      ),
                    ),
                    title: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(msg, style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          isVehicleReq
                              ? 'Tap to review & approve request'
                              : 'Tap to view in dashboard',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.deepPurple.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 18, color: Colors.grey),
                          onPressed: () => docs[i].reference.delete(),
                          tooltip: 'Dismiss',
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
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
        _currentIndex = 0; // Manage Society Tab
      });
      _showVehicleReviewDialog(notif, notifDocRef);
    } else if (type == 'COMPLAINT' ||
        title.contains('complaint') ||
        message.contains('complaint')) {
      setState(() => _currentIndex = 3); // Manage Complaints Tab
    } else if (type == 'PAYMENT' ||
        title.contains('payment') ||
        message.contains('payment')) {
      setState(() => _currentIndex = 5); // Verify Payments Tab
    } else if (type == 'MAINTENANCE' ||
        title.contains('maintenance') ||
        message.contains('maintenance')) {
      setState(() => _currentIndex = 4); // Generate Maintenance Tab
    } else if (type == 'ANNOUNCEMENT' ||
        title.contains('announcement') ||
        message.contains('announcement')) {
      setState(() => _currentIndex = 2); // Manage Announcements Tab
    } else if (type == 'ACCOUNT' ||
        title.contains('account') ||
        title.contains('expense') ||
        title.contains('income')) {
      setState(() => _currentIndex = 1); // Accounts Tab
    } else if (notif['flatNumber'] != null) {
      setState(() {
        _selectedFlatQuery = notif['flatNumber']?.toString();
        _currentIndex = 0;
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
          width: 480,
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
          width: 600,
          height: 480,
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      ManageSocietyTab(
        key: ValueKey(_selectedFlatQuery ?? 'society_default'),
        initialSearchQuery: _selectedFlatQuery,
      ),
      const AccountsTab(),
      const ManageAnnouncementsTab(),
      const ManageComplaintsTab(),
      const GenerateMaintenanceTab(),
      const VerifyPaymentsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.deepPurple,
        actions: [
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
                    icon: const Icon(Icons.notifications, color: Colors.white),
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
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                            minWidth: 16, minHeight: 16),
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
          TextButton.icon(
            icon: const Icon(Icons.logout, color: Colors.white),
            label: const Text('Log out', style: TextStyle(color: Colors.white)),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.deepPurple,
        type: BottomNavigationBarType.fixed,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.apartment), label: 'Flats'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance), label: 'Accounts'),
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'Notices'),
          BottomNavigationBarItem(
              icon: Icon(Icons.support_agent), label: 'Helpdesk'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'Bills'),
          BottomNavigationBarItem(
              icon: Icon(Icons.fact_check), label: 'Payments'),
        ],
      ),
    );
  }
}

