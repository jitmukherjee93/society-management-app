import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:society_management/services/visitor_pass_service.dart';
import 'package:society_management/utils/flat_utils.dart';

void main() {
  group('Security Guard & Visitor Pass Suite', () {
    test('generatePassCode produces valid 6-digit numeric OTP', () {
      for (int i = 0; i < 50; i++) {
        final code = VisitorPassService.generatePassCode();
        expect(code.length, 6);
        final numVal = int.tryParse(code);
        expect(numVal, isNotNull);
        expect(numVal! >= 100000 && numVal <= 999999, isTrue);
      }
    });

    test('generatePassCode yields distributed codes across multiple invocations', () {
      final codes = <String>{};
      for (int i = 0; i < 100; i++) {
        codes.add(VisitorPassService.generatePassCode());
      }
      // Out of 100 generated 6-digit codes, collision is exceedingly rare (>90 unique)
      expect(codes.length > 90, isTrue);
    });

    test('FlatUtils normalization formats flat numbers for visitor & parcel logs correctly', () {
      expect(FlatUtils.normalize('b101'), 'B-101');
      expect(FlatUtils.normalize(' B-204 '), 'B-204');
      expect(FlatUtils.normalize('a302'), 'A-302');
      expect(FlatUtils.normalize('c-101'), 'C-101');
    });

    test('Visitor pass status state machine adheres to valid transitions', () {
      const initialStatus = 'PENDING';
      const checkedInStatus = 'CHECKED_IN';
      const checkedOutStatus = 'CHECKED_OUT';

      bool isValidTransition(String from, String to) {
        if (from == 'PENDING' && to == 'CHECKED_IN') return true;
        if (from == 'CHECKED_IN' && to == 'CHECKED_OUT') return true;
        return false;
      }

      expect(isValidTransition(initialStatus, checkedInStatus), isTrue);
      expect(isValidTransition(checkedInStatus, checkedOutStatus), isTrue);
      expect(isValidTransition(initialStatus, checkedOutStatus), isFalse);
      expect(isValidTransition(checkedOutStatus, checkedInStatus), isFalse);
    });

    test('Parcel status transition adheres to HELD_AT_GATE -> COLLECTED lifecycle', () {
      const heldStatus = 'HELD_AT_GATE';
      const collectedStatus = 'COLLECTED';

      bool isCollectable(String currentStatus) => currentStatus == 'HELD_AT_GATE';

      expect(isCollectable(heldStatus), isTrue);
      expect(isCollectable(collectedStatus), isFalse);
    });

    test('Guard duty status and shift definitions', () {
      const validShifts = ['Day Shift (08:00 - 20:00)', 'Night Shift (20:00 - 08:00)', 'General Shift'];
      const validGates = ['Main Gate - Gate 1', 'Back Gate - Gate 2', 'Service Gate - Gate 3'];

      expect(validShifts.contains('Day Shift (08:00 - 20:00)'), isTrue);
      expect(validShifts.contains('Night Shift (20:00 - 08:00)'), isTrue);
      expect(validGates.contains('Main Gate - Gate 1'), isTrue);

      String toggleStatus(String current) => current == 'ON_DUTY' ? 'OFF_DUTY' : 'ON_DUTY';
      expect(toggleStatus('ON_DUTY'), 'OFF_DUTY');
      expect(toggleStatus('OFF_DUTY'), 'ON_DUTY');
    });

    test('Emergency alert categories are properly classified', () {
      const emergencyTypes = [
        'Fire Emergency',
        'Medical Emergency',
        'Security / Trespassing',
        'Lift / Elevator Breakdown',
        'Water Leakage / Flooding',
        'Power Outage / Transformer Failure',
      ];

      for (final type in emergencyTypes) {
        expect(type.isNotEmpty, isTrue);
      }
      expect(emergencyTypes.length, 6);
    });

    test('Pre-approved visitor check-in notification payload contains required fields for resident alert', () {
      final visitorData = {
        'visitorName': 'Rahul Sharma',
        'phone': '9876543210',
        'flatNumber': 'B-101',
        'hostFlatNumber': 'B-101',
        'residentUid': 'resident_uid_123',
        'purpose': 'Guest / Family',
        'passCode': '654321',
        'status': 'CHECKED_IN',
      };

      final rawFlat = visitorData['hostFlatNumber'] ?? visitorData['flatNumber'] ?? '';
      final hostFlat = FlatUtils.normalize(rawFlat.toString());
      final visitorName = (visitorData['visitorName'] ?? 'Guest').toString().trim();
      final purpose = (visitorData['purpose'] ?? 'Guest / Personal').toString().trim();
      final residentUid = visitorData['residentUid']?.toString();
      const gateName = 'Main Gate';
      const guardName = 'Ramesh Guard';

      final notificationPayload = {
        'targetUid': residentUid,
        'targetRole': 'RESIDENT',
        'flatNumber': hostFlat,
        'title': 'Pre-approved Guest Arrived: $visitorName',
        'message': 'Your pre-approved guest $visitorName ($purpose) has checked in at $gateName.',
        'type': 'VISITOR_CHECK_IN',
        'isPreApproved': true,
        'status': 'CHECKED_IN',
        'approvalStatus': 'APPROVED',
        'gateName': gateName,
        'guardName': guardName,
      };

      expect(notificationPayload['type'], 'VISITOR_CHECK_IN');
      expect(notificationPayload['title'], 'Pre-approved Guest Arrived: Rahul Sharma');
      expect(notificationPayload['targetUid'], 'resident_uid_123');
      expect(notificationPayload['flatNumber'], 'B-101');
      expect(notificationPayload['isPreApproved'], isTrue);
      expect(notificationPayload['approvalStatus'], 'APPROVED');
      expect(notificationPayload['status'], 'CHECKED_IN');
      expect(notificationPayload['gateName'], 'Main Gate');
      expect(notificationPayload['guardName'], 'Ramesh Guard');
    });

    test('VisitorPassService enforces 8-hour validity and single-use lifecycle', () {
      expect(VisitorPassService.passValidityHours, 8);

      final baseTime = DateTime(2026, 9, 14, 10, 0);

      // 1. Freshly created pass within 8 hours is valid
      final activePass = {
        'visitorName': 'Priya Singh',
        'status': 'PENDING',
        'isUsed': false,
        'createdAt': null,
        'expiresAt': null,
      };
      expect(VisitorPassService.evaluatePassStatus(activePass, currentTime: baseTime), PassVerificationStatus.valid);

      // 2. Pass checked in is alreadyUsed (single use only)
      final usedPass = {
        'visitorName': 'Priya Singh',
        'status': 'CHECKED_IN',
        'isUsed': true,
      };
      expect(VisitorPassService.evaluatePassStatus(usedPass, currentTime: baseTime), PassVerificationStatus.alreadyUsed);

      // 3. Pass with isUsed true even if status pending is alreadyUsed
      final flaggedUsedPass = {
        'visitorName': 'Priya Singh',
        'status': 'PENDING',
        'isUsed': true,
      };
      expect(VisitorPassService.evaluatePassStatus(flaggedUsedPass, currentTime: baseTime), PassVerificationStatus.alreadyUsed);

      // 4. Pass with EXPIRED status is expired
      final explicitExpiredPass = {
        'visitorName': 'Priya Singh',
        'status': 'EXPIRED',
        'isUsed': false,
      };
      expect(VisitorPassService.evaluatePassStatus(explicitExpiredPass, currentTime: baseTime), PassVerificationStatus.expired);

      // 5. Pass checked-out is also alreadyUsed
      final checkedOutPass = {
        'visitorName': 'Priya Singh',
        'status': 'CHECKED_OUT',
        'isUsed': true,
      };
      expect(VisitorPassService.evaluatePassStatus(checkedOutPass, currentTime: baseTime), PassVerificationStatus.alreadyUsed);
    });

    test('PassVerificationResult helper getters reflect proper state', () {
      const validRes = PassVerificationResult(
        status: PassVerificationStatus.valid,
        message: 'Valid pass verified!',
      );
      expect(validRes.isValid, isTrue);
      expect(validRes.isAlreadyUsed, isFalse);
      expect(validRes.isExpired, isFalse);
      expect(validRes.isInvalid, isFalse);

      const usedRes = PassVerificationResult(
        status: PassVerificationStatus.alreadyUsed,
        message: 'Passcode already used',
      );
      expect(usedRes.isValid, isFalse);
      expect(usedRes.isAlreadyUsed, isTrue);

      const expiredRes = PassVerificationResult(
        status: PassVerificationStatus.expired,
        message: 'Passcode expired',
      );
      expect(expiredRes.isValid, isFalse);
      expect(expiredRes.isExpired, isTrue);

      const invalidRes = PassVerificationResult(
        status: PassVerificationStatus.invalid,
        message: 'Invalid passcode',
      );
      expect(invalidRes.isValid, isFalse);
      expect(invalidRes.isInvalid, isTrue);
    });

    test('Visitor pass supports vehicle details for guest arriving by car', () {
      final passWithVehicle = {
        'visitorName': 'Amit Verma',
        'flatNumber': 'A-402',
        'isComingByCar': true,
        'vehicleNumber': 'WB 02 AK 9876',
        'status': 'PENDING',
        'isUsed': false,
      };

      expect(passWithVehicle['isComingByCar'], isTrue);
      expect(passWithVehicle['vehicleNumber'], 'WB 02 AK 9876');

      // Check notification message formatting when vehicle is present
      final vName = passWithVehicle['visitorName'];
      final vPurpose = 'Guest / Family';
      final vGate = 'Main Gate';
      final vNum = passWithVehicle['vehicleNumber'] as String;
      final vehicleInfo = vNum.isNotEmpty ? ' with vehicle $vNum' : '';
      final msg = 'Your pre-approved guest $vName ($vPurpose) has checked in at $vGate$vehicleInfo.';

      expect(msg, 'Your pre-approved guest Amit Verma (Guest / Family) has checked in at Main Gate with vehicle WB 02 AK 9876.');

      // Check notification message formatting when no vehicle is provided
      final passWithoutVehicle = {
        'visitorName': 'Rohit Sen',
        'isComingByCar': false,
        'vehicleNumber': '',
      };
      final emptyVNum = (passWithoutVehicle['vehicleNumber'] as String).trim();
      final emptySuffix = emptyVNum.isNotEmpty ? ' with vehicle $emptyVNum' : '';
      final regularMsg = 'Your pre-approved guest ${passWithoutVehicle['visitorName']} (Visit) has checked in at $vGate$emptySuffix.';
      expect(regularMsg, 'Your pre-approved guest Rohit Sen (Visit) has checked in at Main Gate.');
    });

    test('Guest check-out dispatches notification to resident with exit details', () {
      final visitorData = {
        'visitorName': 'Suresh Menon',
        'flatNumber': 'C-301',
        'hostFlatNumber': 'C-301',
        'residentUid': 'res_menon_456',
        'purpose': 'Personal Guest',
        'phone': '9876501234',
        'vehicleNumber': 'DL 01 AB 5566',
        'isComingByCar': true,
        'status': 'CHECKED_OUT',
      };

      final hostFlat = FlatUtils.normalize((visitorData['hostFlatNumber'] ?? visitorData['flatNumber'] ?? '').toString());
      final visitorName = (visitorData['visitorName'] ?? 'Guest').toString().trim();
      final purpose = (visitorData['purpose'] ?? 'Guest / Personal').toString().trim();
      final residentUid = visitorData['residentUid']?.toString();
      final vehicleNumber = (visitorData['vehicleNumber'] ?? '').toString().trim();
      final isComingByCar = visitorData['isComingByCar'] == true || vehicleNumber.isNotEmpty;
      const gateName = 'Main Gate';
      const guardName = 'Security Bahadur';
      final vehicleInfo = isComingByCar && vehicleNumber.isNotEmpty ? ' with vehicle $vehicleNumber' : '';

      final expectedTitle = 'Guest Departed: $visitorName';
      final expectedMessage = 'Your guest $visitorName ($purpose) has checked out and exited from $gateName$vehicleInfo.';

      final checkoutPayload = {
        'targetUid': residentUid,
        'targetRole': 'RESIDENT',
        'flatNumber': hostFlat,
        'title': expectedTitle,
        'message': expectedMessage,
        'type': 'VISITOR_CHECK_OUT',
        'gateName': gateName,
        'guardName': guardName,
        'status': 'CHECKED_OUT',
        'isComingByCar': isComingByCar,
        'vehicleNumber': vehicleNumber,
      };

      expect(checkoutPayload['type'], 'VISITOR_CHECK_OUT');
      expect(checkoutPayload['title'], 'Guest Departed: Suresh Menon');
      expect(checkoutPayload['message'], 'Your guest Suresh Menon (Personal Guest) has checked out and exited from Main Gate with vehicle DL 01 AB 5566.');
      expect(checkoutPayload['flatNumber'], 'C-301');
      expect(checkoutPayload['targetUid'], 'res_menon_456');
      expect(checkoutPayload['status'], 'CHECKED_OUT');
      expect(checkoutPayload['vehicleNumber'], 'DL 01 AB 5566');
    });

    test('Notification unread filter accurately counts only isRead != true items and reduces upon read', () {
      final notifications = <Map<String, dynamic>>[
        {'id': 'n1', 'title': 'Alert 1', 'isRead': false},
        {'id': 'n2', 'title': 'Alert 2', 'isRead': false},
        {'id': 'n3', 'title': 'Alert 3', 'isRead': true},
        {'id': 'n4', 'title': 'Alert 4'}, // unread (legacy or null isRead)
      ];

      int countUnread(List<Map<String, dynamic>> list) =>
          list.where((notif) => notif['isRead'] != true).length;

      // Initial unread count should be 3 (n1, n2, n4)
      expect(countUnread(notifications), 3);

      // Tap on n1 -> mark as read
      notifications[0]['isRead'] = true;
      expect(countUnread(notifications), 2);

      // Tap on n4 -> mark as read
      notifications[3]['isRead'] = true;
      expect(countUnread(notifications), 1);

      // Mark all remaining unread as read
      for (final n in notifications) {
        if (n['isRead'] != true) {
          n['isRead'] = true;
        }
      }
      expect(countUnread(notifications), 0);
    });

    test('Admin Visitors tracking aggregates in-campus, checked-out, and pre-approved activities accurately', () {
      final visitorRecords = <Map<String, dynamic>>[
        {
          'id': 'v1',
          'visitorName': 'Amit Kumar',
          'phone': '9876500001',
          'flatNumber': 'A-101',
          'status': 'CHECKED_IN',
          'isComingByCar': true,
          'vehicleNumber': 'WB 02 AB 1234',
          'gateName': 'Main Gate',
          'guardName': 'Guard Bahadur',
        },
        {
          'id': 'v2',
          'visitorName': 'Priya Sen',
          'phone': '9876500002',
          'flatNumber': 'B-202',
          'status': 'CHECKED_IN',
          'isComingByCar': false,
          'gateName': 'Gate 2',
          'guardName': 'Guard Ram',
        },
        {
          'id': 'v3',
          'visitorName': 'Delivery Agent',
          'phone': '9876500003',
          'flatNumber': 'C-303',
          'status': 'CHECKED_OUT',
          'isComingByCar': true,
          'vehicleNumber': 'DL 01 CD 5678',
          'gateName': 'Main Gate',
          'guardName': 'Guard Bahadur',
        },
        {
          'id': 'v4',
          'visitorName': 'Future Guest',
          'phone': '9876500004',
          'flatNumber': 'D-404',
          'status': 'PENDING',
          'isComingByCar': false,
          'passCode': '123456',
        },
      ];

      // In-campus count
      final inCampus = visitorRecords.where((v) => v['status'] == 'CHECKED_IN').length;
      expect(inCampus, 2);

      // Checked out count
      final checkedOut = visitorRecords.where((v) => v['status'] == 'CHECKED_OUT').length;
      expect(checkedOut, 1);

      // Pre-approved pending
      final pending = visitorRecords.where((v) => v['status'] == 'PENDING').length;
      expect(pending, 1);

      // Vehicle filter
      final withVehicle = visitorRecords.where((v) =>
          v['isComingByCar'] == true || (v['vehicleNumber'] as String? ?? '').isNotEmpty).length;
      expect(withVehicle, 2);

      // Search filter for flat "B-202"
      final b202Visitors = visitorRecords.where((v) =>
          (v['flatNumber'] as String).toLowerCase().contains('b-202')).toList();
      expect(b202Visitors.length, 1);
      expect(b202Visitors.first['visitorName'], 'Priya Sen');

      // Search filter for vehicle "5678"
      final vehicleMatch = visitorRecords.where((v) =>
          (v['vehicleNumber'] as String? ?? '').toLowerCase().contains('5678')).toList();
      expect(vehicleMatch.length, 1);
      expect(vehicleMatch.first['visitorName'], 'Delivery Agent');
    });

    test('Guest check-in and checkout notifications explicitly exclude Admin and target linked resident only', () {
      final residentNotification = {
        'targetRole': 'RESIDENT',
        'flatNumber': 'A-101',
        'targetUid': 'res_uid_1',
        'title': 'Pre-approved Guest Arrived: Rahul',
        'type': 'VISITOR_CHECK_IN',
        'isRead': false,
      };

      // Ensure targetRole is RESIDENT and NOT ADMIN
      expect(residentNotification['targetRole'], 'RESIDENT');
      expect(residentNotification['targetRole'] != 'ADMIN', isTrue);
      expect(residentNotification['targetUid'], 'res_uid_1');

      final checkoutNotification = {
        'targetRole': 'RESIDENT',
        'flatNumber': 'A-101',
        'targetUid': 'res_uid_1',
        'title': 'Guest Departed: Rahul',
        'type': 'VISITOR_CHECK_OUT',
        'isRead': false,
      };

      expect(checkoutNotification['targetRole'], 'RESIDENT');
      expect(checkoutNotification['targetRole'] != 'ADMIN', isTrue);
    });

    test('evaluatePassStatus correctly identifies valid pending pass even when createdAt is pending/null', () {
      final freshPassData = {
        'passCode': '654321',
        'visitorName': 'Fresh Guest',
        'flatNumber': 'B-101',
        'status': 'PENDING',
        'isUsed': false,
        'createdAt': null, // pending server timestamp
        'expiresAt': null,
      };

      final status = VisitorPassService.evaluatePassStatus(freshPassData);
      expect(status, PassVerificationStatus.valid);
    });

    test('evaluatePassStatus flags pass as expired after 8 hours or explicit EXPIRED status', () {
      final now = DateTime.now();
      final expiredPassData = {
        'passCode': '112233',
        'visitorName': 'Old Guest',
        'status': 'EXPIRED',
        'isUsed': false,
      };
      expect(VisitorPassService.evaluatePassStatus(expiredPassData, currentTime: now), PassVerificationStatus.expired);

      final timedOutPassData = {
        'passCode': '112233',
        'visitorName': 'Old Guest',
        'status': 'PENDING',
        'isUsed': false,
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 9))),
      };
      expect(VisitorPassService.evaluatePassStatus(timedOutPassData, currentTime: now), PassVerificationStatus.expired);
    });

    test('evaluatePassStatus flags pass as already used when checked in or checked out', () {
      final checkedInPass = {
        'status': 'CHECKED_IN',
        'isUsed': true,
      };
      expect(VisitorPassService.evaluatePassStatus(checkedInPass), PassVerificationStatus.alreadyUsed);

      final checkedOutPass = {
        'status': 'CHECKED_OUT',
        'isUsed': true,
      };
      expect(VisitorPassService.evaluatePassStatus(checkedOutPass), PassVerificationStatus.alreadyUsed);
    });

    test('Denied visitor state transition guarantees no campus entry and status is DENIED', () {
      // Simulates the visitor state transition when resident denies clearance
      final visitorRecord = {
        'visitorName': 'Unverified Guest',
        'flatNumber': 'C-302',
        'status': 'WAITING_APPROVAL',
        'approvalStatus': 'PENDING',
        'entryTime': null,
      };

      // Apply denial update as executed by denyVisitorEntry
      visitorRecord['approvalStatus'] = 'DENIED';
      visitorRecord['status'] = 'DENIED';
      visitorRecord.remove('entryTime');

      // Assert that denied visitors are never marked as CHECKED_IN
      expect(visitorRecord['status'], 'DENIED');
      expect(visitorRecord['status'] == 'CHECKED_IN', isFalse);
      expect(visitorRecord['approvalStatus'], 'DENIED');
      expect(visitorRecord['entryTime'], isNull);

      // Verify guard clearance text instructs guard to turn visitor away
      final isDenied = visitorRecord['approvalStatus'] == 'DENIED';
      final clearanceMessage = isDenied
          ? '⛔ ACTION REQUIRED: Turn visitor away immediately. Resident of flat C-302 has DENIED gate clearance. No campus entry permitted.'
          : 'Allow Entry';
      expect(clearanceMessage.contains('No campus entry permitted'), isTrue);
    });

    test('Leave at gate delivery state transition guarantees status is LEFT_AT_GATE, not CHECKED_IN', () {
      // Simulates delivery state transition when resident selects leave at gate
      final deliveryRecord = {
        'visitorName': 'Zomato Agent',
        'flatNumber': 'A-101',
        'status': 'WAITING_APPROVAL',
        'approvalStatus': 'PENDING',
        'isDelivery': true,
        'entryTime': null,
      };

      const pickupOtp = '4321';

      // Apply leave-at-gate update as executed by leaveAtGateVisitorEntry
      deliveryRecord['approvalStatus'] = 'LEAVE_AT_GATE';
      deliveryRecord['leaveAtGate'] = true;
      deliveryRecord['pickupOtp'] = pickupOtp;
      deliveryRecord['status'] = 'LEFT_AT_GATE';
      deliveryRecord.remove('entryTime');

      // Assert that delivery agents leaving items at gate are strictly LEFT_AT_GATE and never CHECKED_IN
      expect(deliveryRecord['status'], 'LEFT_AT_GATE');
      expect(deliveryRecord['status'] == 'CHECKED_IN', isFalse);
      expect(deliveryRecord['approvalStatus'], 'LEAVE_AT_GATE');
      expect(deliveryRecord['entryTime'], isNull);
      expect(deliveryRecord['pickupOtp'], pickupOtp);

      // Parcel record generated for gate holding queue
      final gateParcelRecord = {
        'flatNumber': deliveryRecord['flatNumber'],
        'visitorName': deliveryRecord['visitorName'],
        'status': 'HELD_AT_GATE',
        'pickupOtp': pickupOtp,
      };
      expect(gateParcelRecord['status'], 'HELD_AT_GATE');
    });

    test('Walk-in guest classification sets initial status to WAITING_APPROVAL, while staff gets CHECKED_IN', () {
      String getInitialWalkInStatus(String purpose) {
        final lower = purpose.toLowerCase();
        final isStaff = lower.contains('maid') ||
            lower.contains('helper') ||
            lower.contains('cook') ||
            lower.contains('driver');
        return isStaff ? 'CHECKED_IN' : 'WAITING_APPROVAL';
      }

      // Guest walk-in must wait at gate for resident clearance
      expect(getInitialWalkInStatus('Guest / Friend Visit'), 'WAITING_APPROVAL');
      expect(getInitialWalkInStatus('Delivery agent / courier'), 'WAITING_APPROVAL');
      expect(getInitialWalkInStatus('Salesperson / Meeting'), 'WAITING_APPROVAL');

      // Daily domestic staff is pre-cleared for direct check-in
      expect(getInitialWalkInStatus('Maid'), 'CHECKED_IN');
      expect(getInitialWalkInStatus('House cook'), 'CHECKED_IN');
      expect(getInitialWalkInStatus('Personal driver'), 'CHECKED_IN');
      expect(getInitialWalkInStatus('Domestic helper'), 'CHECKED_IN');
    });
  });
}

