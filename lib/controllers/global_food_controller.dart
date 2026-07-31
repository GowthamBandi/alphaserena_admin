import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';

import '../core/services/food_platform_service.dart';
import '../core/utils/food_csv.dart';
import '../core/utils/food_errors.dart';
import '../core/utils/food_search.dart';
import '../models/global_food_model.dart';
import '../widgets/app_snackbar.dart';

/// FOOD PLATFORM — the Global Food Database console.
///
/// Owns the ONLY authoring surface for platform food. It writes nothing
/// directly: every mutation is a Cloud Function call, because the security
/// rules deny client writes to `foodDatabase` to everyone — including this
/// console. What that buys is not just defence in depth: it guarantees every
/// change to the library thousands of organizations read carries a
/// server-written audit entry and an immutable revision record.
///
/// ── DESIGNED FOR TENS OF THOUSANDS OF ROWS ──────────────────────────────
/// The list is CURSOR-paginated and every filter is server-side. Nothing here
/// ever loads the library into memory to sort or filter it: at 50,000 foods
/// that is a multi-megabyte download per keystroke, and it is the single
/// difference between a console that works at demo scale and one that works in
/// production.
class GlobalFoodController extends GetxController {
  /// Injectable so the console can actually be tested. The previous version
  /// constructed the service inline, which touches Firebase at construction
  /// time and made every screen in this feature unmountable in a widget test.
  GlobalFoodController({FoodPlatformService? service})
    : _service = service ?? FoodPlatformService();

  final FoodPlatformService _service;

  /// The seed dataset frozen out of the TrainerHQ app bundle. Migration
  /// material only — no app reads it at runtime.
  static const String seedAsset = 'assets/data/global_food_seed.json';

  // ── List state ─────────────────────────────────────────────────────
  final RxList<GlobalFoodModel> foods = <GlobalFoodModel>[].obs;
  final RxList<FoodCategoryModel> categories = <FoodCategoryModel>[].obs;
  final Rx<FoodQuery> query = const FoodQuery().obs;

  /// First-page load. Distinct from [isLoadingMore] so the list can skeleton on
  /// one and show a footer spinner on the other.
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = false.obs;

  /// Failure of the FIRST page — the list has nothing to show.
  final Rxn<FoodConsoleError> error = Rxn<FoodConsoleError>();

  /// Failure of a SUBSEQUENT page. Kept separate on purpose: throwing away 200
  /// already-loaded rows because page 5 failed is a worse outcome than the
  /// failure itself.
  final Rxn<FoodConsoleError> loadMoreError = Rxn<FoodConsoleError>();

  /// Raw text in the search box, before it becomes an index prefix.
  final RxString searchText = ''.obs;

  DocumentSnapshot<Map<String, dynamic>>? _cursor;

  /// Guards against a slower earlier page overwriting a newer query.
  int _seq = 0;
  Timer? _debounce;

  // ── Selection ──────────────────────────────────────────────────────
  final RxSet<String> selected = <String>{}.obs;
  bool get hasSelection => selected.isNotEmpty;

  // ── Operation state ────────────────────────────────────────────────
  final RxBool isSaving = false.obs;
  final RxBool isBusy = false.obs;

  // ── Panels ─────────────────────────────────────────────────────────
  /// Why the last write failed, surfaced INLINE by the editors.
  ///
  /// A toast that vanishes in two seconds is not adequate feedback for a
  /// refused save: the operator is left staring at a form that will not close
  /// with no statement of what is wrong.
  final Rxn<FoodConsoleError> writeError = Rxn<FoodConsoleError>();

  final Rxn<FoodAnalytics> analytics = Rxn<FoodAnalytics>();
  final Rxn<FoodConsoleError> analyticsError = Rxn<FoodConsoleError>();
  final RxBool isLoadingAnalytics = false.obs;

  final Rxn<FoodImportReport> lastImport = Rxn<FoodImportReport>();
  final RxList<DuplicateGroup> duplicateGroups = <DuplicateGroup>[].obs;
  final RxMap<String, String> duplicateNames = <String, String>{}.obs;
  final RxnString duplicateSummary = RxnString();
  final RxnString lastExportJson = RxnString();
  final RxMap<String, int> categoryCounts = <String, int>{}.obs;
  final RxInt uncategorisedCount = 0.obs;

