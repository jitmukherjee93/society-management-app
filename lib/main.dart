import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider, PhoneAuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/resident/resident_dashboard.dart';
import 'screens/guard/guard_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';
import 'widgets/app_feedback.dart';
import 'widgets/app_error_boundary.dart';
import 'services/push_notification_manager.dart';
import 'services/app_permission_manager.dart';
import 'constants/app_flavor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Gracefully handle UI build errors and framework assertions without red screens
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return AppErrorWidget(errorDetails: details);
  };

  // Catch unhandled Flutter framework errors and format to console/reporting
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  // Catch unhandled asynchronous errors from Dart/web zones
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Global Async Error: $error\n$stack');
    return true; // Mark as handled to prevent application breakdown
  };

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Register background message handler for when app is suspended or in background
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize native OS notification channels, status bar hooks, and system notification handlers
  await PushNotificationManager.instance.initializeSystemNotifications();

  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    PhoneAuthProvider(),
  ]);

  AppFlavorConfig.initialize(AppFlavor.unified);
  
  runApp(const SocietyManagementApp());
}

class SocietyManagementApp extends StatelessWidget {
  final AppFlavor? flavor;
  const SocietyManagementApp({super.key, this.flavor});

  @override
  Widget build(BuildContext context) {
    if (flavor != null && (!AppFlavorConfig.isInitialized || AppFlavorConfig.current.flavor != flavor)) {
      AppFlavorConfig.initialize(flavor!);
    } else if (!AppFlavorConfig.isInitialized) {
      AppFlavorConfig.initialize(AppFlavor.unified);
    }

    final config = AppFlavorConfig.current;

    return MaterialApp(
      // Attach global navigator key so notification taps from the Android system notification hood can route modals
      navigatorKey: PushNotificationManager.navigatorKey,
      title: config.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) {
        // Wrap app tree in Global Error Boundary and In-App Heads-Up Push Notification Overlay
        return AppGlobalErrorBoundary(
          child: PushNotificationOverlay(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const AuthWrapper(),
    );
  }
}

// Top-level authentication wrapper that monitors user login state and triggers
// runtime permissions (Camera & Notifications) upon initial app launch / install.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // Prompt the user for Camera and Notification permissions as soon as the first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppPermissionManager.requestInitialPermissions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasData) {
          return const RoleRouter();
        }
        
        // When logged out, cancel active push notification listeners
        PushNotificationManager.instance.stopListening();
        return const CustomAuthScreen();
      },
    );
  }
}

class CustomAuthScreen extends StatefulWidget {
  const CustomAuthScreen({super.key});

  @override
  State<CustomAuthScreen> createState() => _CustomAuthScreenState();
}

