import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../models/accounting_heads.dart';
import 'tabs/community_feed_tab.dart';
import '../../utils/storage_utils.dart';
import '../../widgets/document_preview_dialog.dart';

class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final pages = [
      const HomeTab(),
      const CommunityFeedTab(),
      NotificationsTab(
        onNavigateTab: (idx) => setState(() => _currentIndex = idx),
      ),
      const ResidentHelpdeskTab(),
      const MaintenanceTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resident Dashboard'),
        actions: [
          if (user != null)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('targetUid', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snap) {
                final count = snap.data?.docs.length ?? 0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications),
                      tooltip: 'Alerts',
                      onPressed: () => setState(() => _currentIndex = 2),
                    ),
                    if (count > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          TextButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'Community'),
          BottomNavigationBarItem(
            icon: user != null
                ? StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('notifications')
                        .where('targetUid', isEqualTo: user.uid)
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return Badge(
                        isLabelVisible: count > 0,
                        label: Text('$count'),
                        child: const Icon(Icons.notifications),
                      );
                    },
                  )
                : const Icon(Icons.notifications),
            label: 'Alerts',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.support_agent), label: 'Helpdesk'),
          const BottomNavigationBarItem(icon: Icon(Icons.payment), label: 'Maintenance'),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PreApproveVisitorScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Pre-approve Visitor'),
            )
          : null,
    );
  }
}

