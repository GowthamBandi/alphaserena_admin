import 'package:cloud_firestore/cloud_firestore.dart';

/// =============================================================
/// SUBSCRIPTION LIMITS MODEL (SINGLE SOURCE OF TRUTH)
/// =============================================================
class AdminSubscriptionLimits {
  final int maxAdmins;
  final int maxTrainers;
  final int maxClients;
  final int maxWorkoutPlans;
  final int maxDietPlans;

  const AdminSubscriptionLimits({
    required this.maxAdmins,
    required this.maxTrainers,
    required this.maxClients,
    required this.maxWorkoutPlans,
    required this.maxDietPlans,
  });

  /// Empty limits → blocks everything (SAFE DEFAULT)
  factory AdminSubscriptionLimits.empty() {
    return const AdminSubscriptionLimits(
      maxAdmins: 0,
      maxTrainers: 0,
      maxClients: 0,
      maxWorkoutPlans: 0,
      maxDietPlans: 0,
    );
  }

  factory AdminSubscriptionLimits.fromMap(Map<String, dynamic>? map) {
    if (map == null) return AdminSubscriptionLimits.empty();

    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    return AdminSubscriptionLimits(
      maxAdmins: toInt(map['maxAdmins']),
      maxTrainers: toInt(map['maxTrainers']),
      maxClients: toInt(map['maxClients']),
      maxWorkoutPlans: toInt(map['maxWorkoutPlans']),
      maxDietPlans: toInt(map['maxDietPlans']),
    );
  }

  Map<String, dynamic> toMap() => {
    'maxAdmins': maxAdmins,
    'maxTrainers': maxTrainers,
    'maxClients': maxClients,
    'maxWorkoutPlans': maxWorkoutPlans,
    'maxDietPlans': maxDietPlans,
  };
}

/// =============================================================
/// ADMIN MODEL (PRODUCTION / SAAS READY)
/// =============================================================
class AdminModel {
  final String docId; // Firestore document ID
  final String uid; // Firebase Auth UID

  // Basic Info
  final String name;
  final String email;
  final String? password;
  final String phone;
  final String organizationName;

  // Role & Status
  final String role; // admin | super_admin
  final String status; // active | pending | blocked

  // Profile
  final String? profilePicUrl;
  final bool isVerified;

  // Address
  final String? address;
  final String? state;
  final String? area;
  final String? pincode;

  // Business
  final String? gstNumber;
  final String? panNumber;

  // Languages
  final List<String> spokenLanguages;

  // 🔒 Subscription (PAYMENT METADATA ONLY)
  final Map<String, dynamic>? subscription;

  // 🔥 LIMITS (REAL ENFORCEMENT SOURCE)
  final AdminSubscriptionLimits subscriptionLimits;

  final String? planName;
  final DateTime? planExpiry;
  final bool isSubscriptionActive;

  // Admin control
  final String? approvedBy;

  // System
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  // Relations
  final List<String> trainerIds;
  final List<String> clientIds;

  // Misc
  final Map<String, dynamic>? metadata;

  const AdminModel({
    required this.docId,
    required this.uid,
    required this.name,
    required this.email,
    this.password,
    required this.phone,
    required this.organizationName,
    required this.role,
    required this.status,
    this.profilePicUrl,
    this.isVerified = false,
    this.address,
    this.state,
    this.area,
    this.pincode,
    this.gstNumber,
    this.panNumber,
    this.spokenLanguages = const [],
    this.subscription,
    required this.subscriptionLimits,
    this.planName,
    this.planExpiry,
    this.isSubscriptionActive = false,
    this.approvedBy,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
    this.trainerIds = const [],
    this.clientIds = const [],
    this.metadata,
  });

