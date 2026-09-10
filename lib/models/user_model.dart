import 'package:cloud_firestore/cloud_firestore.dart';

/// Strongly-typed User entity for authentication, roles, and resident profiles
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String role; // 'ADMIN', 'RESIDENT', 'GUARD'
  final String flatNumber;
  final String? block;
  final String? residentType; // 'Owner', 'Tenant'
  final String? carRegistration;
  final String? bike1Registration;
  final String? bike2Registration;
  final DateTime? createdAt;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.flatNumber,
    this.block,
    this.residentType,
    this.carRegistration,
    this.bike1Registration,
    this.bike2Registration,
    this.createdAt,
  });

  bool get isAdmin => role.toUpperCase() == 'ADMIN';
  bool get isResident => role.toUpperCase() == 'RESIDENT';
  bool get isGuard => role.toUpperCase() == 'GUARD';

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return AppUser(
      uid: doc.id,
      name: (data['name'] ?? data['ownerName'] ?? 'User').toString(),
      email: (data['email'] ?? data['username'] ?? '').toString(),
      phone: (data['phone'] ?? data['mobile'] ?? '').toString(),
      role: (data['role'] ?? 'RESIDENT').toString(),
      flatNumber: (data['flatNumber'] ?? '').toString(),
      block: data['block']?.toString(),
      residentType: data['residentType']?.toString(),
      carRegistration: data['carRegistration']?.toString(),
      bike1Registration: data['bike1Registration']?.toString() ?? data['bikeRegistration']?.toString(),
      bike2Registration: data['bike2Registration']?.toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role,
      'flatNumber': flatNumber,
      if (block != null) 'block': block,
      if (residentType != null) 'residentType': residentType,
      if (carRegistration != null) 'carRegistration': carRegistration,
      if (bike1Registration != null) 'bike1Registration': bike1Registration,
      if (bike2Registration != null) 'bike2Registration': bike2Registration,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    };
  }
}