  /// The food open in the detail view, or null when the list is showing.
  final Rxn<GlobalFoodModel> detail = Rxn<GlobalFoodModel>();
  final Rxn<FoodUsage> detailUsage = Rxn<FoodUsage>();
  final RxList<FoodHistoryEntry> detailHistory = <FoodHistoryEntry>[].obs;
  final RxBool isLoadingDetail = false.obs;

  StreamSubscription? _categorySub;

  List<FoodCategoryModel> get activeCategories =>
      categories.where((c) => !c.isArchived).toList();

  /// Top-level categories with their children attached, for the tree view.
  List<({FoodCategoryModel parent, List<FoodCategoryModel> children})>
  get categoryTree {
    final roots = categories.where((c) => c.isTopLevel).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [
      for (final root in roots)
        (
          parent: root,
          children:
              categories.where((c) => c.parentId == root.id).toList()
                ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
        ),
    ];
  }

  @override
  void onInit() {
    super.onInit();
    _bindCategories();
    refreshList();
    loadAnalytics();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    _categorySub?.cancel();
    super.onClose();
  }

  // ── Categories ─────────────────────────────────────────────────────

  void _bindCategories() {
    _categorySub?.cancel();
    _categorySub = _service.watchCategories().listen(
      (list) {
        categories.value = [
          for (final c in list) c.withCount(categoryCounts[c.id] ?? 0),
        ];
      },
      // The taxonomy is a filter, not a dependency — its failure must never
      // take the library down with it.
      onError: (Object _) => categories.clear(),
    );
  }

  String categoryName(String id) {
    if (id.isEmpty) return '';
    for (final c in categories) {
      if (c.id == id) return c.name;
    }
    return '';
  }

  /// Full label including the parent, so "Chicken" reads as "Protein › Chicken".
  String categoryPath(String id) {
    final match = categories.firstWhereOrNull((c) => c.id == id);
    if (match == null) return '';
    if (match.isTopLevel) return match.name;
    final parent = categories.firstWhereOrNull((c) => c.id == match.parentId);
    return parent == null ? match.name : '${parent.name} › ${match.name}';
  }

  /// Loads live per-category counts.
  ///
  /// Failure is deliberately SILENT: counts are an enrichment, and a missing
  /// count must never blank the taxonomy or the dashboard around it. The
  /// categories simply render with the count they already had.
  Future<void> loadCategoryCounts() async {
    try {
      final res = await _service.categoryCounts();
      categoryCounts.value = res.counts;
      uncategorisedCount.value = res.uncategorised;
      categories.value = [
        for (final c in categories) c.withCount(res.counts[c.id] ?? 0),
      ];
    } catch (_) {
      // Intentionally swallowed — see above.
    }
  }

  // ── The list ───────────────────────────────────────────────────────

  /// Reloads from page one. Every filter change routes through here so the
  /// cursor can never survive a query it no longer belongs to.
  Future<void> refreshList() async {
    final seq = ++_seq;
    _cursor = null;
    isLoading.value = true;
    error.value = null;
    loadMoreError.value = null;
    try {
      final page = await _service.fetchGlobalFoods(query: query.value);
      if (seq != _seq) return;
      foods.value = page.foods;
      _cursor = page.lastDoc;
      hasMore.value = page.hasMore;
      // Selection is scoped to what is on screen: silently carrying a hidden
      // selection into a bulk action is how a curator archives 200 foods they
      // cannot see.
      selected.removeWhere((id) => !page.foods.any((f) => f.id == id));
    } catch (e) {
      if (seq != _seq) return;
      foods.clear();
      hasMore.value = false;
      error.value = describeFoodError(e, operation: 'the foods list');
    } finally {
      if (seq == _seq) isLoading.value = false;
    }
  }

