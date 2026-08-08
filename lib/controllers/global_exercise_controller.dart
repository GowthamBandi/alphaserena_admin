import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';

import '../core/services/exercise_catalog_service.dart';
import '../core/utils/csv_table.dart';
import '../core/utils/exercise_csv.dart';
import '../core/utils/exercise_errors.dart';
import '../core/utils/exercise_search.dart';
import '../models/global_exercise_model.dart';
import '../widgets/app_snackbar.dart';

/// GLOBAL EXERCISE LIBRARY — the master exercise catalog console.
///
/// Owns the ONLY authoring surface for the platform's exercise catalog. It
/// writes nothing directly: every mutation is a Cloud Function call, because
/// the security rules deny client writes to `exerciseCatalog` to everyone —
/// including this console. What that buys is not just defence in depth: it
/// guarantees every change to the catalog carries a server-written audit entry,
/// which the console's existing Audit Log screen already renders.
///
/// ── BUILT FOR A CATALOG THAT GROWS ──────────────────────────────────────
/// The list is CURSOR-paginated and every filter is server-side. Nothing here
/// ever loads the catalog into memory to sort or filter it — the single
/// difference between a console that works at demo scale and one that works in
/// production.
///
/// A deliberate structural twin of `GlobalFoodController`.
class GlobalExerciseController extends GetxController {
  /// Injectable so the console can actually be tested. Constructing the service
  /// inline would touch Firebase at construction time and make every screen in
  /// this feature unmountable in a widget test.
  GlobalExerciseController({ExerciseCatalogService? service})
    : _service = service ?? ExerciseCatalogService();

  final ExerciseCatalogService _service;

  /// The master dataset shipped with the console. Founding material only — no
  /// app reads it at runtime, and importing it is a one-time operator action.
  static const String seedAsset = 'assets/data/global_exercise_seed.csv';

  // ── List state ─────────────────────────────────────────────────────
  final RxList<GlobalExerciseModel> exercises = <GlobalExerciseModel>[].obs;
  final Rx<ExerciseQuery> query = const ExerciseQuery().obs;

  /// First-page load. Distinct from [isLoadingMore] so the list can skeleton on
  /// one and show a footer spinner on the other.
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = false.obs;

  /// Failure of the FIRST page — the list has nothing to show.
  final Rxn<ConsoleError> error = Rxn<ConsoleError>();

  /// Failure of a SUBSEQUENT page. Kept separate on purpose: throwing away 200
  /// already-loaded rows because page 5 failed is a worse outcome than the
  /// failure itself.
  final Rxn<ConsoleError> loadMoreError = Rxn<ConsoleError>();

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

  /// Why the last write failed, surfaced INLINE by the editors.
  ///
  /// A toast that vanishes in two seconds is not adequate feedback for a
  /// refused save: the operator is left staring at a form that will not close
  /// with no statement of what is wrong.
  final Rxn<ConsoleError> writeError = Rxn<ConsoleError>();

  // ── Panels ─────────────────────────────────────────────────────────
  final Rxn<ExerciseAnalytics> analytics = Rxn<ExerciseAnalytics>();
  final Rxn<ConsoleError> analyticsError = Rxn<ConsoleError>();
  final RxBool isLoadingAnalytics = false.obs;

  final Rxn<ExerciseImportReport> lastImport = Rxn<ExerciseImportReport>();
  final RxList<ExerciseDuplicateGroup> duplicateGroups =
      <ExerciseDuplicateGroup>[].obs;
  final RxnString duplicateSummary = RxnString();
  final RxnString lastExportJson = RxnString();

  /// Live per-category counts, keyed by category name. Server-computed.
  final RxMap<String, int> categoryCounts = <String, int>{}.obs;

