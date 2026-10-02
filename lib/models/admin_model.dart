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

  // Moderation trail — written by the founder console's status actions
  // (admin_controller/_setStatus + dashboard approveOrg): statusReason /
  // statusUpdatedBy (actor uid) / statusUpdatedAt. Read-only here for traceability.
  final String? statusReason;
  final String? statusUpdatedBy;
  final DateTime? statusUpdatedAt;

  // System
  final DateTime createdAt;

  /// False when the document carries no readable `createdAt`. [createdAt] is
  /// then a parse-time placeholder, never a fact: the Organizations screen
  /// prints "Creation date not recorded" instead of a date and sorts such
  /// records last. Legacy documents seeded before timestamps were stamped are
  /// the known case.
  final bool createdAtKnown;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  // Relations
  final List<String> trainerIds;
  final List<String> clientIds;

  // Misc
  /// OWNER-EDITABLE (the rules do not denylist `metadata`). Never present a
  /// key under it — `createdFrom`, `features` — as a platform fact.
  final Map<String, dynamic>? metadata;

  /// The plan-projected capability whitelist, read from the TOP-LEVEL
  /// `features` key that `grantSubscription` / the online activation write and
  /// the coach app's `hasFeature()` gate reads (server-only under the rules).
  ///
  /// TRI-STATE, exactly as the backend reads it (lib/payments.ts):
  ///   • null — the field is ABSENT: a legacy, ungated organization;
  ///   • []   — present and empty: every gated feature is denied;
  ///   • [..] — the slugs the organization may use.
  final List<String>? features;

  /// Fields that are PRESENT on the document with a type this console cannot
  /// read as intended. The record still parses — each such field reads as a
  /// blank / default — so the organization stays listed, counted and
  /// moderatable. An owner can write most profile keys with any type (the
  /// rules denylist only the commercial and moderation keys), so one
  /// type-drifted write used to throw inside the whole-list parse and blank
  /// the founder's Organizations list: the org that caused it vanished from
  /// moderation along with everyone else.
  final List<String> malformedFields;

  /// True when the document could not be parsed at all and this row is a
  /// placeholder carrying only what could be read (its id, and its status
  /// when that was readable). Never skipped: an unreadable organization is
  /// exactly the one the founder must still be able to find and block.
  final bool unreadable;

  bool get hasMalformedFields => unreadable || malformedFields.isNotEmpty;

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
    this.statusReason,
    this.statusUpdatedBy,
    this.statusUpdatedAt,
    required this.createdAt,
    this.createdAtKnown = true,
    required this.updatedAt,
    this.lastLogin,
    this.trainerIds = const [],
    this.clientIds = const [],
    this.metadata,
    this.features,
    this.malformedFields = const [],
    this.unreadable = false,
  });

  /// The status exactly as the console's fresh server read normalises it
  /// (`AdminController._freshStatusFromServer`): missing → `pending`,
  /// `approved` → `active`, anything else as its text. Both sides MUST agree,
  /// or a record with an odd status could never pass the stale-decision guard
  /// and could never be moderated.
  static String normalizeStatus(dynamic raw) {
    if (raw == null) return 'pending';
    final s = raw.toString();
    return s == 'approved' ? 'active' : s;
  }

  // -------------------------------------------------------------
  // FROM MAP — tolerant PER FIELD (never throws on a wrong type)
  // -------------------------------------------------------------
  factory AdminModel.fromMap(Map<String, dynamic> map, String docId) {
    final r = _FieldReader(map);
    final created = r.date('createdAt');
    final rawStatus = map['status'];
    if (rawStatus != null && rawStatus is! String) r.bad.add('status');
    final uid = r.str('uid');
    final limits = r.mapOrNull('subscriptionLimits');
    final model = AdminModel(
      docId: docId,
      uid: uid.isEmpty ? docId : uid,
      password: r.strOrNull('password'),
      name: r.str('name'),
      email: r.str('email'),
      phone: r.str('phone'),
      organizationName: r.str('organizationName'),
      role: r.str('role', 'admin'),
      // trainersHQ's own super-admin screen can set status 'approved' (approved,
      // not-yet-subscribed). This console models active|pending|warning|blocked;
      // normalize 'approved'→'active' so such orgs stay visible + counted +
      // actionable (subscription state is shown separately via isSubscriptionActive).
      status: normalizeStatus(rawStatus),
      profilePicUrl: r.strOrNull('profilePicUrl'),
      isVerified: r.boolean('isVerified', false),

      // Address
      address: r.strOrNull('address'),
      state: r.strOrNull('state'),
      area: r.strOrNull('area'),
      pincode: r.strOrNull('pincode'),

      // Business
      gstNumber: r.strOrNull('gstNumber'),
      panNumber: r.strOrNull('panNumber'),

      // Languages
      spokenLanguages: r.strList('spokenLanguages'),

      // 🔒 PAYMENT METADATA ONLY
      subscription: r.mapOrNull('subscription'),

      // 🔥 LIMITS — FIXED SOURCE
      subscriptionLimits: AdminSubscriptionLimits.fromMap(limits),

      planName: r.strOrNull('planName'),
      planExpiry: r.date('planExpiry'),
      isSubscriptionActive: r.boolean('isSubscriptionActive', false),

      approvedBy: r.strOrNull('approvedBy'),
      statusReason: r.strOrNull('statusReason'),
      statusUpdatedBy: r.strOrNull('statusUpdatedBy'),
      statusUpdatedAt: r.date('statusUpdatedAt'),

      createdAt: created ?? DateTime.now(),
      createdAtKnown: created != null,
      updatedAt: r.date('updatedAt') ?? DateTime.now(),
      lastLogin: r.date('lastLogin'),

      trainerIds: r.strList('trainerIds'),
      clientIds: r.strList('clientIds'),

      metadata: r.mapOrNull('metadata'),
      features: r.strListOrNull('features'),
      malformedFields: List.unmodifiable(r.bad),
    );
    return model;
  }

  /// A row for a document that could not be parsed at all. Carries its id
  /// and — when readable — its status, so the organization is still listed
  /// and the founder can still moderate it.
  factory AdminModel.unreadableRecord(String docId, {dynamic rawStatus}) =>
      AdminModel(
        docId: docId,
        uid: docId,
        name: '',
        email: '',
        phone: '',
        organizationName: '',
        role: 'admin',
        status: normalizeStatus(rawStatus),
        subscriptionLimits: AdminSubscriptionLimits.empty(),
        createdAt: DateTime.now(),
        createdAtKnown: false,
        updatedAt: DateTime.now(),
        malformedFields: const ['(the whole record)'],
        unreadable: true,
      );

  /// Parses ONE document and never throws: a document that defeats even the
  /// per-field reader becomes an [unreadableRecord] placeholder. Every list
  /// that shows organizations builds its rows through this, one document at
  /// a time, so no single record can take the others down with it.
  static AdminModel parseDoc(String docId, Object? data) {
    if (data is Map) {
      try {
        return AdminModel.fromMap(
          data.map((k, v) => MapEntry(k.toString(), v)),
          docId,
        );
      } catch (e) {
        return AdminModel.unreadableRecord(docId, rawStatus: data['status']);
      }
    }
    return AdminModel.unreadableRecord(docId);
  }

  factory AdminModel.fromSnapshot(DocumentSnapshot snap) =>
      parseDoc(snap.id, snap.data());

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
      createdAtKnown: createdAtKnown,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
      trainerIds: trainerIds ?? this.trainerIds,
      clientIds: clientIds ?? this.clientIds,
      metadata: metadata ?? this.metadata,
      features: features,
      malformedFields: malformedFields,
      unreadable: unreadable,
    );
  }
}

