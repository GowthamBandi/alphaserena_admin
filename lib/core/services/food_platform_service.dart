import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../constants/firestore_collections.dart';
import '../../models/global_food_model.dart';

/// How the foods list is ordered.
enum FoodSort { nameAsc, nameDesc, recentlyUpdated, recentlyCreated, caloriesDesc }

/// Which editorial states the list shows.
enum FoodStatusFilter { published, draft, archived, all }

/// Everything that narrows the foods list, as one value so the controller
/// cannot get its filters and its query out of step.
class FoodQuery {
  final String? prefix;
  final String? categoryId;
  final String? verification;
  final String? source;
  final DateTime? updatedAfter;
  final FoodStatusFilter status;
  final FoodSort sort;

  const FoodQuery({
    this.prefix,
    this.categoryId,
    this.verification,
    this.source,
    this.updatedAfter,
    this.status = FoodStatusFilter.published,
    this.sort = FoodSort.nameAsc,
  });

  /// True when anything beyond the default status view is narrowing the list —
  /// drives the "clear filters" affordance and the empty state's wording.
  bool get hasFilters =>
      (prefix?.isNotEmpty ?? false) ||
      (categoryId?.isNotEmpty ?? false) ||
      verification != null ||
      source != null ||
      updatedAfter != null ||
      status != FoodStatusFilter.published;

  FoodQuery copyWith({
    Object? prefix = _unset,
    Object? categoryId = _unset,
    Object? verification = _unset,
    Object? source = _unset,
    Object? updatedAfter = _unset,
    FoodStatusFilter? status,
    FoodSort? sort,
  }) {
    return FoodQuery(
      prefix: prefix == _unset ? this.prefix : prefix as String?,
      categoryId: categoryId == _unset ? this.categoryId : categoryId as String?,
      verification:
          verification == _unset ? this.verification : verification as String?,
      source: source == _unset ? this.source : source as String?,
      updatedAfter:
          updatedAfter == _unset ? this.updatedAfter : updatedAfter as DateTime?,
      status: status ?? this.status,
      sort: sort ?? this.sort,
    );
  }
}

/// Sentinel so `copyWith` can distinguish "leave it" from "clear it".
const Object _unset = Object();

/// One page of results plus the cursor needed to ask for the next.
class FoodPage {
  final List<GlobalFoodModel> foods;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const FoodPage({
    this.foods = const [],
    this.lastDoc,
    this.hasMore = false,
  });
}

/// FOOD PLATFORM V1 — the console's window onto the global food database.
///
/// READS go straight to Firestore (the founder holds a platform-wide read
/// grant). Every WRITE goes through a Cloud Function, without exception: the
/// security rules deny client writes to `foodDatabase` and `foodCategories` to
/// EVERYONE, including a super admin. That is deliberate — the global library
/// is read by every organization on the platform, so a compromised console
/// session must not be able to poison it, and every mutation must leave an
/// audit-log entry and a revision record that only the server can write.
class FoodPlatformService {
  // Resolved LAZILY rather than in a field initializer.
  //
  // Field initializers run when the class is constructed, so the previous
  // version touched Firebase the moment a controller was built — which made
  // the entire console impossible to mount in a widget test, and is why its
  // loading, empty and error states were believed rather than proven. A
  // subclass that overrides every method now never reaches Firebase at all.
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseFunctions get _fns => FirebaseFunctions.instance;

  /// One page of the global library. Paging is server-side because this tier
  /// is the one that actually grows — organization libraries are small, the
  /// platform library is not.
  static const int pageSize = 50;

  CollectionReference<Map<String, dynamic>> get _foods =>
      _db.collection(FsCollections.foodDatabase);

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection(FsCollections.foodCategories);

  // ── Reads ──────────────────────────────────────────────────────────