  @override
  void onInit() {
    super.onInit();
    refreshList();
    loadAnalytics();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
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
      final page = await _service.fetchExercises(query: query.value);
      if (seq != _seq) return;
      exercises.value = page.exercises;
      _cursor = page.lastDoc;
      hasMore.value = page.hasMore;
      // Selection is scoped to what is on screen: silently carrying a hidden
      // selection into a bulk action is how a curator deletes 200 exercises
      // they cannot see.
      selected.removeWhere((id) => !page.exercises.any((e) => e.id == id));
    } catch (e) {
      if (seq != _seq) return;
      exercises.clear();
      hasMore.value = false;
      error.value = describeExerciseError(e, operation: 'the exercise list');
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
      final page = await _service.fetchExercises(
        query: query.value,
        startAfter: _cursor,
      );
      if (seq != _seq) return;
      exercises.addAll(page.exercises);
      _cursor = page.lastDoc;
      hasMore.value = page.hasMore;
    } catch (e) {
      // NOT `error`: the rows already on screen stay, and the footer offers a
      // retry for the page that failed.
      if (seq == _seq) {
        loadMoreError.value = describeExerciseError(
          e,
          operation: 'the next page',
        );
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
      query.value = query.value.copyWith(prefix: exerciseSearchPrefix(value));
      refreshList();
    });
  }

  /// Applies a whole query at once (a dashboard drill-down, a category click).
  ///
  /// Clears the search text unless the new query carries one, so the box can
  /// never show a term the list is not actually filtered by.
  void setQuery(ExerciseQuery next) {
    if (next.prefix == null || next.prefix!.isEmpty) searchText.value = '';
    query.value = next;
    refreshList();
  }

  void clearFilters() {
    searchText.value = '';
    query.value = const ExerciseQuery();
    refreshList();
  }

  // ── Selection ──────────────────────────────────────────────────────

  void toggleSelected(String id) {
    selected.contains(id) ? selected.remove(id) : selected.add(id);
  }

  void selectAllLoaded() => selected.addAll(exercises.map((e) => e.id));
  void clearSelection() => selected.clear();

  // ── Authoring ──────────────────────────────────────────────────────

  /// Creates or edits one catalog exercise. The server re-validates the name,
  /// the category vocabulary and the video URL, and refuses a duplicate name.
  Future<bool> save(GlobalExerciseModel exercise, {bool? isActive}) async {
    isSaving.value = true;
    writeError.value = null;
    try {
      final res = await _service.upsert(exercise, isActive: isActive);
      // COMMITTED. Everything below is presentation, and none of it may turn a
      // completed write into a reported failure.
      //
      // Deliberately NOT awaited: the caller closes its dialog on this return,
      // and the success snackbar is a GetX ROUTE. Pushing it first would make
      // the caller's Get.back() pop the TOAST instead of the form — the save
      // works, the row appears, and the operator is left staring at a form that
      // will not close.
      unawaited(
        _afterWrite(
          title: 'Saved',
          message: res.warnings.isEmpty
              ? '"${exercise.name}" saved (revision ${res.revision}).'
              : res.warnings.join(' · '),
        ),
      );
      return true;
    } catch (e) {
      final failure = describeExerciseError(e, operation: 'upsertGlobalExercise');
      writeError.value = failure;
      AppSnackbar.show(title: 'Not saved', message: failure.message);
      return false;
    } finally {
      isSaving.value = false;
    }
  }

  /// Shows a toast that can NEVER turn a completed write into a failure.
  ///
  /// A GetX snackbar is a route: it throws when no Get overlay is mounted, and
  /// it can fail while a dialog owns the overlay. Every post-commit toast in
  /// this controller goes through here, because the alternative — a bare
  /// `AppSnackbar.show` inside a `try` — lets a presentation failure land in
  /// the catch block and report a write the server already accepted as
  /// "Failed", sending the operator back to repeat it.
  void _toast({required String title, required String message}) {
    try {
      AppSnackbar.show(title: title, message: message);
    } catch (_) {
      // Display-only. Never fatal.
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
  }) async {
    // Yield first so any caller that closes a dialog on success does so BEFORE
    // the snackbar route is pushed. Without this the caller's pop lands on the
    // toast and the dialog survives.
    await Future<void>.delayed(Duration.zero);
    _toast(title: title, message: message);
    try {
      await refreshList();
      // The dashboard aggregates (totals, active/inactive, per-category counts)
      // are otherwise loaded only in onInit, so without this a committed
      // create/edit/delete leaves the Overview tab stale until the screen is
      // fully re-entered.
      unawaited(loadAnalytics());
    } catch (_) {
      // The list will be correct on the next load; the write is already done.
    }
  }

  /// Activates or deactivates one exercise — the NON-destructive control.
  Future<void> setActive(GlobalExerciseModel exercise, bool isActive) async {
    isBusy.value = true;
    try {
      await _service.setActive(exercise.id, isActive: isActive);
      await _afterWrite(
        title: isActive ? 'Activated' : 'Deactivated',
        message: isActive
            ? '"${exercise.name}" is available again.'
            : '"${exercise.name}" is hidden from import. It keeps its place in '
                  'the catalog.',
      );
    } catch (e) {
      AppSnackbar.show(
        title: 'Failed',
        message: describeExerciseError(e).message,
      );
    } finally {
      isBusy.value = false;
    }
  }

  /// Permanently deletes one exercise.
  ///
  /// The caller is responsible for confirming first. Delete is safe in this
  /// collection precisely because nothing references a catalog id — but it is
  /// still irreversible from the console, so the destructive path is never the
  /// default and never one click.
  Future<bool> delete(GlobalExerciseModel exercise) async {
    isBusy.value = true;
    try {
      await _service.delete(exercise.id);
      selected.remove(exercise.id);
      await _afterWrite(
        title: 'Archived',
        message: '"${exercise.name}" was withdrawn from the catalog. '
            'Workouts already using it keep working.',
      );
      return true;
    } catch (e) {
      AppSnackbar.show(
        title: 'Not deleted',
        message: describeExerciseError(e).message,
      );
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  // ── Bulk ───────────────────────────────────────────────────────────

  /// Activates or deactivates the current selection.
  Future<int?> bulkSetActive(bool isActive) async {
    if (selected.isEmpty) return null;
    isBusy.value = true;
    try {
      final res = await _service.bulkSetActive(
        selected.toList(),
        isActive: isActive,
      );
      // Captured BEFORE the selection is cleared — reading `selected.length`
      // after clearSelection() compares against zero, which silently disables
      // the "the rest were already" clause below rather than failing loudly.
      final requested = selected.length;
      clearSelection();
      await refreshList();
      unawaited(loadAnalytics());
      _toast(
        title: 'Done',
        message: '${res.changed.length} exercise'
            '${res.changed.length == 1 ? '' : 's'} '
            '${isActive ? 'activated' : 'deactivated'}'
            // A no-op is not a failure, but silently reporting "0 updated"
            // without saying why reads as one.
            '${res.changed.length < requested ? ' (the rest already were)' : ''}.',
      );
      return res.changed.length;
    } catch (e) {
      AppSnackbar.show(
        title: 'Failed',
        message: describeExerciseError(e).message,
      );
      return null;
    } finally {
      isBusy.value = false;
    }
  }

  /// Permanently deletes the current selection. The caller confirms first.
  Future<int?> bulkDelete() async {
    if (selected.isEmpty) return null;
    isBusy.value = true;
    try {
      final res = await _service.bulkDelete(selected.toList());
      clearSelection();
      await refreshList();
      unawaited(loadAnalytics());
      _toast(
        title: 'Archived',
        message: '${res.deleted.length} exercise'
            '${res.deleted.length == 1 ? '' : 's'} withdrawn from the catalog.',
      );
      return res.deleted.length;
    } catch (e) {
      AppSnackbar.show(
        title: 'Not deleted',
        message: describeExerciseError(e).message,
      );
      return null;
    } finally {
      isBusy.value = false;
    }
  }

  Future<List<GlobalExerciseModel>> resolveExercises(List<String> ids) =>
      _service.fetchExercisesByIds(ids);

  // ── Duplicates ─────────────────────────────────────────────────────

  Future<void> scanDuplicates() async {
    isBusy.value = true;
    try {
      final res = await _service.findDuplicates();
      duplicateGroups.value = res.groups;
      duplicateSummary.value = res.groups.isEmpty
          ? 'No duplicate names across ${res.scanned} catalog exercises.'
          : '${res.groups.length} duplicate name'
                '${res.groups.length == 1 ? '' : 's'} across ${res.scanned} '
                'exercises${res.truncated ? ' (scan truncated)' : ''}.';
    } catch (e) {
      AppSnackbar.show(
        title: 'Scan failed',
        message: describeExerciseError(e).message,
      );
    } finally {
      isBusy.value = false;
    }
  }

  // ── Analytics ──────────────────────────────────────────────────────

  /// Loads the overview.
  ///
  /// Reports failure through [analyticsError] rather than a snackbar: this runs
  /// on the console's first frame, where a toast competes with the list's own
  /// first load and is dismissed before anyone reads it. The panel renders the
  /// error — including how to fix it — in place.
  Future<void> loadAnalytics() async {
    isLoadingAnalytics.value = true;
    analyticsError.value = null;
    try {
      final result = await _service.analytics();
      analytics.value = result;
      categoryCounts.value = {
        for (final c in result.categoryCounts) c.category: c.count,
      };
    } catch (e) {
      analyticsError.value = describeExerciseError(
        e,
        operation: 'getExerciseLibraryAnalytics',
      );
    } finally {
      isLoadingAnalytics.value = false;
    }
  }

  // ── Import / export ────────────────────────────────────────────────

  /// Loads the master dataset that ships with the console and normalizes it to
  /// the import shape.
  ///
  /// It is parsed through the SAME reader an uploaded file uses, so the seed
  /// cannot take a shortcut the operator's own file would not survive.
  Future<({List<Map<String, dynamic>> rows, String? error})>
  loadSeedCatalog() async {
    try {
      final raw = await rootBundle.loadString(seedAsset);
      final parsed = parseImportFile('global_exercise_seed.csv', raw);
      return (rows: parsed.rows, error: parsed.error);
    } catch (e) {
      return (
        rows: const <Map<String, dynamic>>[],
        error:
            'The bundled dataset could not be read ($e). It ships at '
            '$seedAsset and must be declared in pubspec.yaml assets.',
      );
    }
  }

  /// Validates or performs a bulk import. The caller always dry-runs first.
  ///
  /// [chunkSize] exists because the callable caps one call at 1000 rows and the
  /// master dataset is larger. Chunking here rather than in the UI means the
  /// seed import and an operator's own oversized file take the identical path.
  Future<ExerciseImportReport?> runImport(
    List<Map<String, dynamic>> rows, {
    required bool dryRun,
    String? category,
    String source = 'import',
    String conflictMode = 'skip',
    bool isActive = true,
    int chunkSize = 500,
  }) async {
    if (rows.isEmpty) return null;
    isBusy.value = true;
    try {
      ExerciseImportReport? merged;
      for (var i = 0; i < rows.length; i += chunkSize) {
        final end = i + chunkSize > rows.length ? rows.length : i + chunkSize;
        final report = await _service.bulkImport(
          rows.sublist(i, end),
          dryRun: dryRun,
          category: category,
          source: source,
          conflictMode: conflictMode,
          isActive: isActive,
        );
        merged = merged == null ? report : _mergeReports(merged, report);
      }
      lastImport.value = merged;
      if (!dryRun) {
        await refreshList();
        // Import bypasses _afterWrite, so the overview would otherwise stay
        // stale until a full screen re-entry even though hundreds of rows were
        // just written.
        unawaited(loadAnalytics());
      }
      return merged;
    } catch (e) {
      AppSnackbar.show(
        title: 'Import failed',
        message: describeExerciseError(e).message,
      );
      return null;
    } finally {
      isBusy.value = false;
    }
  }

  /// Folds two chunk reports into one.
  ///
  /// A DRY RUN CANNOT SEE ITS OWN EARLIER CHUNKS: each call re-reads the stored
  /// catalog, so a name appearing in chunk 1 and again in chunk 3 is reported
  /// as accepted twice. The real run does not have this problem — chunk 1 is
  /// committed before chunk 2 is validated — so the preview can overcount
  /// slightly on a file that repeats a name across a chunk boundary. Saying so
  /// here is the honest fix; silently reconciling the numbers would make the
  /// preview disagree with the run.
  ExerciseImportReport _mergeReports(
    ExerciseImportReport a,
    ExerciseImportReport b,
  ) => ExerciseImportReport(
    dryRun: a.dryRun,
    conflictMode: a.conflictMode,
    isActive: a.isActive,
    received: a.received + b.received,
    accepted: a.accepted + b.accepted,
    willUpdate: a.willUpdate + b.willUpdate,
    imported: a.imported + b.imported,
    updated: a.updated + b.updated,
    rejected: [...a.rejected, ...b.rejected],
    duplicates: [...a.duplicates, ...b.duplicates],
    warnings: [...a.warnings, ...b.warnings],
  );

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
      final rows = parseExerciseJson(content);
      if (rows == null) {
        return (
          rows: const <Map<String, dynamic>>[],
          unmapped: const <String>[],
          error:
              'That is not a valid exercises array or {"exercises": [...]} '
              'object.',
        );
      }
      return (rows: rows, unmapped: const <String>[], error: null);
    }
    try {
      final table = parseCsvTable(content);
      final mapping = mapExerciseCsvHeaders(table.headers);
      final rows = csvToExerciseRows(table, mapping);
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

  Future<void> runExport({bool includeInactive = false}) async {
    isBusy.value = true;
    try {
      final res = await _service.export(includeInactive: includeInactive);
      lastExportJson.value = const JsonEncoder.withIndent(
        '  ',
      ).convert({'exercises': res.exercises});
      _toast(
        title: 'Exported',
        message: res.truncated
            ? '${res.exercises.length} exercises (truncated at the export '
                  'ceiling).'
            : '${res.exercises.length} exercises ready to copy.',
      );
    } catch (e) {
      AppSnackbar.show(
        title: 'Export failed',
        message: describeExerciseError(e).message,
      );
    } finally {
      isBusy.value = false;
    }
  }

  /// Renders rows as CSV in the exact shape the importer accepts.
  String exportCsv(List<GlobalExerciseModel> rows) {
    const headers = [
      'name', 'category', 'videoUrl', 'aliases', 'equipment', 'difficulty',
      'isActive', 'source', 'revision',
    ];
    String cell(Object? v) {
      final text = (v ?? '').toString();
      // Quote anything that would otherwise break the row apart on re-import.
      return text.contains(RegExp(r'[",\n]'))
          ? '"${text.replaceAll('"', '""')}"'
          : text;
    }

    final buffer = StringBuffer(headers.join(','))..writeln();
    for (final e in rows) {
      buffer.writeln([
        cell(e.name), cell(e.category), cell(e.videoUrl),
        cell(e.aliases.join('; ')), cell(e.equipment), cell(e.difficulty),
        cell(e.isActive), cell(e.source), cell(e.revision),
      ].join(','));
    }
    return buffer.toString();
  }
}
