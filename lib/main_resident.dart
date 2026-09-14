import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'firebase_options.dart';
import 'constants/app_flavor.dart';
import 'services/push_notification_manager.dart';
import 'main.dart';

/// Standalone Entrypoint for the Ramkrishnapuram Resident App.
/// Run target: `flutter run -t lib/main_resident.dart --flavor resident`
/// Build target: `flutter build apk --flavor resident -t lib/main_resident.dart`
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with the Resident-specific Android Application ID
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatformForFlavor(AppFlavor.resident),
  );

  // Background push notification handler for suspended/terminated app state
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize native OS notification channels, status bar hooks, and foreground banners
  await PushNotificationManager.instance.initializeSystemNotifications();

  // Authentication UI providers
  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    PhoneAuthProvider(),
  ]);

  // Set flavor configuration to Resident
  AppFlavorConfig.initialize(AppFlavor.resident);

  runApp(const SocietyManagementApp(flavor: AppFlavor.resident));
}
