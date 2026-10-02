// MEMBER INSIGHTS — the arithmetic behind the Members screen's two analytics
// cards, kept pure so it can be tested without Firestore and so neither card can
// state something the data does not support.
//
// 🔴 WHAT THIS REPLACES (found 2026-09-09 on the emulator, 428 real members):
//
//   "Growth Trend"  rendered the literal string "📈 Chart Placeholder".
//   "Client Goals"  counted `c.goal == "Fat Loss"` and `c.goal == "Muscle Gain"`
//                   — an exact, case-sensitive match on a FREE-TEXT field with
//                   exactly two hard-coded buckets and no "not recorded" row.
//
// On the live fixture that card read **Fat Loss 0 · Muscle Gain 0** while 27
// members carried the goal "Fat loss" (lower-case L) and 401 carried no goal at
// all. Both numbers were false, and the screen offered no way to tell that from
// "we have no fat-loss members". This console has removed exactly this class of
// card before (the fictitious isVerified/isActive KPIs); the goals card was
// missed because it looked like it was reading a real field — it was, it just
// could never match it.
//
// THE RULE both helpers follow: report what the records actually say, name what
// is unknown, and never invent a bucket the data did not produce.

import '../../models/clints_model.dart';

/// One row of the goals breakdown.
class GoalCount {
  /// The goal exactly as the coach recorded it on the FIRST member seen with
  /// this goal — normalised only for MATCHING, never for display. Showing
  /// "Fat Loss" when every record says "Fat loss" is a small lie about the data.
  final String label;
  final int count;

  const GoalCount(this.label, this.count);
}

class GoalBreakdown {
  /// Recorded goals, largest first, then alphabetically for a stable order.
  final List<GoalCount> goals;

  /// Members whose record carries no goal at all (or an empty one). This is the
  /// number that made the old card meaningless, so it is never hidden.
  final int notRecorded;

  /// Every member considered.
  final int total;

  const GoalBreakdown({
    required this.goals,
    required this.notRecorded,
    required this.total,
  });

  bool get hasAnyRecorded => goals.isNotEmpty;
}

/// Groups members by the goal their record carries.
///
/// Matching is case- and whitespace-insensitive because the field is free text
/// written by many coaches across many organizations: "Fat loss", "fat loss"
/// and " Fat Loss " are one goal, and treating them as three is how a real
/// category came to read zero.
GoalBreakdown clientGoalBreakdown(List<ClientModel> clients, {int top = 6}) {
  final counts = <String, int>{};
  final display = <String, String>{};
  var notRecorded = 0;

  for (final c in clients) {
    final raw = (c.goal ?? '').trim();
    if (raw.isEmpty) {
      notRecorded++;
      continue;
    }
    final key = raw.toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
    display.putIfAbsent(key, () => raw);
  }

  final entries = counts.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });

  final rows = entries
      .take(top)
      .map((e) => GoalCount(display[e.key]!, e.value))
      .toList();

  return GoalBreakdown(
    goals: rows,
    notRecorded: notRecorded,
    total: clients.length,
  );
}

/// One month of joins.
class MonthCount {
  /// First day of the month, local time.
  final DateTime month;
  final int count;

  const MonthCount(this.month, this.count);
}

class GrowthSeries {
  /// Oldest month first, with empty months present so the shape is honest.
  final List<MonthCount> months;

  /// Members whose record carries no usable creation date. They are counted
  /// NOWHERE in [months] — putting them in the current month is what turns a
  /// missing field into fabricated growth.
  final int undated;

  final int peak;

  const GrowthSeries({
    required this.months,
    required this.undated,
    required this.peak,
  });

  bool get hasAnyDated => peak > 0;
}

/// New members per calendar month over the last [months] months ending at [now].
///
/// A member whose `createdAtKnown` is false is EXCLUDED and reported through
/// [GrowthSeries.undated]. `ClientModel.createdAt` falls back to
/// `DateTime.now()` when the document has no date, so counting it blindly would
/// pile every undated member onto the current month and draw a growth spike
/// that never happened.
GrowthSeries clientGrowthSeries(
  List<ClientModel> clients, {
  required DateTime now,
  int months = 6,
}) {
  final buckets = <DateTime, int>{};
  final start = DateTime(now.year, now.month - (months - 1));
  for (var i = 0; i < months; i++) {
    buckets[DateTime(start.year, start.month + i)] = 0;
  }

  var undated = 0;
  for (final c in clients) {
    if (!c.createdAtKnown) {
      undated++;
      continue;
    }
    final key = DateTime(c.createdAt.year, c.createdAt.month);
    if (buckets.containsKey(key)) buckets[key] = buckets[key]! + 1;
  }

  final rows = buckets.entries.map((e) => MonthCount(e.key, e.value)).toList()
    ..sort((a, b) => a.month.compareTo(b.month));

  var peak = 0;
  for (final r in rows) {
    if (r.count > peak) peak = r.count;
  }

  return GrowthSeries(months: rows, undated: undated, peak: peak);
}
