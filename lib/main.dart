import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider, PhoneAuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'firebase_options.dart';
import 'screens/resident/resident_dashboard.dart';
import 'screens/guard/guard_dashboard.dart';
import 'screens/admin/admin_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  FirebaseUIAuth.configureProviders([
    EmailAuthProvider(),
    PhoneAuthProvider(),
  ]);
  
  runApp(const SocietyManagementApp());
}

class SocietyManagementApp extends StatelessWidget {
  const SocietyManagementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ramkrishnapuram RWA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

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

      // 1. Try direct Firebase Auth sign-in first
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: targetAuthEmail,
          password: password,
        );
        return;
      } catch (authError) {
        // If direct email failed and input contains '@', try lookup by personal email in Firestore
        if (cleanInput.contains('@')) {
          try {
            final snapByEmail = await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: cleanInput)
                .get();

            if (snapByEmail.docs.isNotEmpty) {
              final data = snapByEmail.docs.first.data();
              final username = data['username']?.toString();
              if (username != null && username.isNotEmpty && username != cleanInput) {
                await FirebaseAuth.instance.signInWithEmailAndPassword(
                  email: username,
                  password: password,
                );
                return;
              }
            }
          } catch (_) {
            // Unauthenticated Firestore read rules will be bypassed gracefully
          }
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

      // Check if custom email exists for this user in Firestore to send reset email there
      try {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: targetEmail)
            .get();

        if (userSnap.docs.isNotEmpty) {
          final data = userSnap.docs.first.data();
          final personalEmail = data['email']?.toString();
          if (personalEmail != null && personalEmail.contains('@')) {
            targetEmail = personalEmail;
          }
        }
      } catch (_) {}

      await FirebaseAuth.instance.sendPasswordResetEmail(email: targetEmail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset email sent to $targetEmail! Check your inbox.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.apartment, size: 64, color: Colors.teal),
                      const SizedBox(height: 12),
                      const Text(
                        'Ramkrishnapuram RWA',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Welcome back! Sign in to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Username / Email Address',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
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
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible;
                              });
                            },
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _resetPassword,
                          child: const Text('Forgot Password?'),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
  bool _isLoading = true;
  String? _error;
  String? _role;

  @override
  void initState() {
    super.initState();
    _determineRole();
  }

  Future<void> _determineRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Check if a document with ID = user.uid exists
      var docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var docSnap = await docRef.get();

      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        final role = data['role'] as String?;
        final flatNum = data['flatNumber']?.toString().trim() ?? '';

        if (role == 'RESIDENT' && flatNum.isNotEmpty) {
          final cleanFlatNum = flatNum.trim().toLowerCase();
          final flatDoc = await FirebaseFirestore.instance.collection('flats').doc(flatNum).get();
          final allFlatsSnap = await FirebaseFirestore.instance.collection('flats').get();
          final flatExists = flatDoc.exists ||
              allFlatsSnap.docs.any((d) => d.id.trim().toLowerCase() == cleanFlatNum);

          if (!flatExists) {
            // Flat has been deleted by Admin! Delete user doc, sign out, and block access
            await docRef.delete();
            await FirebaseAuth.instance.signOut();
            if (mounted) {
              setState(() {
                _error = 'This flat has been deleted by the Admin. Access revoked.';
                _isLoading = false;
              });
            }
            return;
          }
        }

        setState(() {
          _role = role;
          _isLoading = false;
        });
        return;
      }

      // 2. Not found by uid. Let's check by email or phone number.
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
        // Found the record admin created. Link it to this UID.
        final existingDoc = querySnap.docs.first;
        final existingData = existingDoc.data();
          
          // Normalize role for dashboard routing
          String assignedRole = existingData['role'] ?? 'RESIDENT';
          if (assignedRole == 'Owner' || assignedRole == 'Resident') {
            assignedRole = 'RESIDENT';
          }
          
          // Re-create the document with doc ID = user.uid and delete the old one
          await docRef.set({
            ...existingData,
            'uid': user.uid,
            'role': assignedRole,
          });
          await existingDoc.reference.delete();

          if (mounted) {
            setState(() {
              _role = assignedRole;
              _isLoading = false;
            });
          }
          return;
        }

      // 3. User is completely new or deleted.
      if (user.email != null && user.email!.endsWith('@ramkrishnapuram.com')) {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          setState(() {
            _error = 'This account or flat has been deleted by the Admin.';
            _isLoading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(body: Center(child: Text('Error: $_error')));
    }

    if (_role == 'RESIDENT') return const ResidentDashboard();
    if (_role == 'GUARD') return const GuardDashboard();
    if (_role == 'ADMIN') return const AdminDashboard();

    // Default or null role -> needs profile setup
    return const ProfileSetupScreen();
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
