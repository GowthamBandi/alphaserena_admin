// THE MEMBERS SCREEN MUST NOT STATE A NUMBER THE RECORDS DO NOT SUPPORT.
//
// 🔴 THE DEFECT THIS GUARDS (emulator, 2026-09-09, 428 real member records):
//   • "Growth Trend" rendered the literal string "📈 Chart Placeholder".
//   • "Client Goals" counted `c.goal == "Fat Loss"` / `== "Muscle Gain"` — an
//     exact, case-sensitive match on a free-text field, two hard-coded buckets,
//     no "not recorded" row. It read **Fat Loss 0 · Muscle Gain 0** while 27
//     members carried "Fat loss" and 401 carried no goal at all.
//
// Both numbers were wrong and neither could be distinguished from a true zero.
// This is the same class the console already removed once (the fictitious
// isVerified/isActive KPIs); this card survived because it read a field that
// really exists — it simply could never match it.

import 'dart:io';

import 'package:alphaserena_admin_portel/core/services/member_insights.dart';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:flutter_test/flutter_test.dart';

ClientModel member({
  String id = 'm',
  String? goal,
  DateTime? createdAt,
  bool createdAtKnown = true,
}) => ClientModel(
  docId: id,
  uid: id,
  name: id,
  email: '',
  phone: '',
  createdAt: createdAt ?? DateTime(2026, 9, 1),
  createdAtKnown: createdAtKnown,
  updatedAt: DateTime(2026, 9, 1),
  goal: goal,
);

void main() {
  group('goal breakdown', () {
    test('matches case- and whitespace-insensitively — the actual defect', () {
      // Exactly the shipped fixture: 27 "Fat loss", 401 with no goal.
      final clients = [
        for (var i = 0; i < 27; i++) member(id: 'f$i', goal: 'Fat loss'),
        for (var i = 0; i < 401; i++) member(id: 'n$i'),
      ];

      final b = clientGoalBreakdown(clients);

      expect(b.total, 428);
      expect(b.notRecorded, 401);
      expect(b.goals.single.count, 27);
      // Displayed as the coaches wrote it, not as the old card assumed.
      expect(b.goals.single.label, 'Fat loss');
    });

    test('one goal written three ways is one goal', () {
      final b = clientGoalBreakdown([
        member(id: 'a', goal: 'Fat Loss'),
        member(id: 'b', goal: 'fat loss'),
        member(id: 'c', goal: '  Fat loss  '),
      ]);

      expect(b.goals.length, 1);
      expect(b.goals.single.count, 3);
      expect(b.notRecorded, 0);
    });

    test('an empty or whitespace goal counts as not recorded, never as a goal',
        () {
      final b = clientGoalBreakdown([
        member(id: 'a', goal: ''),
        member(id: 'b', goal: '   '),
        member(id: 'c'),
      ]);

      expect(b.goals, isEmpty);
      expect(b.notRecorded, 3);
      expect(b.hasAnyRecorded, isFalse);
    });

    test('rows come back largest first, ties alphabetical, capped at top', () {
      final b = clientGoalBreakdown([
        member(id: '1', goal: 'Strength'),
        member(id: '2', goal: 'Strength'),
        member(id: '3', goal: 'Mobility'),
        member(id: '4', goal: 'Endurance'),
      ], top: 2);

      expect(b.goals.map((g) => g.label).toList(), ['Strength', 'Endurance']);
    });

    test('a goal the code never heard of still appears', () {
      // The old card could only ever show two categories.
      final b = clientGoalBreakdown([member(id: 'a', goal: 'Postnatal')]);
      expect(b.goals.single.label, 'Postnatal');
    });
  });

  group('growth series', () {
    final now = DateTime(2026, 9, 9);

    test('undated members are excluded, not piled onto this month', () {
      // THE TRAP: ClientModel.createdAt falls back to DateTime.now(), so an
      // undated member LOOKS like it joined today.
      final clients = [
        member(id: 'a', createdAt: DateTime(2026, 7, 4)),
        for (var i = 0; i < 50; i++)
          member(id: 'u$i', createdAt: now, createdAtKnown: false),
      ];

      final s = clientGrowthSeries(clients, now: now);

      expect(s.undated, 50);
      final sept = s.months.firstWhere((m) => m.month == DateTime(2026, 9));
      expect(sept.count, 0, reason: '50 undated members must not become joins');
      expect(s.months.firstWhere((m) => m.month == DateTime(2026, 7)).count, 1);
    });

    test('returns six consecutive months, oldest first, empties included', () {
      final s = clientGrowthSeries([], now: now);
      expect(s.months.length, 6);
      expect(s.months.first.month, DateTime(2026, 4));
      expect(s.months.last.month, DateTime(2026, 9));
      expect(s.hasAnyDated, isFalse);
    });

    test('a member older than the window is not counted into the first month',
        () {
      final s = clientGrowthSeries(
        [member(id: 'old', createdAt: DateTime(2023, 1, 1))],
        now: now,
      );
      expect(s.months.every((m) => m.count == 0), isTrue);
      expect(s.undated, 0);
    });

    test('peak is the tallest month, used for the bar scale', () {
      final s = clientGrowthSeries([
        member(id: 'a', createdAt: DateTime(2026, 8, 2)),
        member(id: 'b', createdAt: DateTime(2026, 8, 9)),
        member(id: 'c', createdAt: DateTime(2026, 9, 1)),
      ], now: now);

      expect(s.peak, 2);
      expect(s.hasAnyDated, isTrue);
    });
  });

  test('the placeholder string is gone from the console', () {
    // A founder screen shipped the words "Chart Placeholder" to production.
    final src = File(
      'lib/screens/clients_screen.dart',
    ).readAsStringSync();
    expect(src.contains('Chart Placeholder'), isFalse);
  });
}
