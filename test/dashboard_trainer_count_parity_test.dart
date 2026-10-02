// THE DASHBOARD AND THE TRAINERS SCREEN MUST COUNT THE SAME TRAINERS.
//
// Found on the emulator (2026-09-06): Dashboard "7 trainers", Trainers screen
// "6". Same nine documents. The Dashboard subtracted only `isDeleted == true`
// (the backend quota sweep's `countLive`), the Trainers screen subtracts
// `isDeleted || status == 'removed'` (`TrainerController.isRemoved`), and the
// backend itself writes BOTH signals atomically in `removeTrainer` and reads
// EITHER in its seat logic. So a document carrying only `status:'removed'`
// was a seat on one screen and a removed coach on the other.
//
// The Dashboard cannot OR two filters in one aggregate, so it uses
// inclusion–exclusion over three counts. This test replays the same fixture
// through BOTH definitions and requires them to agree — for the corrupt row,
// the clean row, and the empty set.

import 'package:alphaserena_admin_portel/controllers/dashboard_controller.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';
import 'package:flutter_test/flutter_test.dart';

TrainerModel _t(String id, {String status = 'active', bool? isDeleted}) =>
    TrainerModel.fromMap({
      'name': id,
      'status': status,
      if (isDeleted != null) 'isDeleted': isDeleted,
      'assignedBy': 'org-1',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    }, id);

/// What the Dashboard's four aggregate queries would return for [rows].
({int total, int deleted, int removed, int both}) _aggregates(
    List<TrainerModel> rows) {
  final deleted = rows.where((t) => t.isDeleted).length;
  final removed = rows.where((t) => t.status == 'removed').length;
  final both =
      rows.where((t) => t.isDeleted && t.status == 'removed').length;
  return (total: rows.length, deleted: deleted, removed: removed, both: both);
}

int _dashboardLive(List<TrainerModel> rows) {
  final a = _aggregates(rows);
  return DashboardController.liveFromCounts(a.total, a.deleted,
      removed: a.removed, both: a.both);
}

int _trainersScreenLive(List<TrainerModel> rows) =>
    rows.where((t) => !TrainerController.isRemoved(t)).length;

void main() {
  test('the emulator fixture that exposed the discrepancy now agrees', () {
    final rows = [
      for (int i = 0; i < 6; i++) _t('live-$i'),
      _t('del-0', status: 'removed', isDeleted: true),
      _t('del-1', status: 'removed', isDeleted: true),
      _t('removed-no-flag', status: 'removed'), // the corrupt row
    ];
    expect(_trainersScreenLive(rows), 6);
    expect(_dashboardLive(rows), 6, reason: 'was 7 before the fix');
  });

  test('a row with only isDeleted (no status) is also removed on both screens',
      () {
    final rows = [_t('a'), _t('half', isDeleted: true)];
    expect(_dashboardLive(rows), _trainersScreenLive(rows));
    expect(_dashboardLive(rows), 1);
  });

  test('inactive / pending / blocked coaches still occupy a seat on both', () {
    final rows = [
      _t('a', status: 'inactive'),
      _t('b', status: 'pending'),
      _t('c', status: 'blocked'),
    ];
    expect(_dashboardLive(rows), 3);
    expect(_trainersScreenLive(rows), 3);
  });

  test('clean data (both signals always together) is unchanged by the fix', () {
    final rows = [
      _t('a'),
      _t('b'),
      _t('gone', status: 'removed', isDeleted: true),
    ];
    // The two-count form (what the clients collection still uses) and the
    // four-count form agree when nothing is half-written.
    final a = _aggregates(rows);
    expect(DashboardController.liveFromCounts(a.total, a.deleted), 2);
    expect(_dashboardLive(rows), 2);
    expect(_trainersScreenLive(rows), 2);
  });

  test('arithmetic never goes negative and handles the empty set', () {
    expect(DashboardController.liveFromCounts(0, 0), 0);
    expect(DashboardController.liveFromCounts(2, 3), 0);
    expect(DashboardController.liveFromCounts(5, 2, removed: 2, both: 2), 3);
    expect(DashboardController.liveFromCounts(5, 2, removed: 2, both: 0), 1);
  });
}
