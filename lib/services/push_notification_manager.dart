import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import '../widgets/push_notification_banner.dart';
import '../utils/flat_utils.dart';
import 'notification_service.dart';
import 'visitor_pass_service.dart';

// ============================================================================
// GLOBAL PUSH NOTIFICATION MANAGER & OS BACKGROUND HOOD SYSTEM
// ============================================================================
// This singleton service manages real-time push notification delivery across all
// actor roles (Resident, Admin, Guard) when the app is active, minimized, or in background.
//
// Key Responsibilities:
// 1. Android OS System Notification Hood Delivery:
//    - Posts native system notifications via [FlutterLocalNotificationsPlugin] into the
//      device status bar, lock screen, and notification shade drawer with sound & vibration.
//    - Ensures delivery occurs regardless of whether app is in foreground or background.
//
// 2. Firebase Cloud Messaging (FCM) Integration:
//    - Obtains device FCM tokens and links them to user profiles in Firestore.
//    - Runs top-level background isolate handlers for OS notification delivery when minimized.
//
// 3. Real-Time Firestore Synchronization:
//    - Listens to the `notifications` collection and delivers any unread targeted notices.
//    - Prevents accidental event drops from clock drift or lifecycle pauses.
//
// 4. App Lifecycle Tracking & Deep-Link Tap Routing:
//    - Routes notification clicks from the OS tray directly to the relevant modal/section.
// ============================================================================

/// Safely transforms a dynamic data map so that any non-JSON primitive
/// (such as Cloud Firestore [Timestamp] or Dart [DateTime]) is converted to an ISO-8601 string,
/// preventing [Converting object to an encodable object failed] runtime exceptions in [jsonEncode].
Map<String, dynamic> _sanitizeForJson(Map<String, dynamic> map) {
  final clean = <String, dynamic>{};
  map.forEach((key, value) {
    if (value is Timestamp) {
      clean[key] = value.toDate().toIso8601String();
    } else if (value is DateTime) {
      clean[key] = value.toIso8601String();
    } else if (value is Map) {
      clean[key] = _sanitizeForJson(Map<String, dynamic>.from(value));
    } else if (value is List) {
      clean[key] = value.map((item) {
        if (item is Timestamp) return item.toDate().toIso8601String();
        if (item is DateTime) return item.toIso8601String();
        if (item is Map) return _sanitizeForJson(Map<String, dynamic>.from(item));
        return item;
      }).toList();
    } else if (value is String || value is num || value is bool || value == null) {
      clean[key] = value;
    } else {
      clean[key] = value.toString();
    }
  });
  return clean;
}

/// Top-level background message handler for Firebase Cloud Messaging (FCM).
/// This function runs in an isolated background Dart VM when a message arrives while
/// the application is minimized or suspended by Android OS.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Initialize Firebase in the background isolate
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    final data = message.data;
    final notification = message.notification;
    final title = notification?.title ?? data['title']?.toString() ?? 'Society Notification';
    final body = notification?.body ?? data['message']?.toString() ?? '';
    final id = data['id']?.toString() ?? message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final type = data['type']?.toString() ?? 'GENERAL';
    final flatNumber = data['flatNumber']?.toString();

    final FlutterLocalNotificationsPlugin localNotif = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings);
    await localNotif.initialize(settings: initSettings);

    final int notifId = id.hashCode & 0x7FFFFFFF;
    final bool isEmergency = type == 'EMERGENCY' || type == 'SOS';
    final bool isVisitorApproval = type == 'VISITOR_CHECK_IN' &&
        (data['approvalStatus'] == 'PENDING' || data['isWalkIn'] == 'true' || data['isWalkIn'] == true);

    final String channelId = isEmergency
        ? 'society_emergency_channel'
        : (isVisitorApproval ? 'society_visitor_ring_channel' : 'society_general_channel');

    final String channelName = isEmergency
        ? 'Society Emergency Alerts'
        : (isVisitorApproval ? 'Visitor Doorbell & Gate Approvals' : 'Society Notifications');

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: isEmergency
          ? 'Critical emergency SOS alerts'
          : (isVisitorApproval
              ? 'Urgent visitor gate clearance requests with custom doorbell ringtone'
              : 'Important society announcements, bills, visitor and parcel alerts'),
      importance: (isEmergency || isVisitorApproval) ? Importance.max : Importance.high,
      priority: (isEmergency || isVisitorApproval) ? Priority.max : Priority.high,
      ticker: title,
      color: const Color(0xFF0F766E),
      visibility: NotificationVisibility.public,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      sound: isVisitorApproval ? const RawResourceAndroidNotificationSound('cell_phone_ring_std') : null,
      audioAttributesUsage: isVisitorApproval ? AudioAttributesUsage.notificationRingtone : AudioAttributesUsage.notification,
      channelShowBadge: true,
      fullScreenIntent: isEmergency || isVisitorApproval,
      category: isEmergency
          ? AndroidNotificationCategory.alarm
          : (isVisitorApproval ? AndroidNotificationCategory.call : AndroidNotificationCategory.message),
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: flatNumber != null ? 'Flat $flatNumber' : 'Society Update',
      ),
    );

    // Sanitize data payload to ensure no Firestore Timestamps crash jsonEncode
    final sanitizedData = _sanitizeForJson(data);

    await localNotif.show(
      id: notifId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: androidDetails),
      payload: jsonEncode({
        'id': id,
        'title': title,
        'message': body,
        'type': type,
        'flatNumber': flatNumber,
        'extraData': sanitizedData,
      }),
    );
  } catch (e) {
    debugPrint('[FCM Background Handler] Error showing system notification: $e');
  }
}