/// Reads one Firestore map field by field, recording every field that is
/// present with the wrong type instead of throwing. A readable scalar in a
/// text field (a number typed as the phone) is kept as its text AND recorded.
class _FieldReader {
  _FieldReader(this.map);
  final Map<String, dynamic> map;
  final List<String> bad = [];

  void _flag(String k) {
    if (!bad.contains(k)) bad.add(k);
  }

  String str(String k, [String fallback = '']) {
    final v = map[k];
    if (v == null) return fallback;
    if (v is String) return v;
    _flag(k);
    return (v is num || v is bool) ? v.toString() : fallback;
  }

  String? strOrNull(String k) {
    final v = map[k];
    if (v == null) return null;
    if (v is String) return v;
    _flag(k);
    return (v is num || v is bool) ? v.toString() : null;
  }

  List<String> strList(String k) => strListOrNull(k) ?? const [];

  List<String>? strListOrNull(String k) {
    final v = map[k];
    if (v == null) return null;
    if (v is! List) {
      _flag(k);
      return null;
    }
    final out = <String>[];
    for (final e in v) {
      if (e is String) {
        out.add(e);
      } else if (e is num || e is bool) {
        _flag(k);
        out.add(e.toString());
      } else {
        _flag(k);
      }
    }
    return out;
  }

  Map<String, dynamic>? mapOrNull(String k) {
    final v = map[k];
    if (v == null) return null;
    if (v is Map) return v.map((key, val) => MapEntry(key.toString(), val));
    _flag(k);
    return null;
  }

  bool boolean(String k, bool fallback) {
    final v = map[k];
    if (v == null) return fallback;
    if (v is bool) return v;
    _flag(k);
    return fallback;
  }

  /// A present value that is not a readable date is MALFORMED, not absent:
  /// the backend's `toEpochMs` cannot read it either (a plain
  /// `{seconds, nanoseconds}` map, an unparseable string), so for
  /// `planExpiry` it is the "never expires" state and must be named.
  DateTime? date(String k) {
    final v = map[k];
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      final d = DateTime.tryParse(v);
      if (d == null) _flag(k);
      return d;
    }
    _flag(k);
    return null;
  }
}
