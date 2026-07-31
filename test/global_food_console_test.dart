import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena_admin_portel/controllers/global_food_controller.dart';
import 'package:alphaserena_admin_portel/core/services/food_platform_service.dart';
import 'package:alphaserena_admin_portel/core/utils/food_errors.dart';
import 'package:alphaserena_admin_portel/models/global_food_model.dart';
import 'package:alphaserena_admin_portel/widgets/food/food_analytics_panel.dart';
import 'package:alphaserena_admin_portel/widgets/food/food_list_panel.dart';

// ════════════════════════════════════════════════════════════════════════
// GLOBAL FOOD CONSOLE — the states, PROVEN.
//
// These exist because the console shipped a certification claiming its
// loading, empty and error states worked, and the very first screen a human
// opened said "Could not load this view." Nothing had ever mounted the
// console; every state was asserted by reading the code.
//
// The failure was real and reproducible: all 17 food Cloud Functions were
// absent from the project. The console's job in that situation is not to
// succeed — it is to say precisely what is missing, and to keep working
// wherever it still can. That is what most of these tests pin.
// ════════════════════════════════════════════════════════════════════════

/// A service that never touches Firebase. Every method used is overridden.
class _FakeService extends FoodPlatformService {
  _FakeService({
    this.pages = const [],
    this.analyticsResult,
    this.throwOnAnalytics,
    this.throwOnPage,
    this.throwOnLoadMore,
  });

  /// Successive pages returned by [fetchGlobalFoods].
  final List<FoodPage> pages;
  final FoodAnalytics? analyticsResult;
  final Object? throwOnAnalytics;
  final Object? throwOnPage;
  final Object? throwOnLoadMore;

  int pageCalls = 0;
  final List<FoodQuery> queries = [];

  @override
  Future<FoodPage> fetchGlobalFoods({
    FoodQuery query = const FoodQuery(),
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FoodPlatformService.pageSize,
  }) async {
    queries.add(query);
    final isFirstCall = pageCalls == 0;
    if (isFirstCall && throwOnPage != null) throw throwOnPage!;
    if (!isFirstCall && throwOnLoadMore != null) throw throwOnLoadMore!;
    final page = pageCalls < pages.length ? pages[pageCalls] : const FoodPage();
    pageCalls++;
    return page;
  }

  @override
  Future<FoodAnalytics> analytics() async {
    if (throwOnAnalytics != null) throw throwOnAnalytics!;
    return analyticsResult ?? const FoodAnalytics();
  }

  @override
  Future<({Map<String, int> counts, int uncategorised})>
  categoryCounts() async => (counts: <String, int>{}, uncategorised: 0);

  @override
  Stream<List<FoodCategoryModel>> watchCategories() =>
      Stream.value(const <FoodCategoryModel>[]);

  @override
  Future<List<GlobalFoodModel>> fetchFoodsByIds(List<String> ids) async =>
      const [];

  @override
  Future<({String id, int revision, List<String> warnings})> upsertFood(
    GlobalFoodModel food, {
    bool allowEnergyMismatch = false,
    String? verification,
    String? status,
    String reason = '',
  }) async => (id: 'saved-1', revision: 1, warnings: const <String>[]);
}

GlobalFoodModel food(String id, String name, {String status = 'published'}) =>
    GlobalFoodModel(
      id: id,
      name: name,
      scope: 'global',
      status: status,
      calories: 379,
      protein: 13.2,
      carbs: 67.7,
      fat: 6.5,
      baseGrams: 100,
    );

/// The exact exception a missing Cloud Function raises.
final _notDeployed = FirebaseFunctionsException(
  code: 'not-found',
  message: 'NOT_FOUND',
);

/// The exact exception a missing composite index raises, including the
/// one-click creation link Firestore embeds in it.
final _missingIndex = FirebaseException(
  plugin: 'cloud_firestore',
  code: 'failed-precondition',
  message:
      'The query requires an index. You can create it here: '
      'https://console.firebase.google.com/v1/r/project/demo/firestore/'
      'indexes?create_composite=Xyz',
);