  /// Appends the next page. Safe to call on every scroll event — it no-ops
  /// while a page is already in flight or the list is exhausted.
  Future<void> loadMore() async {
    if (isLoadingMore.value || isLoading.value || !hasMore.value) return;
    final seq = _seq;
    isLoadingMore.value = true;
    loadMoreError.value = null;
    try {
      final page = await _service.fetchGlobalFoods(
        query: query.value,
        startAfter: _cursor,
      );
      if (seq != _seq) return;
      foods.addAll(page.foods);
      _cursor = page.lastDoc;
      hasMore.value = page.hasMore;
    } catch (e) {
      // NOT `error`: the rows already on screen stay, and the footer offers a
      // retry for the page that failed.
      if (seq == _seq) {
        loadMoreError.value = describeFoodError(e, operation: 'the next page');
      }
    } finally {
      if (seq == _seq) isLoadingMore.value = false;
    }
  }

  void onSearchChanged(String value) {
    searchText.value = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      // Below the index minimum a prefix query cannot be answered, so browse
      // instead of issuing one that would match nothing.
      query.value = query.value.copyWith(prefix: foodSearchPrefix(value));
      refreshList();
    });
  }

  /// Applies a whole query at once (a dashboard drill-down, a category click).
  ///
  /// Clears the search text unless the new query carries one, so the box can
  /// never show a term the list is not actually filtered by.
  void setQuery(FoodQuery next) {
    if (next.prefix == null || next.prefix!.isEmpty) searchText.value = '';
    query.value = next;
    refreshList();
  }

  void clearFilters() {
    searchText.value = '';
    query.value = const FoodQuery();
    refreshList();
  }

  // ── Selection ──────────────────────────────────────────────────────

  void toggleSelected(String id) {
    selected.contains(id) ? selected.remove(id) : selected.add(id);
  }

  void selectAllLoaded() => selected.addAll(foods.map((f) => f.id));
  void clearSelection() => selected.clear();

  // ── Detail ─────────────────────────────────────────────────────────

  /// Opens the detail view. Clicking a row must NOT drop straight into an
  /// editor — a curator needs to see usage and history before touching a food
  /// hundreds of organizations depend on.
  Future<void> openDetail(GlobalFoodModel food) async {
    detail.value = food;
    detailUsage.value = food.usage;
    detailHistory.clear();
    isLoadingDetail.value = true;
    try {
      final results = await Future.wait([
        _service.usage(food.id),
        _service.history(food.id),
        _service.fetchFood(food.id),
      ]);
      final fresh = results[2] as GlobalFoodModel?;
      if (detail.value?.id != food.id) return; // navigated away
      detailUsage.value = results[0] as FoodUsage;
      detailHistory.value = results[1] as List<FoodHistoryEntry>;
      if (fresh != null) detail.value = fresh;
    } catch (e) {
      AppSnackbar.show(title: 'Partly loaded', message: describeFoodError(e).message);
    } finally {
      isLoadingDetail.value = false;
    }
  }

  Future<void> reloadDetail() async {
    final current = detail.value;
    if (current != null) await openDetail(current);
  }

  void closeDetail() {
    detail.value = null;
    detailUsage.value = null;
    detailHistory.clear();
  }

  // ── Authoring ──────────────────────────────────────────────────────

  /// Creates or edits a global food.
  ///
  /// The server re-validates everything: macro mass, sugar-vs-carbs,
  /// saturated-fat-vs-fat and Atwater energy consistency. [allowEnergyMismatch]
  /// is the curator knowingly accepting a row whose calories macros cannot
  /// explain — never the default.
  Future<bool> saveFood(
    GlobalFoodModel food, {
    bool allowEnergyMismatch = false,
    String? status,
    String reason = '',
  }) async {
    isSaving.value = true;
    writeError.value = null;
    try {
      final res = await _service.upsertFood(
        food,
        allowEnergyMismatch: allowEnergyMismatch,
        status: status,
        reason: reason,
      );
      // COMMITTED. Everything below is presentation, and none of it may turn a
      // completed write into a reported failure.
      //
      // Deliberately NOT awaited: the caller closes its dialog on this return,
      // and the success snackbar is a GetX ROUTE. Pushing it first made the
      // caller's Get.back() pop the TOAST instead of the wizard — the save
      // worked, the food appeared in the list, and the operator was left
      // staring at a form that would not close.
      unawaited(
        _afterWrite(
          title: status == 'draft' ? 'Saved as draft' : 'Saved',
          message: res.warnings.isEmpty
              ? '"${food.name}" saved (revision ${res.revision}).'
              : res.warnings.join(' · '),
          reloadDetailId: res.id,
        ),
      );
      return true;
    } catch (e) {
      final failure = describeFoodError(e, operation: 'upsertGlobalFood');
      writeError.value = failure;
      AppSnackbar.show(title: 'Not saved', message: failure.message);
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Runs the side effects that follow a COMMITTED write.
  ///
  /// Deliberately swallows its own failures. The server has already accepted
  /// the change by the time this runs; a toast that cannot render or a list
  /// that cannot refresh is a display problem, and reporting it as "not saved"
  /// sends the operator back to repeat a write that already succeeded.
  Future<void> _afterWrite({
    required String title,
    required String message,
    String? reloadDetailId,
  }) async {
    // Yield first so any caller that closes a dialog on success does so BEFORE
    // the snackbar route is pushed. Without this the caller's pop lands on the
    // toast and the dialog survives.
    await Future<void>.delayed(Duration.zero);
    try {
      AppSnackbar.show(title: title, message: message);
    } catch (_) {
      // A snackbar can fail while a dialog owns the overlay. Never fatal.
    }
    try {
      await refreshList();
      if (reloadDetailId != null && detail.value?.id == reloadDetailId) {
        await reloadDetail();
      }
      // The dashboard aggregates (totals, published/draft/archived, needs-review
      // and missing-data queues, category counts) are otherwise loaded only once
      // in onInit, so without this a committed create/edit/archive/merge left the
      // whole Dashboard tab and its tab badges stale until the screen was fully
      // re-entered. Fire-and-forget: it swallows its own errors and must never
      // turn a completed write into a reported failure.
      unawaited(loadAnalytics());
    } catch (_) {
      // The list will be correct on the next load; the write is already done.
    }
  }

  /// Moves a food through the editorial lifecycle.
  ///
  /// Returns the server's refusal message when the archive usage guard blocks
  /// it, so the caller can show the curator exactly what is affected and offer
  /// an explicit override — rather than swallowing the refusal as a failure.
  Future<String?> setStatus(
    GlobalFoodModel food,
    String status, {
    bool force = false,
    String reason = '',
  }) async {
    isBusy.value = true;
    try {
      await _service.setStatus(
        food.id,
        status: status,
        force: force,
        reason: reason,
      );
      await _afterWrite(
        title: switch (status) {
          'archived' => 'Archived',
          'draft' => 'Moved to draft',
          _ => 'Published',
        },
        message: status == 'archived'
            ? '"${food.name}" is hidden from search. Existing diet plans are '
                  'untouched.'
            : '"${food.name}" is now $status.',
        reloadDetailId: food.id,
      );
      return null;
    } on FirebaseFunctionsException catch (e) {
      // failed-precondition is the usage guard, not an error — hand the
      // message back so the caller can ask for confirmation.
      if (e.code == 'failed-precondition') return e.message ?? 'In use.';
      AppSnackbar.show(title: 'Failed', message: e.message ?? 'Try again.');
      return null;
    } finally {
      isBusy.value = false;
    }
  }

  Future<void> setVerification(GlobalFoodModel food, String verification) async {
    isBusy.value = true;
    try {
      await _service.setVerification(food.id, verification);
      await _afterWrite(
        title: 'Updated',
        message: 'Marked $verification.',
        reloadDetailId: food.id,
      );
    } catch (e) {
      AppSnackbar.show(title: 'Failed', message: describeFoodError(e).message);
    } finally {
      isBusy.value = false;
    }
  }

  /// Applies a status or verification change to the current selection.
  ///
  /// The archive guard runs per row on the server, so a bulk archive reports
  /// exactly which foods were skipped and why instead of failing wholesale or,
  /// worse, quietly withdrawing foods that are in use.
  Future<({int changed, List<({String id, String name, String reason})> blocked})?>
  bulkApply({
    String? status,
    String? verification,
    bool force = false,
    String reason = '',
  }) async {
    if (selected.isEmpty) return null;
    isBusy.value = true;
    try {
      final res = await _service.bulkSetState(
        selected.toList(),
        status: status,
        verification: verification,
        force: force,
        reason: reason,
      );
      await refreshList();
      // Bulk status/verification changes move foods between the published/
      // draft/archived buckets the dashboard counts.
      unawaited(loadAnalytics());
      if (res.blocked.isEmpty) {
        clearSelection();
        AppSnackbar.show(
          title: 'Done',
          message: '${res.changed.length} food'
              '${res.changed.length == 1 ? '' : 's'} updated.',
        );
      } else {
        // Keep the blocked rows selected so the operator can act on them,
        // and only those — anything that succeeded is no longer actionable.
        selected
          ..clear()
          ..addAll(res.blocked.map((b) => b.id));
      }
      return (changed: res.changed.length, blocked: res.blocked);
    } catch (e) {
      AppSnackbar.show(title: 'Failed', message: describeFoodError(e).message);
      return null;
    } finally {
      isBusy.value = false;
    }
  }

  /// Refreshes the stored usage snapshot for the selection (or the page).
  Future<void> refreshUsageFor(List<String> ids) async {
    if (ids.isEmpty) return;
    isBusy.value = true;
    try {
      await _service.refreshUsage(ids);
      await refreshList();
      // Usage feeds the "never used" / "most used" dashboard panels.
      unawaited(loadAnalytics());
      AppSnackbar.show(
        title: 'Usage refreshed',
        message: 'Recomputed for ${ids.length > 25 ? 25 : ids.length} foods.',
      );
    } catch (e) {
      AppSnackbar.show(title: 'Failed', message: describeFoodError(e).message);
    } finally {
      isBusy.value = false;
    }
  }

  // ── Duplicates ─────────────────────────────────────────────────────

  Future<void> scanDuplicates() async {
    isBusy.value = true;
    try {
      final res = await _service.findDuplicates();
      duplicateGroups.value = res.groups;
      duplicateNames.value = res.names;
      duplicateSummary.value = res.groups.isEmpty
          ? 'No duplicate signals across ${res.scanned} global foods.'
          : '${res.groups.length} signal${res.groups.length == 1 ? '' : 's'} '
                'across ${res.scanned} global foods'
                '${res.truncated ? ' (scan truncated)' : ''}.';
    } catch (e) {
      AppSnackbar.show(title: 'Scan failed', message: describeFoodError(e).message);
    } finally {
      isBusy.value = false;
    }
  }

  /// Resolves a duplicate group by folding the losers into one survivor.
  /// The losers are ARCHIVED, never deleted, so every plan already pointing at
  /// one keeps resolving exactly as before.
  Future<bool> mergeFoods({
    required String keepId,
    required List<String> mergeIds,
    String reason = '',
  }) async {
    isBusy.value = true;
    try {
      final res = await _service.merge(
        keepId: keepId,
        mergeIds: mergeIds,
        reason: reason,
      );
      // COMMITTED — see _afterWrite.
      try {
        AppSnackbar.show(
          title: 'Merged',
          message: '${res.archived.length} food'
              '${res.archived.length == 1 ? '' : 's'} archived; their names are '
              'now aliases of the survivor.',
        );
        await scanDuplicates();
        await refreshList();
        // Merge archives the losers, changing the archived/total aggregates.
        unawaited(loadAnalytics());
      } catch (_) {}
      return true;
    } catch (e) {
      AppSnackbar.show(title: 'Merge failed', message: describeFoodError(e).message);
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  Future<List<GlobalFoodModel>> resolveFoods(List<String> ids) =>
      _service.fetchFoodsByIds(ids);

  // ── Categories ─────────────────────────────────────────────────────

  Future<bool> saveCategory({
    String? id,
    required String name,
    String icon = '',
    String parentId = '',
    int sortOrder = 100,
  }) async {
    isSaving.value = true;
    try {
      await _service.upsertCategory(
        id: id,
        name: name,
        icon: icon,
        parentId: parentId,
        sortOrder: sortOrder,
      );
      // COMMITTED. Not awaited, and the toast is deferred a frame — a GetX
      // snackbar is a ROUTE, so pushing it before the caller pops its dialog
      // makes that pop dismiss the toast and leave the editor open.
      unawaited(
        _afterWrite(title: 'Saved', message: 'Category "$name" saved.'),
      );
      unawaited(loadCategoryCounts());
      return true;
    } catch (e) {
      AppSnackbar.show(title: 'Not saved', message: describeFoodError(e).message);
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> setCategoryArchived(FoodCategoryModel c, bool archived) async {
    try {
      await _service.setCategoryStatus(c.id, archived: archived);
      AppSnackbar.show(
        title: archived ? 'Archived' : 'Restored',
        // Foods keep their categoryId; an archived category simply stops
        // appearing in pickers. Nothing is orphaned, no food is rewritten.
        message: archived
            ? '"${c.name}" is hidden from pickers. Its ${c.foodCount} foods '
                  'keep their category.'
            : '"${c.name}" is available again.',
      );
    } catch (e) {
      AppSnackbar.show(title: 'Failed', message: describeFoodError(e).message);
    }
  }

  // ── Analytics ──────────────────────────────────────────────────────

  /// Loads the dashboard.
  ///
  /// Reports failure through [analyticsError] rather than a snackbar: this runs
  /// on the console's first frame, where a toast competes with the list's own
  /// first load and is dismissed before anyone reads it. The panel renders the
  /// error — including how to fix it — in place.
  Future<void> loadAnalytics() async {
    isLoadingAnalytics.value = true;
    analyticsError.value = null;
    try {
      analytics.value = await _service.analytics();
    } catch (e) {
      analyticsError.value = describeFoodError(
        e,
        operation: 'getFoodLibraryAnalytics',
      );
    } finally {
      isLoadingAnalytics.value = false;
    }
    // Independent of the dashboard: counts enrich the taxonomy whether or not
    // the analytics callable exists.
    await loadCategoryCounts();
  }

  // ── Import / export / migration ────────────────────────────────────

  /// Loads the frozen seed dataset and normalizes it to the import shape.
  /// The ONE remaining reader of the old JSON, and a migration tool — no app
  /// reads that file at runtime.
  Future<List<Map<String, dynamic>>> loadSeedCatalog() async {
    final raw = await rootBundle.loadString(seedAsset);
    final decoded = json.decode(raw);
    final list = (decoded is Map && decoded['foods'] is List)
        ? decoded['foods'] as List
        : const [];

    final out = <Map<String, dynamic>>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final per = (m['per100'] is Map)
          ? Map<String, dynamic>.from(m['per100'] as Map)
          : const <String, dynamic>{};
      final name = (m['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      // The seed's `tags` were search-only hints that were never persisted.
      // They become ALIASES, which the platform does index — so "staple" and
      // "grain" stay searchable.
      final tags = ((m['tags'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.length >= 2)
          .toList();

      out.add({
        'name': name,
        'foodType': 'dish',
        'cuisine': 'indian',
        'aliases': tags,
        'calories': per['calories'] ?? 0,
        'protein': per['protein'] ?? 0,
        'carbs': per['carbs'] ?? 0,
        'fat': per['fat'] ?? 0,
        // The seed carries no fiber/sugar/saturated fat. They stay zero rather
        // than invented; each correction lands in the food's revision trail.
        'portions': ((m['portions'] as List?) ?? const [])
            .whereType<Map>()
            .map((p) => {'label': p['label'], 'grams': p['grams']})
            .toList(),
        'source': 'seed',
        'sourceRef': foodNameKey(name),
      });
    }
    return out;
  }

  /// Validates or performs a bulk import. The caller always dry-runs first.
  Future<FoodImportReport?> runImport(
    List<Map<String, dynamic>> rows, {
    required bool dryRun,
    String? categoryId,
    String source = 'import',
    String conflictMode = 'skip',
    String status = 'draft',
  }) async {
    isBusy.value = true;
    try {
      final report = await _service.bulkImport(
        rows,
        dryRun: dryRun,
        categoryId: categoryId,
        source: source,
        conflictMode: conflictMode,
        status: status,
      );
      lastImport.value = report;
      if (!dryRun) {
        await refreshList();
        // Import bypasses _afterWrite, so the dashboard aggregates (totals,
        // drafts, missing-data) would otherwise stay stale until a full screen
        // re-entry even though several foods were just written.
        unawaited(loadAnalytics());
      }
      return report;
    } catch (e) {
      AppSnackbar.show(title: 'Import failed', message: describeFoodError(e).message);
      return null;
    } finally {
      isBusy.value = false;
    }
  }

  /// Parses an uploaded file into import rows, choosing the reader by content.
  ///
  /// Returns the rows plus anything the operator should know before importing:
  /// columns that were not understood are surfaced, never dropped in silence.
  ({List<Map<String, dynamic>> rows, List<String> unmapped, String? error})
  parseImportFile(String name, String content) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      return (
        rows: const <Map<String, dynamic>>[],
        unmapped: const <String>[],
        error:
            'Excel workbooks are a binary format this console cannot read. '
            'Export the sheet as CSV (File → Save As → CSV) and upload that.',
      );
    }
    if (lower.endsWith('.json')) {
      final rows = parseFoodJson(content);
      if (rows == null) {
        return (
          rows: const <Map<String, dynamic>>[],
          unmapped: const <String>[],
          error: 'That is not a valid foods array or {"foods": [...]} object.',
        );
      }
      return (rows: rows, unmapped: const <String>[], error: null);
    }
    try {
      final table = parseCsvTable(content);
      final mapping = mapCsvHeaders(table.headers);
      final rows = csvToFoodRows(table, mapping);
      return (
        rows: rows,
        unmapped: unmappedCsvHeaders(table.headers, mapping),
        error: null,
      );
    } on CsvError catch (e) {
      return (
        rows: const <Map<String, dynamic>>[],
        unmapped: const <String>[],
        error: e.message,
      );
    }
  }

  Future<void> runExport({bool includeArchived = false}) async {
    isBusy.value = true;
    try {
      final res = await _service.export(includeArchived: includeArchived);
      lastExportJson.value = const JsonEncoder.withIndent(
        '  ',
      ).convert({'foods': res.foods});
      AppSnackbar.show(
        title: 'Exported',
        message: res.truncated
            ? '${res.foods.length} foods (truncated at the export ceiling).'
            : '${res.foods.length} foods ready to copy.',
      );
    } catch (e) {
      AppSnackbar.show(title: 'Export failed', message: describeFoodError(e).message);
    } finally {
      isBusy.value = false;
    }
  }

  /// Exports the selection (or the loaded page) as CSV.
  String exportCsv(List<GlobalFoodModel> rows) {
    const headers = [
      'name', 'brand', 'category', 'foodType', 'cuisine', 'status',
      'verification', 'calories', 'protein', 'carbs', 'fat', 'fiber',
      'sugar', 'saturatedFat', 'barcode', 'aliases', 'source', 'revision',
    ];
    String cell(Object? v) {
      final text = (v ?? '').toString();
      // Quote anything that would otherwise break the row apart on re-import.
      return text.contains(RegExp(r'[",\n]'))
          ? '"${text.replaceAll('"', '""')}"'
          : text;
    }

    final buffer = StringBuffer(headers.join(','))..writeln();
    for (final f in rows) {
      buffer.writeln([
        cell(f.name), cell(f.brand), cell(categoryName(f.categoryId)),
        cell(f.foodType), cell(f.cuisine), cell(f.status), cell(f.verification),
        cell(f.calories), cell(f.protein), cell(f.carbs), cell(f.fat),
        cell(f.fiber), cell(f.sugar), cell(f.saturatedFat), cell(f.barcode),
        cell(f.aliases.join('; ')), cell(f.source), cell(f.revision),
      ].join(','));
    }
    return buffer.toString();
  }

  /// Runs an additive migration to completion, batch by batch.
  Future<void> runBackfill({
    required bool dryRun,
    String? usageCollection,
  }) async {
    isBusy.value = true;
    var cursor = '';
    var scanned = 0;
    var patched = 0;
    try {
      while (true) {
        final res = usageCollection == null
            ? await _service.backfill(dryRun: dryRun, cursor: cursor)
            : await _service.backfillUsageIndex(
                collection: usageCollection,
                dryRun: dryRun,
                cursor: cursor,
              );
        scanned += res.scanned;
        patched += res.patched;
        if (res.done || res.cursor.isEmpty) break;
        cursor = res.cursor;
      }
      AppSnackbar.show(
        title: dryRun ? 'Dry run complete' : 'Migration complete',
        message: '$patched of $scanned documents '
            '${dryRun ? 'would be' : 'were'} upgraded.',
      );
    } catch (e) {
      AppSnackbar.show(title: 'Migration failed', message: describeFoodError(e).message);
    } finally {
      isBusy.value = false;
    }
  }

}
