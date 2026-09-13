import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'firebase_options.dart';
import 'constants/app_flavor.dart';
import 'main.dart';

/// Standalone Entrypoint for the Ramkrishnapuram RWA Admin Portal.
/// Optimized for Desktop, Tablet, and Flutter Web.
/// Run target: `flutter run -t lib/main_admin.dart` or `flutter run -d chrome -t lib/main_admin.dart`
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    PhoneAuthProvider(),
  ]);

  AppFlavorConfig.initialize(AppFlavor.admin);

  runApp(const SocietyManagementApp(flavor: AppFlavor.admin));
}