/// Registers the controller the way production does.
///
/// GetX calls `onInit` on REGISTRATION, not on construction — a directly
/// constructed controller never loads anything. Going through Get.put means
/// these tests exercise the same lifecycle the console does.
GlobalFoodController controllerWith(FoodPlatformService service) =>
    Get.put(GlobalFoodController(service: service));

/// Lets the controller's constructor-time futures settle in a plain unit test.
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Renders at a given console size.
///
/// The default is a normal desktop; the 1000px case is a 13" laptop once the
/// console's 260px sidebar is subtracted, which is exactly where the toolbar
/// overflow was found.
Future<void> pumpAt(
  WidgetTester t,
  Widget child, {
  Size size = const Size(1440, 900),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await t.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  // ── The failure that was actually reported ─────────────────────────

  group('the failure that was actually reported', () {
    test('a missing Cloud Function is classified as NOT DEPLOYED', () {
      final e = describeFoodError(
        _notDeployed,
        operation: 'getFoodLibraryAnalytics',
      );
      expect(e.kind, FoodErrorKind.notDeployed);
      expect(e.needsDeploy, isTrue);
      // Retry is refused: a missing function will not appear by itself, and
      // offering "Try again" is what made the real failure undiagnosable.
      expect(e.isRetryable, isFalse);
      expect(e.message, contains('getFoodLibraryAnalytics'));
      expect(e.message, contains('not deployed'));
      // The remedy must be SCOPED: a blanket `--only functions` would ship
      // unrelated uncommitted backend work to a live project.
      expect(e.remedy, contains('deploy_food_platform'));
      expect(e.remedy, isNot(contains('--only functions,')));
    });

    testWidgets('the dashboard NAMES the missing function on screen', (t) async {
      final c = controllerWith(_FakeService(throwOnAnalytics: _notDeployed));
      await pumpAt(
        t,
        FoodAnalyticsPanel(
          controller: c,
          onDrillDown: (_) {},
          onOpenFood: (_) {},
        ),
      );

      expect(find.text('Backend not deployed'), findsOneWidget);
      expect(find.textContaining('getFoodLibraryAnalytics'), findsOneWidget);
      expect(find.textContaining('deploy_food_platform'), findsOneWidget);
      // And it must not imply the whole library is gone.
      expect(find.textContaining('Foods tab'), findsOneWidget);
    });

    testWidgets('a missing index shows the one-click creation link', (t) async {
      final c = controllerWith(_FakeService(throwOnPage: _missingIndex));
      await pumpAt(
        t,
        FoodListPanel(controller: c, onOpen: (_) {}, onCreate: () {}),
      );

      expect(find.text('A Firestore index is missing'), findsOneWidget);
      expect(
        find.textContaining('create_composite=Xyz'),
        findsOneWidget,
        reason: 'losing the link turns a 30-second fix into a support ticket',
      );
    });

    test('permission and offline are distinguished, not lumped together', () {
      expect(
        describeFoodError(
          FirebaseFunctionsException(code: 'permission-denied', message: 'x'),
        ).kind,
        FoodErrorKind.permission,
      );
      final offline = describeFoodError(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      expect(offline.kind, FoodErrorKind.offline);
      // Offline is the one case where retrying genuinely helps.
      expect(offline.isRetryable, isTrue);
    });
  });

  // ── Layout ─────────────────────────────────────────────────────────

  group('layout survives a real window', () {
    testWidgets('the foods list does not overflow on a SMALL desktop', (t) async {
      // The regression this guards: the toolbar was a fixed Row and overflowed
      // by 255px here. Nothing in `flutter analyze` could see it.
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'Rolled Oats')]),
          ],
        ),
      );
      await pumpAt(
        t,
        FoodListPanel(controller: c, onOpen: (_) {}, onCreate: () {}),
        size: const Size(1000, 800),
      );
      expect(
        t.takeException(),
        isNull,
        reason: 'a layout overflow is recorded as a framework exception',
      );
    });

    testWidgets('the foods list does not overflow at tablet width', (t) async {
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'Rolled Oats')]),
          ],
        ),
      );
      await pumpAt(
        t,
        FoodListPanel(controller: c, onOpen: (_) {}, onCreate: () {}),
        size: const Size(760, 1024),
      );
      expect(
        t.takeException(),
        isNull,
        reason: 'a layout overflow is recorded as a framework exception',
      );
    });

    testWidgets('the bulk bar does not overflow with a selection', (t) async {
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'A'), food('b', 'B')]),
          ],
        ),
      );
      await pumpAt(
        t,
        FoodListPanel(controller: c, onOpen: (_) {}, onCreate: () {}),
        size: const Size(1000, 800),
      );
      c.selectAllLoaded();
      await t.pumpAndSettle();
      expect(
        t.takeException(),
        isNull,
        reason: 'a layout overflow is recorded as a framework exception',
      );
    });

    testWidgets('the dashboard does not overflow on a small desktop', (t) async {
      final c = controllerWith(
        _FakeService(
          analyticsResult: const FoodAnalytics(total: 120, published: 100),
        ),
      );
      await pumpAt(
        t,
        FoodAnalyticsPanel(
          controller: c,
          onDrillDown: (_) {},
          onOpenFood: (_) {},
        ),
        size: const Size(1000, 800),
      );
      expect(
        t.takeException(),
        isNull,
        reason: 'a layout overflow is recorded as a framework exception',
      );
    });
  });

  // ── List states ────────────────────────────────────────────────────

  group('the foods list', () {
    testWidgets('ZERO records shows the founding empty state, not an error', (
      t,
    ) async {
      final c = controllerWith(_FakeService());
      await pumpAt(
        t,
        FoodListPanel(controller: c, onOpen: (_) {}, onCreate: () {}),
      );

      expect(find.text('The global library is empty'), findsOneWidget);
      expect(find.text('Create the first food'), findsOneWidget);
    });

    testWidgets('ONE record renders and reports the end of results', (t) async {
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'Rolled Oats')]),
          ],
        ),
      );
      await pumpAt(
        t,
        FoodListPanel(controller: c, onOpen: (_) {}, onCreate: () {}),
      );

      expect(find.text('Rolled Oats'), findsOneWidget);
      expect(find.textContaining('End of results'), findsOneWidget);
    });

    test('a FULL page offers more, and appends the next one', () async {
      final first = List.generate(50, (i) => food('a$i', 'Food $i'));
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: first, hasMore: true),
            FoodPage(foods: [food('b', 'Second Page Food')]),
          ],
        ),
      );
      await settle();
      expect(c.foods.length, 50);
      expect(c.hasMore.value, isTrue);

      await c.loadMore();
      expect(c.foods.length, 51);
      expect(c.hasMore.value, isFalse);
    });

    testWidgets(
      'a failed NEXT page keeps the rows already loaded and offers retry',
      (t) async {
        final first = List.generate(50, (i) => food('a$i', 'Food $i'));
        final c = controllerWith(
          _FakeService(
            pages: [FoodPage(foods: first, hasMore: true)],
            throwOnLoadMore: FirebaseException(
              plugin: 'cloud_firestore',
              code: 'unavailable',
            ),
          ),
        );
        await pumpAt(
          t,
          FoodListPanel(controller: c, onOpen: (_) {}, onCreate: () {}),
        );

        await c.loadMore();
        await t.pumpAndSettle();

        // The regression this guards: discarding 50 loaded rows because page 2
        // failed is a worse outcome than the failure itself.
        expect(c.foods.length, 50, reason: 'loaded rows must survive');
        expect(c.error.value, isNull, reason: 'page 1 did not fail');
        expect(c.loadMoreError.value, isNotNull);
      },
    );

    testWidgets('a filtered empty result is NOT the empty-library state', (
      t,
    ) async {
      final c = controllerWith(_FakeService());
      await pumpAt(
        t,
        FoodListPanel(controller: c, onOpen: (_) {}, onCreate: () {}),
      );

      c.setQuery(const FoodQuery(status: FoodStatusFilter.draft));
      await t.pumpAndSettle();

      expect(find.text('No foods match these filters'), findsOneWidget);
      expect(find.text('The global library is empty'), findsNothing);
    });
  });

  // ── Query behaviour ────────────────────────────────────────────────

  group('filters and sorting reach the server', () {
    test('every filter is sent as a query, never applied in memory', () async {
      final fake = _FakeService();
      final c = controllerWith(fake);
      await settle();

      c.setQuery(
        const FoodQuery(
          status: FoodStatusFilter.archived,
          categoryId: 'cat-1',
          verification: 'official',
          source: 'seed',
          sort: FoodSort.caloriesDesc,
        ),
      );
      await settle();

      final last = fake.queries.last;
      expect(last.status, FoodStatusFilter.archived);
      expect(last.categoryId, 'cat-1');
      expect(last.verification, 'official');
      expect(last.source, 'seed');
      expect(last.sort, FoodSort.caloriesDesc);
    });

    test('a drill-down clears a stale search box', () async {
      final c = controllerWith(_FakeService());
      await settle();
      c.searchText.value = 'oats';

      c.setQuery(const FoodQuery(status: FoodStatusFilter.draft));
      await settle();

      // Otherwise the box shows a term the list is not filtered by.
      expect(c.searchText.value, '');
    });

    test('a new query resets pagination rather than reusing a cursor', () async {
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'A')], hasMore: true),
            FoodPage(foods: [food('b', 'B')], hasMore: true),
            FoodPage(foods: [food('c', 'C')]),
          ],
        ),
      );
      await settle();
      await c.loadMore();
      expect(c.foods.length, 2);

      c.setQuery(const FoodQuery(status: FoodStatusFilter.all));
      await settle();

      expect(c.foods.length, 1, reason: 'a new query starts from page one');
      expect(c.loadMoreError.value, isNull);
    });
  });

  // ── Selection ──────────────────────────────────────────────────────

  group('bulk selection', () {
    test('a selection cannot survive into rows the operator cannot see', () async {
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'A'), food('b', 'B')]),
            const FoodPage(),
          ],
        ),
      );
      await settle();

      c.toggleSelected('a');
      c.toggleSelected('b');
      expect(c.selected.length, 2);

      // Filtering away the selected rows must drop them: acting on a hidden
      // selection is how a curator archives foods they never looked at.
      c.setQuery(const FoodQuery(status: FoodStatusFilter.archived));
      await settle();
      expect(c.selected, isEmpty);
    });

    test('select-all covers exactly what is loaded', () async {
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'A'), food('b', 'B')]),
          ],
        ),
      );
      await settle();
      c.selectAllLoaded();
      expect(c.selected, {'a', 'b'});
      c.clearSelection();
      expect(c.hasSelection, isFalse);
    });
  });

  // ── Dashboard degradation ──────────────────────────────────────────

  group('the dashboard degrades instead of blanking', () {
    test('a dead analytics callable does not stop the list loading', () async {
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'Rolled Oats')]),
          ],
          throwOnAnalytics: _notDeployed,
        ),
      );
      await settle();

      expect(c.analytics.value, isNull);
      expect(c.analyticsError.value?.kind, FoodErrorKind.notDeployed);
      // The library itself is fine, and the console must keep working.
      expect(c.foods.length, 1);
      expect(c.error.value, isNull);
    });

    testWidgets('an EMPTY library renders a dashboard, not an error', (t) async {
      final c = controllerWith(
        _FakeService(analyticsResult: const FoodAnalytics()),
      );
      await pumpAt(
        t,
        FoodAnalyticsPanel(
          controller: c,
          onDrillDown: (_) {},
          onOpenFood: (_) {},
        ),
      );

      expect(find.text('Total foods'), findsOneWidget);
      expect(find.text('Backend not deployed'), findsNothing);
      // Zero foods means zero work, and the console should say so plainly.
      expect(find.textContaining('Nothing to review'), findsOneWidget);
    });

    testWidgets('every headline counter is a drill-down, not decoration', (
      t,
    ) async {
      FoodQuery? drilled;
      final c = controllerWith(
        _FakeService(
          analyticsResult: const FoodAnalytics(total: 10, draft: 3),
        ),
      );
      await pumpAt(
        t,
        FoodAnalyticsPanel(
          controller: c,
          onDrillDown: (q) => drilled = q,
          onOpenFood: (_) {},
        ),
      );

      await t.tap(find.text('Drafts').first);
      await t.pumpAndSettle();
      expect(drilled?.status, FoodStatusFilter.draft);
    });
  });

  // ── The dashboard must not overstate what it knows ─────────────────

  group('the dashboard reports floors as floors', () {
    testWidgets('a capped queue count renders as N+, never as a total', (
      t,
    ) async {
      final c = controllerWith(
        _FakeService(
          analyticsResult: const FoodAnalytics(
            total: 5000,
            missingDataTotal: 25,
            // The queue is capped, so 25 is a FLOOR discovered in a sample.
            missingDataTruncated: true,
            missingData: [(id: 'a', name: 'Thin Food', gaps: ['macros'])],
          ),
        ),
      );
      await pumpAt(
        t,
        FoodAnalyticsPanel(
          controller: c,
          onDrillDown: (_) {},
          onOpenFood: (_) {},
        ),
      );

      expect(find.text('25+'), findsOneWidget);
      expect(find.text('25'), findsNothing);
    });

    testWidgets('an exact count renders bare, with no misleading plus', (
      t,
    ) async {
      final c = controllerWith(
        _FakeService(
          analyticsResult: const FoodAnalytics(
            total: 40,
            draft: 7,
            missingDataTotal: 3,
            missingData: [(id: 'a', name: 'Thin', gaps: ['macros'])],
          ),
        ),
      );
      await pumpAt(
        t,
        FoodAnalyticsPanel(
          controller: c,
          onDrillDown: (_) {},
          onOpenFood: (_) {},
        ),
      );

      expect(find.text('3'), findsWidgets);
      expect(find.text('3+'), findsNothing);
    });

    test('the review queue counts drafts only, never draft + unverified', () {
      // The regression this guards: a draft is almost always ALSO unverified,
      // so summing the two double-counted every draft and inflated the badge.
      const a = FoodAnalytics(total: 10, draft: 4, unverifiedTotal: 6);
      expect(a.awaitingReviewTotal, isNot(a.draft + a.unverifiedTotal));
    });
  });

  _d5();
  _d5RootCause();

  // ── Lifecycle ──────────────────────────────────────────────────────

  group('lifecycle', () {
    test('a late page cannot overwrite a newer query', () async {
      // Guards the classic list race: query A is slow, query B returns first,
      // then A lands and silently replaces B's results.
      final c = controllerWith(
        _FakeService(
          pages: [
            FoodPage(foods: [food('a', 'Old')]),
            FoodPage(foods: [food('b', 'New')]),
          ],
        ),
      );
      await settle();

      final stale = c.refreshList();
      c.setQuery(const FoodQuery(status: FoodStatusFilter.all));
      await stale;
      await settle();

      expect(c.foods.length, lessThanOrEqualTo(1));
    });

    test('closing the controller mid-debounce does not fire a search', () async {
      final fake = _FakeService();
      final c = controllerWith(fake);
      await settle();
      final before = fake.pageCalls;

      c.onSearchChanged('oa');
      c.onClose();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(fake.pageCalls, before, reason: 'the debounce must be cancelled');
    });
  });
}

