import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'tabs/community_feed_tab.dart';
import '../../widgets/pdf_iframe.dart';

class ResidentDashboard extends StatefulWidget {
  const ResidentDashboard({super.key});

  @override
  State<ResidentDashboard> createState() => _ResidentDashboardState();
}

class _ResidentDashboardState extends State<ResidentDashboard> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomeTab(),
    const CommunityFeedTab(),
    const NotificationsTab(),
    const ResidentHelpdeskTab(),
    const MaintenanceTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resident Dashboard'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'Community'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.support_agent), label: 'Helpdesk'),
          BottomNavigationBarItem(icon: Icon(Icons.payment), label: 'Maintenance'),
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

  void _editDetailsDialog(BuildContext context, String docId, Map<String, dynamic> data) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();

    String rawPhone = data['phone']?.toString() ?? '';
    if (rawPhone.startsWith('+91')) rawPhone = rawPhone.substring(3);

    final mobileCtrl = TextEditingController(text: rawPhone);
    final waCtrl = TextEditingController(text: data['whatsapp']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: data['email']?.toString() ?? '');

    bool isCarOwner = data['isCarOwner'] == true;
    bool isBikeOwner = data['isBikeOwner'] == true;
    final currentCarReg = data['carReg']?.toString().trim() ?? '';
    final currentBikeReg = data['bikeReg']?.toString().trim() ?? '';
    final carRegCtrl = TextEditingController(text: currentCarReg);
    final bikeRegCtrl = TextEditingController(text: currentBikeReg);

    PlatformFile? carRcFile;
    PlatformFile? bikeRcFile;
    bool isSaving = false;

    Future<String?> uploadRcDoc(PlatformFile file, String prefix) async {
      final fileName = file.name;
      final ref = FirebaseStorage.instance
          .ref('vehicle_rc/${prefix}_${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final contentType = fileName.toLowerCase().endsWith('.pdf')
          ? 'application/pdf'
          : fileName.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg';
      final bytes = await file.readAsBytes();
      await ref.putString(
        base64Encode(bytes),
        format: PutStringFormat.base64,
        metadata: SettableMetadata(contentType: contentType),
      );
      return ref.getDownloadURL();
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
                      'Vehicle Details',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Note: Updating vehicle numbers requires uploading RC/Blue Book copy for Admin approval.',
                      style: TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Do you own a 4-Wheeler (Car)?'),
                      secondary: const Icon(Icons.directions_car, color: Colors.teal),
                      value: isCarOwner,
                      activeThumbColor: Colors.teal,
                      onChanged: (val) {
                        setDS(() => isCarOwner = val);
                      },
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
                                    final res = await FilePicker.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                                    );
                                    if (res.isNotEmpty) {
                                      setDS(() => carRcFile = res.first);
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Do you own a 2-Wheeler (Bike/Scooter)?'),
                      secondary: const Icon(Icons.two_wheeler, color: Colors.teal),
                      value: isBikeOwner,
                      activeThumbColor: Colors.teal,
                      onChanged: (val) {
                        setDS(() => isBikeOwner = val);
                      },
                    ),
                    if (isBikeOwner) ...[
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: bikeRegCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Bike Registration No. *',
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
                      // RC upload button for Bike
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
                                    'Upload Bike RC / Blue Book Copy *',
                                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.attach_file, size: 16),
                                  label: Text(bikeRcFile == null ? 'Select File' : 'Change'),
                                  onPressed: () async {
                                    final res = await FilePicker.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                                    );
                                    if (res.isNotEmpty) {
                                      setDS(() => bikeRcFile = res.first);
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
                      final carChanged = newCarReg.isNotEmpty && newCarReg != currentCarReg;
                      final bikeChanged = newBikeReg.isNotEmpty && newBikeReg != currentBikeReg;

                      if (carChanged && carRcFile == null && data['pendingCarRcUrl'] == null) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Please upload RC / Blue Book copy for Car update.')),
                        );
                        return;
                      }
                      if (bikeChanged && bikeRcFile == null && data['pendingBikeRcUrl'] == null) {
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Please upload RC / Blue Book copy for Bike update.')),
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
                        } else if (bikeChanged) {
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
                            'title': 'Bike Number Update Request',
                            'message': '$residentName ($flatDisplay) requested to update Bike number to $newBikeReg with RC copy.',
                            'flatNumber': flatDisplay,
                            'userId': docId,
                            'vehicleType': 'Bike',
                            'requestedReg': newBikeReg,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
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
                              carChanged || bikeChanged
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

    final String? pendingCarReg = data?['pendingCarReg']?.toString().trim();
    final String? pendingCarRcUrl = data?['pendingCarRcUrl']?.toString();
    final String? carRejectionReason = data?['carRejectionReason']?.toString();

    final String? pendingBikeReg = data?['pendingBikeReg']?.toString().trim();
    final String? pendingBikeRcUrl = data?['pendingBikeRcUrl']?.toString();
    final String? bikeRejectionReason = data?['bikeRejectionReason']?.toString();

    void showRcDocDialog(String url, String title) {
      final lower = url.toLowerCase();
      final isPdf = lower.contains('.pdf');
      final isImage = lower.contains('.png') || lower.contains('.jpg') || lower.contains('.jpeg');

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            height: MediaQuery.of(context).size.height * 0.6,
            child: isImage
                ? InteractiveViewer(
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, e, _) =>
                          const Center(child: Text('Error loading image')),
                    ),
                  )
                : isPdf
                    ? buildPdfIframe(url)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.description, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('RC Document uploaded.', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        ),
      );
    }

    String vehicleSummary;
    if (isCarOwner && isBikeOwner) {
      vehicleSummary = 'Both (4-Wheeler & 2-Wheeler)';
    } else if (isCarOwner) {
      vehicleSummary = 'Car (4-Wheeler)';
    } else if (isBikeOwner) {
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
                if (!isCarOwner && !isBikeOwner)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      'No vehicles registered yet.',
                      style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic),
                    ),
                  )
                else ...[
                  if (isCarOwner)
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
                  if (isBikeOwner)
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
                                        text: 'Bike: ${bikeReg.isNotEmpty ? bikeReg : "Registered (No Reg. No.)"}',
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
                                      onTap: () => showRcDocDialog(pendingBikeRcUrl, 'Bike RC / Blue Book'),
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
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
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
          return const Center(child: Text('No announcements yet.'));
        }

        docs.sort((a, b) {
          final aPinned = (a.data() as Map<String, dynamic>)['isPinned'] ?? false;
          final bPinned = (b.data() as Map<String, dynamic>)['isPinned'] ?? false;
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          return 0; // retain createdAt sort order
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
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
                        if (isPinned) const Icon(Icons.push_pin, color: Colors.teal, size: 20),
                        if (isPinned) const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            data['title'] ?? '',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(data['message'] ?? '', style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class MaintenanceTab extends StatelessWidget {
  const MaintenanceTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final flatNumber = userSnapshot.data?.get('flatNumber');
        
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('maintenance_dues')
              .where('flatNumber', isEqualTo: flatNumber)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(child: Text('No maintenance dues found.'));
            }

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final status = data['status'];
                final amount = data['amount'];
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long, size: 40, color: Colors.teal),
                    title: Text('Month: ${data['month']}'),
                    subtitle: Text('Amount: ₹$amount\nStatus: $status'),
                    isThreeLine: true,
                    trailing: status == 'UNPAID' 
                      ? ElevatedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Pay Maintenance'),
                                content: const Text('Choose payment method:'),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      // Mock Offline Payment Submission
                                      FirebaseFirestore.instance
                                          .collection('maintenance_dues')
                                          .doc(docs[index].id)
                                          .update({'status': 'PAID_OFFLINE_PENDING'});
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Offline payment submitted for verification.')),
                                      );
                                    },
                                    child: const Text('Offline (Cash/Cheque)'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      // Mock Online Payment
                                      FirebaseFirestore.instance
                                          .collection('maintenance_dues')
                                          .doc(docs[index].id)
                                          .update({'status': 'PAID_ONLINE'});
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Online payment successful!')),
                                      );
                                    },
                                    child: const Text('Pay Online'),
                                  ),
                                ],
                              )
                            );
                          },
                          child: const Text('Pay Now'),
                        )
                      : const Icon(Icons.check_circle, color: Colors.green),
                  ),
                );
              },
            );
          },
        );
      }
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
