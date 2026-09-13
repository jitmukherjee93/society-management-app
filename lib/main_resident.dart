import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'firebase_options.dart';
import 'constants/app_flavor.dart';
import 'main.dart';

/// Standalone Entrypoint for the Ramkrishnapuram Resident App.
/// Run target: `flutter run -t lib/main_resident.dart`
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    PhoneAuthProvider(),
  ]);

  AppFlavorConfig.initialize(AppFlavor.resident);

  runApp(const SocietyManagementApp(flavor: AppFlavor.resident));
}

