// lib/models/clints_model.dart  (legacy file name — the collection is `clients`)
//
// THE MEMBER RECORD, AS ITS WRITERS ACTUALLY SHAPE IT.
//
// `clients/{id}` is written by sixteen backend paths and seven coach-app paths
// (catalogued 2026-09-24 from memberships.ts, scheduled.ts, assignments_coach.ts,
// profile.ts, activation.ts, engagement.ts, progress.ts, nutrition.ts,
// prescriptions.ts, member_deletion.ts and trainersHQ's client/membership/
// check-in services). The previous model here knew nine of its fields and
// invented two (`isActive`, `isVerified`) that no writer sets. What it did
// not know, the Members screen could not show — and a founder console that
// cannot see a member's membership expiry, coach, activity or account state
// is not oversight.
//
// FACTS THIS MODEL ENCODES (each one cost a defect somewhere before):
//   • The DOCUMENT ID IS RANDOM. The member's Auth uid is `authUid`, and one
//     person can hold several records — one per organization they joined.
//   • `name` is often EMPTY on backend-created records; the real display name
//     lives in `sharedProfile.identity.displayName`. Resolution is per field
//     (see MemberLanguage.displayName), mirroring trainersHQ's
//     `resolveClientIdentity`.
//   • `trainerId` absent or "" means COACHED BY THE OWNER (`adminId`), not
//     "coachless" — the payment writers never set it.
//   • Membership state is DERIVED from `membershipExpiry` + `membershipFrozen`,
//     not read from `membershipActive`: the hourly `expireMemberships` sweep
//     lags, so the flag can say active after the expiry has passed.
//   • Dates arrive as Firestore Timestamps (createdAt, updatedAt,
//     lastActivityAt…), UTC ISO strings (membershipExpiry, membership.*) and
//     LOCAL ISO strings without a zone (membershipFrozenAt, lastCheckInAt,
//     nextCheckInAt). Every date is parsed through one tolerant helper.
//   • A member who deletes their account is NOT deleted here: `authUid` is
//     removed and `authUnlinkedAt` / `authUnlinkReason` are stamped. There is
//     no soft-delete flag on members today; `isDeleted` is read defensively
//     because the Dashboard headcount subtracts it, and the two must agree.

import 'package:cloud_firestore/cloud_firestore.dart';

/// Tolerant date parsing shared by every member field.
DateTime? memberDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
  if (v is num) {
    // Epoch millis (some rollups) — never seconds, the platform uses ms.
    if (v > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    }
  }
  return null;
}

Map<String, dynamic>? _map(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}

class ClientModel {
  final String docId;

  /// Legacy alias kept for older call sites; equals [docId] unless the record
  /// carries an explicit `uid` field (none of the current writers set one).
  final String uid;

  /// The member's Firebase Auth uid, or empty when the record was never
  /// claimed or the member deleted their account (see [authUnlinkedAt]).
  final String authUid;

  final String name;
  final String email;
  final String phone;
  final String? profilePicUrl;
  final String? goal;
  final String? gender;
  final int? age;
  final double? height; // cm
  final double? weight; // kg

  /// Delegated coach (a trainer uid). Empty ⇒ coached by the owner.
  final String? trainerId;

  /// The organization (`admins/{uid}`) this record belongs to.
  final String? adminId;

  /// `active` | `inactive` — the owner's on/off switch for the member inside
  /// the coach app. Missing reads as active (the producer's own default).
  final String status;

  // Legacy console-only flags. NO writer sets them; kept so old call sites
  // compile. Never displayed, never counted.
  final bool isActive;
  final bool isVerified;

  // ── membership ────────────────────────────────────────────────────────────
  final bool membershipActive;
  final DateTime? membershipExpiry;
  final bool membershipFrozen;
  final DateTime? membershipFrozenAt;

  /// The current term as the activating writer left it: planId, planName,
  /// amount (rupees), months, durationValue, durationUnit, termStartAt,
  /// startedAt, expiry, method, source, couponCode, couponDiscount,
  /// razorpayOrderId, razorpayPaymentId.
  final Map<String, dynamic>? membership;

  // ── projections written only by the backend ───────────────────────────────
  final Map<String, dynamic>? sharedProfile;
  final DateTime? sharedProfileAt;
  final DateTime? lastActivityAt;

  /// onboarding | awaitingTrainer | preparingPlan | ready
  final String? activationStage;
  final DateTime? activationStageAt;

