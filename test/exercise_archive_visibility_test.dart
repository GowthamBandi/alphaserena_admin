import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena_admin_portel/controllers/global_exercise_controller.dart';
import 'package:alphaserena_admin_portel/core/services/exercise_catalog_service.dart';
import 'package:alphaserena_admin_portel/models/global_exercise_model.dart';
import 'package:alphaserena_admin_portel/widgets/exercise/exercise_chrome.dart';
import 'package:alphaserena_admin_portel/widgets/exercise/exercise_list_panel.dart';

// ════════════════════════════════════════════════════════════════════════
// THE CONSOLE MUST BE ABLE TO SEE AN ARCHIVED EXERCISE.
//
// Archiving writes BOTH `isArchived: true` and `isActive: false`. The console
// modelled only the second, so a withdrawn exercise rendered exactly like a
// deactivated one — "Inactive" — and the founder had no way to tell a movement
// they had retired for the season from one they had withdrawn entirely.
//
// That difference is not cosmetic. `isArchived` is the flag TrainerHQ reads
// FIRST (`_parseStatus`), so it is the one that decides whether any coach on the
// platform can find the exercise at all. And coming back from it is an
// UN-archive, which the row menu offered under the word "Activate" while ALSO
// offering "Archive" — a control on an already-archived row that could only
// ever report "nothing changed".
// ════════════════════════════════════════════════════════════════════════

class _FakeService extends ExerciseCatalogService {
  _FakeService(this.rows);

  final List<GlobalExerciseModel> rows;

  @override
  Future<ExercisePage> fetchExercises({
    ExerciseQuery query = const ExerciseQuery(),
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = ExerciseCatalogService.pageSize,
  }) async => ExercisePage(exercises: rows);

  @override
  Future<ExerciseAnalytics> analytics() async => const ExerciseAnalytics();
}

GlobalExerciseModel _row(
  String name, {
  bool isActive = true,
  bool isArchived = false,
}) => GlobalExerciseModel(
  id: name,
  name: name,
  category: 'Chest',
  isActive: isActive,
  isArchived: isArchived,
);

Widget _host(Widget child) => GetMaterialApp(
  home: Scaffold(body: SizedBox(width: 1200, height: 800, child: child)),
);

Future<void> _pump(WidgetTester tester, List<GlobalExerciseModel> rows) async {
  // Through Get.put, because GetX calls `onInit` — and therefore the first
  // page load — on REGISTRATION, not on construction.
  final c = Get.put(GlobalExerciseController(service: _FakeService(rows)));
  await tester.pumpWidget(
    _host(ExerciseListPanel(controller: c, onEdit: (_) {}, onCreate: () {})),
  );
  await tester.pumpAndSettle();
}

/// Scoped to the ROW PILL, never the whole screen.
///
/// The filter bar renders chips reading "Active" and "Inactive" too, so a bare
/// `find.text('Inactive')` matches the control that FILTERS the list as
/// readily as the badge that DESCRIBES a row — and would pass while the badge
/// said nothing at all. `find.text` matches data, not pixels.
Finder _pillText(String label) => find.descendant(
  of: find.byType(ExerciseActivePill),
  matching: find.text(label),
);

void main() {
  tearDown(Get.reset);

  testWidgets('an ARCHIVED row says so — it does not hide behind "Inactive"', (
    tester,
  ) async {
    await _pump(tester, [
      _row('Withdrawn Press', isActive: false, isArchived: true),
    ]);

    expect(
      _pillText('Archived'),
      findsOneWidget,
      reason: 'the founder must be able to see which rows are withdrawn',
    );
    expect(
      _pillText('Inactive'),
      findsNothing,
      reason: 'archived is the stronger statement and must win the label',
    );
  });

  testWidgets('DEACTIVATED and ARCHIVED are told apart on the same list', (
    tester,
  ) async {
    await _pump(tester, [
      _row('Live Press'),
      _row('Rested Press', isActive: false),
      _row('Withdrawn Press', isActive: false, isArchived: true),
    ]);

    // Three rows, three different states, three different words. Before this
    // the last two were indistinguishable.
    expect(_pillText('Active'), findsOneWidget);
    expect(_pillText('Inactive'), findsOneWidget);
    expect(_pillText('Archived'), findsOneWidget);
  });

  testWidgets('the archived row offers RESTORE, and does not offer Archive', (
    tester,
  ) async {
    await _pump(tester, [
      _row('Withdrawn Press', isActive: false, isArchived: true),
    ]);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(
      find.text('Restore'),
      findsOneWidget,
      reason: 'coming back from archived is an un-archive, not an activation',
    );
    expect(find.text('Activate'), findsNothing);
    expect(
      find.text('Archive'),
      findsNothing,
      reason: 'archiving an archived row is a control that can only no-op',
    );
  });

  testWidgets('a merely DEACTIVATED row still offers Activate and Archive', (
    tester,
  ) async {
    await _pump(tester, [_row('Rested Press', isActive: false)]);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Activate'), findsOneWidget);
    expect(find.text('Restore'), findsNothing);
    expect(
      find.text('Archive'),
      findsOneWidget,
      reason: 'a deactivated row has not been withdrawn yet',
    );
  });

  testWidgets('an ACTIVE row offers Deactivate and Archive', (tester) async {
    await _pump(tester, [_row('Live Press')]);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Deactivate'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
  });

  test('the model reads the flag the server actually writes', () {
    // `deleteGlobalExercise` writes {isArchived: true, isActive: false}.
    final archived = GlobalExerciseModel.fromMap(
      {'name': 'X', 'isArchived': true, 'isActive': false},
      'x',
    );
    expect(archived.isArchived, isTrue);
    expect(archived.isActive, isFalse);

    // Absent means live — every row written before archiving existed.
    final legacy = GlobalExerciseModel.fromMap({'name': 'X'}, 'x');
    expect(legacy.isArchived, isFalse);
    expect(legacy.isActive, isTrue);
  });
}
