// lib/models/client_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class ClientModel {
  final String docId;
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String? profilePicUrl;
  final String? goal; // e.g. "Fat Loss", "Muscle Gain", etc.
  final String? gender;
  final int? age;
  final double? height; // in cm
  final double? weight; // in kg
  final String? trainerId; // assigned trainer
  final String? adminId; // who created / assigned
  final bool isActive;
  final bool isVerified;

  /// REAL membership state written by trainersHQ (membership CFs + the admin's
  /// extend/freeze feature). This — not the legacy `isActive`/`isVerified`
  /// fields (which the real `clients` doc never sets) — is the source of truth
  /// for a member being active. Read-only here (founder oversight).
  final bool membershipActive;
  final Map<String, dynamic>? progress; // e.g. weight logs
  final Map<String, dynamic>? metadata;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  ClientModel({
    required this.docId,
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.profilePicUrl,
    this.goal,
    this.gender,
    this.age,
    this.height,
    this.weight,
    this.trainerId,
    this.adminId,
    this.isActive = true,
    this.isVerified = false,
    this.membershipActive = false,
    this.progress,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
  });

  // Tolerant date parsing. Production `clients` docs store dates as a Firestore
  // Timestamp (server/CF writes); legacy/local writes may use an ISO String or a
  // DateTime; a field may be absent. Accept all shapes; never crash. (Fixes the
  // "Instance of 'Timestamp' is not a subtype of type 'String'" TypeError that
  // was thrown by passing a Timestamp straight into DateTime.tryParse(String).)
  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory ClientModel.fromMap(Map<String, dynamic> map) => ClientModel(
    docId: map['docId'] ?? '',
    uid: map['uid'] ?? '',
    name: map['name'] ?? '',
    email: map['email'] ?? '',
    phone: map['phone'] ?? '',
    profilePicUrl: map['profilePicUrl'],
    goal: map['goal'],
    gender: map['gender'],
    age: map['age'],
    height: (map['height'] != null)
        ? double.tryParse(map['height'].toString())
        : null,
    weight: (map['weight'] != null)
        ? double.tryParse(map['weight'].toString())
        : null,
    trainerId: map['trainerId'],
    adminId: map['adminId'],
    isActive: map['isActive'] ?? true,
    isVerified: map['isVerified'] ?? false,
    membershipActive: map['membershipActive'] == true,
    progress: map['progress'],
    metadata: map['metadata'],
    createdAt: _date(map['createdAt']) ?? DateTime.now(),
    updatedAt: _date(map['updatedAt']) ?? DateTime.now(),
    lastLogin: _date(map['lastLogin']),
  );

  Map<String, dynamic> toMap() => {
    'docId': docId,
    'uid': uid,
    'name': name,
    'email': email,
    'phone': phone,
    'profilePicUrl': profilePicUrl,
    'goal': goal,
    'gender': gender,
    'age': age,
    'height': height,
    'weight': weight,
    'trainerId': trainerId,
    'adminId': adminId,
    'isActive': isActive,
    'isVerified': isVerified,
    'progress': progress,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastLogin': lastLogin?.toIso8601String(),
  };

  ClientModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? profilePicUrl,
    String? goal,
    String? gender,
    int? age,
    double? height,
    double? weight,
    String? trainerId,
    String? adminId,
    bool? isActive,
    bool? isVerified,
    Map<String, dynamic>? progress,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLogin,
  }) {
    return ClientModel(
      docId: docId,
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
      goal: goal ?? this.goal,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      trainerId: trainerId ?? this.trainerId,
      adminId: adminId ?? this.adminId,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      progress: progress ?? this.progress,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }
}