// ── D5: a committed write must never be reported as a failure ────────────
//
// Found live: the food was created (visible in the list, rev 1, correct data)
// but the wizard reported failure and trapped the operator, because the
// snackbar/refresh that runs AFTER the write threw inside the same try block.

class _SaveThenBreakService extends FoodPlatformService {
  int upserts = 0;

  @override
  Future<({String id, int revision, List<String> warnings})> upsertFood(
    GlobalFoodModel food, {
    bool allowEnergyMismatch = false,
    String? verification,
    String? status,
    String reason = '',
  }) async {
    upserts++;
    return (id: 'created-1', revision: 1, warnings: const <String>[]);
  }

  // The write succeeded; the refresh that follows it does not.
  @override
  Future<FoodPage> fetchGlobalFoods({
    FoodQuery query = const FoodQuery(),
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FoodPlatformService.pageSize,
  }) async => throw StateError('refresh exploded');

  @override
  Future<FoodAnalytics> analytics() async => const FoodAnalytics();

  @override
  Future<({Map<String, int> counts, int uncategorised})>
  categoryCounts() async => (counts: <String, int>{}, uncategorised: 0);

  @override
  Stream<List<FoodCategoryModel>> watchCategories() =>
      Stream.value(const <FoodCategoryModel>[]);
}

