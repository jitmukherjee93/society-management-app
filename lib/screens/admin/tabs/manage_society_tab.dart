import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../widgets/form_helpers.dart';
import '../../../utils/storage_utils.dart';
import '../../../widgets/document_preview_dialog.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_decorations.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_feedback.dart';

class ManageSocietyTab extends StatefulWidget {
  final String? initialSearchQuery;
  const ManageSocietyTab({super.key, this.initialSearchQuery});

  @override
  State<ManageSocietyTab> createState() => _ManageSocietyTabState();
}

class _ManageSocietyTabState extends State<ManageSocietyTab> {
  bool _isUploading = false;
  String _searchQuery = '';
  late TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery ?? '';
    _searchCtrl = TextEditingController(text: _searchQuery);
  }

  @override
  void didUpdateWidget(covariant ManageSocietyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSearchQuery != oldWidget.initialSearchQuery && widget.initialSearchQuery != null) {
      setState(() {
        _searchQuery = widget.initialSearchQuery!;
        _searchCtrl.text = _searchQuery;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─── CSV Upload ─────────────────────────────────────────────────────────────

  Future<void> _processCsvUpload() async {
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
        final Map<String, int> csvFlatCars = {};
        final Map<String, int> csvFlatBikes = {};

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

          final docId = (block.isNotEmpty && !flatNo.contains('-'))
              ? '$block-$flatNo'
              : flatNo;

          if (isCarOwner || isBikeOwner) {
            final currentCounts = await _getFlatVehicleCounts(docId);
            final existingCars = currentCounts['cars'] ?? 0;
            final existingBikes = currentCounts['bikes'] ?? 0;
            final batchCars = csvFlatCars[docId] ?? 0;
            final batchBikes = csvFlatBikes[docId] ?? 0;

            if (isCarOwner && (existingCars + batchCars + 1 > 1)) {
              rowErrors.add('Flat $docId exceeds car quota (max 1 car per flat)');
            }
            if (isBikeOwner && (existingBikes + batchBikes + 1 > 2)) {
              rowErrors.add('Flat $docId exceeds bike quota (max 2 bikes per flat)');
            }
          }

          if (rowErrors.isNotEmpty) {
            errors.add('Row ${i + 1}: ${rowErrors.join(', ')}');
            continue;
          }

          if (isCarOwner) csvFlatCars[docId] = (csvFlatCars[docId] ?? 0) + 1;
          if (isBikeOwner) csvFlatBikes[docId] = (csvFlatBikes[docId] ?? 0) + 1;

          await _saveRecord(flatNo, name, whatsapp, mobile, block,
              isCarOwner, carReg, isBikeOwner, bikeReg);
          count++;
        }

        if (mounted) {
          if (errors.isNotEmpty) {
            _showCsvErrorDialog(errors, count);
          } else {
            AppFeedback.showSuccess(context, 'Successfully uploaded $count records!');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error uploading CSV: $e');
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showCsvErrorDialog(List<String> errors, int count) {
    AppDialog.show(
      context: context,
      title: 'Upload Issues',
      subtitle: 'Some records had validation errors',
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.error,
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Successfully uploaded $count records.',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success),
            ),
            const SizedBox(height: 12),
            Text(
              'Skipped ${errors.length} records due to validation errors:',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.error),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: errors.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('• ${errors[i]}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    );
  }

  // ─── Firestore helpers ───────────────────────────────────────────────────────

  Future<Map<String, int>> _getFlatVehicleCounts(String flatId, {String? excludeUserId}) async {
    try {
      final querySnap = await FirebaseFirestore.instance
          .collection('users')
          .where('flatNumber', isEqualTo: flatId)
          .get();
      int cars = 0;
      int bikes = 0;
      for (final doc in querySnap.docs) {
        if (excludeUserId != null && doc.id == excludeUserId) continue;
        final data = doc.data();
        if (data['isCarOwner'] == true && (data['carReg']?.toString().trim().isNotEmpty ?? false)) {
          cars++;
        }
        if (data['isBikeOwner'] == true && (data['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
          bikes++;
        }
        if (data['hasBike2'] == true && (data['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
          bikes++;
        }
      }
      return {'cars': cars, 'bikes': bikes};
    } catch (e) {
      debugPrint('Error getting flat vehicle counts: $e');
      return {'cars': 0, 'bikes': 0};
    }
  }

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
    bool hasBike2 = false,
    String? bike2Reg,
    String role = 'Owner',
    String? email,
    String? rentAgreementUrl,
    String? rentAgreementFileName,
  }) async {
    final docId = (block.isNotEmpty && !flatNo.contains('-'))
        ? '$block-$flatNo'
        : flatNo;

    final cleanDocId = docId.toLowerCase().replaceAll(' ', '');
    final cleanMobile = mobile.replaceAll(RegExp(r'\D'), '');
    final defaultAuthEmail = (role == 'Owner')
        ? '$cleanDocId@ramkrishnapuram.com'
        : '${cleanDocId}_$cleanMobile@ramkrishnapuram.com';
    final authEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim().toLowerCase()
        : defaultAuthEmail;

    // Automatically create user account in Firebase Auth without signing out current admin
    String? newUid;
    try {
      final appName = 'AuthApp_${DateTime.now().microsecondsSinceEpoch}';
      final secondaryApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      final auth = FirebaseAuth.instanceFor(app: secondaryApp);
      try {
        final userCred = await auth.createUserWithEmailAndPassword(
          email: authEmail,
          password: 'Password@123',
        );
        newUid = userCred.user?.uid;
      } on FirebaseAuthException catch (authErr) {
        if (authErr.code == 'email-already-in-use') {
          try {
            final cred = await auth.signInWithEmailAndPassword(
              email: authEmail,
              password: 'Password@123',
            );
            newUid = cred.user?.uid;
          } catch (_) {
            debugPrint('Could not sign in to existing auth user ($authEmail)');
          }
        } else {
          debugPrint('Auth user creation error ($authEmail): $authErr');
        }
      } catch (e) {
        debugPrint('Auth user creation general error: $e');
      }
      await secondaryApp.delete();
    } catch (e) {
      debugPrint('Auth user creation secondary app error ($authEmail): $e');
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
      'username': authEmail,
      'email': authEmail,
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
      'hasBike2': hasBike2,
      'bike2Reg': (hasBike2 && bike2Reg != null) ? bike2Reg : '',
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
    final confirm = await AppDialog.show<bool>(
      context: context,
      title: 'Confirm Flat Deletion',
      subtitle: 'Permanent Action',
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.error,
      content: Text(
        'Are you sure you want to delete flat "$flatId"?\n\n'
        'This will permanently remove the flat, all assigned members (owners/rentees), '
        'their user accounts, uploaded documents, and maintenance dues.',
        style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Flat'),
        ),
      ],
    );

    if (confirm != true) return;
    if (!mounted) return;

    try {
      // 1. Query all users belonging to this flat
      final usersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('flatNumber', isEqualTo: flatId)
          .get();
      for (final userDoc in usersSnap.docs) {
        await _deleteUserData(userDoc.id, userDoc.data(), flatId);
      }

      // 2. Delete maintenance dues for this flat
      final duesSnap = await FirebaseFirestore.instance
          .collection('maintenance_dues')
          .where('flatNumber', isEqualTo: flatId)
          .get();
      for (final dueDoc in duesSnap.docs) {
        await dueDoc.reference.delete();
      }

      // 3. Delete the flat document itself
      await FirebaseFirestore.instance.collection('flats').doc(flatId).delete();

      if (mounted) {
        AppFeedback.showSuccess(context, 'Flat $flatId and all associated records deleted.');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error deleting flat $flatId: $e');
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

    final confirm = await AppDialog.show<bool>(
      context: context,
      title: 'Confirm $displayRole Deletion',
      subtitle: 'Permanent Action',
      icon: Icons.warning_amber_rounded,
      iconColor: AppColors.error,
      content: Text(
        'Are you sure you want to delete $displayRole "$memberName"?\n\n'
        'This will permanently delete their account, details, and associated documents.',
        style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Member'),
        ),
      ],
    );

    if (confirm != true) return;
    if (!mounted) return;

    try {
      final flatId = resData['flatNumber']?.toString() ?? '';
      await _deleteUserData(memberId, resData, flatId);
      if (mounted) {
        AppFeedback.showSuccess(context, 'Member deleted successfully.');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Error deleting member: $e');
      }
    }
  }

  Future<void> _deleteUserData(String docId, Map<String, dynamic> data, String flatId) async {
    // Delete Rent Agreement PDF/Image from Storage
    final url = data['rentAgreementUrl']?.toString() ?? '';
    if (url.isNotEmpty) {
      try {
        await FirebaseStorage.instance.refFromURL(url).delete();
      } catch (e) {
        debugPrint('Storage deletion notice ($url): $e');
      }
    }

    // Delete any pending vehicle RC documents from Storage
    final rcUrls = [
      data['pendingCarRcUrl']?.toString() ?? '',
      data['pendingBikeRcUrl']?.toString() ?? '',
      data['pendingBike2RcUrl']?.toString() ?? '',
    ];
    for (final rcUrl in rcUrls) {
      if (rcUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(rcUrl).delete();
        } catch (e) {
          debugPrint('RC storage deletion notice ($rcUrl): $e');
        }
      }
    }

    // Dismiss any notifications for this user
    try {
      final notifs = await FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: docId)
          .get();
      for (final n in notifs.docs) {
        await n.reference.delete();
      }
    } catch (_) {}

    // Delete User Account from Firebase Auth
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

    // Delete User Document from Firestore
    await FirebaseFirestore.instance.collection('users').doc(docId).delete();

    // Reset isRented to false on the flat document if the deleted user was a rentee
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
    return uploadFile(
      file,
      'rent_agreements/${DateTime.now().millisecondsSinceEpoch}_$fileName',
    );
  }

  // ─── Dialogs ─────────────────────────────────────────────────────────────────

  void _addRecordDialog() {
    final formKey = GlobalKey<FormState>();
    final flatCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final waCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final carRegCtrl = TextEditingController();
    final bikeRegCtrl = TextEditingController();
    final bike2RegCtrl = TextEditingController();

    String isCarOwner = 'No';
    String isBikeOwner = 'No';
    bool hasBike2 = false;
    String? selectedBlock;
    bool hasAttemptedSubmit = false;
    bool canAddCar = true;
    int maxBikesAddable = 2;

    Future<void> updateQuota(void Function(void Function()) setDS) async {
      final b = selectedBlock ?? '';
      final f = flatCtrl.text.trim();
      if (f.isNotEmpty) {
        final docId = (b.isNotEmpty && !f.contains('-')) ? '$b-$f' : f;
        final counts = await _getFlatVehicleCounts(docId);
        setDS(() {
          canAddCar = (counts['cars'] ?? 0) < 1;
          maxBikesAddable = 2 - (counts['bikes'] ?? 0);
          if (!canAddCar && isCarOwner == 'Yes') {
            isCarOwner = 'No';
            carRegCtrl.clear();
          }
          if (maxBikesAddable <= 0 && isBikeOwner == 'Yes') {
            isBikeOwner = 'No';
            bikeRegCtrl.clear();
            hasBike2 = false;
            bike2RegCtrl.clear();
          } else if (maxBikesAddable == 1 && hasBike2) {
            hasBike2 = false;
            bike2RegCtrl.clear();
          }
        });
      }
    }

    AppDialog.show(
      context: context,
      title: 'Add Member Record',
      subtitle: 'Register flat owner details & vehicles',
      icon: Icons.person_add,
      maxWidth: 580,
      content: StatefulBuilder(
        builder: (_, setDS) => Form(
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
                      initialValue: selectedBlock,
                      items: kBlockOptions
                          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      onChanged: (v) {
                        setDS(() => selectedBlock = v);
                        updateQuota(setDS);
                      },
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
                      onChanged: (_) => updateQuota(setDS),
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
              const SizedBox(height: 20),
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
              const SizedBox(height: 20),
              VehiclesSection(
                isCarOwner: isCarOwner,
                isBikeOwner: isBikeOwner,
                carRegController: carRegCtrl,
                bikeRegController: bikeRegCtrl,
                hasBike2: hasBike2,
                bike2RegController: bike2RegCtrl,
                canAddCar: canAddCar,
                maxBikesAddable: maxBikesAddable,
                hasAttemptedSubmit: hasAttemptedSubmit,
                onCarChanged: (v) => setDS(() => isCarOwner = v),
                onBikeChanged: (v) => setDS(() => isBikeOwner = v),
                onBike2Changed: (v) => setDS(() => hasBike2 = v),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save Record'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      setDS(() => hasAttemptedSubmit = true);
                      if (!formKey.currentState!.validate()) return;
                      setState(() => _isUploading = true);
                      Navigator.pop(context);
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
                          hasBike2: hasBike2 && isBikeOwner == 'Yes',
                          bike2Reg: (hasBike2 && isBikeOwner == 'Yes') ? bike2RegCtrl.text.trim() : '',
                          email: emailCtrl.text.trim(),
                        );
                        if (mounted) {
                          AppFeedback.showSuccess(context, 'Record added successfully');
                        }
                      } catch (e) {
                        if (mounted) {
                          AppFeedback.showError(context, 'Error: $e');
                        }
                      } finally {
                        if (mounted) setState(() => _isUploading = false);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addRenteeDialog(String flatId, String block) async {
    final counts = await _getFlatVehicleCounts(flatId);
    final canAddCar = (counts['cars'] ?? 0) < 1;
    final maxBikesAddable = 2 - (counts['bikes'] ?? 0);

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final waCtrl = TextEditingController();
    final mobileCtrl = TextEditingController();
    final carRegCtrl = TextEditingController();
    final bikeRegCtrl = TextEditingController();
    final bike2RegCtrl = TextEditingController();

    String isCarOwner = 'No';
    String isBikeOwner = 'No';
    bool hasBike2 = false;
    bool hasAttemptedSubmit = false;
    bool renteeAdded = false;
    PlatformFile? rentAgreementFile;

    if (!mounted) return;
    await AppDialog.show(
      context: context,
      title: 'Add Rentee',
      subtitle: 'Flat: $flatId',
      icon: Icons.person_add_alt_1,
      maxWidth: 580,
      content: StatefulBuilder(
        builder: (_, setDS) => Form(
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
              const SizedBox(height: 20),
              VehiclesSection(
                isCarOwner: isCarOwner,
                isBikeOwner: isBikeOwner,
                carRegController: carRegCtrl,
                bikeRegController: bikeRegCtrl,
                hasBike2: hasBike2,
                bike2RegController: bike2RegCtrl,
                canAddCar: canAddCar,
                maxBikesAddable: maxBikesAddable,
                hasAttemptedSubmit: hasAttemptedSubmit,
                onCarChanged: (v) => setDS(() => isCarOwner = v),
                onBikeChanged: (v) => setDS(() => isBikeOwner = v),
                onBike2Changed: (v) => setDS(() => hasBike2 = v),
              ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Owner's NOC/Rent Agreement/Contract *",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('Pick PDF/Image'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primarySurface,
                      foregroundColor: AppColors.primary,
                      elevation: 0,
                    ),
                    onPressed: () async {
                      final file = await pickFile();
                      if (file != null) {
                        setDS(() => rentAgreementFile = file);
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rentAgreementFile?.name ?? 'No file selected *',
                      style: TextStyle(
                        color: rentAgreementFile != null
                            ? AppColors.success
                            : (hasAttemptedSubmit ? AppColors.error : AppColors.textMuted),
                        fontStyle: rentAgreementFile != null ? FontStyle.normal : FontStyle.italic,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (rentAgreementFile != null)
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.error, size: 18),
                      splashRadius: 16,
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
                      style: TextStyle(color: AppColors.error, fontSize: 12),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save Rentee'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      setDS(() => hasAttemptedSubmit = true);
                      if (!formKey.currentState!.validate() || rentAgreementFile == null) return;
                      setState(() => _isUploading = true);
                      renteeAdded = true;
                      Navigator.pop(context);
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
                          hasBike2: hasBike2 && isBikeOwner == 'Yes',
                          bike2Reg: (hasBike2 && isBikeOwner == 'Yes') ? bike2RegCtrl.text.trim() : '',
                          role: 'Rentee',
                          email: emailCtrl.text.trim(),
                          rentAgreementUrl: downloadUrl,
                          rentAgreementFileName: fileName,
                        );
                        if (mounted) {
                          AppFeedback.showSuccess(context, 'Rentee Added Successfully');
                        }
                      } catch (e) {
                        if (mounted) {
                          AppFeedback.showError(context, 'Error: $e');
                        }
                      } finally {
                        if (mounted) setState(() => _isUploading = false);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
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

  Future<void> _editMemberDialog(String memberId, Map<String, dynamic> currentData) async {
    final flatId = currentData['flatNumber']?.toString() ?? '';
    final counts = await _getFlatVehicleCounts(flatId, excludeUserId: memberId);
    final canAddCar = (counts['cars'] ?? 0) < 1;
    final maxBikesAddable = 2 - (counts['bikes'] ?? 0);

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: currentData['name']);
    final emailCtrl = TextEditingController(text: currentData['email']?.toString() ?? '');
    final waCtrl = TextEditingController(text: currentData['whatsapp']?.toString());

    String rawPhone = currentData['phone']?.toString() ?? '';
    if (rawPhone.startsWith('+91')) rawPhone = rawPhone.substring(3);
    final mobileCtrl = TextEditingController(text: rawPhone);
    final carRegCtrl = TextEditingController(text: currentData['carReg']);
    final bikeRegCtrl = TextEditingController(text: currentData['bikeReg']);
    final bike2RegCtrl = TextEditingController(text: currentData['bike2Reg']?.toString() ?? '');

    String isCarOwner = currentData['isCarOwner'] == true ? 'Yes' : 'No';
    String isBikeOwner = currentData['isBikeOwner'] == true ? 'Yes' : 'No';
    bool hasBike2 = currentData['hasBike2'] == true;
    bool hasAttemptedSubmit = false;

    if (!mounted) return;
    AppDialog.show(
      context: context,
      title: 'Edit Member Details',
      subtitle: currentData['name']?.toString() ?? 'Member',
      icon: Icons.edit_note_rounded,
      maxWidth: 580,
      content: StatefulBuilder(
        builder: (_, setDS) => Form(
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
              const SizedBox(height: 20),
              VehiclesSection(
                isCarOwner: isCarOwner,
                isBikeOwner: isBikeOwner,
                carRegController: carRegCtrl,
                bikeRegController: bikeRegCtrl,
                hasBike2: hasBike2,
                bike2RegController: bike2RegCtrl,
                canAddCar: canAddCar || isCarOwner == 'Yes',
                maxBikesAddable: maxBikesAddable,
                hasAttemptedSubmit: hasAttemptedSubmit,
                onCarChanged: (v) => setDS(() => isCarOwner = v),
                onBikeChanged: (v) => setDS(() => isBikeOwner = v),
                onBike2Changed: (v) => setDS(() => hasBike2 = v),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Update'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      setDS(() => hasAttemptedSubmit = true);
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(context);
                      try {
                        final updateData = <String, dynamic>{
                          'name': nameCtrl.text.trim(),
                          'phone': '+91${mobileCtrl.text.trim()}',
                          'whatsapp': waCtrl.text.trim(),
                          'isCarOwner': isCarOwner == 'Yes',
                          'carReg': isCarOwner == 'Yes' ? carRegCtrl.text.trim() : '',
                          'isBikeOwner': isBikeOwner == 'Yes',
                          'bikeReg': isBikeOwner == 'Yes' ? bikeRegCtrl.text.trim() : '',
                          'hasBike2': isBikeOwner == 'Yes' && hasBike2,
                          'bike2Reg': (isBikeOwner == 'Yes' && hasBike2) ? bike2RegCtrl.text.trim() : '',
                        };
                        if (isCarOwner == 'No') {
                          updateData['pendingCarReg'] = FieldValue.delete();
                          updateData['pendingCarRcUrl'] = FieldValue.delete();
                          updateData['pendingCarRcFileName'] = FieldValue.delete();
                          updateData['carRejectionReason'] = FieldValue.delete();
                        }
                        if (isBikeOwner == 'No') {
                          updateData['pendingBikeReg'] = FieldValue.delete();
                          updateData['pendingBikeRcUrl'] = FieldValue.delete();
                          updateData['pendingBikeRcFileName'] = FieldValue.delete();
                          updateData['bikeRejectionReason'] = FieldValue.delete();
                          updateData['pendingBike2Reg'] = FieldValue.delete();
                          updateData['pendingBike2RcUrl'] = FieldValue.delete();
                          updateData['pendingBike2RcFileName'] = FieldValue.delete();
                          updateData['bike2RejectionReason'] = FieldValue.delete();
                        } else if (!hasBike2) {
                          updateData['pendingBike2Reg'] = FieldValue.delete();
                          updateData['pendingBike2RcUrl'] = FieldValue.delete();
                          updateData['pendingBike2RcFileName'] = FieldValue.delete();
                          updateData['bike2RejectionReason'] = FieldValue.delete();
                        }
                        if (emailCtrl.text.trim().isNotEmpty) {
                          updateData['email'] = emailCtrl.text.trim().toLowerCase();
                        }
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(memberId)
                            .update(updateData);
                        if (mounted) {
                          AppFeedback.showSuccess(context, 'Member Updated Successfully');
                        }
                      } catch (e) {
                        if (mounted) {
                          AppFeedback.showError(context, 'Error: $e');
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDocumentDialog(String url, String fileName) {
    showDocumentPreviewDialog(context, url, fileName);
  }

  Future<void> _approveVehicleUpdate(
    String userDocId,
    Map<String, dynamic> userData,
    String vehicleType,
  ) async {
    try {
      final flatNumber = userData['flatNumber']?.toString();
      if (flatNumber != null && flatNumber.isNotEmpty) {
        final flatMembersSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('flatNumber', isEqualTo: flatNumber)
            .get();

        int otherCars = 0;
        int otherBikes = 0;
        for (final doc in flatMembersSnap.docs) {
          final d = doc.data();
          if (doc.id != userDocId) {
            if (d['isCarOwner'] == true && (d['carReg']?.toString().trim().isNotEmpty ?? false)) {
              otherCars++;
            }
            if (d['isBikeOwner'] == true && (d['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
              otherBikes++;
            }
            if (d['hasBike2'] == true && (d['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
              otherBikes++;
            }
          } else {
            if (vehicleType == 'Bike 2') {
              if (d['isBikeOwner'] == true && (d['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
                otherBikes++;
              }
            } else if (vehicleType == 'Bike 1' || vehicleType == 'Bike') {
              if (d['hasBike2'] == true && (d['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
                otherBikes++;
              }
            }
          }
        }

        if (vehicleType == 'Car' && otherCars >= 1) {
          if (mounted) {
            AppFeedback.showWarning(
              context,
              'Cannot approve Car update. Flat $flatNumber already has 1 approved Car registered.',
              title: 'Flat Quota Exceeded',
            );
          }
          return;
        }

        if ((vehicleType == 'Bike 1' || vehicleType == 'Bike' || vehicleType == 'Bike 2') && otherBikes >= 2) {
          if (mounted) {
            AppFeedback.showWarning(
              context,
              'Cannot approve $vehicleType update. Flat $flatNumber already has 2 approved Bikes registered.',
              title: 'Flat Quota Exceeded',
            );
          }
          return;
        }
      }

      final updateData = <String, dynamic>{};
      String? approvedReg;

      if (vehicleType == 'Car') {
        approvedReg = userData['pendingCarReg']?.toString().trim();
        if (approvedReg != null && approvedReg.isNotEmpty) {
          updateData['carReg'] = approvedReg;
          updateData['isCarOwner'] = true;
        }
        updateData['pendingCarReg'] = FieldValue.delete();
        updateData['pendingCarRcUrl'] = FieldValue.delete();
        updateData['pendingCarRcFileName'] = FieldValue.delete();
        updateData['carRejectionReason'] = FieldValue.delete();
      } else if (vehicleType == 'Bike 1' || vehicleType == 'Bike') {
        approvedReg = userData['pendingBikeReg']?.toString().trim();
        if (approvedReg != null && approvedReg.isNotEmpty) {
          updateData['bikeReg'] = approvedReg;
          updateData['isBikeOwner'] = true;
        }
        updateData['pendingBikeReg'] = FieldValue.delete();
        updateData['pendingBikeRcUrl'] = FieldValue.delete();
        updateData['pendingBikeRcFileName'] = FieldValue.delete();
        updateData['bikeRejectionReason'] = FieldValue.delete();
      } else if (vehicleType == 'Bike 2') {
        approvedReg = userData['pendingBike2Reg']?.toString().trim();
        if (approvedReg != null && approvedReg.isNotEmpty) {
          updateData['bike2Reg'] = approvedReg;
          updateData['hasBike2'] = true;
        }
        updateData['pendingBike2Reg'] = FieldValue.delete();
        updateData['pendingBike2RcUrl'] = FieldValue.delete();
        updateData['pendingBike2RcFileName'] = FieldValue.delete();
        updateData['bike2RejectionReason'] = FieldValue.delete();
      }

      await FirebaseFirestore.instance.collection('users').doc(userDocId).update(updateData);

      // Notify resident
      final targetUid = userData['uid']?.toString();
      if (targetUid != null && targetUid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'targetUid': targetUid,
          'targetRole': 'RESIDENT',
          'type': 'VEHICLE_APPROVED',
          'title': '$vehicleType Number Approved',
          'message': 'Your request to update $vehicleType number to $approvedReg has been approved by the Admin.',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Dismiss corresponding admin notification(s)
      try {
        final notifs = await FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: userDocId)
            .where('type', isEqualTo: 'VEHICLE_UPDATE_REQUEST')
            .get();
        for (final doc in notifs.docs) {
          final d = doc.data();
          if (d['vehicleType'] == vehicleType || vehicleType.startsWith(d['vehicleType']?.toString() ?? '')) {
            await doc.reference.delete();
          }
        }
      } catch (_) {}

      if (mounted) {
        AppFeedback.showSuccess(context, '$vehicleType number update approved successfully!');
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, 'Failed to approve update: $e');
      }
    }
  }

  void _rejectVehicleUpdate(
    String userDocId,
    Map<String, dynamic> userData,
    String vehicleType,
  ) {
    final reasonCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    AppDialog.show(
      context: context,
      title: 'Reject $vehicleType Update',
      subtitle: 'Provide rejection rationale for the resident',
      icon: Icons.cancel_outlined,
      iconColor: AppColors.error,
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please provide a reason for rejecting the vehicle update:',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Rejection Reason *',
                hintText: 'e.g. RC copy unclear / details do not match',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter a rejection reason';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final reason = reasonCtrl.text.trim();
                    Navigator.pop(context);

                    try {
                      final updateData = <String, dynamic>{};
                      if (vehicleType == 'Car') {
                        updateData['pendingCarReg'] = FieldValue.delete();
                        updateData['pendingCarRcUrl'] = FieldValue.delete();
                        updateData['pendingCarRcFileName'] = FieldValue.delete();
                        updateData['carRejectionReason'] = reason;
                      } else if (vehicleType == 'Bike 1' || vehicleType == 'Bike') {
                        updateData['pendingBikeReg'] = FieldValue.delete();
                        updateData['pendingBikeRcUrl'] = FieldValue.delete();
                        updateData['pendingBikeRcFileName'] = FieldValue.delete();
                        updateData['bikeRejectionReason'] = reason;
                      } else if (vehicleType == 'Bike 2') {
                        updateData['pendingBike2Reg'] = FieldValue.delete();
                        updateData['pendingBike2RcUrl'] = FieldValue.delete();
                        updateData['pendingBike2RcFileName'] = FieldValue.delete();
                        updateData['bike2RejectionReason'] = reason;
                      }

                      await FirebaseFirestore.instance.collection('users').doc(userDocId).update(updateData);

                      // Notify resident
                      final targetUid = userData['uid']?.toString();
                      if (targetUid != null && targetUid.isNotEmpty) {
                        await FirebaseFirestore.instance.collection('notifications').add({
                          'targetUid': targetUid,
                          'targetRole': 'RESIDENT',
                          'type': 'VEHICLE_REJECTED',
                          'title': '$vehicleType Number Update Rejected',
                          'message': 'Your request to update $vehicleType number was rejected by Admin. Reason: $reason',
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                      }

                      // Dismiss corresponding admin notification(s)
                      try {
                        final notifs = await FirebaseFirestore.instance
                            .collection('notifications')
                            .where('userId', isEqualTo: userDocId)
                            .where('type', isEqualTo: 'VEHICLE_UPDATE_REQUEST')
                            .get();
                        for (final doc in notifs.docs) {
                          final d = doc.data();
                          if (d['vehicleType'] == vehicleType || vehicleType.startsWith(d['vehicleType']?.toString() ?? '')) {
                            await doc.reference.delete();
                          }
                        }
                      } catch (_) {}

                      if (mounted) {
                        AppFeedback.showSuccess(context, '$vehicleType update rejected.');
                      }
                    } catch (e) {
                      if (mounted) {
                        AppFeedback.showError(context, 'Failed to reject: $e');
                      }
                    }
                  },
                  child: const Text('Confirm Rejection'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showFlatDetailsModal(BuildContext context, String flatId, Map<String, dynamic> flatData) {
    showDialog(
      context: context,
      builder: (ctx) => _FlatDetailsDialog(
        flatId: flatId,
        initialFlatData: flatData,
        onAddRentee: (fId, blk) => _addRenteeDialog(fId, blk),
        onEditMember: (mId, data) => _editMemberDialog(mId, data),
        onRemoveMember: (mId, data) => _removeMember(mId, data),
        onRemoveFlat: (fId) => _removeFlat(fId),
        onApproveVehicle: (uId, data, type) => _approveVehicleUpdate(uId, data, type),
        onRejectVehicle: (uId, data, type) => _rejectVehicleUpdate(uId, data, type),
        onShowDoc: (url, name) => _showDocumentDialog(url, name),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top Action Bar with Search positioned at top right
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.cardSurface,
            border: Border(bottom: BorderSide(color: AppColors.border, width: 0.9)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 650;

              final actionButtons = Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _addRecordDialog,
                    icon: const Icon(Icons.person_add, size: 16),
                    label: const Text('Add Member'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _processCsvUpload,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.upload_file, size: 16),
                    label: const Text('Bulk CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              );

              final searchBox = SizedBox(
                width: isNarrow ? double.infinity : 240,
                height: 38,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search Flat No...',
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textMuted),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            padding: EdgeInsets.zero,
                            splashRadius: 12,
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                                _searchCtrl.clear();
                              });
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    filled: true,
                    fillColor: AppColors.cardSurfaceSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border, width: 0.8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border, width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    actionButtons,
                    const SizedBox(height: 10),
                    searchBox,
                  ],
                );
              } else {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    actionButtons,
                    searchBox,
                  ],
                );
              }
            },
          ),
        ),

        // Responsive Flats Grid
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

              if (docs.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_work_outlined, size: 48, color: AppColors.textMuted),
                      SizedBox(height: 12),
                      Text(
                        'No flats found matching your search.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 145,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final flatId = doc.id;
                  final flatData = doc.data() as Map<String, dynamic>;
                  return _FlatTile(
                    flatId: flatId,
                    flatData: flatData,
                    onTap: () => _showFlatDetailsModal(context, flatId, flatData),
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

// ─── Compact Flat Tile Widget ───────────────────────────────────────────────

class _FlatTile extends StatelessWidget {
  final String flatId;
  final Map<String, dynamic> flatData;
  final VoidCallback onTap;

  const _FlatTile({
    required this.flatId,
    required this.flatData,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final block = flatData['block']?.toString() ?? '';
    final isRented = flatData['isRented'] == true;
    final flatNumber = flatData['flatNumber']?.toString() ?? flatId;
    final displayFlatNumber = flatNumber.contains('-') ? flatNumber.split('-').last : flatNumber;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('flatNumber', isEqualTo: flatId)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        
        int cars = 0;
        int bikes = 0;
        bool hasPendingReq = false;
        String? primaryOccupantName;

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (primaryOccupantName == null && (data['name']?.toString().isNotEmpty ?? false)) {
            primaryOccupantName = data['name'].toString();
          }
          if (data['isCarOwner'] == true && (data['carReg']?.toString().trim().isNotEmpty ?? false)) {
            cars++;
          }
          if (data['isBikeOwner'] == true && (data['bikeReg']?.toString().trim().isNotEmpty ?? false)) {
            bikes++;
          }
          if (data['hasBike2'] == true && (data['bike2Reg']?.toString().trim().isNotEmpty ?? false)) {
            bikes++;
          }
          if ((data['pendingCarReg']?.toString().isNotEmpty ?? false) ||
              (data['pendingBikeReg']?.toString().isNotEmpty ?? false) ||
              (data['pendingBike2Reg']?.toString().isNotEmpty ?? false)) {
            hasPendingReq = true;
          }
        }

        final isVacant = docs.isEmpty;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasPendingReq ? AppColors.warningBorder : AppColors.border,
                  width: hasPendingReq ? 1.4 : 0.9,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Row: Block & Flat No + Occupancy Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (block.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.primaryBorder, width: 0.8),
                              ),
                              child: Text(
                                block,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            displayFlatNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      if (isVacant)
                        const AppBadge(
                          label: 'Vacant',
                          textColor: AppColors.textMuted,
                          backgroundColor: AppColors.cardSurfaceSecondary,
                          borderColor: AppColors.border,
                        )
                      else if (isRented)
                        AppBadge.info('Rented')
                      else
                        AppBadge.success('Owner'),
                    ],
                  ),

                  // Middle Row: Primary occupant name
                  Row(
                    children: [
                      Icon(
                        isVacant ? Icons.person_off_outlined : Icons.person_outline,
                        size: 14,
                        color: isVacant ? AppColors.textMuted : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          isVacant
                              ? 'No occupant'
                              : (docs.length > 1
                                  ? '$primaryOccupantName (+${docs.length - 1})'
                                  : (primaryOccupantName ?? 'Occupant')),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isVacant ? AppColors.textMuted : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // Bottom Row: Vehicles + Pending request indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (cars > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.cardSurfaceSecondary,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.border, width: 0.7),
                              ),
                              child: Text('🚗 $cars', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (bikes > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.cardSurfaceSecondary,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.border, width: 0.7),
                              ),
                              child: Text('🏍️ $bikes', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 4),
                          ],
                          if (cars == 0 && bikes == 0)
                            const Text(
                              'No vehicles',
                              style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                            ),
                        ],
                      ),
                      if (hasPendingReq)
                        const AppBadge(
                          label: 'Pending Req',
                          icon: Icons.pending_actions,
                          textColor: AppColors.warning,
                          backgroundColor: AppColors.warningSurface,
                          borderColor: AppColors.warningBorder,
                          fontSize: 10,
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        )
                      else
                        const Icon(Icons.arrow_forward_ios, size: 11, color: AppColors.textMuted),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Flat Details Modal Dialog ──────────────────────────────────────────────

class _FlatDetailsDialog extends StatelessWidget {
  final String flatId;
  final Map<String, dynamic> initialFlatData;
  final Function(String, String) onAddRentee;
  final Function(String, Map<String, dynamic>) onEditMember;
  final Function(String, Map<String, dynamic>) onRemoveMember;
  final Function(String) onRemoveFlat;
  final Function(String, Map<String, dynamic>, String) onApproveVehicle;
  final Function(String, Map<String, dynamic>, String) onRejectVehicle;
  final Function(String, String) onShowDoc;

  const _FlatDetailsDialog({
    required this.flatId,
    required this.initialFlatData,
    required this.onAddRentee,
    required this.onEditMember,
    required this.onRemoveMember,
    required this.onRemoveFlat,
    required this.onApproveVehicle,
    required this.onRejectVehicle,
    required this.onShowDoc,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('flats').doc(flatId).snapshots(),
      builder: (context, flatSnap) {
        final flatData = (flatSnap.hasData && flatSnap.data!.exists)
            ? (flatSnap.data!.data() as Map<String, dynamic>)
            : initialFlatData;
        final block = flatData['block']?.toString() ?? '';
        final isRented = flatData['isRented'] == true;
        final flatNumber = flatData['flatNumber']?.toString() ?? flatId;
        final flatLabel = flatNumber.contains('-') ? 'Flat $flatNumber' : (block.isNotEmpty ? 'Flat $block-$flatNumber' : 'Flat $flatNumber');

        return AppDialog(
          title: flatLabel,
          subtitle: 'Block: ${block.isEmpty ? "N/A" : block} • Management Console',
          icon: Icons.apartment_rounded,
          maxWidth: 620,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Rented Switch & Add Rentee button section
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('flatNumber', isEqualTo: flatId)
                    .snapshots(),
                builder: (context, userSnap) {
                  final resDocs = userSnap.hasData ? userSnap.data!.docs : <QueryDocumentSnapshot>[];

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

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurfaceSecondary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border, width: 0.8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.key, size: 18, color: AppColors.primary),
                                SizedBox(width: 8),
                                Text(
                                  'Is this flat rented?',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                                ),
                              ],
                            ),
                            Switch(
                              value: isRented,
                              activeThumbColor: AppColors.primary,
                              onChanged: hasExistingRentee
                                  ? null
                                  : (val) async {
                                      await FirebaseFirestore.instance
                                          .collection('flats')
                                          .doc(flatId)
                                          .update({'isRented': val});
                                      if (val) {
                                        onAddRentee(flatId, block);
                                      }
                                    },
                            ),
                          ],
                        ),
                        if (isRented) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Tooltip(
                              message: hasExistingRentee ? 'A rentee is already registered for this property' : '',
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.person_add_alt_1, size: 15),
                                label: const Text('Add Rentee', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: hasExistingRentee ? Colors.grey : AppColors.secondary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: hasExistingRentee ? null : () => onAddRentee(flatId, block),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Occupants & Members Stream
              const Text(
                'Assigned Occupants & Members',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('flatNumber', isEqualTo: flatId)
                    .snapshots(),
                builder: (context, resSnap) {
                  if (resSnap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final resDocs = resSnap.hasData ? resSnap.data!.docs : <QueryDocumentSnapshot>[];

                  if (resDocs.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.cardSurfaceSecondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'No members assigned to this flat yet.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: resDocs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final resDoc = resDocs[i];
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

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border, width: 0.8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Member Header Row
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: isRentee ? AppColors.secondarySurface : AppColors.primarySurface,
                                  child: Icon(
                                    isRentee ? Icons.key : Icons.home,
                                    size: 18,
                                    color: isRentee ? AppColors.secondary : AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              resData['name'] ?? 'Unknown Member',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          AppBadge(
                                            label: displayRole,
                                            textColor: isRentee ? AppColors.secondary : AppColors.primary,
                                            backgroundColor: isRentee ? AppColors.secondarySurface : AppColors.primarySurface,
                                            borderColor: isRentee ? AppColors.secondaryBorder : AppColors.primaryBorder,
                                            fontSize: 10,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${resData['phone'] ?? ''} ${((resData['email']?.toString() ?? '').isNotEmpty) ? '• ${resData['email']}' : ''}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18, color: AppColors.primary),
                                  splashRadius: 16,
                                  tooltip: 'Edit Member',
                                  onPressed: () => onEditMember(resDoc.id, resData),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 18, color: AppColors.error),
                                  splashRadius: 16,
                                  tooltip: 'Remove Member',
                                  onPressed: () => onRemoveMember(resDoc.id, resData),
                                ),
                              ],
                            ),

                            // Vehicle badges
                            if ((isCarOwner && (resData['carReg']?.toString().trim().isNotEmpty ?? false)) ||
                                (isBikeOwner && (resData['bikeReg']?.toString().trim().isNotEmpty ?? false)) ||
                                (resData['hasBike2'] == true && (resData['bike2Reg']?.toString().isNotEmpty ?? false))) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (isCarOwner && (resData['carReg']?.toString().trim().isNotEmpty ?? false))
                                    AppBadge(
                                      label: '🚗 ${resData['carReg']}',
                                      textColor: AppColors.textPrimary,
                                      backgroundColor: AppColors.cardSurfaceSecondary,
                                      borderColor: AppColors.border,
                                    ),
                                  if (isBikeOwner && (resData['bikeReg']?.toString().trim().isNotEmpty ?? false))
                                    AppBadge(
                                      label: '🏍️ 1: ${resData['bikeReg']}',
                                      textColor: AppColors.textPrimary,
                                      backgroundColor: AppColors.cardSurfaceSecondary,
                                      borderColor: AppColors.border,
                                    ),
                                  if (resData['hasBike2'] == true && (resData['bike2Reg']?.toString().isNotEmpty ?? false))
                                    AppBadge(
                                      label: '🏍️ 2: ${resData['bike2Reg']}',
                                      textColor: AppColors.textPrimary,
                                      backgroundColor: AppColors.cardSurfaceSecondary,
                                      borderColor: AppColors.border,
                                    ),
                                ],
                              ),
                            ],

                            // Pending Car Update Box
                            if (resData['pendingCarReg'] != null && resData['pendingCarReg'].toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _VehiclePendingCard(
                                title: 'Car Update Requested: ${resData['pendingCarReg']}',
                                icon: Icons.directions_car,
                                rcUrl: resData['pendingCarRcUrl']?.toString(),
                                rcFileName: resData['pendingCarRcFileName']?.toString() ?? 'Car_RC',
                                onApprove: () => onApproveVehicle(resDoc.id, resData, 'Car'),
                                onReject: () => onRejectVehicle(resDoc.id, resData, 'Car'),
                                onViewDoc: () => onShowDoc(
                                  resData['pendingCarRcUrl'].toString(),
                                  resData['pendingCarRcFileName']?.toString() ?? 'Car_RC',
                                ),
                              ),
                            ],

                            // Pending Bike 1 Update Box
                            if (resData['pendingBikeReg'] != null && resData['pendingBikeReg'].toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _VehiclePendingCard(
                                title: 'Bike 1 Update Requested: ${resData['pendingBikeReg']}',
                                icon: Icons.two_wheeler,
                                rcUrl: resData['pendingBikeRcUrl']?.toString(),
                                rcFileName: resData['pendingBikeRcFileName']?.toString() ?? 'Bike1_RC',
                                onApprove: () => onApproveVehicle(resDoc.id, resData, 'Bike 1'),
                                onReject: () => onRejectVehicle(resDoc.id, resData, 'Bike 1'),
                                onViewDoc: () => onShowDoc(
                                  resData['pendingBikeRcUrl'].toString(),
                                  resData['pendingBikeRcFileName']?.toString() ?? 'Bike1_RC',
                                ),
                              ),
                            ],

                            // Pending Bike 2 Update Box
                            if (resData['pendingBike2Reg'] != null && resData['pendingBike2Reg'].toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _VehiclePendingCard(
                                title: 'Bike 2 Update Requested: ${resData['pendingBike2Reg']}',
                                icon: Icons.two_wheeler,
                                rcUrl: resData['pendingBike2RcUrl']?.toString(),
                                rcFileName: resData['pendingBike2RcFileName']?.toString() ?? 'Bike2_RC',
                                onApprove: () => onApproveVehicle(resDoc.id, resData, 'Bike 2'),
                                onReject: () => onRejectVehicle(resDoc.id, resData, 'Bike 2'),
                                onViewDoc: () => onShowDoc(
                                  resData['pendingBike2RcUrl'].toString(),
                                  resData['pendingBike2RcFileName']?.toString() ?? 'Bike2_RC',
                                ),
                              ),
                            ],

                            // Rent Agreement Link
                            if (resData['rentAgreementUrl'] != null) ...[
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () => onShowDoc(
                                  resData['rentAgreementUrl'].toString(),
                                  resData['rentAgreementFileName']?.toString() ?? 'Rent_Agreement',
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.description, size: 14, color: AppColors.primary),
                                    SizedBox(width: 4),
                                    Text(
                                      'View Rent Agreement',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
              label: const Text('Delete Flat', style: TextStyle(color: AppColors.error)),
              onPressed: () {
                Navigator.pop(context);
                onRemoveFlat(flatId);
              },
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

// ─── Reusable Vehicle Pending Card ──────────────────────────────────────────

class _VehiclePendingCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? rcUrl;
  final String rcFileName;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onViewDoc;

  const _VehiclePendingCard({
    required this.title,
    required this.icon,
    required this.rcUrl,
    required this.rcFileName,
    required this.onApprove,
    required this.onReject,
    required this.onViewDoc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          if (rcUrl != null && rcUrl!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InkWell(
                onTap: onViewDoc,
                child: const Text(
                  '📄 View Uploaded RC / Blue Book',
                  style: TextStyle(
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Approve', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 28),
                ),
                onPressed: onApprove,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.close, size: 14),
                label: const Text('Reject', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 28),
                ),
                onPressed: onReject,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