  // -------------------------------------------------------------
  // DATE PARSER (STRICT + SAFE)
  // -------------------------------------------------------------
  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  // -------------------------------------------------------------
  // FROM MAP
  // -------------------------------------------------------------
  factory AdminModel.fromMap(Map<String, dynamic> map, String docId) {
    return AdminModel(
      docId: docId,
      uid: map['uid'] ?? docId,
      password: map['password'],
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      organizationName: map['organizationName'] ?? '',
      role: map['role'] ?? 'admin',
      status: map['status'] ?? 'pending',
      profilePicUrl: map['profilePicUrl'],
      isVerified: map['isVerified'] ?? false,

      // Address
      address: map['address'],
      state: map['state'],
      area: map['area'],
      pincode: map['pincode'],

      // Business
      gstNumber: map['gstNumber'],
      panNumber: map['panNumber'],

      // Languages
      spokenLanguages: List<String>.from(map['spokenLanguages'] ?? const []),

      // 🔒 PAYMENT METADATA ONLY
      subscription: map['subscription'] != null
          ? Map<String, dynamic>.from(map['subscription'])
          : null,

      // 🔥 LIMITS — FIXED SOURCE
      subscriptionLimits: AdminSubscriptionLimits.fromMap(
        map['subscriptionLimits'],
      ),

      planName: map['planName'],
      planExpiry: _parseDate(map['planExpiry']),
      isSubscriptionActive: map['isSubscriptionActive'] == true,

      approvedBy: map['approvedBy'],

      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']) ?? DateTime.now(),
      lastLogin: _parseDate(map['lastLogin']),

      trainerIds: List<String>.from(map['trainerIds'] ?? const []),
      clientIds: List<String>.from(map['clientIds'] ?? const []),

      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'])
          : null,
    );
  }

  factory AdminModel.fromSnapshot(DocumentSnapshot snap) {
    return AdminModel.fromMap(
      snap.data() as Map<String, dynamic>? ?? {},
      snap.id,
    );
  }

  // -------------------------------------------------------------
  // TO MAP
  // -------------------------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      'docId': docId,
      'uid': uid,
      'name': name,
      'email': email,
      'password': password,
      'phone': phone,
      'organizationName': organizationName,
      'role': role,
      'status': status,
      'profilePicUrl': profilePicUrl,
      'isVerified': isVerified,

      // Address
      'address': address,
      'state': state,
      'area': area,
      'pincode': pincode,

      // Business
      'gstNumber': gstNumber,
      'panNumber': panNumber,

      // Languages
      'spokenLanguages': spokenLanguages,

      // Subscription
      'subscription': subscription,
      'subscriptionLimits': subscriptionLimits.toMap(),
      'planName': planName,
      'planExpiry': planExpiry?.toIso8601String(),
      'isSubscriptionActive': isSubscriptionActive,

      'approvedBy': approvedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),

      'trainerIds': trainerIds,
      'clientIds': clientIds,
      'metadata': metadata,
    };
  }

  // -------------------------------------------------------------
  // COPY WITH
  // -------------------------------------------------------------
  AdminModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? organizationName,
    String? role,
    String? status,
    String? profilePicUrl,
    bool? isVerified,
    String? address,
    String? state,
    String? area,
    String? pincode,
    String? gstNumber,
    String? panNumber,
    List<String>? spokenLanguages,
    Map<String, dynamic>? subscription,
    AdminSubscriptionLimits? subscriptionLimits,
    String? planName,
    DateTime? planExpiry,
    bool? isSubscriptionActive,
    String? approvedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLogin,
    List<String>? trainerIds,
    List<String>? clientIds,
    Map<String, dynamic>? metadata,
  }) {
    return AdminModel(
      docId: docId,
      uid: uid,
      password: password,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      organizationName: organizationName ?? this.organizationName,
      role: role ?? this.role,
      status: status ?? this.status,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
      isVerified: isVerified ?? this.isVerified,
      address: address ?? this.address,
      state: state ?? this.state,
      area: area ?? this.area,
      pincode: pincode ?? this.pincode,
      gstNumber: gstNumber ?? this.gstNumber,
      panNumber: panNumber ?? this.panNumber,
      spokenLanguages: spokenLanguages ?? this.spokenLanguages,
      subscription: subscription ?? this.subscription,
      subscriptionLimits: subscriptionLimits ?? this.subscriptionLimits,
      planName: planName ?? this.planName,
      planExpiry: planExpiry ?? this.planExpiry,
      isSubscriptionActive: isSubscriptionActive ?? this.isSubscriptionActive,
      approvedBy: approvedBy ?? this.approvedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
      trainerIds: trainerIds ?? this.trainerIds,
      clientIds: clientIds ?? this.clientIds,
      metadata: metadata ?? this.metadata,
    );
  }
}
