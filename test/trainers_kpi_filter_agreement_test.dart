import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';

// THE INACTIVE CHIP MUST SHOW THE ROWS IT COUNTS.
//
// The KPI counted `status != "active"`; the filter matched `status ==
// "inactive"` exactly. `TrainerModel` defaults a MISSING status to 'pending'
// (trainer_model.dart:93), and the producer (trainersHQ `setTrainerStatus`)
// has only ever written active/inactive — so any legacy or partially-written
// trainer document landed in the KPI and was hidden by the filter. The
// operator read "Inactive 7", clicked it, and got an empty table.
//
// Both now resolve through `TrainerController.isInactive`. This test pins the
// AGREEMENT, not either number on its own — a number is easy to keep right in
// isolation and that is exactly how these two drifted apart.

class _Harness extends TrainerController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

TrainerModel _t(String id, String? status) => TrainerModel.fromMap({
  'docId': id,
  'uid': id,
  'name': 'Trainer $id',
  'email': '$id@example.com',
  // A null status exercises the model's 'pending' default — the case that
  // actually broke, and the one an exact-match filter can never catch.
  if (status != null) 'status': status,
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
      _t('e', 'removed'), // a status the console has no chip for
    ];
  });

  test('the Inactive KPI equals what the Inactive filter returns', () {
    c.selectedStatus.value = 'inactive';
    expect(c.filteredTrainers.length, c.inactiveCount);
  });

  test('a trainer with NO status field is both counted and shown', () {
    c.selectedStatus.value = 'inactive';
    final shown = c.filteredTrainers.map((t) => t.docId).toList();
    expect(c.inactiveCount, 3); // c, d, e
    expect(shown, containsAll(<String>['c', 'd', 'e']));
  });

  test('CONTROL: Active is unaffected and still an exact match', () {
    c.selectedStatus.value = 'active';
    expect(c.filteredTrainers.length, c.activeCount);
    expect(c.filteredTrainers.every((t) => t.status == 'active'), isTrue);
  });

  test('CONTROL: All still returns everyone', () {
    c.selectedStatus.value = 'all';
    expect(c.filteredTrainers.length, c.totalCount);
  });

  test('active + inactive partitions the roster with no overlap or gap', () {
    expect(c.activeCount + c.inactiveCount, c.totalCount);
  });
}
