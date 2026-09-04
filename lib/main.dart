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
      title: 'Society Management',
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
        
        return SignInScreen(
          headerBuilder: (context, constraints, shrinkOffset) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Society Management',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
              ),
            );
          },
          subtitleBuilder: (context, action) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: action == AuthAction.signIn
                  ? const Text('Welcome to your community! Please sign in.')
                  : const Text('Welcome to your community! Please sign up.'),
            );
          },
        );
      },
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
        setState(() {
          _role = data['role'] as String?;
          _isLoading = false;
        });
        return;
      }

      // 2. Not found by uid. Let's check by phone number.
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        var querySnap = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: user.phoneNumber)
            .limit(1)
            .get();

        if (querySnap.docs.isNotEmpty) {
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
      }

      // 3. User is completely new. Route to ProfileSetup
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
          IconButton(
            icon: const Icon(Icons.logout),
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