class _CustomAuthScreenState extends State<CustomAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final input = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final cleanInput = input.toLowerCase();
      String targetAuthEmail = cleanInput;

      // If user typed a short flatId/username without '@' (e.g. "b-204" or "b204")
      if (!cleanInput.contains('@')) {
        targetAuthEmail = '${cleanInput.replaceAll(' ', '')}@ramkrishnapuram.com';
      }

      // Check if user is trying to log in using flat number or default society email
      final bool isFlatOrSocietyEmailInput =
          !cleanInput.contains('@') || cleanInput.endsWith('@ramkrishnapuram.com');

      if (isFlatOrSocietyEmailInput) {
        String flatCode = cleanInput;
        if (flatCode.contains('@')) {
          flatCode = flatCode.split('@').first;
        }
        flatCode = flatCode.toUpperCase().replaceAll(' ', '');

        try {
          final usersRef = FirebaseFirestore.instance.collection('users');
          var snap = await usersRef
              .where('flatNumber', isEqualTo: flatCode)
              .where('isOwner', isEqualTo: true)
              .limit(1)
              .get();

          if (snap.docs.isEmpty) {
            snap = await usersRef
                .where('flatNumber', isEqualTo: flatCode)
                .limit(1)
                .get();
          }

          if (snap.docs.isEmpty) {
            snap = await usersRef
                .where('username', isEqualTo: targetAuthEmail)
                .limit(1)
                .get();
          }

          if (snap.docs.isNotEmpty) {
            final data = snap.docs.first.data();
            final personalEmail = (data['personalEmail'] ?? '').toString().trim();
            final bool hasUpdatedEmail = personalEmail.isNotEmpty &&
                personalEmail.contains('@') &&
                !personalEmail.toLowerCase().endsWith('@ramkrishnapuram.com');

            if (hasUpdatedEmail) {
              if (mounted) {
                setState(() {
                  _errorMessage =
                      'Login via Flat Number or default society ID is disabled. Since you have updated your email, please sign in using your registered email address ($personalEmail).';
                  _isLoading = false;
                });
              }
              return;
            }
          }
        } catch (_) {
          // If Firestore query fails, fallback gracefully
        }
      }

      // 1. Try direct Firebase Auth sign-in first
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: targetAuthEmail,
          password: password,
        );
        return;
      } catch (authError) {
        // Fallback: If direct sign-in failed, check Firestore:
        try {
          String? resolvedAuthEmail;

          // 1. Check by personal email or email
          final snapByEmail = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: cleanInput)
              .limit(1)
              .get();

          if (snapByEmail.docs.isNotEmpty) {
            final data = snapByEmail.docs.first.data();
            resolvedAuthEmail = data['username']?.toString() ?? data['email']?.toString();
          }

          if (resolvedAuthEmail == null) {
            final snapByPersonalEmail = await FirebaseFirestore.instance
                .collection('users')
                .where('personalEmail', isEqualTo: cleanInput)
                .limit(1)
                .get();
            if (snapByPersonalEmail.docs.isNotEmpty) {
              final data = snapByPersonalEmail.docs.first.data();
              resolvedAuthEmail = data['username']?.toString() ?? data['email']?.toString();
            }
          }

          // 2. If not found and input was a society email or flat ID, check by flatNumber
          if (resolvedAuthEmail == null || resolvedAuthEmail == targetAuthEmail) {
            String flatCode = cleanInput;
            if (flatCode.contains('@')) {
              flatCode = flatCode.split('@').first;
            }
            flatCode = flatCode.toUpperCase().replaceAll(' ', '');
            final snapByFlat = await FirebaseFirestore.instance
                .collection('users')
                .where('flatNumber', isEqualTo: flatCode)
                .where('isOwner', isEqualTo: true)
                .limit(1)
                .get();

            if (snapByFlat.docs.isNotEmpty) {
              final data = snapByFlat.docs.first.data();
              final pEmail = (data['personalEmail'] ?? '').toString().trim();
              if (pEmail.isNotEmpty && pEmail.contains('@') && !pEmail.toLowerCase().endsWith('@ramkrishnapuram.com')) {
                if (mounted) {
                  setState(() {
                    _errorMessage =
                        'Login via Flat Number or default society ID is disabled. Since you have updated your email, please sign in using your registered email address ($pEmail).';
                    _isLoading = false;
                  });
                }
                return;
              }
              resolvedAuthEmail = data['email']?.toString() ?? data['username']?.toString();
            }
          }

          if (resolvedAuthEmail != null && resolvedAuthEmail.isNotEmpty && resolvedAuthEmail != targetAuthEmail) {
            await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: resolvedAuthEmail,
              password: password,
            );
            return;
          }
        } catch (_) {
          // Unauthenticated Firestore read rules will be bypassed gracefully
        }
        rethrow;
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message ?? 'An authentication error occurred.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An error occurred: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    final input = _emailController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Username or Email address first.')),
      );
      return;
    }

    try {
      final cleanInput = input.toLowerCase();
      String targetEmail = cleanInput;

      if (!cleanInput.contains('@')) {
        targetEmail = '${cleanInput.replaceAll(' ', '')}@ramkrishnapuram.com';
      }

      // Check if custom or personal email exists for this user in Firestore to send reset email there
      try {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: targetEmail)
            .get();

        if (userSnap.docs.isNotEmpty) {
          final data = userSnap.docs.first.data();
          final personalEmail = data['personalEmail']?.toString() ?? data['email']?.toString();
          if (personalEmail != null && personalEmail.contains('@') && !personalEmail.endsWith('@ramkrishnapuram.com')) {
            targetEmail = personalEmail;
          }
        } else {
          // Fallback: check by flatNumber
          String flatCode = cleanInput;
          if (flatCode.contains('@')) {
            flatCode = flatCode.split('@').first;
          }
          flatCode = flatCode.toUpperCase().replaceAll(' ', '');
          final snapByFlat = await FirebaseFirestore.instance
              .collection('users')
              .where('flatNumber', isEqualTo: flatCode)
              .where('isOwner', isEqualTo: true)
              .limit(1)
              .get();

          if (snapByFlat.docs.isNotEmpty) {
            final data = snapByFlat.docs.first.data();
            final personalEmail = data['personalEmail']?.toString() ?? data['email']?.toString();
            if (personalEmail != null && personalEmail.contains('@') && !personalEmail.endsWith('@ramkrishnapuram.com')) {
              targetEmail = personalEmail;
            }
          }
        }
      } catch (_) {}

      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: targetEmail);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade700,
              content: Text('Password reset email sent to $targetEmail! Check your inbox (and Spam/Promotions folder).'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } on FirebaseAuthException catch (authErr) {
        if (mounted) {
          String msg = authErr.message ?? 'Failed to send password reset email.';
          if (authErr.code == 'user-not-found') {
            msg = 'No password reset account found for $targetEmail. If you recently registered this email, please check your inbox for the email verification link to finalize your update, or log in with your initial password.';
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: Text(msg),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade700,
              content: Text('Error: $e'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text('Error: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppColors.border, width: 0.9),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          AppFlavorConfig.current.flavor == AppFlavor.guard
                              ? Icons.shield_rounded
                              : (AppFlavorConfig.current.flavor == AppFlavor.admin
                                  ? Icons.admin_panel_settings_rounded
                                  : Icons.apartment_rounded),
                          size: 40,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppFlavorConfig.current.appTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppFlavorConfig.current.appSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        AppBanner.error(message: _errorMessage!),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Username or Email Address',
                          hintText: 'e.g. B-312 or user@ramkrishnapuram.com',
                          prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your username or email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_isPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                              size: 20,
                              color: AppColors.textMuted,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _resetPassword,
                          child: const Text('Forgot Password?', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Sign In to Dashboard',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  bool _isResolving = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ensureUserLinked();
  }

  Future<void> _ensureUserLinked() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isResolving = false);
      return;
    }

    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final docSnap = await docRef.get();
      if (docSnap.exists) {
        if (mounted) setState(() => _isResolving = false);
        return;
      }

      // Check by email or phone
      QuerySnapshot<Map<String, dynamic>>? querySnap;
      if (user.email != null && user.email!.isNotEmpty) {
        querySnap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email!.toLowerCase())
            .limit(1)
            .get();
      }

      if ((querySnap == null || querySnap.docs.isEmpty) && user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        querySnap = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: user.phoneNumber)
            .limit(1)
            .get();
      }

      if (querySnap != null && querySnap.docs.isNotEmpty) {
        final existingDoc = querySnap.docs.first;
        final existingData = existingDoc.data();
        String assignedRole = existingData['role'] ?? 'RESIDENT';
        if (assignedRole == 'Owner' || assignedRole == 'Resident') {
          assignedRole = 'RESIDENT';
        }

        await docRef.set({
          ...existingData,
          'uid': user.uid,
          'role': assignedRole,
        });
        await existingDoc.reference.delete();
      } else if (user.email != null && user.email!.endsWith('@ramkrishnapuram.com')) {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          setState(() {
            _error = 'This account or flat has been deleted by the Admin.';
            _isResolving = false;
          });
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isResolving) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const CustomAuthScreen();
    }

    // Real-time synchronization stream for User Profile & Role from Firestore backend
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Error: ${snapshot.error}')));
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // Document was deleted from backend or not yet created
          return const ProfileSetupScreen();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final role = data['role'] as String?;
        final userFlat = (data['flatNumber'] ?? '').toString().trim().toUpperCase();
        final blockStr = (data['block'] ?? '').toString().trim().toUpperCase();
        final fullFlat = (blockStr.isNotEmpty && !userFlat.startsWith(blockStr))
            ? '$blockStr-$userFlat'
            : userFlat;

        // Initialize real-time in-app push notifications for this authenticated session
        PushNotificationManager.instance.startListening(
          user: user,
          role: role,
          flatNumber: fullFlat.isNotEmpty ? fullFlat : userFlat,
        );

        // Role authorization check for current app flavor
        if (!AppFlavorConfig.current.isRoleAllowed(role)) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.no_accounts_rounded, size: 54, color: Colors.amber),
                          const SizedBox(height: 16),
                          const Text(
                            'Different App Required',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'You are logged in with role "$role", but this is the ${AppFlavorConfig.current.appTitle}.\n\nPlease launch the appropriate app target for your role, or log in with an authorized account.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: const Text('Sign Out'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => FirebaseAuth.instance.signOut(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        if (role == 'RESIDENT') return const ResidentDashboard();
        if (role == 'GUARD') return const GuardDashboard();
        if (role == 'ADMIN') return const AdminDashboard();

        return const ProfileSetupScreen();
      },
    );
  }
}

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _flatController = TextEditingController();
  bool _isLoading = false;

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    
    try {
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'uid': user.uid,
        'name': _nameController.text.trim(),
        'phone': user.phoneNumber ?? '',
        'email': user.email ?? '',
        'role': 'RESIDENT',
        'flatNumber': _flatController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // Force rebuild to route to the correct dashboard
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RoleRouter()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Profile'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 24.0),
                child: Text(
                  'Welcome! Please provide your details to register as a Resident.',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
                validator: (value) => value!.isEmpty ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _flatController,
                decoration: const InputDecoration(labelText: 'Flat / Villa Number'),
                validator: (value) => value!.isEmpty ? 'Please enter your flat number' : null,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                child: _isLoading 
                    ? const CircularProgressIndicator()
                    : const Text('Save & Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Dashboards ----------------

// AdminDashboard moved to lib/screens/admin/admin_dashboard.dart
