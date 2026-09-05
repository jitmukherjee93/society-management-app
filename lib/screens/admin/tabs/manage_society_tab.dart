import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../widgets/pdf_iframe.dart';
import '../../../widgets/form_helpers.dart';

class ManageSocietyTab extends StatefulWidget {
  const ManageSocietyTab({super.key});

  @override
  State<ManageSocietyTab> createState() => _ManageSocietyTabState();
}

class _ManageSocietyTabState extends State<ManageSocietyTab> {
  bool _isUploading = false;
  String _searchQuery = '';

  // ─── CSV Upload ─────────────────────────────────────────────────────────────

  Future<void> _processCsvUpload() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (files.isNotEmpty) {
        setState(() => _isUploading = true);

        final fileBytes = await files.first.readAsBytes();
        final csvString = utf8.decode(fileBytes);
        final List<List<dynamic>> csvTable =
            CsvDecoder().convert(csvString);

        if (csvTable.length <= 1) {
          throw Exception('CSV file is empty or missing data rows.');
        }

        final header =
            csvTable.first.map((e) => e.toString().trim().toLowerCase()).toList();

        final flatIndex = header.indexWhere((h) => h.contains('flat'));
        final nameIndex = header.indexWhere((h) => h.contains('name'));
        final whatsappIndex = header.indexWhere((h) => h.contains('whatsapp'));
        final mobileIndex = header.indexWhere((h) => h.contains('mobile'));
        final blockIndex = header.indexWhere((h) => h == 'block');
        final carOwnerIndex = header.indexWhere((h) => h.contains('car owner'));
        final carRegIndex = header.indexWhere((h) => h.contains('car reg'));
        final bikeOwnerIndex = header.indexWhere((h) => h.contains('bike owner'));
        final bikeRegIndex = header.indexWhere((h) => h.contains('bike reg'));

        if (flatIndex == -1 || nameIndex == -1 || whatsappIndex == -1 || mobileIndex == -1) {
          throw Exception(
              'CSV must contain columns: Flat No, Owner Name, WhatsApp No, Mobile No');
        }

        const validBlocks = {'A', 'B', 'C', 'D'};
        int count = 0;
        final List<String> errors = [];

        for (var i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.isEmpty ||
              row.length <= flatIndex ||
              row[flatIndex].toString().trim().isEmpty) { continue; }

          final flatNo = row[flatIndex].toString().trim();
          final name = row[nameIndex].toString().trim();
          final whatsapp = row[whatsappIndex].toString().trim();
          final mobile = row[mobileIndex].toString().trim();

          final List<String> rowErrors = [];

          if (!kFlatNoRegex.hasMatch(flatNo)) rowErrors.add('Flat No must be 3 digits');
          if (!kPhoneRegex.hasMatch(whatsapp)) rowErrors.add('WhatsApp No must be 10 digits');
          if (!kPhoneRegex.hasMatch(mobile)) rowErrors.add('Mobile No must be 10 digits');

          final block = blockIndex != -1 && row.length > blockIndex
              ? row[blockIndex].toString().trim().toUpperCase()
              : '';
          if (!validBlocks.contains(block)) rowErrors.add('Block must be A, B, C or D');

          final isCarOwner = carOwnerIndex != -1 && row.length > carOwnerIndex
              ? row[carOwnerIndex].toString().trim().toLowerCase() == 'yes'
              : false;
          final carReg = carRegIndex != -1 && row.length > carRegIndex
              ? row[carRegIndex].toString().trim()
              : '';
          final isBikeOwner = bikeOwnerIndex != -1 && row.length > bikeOwnerIndex
              ? row[bikeOwnerIndex].toString().trim().toLowerCase() == 'yes'
              : false;
          final bikeReg = bikeRegIndex != -1 && row.length > bikeRegIndex
              ? row[bikeRegIndex].toString().trim()
              : '';

          if (isCarOwner && carReg.isEmpty) rowErrors.add('Car Reg No required');
          if (isBikeOwner && bikeReg.isEmpty) rowErrors.add('Bike Reg No required');

          if (rowErrors.isNotEmpty) {
            errors.add('Row ${i + 1}: ${rowErrors.join(', ')}');
            continue;
          }

          await _saveRecord(flatNo, name, whatsapp, mobile, block,
              isCarOwner, carReg, isBikeOwner, bikeReg);
          count++;
        }

