import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../widgets/pdf_iframe.dart';

class ManageSocietyTab extends StatefulWidget {
  const ManageSocietyTab({super.key});

  @override
  State<ManageSocietyTab> createState() => _ManageSocietyTabState();
}

class _ManageSocietyTabState extends State<ManageSocietyTab> {
  bool _isUploading = false;
  String _searchQuery = '';

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
        final List<List<dynamic>> csvTable = CsvDecoder().convert(csvString);
        
        if (csvTable.length <= 1) {
          throw Exception("CSV file is empty or missing data rows.");
        }
        
        final header = csvTable.first.map((e) => e.toString().trim().toLowerCase()).toList();
        
        // Find column indices
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
          throw Exception("CSV must contain columns: Flat No, Owner Name, WhatsApp No, Mobile No");
        }

        const validBlocks = {'A', 'B', 'C', 'D'};
        int count = 0;
        List<String> errors = [];
        
        for (var i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.isEmpty || row.length <= flatIndex || row[flatIndex].toString().trim().isEmpty) continue;
          
          final flatNo = row[flatIndex].toString().trim();
          final name = row[nameIndex].toString().trim();
          final whatsapp = row[whatsappIndex].toString().trim();
          final mobile = row[mobileIndex].toString().trim();
          
          List<String> rowErrors = [];

          if (!RegExp(r'^\d{3}$').hasMatch(flatNo)) {
            rowErrors.add("Flat No must be 3 digits");
          }
          if (!RegExp(r'^\d{10}$').hasMatch(whatsapp)) {
            rowErrors.add("WhatsApp No must be 10 digits");
          }
          if (!RegExp(r'^\d{10}$').hasMatch(mobile)) {
            rowErrors.add("Mobile No must be 10 digits");
          }

          final block = blockIndex != -1 && row.length > blockIndex ? row[blockIndex].toString().trim().toUpperCase() : '';
          if (!validBlocks.contains(block)) {
            rowErrors.add("Block must be A, B, C or D");
          }
          
          final isCarOwner = carOwnerIndex != -1 && row.length > carOwnerIndex ? (row[carOwnerIndex].toString().trim().toLowerCase() == 'yes') : false;
          final carReg = carRegIndex != -1 && row.length > carRegIndex ? row[carRegIndex].toString().trim() : '';
          
          final isBikeOwner = bikeOwnerIndex != -1 && row.length > bikeOwnerIndex ? (row[bikeOwnerIndex].toString().trim().toLowerCase() == 'yes') : false;
          final bikeReg = bikeRegIndex != -1 && row.length > bikeRegIndex ? row[bikeRegIndex].toString().trim() : '';

          if (isCarOwner && carReg.isEmpty) {
            rowErrors.add("Car Reg No required");
          }
          if (isBikeOwner && bikeReg.isEmpty) {
            rowErrors.add("Bike Reg No required");
          }

          if (rowErrors.isNotEmpty) {
            errors.add("Row ${i + 1}: ${rowErrors.join(', ')}");
            continue;
          }

          await _saveRecord(flatNo, name, whatsapp, mobile, block, isCarOwner, carReg, isBikeOwner, bikeReg);
          count++;
        }
        
        if (mounted) {
          if (errors.isNotEmpty) {
            _showCsvErrorDialog(errors, count);
          } else {
            scaffoldMessenger.showSnackBar(SnackBar(content: Text('Successfully uploaded $count records!')));
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
              Text('Skipped ${errors.length} records due to validation errors:', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: errors.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text('- ${errors[index]}'),
                    );
                  },
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

  Future<void> _saveRecord(String flatNo, String name, String whatsapp, String mobile, String block, bool isCarOwner, String carReg, bool isBikeOwner, String bikeReg, {String role = 'Owner', String? rentAgreementUrl, String? rentAgreementFileName}) async {
    // 1. Ensure flat exists
    await FirebaseFirestore.instance.collection('flats').doc(flatNo).set({
      'flatNumber': flatNo,
      'block': block,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. Unset previous owner if we are adding a new Owner
    if (role == 'Owner') {
      final prevOwners = await FirebaseFirestore.instance
        .collection('users')
        .where('flatNumber', isEqualTo: flatNo)
        .where('role', isEqualTo: 'Owner')
        .get();
      
      for (var doc in prevOwners.docs) {
        await doc.reference.update({'role': 'Resident'});
      }
    }

    // 3. Create user
    final userData = {
      'name': name,
      'phone': '+91$mobile',
      'whatsapp': whatsapp,
      'flatNumber': flatNo,
      'block': block,
      'role': role,
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

    await FirebaseFirestore.instance.collection('users').add(userData);
  }

  void _addRecordDialog() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final flatController = TextEditingController();
    final nameController = TextEditingController();
    final whatsappController = TextEditingController();
    final mobileController = TextEditingController();
    final carRegController = TextEditingController();
    final bikeRegController = TextEditingController();
    
    String isCarOwner = 'No';
    String isBikeOwner = 'No';
    String? selectedBlock;
    bool hasAttemptedSubmit = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.person_add, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('Add Member Record'),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Flat Details Section
                      const Row(
                        children: [
                          Icon(Icons.home, color: Colors.deepPurple, size: 20),
                          SizedBox(width: 8),
                          Text('Flat Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: selectedBlock,
                              items: ['A', 'B', 'C', 'D'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                              onChanged: (val) => setDialogState(() => selectedBlock = val),
                              decoration: const InputDecoration(labelText: 'Block *', border: OutlineInputBorder(), isDense: true),
                              validator: (val) => val == null ? (hasAttemptedSubmit ? 'Required' : null) : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: flatController, 
                              decoration: const InputDecoration(labelText: 'Flat No. (3 digits) *', border: OutlineInputBorder(), isDense: true),
                              keyboardType: TextInputType.number,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return hasAttemptedSubmit ? 'Required' : null;
                                if (!RegExp(r'^\d{3}$').hasMatch(val.trim())) return 'Must be exactly 3 digits';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // 2. Owner Details Section
                      const Row(
                        children: [
                          Icon(Icons.person, color: Colors.deepPurple, size: 20),
                          SizedBox(width: 8),
                          Text('Owner Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController, 
                        decoration: const InputDecoration(labelText: 'Owner Name *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.badge)),
                        validator: (val) => val!.trim().isEmpty ? (hasAttemptedSubmit ? 'Required' : null) : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: whatsappController, 
                              decoration: const InputDecoration(labelText: 'WhatsApp No. *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.chat, size: 20)),
                              keyboardType: TextInputType.phone,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return hasAttemptedSubmit ? 'Required' : null;
                                if (!RegExp(r'^\d{10}$').hasMatch(val.trim())) return 'Must be 10 digits';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: mobileController, 
                              decoration: const InputDecoration(labelText: 'Mobile No. *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.phone, size: 20)),
                              keyboardType: TextInputType.phone,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return hasAttemptedSubmit ? 'Required' : null;
                                if (!RegExp(r'^\d{10}$').hasMatch(val.trim())) return 'Must be 10 digits';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // 3. Vehicles Section
                      const Row(
                        children: [
                          Icon(Icons.directions_car, color: Colors.deepPurple, size: 20),
                          SizedBox(width: 8),
                          Text('Vehicles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: isCarOwner,
                              items: ['Yes', 'No'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                              onChanged: (val) => setDialogState(() => isCarOwner = val!),
                              decoration: const InputDecoration(labelText: 'Car?', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          if (isCarOwner == 'Yes') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: carRegController, 
                                decoration: const InputDecoration(labelText: 'Car Reg. No. *', border: OutlineInputBorder(), isDense: true),
                                validator: (val) {
                                  if (isCarOwner == 'Yes' && (val == null || val.trim().isEmpty)) return hasAttemptedSubmit ? 'Required' : null;
                                  return null;
                                },
                              ),
                            ),
                          ] else const Expanded(flex: 2, child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: isBikeOwner,
                              items: ['Yes', 'No'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                              onChanged: (val) => setDialogState(() => isBikeOwner = val!),
                              decoration: const InputDecoration(labelText: 'Bike?', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          if (isBikeOwner == 'Yes') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: bikeRegController, 
                                decoration: const InputDecoration(labelText: 'Bike Reg. No. *', border: OutlineInputBorder(), isDense: true),
                                validator: (val) {
                                  if (isBikeOwner == 'Yes' && (val == null || val.trim().isEmpty)) return hasAttemptedSubmit ? 'Required' : null;
                                  return null;
                                },
                              ),
                            ),
                          ] else const Expanded(flex: 2, child: SizedBox()),
                        ],
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                onPressed: () async {
                  setDialogState(() => hasAttemptedSubmit = true);
                  if (!formKey.currentState!.validate()) return;
                  
                  setState(() => _isUploading = true);
                  Navigator.pop(ctx);
                  
                  try {
                    await _saveRecord(
                      flatController.text.trim(),
                      nameController.text.trim(),
                      whatsappController.text.trim(),
                      mobileController.text.trim(),
                      selectedBlock ?? '',
                      isCarOwner == 'Yes',
                      carRegController.text.trim(),
                      isBikeOwner == 'Yes',
                      bikeRegController.text.trim(),
                    );
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Record Added Successfully')));
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  } finally {
                    if (mounted) setState(() => _isUploading = false);
                  }
                },
              )
            ],
          );
        },
      ),
    );
  }

  void _addRenteeDialog(String flatId, String block) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final whatsappController = TextEditingController();
    final mobileController = TextEditingController();
    final carRegController = TextEditingController();
    final bikeRegController = TextEditingController();
    
    String isCarOwner = 'No';
    String isBikeOwner = 'No';
    bool hasAttemptedSubmit = false;
    PlatformFile? rentAgreementFile;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.person_add_alt_1, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text('Add Rentee to $block-$flatId'),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rentee Details Section
                      const Row(
                        children: [
                          Icon(Icons.person, color: Colors.deepPurple, size: 20),
                          SizedBox(width: 8),
                          Text('Rentee Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nameController, 
                        decoration: const InputDecoration(labelText: 'Rentee Name *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.badge)),
                        validator: (val) => val!.trim().isEmpty ? (hasAttemptedSubmit ? 'Required' : null) : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: whatsappController, 
                              decoration: const InputDecoration(labelText: 'WhatsApp No. *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.chat, size: 20)),
                              keyboardType: TextInputType.phone,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return hasAttemptedSubmit ? 'Required' : null;
                                if (!RegExp(r'^\d{10}$').hasMatch(val.trim())) return 'Must be 10 digits';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: mobileController, 
                              decoration: const InputDecoration(labelText: 'Mobile No. *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.phone, size: 20)),
                              keyboardType: TextInputType.phone,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return hasAttemptedSubmit ? 'Required' : null;
                                if (!RegExp(r'^\d{10}$').hasMatch(val.trim())) return 'Must be 10 digits';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Vehicles Section
                      const Row(
                        children: [
                          Icon(Icons.directions_car, color: Colors.deepPurple, size: 20),
                          SizedBox(width: 8),
                          Text('Vehicles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: isCarOwner,
                              items: ['Yes', 'No'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                              onChanged: (val) => setDialogState(() => isCarOwner = val!),
                              decoration: const InputDecoration(labelText: 'Car?', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          if (isCarOwner == 'Yes') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: carRegController, 
                                decoration: const InputDecoration(labelText: 'Car Reg. No. *', border: OutlineInputBorder(), isDense: true),
                                validator: (val) {
                                  if (isCarOwner == 'Yes' && (val == null || val.trim().isEmpty)) return hasAttemptedSubmit ? 'Required' : null;
                                  return null;
                                },
                              ),
                            ),
                          ] else const Expanded(flex: 2, child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: isBikeOwner,
                              items: ['Yes', 'No'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                              onChanged: (val) => setDialogState(() => isBikeOwner = val!),
                              decoration: const InputDecoration(labelText: 'Bike?', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          if (isBikeOwner == 'Yes') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: bikeRegController, 
                                decoration: const InputDecoration(labelText: 'Bike Reg. No. *', border: OutlineInputBorder(), isDense: true),
                                validator: (val) {
                                  if (isBikeOwner == 'Yes' && (val == null || val.trim().isEmpty)) return hasAttemptedSubmit ? 'Required' : null;
                                  return null;
                                },
                              ),
                            ),
                          ] else const Expanded(flex: 2, child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Rent Agreement Section
                      const Row(
                        children: [
                          Icon(Icons.description, color: Colors.deepPurple, size: 20),
                          SizedBox(width: 8),
                          Text('Rent Agreement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Select File'),
                            onPressed: () async {
                              final result = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
                              );
                              if (result != null && result.isNotEmpty) {
                                setDialogState(() {
                                  rentAgreementFile = result.first;
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              rentAgreementFile != null ? rentAgreementFile!.name : 'No file selected (Optional)',
                              style: TextStyle(
                                color: rentAgreementFile != null ? Colors.green : Colors.grey,
                                fontStyle: rentAgreementFile != null ? FontStyle.normal : FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (rentAgreementFile != null)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 20),
                              onPressed: () => setDialogState(() => rentAgreementFile = null),
                            )
                        ],
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                onPressed: () async {
                  setDialogState(() => hasAttemptedSubmit = true);
                  if (!formKey.currentState!.validate()) return;
                  
                  setState(() => _isUploading = true);
                  Navigator.pop(ctx);
                  
                  try {
                    String? downloadUrl;
                    String? fileName;
                    
                    if (rentAgreementFile != null) {
                      fileName = rentAgreementFile!.name;
                      final ref = FirebaseStorage.instance
                          .ref('rent_agreements/${flatId}_${DateTime.now().millisecondsSinceEpoch}_$fileName');
                      
                      // Read bytes and encode to base64 to avoid dart2js Int64 serialization bug in putData
                      final fileBytes = await rentAgreementFile!.readAsBytes();
                      final base64String = base64Encode(fileBytes);
                      
                      final metadata = SettableMetadata(
                        contentType: fileName.toLowerCase().endsWith('.pdf') 
                            ? 'application/pdf' 
                            : (fileName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg'),
                      );
                      await ref.putString(base64String, format: PutStringFormat.base64, metadata: metadata);
                      
                      downloadUrl = await ref.getDownloadURL();
                    }

                    await _saveRecord(
                      flatId,
                      nameController.text.trim(),
                      whatsappController.text.trim(),
                      mobileController.text.trim(),
                      block,
                      isCarOwner == 'Yes',
                      carRegController.text.trim(),
                      isBikeOwner == 'Yes',
                      bikeRegController.text.trim(),
                      role: 'Resident',
                      rentAgreementUrl: downloadUrl,
                      rentAgreementFileName: fileName,
                    );
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Rentee Added Successfully')));
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  } finally {
                    if (mounted) setState(() => _isUploading = false);
                  }
                },
              )
            ],
          );
        }
      ),
    );
  }

  void _editMemberDialog(String memberId, Map<String, dynamic> currentData) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: currentData['name']);
    final whatsappController = TextEditingController(text: currentData['whatsapp']?.toString());
    // Remove the '+91' prefix from phone if it exists
    String rawPhone = currentData['phone']?.toString() ?? '';
    if (rawPhone.startsWith('+91')) {
      rawPhone = rawPhone.substring(3);
    }
    final mobileController = TextEditingController(text: rawPhone);
    final carRegController = TextEditingController(text: currentData['carReg']);
    final bikeRegController = TextEditingController(text: currentData['bikeReg']);
    
    String isCarOwner = currentData['isCarOwner'] == true ? 'Yes' : 'No';
    String isBikeOwner = currentData['isBikeOwner'] == true ? 'Yes' : 'No';
    bool hasAttemptedSubmit = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.edit, color: Colors.blue),
                SizedBox(width: 8),
                Text('Edit Member Details'),
              ],
            ),
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
                        controller: nameController, 
                        decoration: const InputDecoration(labelText: 'Name *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.badge)),
                        validator: (val) => val!.trim().isEmpty ? (hasAttemptedSubmit ? 'Required' : null) : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: whatsappController, 
                              decoration: const InputDecoration(labelText: 'WhatsApp No. *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.chat, size: 20)),
                              keyboardType: TextInputType.phone,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return hasAttemptedSubmit ? 'Required' : null;
                                if (!RegExp(r'^\d{10}$').hasMatch(val.trim())) return 'Must be 10 digits';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: mobileController, 
                              decoration: const InputDecoration(labelText: 'Mobile No. *', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.phone, size: 20)),
                              keyboardType: TextInputType.phone,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return hasAttemptedSubmit ? 'Required' : null;
                                if (!RegExp(r'^\d{10}$').hasMatch(val.trim())) return 'Must be 10 digits';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: isCarOwner,
                              items: ['Yes', 'No'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                              onChanged: (val) => setDialogState(() => isCarOwner = val!),
                              decoration: const InputDecoration(labelText: 'Car?', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          if (isCarOwner == 'Yes') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: carRegController, 
                                decoration: const InputDecoration(labelText: 'Car Reg. No. *', border: OutlineInputBorder(), isDense: true),
                                validator: (val) {
                                  if (isCarOwner == 'Yes' && (val == null || val.trim().isEmpty)) return hasAttemptedSubmit ? 'Required' : null;
                                  return null;
                                },
                              ),
                            ),
                          ] else const Expanded(flex: 2, child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: isBikeOwner,
                              items: ['Yes', 'No'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                              onChanged: (val) => setDialogState(() => isBikeOwner = val!),
                              decoration: const InputDecoration(labelText: 'Bike?', border: OutlineInputBorder(), isDense: true),
                            ),
                          ),
                          if (isBikeOwner == 'Yes') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: bikeRegController, 
                                decoration: const InputDecoration(labelText: 'Bike Reg. No. *', border: OutlineInputBorder(), isDense: true),
                                validator: (val) {
                                  if (isBikeOwner == 'Yes' && (val == null || val.trim().isEmpty)) return hasAttemptedSubmit ? 'Required' : null;
                                  return null;
                                },
                              ),
                            ),
                          ] else const Expanded(flex: 2, child: SizedBox()),
                        ],
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                onPressed: () async {
                  setDialogState(() => hasAttemptedSubmit = true);
                  if (!formKey.currentState!.validate()) return;
                  
                  Navigator.pop(ctx);
                  
                  try {
                    await FirebaseFirestore.instance.collection('users').doc(memberId).update({
                      'name': nameController.text.trim(),
                      'phone': '+91${mobileController.text.trim()}',
                      'whatsapp': whatsappController.text.trim(),
                      'isCarOwner': isCarOwner == 'Yes',
                      'carReg': isCarOwner == 'Yes' ? carRegController.text.trim() : '',
                      'isBikeOwner': isBikeOwner == 'Yes',
                      'bikeReg': isBikeOwner == 'Yes' ? bikeRegController.text.trim() : '',
                    });
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Member Updated Successfully')));
                    }
                  } catch (e) {
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
              )
            ],
          );
        }
      ),
    );
  }

    void _showDocumentDialog(String url, String fileName) {
      final isImage = fileName.toLowerCase().endsWith('.jpg') || 
                      fileName.toLowerCase().endsWith('.jpeg') || 
                      fileName.toLowerCase().endsWith('.png');
      final isPdf = fileName.toLowerCase().endsWith('.pdf');

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
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (context, error, stackTrace) => const Center(child: Text('Error loading image')),
                  )
                )
              : isPdf
                ? buildPdfIframe(url)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.description, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text('Document: $fileName', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Preview is only available for images and PDFs. Please download to view other formats.'),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download / Open'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
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

  void _removeFlat(String flatId) {
    FirebaseFirestore.instance.collection('flats').doc(flatId).delete();
  }

  Future<void> _removeMember(String memberId, Map<String, dynamic> resData) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      if (resData['rentAgreementUrl'] != null && resData['rentAgreementUrl'].toString().isNotEmpty) {
        await FirebaseStorage.instance.refFromURL(resData['rentAgreementUrl']).delete();
      }
    } catch (e) {
      debugPrint('Error deleting rent agreement: $e');
      if (mounted) {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed to delete PDF from Storage: $e')));
      }
    }
    await FirebaseFirestore.instance.collection('users').doc(memberId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
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
                icon: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.upload_file),
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
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search Flat No.',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('flats').orderBy('flatNumber').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              
              var docs = snapshot.data?.docs ?? [];
              
              // Apply local search filter
              if (_searchQuery.trim().isNotEmpty) {
                docs = docs.where((doc) {
                  final flatId = doc.id;
                  final flatData = doc.data() as Map<String, dynamic>;
                  final block = flatData['block']?.toString().toLowerCase() ?? '';
                  final query = _searchQuery.trim().toLowerCase();
                  return flatId.toLowerCase().contains(query) || block.contains(query);
                }).toList();
              }

              if (docs.isEmpty) return const Center(child: Text('No flats found.'));

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final flatId = docs[index].id;
                  final flatData = docs[index].data() as Map<String, dynamic>;
                  final block = flatData['block'] ?? '';
                  final flatLabel = block.isNotEmpty ? 'Flat: $block-$flatId' : 'Flat: $flatId';
                  final isRented = flatData['isRented'] == true;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ExpansionTile(
                      title: Text(flatLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeFlat(flatId),
                        tooltip: 'Remove Flat',
                      ),
                      children: [
                        SwitchListTile(
                          title: const Text('Is this flat rented?', style: TextStyle(fontWeight: FontWeight.bold)),
                          value: isRented,
                          activeThumbColor: Colors.deepPurple,
                          onChanged: (val) {
                            FirebaseFirestore.instance.collection('flats').doc(flatId).update({'isRented': val});
                          },
                        ),
                        if (isRented)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text('Add Rentee'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                                onPressed: () => _addRenteeDialog(flatId, block),
                              ),
                            ),
                          ),
                        const Divider(),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .where('flatNumber', isEqualTo: flatId)
                              .snapshots(),
                          builder: (context, resSnap) {
                            if (!resSnap.hasData) return const SizedBox();
                            final resDocs = resSnap.data!.docs;
                            if (resDocs.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No members assigned to this flat yet.', style: TextStyle(color: Colors.grey)),
                              );
                            }
                            return Column(
                              children: resDocs.map((resDoc) {
                                final resData = resDoc.data() as Map<String, dynamic>;
                                final role = resData['role'] ?? 'Unknown';
                                final isCarOwner = resData['isCarOwner'] == true;
                                final isBikeOwner = resData['isBikeOwner'] == true;
                                
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: role == 'Owner' ? Colors.deepPurple : Colors.blueGrey,
                                    child: Icon(role == 'Owner' ? Icons.home : Icons.person, color: Colors.white),
                                  ),
                                  title: Text(resData['name'] ?? 'Unknown'),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${resData['phone'] ?? ''} • $role'),
                                      if (resData['whatsapp'] != null && resData['whatsapp'].toString().isNotEmpty) 
                                        Text('WA: ${resData['whatsapp']}'),
                                      if (isCarOwner) Text('Car: ${resData['carReg']}'),
                                      if (isBikeOwner) Text('Bike: ${resData['bikeReg']}'),
                                      if (resData['rentAgreementUrl'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4.0),
                                            child: InkWell(
                                              onTap: () {
                                                final url = resData['rentAgreementUrl']?.toString() ?? '';
                                                final fileName = resData['rentAgreementFileName']?.toString() ?? 'Document';
                                                _showDocumentDialog(url, fileName);
                                              },
                                              child: const Text(
                                                'View Rent Agreement',
                                              style: TextStyle(color: Colors.deepPurple, decoration: TextDecoration.underline),
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
                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                        onPressed: () => _removeMember(resDoc.id, resData),
                                        tooltip: 'Remove Member',
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        )
                      ],
                    ),
                  );
                },
              );
            }
          ),
        )
      ],
    );
  }
}



