import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena_admin_portel/controllers/global_exercise_controller.dart';
import 'package:alphaserena_admin_portel/core/services/exercise_catalog_service.dart';
import 'package:alphaserena_admin_portel/models/global_exercise_model.dart';
import 'package:alphaserena_admin_portel/widgets/exercise/exercise_form_dialog.dart';

// ════════════════════════════════════════════════════════════════════════
// EDITING AN EXERCISE MUST NOT DESTROY THE FIELDS THE FORM DOES NOT SHOW.
//
// `upsertGlobalExercise` builds its document from the WHOLE validated payload
// and writes it with `ref.update({...doc})`. A field the payload omits is not
// left alone — `validateExercise` defaults it ('' / [] / 0) and the update
// writes that default over the stored value.
//
// This dialog edits six fields. It used to construct a fresh model and send
// only those, silently destroying the other nine: instructions, primaryMuscles,
// secondaryMuscles, difficulty, mechanics, force, tips, thumbnailUrl,
// videoProvider and videoDurationSec.
//
// Those are precisely the fields AlphaSerena hydrates onto a member's workout
// (backend buildWorkout → exerciseMediaFor). So a super admin fixing a TYPO in
// an exercise name wiped the demo thumbnail and the coaching cues for every
// member already training on that exercise, across every organization, with no
// warning and nothing on screen to show it had happened.
//
// Identical defect and identical remedy to TrainerHQ's updateEmploymentRecord:
// round-trip what you do not own. Removing a CONTROL is not deleting a CONCEPT.
// ════════════════════════════════════════════════════════════════════════

class _CapturingService extends ExerciseCatalogService {
  GlobalExerciseModel? sent;

  @override
  Future<ExercisePage> fetchExercises({
    ExerciseQuery query = const ExerciseQuery(),
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = ExerciseCatalogService.pageSize,
  }) async => const ExercisePage();

  @override
  Future<ExerciseAnalytics> analytics() async => const ExerciseAnalytics();

  @override
  Future<({String id, int revision, List<String> warnings})> upsert(
    GlobalExerciseModel exercise, {
    bool? isActive,
  }) async {
    sent = exercise;
    return (id: exercise.id, revision: 2, warnings: const <String>[]);
  }
}

/// A fully-populated catalog row — every field the member app hydrates is set,
/// so anything the edit drops shows up as a difference.
GlobalExerciseModel richRow() => GlobalExerciseModel(
  id: 'cat_1',
  name: 'Zercher Squat',
  category: 'Legs',
  videoUrl: 'https://cdn/zercher.mp4',
  aliases: const ['Front Squat Variant'],
  equipment: 'Barbell',
  isActive: true,
  source: 'manual',
  sourceRef: 'ref-1',
  primaryMuscles: const ['Quads'],
  secondaryMuscles: const ['Glutes', 'Core'],
  difficulty: 'advanced',
  mechanics: 'compound',
  force: 'push',
  instructions: 'Hold the bar in the crook of the elbows and squat.',
  tips: const ['Keep the elbows high', 'Brace hard'],
  thumbnailUrl: 'https://cdn/zercher.jpg',
  videoProvider: 'mux',
  videoDurationSec: 42,
);

void main() {
  late _CapturingService service;

  setUp(() {
    Get.testMode = true;
    service = _CapturingService();
  });
  tearDown(Get.reset);

  Future<void> openEditAndSave(WidgetTester t, {String? rename}) async {
    await t.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final c = Get.put(GlobalExerciseController(service: service));
    await t.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: ExerciseFormDialog(controller: c, existing: richRow()),
        ),
      ),
    );
    await t.pumpAndSettle();

    if (rename != null) {
      final nameField = find.byType(TextFormField).first;
      await t.enterText(nameField, rename);
      await t.pumpAndSettle();
    }

    final save = find.text('Save changes');
    await t.tap(save.first, warnIfMissed: false);
    // NOT pumpAndSettle: a successful save raises a GetX snackbar, whose
    // dismissal timer never settles inside the test's fake clock. Pump past it
    // instead, so the timer fires and teardown is clean.
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(seconds: 5));
  }

  testWidgets('a plain re-save preserves every field the form cannot edit', (
    t,
  ) async {
    await openEditAndSave(t);

    final sent = service.sent;
    expect(sent, isNotNull, reason: 'the dialog never reached the service');

    final original = richRow();
    // The nine fields with no control on this form.
    expect(sent!.instructions, original.instructions);
    expect(sent.primaryMuscles, original.primaryMuscles);
    expect(sent.secondaryMuscles, original.secondaryMuscles);
    expect(sent.difficulty, original.difficulty);
    expect(sent.mechanics, original.mechanics);
    expect(sent.force, original.force);
    expect(sent.tips, original.tips);
    expect(sent.thumbnailUrl, original.thumbnailUrl);
    expect(sent.videoProvider, original.videoProvider);
    expect(sent.videoDurationSec, original.videoDurationSec);
  });

  testWidgets('RENAMING an exercise does not strip its coaching content', (
    t,
  ) async {
    // The reported shape of the bug: the operator only fixes a typo.
    await openEditAndSave(t, rename: 'Zercher Squat (Barbell)');

    final sent = service.sent;
    expect(sent, isNotNull);
    expect(sent!.name, 'Zercher Squat (Barbell)', reason: 'the edit must apply');
    expect(
      sent.instructions,
      richRow().instructions,
      reason: 'renaming must not wipe the cues every member reads mid-workout',
    );
    expect(
      sent.thumbnailUrl,
      richRow().thumbnailUrl,
      reason: 'renaming must not wipe the demo thumbnail',
    );
    expect(sent.videoDurationSec, 42);
  });

  testWidgets('the payload actually carries them to the callable', (t) async {
    await openEditAndSave(t);

    // toCallablePayload is what upsertGlobalExercise validates, so a field the
    // model keeps but the payload drops would still be destroyed server-side.
    final payload = service.sent!.toCallablePayload();
    expect(payload['instructions'], richRow().instructions);
    expect(payload['primaryMuscles'], richRow().primaryMuscles);
    // LOWERCASE is the wire value. `pickEnum` on the server lowercases
    // whatever it is given, so 'Advanced' and 'advanced' both STORE as
    // 'advanced'; the form now resolves to the stored vocabulary up front so
    // the control shows the value that will actually be persisted rather than
    // a display-cased string that only looks preserved.
    expect(payload['difficulty'], 'advanced');
    expect(payload['thumbnailUrl'], richRow().thumbnailUrl);
    expect(payload['videoDurationSec'], 42);
  });
}
