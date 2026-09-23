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
/// Top-level background notification response handler for flutter_local_notifications.
/// Triggered when the user taps an interactive notification action button (e.g. Approve/Deny)
/// while the application is in the background or device is locked.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  PushNotificationManager.handleNotificationActionStatic(notificationResponse);
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
    await localNotif.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: notificationTapBackground,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final int notifId = id.hashCode & 0x7FFFFFFF;
    final bool isEmergency = type == 'EMERGENCY' || type == 'SOS';
    // Overstay alarm condition: flags visitors who have exceeded stay threshold
    final bool isOverstay = type == 'VISITOR_OVERSTAY' ||
        type.contains('OVERSTAY') ||
        title.toUpperCase().contains('OVERSTAY');
    final bool isVisitorApproval = type == 'VISITOR_CHECK_IN' &&
        (data['approvalStatus'] == 'PENDING' || data['isWalkIn'] == 'true' || data['isWalkIn'] == true);

    // Extract extraData and determine if visitor is a delivery or courier arrival
    final extraData = data['extraData'] is Map ? data['extraData'] as Map : data;
    final bool isDelivery = extraData['isDelivery'] == true ||
        extraData['isDelivery'] == 'true' ||
        (extraData['purpose']?.toString().toLowerCase().contains('delivery') ?? false) ||
        (extraData['purpose']?.toString().toLowerCase().contains('courier') ?? false) ||
        ((extraData['deliveryApp']?.toString() ?? '').isNotEmpty);

    final String channelId = isEmergency
        ? 'society_emergency_channel'
        : (isOverstay
            ? 'society_overstay_channel'
            : (isVisitorApproval ? 'society_visitor_ring_channel_v4' : 'society_general_channel'));

    final String channelName = isEmergency
        ? 'Society Emergency Alerts'
        : (isOverstay
            ? 'Visitor Overstay Alerts'
            : (isVisitorApproval ? 'Visitor Doorbell & Gate Approvals' : 'Society Notifications'));

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: isEmergency
          ? 'Critical emergency SOS alerts'
          : (isOverstay
              ? 'High-priority alarm alerts when visitors or delivery agents exceed allowed stay time'
              : (isVisitorApproval
                  ? 'Urgent visitor gate clearance requests with custom doorbell ringtone'
                  : 'Important society announcements, bills, visitor and parcel alerts')),
      importance: (isEmergency || isOverstay || isVisitorApproval) ? Importance.max : Importance.high,
      priority: (isEmergency || isOverstay || isVisitorApproval) ? Priority.max : Priority.high,
      autoCancel: true,
      ongoing: false,
      ticker: title,
      color: isOverstay ? const Color(0xFFDC2626) : const Color(0xFF0F766E),
      visibility: NotificationVisibility.public,
      enableLights: true,
      enableVibration: true,
      playSound: true,
      sound: isOverstay
          ? const RawResourceAndroidNotificationSound('clock_alarm')
          : (isVisitorApproval ? const RawResourceAndroidNotificationSound('cell_phone_ring_std') : null),
      audioAttributesUsage: isOverstay
          ? AudioAttributesUsage.alarm
          : (isVisitorApproval ? AudioAttributesUsage.notificationRingtone : AudioAttributesUsage.notification),
      channelShowBadge: true,
      fullScreenIntent: isEmergency || isOverstay || isVisitorApproval,
      category: (isEmergency || isOverstay)
          ? AndroidNotificationCategory.alarm
          : (isVisitorApproval ? AndroidNotificationCategory.call : AndroidNotificationCategory.message),
      // Interactive action buttons on the heads-up notification card: Approve, Leave at Gate, and Deny.
      // Setting showsUserInterface: true brings the app to the foreground so the resident can see the action or popout screen immediately.
      // Leave at Gate is strictly reserved for deliveries/couriers; omitted for Guests!
      actions: isVisitorApproval
          ? <AndroidNotificationAction>[
              const AndroidNotificationAction(
                'APPROVE_ACTION',
                'Approve',
                titleColor: Color(0xFF16A34A),
                showsUserInterface: false,
                cancelNotification: true,
              ),
              if (isDelivery)
                const AndroidNotificationAction(
                  'LEAVE_AT_GATE_ACTION',
                  'Leave at Gate',
                  titleColor: Color(0xFFD97706),
                  showsUserInterface: false,
                  cancelNotification: true,
                ),
              const AndroidNotificationAction(
                'DENY_ACTION',
                'Deny',
                titleColor: Color(0xFFDC2626),
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ]
          : null,
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: flatNumber != null ? 'Flat $flatNumber' : 'Society Update',
      ),
    );

    // If FCM generated an OS-level generic notification without buttons,
    // cancel it immediately so only our interactive action-button notification is visible
    if (notification != null && id.isNotEmpty) {
      try {
        await localNotif.cancel(id: 0, tag: id);
        await localNotif.cancel(id: notifId, tag: id);
      } catch (_) {}
    }

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
        'visitorDocId': data['visitorDocId']?.toString(),
        'visitorName': data['visitorName']?.toString(),
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
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  static final PushNotificationManager instance = PushNotificationManager._();

  /// Global navigator key allowing system notification tap callbacks to access [BuildContext].
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isSystemNotificationsInitialized = false;
  PushNotificationPayload? _pendingLaunchPayload;

  // Stores a visitor approval payload that arrived while the screen was locked/off.
  // fullScreenIntent wakes the screen, but Android does NOT fire onDidReceiveNotificationResponse
  // automatically — that only fires on an explicit user tap.
  // When fullScreenIntent auto-brings the app to foreground, didChangeAppLifecycleState fires.
  // We flush this pending payload there so the VisitorPopoutDialog opens immediately.
  PushNotificationPayload? _pendingVisitorApprovalPayload;
  // Timestamp when _pendingVisitorApprovalPayload was set — used to enforce a 2-minute TTL
  // so a stale payload doesn't incorrectly show a popup if the user opens the app much later.
  DateTime? _pendingVisitorApprovalSetAt;

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
    final previous = _lifecycleState;
    _lifecycleState = state;
    debugPrint('[PushNotificationManager] App lifecycle state transitioned to: $state');

    // ── FULL-SCREEN INTENT FOREGROUND HANDLER (over lock screen + after unlock) ──────────────
    // When fullScreenIntent fires, Android auto-brings the app toward the foreground (no tap needed).
    // The lifecycle state it lands on depends on the device / Android version:
    //   • Most Android (stock/Pixel): app goes directly to `resumed`
    //   • Samsung One UI (strict mode): app goes to `inactive` while keyguard is up,
    //     then to `resumed` when the user unlocks
    //
    // To show the popup OVER the lock screen (MyGate-style — no unlock required), we must flush
    // on `inactive` too, not just on `resumed`.
    //
    // Guard conditions:
    //   1. The incoming state must be `inactive` or `resumed` (app is at least partially visible)
    //   2. The previous state must have been a fully background state (`paused` or `detached`)
    //      This prevents spurious triggers when the user alt-tabs or receives a phone call
    //   3. A pending payload must exist AND be within 2 minutes (TTL) to avoid stale popups
    final bool comingToForeground =
        (state == AppLifecycleState.inactive || state == AppLifecycleState.resumed) &&
        (previous == AppLifecycleState.paused || previous == AppLifecycleState.detached);

    if (comingToForeground && _pendingVisitorApprovalPayload != null) {
      // TTL check: discard payloads older than 2 minutes (visitor already left / resolved)
      final setAt = _pendingVisitorApprovalSetAt;
      final bool isStale = setAt != null &&
          DateTime.now().difference(setAt).inSeconds > 120;

      if (isStale) {
        debugPrint('[PushNotificationManager] Discarding stale visitor approval payload (>2 min old)');
        _pendingVisitorApprovalPayload = null;
        _pendingVisitorApprovalSetAt = null;
      } else {
        final deferred = _pendingVisitorApprovalPayload!;
        _pendingVisitorApprovalPayload = null;  // Consume immediately — prevents double-firing
        _pendingVisitorApprovalSetAt = null;
        debugPrint('[PushNotificationManager] fullScreenIntent foreground detected (state=$state) — showing visitor popup over lock screen');
        // 300ms delay gives Flutter's Navigator time to be ready without making the user wait
        Future.delayed(const Duration(milliseconds: 300), () {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted && onIncomingVisitorApproval != null) {
            onIncomingVisitorApproval!.call(ctx, deferred);
          }
        });
      }
    }
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

      // Initialize the local notifications plugin with Android settings and response callbacks
      await _localNotifications.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          // Check if user tapped an interactive action button ('Approve' / 'Deny' / 'Leave at Gate')
          final actionId = response.actionId;
          if (actionId == 'APPROVE_ACTION' || actionId == 'DENY_ACTION' || actionId == 'LEAVE_AT_GATE_ACTION') {
            await handleNotificationActionStatic(response);
            return;
          }

          // If the user tapped anywhere else on the notification (card body / title),
          // route into the app and open the relevant modal.
          // For visitor approval notifications, open the full-screen MyGate-style visitor clearance
          // popup dialog directly — NOT just the notifications tab!
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
                // Determine whether the notification was received recently (within 3 minutes).
                // If it is older than 3 minutes or no longer pending clearance, route to the standard
                // visitor details dialog via handleBannerTap rather than opening the intrusive full-screen wake-up screen.
                final isFresh = DateTime.now().difference(payload.receivedAt).inMinutes < 3;
                if (payload.isVisitorApprovalRequest && isFresh && onIncomingVisitorApproval != null) {
                  debugPrint('[PushNotificationManager] Fresh local notif tapped — opening visitor approval popout dialog');
                  // User tapped the notification manually — clear the pending payload so the
                  // lifecycle resume handler doesn't fire a second duplicate popup.
                  _pendingVisitorApprovalPayload = null;
                  onIncomingVisitorApproval!.call(ctx, payload);
                } else {
                  debugPrint('[PushNotificationManager] Local notif tapped — routing to details dialog via handleBannerTap');
                  handleBannerTap(ctx, payload);
                }
              } else {
                // Context not ready yet — store for later consumption after dashboard mounts
                _pendingLaunchPayload = payload;
              }
            } catch (e) {
              debugPrint('[PushNotificationManager] Error handling system notification response: $e');
            }
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      );

      // Check if app was cold-launched from a full-screen intent or notification tap
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final payloadStr = launchDetails.notificationResponse?.payload;
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final map = jsonDecode(payloadStr) as Map<String, dynamic>;
            _pendingLaunchPayload = PushNotificationPayload(
              id: map['id']?.toString() ?? '',
              title: map['title']?.toString() ?? 'Society Notification',
              message: map['message']?.toString() ?? '',
              type: map['type']?.toString() ?? 'GENERAL',
              flatNumber: map['flatNumber']?.toString(),
              extraData: map['extraData'] is Map ? Map<String, dynamic>.from(map['extraData']) : {},
            );
          } catch (_) {}
        }
      }

      // Request notification permissions for Android 13+
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      // ── USE_FULL_SCREEN_INTENT PERMISSION (Android 14+ / API 34+) ──────────────────
      // On Android 14+, apps that are NOT phone-dialers or alarm apps must get explicit
      // user permission for fullScreenIntent to work. Without it, the notification is
      // posted silently into the status bar (doorbell rings) but the screen NEVER wakes.
      //
      // requestFullScreenIntentPermission() opens the system Settings page for this app
      // where the user toggles "Allow display of pop-up while screen is on / off lock screen".
      // On Android < 14, this is a no-op. flutter_local_notifications v22.3.1 supports this.
      try {
        await androidPlugin?.requestFullScreenIntentPermission();
        debugPrint('[PushNotificationManager] USE_FULL_SCREEN_INTENT permission requested ✓');
      } catch (e) {
        // Safe to ignore — permission check may not apply on all Android versions.
        debugPrint('[PushNotificationManager] fullScreenIntent permission check skipped: $e');
      }

      // Explicitly purge legacy channels that may have had sound or importance muted in device settings
      await androidPlugin?.deleteNotificationChannel(channelId: 'society_visitor_ring_channel');
      await androidPlugin?.deleteNotificationChannel(channelId: 'society_visitor_ring_channel_v2');
      await androidPlugin?.deleteNotificationChannel(channelId: 'society_visitor_ring_channel_v3');

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

      // Dedicated channel v4 for walk-in visitor clearance with custom doorbell ringtone
      const AndroidNotificationChannel visitorRingChannel = AndroidNotificationChannel(
        'society_visitor_ring_channel_v4',
        'Visitor Doorbell & Gate Approvals',
        description: 'Urgent visitor gate clearance requests with custom doorbell ringtone',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('cell_phone_ring_std'),
        enableVibration: true,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      );

      // Dedicated channel for visitor overstay alerts with custom clock alarm sound
      const AndroidNotificationChannel overstayChannel = AndroidNotificationChannel(
        'society_overstay_channel',
        'Visitor Overstay Alerts',
        description: 'High-priority alarm alerts when visitors or delivery agents exceed allowed campus stay time',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('clock_alarm'),
        enableVibration: true,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );

      await androidPlugin?.createNotificationChannel(generalChannel);
      await androidPlugin?.createNotificationChannel(emergencyChannel);
      await androidPlugin?.createNotificationChannel(visitorRingChannel);
      await androidPlugin?.createNotificationChannel(overstayChannel);

      // ── SCREEN-WAKE CHANNEL FIX ────────────────────────────────────────────────────────────────
      // ROOT CAUSE: The old 'society_visitor_silent_wake_channel' used Importance.low.
      // Android (documented behavior) silently suppresses fullScreenIntent for channels whose
      // importance < HIGH. On Samsung One UI this is especially strict — the screen NEVER wakes
      // from a low-importance channel notification, regardless of fullScreenIntent:true on the
      // individual notification. This is why only sound played but the popup never appeared.
      //
      // FIX STRATEGY:
      // 1. Delete the old low-importance channel — Android caches channel importance on first
      //    registration and ignores any subsequent updates to the same channel ID. The only way
      //    to change importance is to delete the channel and create a new one (or use a new ID).
      // 2. Create 'society_visitor_wake_channel_v2' with Importance.max so Android actually fires
      //    the fullScreenIntent and wakes/unlocks the screen.
      // 3. playSound:false at the CHANNEL level — the doorbell ringtone already plays via the
      //    FCM background handler through 'society_visitor_ring_channel_v4'. Keeping sound off
      //    here prevents the doorbell from double-ringing.
      await androidPlugin?.deleteNotificationChannel(channelId: 'society_visitor_silent_wake_channel');
      const AndroidNotificationChannel visitorWakeChannel = AndroidNotificationChannel(
        'society_visitor_wake_channel_v2',
        'Visitor Gate Alerts',
        description: 'Full-screen popup notification that wakes the screen when a visitor is waiting at the gate',
        importance: Importance.max,   // MUST be HIGH or MAX for fullScreenIntent to fire on Samsung / Pixel
        playSound: false,              // Doorbell sound already comes from society_visitor_ring_channel_v4 via FCM
        enableVibration: true,
        showBadge: true,
      );
      await androidPlugin?.createNotificationChannel(visitorWakeChannel);

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
            // For fresh visitor approval requests: open the full-screen clearance popup
            // if the event is recent (< 3 minutes) and still actively pending approval.
            // For all stale or resolved visitor notifications: fall through to handleBannerTap → details dialog.
            final isFresh = DateTime.now().difference(payload.receivedAt).inMinutes < 3;
            if (payload.isVisitorApprovalRequest && isFresh && onIncomingVisitorApproval != null) {
              debugPrint('[PushNotificationManager] Fresh FCM background tap — opening visitor approval popout dialog');
              onIncomingVisitorApproval!.call(ctx, payload);
            } else {
              debugPrint('[PushNotificationManager] FCM background tap — routing to details dialog via handleBannerTap');
              handleBannerTap(ctx, payload);
            }
          } else {
            // App context not yet available (edge case during cold restart) — defer
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

    // ─── Consume pending launch payload ──────────────────────────────────────────
    // If the app was launched from a cold start or background tap of a visitor
    // approval notification, _pendingLaunchPayload was stored during initialization
    // before the ResidentDashboard's callbacks were registered.
    //
    // Now that startListening is called AFTER the dashboard registers
    // onIncomingVisitorApproval, we flush the deferred payload one frame later
    // (post-frame delay ensures the Navigator context is fully mounted before
    // we try to open the full-screen clearance dialog).
    if (_pendingLaunchPayload != null) {
      final deferred = _pendingLaunchPayload!;
      _pendingLaunchPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Allow one extra microtask tick for the dashboard to fully stabilize
        Future.delayed(const Duration(milliseconds: 400), () {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            if (deferred.isVisitorApprovalRequest && onIncomingVisitorApproval != null) {
              // Cold/background-launched visitor notification → open the full clearance popup
              debugPrint('[PushNotificationManager] Flushing deferred visitor approval popup (pending launch)');
              onIncomingVisitorApproval!.call(ctx, deferred);
            } else if (onNotificationClick != null) {
              // Other notification types → route to relevant dashboard section
              debugPrint('[PushNotificationManager] Flushing deferred notification click (pending launch)');
              onNotificationClick!.call(ctx, deferred);
            }
          }
        });
      });
    }


    bool isInitialSnapshot = true;
    _subscription = FirebaseFirestore.instance
        .collection('notifications')
        .snapshots()
        .listen(
      (snapshot) {
        // On initial stream connection when the app starts up, mark all existing documents as seen.
        // This prevents the application from replaying stale unread notifications from past days/sessions
        // (such as older checkout alerts or past visitor passes) as new push alerts!
        if (isInitialSnapshot) {
          isInitialSnapshot = false;
          for (final doc in snapshot.docs) {
            _seenNotificationIds.add(doc.id);
          }
          debugPrint('[PushNotificationManager] Initial snapshot primed with ${_seenNotificationIds.length} existing notifications. Historical alerts suppressed.');
          return;
        }

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

    // Guard-side auto-creation: If a guard receives a VISITOR_APPROVAL_RESPONSE for LEAVE_AT_GATE,
    // automatically ensure the parcel record is created in gate_parcels using guard authority
    if (_currentUserRole == 'GUARD') {
      final extraData = data['extraData'] is Map ? Map<String, dynamic>.from(data['extraData'] as Map) : data;
      final approvalStatus = (extraData['approvalStatus'] ?? data['approvalStatus'] ?? '').toString();
      if (type == 'VISITOR_APPROVAL_RESPONSE' && (approvalStatus == 'LEAVE_AT_GATE' || title.contains('Leave at Gate'))) {
        VisitorPassService.ensureLeaveAtGateParcelCreated(
          visitorDocId: extraData['visitorDocId']?.toString(),
          flatNumber: (data['flatNumber'] ?? extraData['flatNumber'] ?? '').toString(),
          visitorName: (extraData['visitorName'] ?? 'Delivery').toString(),
          deliveryProvider: extraData['deliveryProvider']?.toString(),
          pickupOtp: extraData['pickupOtp']?.toString(),
          photoUrl: extraData['photoUrl']?.toString(),
          gateName: extraData['gateName']?.toString(),
          guardName: extraData['guardName']?.toString(),
          guardUid: _currentUserId,
        );
      }
    }

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
  ///
  /// VISITOR APPROVAL REQUESTS: bypasses both the system notification action bar
  /// and the in-app floating banner entirely. The full-screen MyGate-style
  /// VisitorPopoutDialog is shown immediately and directly. This matches the user
  /// requirement: "pop the screen up right away — no notification bar required."
  ///
  /// ALL OTHER TYPES: normal flow — system notification for background, in-app banner for foreground.
  void _deliverPayload(PushNotificationPayload payload) {
    final bool isAppForeground =
        _lifecycleState == AppLifecycleState.resumed ||
        _lifecycleState == AppLifecycleState.inactive;

    // ── VISITOR APPROVAL FLOW ────────────────────────────────────────────────
    // Skip the notification banner and heads-up card entirely.
    // Show the full-screen VisitorPopoutDialog immediately.
    if (payload.isVisitorApprovalRequest) {
      if (isAppForeground) {
        // App is visible — open the full clearance popup straight away with ringtone.
        HapticFeedback.heavyImpact();
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          onIncomingVisitorApproval?.call(ctx, payload);
        }
      } else {
        // App is in background or locked — post a silent wake notification (no action buttons,
        // no heads-up banner) whose tap handler will open the VisitorPopoutDialog
        // when the resident brings the app to the foreground.
        _showVisitorWakeNotification(payload);
      }
      return; // Exit early — no banner, no generic flow below.
    }

    // ── NON-VISITOR FLOW (bills, parcels, emergency, overstay, announcements) ──────────
    // 1. Post native Android OS system notification into notification hood / status bar.
    // Ensure overstay alerts also post OS system notifications even if the app is currently in foreground,
    // so the custom clock_alarm sound and status bar alert are triggered at the OS level.
    if (!isAppForeground || payload.isOverstay) {
      _showSystemNotification(payload);
    }

    // 2. If app is in foreground, trigger haptic feedback and show in-app banner.
    if (isAppForeground) {
      if (payload.isEmergency || payload.isOverstay) {
        HapticFeedback.heavyImpact();
      } else {
        HapticFeedback.mediumImpact();
      }

      // Display the floating in-app heads-up banner.
      activeNotification.value = payload;

      // Auto-dismiss banner after 6 seconds (emergency and overstay banners stay until dismissed).
      _dismissTimer?.cancel();
      if (!payload.isEmergency && !payload.isOverstay) {
        _dismissTimer = Timer(const Duration(seconds: 6), () {
          if (activeNotification.value?.id == payload.id) {
            activeNotification.value = null;
          }
        });
      }
    }
  }

  /// Posts a HIGH-IMPORTANCE wake notification for visitor approvals when the resident's app is in the background.
  ///
  /// SCREEN-WAKE FIX: fullScreenIntent ONLY fires (and thus wakes the screen) if the notification channel
  /// has Importance.HIGH or higher. This notification uses 'society_visitor_wake_channel_v2' (Importance.max)
  /// instead of the old low-importance channel, so the screen reliably wakes on Samsung and other Android devices.
  ///
  /// Sound is disabled per-notification (playSound:false) because the doorbell ringtone already plays via the
  /// FCM background handler's 'society_visitor_ring_channel_v4' — preventing double-ringing.
  ///
  /// When the resident taps the notification or Android auto-launches the full-screen intent,
  /// the tap callback opens the full VisitorPopoutDialog directly.
  Future<void> _showVisitorWakeNotification(PushNotificationPayload payload) async {
    try {
      final int notifId = payload.id.hashCode & 0x7FFFFFFF;

      // Store the payload so didChangeAppLifecycleState can flush it when Android
      // auto-brings the app to foreground via fullScreenIntent (both over lock screen and after unlock).
      // Without this, the popup would never show because onDidReceiveNotificationResponse
      // only fires on explicit user tap — NOT on fullScreenIntent auto-launch.
      _pendingVisitorApprovalPayload = payload;
      // Record time so the lifecycle handler can enforce a 2-minute TTL on this payload.
      _pendingVisitorApprovalSetAt = DateTime.now();

      // Use 'society_visitor_wake_channel_v2' (Importance.max) — this is the key fix.
      // Android requires the channel importance to be HIGH or MAX for fullScreenIntent to actually
      // wake the screen. The old low-importance channel was silently suppressing the full-screen intent.
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'society_visitor_wake_channel_v2',  // NEW: Importance.max channel — screen wakes reliably
        'Visitor Gate Alerts',
        channelDescription: 'Full-screen popup notification that wakes the screen when a visitor is waiting at the gate',
        importance: Importance.max,         // FIXED: was Importance.low — now correctly wakes screen
        priority: Priority.max,             // FIXED: was Priority.high
        autoCancel: true,
        ongoing: false,
        ticker: payload.title,
        color: const Color(0xFF0F766E),
        visibility: NotificationVisibility.public,
        enableLights: true,
        enableVibration: true,
        playSound: false,          // No OS doorbell here — FCM handler plays via society_visitor_ring_channel_v4
        channelShowBadge: true,
        fullScreenIntent: true,    // Wakes device and opens VisitorPopoutDialog over lock screen
        category: AndroidNotificationCategory.call,
        // No action buttons — resident will interact via the full-screen popup
      );

      final sanitizedExtraData = _sanitizeForJson(payload.extraData);

      await _localNotifications.show(
        id: notifId,
        title: payload.title,
        body: payload.message,
        notificationDetails: NotificationDetails(android: androidDetails),
        payload: jsonEncode({
          'id': payload.id,
          'title': payload.title,
          'message': payload.message,
          'type': payload.type,
          'flatNumber': payload.flatNumber,
          'extraData': sanitizedExtraData,
        }),
      );
      debugPrint('[PushNotificationManager] Posted visitor wake notification (Importance.max, screen will wake): $notifId');
    } catch (e) {
      debugPrint('[PushNotificationManager] Visitor wake notification error: $e');
    }
  }

  /// Dispatches native Android OS system notification into the device status bar / notification hood.

  Future<void> _showSystemNotification(PushNotificationPayload payload) async {
    try {
      final int notifId = payload.id.hashCode & 0x7FFFFFFF;
      final bool isVisitorApproval = payload.isVisitorApprovalRequest;
      final bool isOverstay = payload.isOverstay;

      final String channelId = payload.isEmergency
          ? 'society_emergency_channel'
          : (isOverstay
              ? 'society_overstay_channel'
              : (isVisitorApproval ? 'society_visitor_ring_channel_v4' : 'society_general_channel'));

      final String channelName = payload.isEmergency
          ? 'Society Emergency Alerts'
          : (isOverstay
              ? 'Visitor Overstay Alerts'
              : (isVisitorApproval ? 'Visitor Doorbell & Gate Approvals' : 'Society Notifications'));

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: payload.isEmergency
            ? 'Critical emergency SOS alerts'
            : (isOverstay
                ? 'High-priority alarm alerts when visitors or delivery agents exceed allowed campus stay time'
                : (isVisitorApproval
                    ? 'Urgent visitor gate clearance requests with custom doorbell ringtone'
                    : 'Important society announcements, bills, visitor and parcel alerts')),
        importance: (payload.isEmergency || isOverstay || isVisitorApproval) ? Importance.max : Importance.high,
        priority: (payload.isEmergency || isOverstay || isVisitorApproval) ? Priority.max : Priority.high,
        autoCancel: true,
        ongoing: false,
        ticker: payload.title,
        color: isOverstay ? const Color(0xFFDC2626) : const Color(0xFF0F766E), // Red for overstay alarm
        visibility: NotificationVisibility.public,
        enableLights: true,
        enableVibration: true,
        playSound: true,
        sound: isOverstay
            ? const RawResourceAndroidNotificationSound('clock_alarm')
            : (isVisitorApproval ? const RawResourceAndroidNotificationSound('cell_phone_ring_std') : null),
        audioAttributesUsage: isOverstay
            ? AudioAttributesUsage.alarm
            : (isVisitorApproval ? AudioAttributesUsage.notificationRingtone : AudioAttributesUsage.notification),
        channelShowBadge: true,
        fullScreenIntent: payload.isEmergency || isOverstay || isVisitorApproval,
        category: (payload.isEmergency || isOverstay)
            ? AndroidNotificationCategory.alarm
            : (isVisitorApproval ? AndroidNotificationCategory.call : AndroidNotificationCategory.message),
        // Interactive action buttons on the heads-up notification card: Approve, Leave at Gate, and Deny.
        // Setting showsUserInterface: false ensures actions execute headlessly in the background via
        // notificationTapBackground without demanding the user unlock the screen or PIN challenge.
        // Leave at Gate is strictly reserved for delivery/courier personnel; omitted for Guests!
        actions: isVisitorApproval
            ? <AndroidNotificationAction>[
                const AndroidNotificationAction(
                  'APPROVE_ACTION',
                  'Approve',
                  titleColor: Color(0xFF16A34A),
                  showsUserInterface: false,
                  cancelNotification: true,
                ),
                if (payload.isDelivery)
                  const AndroidNotificationAction(
                    'LEAVE_AT_GATE_ACTION',
                    'Leave at Gate',
                    titleColor: Color(0xFFD97706),
                    showsUserInterface: false,
                    cancelNotification: true,
                  ),
                const AndroidNotificationAction(
                  'DENY_ACTION',
                  'Deny',
                  titleColor: Color(0xFFDC2626),
                  showsUserInterface: false,
                  cancelNotification: true,
                ),
              ]
            : null,
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

  /// Marks a visitor delivery as leave at gate directly from the push banner,
  /// atomically creating a gate parcel entry and alerting security guards.
  Future<void> handleLeaveAtGateVisitor(PushNotificationPayload payload) async {
    final visitorDocId = payload.extraData['visitorDocId']?.toString();
    final flatNumber = payload.flatNumber ?? payload.extraData['flatNumber']?.toString() ?? '';
    final visitorName = payload.extraData['visitorName']?.toString() ?? 'Visitor';
    final deliveryApp = payload.extraData['deliveryApp']?.toString();
    final photoUrl = payload.extraData['photoUrl']?.toString();
    final gateName = payload.extraData['gateName']?.toString();

    dismissCurrent();

    try {
      await VisitorPassService.leaveAtGateVisitorEntry(
        visitorDocId: visitorDocId,
        flatNumber: flatNumber,
        visitorName: visitorName,
        notifDocId: payload.id,
        deliveryApp: deliveryApp,
        photoUrl: photoUrl,
        gateName: gateName,
      );
    } catch (e) {
      debugPrint('[PushNotificationManager] Error setting leave at gate for visitor: $e');
    }
  }

  /// Cancels an active native system notification by ID and tag from the Android status bar / tray,
  /// and clears any matching in-app floating banner.
  static Future<void> cancelNotification(String notifId, [String? visitorDocId]) async {
    try {
      if (notifId.isNotEmpty) {
        final id1 = notifId.hashCode & 0x7FFFFFFF;
        await instance._localNotifications.cancel(id: id1);
        await instance._localNotifications.cancel(id: id1, tag: notifId);
        await instance._localNotifications.cancel(id: 0, tag: notifId);
      }
      if (visitorDocId != null && visitorDocId.isNotEmpty) {
        final id2 = visitorDocId.hashCode & 0x7FFFFFFF;
        await instance._localNotifications.cancel(id: id2);
        await instance._localNotifications.cancel(id: id2, tag: visitorDocId);
        await instance._localNotifications.cancel(id: 0, tag: visitorDocId);
      }
      if (instance.activeNotification.value?.id == notifId ||
          (visitorDocId != null && instance.activeNotification.value?.extraData['visitorDocId'] == visitorDocId)) {
        instance.activeNotification.value = null;
      }
      debugPrint('[PushNotificationManager] Canceled notification for $notifId / $visitorDocId');
    } catch (e) {
      debugPrint('[PushNotificationManager] Error canceling notification: $e');
    }
  }

  /// Handles 1-tap interactive notification action buttons (Approve / Deny)
  /// directly from the Android status bar or lock screen without requiring the app to be opened.
  static Future<void> handleNotificationActionStatic(NotificationResponse response) async {
    final actionId = response.actionId;
    final payloadStr = response.payload;
    if (payloadStr == null || payloadStr.isEmpty) return;

    try {
      final map = jsonDecode(payloadStr) as Map<String, dynamic>;
      final extraData = map['extraData'] is Map ? Map<String, dynamic>.from(map['extraData']) : <String, dynamic>{};
      final notifDocId = map['id']?.toString();
      final visitorDocId = extraData['visitorDocId']?.toString() ?? map['visitorDocId']?.toString();
      final visitorName = (extraData['visitorName'] ?? map['visitorName'] ?? map['title'] ?? 'Visitor').toString().replaceFirst('Visitor At Gate: ', '').trim();
      final flatNumber = (map['flatNumber'] ?? extraData['flatNumber'] ?? '').toString();

      // Ensure Firebase is initialized for background execution
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        }
      } catch (_) {}

      if (actionId == 'APPROVE_ACTION') {
        debugPrint('[PushNotificationManager] Interactive notification action: APPROVE for $visitorName ($visitorDocId)');
        await VisitorPassService.approveVisitorEntry(
          visitorDocId: visitorDocId,
          flatNumber: flatNumber,
          visitorName: visitorName,
          notifDocId: notifDocId,
        );
        await cancelNotification(notifDocId ?? '', visitorDocId);
      } else if (actionId == 'LEAVE_AT_GATE_ACTION') {
        debugPrint('[PushNotificationManager] Interactive notification action: LEAVE_AT_GATE for $visitorName ($visitorDocId)');
        await VisitorPassService.leaveAtGateVisitorEntry(
          visitorDocId: visitorDocId,
          flatNumber: flatNumber,
          visitorName: visitorName,
          notifDocId: notifDocId,
          deliveryApp: extraData['deliveryApp']?.toString(),
          photoUrl: extraData['photoUrl']?.toString(),
        );
        await cancelNotification(notifDocId ?? '', visitorDocId);
      } else if (actionId == 'DENY_ACTION') {
        debugPrint('[PushNotificationManager] Interactive notification action: DENY for $visitorName ($visitorDocId)');
        await VisitorPassService.denyVisitorEntry(
          visitorDocId: visitorDocId,
          flatNumber: flatNumber,
          visitorName: visitorName,
          notifDocId: notifDocId,
        );
        await cancelNotification(notifDocId ?? '', visitorDocId);
      }
    } catch (e) {
      debugPrint('[PushNotificationManager] Error handling notification action: $e');
    }
  }

  NotificationClickHandler? _onNotificationClick;
  NotificationClickHandler? _onIncomingVisitorApproval;

  /// Callback for routing resident to the correct dashboard section when a notification is tapped.
  /// Receives the active [BuildContext] and the [PushNotificationPayload].
  NotificationClickHandler? get onNotificationClick => _onNotificationClick;

  set onNotificationClick(NotificationClickHandler? handler) {
    _onNotificationClick = handler;
    // If a NON-visitor notification was tapped before the dashboard registered its click handler, execute it now.
    // Visitor approval payloads are handled exclusively by onIncomingVisitorApproval setter below.
    if (handler != null && _pendingLaunchPayload != null && !_pendingLaunchPayload!.isVisitorApprovalRequest) {
      final payload = _pendingLaunchPayload!;
      _pendingLaunchPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          handler.call(ctx, payload);
        }
      });
    }
  }

  /// Callback triggered automatically when an incoming visitor approval request arrives.
  /// For foreground arrival: called directly from _deliverPayload.
  /// For background/cold launch: the setter flushes _pendingLaunchPayload as soon as
  /// ResidentDashboard.initState registers this callback, ensuring the popup appears
  /// even when the resident tapped the notification while the app was in the background.
  NotificationClickHandler? get onIncomingVisitorApproval => _onIncomingVisitorApproval;

  set onIncomingVisitorApproval(NotificationClickHandler? handler) {
    _onIncomingVisitorApproval = handler;
    // Flush any deferred visitor approval payload that arrived before the dashboard was mounted
    if (handler != null && _pendingLaunchPayload != null && _pendingLaunchPayload!.isVisitorApprovalRequest) {
      final payload = _pendingLaunchPayload!;
      _pendingLaunchPayload = null;
      debugPrint('[PushNotificationManager] Flushing deferred visitor popup via onIncomingVisitorApproval setter');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Small delay to let the ResidentDashboard widget fully render before showing dialog
        Future.delayed(const Duration(milliseconds: 300), () {
          final ctx = navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            handler.call(ctx, payload);
          }
        });
      });
    }
  }

  /// Handles user tapping the banner body or native OS system notification.
  /// 1. Marks the notification as read in Firestore.
  /// 2. Dismisses the heads-up banner from screen.
  /// 3. Executes [onNotificationClick] to route the user directly to the relevant modal/section.
  Future<void> handleBannerTap(BuildContext context, PushNotificationPayload payload) async {
    // Immediately cancel and dismiss any matching native OS system notification from the status bar hood
    await cancelNotification(payload.id, payload.extraData['visitorDocId']?.toString());

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
    // Clear both callback backing fields directly to avoid triggering the setter flush logic on teardown
    _onNotificationClick = null;
    _onIncomingVisitorApproval = null;
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
                onLeaveAtGate: (payload.isVisitorApprovalRequest && payload.isDelivery)
                    ? () => PushNotificationManager.instance.handleLeaveAtGateVisitor(payload)
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
