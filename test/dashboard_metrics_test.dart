// THE DASHBOARD'S ORGANIZATION ARITHMETIC, PINNED.
//
// `OrgStats.compute` is the ONE place the Dashboard classifies organizations.
// These tests replay the fixture that exposed two live defects on the
// emulator (2026-09-05):
//   • a `suspended` org was in the donut's total but in no slice (14 ≠ 13);
//   • a plan that expired two hours earlier rendered as "today" because
//     `Duration.inDays` truncates toward zero, while one expired 25 hours
//     earlier vanished from the card.

import 'package:alphaserena_admin_portel/core/services/dashboard_metrics.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:flutter_test/flutter_test.dart';

AdminModel org(
  String id, {
  String? status = 'active',
  bool subscribed = false,
  DateTime? expiry,
  DateTime? created,
}) =>
    AdminModel.fromMap({
      'name': '$id owner',
      'organizationName': id,
      'email': '$id@x.test',
      if (status != null) 'status': status,
      'isSubscriptionActive': subscribed,
      if (expiry != null) 'planExpiry': expiry.toIso8601String(),
      'createdAt': (created ?? DateTime(2026, 1, 1)).toIso8601String(),
    }, id);

void main() {
  // A fixed instant, mid-afternoon, so day-boundary maths is unambiguous.
  final now = DateTime(2026, 9, 5, 15, 30);

  group('status slices', () {
    test('every organization lands in exactly one slice, so slices sum to total',
        () {
      final s = OrgStats.compute([
        org('a'),
        org('b', status: 'pending'),
        org('c', status: 'warning'),
        org('d', status: 'blocked'),
        org('e', status: 'suspended'), // unmodelled
        org('f', status: null), // missing → model default 'pending'
        org('g', status: 'approved'), // legacy → normalised to active
        org('h', status: 'ACTIVE'), // case-insensitive
      ], now: now);

      expect(s.total, 8);
      expect(s.active, 3, reason: 'a, legacy approved, ACTIVE');
      expect(s.pending, 2, reason: 'b and the status-less doc');
      expect(s.warning, 1);
      expect(s.blocked, 1);
      expect(s.other, 1, reason: 'suspended is unmodelled, not invisible');
      expect(s.active + s.pending + s.warning + s.blocked + s.other, s.total);
    });

    test('pending approvals are newest first', () {
      final s = OrgStats.compute([
        org('old', status: 'pending', created: DateTime(2026, 8, 1)),
        org('new', status: 'pending', created: DateTime(2026, 9, 4)),
        org('mid', status: 'pending', created: DateTime(2026, 8, 20)),
      ], now: now);
      expect(s.pendingApprovals.map((a) => a.docId), ['new', 'mid', 'old']);
    });
  });

  group('subscriptions', () {
    test('subscribed counts the flag regardless of moderation status; '
        'operable excludes pending and blocked', () {
      final s = OrgStats.compute([
        org('paid-active', subscribed: true),
        org('paid-pending', status: 'pending', subscribed: true),
        org('paid-blocked', status: 'blocked', subscribed: true),
        org('paid-warning', status: 'warning', subscribed: true),
        org('unpaid-active'),
      ], now: now);
      expect(s.subscribed, 4);
      expect(s.operable, 2, reason: 'active + warning can operate');
    });
  });

  group('expiring soon', () {
    test('window is seven calendar days, inclusive of today', () {
      final s = OrgStats.compute([
        org('in6h', subscribed: true, expiry: now.add(const Duration(hours: 6))),
        org('in3d', subscribed: true, expiry: now.add(const Duration(days: 3))),
        org('in7d', subscribed: true, expiry: now.add(const Duration(days: 7))),
        org('in8d', subscribed: true, expiry: now.add(const Duration(days: 8))),
        org('in40d', subscribed: true, expiry: now.add(const Duration(days: 40))),
      ], now: now);
      expect(s.expiring.map((e) => e.org.docId), ['in6h', 'in3d', 'in7d']);
      expect(s.expiring.map((e) => e.daysLeft), [0, 3, 7]);
      expect(s.expiring.every((e) => !e.isPastDue), isTrue);
    });

    test('"today" means before midnight tonight, not within 24 hours', () {
      // 15:30 now; 09:00 tomorrow is 17.5h away but a different calendar
      // day — a founder reading "today" would plan the wrong day.
      final tomorrowMorning = DateTime(2026, 9, 6, 9);
      final s = OrgStats.compute(
          [org('t', subscribed: true, expiry: tomorrowMorning)],
          now: now);
      expect(s.expiring.single.daysLeft, 1);
    });

    test('already-expired but still flagged active is PAST DUE, never "today", '
        'and never hidden', () {
      final s = OrgStats.compute([
        org('2h-ago', subscribed: true,
            expiry: now.subtract(const Duration(hours: 2))),
        org('25h-ago', subscribed: true,
            expiry: now.subtract(const Duration(hours: 25))),
        org('10d-ago', subscribed: true,
            expiry: now.subtract(const Duration(days: 10))),
      ], now: now);
      expect(s.expiring.length, 3, reason: 'none may vanish');
      expect(s.expiring.every((e) => e.isPastDue), isTrue);
      expect(s.expiring.every((e) => e.daysLeft < 0), isTrue,
          reason: 'a negative day count can never render as "today"');
    });

    test('past-due sorts before upcoming, then by soonest expiry', () {
      final s = OrgStats.compute([
        org('in5d', subscribed: true, expiry: now.add(const Duration(days: 5))),
        org('in1d', subscribed: true, expiry: now.add(const Duration(days: 1))),
        org('past', subscribed: true,
            expiry: now.subtract(const Duration(hours: 3))),
      ], now: now);
      expect(s.expiring.map((e) => e.org.docId), ['past', 'in1d', 'in5d']);
    });

    test('an unsubscribed org is never "expiring" — it is lapsed (Operations)',
        () {
      final s = OrgStats.compute([
        org('lapsed', subscribed: false,
            expiry: now.subtract(const Duration(days: 10))),
        org('unpaid-soon', subscribed: false,
            expiry: now.add(const Duration(days: 2))),
      ], now: now);
      expect(s.expiring, isEmpty);
    });

    test('a subscribed org with no expiry date is not listed', () {
      final s = OrgStats.compute([org('noexp', subscribed: true)], now: now);
      expect(s.expiring, isEmpty);
    });
  });

  test('daysUntil floors on calendar days in either direction', () {
    expect(OrgStats.daysUntil(DateTime(2026, 9, 5, 23, 59), now), 0);
    expect(OrgStats.daysUntil(DateTime(2026, 9, 6, 0, 1), now), 1);
    expect(OrgStats.daysUntil(DateTime(2026, 9, 4, 23, 59), now), -1);
    expect(OrgStats.daysUntil(DateTime(2026, 8, 26), now), -10);
  });

  test('empty input is the empty stats, not a crash', () {
    final s = OrgStats.compute(const [], now: now);
    expect(s.total, 0);
    expect(s.expiring, isEmpty);
    expect(s.pendingApprovals, isEmpty);
  });
}
