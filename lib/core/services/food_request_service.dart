import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../constants/firestore_collections.dart';
import '../utils/food_errors.dart';
import '../../models/food_request_model.dart';
import '../../models/food_search_stats_model.dart';

/// One page of food requests plus the cursor needed to ask for the next.
/// Mirrors `FoodPage` in `food_platform_service.dart`.
class FoodRequestPage {
  final List<FoodRequestModel> requests;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const FoodRequestPage({
    this.requests = const [],
    this.lastDoc,
    this.hasMore = false,
  });
}

/// NUTRITION INTELLIGENCE PLATFORM (NIP) — Phase A service contract.
///
/// The console's window onto community food requests and search telemetry.
/// Same contract shape as [FoodPlatformService], and for the same reasons:
///
/// READS go straight to Firestore (the founder holds a platform-wide read
/// grant; the rules expose `food_requests` and `food_search_stats` to the
/// super admin read-only). Every WRITE goes through a Cloud Function — a
/// request's status machine, dedupe counters and audit trail are server-owned,
/// so a compromised console session cannot forge an approval or vanish a
/// request.
class FoodRequestService {
  // Resolved LAZILY rather than in a field initializer, exactly like
  // FoodPlatformService: field initializers run at construction, which would
  // make any controller holding this service impossible to mount in a widget
  // test. A subclass that overrides every method never touches Firebase.
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseFunctions get _fns => FirebaseFunctions.instance;

  static const int pageSize = 50;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection(FsCollections.foodRequests);

  CollectionReference<Map<String, dynamic>> get _searchStats =>
      _db.collection(FsCollections.foodSearchStats);

  // ── Reads ──────────────────────────────────────────────────────────

  /// One page of requests in [status], most-demanded first.
  ///
  /// Ordered `demandCount desc, createdAt asc`: demand is the triage signal,
  /// and within a demand band the request that has waited longest comes first.
  /// The secondary ordering also makes the cursor deterministic — a
  /// single-field order over a non-unique value would hand back pages whose
  /// boundaries drift between reads. Cursor-based (never offset) for the same
  /// cost reason as the foods list: page 200 stays as cheap as page 1.
  ///
  /// [status] is the ENUM, translated to its wire spelling here, so a caller
  /// can never query a misspelled status. [FoodRequestStatus.unknown] has no
  /// wire form and is rejected loudly rather than silently matching nothing.
  Future<FoodRequestPage> fetchRequests({
    FoodRequestStatus status = FoodRequestStatus.pending,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = pageSize,
  }) async {
    final wire = FoodRequestModel.statusWireName(status);
    if (wire == null) {
      throw ArgumentError.value(
        status,
        'status',
        'has no wire representation and cannot be queried',
      );
    }

    Query<Map<String, dynamic>> q = _requests
        .where('status', isEqualTo: wire)
        .orderBy('demandCount', descending: true)
        .orderBy('createdAt');

    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.limit(limit).get();
    return FoodRequestPage(
      requests: snap.docs.map(FoodRequestModel.fromSnapshot).toList(),
      lastDoc: snap.docs.isEmpty ? null : snap.docs.last,
      // Fewer rows than asked for can only mean the end of the collection.
      hasMore: snap.docs.length == limit,
    );
  }

  /// Reads one request by id, in any status. The detail-view resolution path.
  Future<FoodRequestModel?> fetchRequest(String id) async {
    final snap = await _requests.doc(id).get();
    if (!snap.exists) return null;
    return FoodRequestModel.fromSnapshot(snap);
  }

  /// The most recent [days] daily search-stats documents, newest first.
  ///
  /// `food_search_stats` doc ids are `yyyy-MM-dd`, which sorts
  /// lexicographically in calendar order — so a documentId range query IS a
  /// date range query, with no extra field or index needed.
  Future<List<FoodSearchStatsModel>> fetchRecentSearchStats({
    int days = 30,
  }) async {
    final snap = await _searchStats
        .orderBy(FieldPath.documentId, descending: true)
        .limit(days)
        .get();
    return snap.docs
        .map((d) => FoodSearchStatsModel.fromMap(d.data(), d.id))
        .toList();
  }

  /// One day's stats, or null if nothing was aggregated for that date.
  /// [date] must be the `yyyy-MM-dd` document key.
  Future<FoodSearchStatsModel?> fetchSearchStats(String date) async {
    final snap = await _searchStats.doc(date).get();
    final data = snap.data();
    if (data == null) return null;
    return FoodSearchStatsModel.fromMap(data, snap.id);
  }

  // ── Privileged operations (Cloud Functions only) ───────────────────

  /// Resolves one request via the `resolveFoodRequest` callable (Phase B
  /// backend). The server owns the status transition, writes the resolution
  /// block, creates/promotes the food when approving, and audit-logs the act.
  ///
  /// [action] is 'approve' | 'reject' | 'merge_duplicate'.
  /// [approvedFood] — the curator-edited food payload, for approvals where
  /// the proposal was amended before acceptance.
  /// [mergeIntoFoodId] — the surviving food, required for a duplicate merge.
  /// [reason] — required by the server on rejection.
  ///
  /// On failure this throws a [FoodConsoleError] — the SAME taxonomy the rest
  /// of the food console uses (`food_errors.dart`), classified via
  /// [describeFoodError] with the callable named. An undeployed Phase B
  /// backend therefore reports "resolveFoodRequest is not deployed" with the
  /// deploy command, not a blank failure.
  Future<({String requestId, String status, String resultFoodId})>
  resolveRequest({
    required String requestId,
    required String action,
    Map<String, dynamic>? approvedFood,
    String? mergeIntoFoodId,
    String reason = '',
  }) async {
    try {
      final res = await _fns.httpsCallable('resolveFoodRequest').call({
        'requestId': requestId,
        'action': action,
        if (approvedFood != null) 'approvedFood': approvedFood,
        if (mergeIntoFoodId != null && mergeIntoFoodId.isNotEmpty)
          'mergeIntoFoodId': mergeIntoFoodId,
        'reason': reason,
      });
      final m = Map<String, dynamic>.from(res.data as Map);
      return (
        requestId: (m['requestId'] ?? requestId).toString(),
        status: (m['status'] ?? '').toString(),
        resultFoodId: (m['resultFoodId'] ?? '').toString(),
      );
    } catch (e) {
      throw describeFoodError(e, operation: 'resolveFoodRequest');
    }
  }
}
