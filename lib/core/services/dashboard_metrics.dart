// lib/core/services/dashboard_metrics.dart
//
// The founder Dashboard's ORGANIZATION arithmetic, as a pure function.
//
// `DashboardController` used to classify the `admins` stream inline inside
// its snapshot listener: a switch over four status strings, a subscription
// tally, and a seven-day expiry window computed with `Duration.inDays`. None
// of it could be unit-tested without Firestore, and two of its rules were
// wrong in ways only a fixture could show:
//
//   • A status outside {active, pending, warning, blocked} — a legacy value,
//     a typo, a future backend state such as `suspended` — was counted in
//     `orgsTotal` but in NO slice, so the donut's centre said 14 while its
//     legend summed to 13. Nothing on the screen explained the gap.
//   • `Duration.inDays` TRUNCATES toward zero, so an organization whose plan
//     expired two hours ago (the hourly `expireSubscriptions` sweep has not
//     yet flipped `isSubscriptionActive`) had `diff == 0` and rendered as
//     "today" — a renewal that is still due — while one that expired 25 hours
//     ago had `diff == -1` and vanished from the card entirely. Neither is
//     "expiring soon"; both are "already expired, still marked active", which
//     is MORE urgent than a plan with three days left, not less.
//
// Everything here is deterministic in `now` so the tests pin real dates.

import '../../models/admin_model.dart';

/// One organization whose entitlement needs renewal attention.
class ExpiringOrg {
  final AdminModel org;

  /// Whole days until expiry, floored (never truncated toward zero): 0 means
  /// "expires before this time tomorrow", negative means already past.
  final int daysLeft;

  /// `planExpiry` is in the past while `isSubscriptionActive` is still true —
  /// the backend sweep has not caught up. The org is still operating on an
  /// expired plan.
  bool get isPastDue => daysLeft < 0;

  const ExpiringOrg(this.org, this.daysLeft);
}

class OrgStats {
  final int total;
  final int active;
  final int pending;
  final int warning;
  final int blocked;

  /// Organizations whose status is none of the four the console models.
  /// Surfaced rather than swallowed so the donut can always account for
  /// every organization it claims to total.
  final int other;

  /// `isSubscriptionActive == true`, regardless of moderation status. A
  /// blocked org that paid still counts: the money is real and the flag is the
  /// one the backend's operate-gate reads. The Dashboard labels it as such.
  final int subscribed;

  /// Subscribed AND able to operate (status neither pending nor blocked) —
  /// the backend `orgCanOperate` predicate.
  final int operable;

  /// Pending organizations, newest first.
  final List<AdminModel> pendingApprovals;

  /// Subscribed organizations expiring within [OrgStats.expiryWindowDays]
  /// days OR already past expiry but not yet swept. Past-due first, then by
  /// soonest expiry.
  final List<ExpiringOrg> expiring;

  const OrgStats({
    required this.total,
    required this.active,
    required this.pending,
    required this.warning,
    required this.blocked,
    required this.other,
    required this.subscribed,
    required this.operable,
    required this.pendingApprovals,
    required this.expiring,
  });

  static const int expiryWindowDays = 7;

  static const OrgStats empty = OrgStats(
    total: 0,
    active: 0,
    pending: 0,
    warning: 0,
    blocked: 0,
    other: 0,
    subscribed: 0,
    operable: 0,
    pendingApprovals: [],
    expiring: [],
  );

  /// Calendar-day distance from `now` to `expiry`, floored. Compares at day
  /// granularity in the caller's local zone so "3d" means "three more
  /// midnights", the way a founder reads a calendar.
  static int daysUntil(DateTime expiry, DateTime now) {
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(expiry.year, expiry.month, expiry.day);
    return b.difference(a).inDays;
  }

  static OrgStats compute(Iterable<AdminModel> admins, {required DateTime now}) {
    int total = 0, active = 0, pending = 0, warning = 0, blocked = 0, other = 0;
    int subscribed = 0, operable = 0;
    final pendingList = <AdminModel>[];
    final expiring = <ExpiringOrg>[];

    for (final a in admins) {
      total++;
      final status = a.status.toLowerCase();
      switch (status) {
        case 'active':
          active++;
          break;
        case 'pending':
          pending++;
          pendingList.add(a);
          break;
        case 'warning':
          warning++;
          break;
        case 'blocked':
          blocked++;
          break;
        default:
          other++;
      }

      if (a.isSubscriptionActive) {
        subscribed++;
        if (status != 'pending' && status != 'blocked') operable++;

        final exp = a.planExpiry;
        if (exp != null) {
          // Past-due is decided on the INSTANT (an expiry an hour ago is
          // past), the window on calendar days.
          if (exp.isBefore(now)) {
            final d = daysUntil(exp, now);
            expiring.add(ExpiringOrg(a, d < 0 ? d : -1));
          } else {
            final d = daysUntil(exp, now);
            if (d <= expiryWindowDays) expiring.add(ExpiringOrg(a, d));
          }
        }
      }
    }

    pendingList.sort((x, y) => y.createdAt.compareTo(x.createdAt));
    expiring.sort((x, y) {
      if (x.isPastDue != y.isPastDue) return x.isPastDue ? -1 : 1;
      final xe = x.org.planExpiry ?? now, ye = y.org.planExpiry ?? now;
      return xe.compareTo(ye);
    });

    return OrgStats(
      total: total,
      active: active,
      pending: pending,
      warning: warning,
      blocked: blocked,
      other: other,
      subscribed: subscribed,
      operable: operable,
      pendingApprovals: pendingList,
      expiring: expiring,
    );
  }
}
