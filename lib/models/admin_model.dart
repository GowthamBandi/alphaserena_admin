import 'package:cloud_firestore/cloud_firestore.dart';

/// =============================================================
/// SUBSCRIPTION LIMITS MODEL
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

  factory AdminSubscriptionLimits.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const AdminSubscriptionLimits(
        maxAdmins: 1,
        maxTrainers: 1,
        maxClients: 3,
        maxWorkoutPlans: 10,
        maxDietPlans: 10,
      );
    }

    return AdminSubscriptionLimits(
      maxAdmins: map['maxAdmins'] ?? 1,
      maxTrainers: map['maxTrainers'] ?? 1,
      maxClients: map['maxClients'] ?? 3,
      maxWorkoutPlans: map['maxWorkoutPlans'] ?? 10,
      maxDietPlans: map['maxDietPlans'] ?? 10,
    );
  }

  Map<String, dynamic> toMap() => {
    "maxAdmins": maxAdmins,
    "maxTrainers": maxTrainers,
    "maxClients": maxClients,
    "maxWorkoutPlans": maxWorkoutPlans,
    "maxDietPlans": maxDietPlans,
  };
}

/// =============================================================
/// ADMIN MODEL
/// =============================================================
class AdminModel {
  final String docId; // Firestore document ID
  final String uid; // Firebase Auth UID

  final String name;
  final String email;
  final String? password;
  final String phone;
  final String organizationName;

  final String role;
  final String status;

  // Profile
  final String? profilePicUrl;
  final bool isVerified;
  final String? address;
  final String? gstNumber;
  final String? panNumber;

  // Subscription (raw map) & extracted limits
  final Map<String, dynamic>? subscription;
  final AdminSubscriptionLimits subscriptionLimits;

  final String? planName;
  final DateTime? planExpiry;
  final bool isSubscriptionActive;

  // Extra
  final String? approvedBy;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  final List<String> trainerIds;
  final List<String> clientIds;

  final Map<String, dynamic>? metadata;

  const AdminModel({
    required this.docId,
    required this.uid,
    this.password,
    required this.name,
    required this.email,
    required this.phone,
    required this.organizationName,
    required this.role,
    required this.status,
    this.profilePicUrl,
    this.isVerified = false,
    this.address,
    this.gstNumber,
    this.panNumber,

    // subscription
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

  // ------------------------------------------
  // DATE HELPER
  // ------------------------------------------
  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  // ------------------------------------------
  // FROM MAP
  // ------------------------------------------
  factory AdminModel.fromMap(Map<String, dynamic> map, String docId) {
    final subscriptionMap = map['subscription'] != null
        ? Map<String, dynamic>.from(map['subscription'])
        : null;

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
      address: map['address'],
      gstNumber: map['gstNumber'],
      panNumber: map['panNumber'],

      subscription: subscriptionMap,
      subscriptionLimits: AdminSubscriptionLimits.fromMap(
        subscriptionMap,
      ), // <-- extracted limits

      planName: map['planName'],
      planExpiry: map['planExpiry'] != null
          ? _parseDate(map['planExpiry'])
          : null,
      isSubscriptionActive: map['isSubscriptionActive'] ?? false,

      approvedBy: map['approvedBy'],

      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
      lastLogin: map['lastLogin'] != null ? _parseDate(map['lastLogin']) : null,

      trainerIds: List<String>.from(map['trainerIds'] ?? []),
      clientIds: List<String>.from(map['clientIds'] ?? []),

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

  // ------------------------------------------
  // TO MAP
  // ------------------------------------------
  Map<String, dynamic> toMap() {
    return {
      "docId": docId,
      "uid": uid,
      "name": name,
      "email": email,
      "password": password,
      "phone": phone,
      "organizationName": organizationName,
      "role": role,
      "status": status,
      "profilePicUrl": profilePicUrl,
      "isVerified": isVerified,
      "address": address,
      "gstNumber": gstNumber,
      "panNumber": panNumber,

      "subscription": subscription, // keeps raw map
      "planName": planName,
      "planExpiry": planExpiry?.toIso8601String(),
      "isSubscriptionActive": isSubscriptionActive,

      "approvedBy": approvedBy,
      "createdAt": createdAt.toIso8601String(),
      "updatedAt": updatedAt.toIso8601String(),
      "lastLogin": lastLogin?.toIso8601String(),

      "trainerIds": trainerIds,
      "clientIds": clientIds,
      "metadata": metadata,
    };
  }

  // ------------------------------------------
  // COPY WITH
  // ------------------------------------------
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
    String? gstNumber,
    String? panNumber,
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
      gstNumber: gstNumber ?? this.gstNumber,
      panNumber: panNumber ?? this.panNumber,

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
