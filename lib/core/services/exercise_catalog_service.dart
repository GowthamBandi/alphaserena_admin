import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../constants/firestore_collections.dart';
import '../../models/global_exercise_model.dart';

/// How the catalog list is ordered.
enum ExerciseSort { nameAsc, nameDesc, recentlyUpdated, recentlyCreated }

/// Which activation states the list shows.
enum ExerciseActiveFilter { active, inactive, all }

/// Everything that narrows the catalog list, as one value so the controller
/// cannot get its filters and its query out of step.
class ExerciseQuery {
  /// The search token, already reduced to what the index actually stores.
  final String? prefix;

  final String? category;
  final ExerciseActiveFilter active;
  final ExerciseSort sort;

  const ExerciseQuery({
    this.prefix,
    this.category,
    this.active = ExerciseActiveFilter.all,
    this.sort = ExerciseSort.nameAsc,
  });

  /// True when anything is narrowing the list — drives the "clear filters"
  /// affordance and the empty state's wording. An empty catalog and an
  /// over-narrow filter must never look the same.
  bool get hasFilters =>
      (prefix?.isNotEmpty ?? false) ||
      (category?.isNotEmpty ?? false) ||
      active != ExerciseActiveFilter.all;

  ExerciseQuery copyWith({
    Object? prefix = _unset,
    Object? category = _unset,
    ExerciseActiveFilter? active,
    ExerciseSort? sort,
  }) => ExerciseQuery(
    prefix: prefix == _unset ? this.prefix : prefix as String?,
    category: category == _unset ? this.category : category as String?,
    active: active ?? this.active,
    sort: sort ?? this.sort,
  );
}

/// Sentinel so `copyWith` can distinguish "leave it" from "clear it".
const Object _unset = Object();

/// One page of results plus the cursor needed to ask for the next.
class ExercisePage {
  final List<GlobalExerciseModel> exercises;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const ExercisePage({
    this.exercises = const [],
    this.lastDoc,
    this.hasMore = false,
  });
}

/// GLOBAL EXERCISE LIBRARY — the console's window onto the master catalog.
///
/// READS go straight to Firestore (the founder holds a platform-wide read
/// grant). Every WRITE goes through a Cloud Function, without exception: the
/// security rules deny client writes to `exerciseCatalog` to EVERYONE,
/// including a super admin. That is deliberate — every organization on the
/// platform READS THROUGH this catalog (TrainerHQ's picker merges it with the
/// gym's own library and a workout item points at whichever row was chosen), so
/// a compromised console session must not be able to poison it, and every
/// mutation must leave an `audit_logs` entry only the server can write.
///
/// A deliberate structural twin of `FoodPlatformService`.
class ExerciseCatalogService {
  // Resolved LAZILY rather than in a field initializer.
  //
  // Field initializers run when the class is constructed, so touching Firebase
  // there would make the entire console impossible to mount in a widget test —
  // and its loading, empty and error states believed rather than proven. A
  // subclass that overrides every method never reaches Firebase at all.
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseFunctions get _fns => FirebaseFunctions.instance;

  /// Rows per page. The catalog ships at ~900 and is expected to grow, so
  /// paging is server-side from day one.
  static const int pageSize = 50;

  CollectionReference<Map<String, dynamic>> get _catalog =>
      _db.collection(FsCollections.exerciseCatalog);

  // ── Reads ──────────────────────────────────────────────────────────