/// Global Manager for real-time in-app push notifications and OS system notifications.
class PushNotificationManager with WidgetsBindingObserver {
  PushNotificationManager._() {
    // Register lifecycle observer to monitor foreground/background transitions
    WidgetsBinding.instance.addObserver(this);
  }

  static final PushNotificationManager instance = PushNotificationManager._();

  /// Global navigator key allowing system notification tap callbacks to access [BuildContext].
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isSystemNotificationsInitialized = false;
  PushNotificationPayload? _pendingLaunchPayload;

  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  final Set<String> _seenNotificationIds = {};

  // Active push payload notifier consumed by PushNotificationOverlay
  final ValueNotifier<PushNotificationPayload?> activeNotification = ValueNotifier(null);
  Timer? _dismissTimer;

  // Cached user profile metadata for role routing
  String? _currentUserId;
  String? _currentUserRole;
  String? _currentUserFlat;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    debugPrint('[PushNotificationManager] App lifecycle state transitioned to: $state');
  }

  /// Initializes native OS system notifications (notification hood, status bar, sound, channels, FCM).
  Future<void> initializeSystemNotifications() async {
    if (_isSystemNotificationsInitialized) return;

    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
      );

      // Initialize the local notifications plugin with Android settings and response callback
      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payloadStr = response.payload;
          if (payloadStr != null && payloadStr.isNotEmpty) {
            try {
              final map = jsonDecode(payloadStr) as Map<String, dynamic>;
              final payload = PushNotificationPayload(
                id: map['id']?.toString() ?? '',
                title: map['title']?.toString() ?? 'Society Notification',
                message: map['message']?.toString() ?? '',
                type: map['type']?.toString() ?? 'GENERAL',
                flatNumber: map['flatNumber']?.toString(),
                extraData: map['extraData'] is Map ? Map<String, dynamic>.from(map['extraData']) : {},
              );

              final ctx = navigatorKey.currentContext;
              if (ctx != null && ctx.mounted) {
                handleBannerTap(ctx, payload);
              } else {
                _pendingLaunchPayload = payload;
              }
            } catch (e) {
              debugPrint('[PushNotificationManager] Error handling system notification response: $e');
            }
          }
        },
      );

      // Request notification permissions for Android 13+
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      // Create high importance notification channels
      const AndroidNotificationChannel generalChannel = AndroidNotificationChannel(
        'society_general_channel',
        'Society Notifications',
        description: 'Important society announcements, bills, visitor and parcel alerts',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      const AndroidNotificationChannel emergencyChannel = AndroidNotificationChannel(
        'society_emergency_channel',
        'Society Emergency Alerts',
        description: 'Critical emergency and security SOS alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );

      // Dedicated channel for walk-in visitor clearance with custom doorbell ringtone
      const AndroidNotificationChannel visitorRingChannel = AndroidNotificationChannel(
        'society_visitor_ring_channel',
        'Visitor Doorbell & Gate Approvals',
        description: 'Urgent visitor gate clearance requests with custom doorbell ringtone',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('cell_phone_ring_std'),
        enableVibration: true,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      );

      await androidPlugin?.createNotificationChannel(generalChannel);
      await androidPlugin?.createNotificationChannel(emergencyChannel);
      await androidPlugin?.createNotificationChannel(visitorRingChannel);

      // Initialize Firebase Cloud Messaging permissions and stream listeners
      try {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        // Foreground/background FCM message listener
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final data = message.data;
          final notification = message.notification;
          final docId = data['id']?.toString() ?? message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
          
          if (!_seenNotificationIds.contains(docId)) {
            _seenNotificationIds.add(docId);
            final payload = PushNotificationPayload(
              id: docId,
              title: notification?.title ?? data['title']?.toString() ?? 'Society Notification',
              message: notification?.body ?? data['message']?.toString() ?? '',
              type: data['type']?.toString() ?? 'GENERAL',
              flatNumber: data['flatNumber']?.toString(),
              extraData: data,
            );
            _deliverPayload(payload);
          }
        });

        // App opened from background by tapping FCM notification
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          final data = message.data;
          final payload = PushNotificationPayload(
            id: data['id']?.toString() ?? message.messageId ?? '',
            title: data['title']?.toString() ?? 'Society Notification',
            message: data['message']?.toString() ?? '',
            type: data['type']?.toString() ?? 'GENERAL',
            flatNumber: data['flatNumber']?.toString(),
            extraData: data,
          );
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            handleBannerTap(ctx, payload);
          } else {
            _pendingLaunchPayload = payload;
          }
        });

        // Cold launch from terminated state via FCM notification tap
        final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null) {
          final data = initialMessage.data;
          _pendingLaunchPayload = PushNotificationPayload(
            id: data['id']?.toString() ?? initialMessage.messageId ?? '',
            title: data['title']?.toString() ?? 'Society Notification',
            message: data['message']?.toString() ?? '',
            type: data['type']?.toString() ?? 'GENERAL',
            flatNumber: data['flatNumber']?.toString(),
            extraData: data,
          );
        }
      } catch (fcmError) {
        debugPrint('[PushNotificationManager] FirebaseMessaging setup note: $fcmError');
      }

      _isSystemNotificationsInitialized = true;
      debugPrint('[PushNotificationManager] Native system notifications initialized successfully');
    } catch (e) {
      debugPrint('[PushNotificationManager] System notification initialization note: $e');
    }
  }

  /// Starts listening for real-time notifications for the given user profile.
  void startListening({
    required User user,
    String? role,
    String? flatNumber,
  }) {
    final normalizedRole = (role ?? 'RESIDENT').toUpperCase();
    final normalizedFlat = flatNumber != null ? FlatUtils.normalize(flatNumber) : null;

    // Avoid redundant listener rebuilds if the user identity has not changed
    if (_subscription != null &&
        _currentUserId == user.uid &&
        _currentUserRole == normalizedRole &&
        _currentUserFlat == normalizedFlat) {
      return;
    }

    // Cancel any previous subscription before binding fresh user context
    stopListening();

    _currentUserId = user.uid;
    _currentUserRole = normalizedRole;
    _currentUserFlat = normalizedFlat;

    debugPrint('[PushNotificationManager] Starting listener for UID: ${user.uid}, Role: $_currentUserRole, Flat: $_currentUserFlat');

    // Register FCM Device Token with User Profile in Firestore
    _syncFcmDeviceToken(user.uid);

    // Request notification permission again if not yet granted on Android 13+
    _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Subscribe to Firestore notifications collection
    _subscription = FirebaseFirestore.instance
        .collection('notifications')
        .snapshots()
        .listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          // Process newly added or modified documents
          if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
            final doc = change.doc;
            final docId = doc.id;
            final data = doc.data();
            if (data == null) continue;

            // Check if already processed in this session
            if (_seenNotificationIds.contains(docId)) continue;

            // If notification is already marked as read, skip it
            if (data['isRead'] == true) {
              _seenNotificationIds.add(docId);
              continue;
            }

            // Verify if this notification is targeted to the logged-in user
            if (_isTargetedToCurrentUser(data, user)) {
              _seenNotificationIds.add(docId);
              _triggerPushNotification(docId, data);
            }
          }
        }
      },
      onError: (e) {
        debugPrint('[PushNotificationManager] Stream error: $e');
      },
    );
  }

  /// Syncs the device FCM token to the user document in Firestore.
  /// Also sets up an active onTokenRefresh listener to update Firestore automatically
  /// if the Android operating system or Firebase rotates the device registration token.
  Future<void> _syncFcmDeviceToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': token,
          'fcmTokens': FieldValue.arrayUnion([token]),
          'devicePlatform': 'android',
          'lastTokenSync': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[PushNotificationManager] FCM Token synced for $uid: ${token.substring(0, 10)}...');
      }

      // Automatically sync whenever Firebase Cloud Messaging rotates the device token
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        if (newToken.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(uid).set({
            'fcmToken': newToken,
            'fcmTokens': FieldValue.arrayUnion([newToken]),
            'devicePlatform': 'android',
            'lastTokenSync': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).catchError((_) {});
          debugPrint('[PushNotificationManager] Refreshed FCM Token auto-synced for $uid');
        }
      });
    } catch (e) {
      debugPrint('[PushNotificationManager] Token sync note: $e');
    }
  }

  /// Evaluates whether a notification document matches the current logged-in user.
  bool _isTargetedToCurrentUser(Map<String, dynamic> data, User user) {
    final targetRole = (data['targetRole'] ?? '').toString().toUpperCase();

    // 1. Emergency broadcast to ALL
    if (targetRole == 'ALL') return true;

    // 2. Admin targeting
    if (_currentUserRole == 'ADMIN') {
      if (targetRole == 'ADMIN') return true;
    }

    // 3. Security Guard targeting
    if (_currentUserRole == 'GUARD') {
      if (targetRole == 'GUARD') return true;
    }

    // 4. Resident targeting
    if (_currentUserRole == 'RESIDENT' || _currentUserRole == null) {
      if (targetRole == 'ADMIN' || targetRole == 'GUARD') return false;

      // Check UID match
      final targetUid = (data['targetUid'] ?? '').toString();
      if (targetUid.isNotEmpty && targetUid == user.uid) return true;

      // Check targetUids array match
      final targetUids = (data['targetUids'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      if (targetUids.contains(user.uid) ||
          (user.email != null && targetUids.contains(user.email!.toLowerCase())) ||
          (user.email != null && targetUids.contains(user.email!.split('@').first.toUpperCase()))) {
        return true;
      }

      // Check flat number match
      if (_currentUserFlat != null && _currentUserFlat!.isNotEmpty) {
        final flatInDoc = FlatUtils.normalize((data['flatNumber'] ?? '').toString());
        if (flatInDoc == _currentUserFlat) return true;
        final lookupKeys = FlatUtils.getLookupKeys(_currentUserFlat);
        if (targetUids.any((u) => lookupKeys.contains(u))) return true;
      }
    }

    return false;
  }

  /// Triggers haptic feedback and dispatches both in-app heads-up banner and native OS system notification.
  void _triggerPushNotification(String docId, Map<String, dynamic> data) {
    final title = (data['title'] ?? 'New Notification').toString();
    final message = (data['message'] ?? '').toString();
    final type = (data['type'] ?? 'GENERAL').toString();
    final flatNumber = data['flatNumber']?.toString();

    final payload = PushNotificationPayload(
      id: docId,
      title: title,
      message: message,
      type: type,
      flatNumber: flatNumber,
      extraData: data,
    );

    _deliverPayload(payload);
  }

  /// Delivers notification payload to native Android OS notification hood and in-app banner.
  void _deliverPayload(PushNotificationPayload payload) {
    // 1. Post native Android OS system notification into notification hood / status bar
    _showSystemNotification(payload);

    // 2. If app is in foreground, trigger haptic feedback and show in-app banner
    if (_lifecycleState == AppLifecycleState.resumed) {
      if (payload.isEmergency) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }

      activeNotification.value = payload;

      // Auto-dismiss in-app banner after 6 seconds unless it's an emergency or visitor approval request
      _dismissTimer?.cancel();
      if (!payload.isEmergency && !payload.isVisitorApprovalRequest) {
        _dismissTimer = Timer(const Duration(seconds: 6), () {
          if (activeNotification.value?.id == payload.id) {
            activeNotification.value = null;
          }
        });
      }

      // If this is an urgent visitor approval request and the resident is actively using the app,
      // directly pop up the approval modal on-screen with custom ringtone audio
      if (payload.isVisitorApprovalRequest) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          onIncomingVisitorApproval?.call(ctx, payload);
        }
      }
    }
  }

  /// Dispatches native Android OS system notification into the device status bar / notification hood.
  Future<void> _showSystemNotification(PushNotificationPayload payload) async {
    try {
      final int notifId = payload.id.hashCode & 0x7FFFFFFF;
      final bool isVisitorApproval = payload.isVisitorApprovalRequest;

      final String channelId = payload.isEmergency
          ? 'society_emergency_channel'
          : (isVisitorApproval ? 'society_visitor_ring_channel' : 'society_general_channel');

      final String channelName = payload.isEmergency
          ? 'Society Emergency Alerts'
          : (isVisitorApproval ? 'Visitor Doorbell & Gate Approvals' : 'Society Notifications');

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: payload.isEmergency
            ? 'Critical emergency SOS alerts'
            : (isVisitorApproval
                ? 'Urgent visitor gate clearance requests with custom doorbell ringtone'
                : 'Important society announcements, bills, visitor and parcel alerts'),
        importance: (payload.isEmergency || isVisitorApproval) ? Importance.max : Importance.high,
        priority: (payload.isEmergency || isVisitorApproval) ? Priority.max : Priority.high,
        ticker: payload.title,
        color: const Color(0xFF0F766E), // Teal theme primary
        visibility: NotificationVisibility.public,
        enableLights: true,
        enableVibration: true,
        playSound: true,
        sound: isVisitorApproval ? const RawResourceAndroidNotificationSound('cell_phone_ring_std') : null,
        audioAttributesUsage: isVisitorApproval ? AudioAttributesUsage.notificationRingtone : AudioAttributesUsage.notification,
        channelShowBadge: true,
        fullScreenIntent: payload.isEmergency || isVisitorApproval,
        category: payload.isEmergency
            ? AndroidNotificationCategory.alarm
            : (isVisitorApproval ? AndroidNotificationCategory.call : AndroidNotificationCategory.message),
        styleInformation: BigTextStyleInformation(
          payload.message,
          contentTitle: payload.title,
          summaryText: payload.flatNumber != null ? 'Flat ${payload.flatNumber}' : 'Society Update',
        ),
      );

      final NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

      // Sanitize payload data to ensure Firestore Timestamps or DateTimes do not crash jsonEncode
      final sanitizedExtraData = _sanitizeForJson(payload.extraData);

      // Post native notification to Android status bar / notification hood
      await _localNotifications.show(
        id: notifId,
        title: payload.title,
        body: payload.message,
        notificationDetails: platformDetails,
        payload: jsonEncode({
          'id': payload.id,
          'title': payload.title,
          'message': payload.message,
          'type': payload.type,
          'flatNumber': payload.flatNumber,
          'extraData': sanitizedExtraData,
        }),
      );
      debugPrint('[PushNotificationManager] Successfully posted system notification: $notifId - ${payload.title}');
    } catch (e) {
      debugPrint('[PushNotificationManager] System notification display error: $e');
    }
  }

  /// Dismisses the currently displayed push banner.
  void dismissCurrent() {
    _dismissTimer?.cancel();
    activeNotification.value = null;
  }

  /// Approves a visitor's gate entry directly from the push banner.
  Future<void> handleApproveVisitor(PushNotificationPayload payload) async {
    final visitorDocId = payload.extraData['visitorDocId']?.toString();
    final flatNumber = payload.flatNumber ?? payload.extraData['flatNumber']?.toString() ?? '';
    final visitorName = payload.extraData['visitorName']?.toString() ?? 'Guest';

    dismissCurrent();

    try {
      await VisitorPassService.approveVisitorEntry(
        visitorDocId: visitorDocId,
        flatNumber: flatNumber,
        visitorName: visitorName,
        notifDocId: payload.id,
      );
    } catch (e) {
      debugPrint('[PushNotificationManager] Error approving visitor: $e');
    }
  }

  /// Denies a visitor's gate entry directly from the push banner.
  Future<void> handleDenyVisitor(PushNotificationPayload payload) async {
    final visitorDocId = payload.extraData['visitorDocId']?.toString();
    final flatNumber = payload.flatNumber ?? payload.extraData['flatNumber']?.toString() ?? '';
    final visitorName = payload.extraData['visitorName']?.toString() ?? 'Guest';

    dismissCurrent();

    try {
      await VisitorPassService.denyVisitorEntry(
        visitorDocId: visitorDocId,
        flatNumber: flatNumber,
        visitorName: visitorName,
        notifDocId: payload.id,
      );
    } catch (e) {
      debugPrint('[PushNotificationManager] Error denying visitor: $e');
    }
  }

  NotificationClickHandler? _onNotificationClick;

  /// Callback type for handling user taps on a push notification (banner or system tray).
  /// Receives the active [BuildContext] and the [PushNotificationPayload].
  NotificationClickHandler? get onNotificationClick => _onNotificationClick;

  set onNotificationClick(NotificationClickHandler? handler) {
    _onNotificationClick = handler;
    // If a system notification was tapped before the dashboard registered its click handler, execute it now
    if (handler != null && _pendingLaunchPayload != null) {
      final payload = _pendingLaunchPayload!;
      _pendingLaunchPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          handleBannerTap(ctx, payload);
        }
      });
    }
  }

  /// Callback triggered automatically when an incoming walk-in visitor approval request arrives while app is in foreground.
  /// Allows the resident dashboard to directly present the full clearance modal with ringtone audio.
  NotificationClickHandler? onIncomingVisitorApproval;

  /// Handles user tapping the banner body or native OS system notification.
  /// 1. Marks the notification as read in Firestore.
  /// 2. Dismisses the heads-up banner from screen.
  /// 3. Executes [onNotificationClick] to route the user directly to the relevant modal/section.
  Future<void> handleBannerTap(BuildContext context, PushNotificationPayload payload) async {
    // Mark as read in Firestore
    await NotificationService.markAsRead(payload.id);

    // Dismiss floating banner
    dismissCurrent();

    // Use navigatorKey.currentContext if available to ensure the context has a valid Navigator
    final targetContext = navigatorKey.currentContext ?? context;

    // Trigger registered dashboard section / modal handler
    if (targetContext.mounted) {
      onNotificationClick?.call(targetContext, payload);
    }
  }

  /// Stops listening and cleans up active subscriptions.
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _currentUserId = null;
    _currentUserRole = null;
    _currentUserFlat = null;
    _dismissTimer?.cancel();
    activeNotification.value = null;
    onIncomingVisitorApproval = null;
  }
}

/// Signature for notification click handler callbacks across dashboard roles.
typedef NotificationClickHandler = void Function(BuildContext context, PushNotificationPayload payload);

/// Global In-App Push Notification Overlay that wraps the app tree.
class PushNotificationOverlay extends StatelessWidget {
  final Widget child;

  const PushNotificationOverlay({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        // Floating Heads-Up Banner at the top of the screen
        Positioned(
          top: MediaQuery.of(context).padding.top + 8.0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<PushNotificationPayload?>(
            valueListenable: PushNotificationManager.instance.activeNotification,
            builder: (context, payload, _) {
              if (payload == null) return const SizedBox.shrink();

              return PushNotificationBanner(
                key: ValueKey(payload.id),
                payload: payload,
                onDismiss: () => PushNotificationManager.instance.dismissCurrent(),
                onTap: () => PushNotificationManager.instance.handleBannerTap(context, payload),
                onApprove: payload.isVisitorApprovalRequest
                    ? () => PushNotificationManager.instance.handleApproveVisitor(payload)
                    : null,
                onDeny: payload.isVisitorApprovalRequest
                    ? () => PushNotificationManager.instance.handleDenyVisitor(payload)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
