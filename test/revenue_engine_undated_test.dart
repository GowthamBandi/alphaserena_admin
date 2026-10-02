// AN UNDATED RECEIPT IS REAL MONEY WITH NO PERIOD.
//
// Live finding (emulator, 2026-09-05): a history doc with no `createdAt`
// inherited the model's `DateTime.now()` placeholder, so on EVERY snapshot it
// re-dated itself to the current instant — permanently first in "Recent
// payments" as "just now", permanently inside "This month", and counted in
// the current chart bucket for as long as the console stayed open.
//
// Contract now: it counts toward the all-time total and the per-org /
// per-plan breakdowns, toward NO period figure, sorts last, and is reported
// in `undatedCount` so a screen can disclose it.

import 'package:alphaserena_admin_portel/core/services/revenue_engine.dart';
import 'package:alphaserena_admin_portel/models/subscription_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 5, 15, 30);

  SubscriptionModel dated(String id, int amount, DateTime at) =>
      SubscriptionModel.fromMap(id, {
        'adminUid': 'org-$id',
        'planName': 'Growth',
        'amount': amount,
        'createdAt': at.toIso8601String(),
      });

  test('fromMap flags a doc with no usable date', () {
    final m = SubscriptionModel.fromMap('x', {'adminUid': 'o', 'amount': 100});
    expect(m.createdAtKnown, isFalse);
    expect(dated('y', 1, now).createdAtKnown, isTrue);
    // Any of the four accepted date keys makes it known.
    expect(
        SubscriptionModel.fromMap('z', {'amount': 1, 'paidAt': now.toIso8601String()})
            .createdAtKnown,
        isTrue);
  });

  test('fromMap: captureVerified defaults to true when the field is absent, '
      'false only when the backend said so', () {
    expect(SubscriptionModel.fromMap('a', {'amount': 1}).captureVerified, isTrue);
    expect(
        SubscriptionModel.fromMap('b', {'amount': 1, 'captureVerified': false})
            .captureVerified,
        isFalse);
    expect(
        SubscriptionModel.fromMap('c', {'amount': 1, 'captureVerified': true})
            .captureVerified,
        isTrue);
  });

  test('undated: in the total and breakdowns, in no period, sorted last', () {
    final undated = SubscriptionModel.fromMap('u', {
      'adminUid': 'org-u',
      'planName': 'Scale',
      'amount': 2999,
    });
    final r = RevenueEngine.compute([
      undated,
      dated('a', 1000, now.subtract(const Duration(hours: 1))),
      dated('b', 500, DateTime(2026, 8, 10)),
    ], now: now);

    expect(r.totalRevenue, 4499, reason: 'the money is real');
    expect(r.revenueByAdmin['org-u'], 2999);
    expect(r.revenueByPlan['Scale'], 2999);

    expect(r.todayRevenue, 1000);
    expect(r.weekRevenue, 1000);
    expect(r.monthRevenue, 1000, reason: 'not this month — no date');
    expect(r.prevMonthRevenue, 500);
    expect(r.monthlyBuckets.fold<double>(0, (s, b) => s + b.value), 1500,
        reason: 'no bucket may hold the undated amount');
    expect(r.windowRevenue, 1500);

    expect(r.paymentsByDateDesc.map((p) => p.id), ['a', 'b', 'u']);
    expect(r.undatedCount, 1);
  });

  test('a fully dated ledger reports zero undated and is unchanged', () {
    final r = RevenueEngine.compute([
      dated('a', 100, now),
      dated('b', 200, now.subtract(const Duration(days: 40))),
    ], now: now);
    expect(r.undatedCount, 0);
    expect(r.totalRevenue, 300);
    expect(r.monthRevenue, 100);
    expect(r.paymentsByDateDesc.map((p) => p.id), ['a', 'b']);
  });

  test('windowRevenue is the sum of exactly the charted months', () {
    final r = RevenueEngine.compute([
      dated('in', 100, DateTime(2026, 4, 1)), // 6th month back = in window
      dated('out', 999, DateTime(2026, 3, 31)), // 7th month back = out
    ], now: now);
    expect(r.monthlyBuckets.first.key, '2026-04');
    expect(r.windowRevenue, 100);
    expect(r.totalRevenue, 1099);
  });
}
