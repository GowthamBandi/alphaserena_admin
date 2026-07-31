// lib/core/services/revenue_engine.dart
//
// The ONE revenue engine for the founder console. Pure Dart — no Firestore,
// no GetX, no side effects — so the business math is unit-testable and can
// never drift between screens again. PaymentsController and
// DashboardController previously each re-implemented refund netting, period
// sums and growth percentages over the same `admin_payments_history` stream;
// both now call [RevenueEngine.compute] and only bind the results.
//
// Semantics are the PaymentsController semantics (the richer of the two).
// Where the old DashboardController disagreed, the difference is noted:
//
//  * Org breakdown key — dashboard keyed by raw `adminId ?? adminUid`;
//    the model (and therefore this engine) resolves `adminUid ?? adminId`
//    into [SubscriptionModel.adminUid]. Same value on well-formed docs.
//  * Amount field order — dashboard read `amount ?? price ?? paidAmount ??
//    totalAmount`; the model reads `amount ?? amountPaid ?? price ?? …`.
//    The model order wins (payments semantics).
//  * Missing dates — dashboard dropped undated payments from the month
//    buckets; the model defaults a missing `createdAt` to "now", so such a
//    payment lands in the current bucket (payments semantics).

import '../../models/subscription_model.dart';

/// One month of revenue history: `key` is `yyyy-MM`, `label` is `Jan`…`Dec`.
class MonthRevenueBucket {
  final String key;
  final String label;
  final double value;
  const MonthRevenueBucket(this.key, this.label, this.value);
}

/// Everything both controllers derive from the payment history, computed in
/// a single pass. All money figures are net of founder-issued refunds.
class RevenueReport {
  final double totalRevenue;
  final double todayRevenue;
  final double weekRevenue; // rolling: createdAt within the last 7 days
  final double monthRevenue; // calendar month of `now`
  final double prevMonthRevenue; // calendar month before `now`
  final int totalTransactions;

  /// Today vs yesterday, percent. Zero-baseline: 100 when today > 0, else 0.
  final double dailyGrowth;

  /// This calendar month vs last, percent. Same zero-baseline rule.
  final double monthlyGrowth;

  final Map<String, double> revenueByPlan;
  final Map<String, double> revenueByAdmin;

  /// Oldest → newest, always exactly [RevenueEngine.compute]'s
  /// `monthsOfHistory` entries, current month last.
  final List<MonthRevenueBucket> monthlyBuckets;

  /// All payments sorted newest-first by createdAt (for "recent payments").
  final List<SubscriptionModel> paymentsByDateDesc;

  const RevenueReport({
    required this.totalRevenue,
    required this.todayRevenue,
    required this.weekRevenue,
    required this.monthRevenue,
    required this.prevMonthRevenue,
    required this.totalTransactions,
    required this.dailyGrowth,
    required this.monthlyGrowth,
    required this.revenueByPlan,
    required this.revenueByAdmin,
    required this.monthlyBuckets,
    required this.paymentsByDateDesc,
  });
}

class RevenueEngine {
  RevenueEngine._();

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Computes the full [RevenueReport]. `now` is a parameter (never read from
  /// the clock) so every figure is deterministic and testable.
  static RevenueReport compute(
    List<SubscriptionModel> payments, {
    required DateTime now,
    int monthsOfHistory = 6,
  }) {
    final prevMonth = DateTime(now.year, now.month - 1);
    final yesterday = now.subtract(const Duration(days: 1));

    // Month buckets, oldest → newest, current month last.
    final buckets = <String, double>{};
    final order = <String>[];
    for (int i = monthsOfHistory - 1; i >= 0; i--) {
      final k = monthKey(DateTime(now.year, now.month - i));
      buckets[k] = 0;
      order.add(k);
    }

    double total = 0, today = 0, week = 0, month = 0;
    double yesterdayRev = 0, prevMonthRev = 0;
    final byPlan = <String, double>{};
    final byAdmin = <String, double>{};

    for (final s in payments) {
      // Net of founder-issued refunds — revenue is money actually kept.
      final amount = s.netAmount;
      final date = s.createdAt;

      total += amount;

      if (isSameDay(date, now)) today += amount;
      if (isSameDay(date, yesterday)) yesterdayRev += amount;

      // Rolling week — Duration.inDays truncates, so "7 days ago" counts.
      if (now.difference(date).inDays <= 7) week += amount;

      if (date.year == now.year && date.month == now.month) month += amount;
      if (date.year == prevMonth.year && date.month == prevMonth.month) {
        prevMonthRev += amount;
      }

      final k = monthKey(date);
      if (buckets.containsKey(k)) buckets[k] = buckets[k]! + amount;

      byPlan[s.planName] = (byPlan[s.planName] ?? 0) + amount;
      byAdmin[s.adminUid] = (byAdmin[s.adminUid] ?? 0) + amount;
    }

    final sorted = List<SubscriptionModel>.from(payments)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return RevenueReport(
      totalRevenue: total,
      todayRevenue: today,
      weekRevenue: week,
      monthRevenue: month,
      prevMonthRevenue: prevMonthRev,
      totalTransactions: payments.length,
      dailyGrowth: growthPercent(today, yesterdayRev),
      monthlyGrowth: growthPercent(month, prevMonthRev),
      revenueByPlan: byPlan,
      revenueByAdmin: byAdmin,
      monthlyBuckets: order
          .map((k) => MonthRevenueBucket(k, monthLabel(k), buckets[k] ?? 0))
          .toList(),
      paymentsByDateDesc: sorted,
    );
  }

  /// Growth percent with the console's zero-baseline convention:
  /// previous == 0 → 100 when current > 0, else 0.
  static double growthPercent(double current, double previous) {
    if (previous == 0) return current > 0 ? 100 : 0;
    return ((current - previous) / previous) * 100;
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static String monthLabel(String key) {
    final parts = key.split('-');
    final mi = int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
    return _monthNames[(mi - 1).clamp(0, 11)];
  }
}
