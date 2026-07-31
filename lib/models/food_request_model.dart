import 'package:cloud_firestore/cloud_firestore.dart';

/// NUTRITION INTELLIGENCE PLATFORM (NIP) — Phase A.
///
/// The console's view of one community food request: a member or trainer asked
/// for a food the library does not have (or wants an org food promoted, or a
/// correction made), and a curator has to decide what happens to it.
///
/// The console never writes these documents directly. Resolution goes through
/// the `resolveFoodRequest` Cloud Function (Phase B), which owns the status
/// machine and the audit trail; the security rules deny client writes.

/// What the requester is asking for.
enum FoodRequestType {
  /// A brand-new food that does not exist anywhere.
  newFood,

  /// Promote an existing org-scoped food into the global tier.
  promote,

  /// Fix data on an existing food (payload carries `{foodId}` plus the fix).
  correction,

  /// A type this console version does not know. Kept, shown raw, never acted
  /// on — an old console must not misread a new request kind as something it
  /// understands.
  unknown,
}

/// Where the request is in its lifecycle.
enum FoodRequestStatus {
  pending,
  inReview,
  approved,
  rejected,

  /// Closed because the food already existed — folded into it, not created.
  mergedDuplicate,

  /// A status this console version does not know. Treated as CLOSED, because
  /// offering resolution actions on a state we cannot name is how a console
  /// corrupts a workflow it does not understand.
  unknown,
}

/// One "this might already exist" lead attached to a request by the backend's
/// duplicate detector. A lead, never a verdict — nothing merges automatically.
class DuplicateSuggestion {
  final String foodId;
  final String name;

  /// 0..1 similarity score from the backend matcher.
  final double score;

  const DuplicateSuggestion({
    required this.foodId,
    this.name = '',
    this.score = 0,
  });

  /// Strong enough to lead with in the review UI without opening both foods.
  bool get isStrong => score >= 0.9;