void _d5() {
  testWidgets(
    'a save that COMMITTED reports success even if the refresh fails',
    (t) async {
      final fake = _SaveThenBreakService();
      final c = Get.put(GlobalFoodController(service: fake));
      // A real Get context, so the post-write snackbar takes its production
      // path rather than failing for want of an app.
      await t.pumpWidget(const GetMaterialApp(home: Scaffold()));
      await t.pump();

      final ok = await c.saveFood(
        food('x', 'Chicken Breast'),
        status: 'published',
      );
      await t.pump();

      expect(fake.upserts, 1);
      expect(
        ok,
        isTrue,
        reason:
            'the server accepted the write; a failed toast or list refresh '
            'must not send the operator back to repeat it',
      );
      // And the failure that followed the write must not be reported as a
      // failed save anywhere else either.
      expect(c.isSaving.value, isFalse);

      // Let the real snackbar finish its entry/exit animation so its ticker is
      // disposed before teardown — otherwise the harness reports a leak that
      // has nothing to do with the behaviour under test.
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
    },
  );
}

// ── D5 root cause: a GetX snackbar is a ROUTE ────────────────────────────
//
// Found live. The save committed, the food appeared in the list, saveFood
// returned true, and Get.back() still did not close the wizard — because the
// success toast had already been pushed as a route, so the pop landed on the
// toast instead of the dialog. The toast must therefore never be pushed before
// the caller has had its chance to close.

void _d5RootCause() {
  testWidgets('a successful save returns BEFORE the toast is pushed', (t) async {
    final fake = _FakeService(
      pages: [
        FoodPage(foods: [food('a', 'Rolled Oats')]),
      ],
    );
    final c = Get.put(GlobalFoodController(service: fake));
    await t.pumpWidget(const GetMaterialApp(home: Scaffold()));
    await t.pump();

    var snackbarVisibleAtReturn = false;
    final ok = await c.saveFood(food('x', 'Rolled Oats'), status: 'draft');
    // At the moment saveFood returns, no snackbar route may exist yet —
    // otherwise the caller's pop would dismiss it instead of the dialog.
    snackbarVisibleAtReturn = Get.isSnackbarOpen;

    expect(ok, isTrue);
    expect(
      snackbarVisibleAtReturn,
      isFalse,
      reason:
          'the toast is a route; pushing it before the caller pops means the '
          'pop closes the toast and the wizard stays open',
    );

    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
  });
}