  /// One page of the global tier, with cursor-based pagination.
  ///
  /// Always filters `scope == 'global'`, so an organization's private food can
  /// never appear in this console by accident — the query cannot express
  /// "everything", only "the platform tier".
  ///
  /// Pagination is CURSOR-based rather than offset-based: Firestore has no
  /// offset that does not bill for every skipped document, so an offset list
  /// gets linearly more expensive the deeper a curator scrolls. A cursor keeps
  /// page 200 exactly as cheap as page 1.
  Future<FoodPage> fetchGlobalFoods({
    FoodQuery query = const FoodQuery(),
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = pageSize,
  }) async {
    Query<Map<String, dynamic>> q = _foods.where('scope', isEqualTo: 'global');

    // Status. `published` covers the legacy `active` spelling too, so a food
    // written before the editorial workflow existed is not invisible here.
    switch (query.status) {
      case FoodStatusFilter.published:
        q = q.where('status', whereIn: const ['published', 'active']);
      case FoodStatusFilter.draft:
        q = q.where('status', isEqualTo: 'draft');
      case FoodStatusFilter.archived:
        q = q.where('status', isEqualTo: 'archived');
      case FoodStatusFilter.all:
        break;
    }
    if (query.categoryId != null && query.categoryId!.isNotEmpty) {
      q = q.where('categoryId', isEqualTo: query.categoryId);
    }
    if (query.verification != null) {
      q = q.where('verification', isEqualTo: query.verification);
    }
    if (query.source != null) {
      q = q.where('source', isEqualTo: query.source);
    }
    if (query.prefix != null && query.prefix!.isNotEmpty) {
      q = q.where('searchTokens', arrayContains: query.prefix);
    }
    if (query.updatedAfter != null) {
      q = q.where(
        'updatedAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(query.updatedAfter!),
      );
    }

    // A range filter must be the first ordering, so a date filter takes over
    // the sort. Anything else is rejected by Firestore at query time.
    final sort = query.updatedAfter != null ? FoodSort.recentlyUpdated : query.sort;
    switch (sort) {
      case FoodSort.nameAsc:
        q = q.orderBy('nameLower');
      case FoodSort.nameDesc:
        q = q.orderBy('nameLower', descending: true);
      case FoodSort.recentlyUpdated:
        q = q.orderBy('updatedAt', descending: true);
      case FoodSort.recentlyCreated:
        q = q.orderBy('createdAt', descending: true);
      case FoodSort.caloriesDesc:
        q = q.orderBy('calories', descending: true);
    }

    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.limit(limit).get();
    return FoodPage(
      foods: snap.docs.map(GlobalFoodModel.fromSnapshot).toList(),
      lastDoc: snap.docs.isEmpty ? null : snap.docs.last,
      // Fewer rows than asked for can only mean the end of the collection.
      hasMore: snap.docs.length == limit,
    );
  }

  /// Reads one food by id, in any status. The detail page resolution path.
  Future<GlobalFoodModel?> fetchFood(String id) async {
    final snap = await _foods.doc(id).get();
    if (!snap.exists) return null;
    return GlobalFoodModel.fromSnapshot(snap);
  }

