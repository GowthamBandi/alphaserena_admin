import 'package:cloud_firestore/cloud_firestore.dart';

class TrainerModel {
  final String docId; // Firestore doc ID (random until first login)
  final String uid; // Firebase Auth UID (empty until trainer logs in)
  final String name;
  final String email;
  final String?
  password; // Store plaintext ONLY because you're matching for first-time login
  final String phone;
  final String? profilePicUrl;
  final String? specialization;
  final int? experience;
  final String? bio;
  final String status; // pending | active | blocked | suspended
  final String? assignedBy; // adminDocId or adminUid
  final List<String> clientIds;
  final bool isVerified;
  final Map<String, dynamic>? metadata;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  TrainerModel({
    required this.docId,
    required this.uid,
    required this.name,
    required this.email,
    this.password,
    required this.phone,
    this.profilePicUrl,
    this.specialization,
    this.experience,
    this.bio,
    required this.status,
    this.assignedBy,
    this.clientIds = const [],
    this.isVerified = false,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
  });

  // ----------------------------------------------------------------------
  // 🔥 SAFE PARSERS
  // ----------------------------------------------------------------------

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      return DateTime.tryParse(v) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  // ----------------------------------------------------------------------
  // 🔥 FROM MAP (normal constructor)
  // ----------------------------------------------------------------------
  factory TrainerModel.fromMap(Map<String, dynamic> map, String docId) {
    return TrainerModel(
      docId: docId,
      uid: map['uid']?.toString() ?? "", // empty until login
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      password: map['password'], // only used BEFORE auth creation
      phone: map['phone'] ?? '',
      profilePicUrl: map['profilePicUrl'],
      specialization: map['specialization'],
      experience: _parseInt(map['experience']),
      bio: map['bio'],
      status: map['status'] ?? 'pending',
      assignedBy: map['assignedBy'],
      clientIds: List<String>.from(map['clientIds'] ?? []),
      isVerified: map['isVerified'] ?? false,
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(map['metadata'])
          : null,
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
      lastLogin: map['lastLogin'] != null ? _parseDate(map['lastLogin']) : null,
    );
  }

  // ----------------------------------------------------------------------
  // 🔥 FROM SNAPSHOT (Firestore)
  // ----------------------------------------------------------------------
  factory TrainerModel.fromSnapshot(DocumentSnapshot snap) {
    final data = snap.data() as Map<String, dynamic>? ?? {};
    return TrainerModel.fromMap(data, snap.id);
  }

  // ----------------------------------------------------------------------
  // 🔥 TO MAP (for Firestore)
  // ----------------------------------------------------------------------
  Map<String, dynamic> toMap() => {
    'docId': docId,
    'uid': uid,
    'name': name,
    'email': email,
    'password': password,
    'phone': phone,
    'profilePicUrl': profilePicUrl,
    'specialization': specialization,
    'experience': experience,
    'bio': bio,
    'status': status,
    'assignedBy': assignedBy,
    'clientIds': clientIds,
    'isVerified': isVerified,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastLogin': lastLogin?.toIso8601String(),
  };

  // ----------------------------------------------------------------------
  // 🔥 COPYWITH (immutable model editing)
  // ----------------------------------------------------------------------
  TrainerModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? password,
    String? phone,
    String? profilePicUrl,
    String? specialization,
    int? experience,
    String? bio,
    String? status,
    String? assignedBy,
    List<String>? clientIds,
    bool? isVerified,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLogin,
  }) {
    return TrainerModel(
      docId: docId,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      password: password ?? this.password,
      phone: phone ?? this.phone,
      profilePicUrl: profilePicUrl ?? this.profilePicUrl,
      specialization: specialization ?? this.specialization,
      experience: experience ?? this.experience,
      bio: bio ?? this.bio,
      status: status ?? this.status,
      assignedBy: assignedBy ?? this.assignedBy,
      clientIds: clientIds ?? this.clientIds,
      isVerified: isVerified ?? this.isVerified,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }
}