        if (mounted) {
          if (errors.isNotEmpty) {
            _showCsvErrorDialog(errors, count);
          } else {
            scaffoldMessenger.showSnackBar(
                SnackBar(content: Text('Successfully uploaded $count records!')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error uploading CSV: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showCsvErrorDialog(List<String> errors, int count) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload Issues'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Successfully uploaded $count records.'),
              const SizedBox(height: 8),
              Text(
                'Skipped ${errors.length} records due to validation errors:',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: errors.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text('- ${errors[i]}'),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  // ─── Firestore helpers ───────────────────────────────────────────────────────

  Future<void> _saveRecord(
    String flatNo,
    String name,
    String whatsapp,
    String mobile,
    String block,
    bool isCarOwner,
    String carReg,
    bool isBikeOwner,
    String bikeReg, {
    String role = 'Owner',
    String? email,
    String? rentAgreementUrl,
    String? rentAgreementFileName,
  }) async {
    final docId = (block.isNotEmpty && !flatNo.contains('-'))
        ? '$block-$flatNo'
        : flatNo;

    final flatEmail = '${docId.toLowerCase().replaceAll(' ', '')}@ramkrishnapuram.com';
    final customEmail = (email != null && email.trim().isNotEmpty) ? email.trim().toLowerCase() : flatEmail;

    // 0. Automatically create user account in Firebase Auth without signing out current admin
    String? newUid;
    try {
      final appName = 'AuthApp_${DateTime.now().microsecondsSinceEpoch}';
      final secondaryApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      final userCred = await FirebaseAuth.instanceFor(app: secondaryApp)
          .createUserWithEmailAndPassword(
        email: flatEmail,
        password: 'Password@123',
      );
      newUid = userCred.user?.uid;
      await secondaryApp.delete();
    } catch (e) {
      debugPrint('Auth user creation notice ($flatEmail): $e');
    }

    // Ensure flat document exists
    await FirebaseFirestore.instance.collection('flats').doc(docId).set({
      'flatNumber': docId,
      'block': block,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Demote previous owner when adding a new owner
    if (role == 'Owner') {
      final prevOwners = await FirebaseFirestore.instance
          .collection('users')
          .where('flatNumber', isEqualTo: docId)
          .where('role', isEqualTo: 'Owner')
          .get();
      for (final doc in prevOwners.docs) {
        await doc.reference.update({'role': 'Resident'});
      }
    }

    final bool isRentee = (role == 'Rentee' || role == 'Resident');
    final bool isOwner = !isRentee;

    final userData = <String, dynamic>{
      'name': name,
      'phone': '+91$mobile',
      'whatsapp': whatsapp,
      'username': flatEmail,
      'email': customEmail,
      'flatNumber': docId,
      'block': block,
      'role': 'RESIDENT',
      'occupantType': isRentee ? 'Rentee' : 'Owner',
      'isRentee': isRentee,
      'isOwner': isOwner,
      'isCarOwner': isCarOwner,
      'carReg': carReg,
      'isBikeOwner': isBikeOwner,
      'bikeReg': bikeReg,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (rentAgreementUrl != null) {
      userData['rentAgreementUrl'] = rentAgreementUrl;
      userData['rentAgreementFileName'] = rentAgreementFileName ?? '';
    }

    if (newUid != null) {
      userData['uid'] = newUid;
      await FirebaseFirestore.instance.collection('users').doc(newUid).set(userData, SetOptions(merge: true));
    } else {
      await FirebaseFirestore.instance.collection('users').add(userData);
    }
  }

  Future<void> _removeFlat(String flatId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Confirm Flat Deletion'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete flat "$flatId"?\n\n'
          'This will permanently remove the flat, all assigned members (owners/rentees), '
          'their user accounts, uploaded documents, and maintenance dues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Flat'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final cleanId = flatId.trim().toLowerCase();

      // 1. Query all users belonging to this flat (strictly matching c-001 / C-001)
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();
      final matchingDocs = usersSnap.docs.where((doc) {
        final fNum = (doc.data()['flatNumber'] ?? '').toString().trim().toLowerCase();
        return fNum == cleanId;
      }).toList();

      for (final userDoc in matchingDocs) {
        await _deleteUserData(userDoc.id, userDoc.data(), flatId);
      }

      // 2. Delete maintenance dues for this flat (strictly matching c-001 / C-001)
      final duesSnap = await FirebaseFirestore.instance.collection('maintenance_dues').get();
      final matchingDues = duesSnap.docs.where((doc) {
        final fNum = (doc.data()['flatNumber'] ?? '').toString().trim().toLowerCase();
        return fNum == cleanId;
      }).toList();

      for (final dueDoc in matchingDues) {
        await dueDoc.reference.delete();
      }

      // 3. Delete the flat document itself
      await FirebaseFirestore.instance.collection('flats').doc(flatId).delete();

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Flat $flatId and all associated users/records deleted from everywhere.')),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error deleting flat $flatId: $e')),
        );
      }
    }
  }

  Future<void> _removeMember(String memberId, Map<String, dynamic> resData) async {
    final memberName = resData['name'] ?? 'Member';
    final roleStr = (resData['role'] ?? '').toString();
    final occStr = (resData['occupantType'] ?? '').toString();
    final hasAgreement = resData['rentAgreementUrl'] != null &&
        resData['rentAgreementUrl'].toString().isNotEmpty;
    final bool isRentee = resData['isRentee'] == true ||
        occStr == 'Rentee' ||
        occStr == 'Resident' ||
        roleStr == 'Rentee' ||
        roleStr == 'Resident' ||
        hasAgreement;
    final displayRole = isRentee ? 'Rentee' : 'Owner';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Text('Confirm $displayRole Deletion'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete $displayRole "$memberName"?\n\n'
          'This will permanently delete their account, details, and associated documents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Member'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final flatId = resData['flatNumber']?.toString() ?? '';
      await _deleteUserData(memberId, resData, flatId);
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Member deleted successfully from everywhere.')),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error deleting member: $e')),
        );
      }
    }
  }

  Future<void> _deleteUserData(String docId, Map<String, dynamic> data, String flatId) async {
    // A. Delete Rent Agreement PDF/Image from Storage
    final url = data['rentAgreementUrl']?.toString() ?? '';
    if (url.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (e) {
        debugPrint('Storage deletion notice ($url): $e');
      }
    }

    // B. Delete User Account from Firebase Auth
    final email = data['email']?.toString() ??
        '${flatId.toLowerCase().replaceAll(' ', '')}@ramkrishnapuram.com';
    try {
      final appName = 'DeleteAuth_${DateTime.now().microsecondsSinceEpoch}';
      final secondaryApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      try {
        final userCred = await secondaryAuth.signInWithEmailAndPassword(
          email: email,
          password: 'Password@123',
        );
        await userCred.user?.delete();
      } catch (e) {
        debugPrint('Auth account deletion notice ($email): $e');
      }
      await secondaryApp.delete();
    } catch (e) {
      debugPrint('Secondary app cleanup notice: $e');
    }

    // C. Delete User Document from Firestore
    await FirebaseFirestore.instance.collection('users').doc(docId).delete();

    // D. Reset isRented to false on the flat document if the deleted user was a rentee
    if (flatId.isNotEmpty) {
      final roleStr = (data['role'] ?? '').toString();
      final occStr = (data['occupantType'] ?? '').toString();
      final hasAgreement = data['rentAgreementUrl'] != null &&
          data['rentAgreementUrl'].toString().isNotEmpty;
      final bool wasRentee = data['isRentee'] == true ||
          occStr == 'Rentee' ||
          occStr == 'Resident' ||
          roleStr == 'Rentee' ||
          roleStr == 'Resident' ||
          hasAgreement;

      if (wasRentee) {
        await FirebaseFirestore.instance
            .collection('flats')
            .doc(flatId)
            .update({'isRented': false});
      }
    }
  }

  // ─── Upload rent agreement helper ────────────────────────────────────────────

  Future<String?> _uploadRentAgreement(PlatformFile file) async {
    final fileName = file.name;
    final ref = FirebaseStorage.instance.ref(
        'rent_agreements/${DateTime.now().millisecondsSinceEpoch}_$fileName');

    final contentType = fileName.toLowerCase().endsWith('.pdf')
        ? 'application/pdf'
        : fileName.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg';

    // Use base64 to avoid dart2js Int64 serialisation bug on Flutter Web
    final bytes = await file.readAsBytes();
    await ref.putString(
      base64Encode(bytes),
      format: PutStringFormat.base64,
      metadata: SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  // ─── Dialogs ─────────────────────────────────────────────────────────────────

  void _addRecordDialog() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final flatCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final waCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final carRegCtrl = TextEditingController();
    final bikeRegCtrl = TextEditingController();

    String isCarOwner = 'No';
    String isBikeOwner = 'No';
    String? selectedBlock;
    bool hasAttemptedSubmit = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.person_add, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Add Member Record'),
          ]),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SectionHeader(icon: Icons.home, title: 'Flat Details'),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            value: selectedBlock,
                            items: kBlockOptions
                                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                                .toList(),
                            onChanged: (v) => setDS(() => selectedBlock = v),
                            decoration: kInput('Block *'),
                            validator: (v) =>
                                v == null ? (hasAttemptedSubmit ? 'Required' : null) : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: flatCtrl,
                            decoration: kInput('Flat No. (3 digits) *'),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return hasAttemptedSubmit ? 'Required' : null;
                              }
                              if (!kFlatNoRegex.hasMatch(v.trim())) {
                                return 'Must be exactly 3 digits';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const SectionHeader(icon: Icons.person, title: 'Owner Details'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: kInput('Owner Name *', icon: Icons.badge),
                      validator: (v) =>
                          v!.trim().isEmpty ? (hasAttemptedSubmit ? 'Required' : null) : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      decoration: kInput('Email Address (Optional)', icon: Icons.email),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v != null && v.trim().isNotEmpty && !v.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: waCtrl,
                            decoration: kInput('WhatsApp No. *', icon: Icons.chat),
                            keyboardType: TextInputType.phone,
                            validator: (v) => phoneValidator(v, hasAttemptedSubmit),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: mobileCtrl,
                            decoration: kInput('Mobile No. *', icon: Icons.phone),
                            keyboardType: TextInputType.phone,
                            validator: (v) => phoneValidator(v, hasAttemptedSubmit),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    VehiclesSection(
                      isCarOwner: isCarOwner,
                      isBikeOwner: isBikeOwner,
                      carRegController: carRegCtrl,
                      bikeRegController: bikeRegCtrl,
                      hasAttemptedSubmit: hasAttemptedSubmit,
                      onCarChanged: (v) => setDS(() => isCarOwner = v),
                      onBikeChanged: (v) => setDS(() => isBikeOwner = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Record'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              onPressed: () async {
                setDS(() => hasAttemptedSubmit = true);
                if (!formKey.currentState!.validate()) return;
                setState(() => _isUploading = true);
                Navigator.pop(ctx);
                try {
                  await _saveRecord(
                    flatCtrl.text.trim(),
                    nameCtrl.text.trim(),
                    waCtrl.text.trim(),
                    mobileCtrl.text.trim(),
                    selectedBlock ?? '',
                    isCarOwner == 'Yes',
                    carRegCtrl.text.trim(),
                    isBikeOwner == 'Yes',
                    bikeRegCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                  );
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('Record Added Successfully')));
                  }
                } catch (e) {
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                } finally {
                  if (mounted) setState(() => _isUploading = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addRenteeDialog(String flatId, String block) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final waCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final carRegCtrl = TextEditingController();
    final bikeRegCtrl = TextEditingController();

    String isCarOwner = 'No';
    String isBikeOwner = 'No';
    bool hasAttemptedSubmit = false;
    bool renteeAdded = false;
    PlatformFile? rentAgreementFile;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.person_add_alt_1, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Text('Add Rentee to $block-$flatId'),
          ]),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: kInput('Rentee Name *', icon: Icons.badge),
                      validator: (v) =>
                          v!.trim().isEmpty ? (hasAttemptedSubmit ? 'Required' : null) : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      decoration: kInput('Email Address (Optional)', icon: Icons.email),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v != null && v.trim().isNotEmpty && !v.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: waCtrl,
                            decoration: kInput('WhatsApp No. *', icon: Icons.chat),
                            keyboardType: TextInputType.phone,
                            validator: (v) => phoneValidator(v, hasAttemptedSubmit),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: mobileCtrl,
                            decoration: kInput('Mobile No. *', icon: Icons.phone),
                            keyboardType: TextInputType.phone,
                            validator: (v) => phoneValidator(v, hasAttemptedSubmit),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    VehiclesSection(
                      isCarOwner: isCarOwner,
                      isBikeOwner: isBikeOwner,
                      carRegController: carRegCtrl,
                      bikeRegController: bikeRegCtrl,
                      hasAttemptedSubmit: hasAttemptedSubmit,
                      onCarChanged: (v) => setDS(() => isCarOwner = v),
                      onBikeChanged: (v) => setDS(() => isBikeOwner = v),
                    ),
                    const SizedBox(height: 24),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text("Owner's NOC/Rent Agreement/Contract *",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Pick PDF/Image'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple.shade50,
                              foregroundColor: Colors.deepPurple),
                          onPressed: () async {
                            final res = await FilePicker.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                            );
                            if (res.isNotEmpty) {
                              setDS(() => rentAgreementFile = res.first);
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            rentAgreementFile?.name ?? 'No file selected *',
                            style: TextStyle(
                              color: rentAgreementFile != null
                                  ? Colors.green
                                  : (hasAttemptedSubmit ? Colors.red : Colors.grey),
                              fontStyle: rentAgreementFile != null
                                  ? FontStyle.normal
                                  : FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (rentAgreementFile != null)
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red, size: 20),
                            onPressed: () => setDS(() => rentAgreementFile = null),
                          ),
                      ],
                    ),
                    if (hasAttemptedSubmit && rentAgreementFile == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Owner's NOC/Rent Agreement/Contract is required",
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Save Rentee'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
              onPressed: () async {
                setDS(() => hasAttemptedSubmit = true);
                if (!formKey.currentState!.validate() || rentAgreementFile == null) return;
                setState(() => _isUploading = true);
                renteeAdded = true;
                Navigator.pop(ctx);
                try {
                  String? downloadUrl;
                  String? fileName;
                  if (rentAgreementFile != null) {
                    fileName = rentAgreementFile!.name;
                    downloadUrl = await _uploadRentAgreement(rentAgreementFile!);
                  }
                  await _saveRecord(
                    flatId,
                    nameCtrl.text.trim(),
                    waCtrl.text.trim(),
                    mobileCtrl.text.trim(),
                    block,
                    isCarOwner == 'Yes',
                    carRegCtrl.text.trim(),
                    isBikeOwner == 'Yes',
                    bikeRegCtrl.text.trim(),
                    role: 'Rentee',
                    email: emailCtrl.text.trim(),
                    rentAgreementUrl: downloadUrl,
                    rentAgreementFileName: fileName,
                  );
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('Rentee Added Successfully')));
                  }
                } catch (e) {
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                } finally {
                  if (mounted) setState(() => _isUploading = false);
                }
              },
            ),
          ],
        ),
      ),
    );

    // If dialog was closed/cancelled without saving a rentee, check if flat has any existing rentee. If not, reset isRented to false.
    if (!renteeAdded) {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('flatNumber', isEqualTo: flatId)
          .get();

      bool hasRentee = false;
      for (var doc in userSnap.docs) {
        final resData = doc.data();
        final roleStr = (resData['role'] ?? '').toString();
        final occStr = (resData['occupantType'] ?? '').toString();
        final hasAgreement = resData['rentAgreementUrl'] != null &&
            resData['rentAgreementUrl'].toString().isNotEmpty;

        if (resData['isRentee'] == true ||
            occStr == 'Rentee' ||
            occStr == 'Resident' ||
            roleStr == 'Rentee' ||
            roleStr == 'Resident' ||
            hasAgreement) {
          hasRentee = true;
          break;
        }
      }

      if (!hasRentee) {
        await FirebaseFirestore.instance
            .collection('flats')
            .doc(flatId)
            .update({'isRented': false});
      }
    }
  }

  void _editMemberDialog(String memberId, Map<String, dynamic> currentData) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: currentData['name']);
    final emailCtrl = TextEditingController(text: currentData['email']?.toString() ?? '');
    final waCtrl = TextEditingController(text: currentData['whatsapp']?.toString());

    String rawPhone = currentData['phone']?.toString() ?? '';
    if (rawPhone.startsWith('+91')) rawPhone = rawPhone.substring(3);
    final mobileCtrl = TextEditingController(text: rawPhone);
    final carRegCtrl = TextEditingController(text: currentData['carReg']);
    final bikeRegCtrl = TextEditingController(text: currentData['bikeReg']);

    String isCarOwner = currentData['isCarOwner'] == true ? 'Yes' : 'No';
    String isBikeOwner = currentData['isBikeOwner'] == true ? 'Yes' : 'No';
    bool hasAttemptedSubmit = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.edit, color: Colors.blue),
            SizedBox(width: 8),
            Text('Edit Member Details'),
          ]),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: kInput('Name *', icon: Icons.badge),
                      validator: (v) =>
                          v!.trim().isEmpty ? (hasAttemptedSubmit ? 'Required' : null) : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailCtrl,
                      decoration: kInput('Email Address (Optional)', icon: Icons.email),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v != null && v.trim().isNotEmpty && !v.contains('@')) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: waCtrl,
                            decoration: kInput('WhatsApp No. *', icon: Icons.chat),
                            keyboardType: TextInputType.phone,
                            validator: (v) => phoneValidator(v, hasAttemptedSubmit),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: mobileCtrl,
                            decoration: kInput('Mobile No. *', icon: Icons.phone),
                            keyboardType: TextInputType.phone,
                            validator: (v) => phoneValidator(v, hasAttemptedSubmit),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    VehiclesSection(
                      isCarOwner: isCarOwner,
                      isBikeOwner: isBikeOwner,
                      carRegController: carRegCtrl,
                      bikeRegController: bikeRegCtrl,
                      hasAttemptedSubmit: hasAttemptedSubmit,
                      onCarChanged: (v) => setDS(() => isCarOwner = v),
                      onBikeChanged: (v) => setDS(() => isBikeOwner = v),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Update'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white),
              onPressed: () async {
                setDS(() => hasAttemptedSubmit = true);
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  final updateData = <String, dynamic>{
                    'name': nameCtrl.text.trim(),
                    'phone': '+91${mobileCtrl.text.trim()}',
                    'whatsapp': waCtrl.text.trim(),
                    'isCarOwner': isCarOwner == 'Yes',
                    'carReg': isCarOwner == 'Yes' ? carRegCtrl.text.trim() : '',
                    'isBikeOwner': isBikeOwner == 'Yes',
                    'bikeReg': isBikeOwner == 'Yes' ? bikeRegCtrl.text.trim() : '',
                  };
                  if (emailCtrl.text.trim().isNotEmpty) {
                    updateData['email'] = emailCtrl.text.trim().toLowerCase();
                  }
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(memberId)
                      .update(updateData);
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('Member Updated Successfully')));
                  }
                } catch (e) {
                  if (mounted) {
                    scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDocumentDialog(String url, String fileName) {
    final lowerName = fileName.toLowerCase();
    final isImage =
        lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg') || lowerName.endsWith('.png');
    final isPdf = lowerName.endsWith('.pdf');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fileName.isNotEmpty ? fileName : 'Rent Agreement'),
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
                    errorBuilder: (_, e, __) =>
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
                        Text('Document: $fileName',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                            'Preview is only available for images and PDFs. Please download to view other formats.'),
                      ],
                    ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Download / Open'),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _addRecordDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Single Record'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isUploading ? null : _processCsvUpload,
                icon: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Icon(Icons.upload_file),
                label: const Text('Bulk Upload (CSV)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search Flat No.',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('flats')
                .orderBy('flatNumber')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              var docs = snapshot.data?.docs ?? [];

              if (_searchQuery.trim().isNotEmpty) {
                final rawQuery = _searchQuery.trim().toLowerCase();
                final cleanQuery = rawQuery.replaceAll(RegExp(r'[\s\-]'), '');
                docs = docs.where((doc) {
                  final flatData = doc.data() as Map<String, dynamic>;
                  final block = flatData['block']?.toString().toLowerCase() ?? '';
                  final flatNumber = flatData['flatNumber']?.toString().toLowerCase() ?? '';
                  final docId = doc.id.toLowerCase();
                  
                  final blockFlatCombo = '$block-$docId'.toLowerCase();
                  final cleanCombo = '$block$docId$flatNumber'.replaceAll(RegExp(r'[\s\-]'), '');

                  return docId.contains(rawQuery) ||
                      flatNumber.contains(rawQuery) ||
                      block.contains(rawQuery) ||
                      blockFlatCombo.contains(rawQuery) ||
                      cleanCombo.contains(cleanQuery);
                }).toList();
              }

              if (docs.isEmpty) return const Center(child: Text('No flats found.'));

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final flatId = docs[index].id;
                  final flatData = docs[index].data() as Map<String, dynamic>;
                  final block = flatData['block'] ?? '';
                  final flatLabel = flatId.contains('-')
                      ? 'Flat: $flatId'
                      : (block.isNotEmpty ? 'Flat: $block-$flatId' : 'Flat: $flatId');
                  final isRented = flatData['isRented'] == true;

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ExpansionTile(
                      title: Text(flatLabel,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeFlat(flatId),
                        tooltip: 'Remove Flat',
                      ),
                      children: [
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .where('flatNumber', isEqualTo: flatId)
                              .snapshots(),
                          builder: (context, resSnap) {
                            final resDocs = resSnap.hasData ? resSnap.data!.docs : <QueryDocumentSnapshot>[];

                            bool hasExistingRentee = false;
                            for (var doc in resDocs) {
                              final resData = doc.data() as Map<String, dynamic>;
                              final roleStr = (resData['role'] ?? '').toString();
                              final occStr = (resData['occupantType'] ?? '').toString();
                              final hasAgreement = resData['rentAgreementUrl'] != null &&
                                  resData['rentAgreementUrl'].toString().isNotEmpty;

                              if (resData['isRentee'] == true ||
                                  occStr == 'Rentee' ||
                                  occStr == 'Resident' ||
                                  roleStr == 'Rentee' ||
                                  roleStr == 'Resident' ||
                                  hasAgreement) {
                                hasExistingRentee = true;
                                break;
                              }
                            }

                            return Column(
                              children: [
                                SwitchListTile(
                                  title: const Text('Is this flat rented?',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  value: isRented,
                                  activeThumbColor: Colors.deepPurple,
                                  onChanged: hasExistingRentee
                                      ? null
                                      : (val) async {
                                          await FirebaseFirestore.instance
                                              .collection('flats')
                                              .doc(flatId)
                                              .update({'isRented': val});
                                          if (val) {
                                            _addRenteeDialog(flatId, block);
                                          }
                                        },
                                ),
                                if (isRented)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Tooltip(
                                        message: hasExistingRentee ? 'Your property has already been rented' : '',
                                        child: ElevatedButton.icon(
                                          icon: const Icon(Icons.person_add_alt_1),
                                          label: const Text('Add Rentee'),
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: hasExistingRentee ? Colors.grey : Colors.teal,
                                              foregroundColor: Colors.white),
                                          onPressed: hasExistingRentee ? null : () => _addRenteeDialog(flatId, block),
                                        ),
                                      ),
                                    ),
                                  ),
                                const Divider(),
                                if (resDocs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No members assigned to this flat yet.',
                                        style: TextStyle(color: Colors.grey)),
                                  )
                                else
                                  ...resDocs.map((resDoc) {
                                    final resData = resDoc.data() as Map<String, dynamic>;
                                    final roleStr = (resData['role'] ?? '').toString();
                                    final occStr = (resData['occupantType'] ?? '').toString();
                                    final hasAgreement = resData['rentAgreementUrl'] != null &&
                                        resData['rentAgreementUrl'].toString().isNotEmpty;

                                    final bool isRentee = resData['isRentee'] == true ||
                                        occStr == 'Rentee' ||
                                        occStr == 'Resident' ||
                                        roleStr == 'Rentee' ||
                                        roleStr == 'Resident' ||
                                        hasAgreement;
                                    final displayRole = isRentee ? 'Rentee' : 'Owner';
                                    final isCarOwner = resData['isCarOwner'] == true;
                                    final isBikeOwner = resData['isBikeOwner'] == true;

                                    return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        isRentee ? Colors.teal : Colors.deepPurple,
                                    child: Icon(
                                        isRentee ? Icons.key : Icons.home,
                                        color: Colors.white),
                                  ),
                                  title: Text(resData['name'] ?? 'Unknown'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${resData['phone'] ?? ''} • $displayRole'),
                                      if ((resData['email']?.toString() ?? '').isNotEmpty)
                                        Text('Email: ${resData['email']}'),
                                      if ((resData['whatsapp']?.toString() ?? '').isNotEmpty)
                                        Text('WA: ${resData['whatsapp']}'),
                                      if (isCarOwner) Text('Car: ${resData['carReg']}'),
                                      if (isBikeOwner) Text('Bike: ${resData['bikeReg']}'),
                                      if (resData['rentAgreementUrl'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: InkWell(
                                            onTap: () => _showDocumentDialog(
                                              resData['rentAgreementUrl'].toString(),
                                              resData['rentAgreementFileName']?.toString() ??
                                                  'Document',
                                            ),
                                            child: const Text(
                                              'View Rent Agreement',
                                              style: TextStyle(
                                                  color: Colors.deepPurple,
                                                  decoration: TextDecoration.underline),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue),
                                        onPressed: () => _editMemberDialog(resDoc.id, resData),
                                        tooltip: 'Edit Member',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline,
                                            color: Colors.red),
                                        onPressed: () => _removeMember(resDoc.id, resData),
                                        tooltip: 'Remove Member',
                                      ),
                                    ],
                                  ),
                                );
                              }),
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
          ),
        ),
      ],
    );
  }
}
