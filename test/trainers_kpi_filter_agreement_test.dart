import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';

// THE CHIP MUST SHOW THE ROWS IT COUNTS — AND "REMOVED" IS NOT "INACTIVE".
//
// ── DEFECT 1: the Inactive KPI promised rows the Inactive filter refused ────
// The KPI counted `status != "active"`; the filter matched `status ==
// "inactive"` exactly. `TrainerModel` defaults a MISSING status to 'pending'
// (trainer_model.dart:93), and the producer (trainersHQ `setTrainerStatus`) has
// only ever written active/inactive — so any legacy or partially-written
// trainer document landed in the KPI and was hidden by the filter. The operator
// read "Inactive 7", clicked it, and got an empty table.
//
// ── DEFECT 2 (T-2): a soft-DELETED trainer was counted as a live coach ──────
// Live in production. `trainers/SWEtTT07…` carries `status: "removed"`,
// `isDeleted: true`, `removedAt: 2026-08-18`, and its uid is ABSENT from
// `admins/kWHy….trainerIds` because `removeTrainer` arrayRemoves it
// (trainers.ts:507). The organization consumes ONE seat. The console read
// "Total 2 · Active 1 · Inactive 1" — the deleted document counted once as a
// seat and again as a coach awaiting reactivation.
//
// A deactivated coach and a deleted coach are not the same thing:
// `setTrainerStatus` refuses to touch a removed trainer at all
// (trainers.ts:399-404); only `restoreTrainer` can bring one back. Offering it
// under a filter whose implied verb is "reactivate" is a dead end.
//
// Every assertion below pins an AGREEMENT between two numbers, or between a
// number and a list — never a number on its own. A number is easy to keep right
// in isolation, and that is exactly how these drifted apart.

class _Harness extends TrainerController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

TrainerModel _t(
  String id,
  String? status, {
  bool isDeleted = false,
}) =>
    TrainerModel.fromMap({
      'docId': id,
      'uid': id,
      'name': 'Trainer $id',
      'email': '$id@example.com',
      // A null status exercises the model's 'pending' default — the case that
      // actually broke, and the one an exact-match filter can never catch.
      if (status != null) 'status': status,
      if (isDeleted) 'isDeleted': true,
    }, id);

void main() {
  late _Harness c;

  setUp(() {
    c = _Harness();
    c.trainers.value = <TrainerModel>[
      _t('a', 'active'),
      _t('b', 'active'),
      _t('c', 'inactive'),
      _t('d', null), // no status field at all -> model default 'pending'
      // The REAL production shape: both signals set together.
      _t('e', 'removed', isDeleted: true),
    ];
  });

  // ── DEFECT 1 ──────────────────────────────────────────────────────────────

  test('the Inactive KPI equals what the Inactive filter returns', () {
    c.selectedStatus.value = 'inactive';
    expect(c.filteredTrainers.length, c.inactiveCount);
  });

  test('a trainer with NO status field is both counted and shown', () {
    c.selectedStatus.value = 'inactive';
    final shown = c.filteredTrainers.map((t) => t.docId).toList();
    expect(c.inactiveCount, 2); // c, d — NOT e, which is deleted
    expect(shown, containsAll(<String>['c', 'd']));
  });

  test('CONTROL: Active is unaffected and still an exact match', () {
    c.selectedStatus.value = 'active';
    expect(c.filteredTrainers.length, c.activeCount);
    expect(c.filteredTrainers.every((t) => t.status == 'active'), isTrue);
  });

  // ── DEFECT 2 (T-2) ────────────────────────────────────────────────────────

  test('a removed trainer is NOT counted as inactive', () {
    // The exact regression: `status != "active"` swept the deleted document in.
    expect(TrainerController.isInactive(_t('x', 'removed', isDeleted: true)),
        isFalse);
    expect(c.inactiveCount, 2);
  });

  test('Total counts SEATS, not documents', () {
    // 5 documents, 1 of them deleted -> 4 seats. This is the number that must
    // agree with admins/{uid}.trainerIds.length, which excludes removed uids.
    expect(c.trainers.length, 5);
    expect(c.totalCount, 4);
  });

  test('the Removed KPI equals what the Removed filter returns', () {
    c.selectedStatus.value = 'removed';
    expect(c.filteredTrainers.length, c.removedCount);
    expect(c.removedCount, 1);
    expect(c.filteredTrainers.single.docId, 'e');
  });

  test('"All" means all SEATS — a deleted document is not silently mixed in',
      () {
    c.selectedStatus.value = 'all';
    expect(c.filteredTrainers.length, c.totalCount);
    expect(c.filteredTrainers.map((t) => t.docId), isNot(contains('e')));
  });

  test('either signal alone still counts as removed', () {
    // The two are written together today. A row carrying only one of them is a
    // corrupt document, and it must still be excluded from the seat count
    // rather than silently counted as a live coach.
    expect(TrainerController.isRemoved(_t('x', 'removed')), isTrue);
    expect(TrainerController.isRemoved(_t('y', 'inactive', isDeleted: true)),
        isTrue);
    expect(TrainerController.isRemoved(_t('z', 'active')), isFalse);
  });

  test('the model parses the production soft-delete shape', () {
    final t = TrainerModel.fromMap({
      'docId': 'SWEtTT07KxQwNeVP5N7JpHWCLTE2',
      'uid': 'SWEtTT07KxQwNeVP5N7JpHWCLTE2',
      'name': 'Priya Testcoach',
      'email': 'qa@example.com',
      'status': 'removed',
      'isDeleted': true,
      'removedAt': '2026-08-18T16:59:53.644Z',
    }, 'SWEtTT07KxQwNeVP5N7JpHWCLTE2');

    expect(t.isDeleted, isTrue);
    expect(t.removedAt, isNotNull);
    expect(TrainerController.isRemoved(t), isTrue);
  });

  test('an absent isDeleted field reads as NOT deleted', () {
    // Fail-safe direction matters: reading a missing field as `true` would
    // hide every live coach on a legacy document.
    expect(_t('legacy', 'active').isDeleted, isFalse);
  });

  // ── THE PARTITION ─────────────────────────────────────────────────────────

  test('active + inactive + removed partitions every document exactly once',
      () {
    expect(c.activeCount + c.inactiveCount, c.totalCount);
    expect(c.totalCount + c.removedCount, c.trainers.length);
  });
}