  /// {score, workoutPct, dietPct, windowDays, computedAt}
  final Map<String, dynamic>? adherence;
  final Map<String, dynamic>? nutritionTargets;
  final Map<String, dynamic>? dietTargets;
  final Map<String, dynamic>? lifestyleTargets;
  final List<dynamic> supplementPlan;
  final Map<String, dynamic>? coachingPause;
  final Map<String, dynamic>? notif;

  // ── check-in cadence (coach app) ──────────────────────────────────────────
  final int? checkInCadenceDays;
  final DateTime? lastCheckInAt;
  final DateTime? nextCheckInAt;

  /// active | paused | cancelled | archived (absent ⇒ active)
  final String? scheduleStatus;

  // ── account deletion (member app) ─────────────────────────────────────────
  final DateTime? authUnlinkedAt;
  final String? authUnlinkReason;
  final String? authUnlinkedFrom;

  /// No writer sets this on members today; read so the list agrees with the
  /// Dashboard headcount, which subtracts it.
  final bool isDeleted;

  final Map<String, dynamic>? progress;
  final Map<String, dynamic>? metadata;

  final DateTime createdAt;

  /// FALSE when the document carried no usable creation date and [createdAt]
  /// was defaulted to "now" — such a member is counted in no month bucket.
  final bool createdAtKnown;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  /// The whole document, for the technical view. Never used for logic.
  final Map<String, dynamic> raw;

  ClientModel({
    required this.docId,
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.authUid = '',
    this.profilePicUrl,
    this.goal,
    this.gender,
    this.age,
    this.height,
    this.weight,
    this.trainerId,
    this.adminId,
    this.status = 'active',
    this.isActive = true,
    this.isVerified = false,
    this.membershipActive = false,
    this.membershipExpiry,
    this.membershipFrozen = false,
    this.membershipFrozenAt,
    this.membership,
    this.sharedProfile,
    this.sharedProfileAt,
    this.lastActivityAt,
    this.activationStage,
    this.activationStageAt,
    this.adherence,
    this.nutritionTargets,
    this.dietTargets,
    this.lifestyleTargets,
    this.supplementPlan = const [],
    this.coachingPause,
    this.notif,
    this.checkInCadenceDays,
    this.lastCheckInAt,
    this.nextCheckInAt,
    this.scheduleStatus,
    this.authUnlinkedAt,
    this.authUnlinkReason,
    this.authUnlinkedFrom,
    this.isDeleted = false,
    this.progress,
    this.metadata,
    required this.createdAt,
    this.createdAtKnown = true,
    required this.updatedAt,
    this.lastLogin,
    this.raw = const {},
  });

  static String _str(dynamic v) => v == null ? '' : v.toString().trim();

  static double? _dbl(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// [id] is the Firestore document id. Pass it: the document itself never
  /// carries one, and the old code read `map['docId']` and got "" for every
  /// real member, which made two records with different ids the same row.
  factory ClientModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final docId = (id ?? _str(map['docId']));
    final created = memberDate(map['createdAt']);
    return ClientModel(
      docId: docId,
      uid: _str(map['uid']).isEmpty ? docId : _str(map['uid']),
      authUid: _str(map['authUid']),
      name: _str(map['name']).isEmpty
          ? _str(map['clientName'])
          : _str(map['name']),
      email: _str(map['email']),
      phone: _str(map['phone']),
      profilePicUrl: map['profilePicUrl']?.toString(),
      goal: map['goal']?.toString(),
      gender: map['gender']?.toString(),
      age: _int(map['age']),
      height: _dbl(map['height']),
      weight: _dbl(map['weight']),
      trainerId: map['trainerId']?.toString(),
      adminId: map['adminId']?.toString(),
      status: _str(map['status']).isEmpty ? 'active' : _str(map['status']),
      isActive: map['isActive'] is bool ? map['isActive'] as bool : true,
      isVerified: map['isVerified'] == true,
      membershipActive: map['membershipActive'] == true,
      membershipExpiry: memberDate(map['membershipExpiry']),
      membershipFrozen: map['membershipFrozen'] == true,
      membershipFrozenAt: memberDate(map['membershipFrozenAt']),
      membership: _map(map['membership']),
      sharedProfile: _map(map['sharedProfile']),
      sharedProfileAt: memberDate(map['sharedProfileAt']),
      lastActivityAt: memberDate(map['lastActivityAt']),
      activationStage: map['activationStage']?.toString(),
      activationStageAt: memberDate(map['activationStageAt']),
      adherence: _map(map['adherence']),
      nutritionTargets: _map(map['nutritionTargets']),
      dietTargets: _map(map['dietTargets']),
      lifestyleTargets: _map(map['lifestyleTargets']),
      supplementPlan: map['supplementPlan'] is List
          ? List<dynamic>.from(map['supplementPlan'] as List)
          : const [],
      coachingPause: _map(map['coachingPause']),
      notif: _map(map['notif']),
      checkInCadenceDays: _int(map['checkInCadenceDays']),
      lastCheckInAt: memberDate(map['lastCheckInAt']),
      nextCheckInAt: memberDate(map['nextCheckInAt']),
      scheduleStatus: map['scheduleStatus']?.toString(),
      authUnlinkedAt: memberDate(map['authUnlinkedAt']),
      authUnlinkReason: map['authUnlinkReason']?.toString(),
      authUnlinkedFrom: map['authUnlinkedFrom']?.toString(),
      isDeleted: map['isDeleted'] == true,
      progress: _map(map['progress']),
      metadata: _map(map['metadata']),
      createdAt: created ?? DateTime.now(),
      createdAtKnown: created != null,
      updatedAt: memberDate(map['updatedAt']) ?? created ?? DateTime.now(),
      lastLogin: memberDate(map['lastLogin']),
      raw: Map<String, dynamic>.from(map),
    );
  }

