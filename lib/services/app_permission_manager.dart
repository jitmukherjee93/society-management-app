import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'push_notification_manager.dart';

// ============================================================================
// APP PERMISSION MANAGER
// ============================================================================
// Centralized service responsible for requesting critical OS-level runtime
// permissions (Camera and Notifications) upon app installation and launch.
//
// Android 9+ (API 28+) & Android 13+ (API 33+) Requirements:
// 1. Notification Permission: Mandatory on Android 13+ (POST_NOTIFICATIONS) and iOS
//    for receiving emergency alerts, gate visitor requests, parcel arrival notices,
//    and payment approvals.
// 2. Camera Permission: Mandatory for Guard Kiosk (visitor verification photo capture)
//    and Resident Portal (document/payment receipt uploads).
class AppPermissionManager {
  /// Proactively requests runtime permissions on initial app launch or screen mount.
  /// Android and iOS prompt the user with native system permission dialogs.
  static Future<void> requestInitialPermissions() async {
    try {
      debugPrint('[AppPermissionManager] Initiating initial permission requests...');

      // 1. Request Notification Permission (Required for real-time security alerts)
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // On iOS, invoke PushNotificationManager to trigger Darwin and FirebaseMessaging prompts
        await PushNotificationManager.instance.initializeSystemNotifications();
      } else {
        final notifStatus = await Permission.notification.status;
        if (!notifStatus.isGranted) {
          final notifResult = await Permission.notification.request();
          debugPrint('[AppPermissionManager] Notification permission result: $notifResult');
        } else {
          debugPrint('[AppPermissionManager] Notification permission already granted.');
        }
      }

      // 2. Request Camera Permission (Required for visitor passes and document verification)
      final cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        final cameraResult = await Permission.camera.request();
        debugPrint('[AppPermissionManager] Camera permission result: $cameraResult');
      } else {
        debugPrint('[AppPermissionManager] Camera permission already granted.');
      }
    } catch (e) {
      debugPrint('[AppPermissionManager] Error during permission request: $e');
    }
  }

  /// Checks if camera access is currently granted.
  static Future<bool> hasCameraPermission() async {
    return await Permission.camera.isGranted;
  }

  /// Checks if notification access is currently granted.
  static Future<bool> hasNotificationPermission() async {
    return await Permission.notification.isGranted;
  }
}

