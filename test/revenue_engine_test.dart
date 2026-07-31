// test/revenue_engine_test.dart
//
// Unit tests for the shared RevenueEngine — the single source of revenue
// math for PaymentsController and DashboardController. Every case uses a
// fixed `now` so results are deterministic.

import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena_admin_portel/core/services/revenue_engine.dart';
import 'package:alphaserena_admin_portel/models/subscription_model.dart';

// Fixed clock: Wednesday 22 July 2026, midday.
final DateTime now = DateTime(2026, 7, 22, 12, 0);

SubscriptionModel payment({
  String id = 'doc1',
  String adminUid = 'org_a',
  String plan = 'Gold',
  int amountPaid = 1000,
  double refundAmount = 0,
  DateTime? createdAt,
}) {
  return SubscriptionModel(
    id: id,
    adminUid: adminUid,
    adminDocId: adminUid,
    planName: plan,
    durationMonths: 1,
    amountPaid: amountPaid,
    originalAmount: amountPaid,
    couponApplied: false,
    discountAmount: 0,
    paymentId: 'pay_$id',
    razorpayPaymentId: 'pay_$id',
    startAt: createdAt ?? now,
    expiryAt: (createdAt ?? now).add(const Duration(days: 30)),
    createdAt: createdAt ?? now,
    refundAmount: refundAmount,
    maxAdmins: 1,
    maxTrainers: 1,
    maxClients: 1,
    maxWorkoutPlans: 1,
    maxWorkouts: 1,
    maxDietPlans: 1,
  );
}