  factory ClientModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => ClientModel.fromMap(doc.data() ?? const {}, doc.id);

  /// The console never writes a member record (the rules forbid it for the
  /// founder); this exists for fixtures and round-trips only.
  Map<String, dynamic> toMap() => {
    'docId': docId,
    'uid': uid,
    if (authUid.isNotEmpty) 'authUid': authUid,
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
    'status': status,
    'membershipActive': membershipActive,
    'membershipExpiry': membershipExpiry?.toUtc().toIso8601String(),
    'membershipFrozen': membershipFrozen,
    'membershipFrozenAt': membershipFrozenAt?.toIso8601String(),
    'membership': membership,
    'sharedProfile': sharedProfile,
    'lastActivityAt': lastActivityAt,
    'activationStage': activationStage,
    'adherence': adherence,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'lastLogin': lastLogin?.toIso8601String(),
  };

  ClientModel copyWith({
    String? name,
    String? email,
    String? phone,
    String? authUid,
    String? profilePicUrl,
    String? goal,
    String? gender,
    int? age,
    double? height,
    double? weight,
    String? trainerId,
    String? adminId,
    String? status,
    bool? isActive,
    bool? isVerified,
    bool? membershipActive,
    DateTime? membershipExpiry,
    bool? membershipFrozen,
    Map<String, dynamic>? membership,
    Map<String, dynamic>? sharedProfile,
    DateTime? lastActivityAt,
    String? activationStage,
    Map<String, dynamic>? adherence,
    Map<String, dynamic>? progress,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    bool? createdAtKnown,
    DateTime? updatedAt,
    DateTime? lastLogin,
  }) {
    return ClientModel(
      docId: docId,
      uid: uid,
      authUid: authUid ?? this.authUid,
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
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      isVerified: isVerified ?? this.isVerified,
      membershipActive: membershipActive ?? this.membershipActive,
      membershipExpiry: membershipExpiry ?? this.membershipExpiry,
      membershipFrozen: membershipFrozen ?? this.membershipFrozen,
      membershipFrozenAt: membershipFrozenAt,
      membership: membership ?? this.membership,
      sharedProfile: sharedProfile ?? this.sharedProfile,
      sharedProfileAt: sharedProfileAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      activationStage: activationStage ?? this.activationStage,
      activationStageAt: activationStageAt,
      adherence: adherence ?? this.adherence,
      nutritionTargets: nutritionTargets,
      dietTargets: dietTargets,
      lifestyleTargets: lifestyleTargets,
      supplementPlan: supplementPlan,
      coachingPause: coachingPause,
      notif: notif,
      checkInCadenceDays: checkInCadenceDays,
      lastCheckInAt: lastCheckInAt,
      nextCheckInAt: nextCheckInAt,
      scheduleStatus: scheduleStatus,
      authUnlinkedAt: authUnlinkedAt,
      authUnlinkReason: authUnlinkReason,
      authUnlinkedFrom: authUnlinkedFrom,
      isDeleted: isDeleted,
      progress: progress ?? this.progress,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      createdAtKnown: createdAtKnown ?? this.createdAtKnown,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
      raw: raw,
    );
  }
}
