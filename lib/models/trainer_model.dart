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

  /// Free TEXT, e.g. "8 years" — NOT a number.
  ///
  /// The canonical type is set by the two writers that own this document:
  /// the backend's `createTrainer` writes `optionalString(experience)`, and
  /// TrainerHQ's profile editor writes the coach's own free text. This console
  /// previously modelled it as `int?`, so `int.tryParse("8 years")` read null
  /// and the next save here silently WIPED the coach's experience.
  final String? experience;
  final String? bio;

  /// pending | active | blocked | suspended | **removed**
  ///
  /// `removed` is what `removeTrainer` writes (trainers.ts:507). It is NOT a
  /// deactivation: `setTrainerStatus` refuses to touch a removed trainer at all
  /// (trainers.ts:399-404), and only `restoreTrainer` can bring one back.
  final String status;

  /// Soft-delete marker written alongside `status: 'removed'`.
  ///
  /// Modelled explicitly because the console was structurally blind to it —
  /// `grep -c isDeleted` over this file and the controller returned 0 and 0 —
  /// so a DELETED coach and a DEACTIVATED coach were the same row and the same
  /// number. They are different facts about the organization: the removed uid
  /// is arrayRemoved from `admins/{uid}.trainerIds`, so it occupies no seat.
  final bool isDeleted;

  /// When the soft delete happened. Null unless [isDeleted].
  final DateTime? removedAt;
  final String? assignedBy; // adminDocId or adminUid

  /// The organization's operate-state, denormalized onto the trainer by the
  /// backend's `propagateOrgActive` (status not pending/blocked AND the
  /// subscription active). Null when the document has never been stamped.
  /// Read-only here: the Organizations workspace compares it with the state
  /// computed from the organization record to detect a stale cascade.
  final bool? orgActive;

  /// The owner-set permission map (`workoutPlans`, `dietPlans`, `weeklyPlans`,
  /// `exercises`, `food` → bool) and its schema version, written by
  /// `createTrainer` / `setTrainerPermissions`. Read-only here.
  final Map<String, dynamic>? permissions;
  final int? permissionsVersion;
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
    this.isDeleted = false,
    this.removedAt,
    this.assignedBy,
    this.orgActive,
    this.permissions,
    this.permissionsVersion,
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

  /// Tolerant read for the free-text experience field.
  ///
  /// Legacy documents this console itself wrote hold a NUMBER, so a plain cast
  /// would throw on them. Coercing preserves those values as text ("8") rather
  /// than discarding them, and reads TrainerHQ's free text ("8 years") intact.
  static String? _experienceText(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  // ----------------------------------------------------------------------
  // 🔥 FROM MAP (normal constructor)
  // ----------------------------------------------------------------------
  // Tolerant per-field readers. A trainer document is partly written by the
  // trainer's own app, so a field of the wrong type must read as blank —
  // never throw and take the whole organization's trainer list down with it.
  static String _s(dynamic v, [String fallback = '']) =>
      v is String ? v : ((v is num || v is bool) ? v.toString() : fallback);
  static String? _sn(dynamic v) =>
      v is String ? v : ((v is num || v is bool) ? v.toString() : null);

  factory TrainerModel.fromMap(Map<String, dynamic> map, String docId) {
    final rawClients = map['clientIds'];
    return TrainerModel(
      docId: docId,
      uid: map['uid']?.toString() ?? "", // empty until login
      name: _s(map['name']),
      email: _s(map['email']),
      password: _sn(map['password']), // only used BEFORE auth creation
      phone: _s(map['phone']),
      profilePicUrl: _sn(map['profilePicUrl']),
      specialization: _sn(map['specialization']),
      experience: _experienceText(map['experience']),
      bio: _sn(map['bio']),
      status: _s(map['status'], 'pending'),
      // Defensive: production writes a real bool, but a legacy/absent field
      // must read as NOT deleted rather than throwing or silently hiding a
      // live coach.
      isDeleted: map['isDeleted'] == true,
      removedAt: map['removedAt'] == null ? null : _parseDate(map['removedAt']),
      assignedBy: _sn(map['assignedBy']),
      orgActive: map['orgActive'] is bool ? map['orgActive'] as bool : null,
      permissions: map['permissions'] is Map
          ? Map<String, dynamic>.from(map['permissions'] as Map)
          : null,
      permissionsVersion: map['permissionsVersion'] is num
          ? (map['permissionsVersion'] as num).toInt()
          : null,
      clientIds: rawClients is List
          ? rawClients.whereType<Object>().map((e) => e.toString()).toList()
          : const [],
      isVerified: map['isVerified'] == true,
      metadata: map['metadata'] is Map
          ? Map<String, dynamic>.from(map['metadata'] as Map)
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
    'isDeleted': isDeleted,
    if (removedAt != null) 'removedAt': removedAt,
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
    String? experience,
    String? bio,
    String? status,
    bool? isDeleted,
    DateTime? removedAt,
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
      isDeleted: isDeleted ?? this.isDeleted,
      removedAt: removedAt ?? this.removedAt,
      assignedBy: assignedBy ?? this.assignedBy,
      orgActive: orgActive,
      permissions: permissions,
      permissionsVersion: permissionsVersion,
      clientIds: clientIds ?? this.clientIds,
      isVerified: isVerified ?? this.isVerified,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }
}