  /// One page of the catalog, with CURSOR-based pagination.
  ///
  /// Cursor rather than offset: Firestore has no offset that does not bill for
  /// every skipped document, so an offset list gets linearly more expensive the
  /// deeper a curator scrolls. A cursor keeps page 20 exactly as cheap as
  /// page 1.
  ///
  /// Every filter is a server-side `where`. Nothing here downloads the catalog
  /// to sort or filter it in memory — the single difference between a console
  /// that works at demo scale and one that works in production.
  Future<ExercisePage> fetchExercises({
    ExerciseQuery query = const ExerciseQuery(),
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = pageSize,
  }) async {
    Query<Map<String, dynamic>> q = _catalog;

    switch (query.active) {
      case ExerciseActiveFilter.active:
        q = q.where('isActive', isEqualTo: true);
      case ExerciseActiveFilter.inactive:
        q = q.where('isActive', isEqualTo: false);
      case ExerciseActiveFilter.all:
        break;
    }
    if (query.category != null && query.category!.isNotEmpty) {
      q = q.where('category', isEqualTo: query.category);
    }
    if (query.prefix != null && query.prefix!.isNotEmpty) {
      q = q.where('searchTokens', arrayContains: query.prefix);
    }

    switch (query.sort) {
      case ExerciseSort.nameAsc:
        q = q.orderBy('nameLower');
      case ExerciseSort.nameDesc:
        q = q.orderBy('nameLower', descending: true);
      case ExerciseSort.recentlyUpdated:
        q = q.orderBy('updatedAt', descending: true);
      case ExerciseSort.recentlyCreated:
        q = q.orderBy('createdAt', descending: true);
    }

    if (startAfter != null) q = q.startAfterDocument(startAfter);
    final snap = await q.limit(limit).get();
    return ExercisePage(
      exercises: snap.docs.map(GlobalExerciseModel.fromSnapshot).toList(),
      lastDoc: snap.docs.isEmpty ? null : snap.docs.last,
      // Fewer rows than asked for can only mean the end of the collection.
      hasMore: snap.docs.length == limit,
    );
  }

  /// Reads one exercise by id, in any state.
  Future<GlobalExerciseModel?> fetchExercise(String id) async {
    final snap = await _catalog.doc(id).get();
    if (!snap.exists) return null;
    return GlobalExerciseModel.fromSnapshot(snap);
  }

