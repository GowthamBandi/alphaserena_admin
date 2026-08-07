import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena_admin_portel/controllers/global_exercise_controller.dart';
import 'package:alphaserena_admin_portel/core/services/exercise_catalog_service.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/global_exercise_model.dart';
import 'package:alphaserena_admin_portel/widgets/exercise/exercise_form_dialog.dart';
import 'package:alphaserena_admin_portel/widgets/exercise/exercise_list_panel.dart';
import 'package:alphaserena_admin_portel/widgets/exercise/exercise_overview_panel.dart';

// ════════════════════════════════════════════════════════════════════════
// GLOBAL EXERCISE LIBRARY — the states, PROVEN.
//
// These exist because the food console once shipped a certification claiming
// its loading, empty and error states worked, and the first screen a human
// opened said "Could not load this view." Nothing had ever mounted it; every
// state had been asserted by reading the code.
//
// A brand-new feature's most likely production failure is the same one: its
// Cloud Functions are not deployed yet. This console's job in that situation
// is not to succeed — it is to say precisely what is missing, and to keep
// working wherever it still can. That is what most of these tests pin.
// ════════════════════════════════════════════════════════════════════════

/// A service that never touches Firebase. Every method used is overridden.
class _FakeService extends ExerciseCatalogService {
  _FakeService({
    this.pages = const [],
    this.analyticsResult,
    this.throwOnAnalytics,
    this.throwOnPage,
    this.throwOnLoadMore,
  });

  final List<ExercisePage> pages;
  final ExerciseAnalytics? analyticsResult;
  final Object? throwOnAnalytics;
  final Object? throwOnPage;
  final Object? throwOnLoadMore;

  int pageCalls = 0;
  final List<ExerciseQuery> queries = [];

  @override
  Future<ExercisePage> fetchExercises({
    ExerciseQuery query = const ExerciseQuery(),
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = ExerciseCatalogService.pageSize,
  }) async {
    queries.add(query);
    final isFirstCall = pageCalls == 0;
    if (isFirstCall && throwOnPage != null) throw throwOnPage!;
    if (!isFirstCall && throwOnLoadMore != null) throw throwOnLoadMore!;
    final page = pageCalls < pages.length
        ? pages[pageCalls]
        : const ExercisePage();
    pageCalls++;
    return page;
  }

  @override
  Future<ExerciseAnalytics> analytics() async {
    if (throwOnAnalytics != null) throw throwOnAnalytics!;
    return analyticsResult ?? const ExerciseAnalytics();
  }

  /// Ids the last bulk call was actually given.
  List<String> bulkActiveIds = const [];

  @override
  Future<({List<String> changed, List<String> missing})> bulkSetActive(
    List<String> ids, {
    required bool isActive,
  }) async {
    bulkActiveIds = ids;
    // Only the FIRST id actually changes — the rest were already in that
    // state. This is the partial case the reported message has to survive.
    return (changed: ids.take(1).toList(), missing: const <String>[]);
  }
}

GlobalExerciseModel _exercise(String name, {String category = 'Chest'}) =>
    GlobalExerciseModel(id: name, name: name, category: category);

FirebaseFunctionsException _notDeployed() => FirebaseFunctionsException(
  code: 'not-found',
  message: 'NOT_FOUND',
);

/// GetX calls `onInit` on REGISTRATION, not on construction — a directly
/// constructed controller never loads anything, and every state test would
/// silently assert against a screen that was never asked to render. Going
/// through Get.put is what makes these tests exercise the real startup path.
GlobalExerciseController _mount(ExerciseCatalogService service) =>
    Get.put(GlobalExerciseController(service: service));

/// GetMaterialApp, not MaterialApp: a GetX snackbar is a ROUTE and needs a Get
/// overlay to exist. Hosting under a plain MaterialApp would make every
/// post-write toast throw here but not in the real app — a difference that
/// hides exactly the class of bug these tests are for.
Widget _host(Widget child) => GetMaterialApp(
  home: Scaffold(body: SizedBox(width: 1200, height: 800, child: child)),
);

