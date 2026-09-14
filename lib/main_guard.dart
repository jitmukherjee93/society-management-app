import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'firebase_options.dart';
import 'constants/app_flavor.dart';
import 'services/push_notification_manager.dart';
import 'main.dart';

/// Standalone Entrypoint for the Gate Security Kiosk App.
/// Run target: `flutter run -t lib/main_guard.dart --flavor guard`
/// Build target: `flutter build apk --flavor guard -t lib/main_guard.dart`
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with the Gate Guard-specific Android Application ID
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatformForFlavor(AppFlavor.guard),
  );

  // Background push notification handler for suspended/terminated kiosk state
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize native OS notification channels, status bar hooks, and foreground banners
  await PushNotificationManager.instance.initializeSystemNotifications();

  // Authentication UI providers
  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    PhoneAuthProvider(),
  ]);

  // Set flavor configuration to Guard
  AppFlavorConfig.initialize(AppFlavor.guard);

  runApp(const SocietyManagementApp(flavor: AppFlavor.guard));
}