Future<DocumentReference?> _resolveUserDocRef(String uid, String? userEmail, String? flatPrefix) async {
  final usersRef = FirebaseFirestore.instance.collection('users');

  // 1. Direct doc by UID
  final directDoc = await usersRef.doc(uid).get();
  if (directDoc.exists) return usersRef.doc(uid);

  // 2. Query by email
  if (userEmail != null && userEmail.isNotEmpty) {
    final emailSnap = await usersRef.where('email', isEqualTo: userEmail).limit(1).get();
    if (emailSnap.docs.isNotEmpty) return emailSnap.docs.first.reference;
  }

  // 3. Query by flatPrefix / flatNumber
  if (flatPrefix != null && flatPrefix.isNotEmpty) {
    final flatSnap = await usersRef.where('flatNumber', isEqualTo: flatPrefix.toUpperCase()).limit(1).get();
    if (flatSnap.docs.isNotEmpty) return flatSnap.docs.first.reference;

    final docByFlat = await usersRef.doc(flatPrefix.toUpperCase()).get();
    if (docByFlat.exists) return usersRef.doc(flatPrefix.toUpperCase());
  }

  return usersRef.doc(uid);
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // Store the future so it's computed ONCE and never re-runs on rebuild
  late Future<DocumentReference?> _docRefFuture;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userEmail = user.email?.toLowerCase();
      final flatPrefix = userEmail?.contains('@') == true
          ? userEmail!.split('@').first.toLowerCase()
          : null;
      _docRefFuture = _resolveUserDocRef(user.uid, userEmail, flatPrefix);
    } else {
      _docRefFuture = Future.value(null);
    }
  }

  Future<void> _editDetailsDialog(BuildContext context, String docId, Map<String, dynamic> data) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();

    // Calculate flat vehicle quota across other members of this flat
    final flatId = data['flatNumber']?.toString() ?? '';
    int flatOtherCars = 0;
    int flatOtherBikes = 0;
    try {
      final querySnap = await FirebaseFirestore.instance
          .collection('users')
          .where('flatNumber', isEqualTo: flatId)
          .get();
      for (final doc in querySnap.docs) {
        if (doc.id == docId) continue;
        final d = doc.data();
        if (d['isCarOwner'] == true && (d['carReg']?.toString().trim().isNotEmpty ?? false)) {
          flatOtherCars++;
        } else if (d['pendingCarReg']?.toString().trim().isNotEmpty ?? false) {
          flatOtherCars++;
        }
        if (d['isBikeOwner'] == true && (d['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
          flatOtherBikes++;
        } else if (d['pendingBikeReg']?.toString().trim().isNotEmpty ?? false) {
          flatOtherBikes++;
        }
        if (d['hasBike2'] == true && (d['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
          flatOtherBikes++;
        } else if (d['pendingBike2Reg']?.toString().trim().isNotEmpty ?? false) {
          flatOtherBikes++;
        }
      }
    } catch (e) {
      debugPrint('Error calculating flat vehicle quota: $e');
    }

    final bool canAddCar = flatOtherCars < 1;
    final int maxBikesAddable = 2 - flatOtherBikes;

    String rawPhone = data['phone']?.toString() ?? '';
    if (rawPhone.startsWith('+91')) rawPhone = rawPhone.substring(3);

    final mobileCtrl = TextEditingController(text: rawPhone);
    final waCtrl = TextEditingController(text: data['whatsapp']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: data['email']?.toString() ?? '');

    final pendingCarReg = data['pendingCarReg']?.toString().trim() ?? '';
    final pendingBikeReg = data['pendingBikeReg']?.toString().trim() ?? '';
    final pendingBike2Reg = data['pendingBike2Reg']?.toString().trim() ?? '';

    bool isCarOwner = data['isCarOwner'] == true || pendingCarReg.isNotEmpty;
    bool isBikeOwner = data['isBikeOwner'] == true || pendingBikeReg.isNotEmpty;
    bool hasBike2 = data['hasBike2'] == true || pendingBike2Reg.isNotEmpty;

    final currentCarReg = data['carReg']?.toString().trim() ?? '';
    final currentBikeReg = data['bikeReg']?.toString().trim() ?? '';
    final currentBike2Reg = data['bike2Reg']?.toString().trim() ?? '';

    final carRegCtrl = TextEditingController(
        text: currentCarReg.isNotEmpty ? currentCarReg : pendingCarReg);
    final bikeRegCtrl = TextEditingController(
        text: currentBikeReg.isNotEmpty ? currentBikeReg : pendingBikeReg);
    final bike2RegCtrl = TextEditingController(
        text: currentBike2Reg.isNotEmpty ? currentBike2Reg : pendingBike2Reg);

    PlatformFile? carRcFile;
    PlatformFile? bikeRcFile;
    PlatformFile? bike2RcFile;
    bool isSaving = false;

    Future<String?> uploadRcDoc(PlatformFile file, String prefix) async {
      final fileName = file.name;
      return uploadFile(
        file,
        'vehicle_rc/${prefix}_${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit_note, color: Colors.teal),
              SizedBox(width: 8),
              Text('Edit My Details'),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contact Information',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: mobileCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number *',
                        prefixIcon: Icon(Icons.phone),
                        prefixText: '+91 ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Mobile number is required';
                        if (val.length != 10 || !RegExp(r'^[0-9]+$').hasMatch(val)) {
                          return 'Enter a valid 10-digit number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: waCtrl,
                      decoration: const InputDecoration(
                        labelText: 'WhatsApp Number *',
                        prefixIcon: Icon(Icons.chat),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'WhatsApp number is required';
                        if (val.length != 10 || !RegExp(r'^[0-9]+$').hasMatch(val)) {
                          return 'Enter a valid 10-digit number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Email is required';
                        if (!val.contains('@')) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 4),
                    const Text(
                      'Vehicle Details (Max 1 Car & 2 Bikes per Flat)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Note: Updating vehicle numbers requires uploading RC/Blue Book copy for Admin approval.',
                      style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),
                    if (!canAddCar && !isCarOwner)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.red),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'This flat already has 1 Car assigned (Quota full).',
                                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Do you own a 4-Wheeler (Car)?'),
                      secondary: const Icon(Icons.directions_car, color: Colors.teal),
                      value: isCarOwner,
                      activeThumbColor: Colors.teal,
                      onChanged: (canAddCar || isCarOwner)
                          ? (val) {
                              setDS(() => isCarOwner = val);
                            }
                          : null,
                    ),
                    if (isCarOwner) ...[
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: carRegCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Car Registration No. *',
                          hintText: 'e.g. WB 02 AB 1234',
                          prefixIcon: Icon(Icons.pin),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) {
                          if (isCarOwner && (v == null || v.trim().isEmpty)) {
                            return 'Please enter car registration number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      // RC upload button for Car if reg changed or newly added
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.upload_file, size: 20, color: Colors.teal),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Upload Car RC / Blue Book Copy *',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.attach_file, size: 16),
                                  label: Text(carRcFile == null ? 'Select File' : 'Change'),
                                  onPressed: () async {
                                    final file = await pickFile();
                                    if (file != null) {
                                      setDS(() => carRcFile = file);
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (carRcFile != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Selected: ${carRcFile!.name}',
                                  style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                                ),
                              )
                            else if (data['pendingCarReg'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Pending approval: ${data['pendingCarReg']}',
                                  style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (maxBikesAddable <= 0 && !isBikeOwner)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.red),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'This flat already has 2 Bikes assigned (Quota full).',
                                  style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Do you own a 2-Wheeler (Bike/Scooter)?'),
                      secondary: const Icon(Icons.two_wheeler, color: Colors.teal),
                      value: isBikeOwner,
                      activeThumbColor: Colors.teal,
                      onChanged: (maxBikesAddable > 0 || isBikeOwner)
                          ? (val) {
                              setDS(() {
                                isBikeOwner = val;
                                if (!val) hasBike2 = false;
                              });
                            }
                          : null,
                    ),
                    if (isBikeOwner) ...[
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: bikeRegCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Bike 1 Registration No. *',
                          hintText: 'e.g. WB 02 CD 5678',
                          prefixIcon: Icon(Icons.pin),
                          border: OutlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) {
                          if (isBikeOwner && (v == null || v.trim().isEmpty)) {
                            return 'Please enter bike registration number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      // RC upload button for Bike 1
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.upload_file, size: 20, color: Colors.teal),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Upload Bike 1 RC / Blue Book Copy *',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.attach_file, size: 16),
                                  label: Text(bikeRcFile == null ? 'Select File' : 'Change'),
                                  onPressed: () async {
                                    final file = await pickFile();
                                    if (file != null) {
                                      setDS(() => bikeRcFile = file);
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (bikeRcFile != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Selected: ${bikeRcFile!.name}',
                                  style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                                ),
                              )
                            else if (data['pendingBikeReg'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Pending approval: ${data['pendingBikeReg']}',
                                  style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!hasBike2 && maxBikesAddable >= 1)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.teal),
                            label: const Text(
                              'Add Another Bike (Max 2)',
                              style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600),
                            ),
                            onPressed: () => setDS(() => hasBike2 = true),
                          ),
                        ),
                      if (hasBike2) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: bike2RegCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Bike 2 Registration No. *',
                                  hintText: 'e.g. WB 02 EF 9012',
                                  prefixIcon: Icon(Icons.pin),
                                  border: OutlineInputBorder(),
                                ),
                                textCapitalization: TextCapitalization.characters,
                                validator: (v) {
                                  if (isBikeOwner && hasBike2 && (v == null || v.trim().isEmpty)) {
                                    return 'Please enter Bike 2 registration number';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.remove_circle, color: Colors.red),
                              tooltip: 'Remove Bike 2',
                              onPressed: () {
                                setDS(() {
                                  hasBike2 = false;
                                  bike2RegCtrl.clear();
                                  bike2RcFile = null;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.teal.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.upload_file, size: 20, color: Colors.teal),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Upload Bike 2 RC / Blue Book Copy *',
                                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.attach_file, size: 16),
                                    label: Text(bike2RcFile == null ? 'Select File' : 'Change'),
                                    onPressed: () async {
                                      final file = await pickFile();
                                      if (file != null) {
                                        setDS(() => bike2RcFile = file);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              if (bike2RcFile != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Selected: ${bike2RcFile!.name}',
                                    style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                                  ),
                                )
                              else if (data['pendingBike2Reg'] != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Pending approval: ${data['pendingBike2Reg']}',
                                    style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;

                      final newCarReg = isCarOwner ? carRegCtrl.text.trim().toUpperCase() : '';
                      final newBikeReg = isBikeOwner ? bikeRegCtrl.text.trim().toUpperCase() : '';
                      final newBike2Reg = (isBikeOwner && hasBike2) ? bike2RegCtrl.text.trim().toUpperCase() : '';

                      final existingPendingCar = data['pendingCarReg']?.toString().trim() ?? '';
                      final isNewCarSubmission = newCarReg.isNotEmpty && (newCarReg != currentCarReg || carRcFile != null);
                      final carChanged = isNewCarSubmission && (newCarReg != existingPendingCar || carRcFile != null);

                      final existingPendingBike = data['pendingBikeReg']?.toString().trim() ?? '';
                      final isNewBikeSubmission = newBikeReg.isNotEmpty && (newBikeReg != currentBikeReg || bikeRcFile != null);
                      final bikeChanged = isNewBikeSubmission && (newBikeReg != existingPendingBike || bikeRcFile != null);

                      final existingPendingBike2 = data['pendingBike2Reg']?.toString().trim() ?? '';
                      final isNewBike2Submission = newBike2Reg.isNotEmpty && (newBike2Reg != currentBike2Reg || bike2RcFile != null);
                      final bike2Changed = isNewBike2Submission && (newBike2Reg != existingPendingBike2 || bike2RcFile != null);

                      if (carChanged && carRcFile == null && data['pendingCarRcUrl'] == null) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Please upload RC / Blue Book copy for Car update.')),
                        );
                        return;
                      }
                      if (bikeChanged && bikeRcFile == null && data['pendingBikeRcUrl'] == null) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Please upload RC / Blue Book copy for Bike 1 update.')),
                        );
                        return;
                      }
                      if (bike2Changed && bike2RcFile == null && data['pendingBike2RcUrl'] == null) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Please upload RC / Blue Book copy for Bike 2 update.')),
                        );
                        return;
                      }

                      // Quota enforcement
                      if (isCarOwner && !canAddCar && currentCarReg.isEmpty && (data['pendingCarReg'] == null || data['pendingCarReg'].toString().isEmpty)) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Cannot add Car: Flat quota of 1 car already reached.')),
                        );
                        return;
                      }
                      int requestedBikes = (isBikeOwner ? 1 : 0) + ((isBikeOwner && hasBike2) ? 1 : 0);
                      if (flatOtherBikes + requestedBikes > 2) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Cannot exceed flat quota of 2 bikes.')),
                        );
                        return;
                      }

                      setDS(() => isSaving = true);
                      try {
                        final updatePayload = <String, dynamic>{
                          'phone': '+91${mobileCtrl.text.trim()}',
                          'whatsapp': waCtrl.text.trim(),
                          'email': emailCtrl.text.trim().toLowerCase(),
                        };

                        final residentName = data['name'] ?? 'Resident';
                        final flatNum = data['flatNumber'] ?? 'Unknown Flat';
                        final blockStr = data['block'] ?? '';
                        final flatDisplay = blockStr.isNotEmpty && !flatNum.toString().contains('-')
                            ? '$blockStr-$flatNum'
                            : flatNum.toString();

                        if (!isCarOwner) {
                          updatePayload['isCarOwner'] = false;
                          updatePayload['carReg'] = '';
                          updatePayload['pendingCarReg'] = FieldValue.delete();
                          updatePayload['pendingCarRcUrl'] = FieldValue.delete();
                          updatePayload['pendingCarRcFileName'] = FieldValue.delete();
                          updatePayload['carRejectionReason'] = FieldValue.delete();
                        } else if (carChanged) {
                          String? carRcUrl;
                          if (carRcFile != null) {
                            carRcUrl = await uploadRcDoc(carRcFile!, 'car');
                          }
                          updatePayload['pendingCarReg'] = newCarReg;
                          if (carRcUrl != null) {
                            updatePayload['pendingCarRcUrl'] = carRcUrl;
                            updatePayload['pendingCarRcFileName'] = carRcFile!.name;
                          }
                          updatePayload['carRejectionReason'] = FieldValue.delete();

                          // Notify admin
                          await FirebaseFirestore.instance.collection('notifications').add({
                            'targetRole': 'ADMIN',
                            'type': 'VEHICLE_UPDATE_REQUEST',
                            'title': 'Car Number Update Request',
                            'message': '$residentName ($flatDisplay) requested to update Car number to $newCarReg with RC copy.',
                            'flatNumber': flatDisplay,
                            'userId': docId,
                            'vehicleType': 'Car',
                            'requestedReg': newCarReg,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                        }

                        if (!isBikeOwner) {
                          updatePayload['isBikeOwner'] = false;
                          updatePayload['bikeReg'] = '';
                          updatePayload['pendingBikeReg'] = FieldValue.delete();
                          updatePayload['pendingBikeRcUrl'] = FieldValue.delete();
                          updatePayload['pendingBikeRcFileName'] = FieldValue.delete();
                          updatePayload['bikeRejectionReason'] = FieldValue.delete();

                          updatePayload['hasBike2'] = false;
                          updatePayload['bike2Reg'] = '';
                          updatePayload['pendingBike2Reg'] = FieldValue.delete();
                          updatePayload['pendingBike2RcUrl'] = FieldValue.delete();
                          updatePayload['pendingBike2RcFileName'] = FieldValue.delete();
                          updatePayload['bike2RejectionReason'] = FieldValue.delete();
                        } else {
                          if (bikeChanged) {
                            String? bikeRcUrl;
                            if (bikeRcFile != null) {
                              bikeRcUrl = await uploadRcDoc(bikeRcFile!, 'bike');
                            }
                            updatePayload['pendingBikeReg'] = newBikeReg;
                            if (bikeRcUrl != null) {
                              updatePayload['pendingBikeRcUrl'] = bikeRcUrl;
                              updatePayload['pendingBikeRcFileName'] = bikeRcFile!.name;
                            }
                            updatePayload['bikeRejectionReason'] = FieldValue.delete();

                            // Notify admin
                            await FirebaseFirestore.instance.collection('notifications').add({
                              'targetRole': 'ADMIN',
                              'type': 'VEHICLE_UPDATE_REQUEST',
                              'title': 'Bike 1 Number Update Request',
                              'message': '$residentName ($flatDisplay) requested to update Bike 1 number to $newBikeReg with RC copy.',
                              'flatNumber': flatDisplay,
                              'userId': docId,
                              'vehicleType': 'Bike 1',
                              'requestedReg': newBikeReg,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }

                          if (!hasBike2) {
                            updatePayload['hasBike2'] = false;
                            updatePayload['bike2Reg'] = '';
                            updatePayload['pendingBike2Reg'] = FieldValue.delete();
                            updatePayload['pendingBike2RcUrl'] = FieldValue.delete();
                            updatePayload['pendingBike2RcFileName'] = FieldValue.delete();
                            updatePayload['bike2RejectionReason'] = FieldValue.delete();
                          } else if (bike2Changed) {
                            String? bike2RcUrl;
                            if (bike2RcFile != null) {
                              bike2RcUrl = await uploadRcDoc(bike2RcFile!, 'bike2');
                            }
                            updatePayload['hasBike2'] = true;
                            updatePayload['pendingBike2Reg'] = newBike2Reg;
                            if (bike2RcUrl != null) {
                              updatePayload['pendingBike2RcUrl'] = bike2RcUrl;
                              updatePayload['pendingBike2RcFileName'] = bike2RcFile!.name;
                            }
                            updatePayload['bike2RejectionReason'] = FieldValue.delete();

                            // Notify admin
                            await FirebaseFirestore.instance.collection('notifications').add({
                              'targetRole': 'ADMIN',
                              'type': 'VEHICLE_UPDATE_REQUEST',
                              'title': 'Bike 2 Number Update Request',
                              'message': '$residentName ($flatDisplay) requested to update Bike 2 number to $newBike2Reg with RC copy.',
                              'flatNumber': flatDisplay,
                              'userId': docId,
                              'vehicleType': 'Bike 2',
                              'requestedReg': newBike2Reg,
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                          }
                        }

                        // If user only checked isCarOwner/isBikeOwner without reg change
                        if (isCarOwner && !carChanged && data['carReg'] == null) {
                          updatePayload['isCarOwner'] = true;
                          updatePayload['carReg'] = newCarReg;
                        }
                        if (isBikeOwner && !bikeChanged && data['bikeReg'] == null) {
                          updatePayload['isBikeOwner'] = true;
                          updatePayload['bikeReg'] = newBikeReg;
                        }

                        await FirebaseFirestore.instance.collection('users').doc(docId).update(updatePayload);

                        if (ctx.mounted) Navigator.pop(ctx);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              carChanged || bikeChanged || bike2Changed
                                  ? 'Details saved! Vehicle update submitted for Admin approval.'
                                  : 'Details updated successfully!',
                            ),
                          ),
                        );
                      } catch (e) {
                        setDS(() => isSaving = false);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('Failed to update details: $e')),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('No logged in user'));
    }

    return FutureBuilder<DocumentReference?>(
      future: _docRefFuture, // use stored future — never re-runs on rebuild
      builder: (context, futureSnap) {
        if (futureSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docRef = futureSnap.data;
        if (docRef == null) {
          return _buildHomeLayout(context, null, null);
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: docRef.snapshots(),
          builder: (context, docSnap) {
            if (docSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!docSnap.hasData || !docSnap.data!.exists) {
              return _buildHomeLayout(context, null, null);
            }
            final doc = docSnap.data!;
            return _buildHomeLayout(context, doc.id, doc.data() as Map<String, dynamic>);
          },
        );
      },
    );
  }

  /// One-time async lookup: finds the user's Firestore document reference via uid,
  /// username, email, or flat-prefix document ID. Also writes the uid back to the
  /// document so future lookups always use the fast uid path.
  Future<DocumentReference?> _resolveUserDocRef(
    String uid,
    String? userEmail,
    String? flatPrefix,
  ) async {
    final fs = FirebaseFirestore.instance;

    // 1. Try uid field match
    final uidSnap = await fs.collection('users').where('uid', isEqualTo: uid).limit(1).get();
    if (uidSnap.docs.isNotEmpty) return uidSnap.docs.first.reference;

    if (userEmail == null) return null;

    // 2. Try username == userEmail (flat email like b-312@ramkrishnapuram.com)
    final usernameSnap =
        await fs.collection('users').where('username', isEqualTo: userEmail).limit(1).get();
    if (usernameSnap.docs.isNotEmpty) {
      final ref = usernameSnap.docs.first.reference;
      ref.update({'uid': uid}).catchError((_) {});
      return ref;
    }

    // 3. Try email == userEmail (personal email)
    final emailSnap =
        await fs.collection('users').where('email', isEqualTo: userEmail).limit(1).get();
    if (emailSnap.docs.isNotEmpty) {
      final ref = emailSnap.docs.first.reference;
      ref.update({'uid': uid}).catchError((_) {});
      return ref;
    }

    // 4. Try document ID == flatPrefix (e.g. "b-312")
    if (flatPrefix != null) {
      final docSnap = await fs.collection('users').doc(flatPrefix).get();
      if (docSnap.exists) {
        docSnap.reference.update({'uid': uid}).catchError((_) {});
        return docSnap.reference;
      }
    }

    return null;
  }

  Widget _buildHomeLayout(BuildContext context, String? docId, Map<String, dynamic>? data) {
    final name = data?['name'] ?? 'Resident';
    final flatNumber = data?['flatNumber'] ?? 'N/A';
    final block = data?['block'] ?? '';
    final flatLabel = block.isNotEmpty && !flatNumber.toString().contains('-')
        ? '$block-$flatNumber'
        : flatNumber.toString();
    final role = (data?['isRentee'] == true || data?['occupantType'] == 'Rentee')
        ? 'Rentee'
        : 'Owner';
    final mobile = data?['phone'] ?? 'N/A';
    final whatsapp = data?['whatsapp'] ?? 'N/A';
    final email = data?['email'] ?? 'N/A';
    final bool isCarOwner = data?['isCarOwner'] == true;
    final String carReg = data?['carReg']?.toString().trim() ?? '';
    final bool isBikeOwner = data?['isBikeOwner'] == true;
    final String bikeReg = data?['bikeReg']?.toString().trim() ?? '';
    final bool hasBike2 = data?['hasBike2'] == true;
    final String bike2Reg = data?['bike2Reg']?.toString().trim() ?? '';

    final String? pendingCarReg = data?['pendingCarReg']?.toString().trim();
    final String? pendingCarRcUrl = data?['pendingCarRcUrl']?.toString();
    final String? carRejectionReason = data?['carRejectionReason']?.toString();

    final String? pendingBikeReg = data?['pendingBikeReg']?.toString().trim();
    final String? pendingBikeRcUrl = data?['pendingBikeRcUrl']?.toString();
    final String? bikeRejectionReason = data?['bikeRejectionReason']?.toString();

    final String? pendingBike2Reg = data?['pendingBike2Reg']?.toString().trim();
    final String? pendingBike2RcUrl = data?['pendingBike2RcUrl']?.toString();
    final String? bike2RejectionReason = data?['bike2RejectionReason']?.toString();

    void showRcDocDialog(String url, String title) {
      showDocumentPreviewDialog(context, url, title);
    }

    String vehicleSummary;
    final hasAnyBike = isBikeOwner || hasBike2 || (pendingBike2Reg != null && pendingBike2Reg.isNotEmpty);
    if (isCarOwner && hasAnyBike) {
      vehicleSummary = 'Both (4-Wheeler & 2-Wheeler)';
    } else if (isCarOwner) {
      vehicleSummary = 'Car (4-Wheeler)';
    } else if (hasAnyBike) {
      vehicleSummary = 'Bike (2-Wheeler)';
    } else {
      vehicleSummary = 'None';
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 3,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.teal.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.teal,
                          child: Icon(
                            role == 'Rentee' ? Icons.key : Icons.home,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Flat: $flatLabel • $role',
                              style: TextStyle(color: Colors.teal.shade900),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (docId != null && data != null)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.teal),
                        onPressed: () => _editDetailsDialog(context, docId, data),
                        tooltip: 'Edit My Details',
                      ),
                  ],
                ),
                const Divider(height: 24),
                const Text(
                  'Contact Information',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Text('Mobile: $mobile'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.chat, size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Text('WhatsApp: $whatsapp'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.email, size: 18, color: Colors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Email: $email',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Registered Vehicles',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        vehicleSummary,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!isCarOwner && !isBikeOwner && !hasBike2 && (pendingCarReg == null || pendingCarReg.isEmpty) && (pendingBikeReg == null || pendingBikeReg.isEmpty) && (pendingBike2Reg == null || pendingBike2Reg.isEmpty))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      'No vehicles registered yet.',
                      style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic),
                    ),
                  )
                else ...[
                  if (isCarOwner || (pendingCarReg != null && pendingCarReg.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.directions_car, size: 18, color: Colors.teal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Car: ${carReg.isNotEmpty ? carReg : "Registered (No Reg. No.)"}',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      if (pendingCarReg != null && pendingCarReg.isNotEmpty)
                                        const TextSpan(
                                          text: ' (Update pending Admin approval)',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pendingCarReg != null && pendingCarReg.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 2),
                              child: Row(
                                children: [
                                  Text(
                                    'Requested: $pendingCarReg',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                  ),
                                  if (pendingCarRcUrl != null) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => showRcDocDialog(pendingCarRcUrl, 'Car RC / Blue Book'),
                                      child: const Text(
                                        'View Uploaded RC',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.teal,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (carRejectionReason != null && carRejectionReason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Last request rejected: $carRejectionReason',
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (isBikeOwner || (pendingBikeReg != null && pendingBikeReg.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.two_wheeler, size: 18, color: Colors.teal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Bike 1: ${bikeReg.isNotEmpty ? bikeReg : "Registered (No Reg. No.)"}',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      if (pendingBikeReg != null && pendingBikeReg.isNotEmpty)
                                        const TextSpan(
                                          text: ' (Update pending Admin approval)',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pendingBikeReg != null && pendingBikeReg.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 2),
                              child: Row(
                                children: [
                                  Text(
                                    'Requested: $pendingBikeReg',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                  ),
                                  if (pendingBikeRcUrl != null) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => showRcDocDialog(pendingBikeRcUrl, 'Bike 1 RC / Blue Book'),
                                      child: const Text(
                                        'View Uploaded RC',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.teal,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (bikeRejectionReason != null && bikeRejectionReason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Last request rejected: $bikeRejectionReason',
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (hasBike2 || (pendingBike2Reg != null && pendingBike2Reg.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.two_wheeler, size: 18, color: Colors.teal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: 'Bike 2: ${bike2Reg.isNotEmpty ? bike2Reg : "Registered (No Reg. No.)"}',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      if (pendingBike2Reg != null && pendingBike2Reg.isNotEmpty)
                                        const TextSpan(
                                          text: ' (Update pending Admin approval)',
                                          style: TextStyle(
                                            color: Colors.orange,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (pendingBike2Reg != null && pendingBike2Reg.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 2),
                              child: Row(
                                children: [
                                  Text(
                                    'Requested: $pendingBike2Reg',
                                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                  ),
                                  if (pendingBike2RcUrl != null) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => showRcDocDialog(pendingBike2RcUrl, 'Bike 2 RC / Blue Book'),
                                      child: const Text(
                                        'View Uploaded RC',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.teal,
                                          decoration: TextDecoration.underline,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (bike2RejectionReason != null && bike2RejectionReason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 26, top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  'Last request rejected: $bike2RejectionReason',
                                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.security, size: 40, color: Colors.teal),
            title: Text('Gate Pass System'),
            subtitle: Text('Manage your visitors securely.'),
          ),
        ),
      ],
    );
  }
}

class NotificationsTab extends StatelessWidget {
  final Function(int)? onNavigateTab;
  const NotificationsTab({super.key, this.onNavigateTab});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userUid = user?.uid ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (userUid.isNotEmpty) ...[
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('targetUid', isEqualTo: userUid)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('Error loading alerts: ${snap.error}',
                    style: const TextStyle(color: Colors.red));
              }
              final docs = (snap.data?.docs ?? []).toList();
              // Sort in memory by createdAt descending
              docs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = (aData['createdAt'] as Timestamp?)?.toDate() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final bTime = (bData['createdAt'] as Timestamp?)?.toDate() ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return bTime.compareTo(aTime);
              });

              if (docs.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active,
                          color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Personal Alerts (${docs.length})',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...docs.map((doc) {
                    final notif = doc.data() as Map<String, dynamic>;
                    final title = notif['title'] ?? 'Notification';
                    final msg = notif['message'] ?? '';
                    final type =
                        (notif['type'] ?? '').toString().toUpperCase();

                    final isApproved = type == 'VEHICLE_APPROVED';
                    final isRejected = type == 'VEHICLE_REJECTED';
                    final isVehicle =
                        isApproved || isRejected || type.contains('VEHICLE');
                    final isComplaint = type.contains('COMPLAINT');
                    final isMaintenance =
                        type.contains('MAINTENANCE') || type.contains('PAYMENT');

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isApproved
                              ? Colors.green.shade200
                              : isRejected
                                  ? Colors.red.shade200
                                  : Colors.teal.shade200,
                        ),
                      ),
                      color: isApproved
                          ? Colors.green.shade50
                          : isRejected
                              ? Colors.red.shade50
                              : Colors.teal.shade50,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isApproved
                              ? Colors.green.shade100
                              : isRejected
                                  ? Colors.red.shade100
                                  : Colors.teal.shade100,
                          child: Icon(
                            isApproved
                                ? Icons.check_circle
                                : isRejected
                                    ? Icons.cancel
                                    : Icons.info,
                            color: isApproved
                                ? Colors.green.shade800
                                : isRejected
                                    ? Colors.red.shade800
                                    : Colors.teal.shade800,
                          ),
                        ),
                        title: Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(msg, style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              isVehicle
                                  ? 'Tap to view in Vehicle Details'
                                  : isComplaint
                                      ? 'Tap to open Helpdesk'
                                      : isMaintenance
                                          ? 'Tap to view Maintenance'
                                          : 'Tap to view',
                              style: TextStyle(
                                fontSize: 11,
                                color: isApproved
                                    ? Colors.green.shade800
                                    : isRejected
                                        ? Colors.red.shade800
                                        : Colors.teal.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close,
                                  size: 18, color: Colors.grey),
                              onPressed: () => doc.reference.delete(),
                              tooltip: 'Dismiss',
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                        onTap: () {
                          if (isVehicle) {
                            onNavigateTab?.call(0); // Home tab
                          } else if (isComplaint) {
                            onNavigateTab?.call(3); // Helpdesk tab
                          } else if (isMaintenance) {
                            onNavigateTab?.call(4); // Maintenance tab
                          }
                        },
                      ),
                    );
                  }),
                  const Divider(height: 24),
                ],
              );
            },
          ),
        ],
        Row(
          children: const [
            Icon(Icons.campaign, color: Colors.teal, size: 20),
            SizedBox(width: 8),
            Text(
              'Society Announcements',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('announcements')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            var docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('No announcements yet.',
                      style: TextStyle(color: Colors.grey)),
                ),
              );
            }

            docs.sort((a, b) {
              final aPinned =
                  (a.data() as Map<String, dynamic>)['isPinned'] ?? false;
              final bPinned =
                  (b.data() as Map<String, dynamic>)['isPinned'] ?? false;
              if (aPinned && !bPinned) return -1;
              if (!aPinned && bPinned) return 1;
              return 0; // retain createdAt sort order
            });

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final isPinned = data['isPinned'] ?? false;

                return Card(
                  elevation: isPinned ? 4 : 1,
                  color: isPinned ? Colors.teal.shade50 : null,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isPinned)
                              const Icon(Icons.push_pin,
                                  color: Colors.teal, size: 20),
                            if (isPinned) const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                data['title'] ?? '',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(data['message'] ?? '',
                            style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class MaintenanceTab extends StatefulWidget {
  const MaintenanceTab({super.key});

  @override
  State<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<MaintenanceTab> {
  final _currencyFmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  void _showReceiptDialog(BuildContext context, Map<String, dynamic> dueData, String receiptNumber, String? paidDateStr) {
    final flat = (dueData['flatNumber'] ?? 'Unknown').toString();
    final month = (dueData['month'] ?? '').toString();
    final amount = (dueData['amount'] as num?)?.toDouble() ?? 0.0;
    final baseMaint = (dueData['baseMaintenance'] as num?)?.toDouble();
    final puja = (dueData['pujaSubscription'] as num?)?.toDouble() ?? 90.0;
    final carCharges = (dueData['carParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final bikeCharges = (dueData['bikeParkingCharges'] as num?)?.toDouble() ?? 0.0;
    final paymentMode = dueData['paymentMode'] ?? 'Online Payment';
    final txnRef = dueData['transactionRef'] ?? dueData['offlineRef'] ?? 'N/A';
    final block = dueData['block'] ?? (flat.isNotEmpty ? flat[0] : 'A');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(20),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Header
                const Icon(Icons.verified_outlined, color: Colors.teal, size: 40),
                const SizedBox(height: 6),
                const Text(
                  'RAMKRISHNAPURAM WELFARE ASSOCIATION',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal),
                ),
                const Text(
                  'Official Maintenance Payment Receipt',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const Text(
                  'Financial Year 2026-27',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const Divider(height: 20),

                // Meta Info
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Receipt No: $receiptNumber', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('Date: $paidDateStr', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Flat: $flat (Block $block)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text('Billing Month: $month', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const Divider(height: 20),

                // Itemized Table
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Base Maintenance (Block $block)'),
                          Text(_currencyFmt.format(baseMaint ?? (amount - puja - carCharges - bikeCharges))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Puja Subscription Allocation'),
                          Text(_currencyFmt.format(puja)),
                        ],
                      ),
                      if (carCharges > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('4-Wheeler (Car) Parking'),
                            Text(_currencyFmt.format(carCharges)),
                          ],
                        ),
                      ],
                      if (bikeCharges > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('2-Wheeler (Bike) Parking'),
                            Text(_currencyFmt.format(bikeCharges)),
                          ],
                        ),
                      ],
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Amount Paid', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            _currencyFmt.format(amount),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Payment Meta
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Payment Mode: $paymentMode\nRef / Txn ID: $txnRef\nStatus: PAID & VERIFIED IN FULL',
                    style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.4),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Authorized Signatory', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        Text('RWA Accounts Committee', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPaymentModal(BuildContext context, String dueId, Map<String, dynamic> dueData, Map<String, dynamic> userData) {
    final flat = (dueData['flatNumber'] ?? userData['flatNumber'] ?? 'Unknown').toString();
    final month = (dueData['month'] ?? 'Current Month').toString();
    final double amount = (dueData['amount'] as num?)?.toDouble() ?? 0.0;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PaymentModalSheet(
        dueId: dueId,
        dueData: dueData,
        userData: userData,
        flat: flat,
        month: month,
        amount: amount,
        currencyFmt: _currencyFmt,
        onPaymentComplete: (receiptNo) {
          Navigator.pop(ctx);
          final nowStr = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
          _showReceiptDialog(context, dueData, receiptNo, nowStr);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Please log in.'));

    final userEmail = user.email?.toLowerCase();
    final flatPrefix = userEmail?.contains('@') == true
        ? userEmail!.split('@').first.toLowerCase()
        : null;

    return FutureBuilder<DocumentReference?>(
      future: _resolveUserDocRef(user.uid, userEmail, flatPrefix),
      builder: (context, docRefSnap) {
        if (docRefSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docRef = docRefSnap.data;
        if (docRef == null) {
          return const Center(child: Text('User profile not found.'));
        }

        return StreamBuilder<DocumentSnapshot>(
          stream: docRef.snapshots(),
          builder: (context, userSnapshot) {
            if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());

            final userData = userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final breakdown = AccountingConfig.calculateFromUserData(userData);
            final userFlat = (userData['flatNumber'] ?? 'A-101').toString().trim().toUpperCase();
            final blockStr = (userData['block'] ?? '').toString().trim().toUpperCase();
            final flatDisplay = (blockStr.isNotEmpty && !userFlat.startsWith(blockStr))
                ? '$blockStr-$userFlat'
                : userFlat;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FY 2026-27 Approved Maintenance Schedule Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.teal.shade800, Colors.teal.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'MY MONTHLY MAINTENANCE',
                                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Flat $flatDisplay (Block ${breakdown.block})',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'FY ${AccountingConfig.currentFinancialYear}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 8),

                        // Itemized Breakdown
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('• Base Flat Maintenance (Block ${breakdown.block})', style: const TextStyle(color: Colors.white, fontSize: 13)),
                            Text(_currencyFmt.format(breakdown.baseMaintenance), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('• Puja Subscription Allocation', style: TextStyle(color: Colors.white, fontSize: 13)),
                            Text(_currencyFmt.format(breakdown.pujaSubscription), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        if (breakdown.carCount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('• 4-Wheeler Parking (${breakdown.carCount} Car @ ₹430)', style: const TextStyle(color: Colors.white, fontSize: 13)),
                              Text(_currencyFmt.format(breakdown.carParkingCharges), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                        if (breakdown.bikeCount > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('• 2-Wheeler Parking (${breakdown.bikeCount} Bike @ ₹100)', style: const TextStyle(color: Colors.white, fontSize: 13)),
                              Text(_currencyFmt.format(breakdown.bikeParkingCharges), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Fixed Monthly Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            Text(
                              '${_currencyFmt.format(breakdown.totalMonthlyDue)} / month',
                              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Dues Stream Section
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('maintenance_dues')
                        .where('flatNumber', whereIn: [userFlat, flatDisplay, userFlat.replaceAll('-', '')])
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allDocs = snapshot.data?.docs ?? [];
                      final unpaidDocs = allDocs.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'UNPAID').toList();
                      final pendingOfflineDocs = allDocs.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'PAID_OFFLINE_PENDING').toList();
                      final paidDocs = allDocs.where((d) {
                        final st = (d.data() as Map<String, dynamic>)['status'];
                        return st == 'PAID_ONLINE' || st == 'PAID_OFFLINE_VERIFIED';
                      }).toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Outstanding Dues Section
                          const Text(
                            'Outstanding Maintenance Dues',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),

                          if (unpaidDocs.isEmpty && pendingOfflineDocs.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 36),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'All Dues Cleared!',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade900),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'You have no pending maintenance bills for Flat $flatDisplay.',
                                          style: TextStyle(color: Colors.green.shade800, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else ...[
                            // Unpaid Bills
                            ...unpaidDocs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final dueId = doc.id;
                              final month = data['month'] ?? 'Current Month';
                              final amt = (data['amount'] as num?)?.toDouble() ?? breakdown.totalMonthlyDue;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.red.shade200),
                                ),
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade50,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Icon(Icons.receipt_long, color: Colors.red),
                                              ),
                                              const SizedBox(width: 10),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Maintenance Bill: $month',
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                  ),
                                                  Text(
                                                    'FY ${data['financialYear'] ?? AccountingConfig.currentFinancialYear}',
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          Text(
                                            _currencyFmt.format(amt),
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      const Divider(),
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'PAYMENT DUE',
                                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.teal,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                            icon: const Icon(Icons.payment, size: 18),
                                            label: const Text('Pay Now', style: TextStyle(fontWeight: FontWeight.bold)),
                                            onPressed: () => _showPaymentModal(context, dueId, data, userData),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),

                            // Pending Offline Verification Bills
                            ...pendingOfflineDocs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final month = data['month'] ?? '';
                              final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.orange.shade200),
                                ),
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Colors.orange,
                                    child: Icon(Icons.hourglass_top, color: Colors.white),
                                  ),
                                  title: Text('Bill: $month — ${_currencyFmt.format(amt)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: const Text('Offline payment submitted. Awaiting Admin verification.'),
                                ),
                              );
                            }),
                          ],

                          const SizedBox(height: 24),

                          // Payment History & Receipts Section
                          const Text(
                            'Payment History & Receipts',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),

                          if (paidDocs.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No previous payment receipts recorded yet.', style: TextStyle(color: Colors.grey)),
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: paidDocs.length,
                              itemBuilder: (context, index) {
                                final data = paidDocs[index].data() as Map<String, dynamic>;
                                final month = data['month'] ?? '';
                                final amount = data['amount'] ?? 0;
                                final status = data['status'] ?? 'PAID';
                                final receiptNo = data['receiptNumber'] ?? 'REC-2627-${(data['paidAt'] != null ? data['paidAt'].hashCode % 10000 : 1001)}';
                                
                                String dateStr = 'Recently Paid';
                                if (data['paidAt'] is Timestamp) {
                                  dateStr = DateFormat('dd MMM yyyy').format((data['paidAt'] as Timestamp).toDate());
                                }

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Colors.green,
                                      child: Icon(Icons.check, color: Colors.white),
                                    ),
                                    title: Text('$month — ${_currencyFmt.format(amount)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('Receipt: $receiptNo • $dateStr\nStatus: ${status == 'PAID_ONLINE' ? 'Paid Online' : 'Offline Verified'}'),
                                    isThreeLine: true,
                                    trailing: OutlinedButton.icon(
                                      icon: const Icon(Icons.receipt, size: 16),
                                      label: const Text('Receipt'),
                                      style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
                                      onPressed: () => _showReceiptDialog(context, data, receiptNo, dateStr),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PaymentModalSheet extends StatefulWidget {
  final String dueId;
  final Map<String, dynamic> dueData;
  final Map<String, dynamic> userData;
  final String flat;
  final String month;
  final double amount;
  final NumberFormat currencyFmt;
  final Function(String receiptNo) onPaymentComplete;

  const _PaymentModalSheet({
    required this.dueId,
    required this.dueData,
    required this.userData,
    required this.flat,
    required this.month,
    required this.amount,
    required this.currencyFmt,
    required this.onPaymentComplete,
  });

  @override
  State<_PaymentModalSheet> createState() => _PaymentModalSheetState();
}

class _PaymentModalSheetState extends State<_PaymentModalSheet> {
  int _selectedPaymentTab = 0; // 0: Online (UPI / Card), 1: Offline (Cheque / Cash / Bank Transfer)
  String _selectedOnlineMethod = 'UPI'; // UPI, CARD, NETBANKING
  final _offlineRefController = TextEditingController();
  final _offlineModeController = TextEditingController(text: 'Bank Transfer / NEFT');
  bool _isProcessing = false;

  @override
  void dispose() {
    _offlineRefController.dispose();
    _offlineModeController.dispose();
    super.dispose();
  }

  Future<void> _processOnlinePayment() async {
    setState(() => _isProcessing = true);

    try {
      // Simulate gateway processing delay
      await Future.delayed(const Duration(milliseconds: 1200));

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final receiptNo = 'REC-2627-${(timestamp % 100000).toString().padLeft(5, '0')}';
      final txnRef = 'TXN_UPI_${timestamp.toString().substring(5)}';

      // 1. Determine budget head
      String head = 'Monthly Maintenance - Block A';
      final cleanUpper = widget.flat.toUpperCase();
      if (cleanUpper.startsWith('B') || cleanUpper.contains('B-')) {
        head = 'Monthly Maintenance - Block B';
      } else if (cleanUpper.startsWith('C') || cleanUpper.contains('C-')) {
        head = 'Monthly Maintenance - Block C';
      } else if (cleanUpper.startsWith('D') || cleanUpper.contains('D-')) {
        head = 'Monthly Maintenance - Block D';
      }

      // 2. Update maintenance due doc
      await FirebaseFirestore.instance.collection('maintenance_dues').doc(widget.dueId).update({
        'status': 'PAID_ONLINE',
        'paidAt': FieldValue.serverTimestamp(),
        'receiptNumber': receiptNo,
        'paymentMode': 'Online ($_selectedOnlineMethod)',
        'transactionRef': txnRef,
      });

      // 3. Post income transaction into society accounting ledger
      await FirebaseFirestore.instance.collection('society_transactions').add({
        'type': 'INCOME',
        'voucherNumber': receiptNo,
        'accountHead': head,
        'category': 'Maintenance Collection',
        'amount': widget.amount,
        'paidToOrReceivedFrom': 'Flat ${widget.flat}',
        'paymentDate': FieldValue.serverTimestamp(),
        'paymentMode': 'Online ($_selectedOnlineMethod)',
        'referenceNumber': txnRef,
        'description': 'Online maintenance payment for ${widget.month} by Flat ${widget.flat} (FY 2026-27)',
        'linkedDueId': widget.dueId,
        'recordedBy': 'Resident (${widget.flat})',
        'createdAt': FieldValue.serverTimestamp(),
      });

      widget.onPaymentComplete(receiptNo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Payment error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _processOfflinePayment() async {
    final ref = _offlineRefController.text.trim();
    if (ref.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Cheque No. or Bank UTR / Reference No.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await FirebaseFirestore.instance.collection('maintenance_dues').doc(widget.dueId).update({
        'status': 'PAID_OFFLINE_PENDING',
        'paymentMode': _offlineModeController.text,
        'offlineRef': ref,
        'submittedAt': FieldValue.serverTimestamp(),
      });

      // Send admin notification
      await FirebaseFirestore.instance.collection('notifications').add({
        'targetRole': 'ADMIN',
        'type': 'OFFLINE_PAYMENT_SUBMITTED',
        'title': 'Offline Maintenance Payment Submitted',
        'message': 'Flat ${widget.flat} submitted offline payment of ${widget.currencyFmt.format(widget.amount)} for ${widget.month} (Ref: $ref).',
        'flatNumber': widget.flat,
        'dueId': widget.dueId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.teal,
            content: Text('Offline payment details submitted for Admin verification.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pay Maintenance Bill', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 8),

          // Bill Summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Flat ${widget.flat} • ${widget.month}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Text('FY 2026-27 Approved Rates', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
                Text(
                  widget.currencyFmt.format(widget.amount),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Segment Selector
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedPaymentTab == 0 ? Colors.teal : Colors.grey.shade200,
                    foregroundColor: _selectedPaymentTab == 0 ? Colors.white : Colors.black87,
                    elevation: _selectedPaymentTab == 0 ? 2 : 0,
                  ),
                  icon: const Icon(Icons.flash_on, size: 18),
                  label: const Text('Instant Online Pay'),
                  onPressed: () => setState(() => _selectedPaymentTab = 0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedPaymentTab == 1 ? Colors.teal : Colors.grey.shade200,
                    foregroundColor: _selectedPaymentTab == 1 ? Colors.white : Colors.black87,
                    elevation: _selectedPaymentTab == 1 ? 2 : 0,
                  ),
                  icon: const Icon(Icons.account_balance, size: 18),
                  label: const Text('Offline / Transfer'),
                  onPressed: () => setState(() => _selectedPaymentTab = 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Online Payment View
          if (_selectedPaymentTab == 0) ...[
            const Text('Select Online Payment Channel:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            RadioListTile<String>(
              value: 'UPI',
              groupValue: _selectedOnlineMethod,
              title: const Row(
                children: [
                  Icon(Icons.qr_code, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('UPI / QR Code / GPay / PhonePe / Paytm'),
                ],
              ),
              onChanged: (val) => setState(() => _selectedOnlineMethod = val!),
            ),
            RadioListTile<String>(
              value: 'CARD',
              groupValue: _selectedOnlineMethod,
              title: const Row(
                children: [
                  Icon(Icons.credit_card, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('Debit / Credit Card'),
                ],
              ),
              onChanged: (val) => setState(() => _selectedOnlineMethod = val!),
            ),
            RadioListTile<String>(
              value: 'NETBANKING',
              groupValue: _selectedOnlineMethod,
              title: const Row(
                children: [
                  Icon(Icons.account_balance, color: Colors.teal),
                  SizedBox(width: 8),
                  Text('Net Banking (SBI / HDFC / ICICI / Axis)'),
                ],
              ),
              onChanged: (val) => setState(() => _selectedOnlineMethod = val!),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isProcessing ? null : _processOnlinePayment,
                icon: _isProcessing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.lock),
                label: Text(
                  _isProcessing ? 'Processing Payment...' : 'Pay ${widget.currencyFmt.format(widget.amount)} Now',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else ...[
            // Offline Payment View
            DropdownButtonFormField<String>(
              value: _offlineModeController.text,
              decoration: const InputDecoration(labelText: 'Payment Mode', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'Bank Transfer / NEFT', child: Text('Bank Transfer / NEFT / IMPS')),
                DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                DropdownMenuItem(value: 'Cash', child: Text('Cash to Treasurer')),
                DropdownMenuItem(value: 'Demand Draft', child: Text('Demand Draft')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _offlineModeController.text = val);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _offlineRefController,
              decoration: const InputDecoration(
                labelText: 'Cheque No. / Transaction UTR / Ref No. *',
                hintText: 'e.g. UTR12345678 or Cheque #987654',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isProcessing ? null : _processOfflinePayment,
                icon: _isProcessing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _isProcessing ? 'Submitting...' : 'Submit Offline Payment for Verification',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------ Pre-Approve Visitor Screen ------
class PreApproveVisitorScreen extends StatefulWidget {
  const PreApproveVisitorScreen({super.key});

  @override
  State<PreApproveVisitorScreen> createState() => _PreApproveVisitorScreenState();
}

class _PreApproveVisitorScreenState extends State<PreApproveVisitorScreen> {
  final _formKey = GlobalKey<FormState>();
  String _visitorName = '';
  String _purpose = 'Guest';

  bool _isLoading = false;

  Future<void> _generatePass() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      setState(() => _isLoading = true);
      
      try {
        final user = FirebaseAuth.instance.currentUser!;
        // Fetch host flat number
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final flatNumber = userDoc.data()?['flatNumber'] ?? 'Unknown';
        
        // Generate random 6-digit code
        final passCode = (100000 + DateTime.now().microsecondsSinceEpoch % 900000).toString();

        await FirebaseFirestore.instance.collection('visitors').add({
          'visitorName': _visitorName,
          'purpose': _purpose,
          'hostFlatNumber': flatNumber,
          'hostUid': user.uid,
          'passCode': passCode,
          'status': 'PENDING', // PENDING, CHECKED_IN, CHECKED_OUT
          'createdAt': FieldValue.serverTimestamp(),
        });

        if (!mounted) return;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Gate Pass Generated'),
            content: Text(
              'Share this code with $_visitorName:\n\n$passCode',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(); // Close dialog
                  Navigator.of(context).pop(); // Close screen
                },
                child: const Text('Done'),
              )
            ],
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pre-Approve Visitor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Visitor Name'),
                validator: (val) => val!.isEmpty ? 'Required' : null,
                onSaved: (val) => _visitorName = val!,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _purpose,
                decoration: const InputDecoration(labelText: 'Purpose'),
                items: const [
                  DropdownMenuItem(value: 'Guest', child: Text('Guest')),
                  DropdownMenuItem(value: 'Delivery', child: Text('Delivery')),
                  DropdownMenuItem(value: 'Service', child: Text('Service/Repair')),
                ],
                onChanged: (val) => setState(() => _purpose = val!),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _isLoading ? null : _generatePass,
                child: _isLoading 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator()) 
                    : const Text('Generate Pass Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResidentHelpdeskTab extends StatefulWidget {
  const ResidentHelpdeskTab({super.key});

  @override
  State<ResidentHelpdeskTab> createState() => _ResidentHelpdeskTabState();
}

class _ResidentHelpdeskTabState extends State<ResidentHelpdeskTab> {
  void _showRaiseTicketDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String category = 'Maintenance';
    bool isLoading = false;
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Raise a Ticket'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                      DropdownMenuItem(value: 'Security', child: Text('Security')),
                      DropdownMenuItem(value: 'Cleanliness', child: Text('Cleanliness')),
                      DropdownMenuItem(value: 'Other', child: Text('Other')),
                    ],
                    onChanged: (val) => setState(() => category = val!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  if (titleController.text.trim().isEmpty || descController.text.trim().isEmpty) return;
                  setState(() => isLoading = true);
                  
                  try {
                    final uid = FirebaseAuth.instance.currentUser!.uid;
                    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
                    final flatNumber = userDoc.data()?['flatNumber'] ?? 'Unknown';
                    
                    await FirebaseFirestore.instance.collection('complaints').add({
                      'title': titleController.text.trim(),
                      'description': descController.text.trim(),
                      'category': category,
                      'status': 'OPEN',
                      'residentUid': uid,
                      'flatNumber': flatNumber,
                      'createdAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });
                    
                    if (context.mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    setState(() => isLoading = false);
                  }
                },
                child: isLoading ? const CircularProgressIndicator() : const Text('Submit'),
              )
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('complaints')
            .where('residentUid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          var docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('You have not raised any tickets.'));
          }
          
          // Sort by createdAt locally
          docs.sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime); // descending
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final status = data['status'] ?? 'OPEN';
              
              Color statusColor = Colors.red;
              if (status == 'IN_PROGRESS') statusColor = Colors.orange;
              if (status == 'RESOLVED') statusColor = Colors.green;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(data['title'] ?? 'No Title', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Category: ${data['category'] ?? 'General'}'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showRaiseTicketDialog,
        icon: const Icon(Icons.add),
        label: const Text('Raise Ticket'),
      ),
    );
  }
}