  /// Resolves several exercises by id — used to render a duplicate group
  /// without re-scanning the catalog.
  Future<List<GlobalExerciseModel>> fetchExercisesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final out = <GlobalExerciseModel>[];
    // `whereIn` caps at 30 values per query, so chunk rather than assume.
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await _catalog
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      out.addAll(snap.docs.map(GlobalExerciseModel.fromSnapshot));
    }
    return out;
  }

  // ── Privileged operations (Cloud Functions only) ───────────────────

  /// Creates or edits one catalog exercise. Returns the doc id and any
  /// validation warnings the server chose to surface rather than reject.
  Future<({String id, int revision, List<String> warnings})> upsert(
    GlobalExerciseModel exercise, {
    bool? isActive,
  }) async {
    final res = await _fns.httpsCallable('upsertGlobalExercise').call({
      ...exercise.toCallablePayload(),
      if (isActive != null) 'isActive': isActive,
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

  /// Activates or deactivates one exercise — the NON-destructive control.
  Future<void> setActive(String id, {required bool isActive}) async {
    await _fns.httpsCallable('setGlobalExerciseActive').call({
      'id': id,
      'isActive': isActive,
    });
  }

  /// ARCHIVES one exercise. Nothing is ever removed from Firestore.
  ///
  /// ⚠️ THE NAME IS HISTORICAL AND THE BEHAVIOUR IS NOT. `deleteGlobalExercise`
  /// really did hard-delete while organizations IMPORTED from the catalog by
  /// copying a row into their own library, leaving nothing anywhere that
  /// referenced a catalog id. TrainerHQ now POINTS AT catalog rows — the
  /// exercise picker merges both tiers and a workout item stores whichever id
  /// was chosen — so a delete would tear a live exercise out of assigned
  /// workouts and out of members' training, silently: the member app degrades a
  /// missing exercise to its name and prescription rather than erroring.
  ///
  /// The callable therefore sets `isArchived: true, isActive: false`. The row
  /// leaves every picker and keeps resolving forever. The callable's NAME is
  /// kept so a deployed console build cannot 404 on a lifecycle action.
  Future<void> delete(String id) async {
    await _fns.httpsCallable('deleteGlobalExercise').call({'id': id});
  }

  /// Applies one activation change to many exercises.
  Future<({List<String> changed, List<String> missing})> bulkSetActive(
    List<String> ids, {
    required bool isActive,
  }) async {
    final res = await _fns.httpsCallable('bulkSetGlobalExerciseActive').call({
      'ids': ids,
      'isActive': isActive,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return (
      changed: ((m['changed'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      missing: ((m['missing'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// ARCHIVES many exercises. Nothing is removed. See [delete] for why.
  ///
  /// The `deleted` field of the result names what was ARCHIVED — the wire key
  /// is kept for the same compatibility reason the callable's name is.
  Future<({List<String> deleted, List<String> missing})> bulkDelete(
    List<String> ids,
  ) async {
    final res = await _fns.httpsCallable('bulkDeleteGlobalExercises').call({
      'ids': ids,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return (
      deleted: ((m['deleted'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      missing: ((m['missing'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  /// Validates (and optionally performs) a batch import — the catalog's single
  /// import pipeline.
  ///
  /// ALWAYS run with `dryRun: true` first. The report is identical either way,
  /// nothing is written, and the operator sees exactly which rows would be
  /// rejected and why before a single document is created.
  Future<ExerciseImportReport> bulkImport(
    List<Map<String, dynamic>> exercises, {
    required bool dryRun,
    String? category,
    String source = 'import',
    String conflictMode = 'skip',
    bool isActive = true,
  }) async {
    final res = await _fns.httpsCallable('bulkImportGlobalExercises').call({
      'exercises': exercises,
      'dryRun': dryRun,
      'source': source,
      'conflictMode': conflictMode,
      'isActive': isActive,
      if (category != null && category.isNotEmpty) 'category': category,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    int n(String k) => (m[k] is num) ? (m[k] as num).toInt() : 0;

    return ExerciseImportReport(
      dryRun: m['dryRun'] == true,
      conflictMode: (m['conflictMode'] ?? 'skip').toString(),
      isActive: m['isActive'] != false,
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

  /// Exports the catalog in the exact shape [bulkImport] accepts, so an export
  /// can be re-imported into another environment untransformed.
  Future<({List<Map<String, dynamic>> exercises, bool truncated})> export({
    bool includeInactive = false,
  }) async {
    final res = await _fns.httpsCallable('exportGlobalExercises').call({
      'includeInactive': includeInactive,
    });
    final m = Map<String, dynamic>.from(res.data as Map);
    return (
      exercises: ((m['exercises'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      truncated: m['truncated'] == true,
    );
  }

  /// Name collisions inside the catalog, largest cluster first.
  Future<({int scanned, bool truncated, List<ExerciseDuplicateGroup> groups})>
  findDuplicates() async {
    final res = await _fns.httpsCallable('findGlobalExerciseDuplicates').call();
    final m = Map<String, dynamic>.from(res.data as Map);
    return (
      scanned: (m['scanned'] is num) ? (m['scanned'] as num).toInt() : 0,
      truncated: m['truncated'] == true,
      groups: ((m['groups'] as List?) ?? const [])
          .map(
            (e) => ExerciseDuplicateGroup.fromMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }

  // ── Analytics ──────────────────────────────────────────────────────

  Future<ExerciseAnalytics> analytics() async {
    final res = await _fns.httpsCallable('getExerciseLibraryAnalytics').call();
    final m = Map<String, dynamic>.from(res.data as Map);
    final counts = Map<String, dynamic>.from((m['counts'] as Map?) ?? const {});
    int n(Map<String, dynamic> src, String k) =>
        (src[k] is num) ? (src[k] as num).toInt() : 0;

    return ExerciseAnalytics(
      total: n(counts, 'total'),
      active: n(counts, 'active'),
      inactive: n(counts, 'inactive'),
      withVideo: n(counts, 'withVideo'),
      withoutVideo: n(counts, 'withoutVideo'),
      categories: n(counts, 'categories'),
      categoryCounts: ((m['categoryCounts'] as List?) ?? const []).map((e) {
        final v = Map<String, dynamic>.from(e as Map);
        return ExerciseCategoryCount(
          category: (v['category'] ?? '').toString(),
          count: (v['count'] is num) ? (v['count'] as num).toInt() : 0,
          active: (v['active'] is num) ? (v['active'] as num).toInt() : 0,
        );
      }).toList(),
      recent: ((m['recent'] as List?) ?? const []).map((e) {
        final v = Map<String, dynamic>.from(e as Map);
        return (
          id: (v['id'] ?? '').toString(),
          name: (v['name'] ?? '').toString(),
          category: (v['category'] ?? '').toString(),
          isActive: v['isActive'] != false,
          at: v['createdAt'] is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  (v['createdAt'] as num).toInt(),
                )
              : null,
        );
      }).toList(),
    );
  }
}