void main() {
  tearDown(Get.reset);

  group('the list survives what production actually does to it', () {
    testWidgets('an undeployed backend names the missing function and the fix', (
      tester,
    ) async {
      final c = _mount(
        _FakeService(throwOnPage: _notDeployed()),
      );
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Backend not deployed'), findsOneWidget);
      // The exact command, not a shrug.
      expect(
        find.textContaining('deploy_exercise_catalog.sh'),
        findsOneWidget,
      );
      // Retry cannot fix an absent function, so it is not offered as one.
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Check again'), findsOneWidget);
    });

    testWidgets('an EMPTY catalog and an OVER-NARROW filter read differently', (
      tester,
    ) async {
      final c = _mount(_FakeService());
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('The catalog is empty'), findsOneWidget);
      expect(find.textContaining('844'), findsOneWidget);

      // Now narrow it. Same zero rows, different problem, different fix.
      c.setQuery(const ExerciseQuery(category: 'Bands'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing matches those filters'), findsOneWidget);
      expect(find.text('Clear filters'), findsWidgets);
    });

    testWidgets('a failed SECOND page keeps the rows already on screen', (
      tester,
    ) async {
      // Throwing away 200 loaded rows because page 5 failed is a worse outcome
      // than the failure itself.
      final c = _mount(
        _FakeService(
          pages: [
            ExercisePage(
              exercises: [_exercise('Barbell Bench Press')],
              hasMore: true,
            ),
          ],
          throwOnLoadMore: _notDeployed(),
        ),
      );
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Barbell Bench Press'), findsOneWidget);

      await c.loadMore();
      await tester.pumpAndSettle();

      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(c.error.value, isNull);
      expect(c.loadMoreError.value, isNotNull);
    });

    testWidgets('every filter becomes a SERVER query, never an in-memory one', (
      tester,
    ) async {
      final service = _FakeService(
        pages: [
          ExercisePage(exercises: [_exercise('Plank', category: 'Core')]),
        ],
      );
      final c = _mount(service);
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();

      c.setQuery(
        const ExerciseQuery(
          category: 'Core',
          active: ExerciseActiveFilter.inactive,
        ),
      );
      await tester.pumpAndSettle();

      final last = service.queries.last;
      expect(last.category, 'Core');
      expect(last.active, ExerciseActiveFilter.inactive);
    });

    testWidgets('the exercise count reports BOTH loaded and catalog totals', (
      tester,
    ) async {
      // "50 shown" alone reads as "the catalog holds 50".
      final c = _mount(
        _FakeService(
          pages: [
            ExercisePage(exercises: [_exercise('Plank')], hasMore: true),
          ],
          analyticsResult: const ExerciseAnalytics(total: 844, active: 844),
        ),
      );
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('1+ shown'), findsOneWidget);
      expect(find.textContaining('844 in catalog'), findsOneWidget);
    });

    testWidgets('"No video uploaded" is stated on every row that lacks one', (
      tester,
    ) async {
      final c = _mount(
        _FakeService(
          pages: [
            ExercisePage(exercises: [_exercise('Plank', category: 'Core')]),
          ],
        ),
      );
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No video uploaded'), findsOneWidget);
    });

    testWidgets('selection is dropped when the list reloads', (tester) async {
      // Carrying a hidden selection into a bulk DELETE is how a curator
      // removes rows they cannot see.
      final c = _mount(
        _FakeService(
          pages: [
            ExercisePage(exercises: [_exercise('Plank')]),
            const ExercisePage(),
          ],
        ),
      );
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();

      c.toggleSelected('Plank');
      expect(c.hasSelection, isTrue);

      await c.refreshList();
      await tester.pumpAndSettle();

      expect(c.hasSelection, isFalse);
    });
  });

  group('bulk actions', () {
    testWidgets('a bulk action sends exactly the selected ids', (tester) async {
      final service = _FakeService(
        pages: [
          ExercisePage(
            exercises: [_exercise('Plank'), _exercise('Squat')],
          ),
        ],
      );
      final c = _mount(service);
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();

      c.toggleSelected('Plank');
      c.toggleSelected('Squat');
      final changed = await c.bulkSetActive(false);
      // The success toast is a real GetX route with a real dismissal timer.
      // Draining it is what proves the post-commit path completes rather than
      // throwing — the bug this test was written for.
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(service.bulkActiveIds, ['Plank', 'Squat']);
      // Two were asked for, one actually moved — the partial result must be
      // reported as the count that CHANGED, not the count that was selected.
      expect(changed, 1);
      // And the selection is dropped, so a second click cannot re-apply it.
      expect(c.hasSelection, isFalse);
    });

    testWidgets('a bulk action on an empty selection does nothing', (
      tester,
    ) async {
      final service = _FakeService();
      final c = _mount(service);
      await tester.pumpWidget(
        _host(
          ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(await c.bulkSetActive(true), isNull);
      expect(service.bulkActiveIds, isEmpty);
    });
  });

  group('the overview', () {
    testWidgets('a failed dashboard renders IN PLACE, not as a lost toast', (
      tester,
    ) async {
      final c = _mount(
        _FakeService(throwOnAnalytics: _notDeployed()),
      );
      await tester.pumpWidget(
        _host(ExerciseOverviewPanel(controller: c, onDrillDown: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('Backend not deployed'), findsOneWidget);
    });

    testWidgets('an unfounded catalog says how to found it', (tester) async {
      final c = _mount(
        _FakeService(analyticsResult: const ExerciseAnalytics()),
      );
      await tester.pumpWidget(
        _host(ExerciseOverviewPanel(controller: c, onDrillDown: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('The catalog has not been founded yet'),
        findsOneWidget,
      );
    });

    testWidgets('empty categories are named rather than hidden', (tester) async {
      final c = _mount(
        _FakeService(
          analyticsResult: const ExerciseAnalytics(
            total: 3,
            active: 3,
            withoutVideo: 3,
            categories: 20,
            categoryCounts: [
              ExerciseCategoryCount(category: 'Chest', count: 3, active: 3),
              ExerciseCategoryCount(category: 'Bands', count: 0),
            ],
          ),
        ),
      );
      await tester.pumpWidget(
        _host(ExerciseOverviewPanel(controller: c, onDrillDown: (_) {})),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Bands'), findsWidgets);
      expect(find.textContaining('holds\nnothing'), findsNothing);
    });

    testWidgets('a category row drills into the filtered list', (tester) async {
      ExerciseQuery? drilled;
      final c = _mount(
        _FakeService(
          analyticsResult: const ExerciseAnalytics(
            total: 3,
            categoryCounts: [
              ExerciseCategoryCount(category: 'Chest', count: 3, active: 3),
            ],
          ),
        ),
      );
      await tester.pumpWidget(
        _host(
          ExerciseOverviewPanel(
            controller: c,
            onDrillDown: (q) => drilled = q,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chest').first);
      await tester.pumpAndSettle();

      expect(drilled?.category, 'Chest');
    });
  });

  group('error classification is actionable, never a shrug', () {
    test('an undeployed callable is distinguished from a denied one', () {
      final undeployed = describeConsoleError(
        _notDeployed(),
        operation: 'getExerciseLibraryAnalytics',
        subject: 'the Global Exercise Library',
        deployRemedy: 'bash scripts/deploy_exercise_catalog.sh',
        logTarget: 'exerciseCatalog',
      );
      expect(undeployed.kind, ConsoleErrorKind.notDeployed);
      expect(undeployed.needsDeploy, isTrue);
      expect(undeployed.isRetryable, isFalse);

      final denied = describeConsoleError(
        FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'denied',
        ),
        subject: 'the Global Exercise Library',
        deployRemedy: 'x',
        logTarget: 'x',
      );
      expect(denied.kind, ConsoleErrorKind.permission);
      expect(denied.needsDeploy, isFalse);
    });

    test('a missing Firestore index keeps its one-click creation URL', () {
      // Losing that link turns a 30-second fix into a support ticket.
      final error = describeConsoleError(
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message:
              'The query requires an index. You can create it here: '
              'https://console.firebase.google.com/project/x/firestore/indexes?create=abc',
        ),
        subject: 'the Global Exercise Library',
        deployRemedy: 'x',
        logTarget: 'x',
      );
      expect(error.kind, ConsoleErrorKind.missingIndex);
      expect(error.url, contains('console.firebase.google.com'));
    });

    test('a server refusal is shown verbatim — it is the useful message', () {
      final error = describeConsoleError(
        FirebaseFunctionsException(
          code: 'already-exists',
          message: '"Plank" is already in the exercise catalog.',
        ),
        subject: 'the Global Exercise Library',
        deployRemedy: 'x',
        logTarget: 'x',
      );
      expect(error.kind, ConsoleErrorKind.rejected);
      expect(error.message, '"Plank" is already in the exercise catalog.');
    });
  });

  group('the import reader', () {
    late GlobalExerciseController c;

    setUp(() => c = _mount(_FakeService()));
    

    test('a CSV with name and category is read', () {
      final parsed = c.parseImportFile(
        'x.csv',
        'name,category\nBarbell Bench Press,Chest\nPlank,Core\n',
      );
      expect(parsed.error, isNull);
      expect(parsed.rows, hasLength(2));
      expect(parsed.rows.first['name'], 'Barbell Bench Press');
      expect(parsed.rows.first['category'], 'Chest');
    });

    test('a CSV with no category column is REFUSED, not half-imported', () {
      // Every row would land in no category and be invisible in every filter.
      final parsed = c.parseImportFile('x.csv', 'name\nPlank\n');
      expect(parsed.rows, isEmpty);
      expect(parsed.error, contains('category'));
    });

    test('a CSV with no name column is refused', () {
      final parsed = c.parseImportFile('x.csv', 'category\nCore\n');
      expect(parsed.rows, isEmpty);
      expect(parsed.error, contains('name'));
    });

    test('unrecognised columns are REPORTED, never dropped in silence', () {
      final parsed = c.parseImportFile(
        'x.csv',
        'name,category,sets,rest\nPlank,Core,3,60\n',
      );
      expect(parsed.error, isNull);
      expect(parsed.unmapped, containsAll(['sets', 'rest']));
    });

    test('an Excel workbook is refused with the one-click fix', () {
      final parsed = c.parseImportFile('x.xlsx', 'PK');
      expect(parsed.rows, isEmpty);
      expect(parsed.error, contains('CSV'));
    });

    test('JSON is accepted as a bare array or an {exercises: []} object', () {
      final bare = c.parseImportFile(
        'x.json',
        '[{"name":"Plank","category":"Core"}]',
      );
      expect(bare.rows, hasLength(1));

      final wrapped = c.parseImportFile(
        'x.json',
        '{"exercises":[{"name":"Plank","category":"Core"}]}',
      );
      expect(wrapped.rows, hasLength(1));
    });

    test('malformed JSON is refused rather than silently read as CSV', () {
      final parsed = c.parseImportFile('x.json', '{not json');
      expect(parsed.rows, isEmpty);
      expect(parsed.error, isNotNull);
    });
  });

  group('CSV export round-trips into the importer', () {
    test('an exported row re-imports as the same exercise', () {
      final c = _mount(_FakeService());
      final csv = c.exportCsv([
        const GlobalExerciseModel(
          id: '1',
          // A comma and a quote — the two characters that break a naive
          // exporter and split one row into two on the way back in.
          name: 'Swing, "Russian"',
          category: 'Kettlebell',
        ),
      ]);

      final parsed = c.parseImportFile('x.csv', csv);
      expect(parsed.error, isNull);
      expect(parsed.rows, hasLength(1));
      expect(parsed.rows.first['name'], 'Swing, "Russian"');
      expect(parsed.rows.first['category'], 'Kettlebell');
    });
  });

  group('a category this build does not know is never rewritten in silence', () {
    // WHY THIS EXISTS. The vocabulary is defined twice — once in TypeScript and
    // once in Dart — so a console build can be one release behind the server
    // that writes the data. When that happens the editor is handed a category
    // it cannot render. Picking the first entry of its own list is the wrong
    // answer twice over: the operator is shown "Chest" for a row that is not
    // Chest, and saving an unrelated field (a typo in the name) rewrites the
    // category to Chest with no warning and no undo. That is silent data loss
    // in the one screen whose entire job is deliberate editing.
    testWidgets('the editor SHOWS the stored category, not the first one', (
      tester,
    ) async {
      _mount(_FakeService());
      // 'Plyometrics' is deliberately one character away from the real
      // 'Plyometric' — the shape a vocabulary drift actually takes.
      const stored = GlobalExerciseModel(
        id: 'x',
        name: 'Depth Jump',
        category: 'Plyometrics',
      );

      await tester.pumpWidget(
        _host(
          ExerciseFormDialog(
            controller: Get.find<GlobalExerciseController>(),
            existing: stored,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The dropdown must be showing the row's OWN category. If this finds
      // 'Chest', the operator is looking at a value the document does not hold.
      expect(
        find.text('Plyometrics'),
        findsWidgets,
        reason: 'the stored category must be visible in the editor',
      );
      expect(
        find.text('Chest'),
        findsNothing,
        reason: 'an unknown category must not be displayed as Chest',
      );
    });
  });
}