  factory DuplicateSuggestion.fromMap(Map<String, dynamic> m) =>
      DuplicateSuggestion(
        foodId: (m['foodId'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        score: (m['score'] is num) ? (m['score'] as num).toDouble() : 0,
      );

  Map<String, dynamic> toMap() => {
    'foodId': foodId,
    'name': name,
    'score': score,
  };
}

/// How a request was closed, and by whom. Null while the request is open.
class FoodRequestResolution {
  final String by;
  final DateTime? at;

  /// The resolver's action verb ('approved' | 'rejected' | 'merged_duplicate').
  final String action;

  /// Why — REQUIRED by the backend on rejection, so a requester is never
  /// refused silently.
  final String reason;

  /// The food the request became (approved) or was folded into (merged).
  /// Empty on rejection.
  final String resultFoodId;

  const FoodRequestResolution({
    this.by = '',
    this.at,
    this.action = '',
    this.reason = '',
    this.resultFoodId = '',
  });

  factory FoodRequestResolution.fromMap(Map<String, dynamic> m) {
    final at = m['at'];
    return FoodRequestResolution(
      by: (m['by'] ?? '').toString(),
      at: at is Timestamp
          ? at.toDate()
          : (at is String ? DateTime.tryParse(at) : null),
      action: (m['action'] ?? '').toString(),
      reason: (m['reason'] ?? '').toString(),
      resultFoodId: (m['resultFoodId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {
    'by': by,
    if (at != null) 'at': Timestamp.fromDate(at!),
    'action': action,
    'reason': reason,
    'resultFoodId': resultFoodId,
  };
}

/// One document from `food_requests`.
class FoodRequestModel {
  final String id;
  final int schemaVersion;
  final FoodRequestType type;

  /// The exact string the document carried — preserved so an [unknown] type or
  /// status can still be DISPLAYED truthfully instead of as a blank.
  final String rawType;

  final String requesterUid;

  /// 'member' | 'trainer' | 'admin'. Kept as a string: the role vocabulary is
  /// owned by the identity system, and this console only displays it.
  final String requesterRole;

  /// The requester's organization. Empty when the request came from outside an
  /// org context.
  final String adminId;

  final FoodRequestStatus status;
  final String rawStatus;

  /// The proposed food map (new/correction) OR `{foodId: ...}` (promote).
  /// Deliberately untyped: the server re-validates everything at resolution
  /// time, and Phase B's approval dialog edits this map before submitting it.
  final Map<String, dynamic> payload;

  /// Backend-computed dedupe key (normalized name+brand). Requests sharing a
  /// key are the same ask, and the backend bumps [demandCount] instead of
  /// creating a twin.
  final String normalizedKey;

  final List<DuplicateSuggestion> duplicateSuggestions;

  /// How many distinct askers want this food. THE triage number: the review
  /// queue is ordered by it, because demand is what turns a request into a
  /// library gap.
  final int demandCount;

  final FoodRequestResolution? resolution;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FoodRequestModel({
    required this.id,
    this.schemaVersion = 1,
    this.type = FoodRequestType.unknown,
    this.rawType = '',
    this.requesterUid = '',
    this.requesterRole = '',
    this.adminId = '',
    this.status = FoodRequestStatus.unknown,
    this.rawStatus = '',
    this.payload = const {},
    this.normalizedKey = '',
    this.duplicateSuggestions = const [],
    this.demandCount = 0,
    this.resolution,
    this.createdAt,
    this.updatedAt,
  });

  /// Still awaiting a curator's decision.
  bool get isOpen =>
      status == FoodRequestStatus.pending ||
      status == FoodRequestStatus.inReview;

  bool get isResolved => !isOpen && status != FoodRequestStatus.unknown;

  /// The existing food a promote/correction request points at. Empty for a
  /// new-food request.
  String get targetFoodId => (payload['foodId'] ?? '').toString();

  /// The proposed food's display name, best-effort from the payload.
  String get proposedName => (payload['name'] ?? '').toString();

  bool get hasDuplicateSuggestions => duplicateSuggestions.isNotEmpty;

  /// Review-queue order: most-demanded first, then oldest first (a tie in
  /// demand is broken by who has waited longest). Requests with no
  /// `createdAt` sort last within their demand band.
  static int compareByDemand(FoodRequestModel a, FoodRequestModel b) {
    final byDemand = b.demandCount.compareTo(a.demandCount);
    if (byDemand != 0) return byDemand;
    final aAt = a.createdAt;
    final bAt = b.createdAt;
    if (aAt == null && bAt == null) return 0;
    if (aAt == null) return 1;
    if (bAt == null) return -1;
    return aAt.compareTo(bAt);
  }

  static FoodRequestType parseType(String raw) => switch (raw) {
    'new' => FoodRequestType.newFood,
    'promote' => FoodRequestType.promote,
    'correction' => FoodRequestType.correction,
    _ => FoodRequestType.unknown,
  };

  static FoodRequestStatus parseStatus(String raw) => switch (raw) {
    'pending' => FoodRequestStatus.pending,
    'in_review' => FoodRequestStatus.inReview,
    'approved' => FoodRequestStatus.approved,
    'rejected' => FoodRequestStatus.rejected,
    'merged_duplicate' => FoodRequestStatus.mergedDuplicate,
    _ => FoodRequestStatus.unknown,
  };

  /// The wire spelling of a status — the exact strings the backend contract
  /// stores and the queries filter on. Null for [FoodRequestStatus.unknown],
  /// which has no wire form and must never be written or queried.
  static String? statusWireName(FoodRequestStatus s) => switch (s) {
    FoodRequestStatus.pending => 'pending',
    FoodRequestStatus.inReview => 'in_review',
    FoodRequestStatus.approved => 'approved',
    FoodRequestStatus.rejected => 'rejected',
    FoodRequestStatus.mergedDuplicate => 'merged_duplicate',
    FoodRequestStatus.unknown => null,
  };

  static String? typeWireName(FoodRequestType t) => switch (t) {
    FoodRequestType.newFood => 'new',
    FoodRequestType.promote => 'promote',
    FoodRequestType.correction => 'correction',
    FoodRequestType.unknown => null,
  };

  factory FoodRequestModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return FoodRequestModel.fromMap(doc.data() ?? const {}, doc.id);
  }

  factory FoodRequestModel.fromMap(Map<String, dynamic> data, String id) {
    DateTime? at(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final rawType = (data['type'] ?? '').toString();
    final rawStatus = (data['status'] ?? '').toString();

    final suggestions = <DuplicateSuggestion>[];
    final rawSuggestions = data['duplicateSuggestions'];
    if (rawSuggestions is List) {
      for (final e in rawSuggestions) {
        if (e is Map) {
          final s = DuplicateSuggestion.fromMap(
            Map<String, dynamic>.from(e),
          );
          if (s.foodId.isNotEmpty) suggestions.add(s);
        }
      }
    }

    return FoodRequestModel(
      id: id,
      schemaVersion: (data['schemaVersion'] is num)
          ? (data['schemaVersion'] as num).toInt()
          : 1,
      type: parseType(rawType),
      rawType: rawType,
      requesterUid: (data['requesterUid'] ?? '').toString(),
      requesterRole: (data['requesterRole'] ?? '').toString(),
      adminId: (data['adminId'] ?? '').toString(),
      status: parseStatus(rawStatus),
      rawStatus: rawStatus,
      payload: data['payload'] is Map
          ? Map<String, dynamic>.from(data['payload'] as Map)
          : const {},
      normalizedKey: (data['normalizedKey'] ?? '').toString(),
      duplicateSuggestions: suggestions,
      demandCount: (data['demandCount'] is num)
          ? (data['demandCount'] as num).toInt()
          : 0,
      resolution: data['resolution'] is Map
          ? FoodRequestResolution.fromMap(
              Map<String, dynamic>.from(data['resolution'] as Map),
            )
          : null,
      createdAt: at(data['createdAt']),
      updatedAt: at(data['updatedAt']),
    );
  }

  /// The stored-document shape, for tests and round-trips. The console never
  /// writes this document in production — resolution goes through the
  /// `resolveFoodRequest` callable.
  Map<String, dynamic> toMap() => {
    'schemaVersion': schemaVersion,
    'type': typeWireName(type) ?? rawType,
    'requesterUid': requesterUid,
    'requesterRole': requesterRole,
    'adminId': adminId,
    'status': statusWireName(status) ?? rawStatus,
    'payload': payload,
    'normalizedKey': normalizedKey,
    'duplicateSuggestions': [
      for (final s in duplicateSuggestions) s.toMap(),
    ],
    'demandCount': demandCount,
    'resolution': resolution?.toMap(),
    if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
  };
}