  /// Resolves several foods by id — used to render a duplicate group without
  /// re-scanning the library.
  Future<List<GlobalFoodModel>> fetchFoodsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final out = <GlobalFoodModel>[];
    // `whereIn` caps at 30 values per query, so chunk rather than assume.
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await _foods
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      out.addAll(snap.docs.map(GlobalFoodModel.fromSnapshot));
    }
    return out;
  }

  Stream<List<FoodCategoryModel>> watchCategories() {
    return _categories
        .orderBy('sortOrder')
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => FoodCategoryModel.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  // ── Privileged operations (Cloud Functions only) ───────────────────

  /// Creates or edits one global food. Returns the doc id and any validation
  /// warnings the server chose to surface rather than reject.
  Future<({String id, int revision, List<String> warnings})> upsertFood(
    GlobalFoodModel food, {
    bool allowEnergyMismatch = false,
    String? verification,
    String? status,
    String reason = '',
  }) async {
    final res = await _fns.httpsCallable('upsertGlobalFood').call({
      ...food.toCallablePayload(),
      'allowEnergyMismatch': allowEnergyMismatch,
      'reason': reason,
      if (verification != null) 'verification': verification,
      if (status != null) 'status': status,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return (
      id: (m['id'] ?? '').toString(),
      revision: (m['revision'] is num) ? (m['revision'] as num).toInt() : 1,
      warnings: ((m['warnings'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// Archives or restores a global food.
  ///
  /// Not a delete — deletion does not exist anywhere in the platform. Diet
  /// plans embed this food's id and the served plan hydrates zero-macro items
  /// from it, so removing the document would start serving members a zeroed
  /// meal. Archiving hides it from search while leaving every plan intact.
  /// Moves a food through the editorial lifecycle.
  ///
  /// [force] bypasses the server's archive usage guard. It is passed only
  /// after the curator has been shown, in words, exactly which organizations
  /// the food is in use by.
  Future<void> setStatus(
    String id, {
    required String status,
    bool force = false,
    String reason = '',
  }) async {
    await _fns.httpsCallable('setGlobalFoodStatus').call({
      'id': id,
      'status': status,
      'force': force,
      'reason': reason,
    });
  }

  Future<void> setVerification(String id, String verification) async {
    await _fns.httpsCallable('setGlobalFoodVerification').call({
      'id': id,
      'verification': verification,
    });
  }

  Future<List<FoodHistoryEntry>> history(String id) async {
    final res = await _fns.httpsCallable('getGlobalFoodHistory').call({
      'id': id,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return ((m['entries'] as List?) ?? const []).map((e) {
      final v = Map<String, dynamic>.from(e as Map);
      final at = v['at'];
      return FoodHistoryEntry(
        id: (v['id'] ?? '').toString(),
        action: (v['action'] ?? '').toString(),
        actorUid: (v['actorUid'] ?? '').toString(),
        revision: (v['revision'] is num) ? (v['revision'] as num).toInt() : 0,
        from: (v['from'] ?? '').toString(),
        to: (v['to'] ?? '').toString(),
        reason: (v['reason'] ?? '').toString(),
        changes: ((v['changes'] as List?) ?? const []).map((c) {
          final f = Map<String, dynamic>.from(c as Map);
          return (
            field: (f['field'] ?? '').toString(),
            from: (f['from'] ?? '').toString(),
            to: (f['to'] ?? '').toString(),
          );
        }).toList(),
        at: at is num
            ? DateTime.fromMillisecondsSinceEpoch(at.toInt())
            : null,
      );
    }).toList();
  }

  /// Validates (and optionally imports) a batch of foods.
  ///
  /// ALWAYS run with `dryRun: true` first. The report is identical either way,
  /// nothing is written, and the curator sees exactly which rows would be
  /// rejected and why before a single document is created.
  Future<FoodImportReport> bulkImport(
    List<Map<String, dynamic>> foods, {
    required bool dryRun,
    String? categoryId,
    String source = 'import',
    bool allowEnergyMismatch = false,
    String conflictMode = 'skip',
    String status = 'draft',
  }) async {
    final res = await _fns.httpsCallable('bulkImportGlobalFoods').call({
      'foods': foods,
      'dryRun': dryRun,
      'source': source,
      'allowEnergyMismatch': allowEnergyMismatch,
      'conflictMode': conflictMode,
      'status': status,
      if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    int n(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;

    return FoodImportReport(
      dryRun: m['dryRun'] == true,
      conflictMode: (m['conflictMode'] ?? 'skip').toString(),
      status: (m['status'] ?? 'draft').toString(),
      received: n('received'),
      accepted: n('accepted'),
      willUpdate: n('willUpdate'),
      imported: n('imported'),
      updated: n('updated'),
      rejected: ((m['rejected'] as List?) ?? const []).map((e) {
        final v = Map<String, dynamic>.from(e as Map);
        return (
          name: (v['name'] ?? '').toString(),
          errors: ((v['errors'] as List?) ?? const [])
              .map((x) => x.toString())
              .toList(),
        );
      }).toList(),
      duplicates: ((m['duplicates'] as List?) ?? const []).map((e) {
        final v = Map<String, dynamic>.from(e as Map);
        return (
          name: (v['name'] ?? '').toString(),
          reason: (v['reason'] ?? '').toString(),
        );
      }).toList(),
      warnings: ((m['warnings'] as List?) ?? const []).map((e) {
        final v = Map<String, dynamic>.from(e as Map);
        return (
          name: (v['name'] ?? '').toString(),
          warnings: ((v['warnings'] as List?) ?? const [])
              .map((x) => x.toString())
              .toList(),
        );
      }).toList(),
    );
  }

  /// Exports the global library in the exact shape [bulkImport] accepts, so an
  /// export can be re-imported into another environment untransformed.
  Future<({List<Map<String, dynamic>> foods, bool truncated})> export({
    bool includeArchived = false,
  }) async {
    final res = await _fns.httpsCallable('exportGlobalFoods').call({
      'includeArchived': includeArchived,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return (
      foods: ((m['foods'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      truncated: m['truncated'] == true,
    );
  }

  /// Name+brand collisions inside the global tier, largest cluster first.
  Future<({int scanned, bool truncated, List<DuplicateGroup> groups, Map<String, String> names})>
  findDuplicates() async {
    final res = await _fns.httpsCallable('findGlobalFoodDuplicates').call({
      'scope': 'global',
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    final names = Map<String, dynamic>.from((m['names'] as Map?) ?? const {});
    return (
      scanned: (m['scanned'] is num) ? (m['scanned'] as num).toInt() : 0,
      truncated: m['truncated'] == true,
      groups: ((m['groups'] as List?) ?? const [])
          .map((e) => DuplicateGroup.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      names: names.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Future<String> upsertCategory({
    String? id,
    required String name,
    String icon = '',
    String parentId = '',
    int sortOrder = 100,
  }) async {
    final res = await _fns.httpsCallable('upsertFoodCategory').call({
      if (id != null && id.isNotEmpty) 'id': id,
      'name': name,
      'icon': icon,
      'parentId': parentId,
      'sortOrder': sortOrder,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return (m['id'] ?? '').toString();
  }

  Future<void> setCategoryStatus(String id, {required bool archived}) async {
    await _fns.httpsCallable('setFoodCategoryStatus').call({
      'id': id,
      'status': archived ? 'archived' : 'active',
    });
  }

  // ── Usage intelligence ─────────────────────────────────────────────

  /// LIVE usage for one food. Never cached: this is the number that gates a
  /// destructive action, and a stale one would make the guard worthless.
  Future<FoodUsage> usage(String id) async {
    final res = await _fns.httpsCallable('getFoodUsage').call({'id': id});
    return FoodUsage.fromMap(Map<String, dynamic>.from(res.data as Map));
  }

  /// Recomputes and STORES usage for up to 25 foods, so the list can show a
  /// number per row without two queries per row per render.
  Future<Map<String, FoodUsage>> refreshUsage(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final res = await _fns.httpsCallable('recomputeFoodUsage').call({
      'ids': ids.take(25).toList(),
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    final raw = Map<String, dynamic>.from((m['usage'] as Map?) ?? const {});
    return raw.map(
      (k, v) => MapEntry(k, FoodUsage.fromMap(Map<String, dynamic>.from(v as Map))),
    );
  }

  /// Populates the `foodIds` usage mirror on existing plans and assignments.
  Future<({int scanned, int patched, bool done, String cursor})> backfillUsageIndex({
    required String collection,
    required bool dryRun,
    String cursor = '',
  }) async {
    final res = await _fns.httpsCallable('backfillFoodUsageIndex').call({
      'collection': collection,
      'dryRun': dryRun,
      if (cursor.isNotEmpty) 'cursor': cursor,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    int n(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;
    return (
      scanned: n('scanned'),
      patched: n('patched'),
      done: m['done'] == true,
      cursor: (m['cursor'] ?? '').toString(),
    );
  }

  // ── Bulk operations ────────────────────────────────────────────────

  /// Applies one status or verification change to many foods.
  ///
  /// [force] skips the archive usage guard. It is passed only after the
  /// operator has seen exactly which foods are in use and confirmed anyway.
  Future<({List<String> changed, List<({String id, String name, String reason})> blocked, List<String> skipped})>
  bulkSetState(
    List<String> ids, {
    String? status,
    String? verification,
    bool force = false,
    String reason = '',
  }) async {
    final res = await _fns.httpsCallable('bulkSetGlobalFoodState').call({
      'ids': ids,
      if (status != null) 'status': status,
      if (verification != null) 'verification': verification,
      'force': force,
      'reason': reason,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return (
      changed: ((m['changed'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      blocked: ((m['blocked'] as List?) ?? const []).map((e) {
        final v = Map<String, dynamic>.from(e as Map);
        return (
          id: (v['id'] ?? '').toString(),
          name: (v['name'] ?? '').toString(),
          reason: (v['reason'] ?? '').toString(),
        );
      }).toList(),
      skipped: ((m['skipped'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// Folds duplicates into one survivor: the losers are ARCHIVED (never
  /// deleted) and their names become aliases of the food that replaced them.
  Future<({List<String> archived, List<String> aliases, int usageArchived})> merge({
    required String keepId,
    required List<String> mergeIds,
    String reason = '',
  }) async {
    final res = await _fns.httpsCallable('mergeGlobalFoods').call({
      'keepId': keepId,
      'mergeIds': mergeIds,
      'reason': reason,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return (
      archived: ((m['archived'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      aliases: ((m['aliases'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      usageArchived: (m['usageArchived'] is num)
          ? (m['usageArchived'] as num).toInt()
          : 0,
    );
  }

  // ── Analytics ──────────────────────────────────────────────────────

  Future<FoodAnalytics> analytics() async {
    final res = await _fns.httpsCallable('getFoodLibraryAnalytics').call();
    final m = Map<String, dynamic>.from(res.data as Map);
    final counts = Map<String, dynamic>.from((m['counts'] as Map?) ?? const {});
    int n(Map<String, dynamic> src, String k) =>
        (src[k] is num) ? (src[k] as num).toInt() : 0;
    List<Map<String, dynamic>> rows(String k) =>
        ((m[k] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    return FoodAnalytics(
      total: n(counts, 'total'),
      published: n(counts, 'published'),
      draft: n(counts, 'draft'),
      archived: n(counts, 'archived'),
      verified: n(counts, 'verified'),
      official: n(counts, 'official'),
      unverified: n(counts, 'unverified'),
      sampled: n(m, 'sampled'),
      sampleTruncated: m['sampleTruncated'] == true,
      topCategories: rows('topCategories')
          .map((e) => (
                categoryId: (e['categoryId'] ?? '').toString(),
                count: (e['count'] is num) ? (e['count'] as num).toInt() : 0,
              ))
          .toList(),
      missingData: rows('missingData')
          .map((e) => (
                id: (e['id'] ?? '').toString(),
                name: (e['name'] ?? '').toString(),
                gaps: ((e['gaps'] as List?) ?? const [])
                    .map((g) => g.toString())
                    .toList(),
              ))
          .toList(),
      missingDataTotal: n(m, 'missingDataTotal'),
      missingDataTruncated: m['missingDataTruncated'] == true,
      awaitingReview: rows('awaitingReview')
          .map((e) => (
                id: (e['id'] ?? '').toString(),
                name: (e['name'] ?? '').toString(),
              ))
          .toList(),
      awaitingReviewTotal: n(m, 'awaitingReviewTotal'),
      unverifiedTotal: n(m, 'unverifiedTotal'),
      mostUsed: rows('mostUsed')
          .map((e) => (
                id: (e['id'] ?? '').toString(),
                name: (e['name'] ?? '').toString(),
                plans: (e['plans'] is num) ? (e['plans'] as num).toInt() : 0,
              ))
          .toList(),
      neverUsed: rows('neverUsed')
          .map((e) => (
                id: (e['id'] ?? '').toString(),
                name: (e['name'] ?? '').toString(),
              ))
          .toList(),
      neverUsedTotal: n(m, 'neverUsedTotal'),
      neverUsedTruncated: m['neverUsedTruncated'] == true,
      recent: rows('recentlyAdded')
          .map((e) => (
                id: (e['id'] ?? '').toString(),
                name: (e['name'] ?? '').toString(),
                status: (e['status'] ?? 'published').toString(),
                at: e['createdAt'] is num
                    ? DateTime.fromMillisecondsSinceEpoch(
                        (e['createdAt'] as num).toInt())
                    : null,
              ))
          .toList(),
    );
  }

  /// Live global-food counts per category, so an empty category is visible.
  Future<({Map<String, int> counts, int uncategorised})> categoryCounts() async {
    final res = await _fns.httpsCallable('getFoodCategoryCounts').call();
    final m = Map<String, dynamic>.from(res.data as Map);
    final raw = Map<String, dynamic>.from((m['counts'] as Map?) ?? const {});
    return (
      counts: raw.map(
        (k, v) => MapEntry(k, (v is num) ? v.toInt() : 0),
      ),
      uncategorised: (m['uncategorised'] is num)
          ? (m['uncategorised'] as num).toInt()
          : 0,
    );
  }

  /// Runs one batch of the V1 migration over pre-V1 organization foods.
  ///
  /// Purely additive and idempotent. The platform is already CORRECT without
  /// it — organization queries use only `adminId` and `name`, which every
  /// legacy document has — so this upgrades legacy foods to server-side token
  /// search rather than repairing anything.
  Future<({int scanned, int patched, bool done, String cursor})> backfill({
    required bool dryRun,
    String cursor = '',
  }) async {
    final res = await _fns.httpsCallable('backfillFoodPlatform').call({
      'dryRun': dryRun,
      if (cursor.isNotEmpty) 'cursor': cursor,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    int n(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;
    return (
      scanned: n('scanned'),
      patched: n('patched'),
      done: m['done'] == true,
      cursor: (m['cursor'] ?? '').toString(),
    );
  }
}