void main() {
  group('refund netting', () {
    test('partial refund nets against revenue everywhere', () {
      final r = RevenueEngine.compute([
        payment(amountPaid: 1000, refundAmount: 300, createdAt: now),
      ], now: now);

      expect(r.totalRevenue, 700);
      expect(r.todayRevenue, 700);
      expect(r.weekRevenue, 700);
      expect(r.monthRevenue, 700);
      expect(r.revenueByPlan['Gold'], 700);
      expect(r.revenueByAdmin['org_a'], 700);
    });

    test('full refund contributes zero, never negative', () {
      final r = RevenueEngine.compute([
        payment(amountPaid: 1000, refundAmount: 1000, createdAt: now),
        // Over-refund (should be impossible, but must clamp at 0).
        payment(id: 'doc2', amountPaid: 500, refundAmount: 900, createdAt: now),
        payment(id: 'doc3', amountPaid: 200, createdAt: now),
      ], now: now);

      expect(r.totalRevenue, 200);
      expect(r.totalTransactions, 3); // refunded payments still count
    });
  });

  group('time windows', () {
    test('today counts only the same calendar day', () {
      final r = RevenueEngine.compute([
        payment(id: 'a', amountPaid: 100, createdAt: DateTime(2026, 7, 22, 0, 1)),
        payment(id: 'b', amountPaid: 200, createdAt: DateTime(2026, 7, 22, 23, 59)),
        payment(id: 'c', amountPaid: 400, createdAt: DateTime(2026, 7, 21, 23, 59)),
      ], now: now);

      // 23:59 today is AFTER `now` (midday) — still the same calendar day,
      // so it counts; yesterday 23:59 does not.
      expect(r.todayRevenue, 300);
    });

    test('week is a rolling 7-day window (inDays <= 7, truncating)', () {
      final r = RevenueEngine.compute([
        // Exactly 7 days before `now` — inDays == 7 → included.
        payment(id: 'a', amountPaid: 100, createdAt: now.subtract(const Duration(days: 7))),
        // 7 days and 1 hour — inDays == 7 (truncation) → still included.
        payment(id: 'b', amountPaid: 200, createdAt: now.subtract(const Duration(days: 7, hours: 1))),
        // 8 full days — excluded.
        payment(id: 'c', amountPaid: 400, createdAt: now.subtract(const Duration(days: 8))),
      ], now: now);

      expect(r.weekRevenue, 300);
      expect(r.totalRevenue, 700);
    });

    test('month is the calendar month, not a rolling 30 days', () {
      final r = RevenueEngine.compute([
        payment(id: 'a', amountPaid: 100, createdAt: DateTime(2026, 7, 1)),
        payment(id: 'b', amountPaid: 200, createdAt: DateTime(2026, 7, 31)),
        payment(id: 'c', amountPaid: 400, createdAt: DateTime(2026, 6, 30)),
      ], now: now);

      expect(r.monthRevenue, 300);
      expect(r.prevMonthRevenue, 400);
    });

    test('january boundary: prev month resolves to December of last year', () {
      final jan = DateTime(2026, 1, 15);
      final r = RevenueEngine.compute([
        payment(id: 'a', amountPaid: 100, createdAt: DateTime(2026, 1, 2)),
        payment(id: 'b', amountPaid: 200, createdAt: DateTime(2025, 12, 31)),
        payment(id: 'c', amountPaid: 400, createdAt: DateTime(2025, 1, 10)),
      ], now: jan);

      expect(r.monthRevenue, 100);
      expect(r.prevMonthRevenue, 200); // Dec 2025, NOT Jan 2025
    });
  });

  group('growth percentages', () {
    test('daily growth compares today vs yesterday', () {
      final r = RevenueEngine.compute([
        payment(id: 'a', amountPaid: 300, createdAt: now),
        payment(id: 'b', amountPaid: 200, createdAt: now.subtract(const Duration(days: 1))),
      ], now: now);

      expect(r.dailyGrowth, closeTo(50, 0.0001)); // (300-200)/200
    });

    test('monthly growth compares calendar months', () {
      final r = RevenueEngine.compute([
        payment(id: 'a', amountPaid: 150, createdAt: DateTime(2026, 7, 5)),
        payment(id: 'b', amountPaid: 300, createdAt: DateTime(2026, 6, 5)),
      ], now: now);

      expect(r.monthlyGrowth, closeTo(-50, 0.0001));
    });

    test('zero baseline: 100 when current > 0, 0 when both are zero', () {
      final withCurrent = RevenueEngine.compute([
        payment(id: 'a', amountPaid: 100, createdAt: now),
      ], now: now);
      expect(withCurrent.dailyGrowth, 100);
      expect(withCurrent.monthlyGrowth, 100);

      final empty = RevenueEngine.compute([], now: now);
      expect(empty.dailyGrowth, 0);
      expect(empty.monthlyGrowth, 0);

      // A fully-refunded payment today keeps the baseline at zero → 0, not 100.
      final refunded = RevenueEngine.compute([
        payment(id: 'a', amountPaid: 100, refundAmount: 100, createdAt: now),
      ], now: now);
      expect(refunded.dailyGrowth, 0);
    });
  });

  group('breakdowns', () {
    test('plan and org breakdowns sum net amounts per key', () {
      final r = RevenueEngine.compute([
        payment(id: 'a', adminUid: 'org_a', plan: 'Gold', amountPaid: 100, createdAt: now),
        payment(id: 'b', adminUid: 'org_a', plan: 'Silver', amountPaid: 200, createdAt: now),
        payment(id: 'c', adminUid: 'org_b', plan: 'Gold', amountPaid: 400, refundAmount: 150, createdAt: now),
      ], now: now);

      expect(r.revenueByPlan, {'Gold': 350, 'Silver': 200});
      expect(r.revenueByAdmin, {'org_a': 300, 'org_b': 250});
    });
  });

  group('monthly buckets', () {
    test('six buckets oldest-first, current month last, labeled', () {
      final r = RevenueEngine.compute([
        payment(id: 'a', amountPaid: 100, createdAt: DateTime(2026, 7, 10)),
        payment(id: 'b', amountPaid: 200, createdAt: DateTime(2026, 2, 10)),
        // Outside the 6-month window (Feb..Jul 2026) — excluded from buckets.
        payment(id: 'c', amountPaid: 400, createdAt: DateTime(2026, 1, 10)),
      ], now: now);

      expect(r.monthlyBuckets.length, 6);
      expect(r.monthlyBuckets.map((b) => b.label).toList(),
          ['Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul']);
      expect(r.monthlyBuckets.first.value, 200);
      expect(r.monthlyBuckets.last.value, 100);
      // ...but the out-of-window payment still counts toward total revenue.
      expect(r.totalRevenue, 700);
    });
  });

  group('recent payments ordering', () {
    test('paymentsByDateDesc is sorted newest first', () {
      final r = RevenueEngine.compute([
        payment(id: 'old', createdAt: DateTime(2026, 5, 1)),
        payment(id: 'newest', createdAt: DateTime(2026, 7, 22)),
        payment(id: 'mid', createdAt: DateTime(2026, 6, 15)),
      ], now: now);

      expect(r.paymentsByDateDesc.map((s) => s.id).toList(),
          ['newest', 'mid', 'old']);
    });
  });
}
