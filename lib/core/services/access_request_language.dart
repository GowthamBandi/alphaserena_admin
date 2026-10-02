// lib/core/services/access_request_language.dart
//
// ACCESS REQUESTS — the words and the arithmetic, as pure Dart.
//
// WHAT AN "ACCESS REQUEST" IS. A gym owner (the requester) has asked, from the
// Trainersarena app's public form, for their gym to join the platform. Approving
// one does not toggle a permission: it CREATES the organization — a sign-in for
// the owner, an organization record, and a paid plan — after the team has
// spoken to them and taken payment outside the platform. So the review
// questions are commercial ones (who, which gym, how big, why, have they paid)
// and the "access" granted is always the same thing: an organization owner
// account on the plan the founder picks at creation.
//
// LIFECYCLE (enforced by `setAccessRequestStatus` / `provisionOrganization`,
// mirrored in `SaasOnboardingService`):
//   requested → contacted → payment_pending → payment_confirmed → approved
//                                              → organization_created (terminal)
//   any open stage → rejected;  rejected → requested (reopen)
// There is no cancel, expiry or revoke; the UI must not imply one.
//
// TERMINOLOGY (use exactly these words):
//   Request        — one row of `access_requests`.
//   Requester      — the gym owner who asked (`ownerName`).
//   Organization   — the gym (`organizationName`); once created, an `admins` doc.
//   Stage          — where the request is in the pipeline (business words).
//   Reason         — the requester's own message.
//   Payment        — the off-platform payment the team recorded as evidence.
//   Create the organization — the approval act. Never "provision" in the UI.
//   Reject / Reopen — the only reversals that exist.

import '../../models/access_request_model.dart';
import '../../models/subscription_plan_model.dart';
import 'saas_onboarding_service.dart';

/// The pipeline grouped the way a person works it.
enum RequestGroup {
  newRequests,
  inConversation,
  readyToCreate,
  created,
  rejected,
  unknown,
}

extension RequestGroupX on RequestGroup {
  String get label => switch (this) {
    RequestGroup.newRequests => 'New',
    RequestGroup.inConversation => 'In conversation',
    RequestGroup.readyToCreate => 'Ready to create',
    RequestGroup.created => 'Organization created',
    RequestGroup.rejected => 'Rejected',
    RequestGroup.unknown => 'Unrecognised stage',
  };

  /// What the group means for the person working the queue.
  String get meaning => switch (this) {
    RequestGroup.newRequests => 'Nobody has contacted them yet.',
    RequestGroup.inConversation =>
      'The team is talking to them or waiting for their payment.',
    RequestGroup.readyToCreate =>
      'Payment is recorded. Create their organization account.',
    RequestGroup.created => 'Done — they can sign in to Trainersarena.',
    RequestGroup.rejected => 'Declined. Can be reopened if that was a mistake.',
    RequestGroup.unknown =>
      'The stored stage is not one this console knows. Open the details.',
  };

  bool get isOpen =>
      this == RequestGroup.newRequests ||
      this == RequestGroup.inConversation ||
      this == RequestGroup.readyToCreate;
}

/// How long a request has waited, in the words an operator uses.
enum WaitLevel { fresh, waiting, overdue }

extension WaitLevelX on WaitLevel {
  String get label => switch (this) {
    WaitLevel.fresh => 'Normal',
    WaitLevel.waiting => 'Waiting a while',
    WaitLevel.overdue => 'Overdue',
  };
}

class AccessRequestLanguage {
  AccessRequestLanguage._();

  /// Age thresholds. A prospect left three days without contact is losing
  /// interest; a week is a lost sale. These are the ONLY urgency signals — the
  /// backend records no priority, and this layer invents none.
  static const int waitingAfterDays = 3;
  static const int overdueAfterDays = 7;

  /// Days of completed history the summary tiles count.
  static const int recentWindowDays = 30;

  // ── stage words ───────────────────────────────────────────────────────────

  static RequestGroup groupOf(String status) => switch (status) {
    SaasOnboardingService.requested => RequestGroup.newRequests,
    SaasOnboardingService.contacted ||
    SaasOnboardingService.paymentPending => RequestGroup.inConversation,
    SaasOnboardingService.paymentConfirmed ||
    SaasOnboardingService.approved => RequestGroup.readyToCreate,
    SaasOnboardingService.organizationCreated => RequestGroup.created,
    SaasOnboardingService.rejected => RequestGroup.rejected,
    _ => RequestGroup.unknown,
  };

  static bool isKnownStatus(String status) =>
      groupOf(status) != RequestGroup.unknown;

  /// The stage as the operator reads it on a row.
  static String stageLabel(String status) => switch (status) {
    SaasOnboardingService.requested => 'New — not yet contacted',
    SaasOnboardingService.contacted => 'Contacted',
    SaasOnboardingService.paymentPending => 'Waiting for payment',
    SaasOnboardingService.paymentConfirmed => 'Payment received',
    SaasOnboardingService.approved => 'Approved — awaiting creation',
    SaasOnboardingService.organizationCreated => 'Organization created',
    SaasOnboardingService.rejected => 'Rejected',
    _ => 'Unrecognised stage',
  };

  /// Past-tense line for a timeline entry.
  static String eventLabel(String status) => switch (status) {
    SaasOnboardingService.requested => 'Request received',
    SaasOnboardingService.contacted => 'Marked as contacted',
    SaasOnboardingService.paymentPending => 'Payment link sent',
    SaasOnboardingService.paymentConfirmed => 'Payment recorded',
    SaasOnboardingService.approved => 'Approved',
    SaasOnboardingService.organizationCreated => 'Organization created',
    SaasOnboardingService.rejected => 'Rejected',
    _ => 'Moved to "$status"',
  };

  /// The one thing to do next, or null when nothing can be done here.
  static String? nextAction(AccessRequestModel r) {
    if (r.isProvisioned) return 'Open organization';
    return switch (r.status) {
      SaasOnboardingService.requested => 'Mark as contacted',
      SaasOnboardingService.contacted => 'Payment link sent',
      SaasOnboardingService.paymentPending => 'Record payment',
      SaasOnboardingService.paymentConfirmed ||
      SaasOnboardingService.approved => 'Create organization',
      SaasOnboardingService.rejected => 'Reopen',
      SaasOnboardingService.organizationCreated => 'Open organization',
      _ => null,
    };
  }

  /// What the next action will DO — shown before it is taken.
  static String nextActionMeaning(AccessRequestModel r) => switch (r.status) {
    SaasOnboardingService.requested =>
      'Records that the team has spoken to the requester. Nothing is '
          'created and they gain no access.',
    SaasOnboardingService.contacted =>
      'Records that a payment link was sent and you are waiting for the '
          'money. Nothing is created.',
    SaasOnboardingService.paymentPending =>
      'Records the payment the team already collected, with its reference. '
          'This is evidence only — no money moves here.',
    SaasOnboardingService.paymentConfirmed || SaasOnboardingService.approved =>
      'Creates the organization: a sign-in for the owner, the organization '
          'record and the plan you choose. This cannot be undone from here.',
    SaasOnboardingService.rejected =>
      'Puts the request back at the start of the queue as "New".',
    _ => '',
  };

  // ── who ───────────────────────────────────────────────────────────────────

  static const String unnamedRequester = 'Name not provided';
  static const String unnamedOrganization = 'Organization name not provided';
  static const String noReason = 'Reason not provided';

  static String requesterName(AccessRequestModel r) =>
      r.ownerName.trim().isEmpty ? unnamedRequester : r.ownerName.trim();

  static String organizationName(AccessRequestModel r) =>
      r.organizationName.trim().isEmpty
      ? unnamedOrganization
      : r.organizationName.trim();

  static String reason(AccessRequestModel r) =>
      r.message.trim().isEmpty ? noReason : r.message.trim();

  /// One line describing what is being asked for, in business terms.
  static String whatTheyWant(AccessRequestModel r) {
    final parts = <String>['A Trainersarena organization account'];
    if (r.teamSize != null && r.teamSize! > 0) {
      parts.add('team of ${r.teamSize}');
    }
    if (r.locationLine.isNotEmpty) parts.add(r.locationLine);
    return parts.join(' · ');
  }

  /// Initial for the avatar, from the organization or the requester.
  static String initial(AccessRequestModel r) {
    final s = r.organizationName.trim().isNotEmpty
        ? r.organizationName.trim()
        : r.ownerName.trim();
    return s.isEmpty ? '?' : s[0].toUpperCase();
  }

  /// Who acted. `by` is a uid (super admin), the literal 'prospect', or empty
  /// on legacy rows. [staffName] resolves a uid to a person; [currentUid] turns
  /// the founder's own uid into "you".
  static String actor(
    String by, {
    required String? Function(String uid) staffName,
    String? currentUid,
  }) {
    if (by.isEmpty) return 'Unknown';
    if (by == 'prospect') return 'the requester';
    if (currentUid != null && by == currentUid) return 'you';
    return staffName(by) ?? 'a super-admin';
  }

  // ── when ──────────────────────────────────────────────────────────────────

  static int daysWaiting(AccessRequestModel r, {required DateTime now}) {
    final c = r.createdAt;
    if (c == null) return 0;
    final d = now.difference(c).inDays;
    return d < 0 ? 0 : d;
  }

  static WaitLevel waitLevel(AccessRequestModel r, {required DateTime now}) {
    if (!groupOf(r.status).isOpen) return WaitLevel.fresh;
    final d = daysWaiting(r, now: now);
    if (d >= overdueAfterDays) return WaitLevel.overdue;
    if (d >= waitingAfterDays) return WaitLevel.waiting;
    return WaitLevel.fresh;
  }

  /// "Just now", "3 hours ago", "Yesterday", "5 days ago", "12 Aug 2026".
  static String ago(DateTime? t, {required DateTime now}) {
    if (t == null) return 'Time not recorded';
    final d = now.difference(t);
    if (d.isNegative) return 'Just now';
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) {
      return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
    }
    if (d.inHours < 24) {
      return '${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
    }
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final days = today.difference(day).inDays;
    if (days == 1) return 'Yesterday';
    if (days < 30) return '$days days ago';
    return exact(t, withTime: false);
  }

  /// "Waiting 5 days" for open rows; "" otherwise.
  static String waitingLine(AccessRequestModel r, {required DateTime now}) {
    if (!groupOf(r.status).isOpen) return '';
    if (r.createdAt == null) return 'Waiting time unknown';
    final d = daysWaiting(r, now: now);
    if (d == 0) return 'Received today';
    return 'Waiting $d day${d == 1 ? '' : 's'}';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String exact(DateTime? t, {bool withTime = true}) {
    if (t == null) return 'not recorded';
    final date = '${t.day} ${_months[t.month - 1]} ${t.year}';
    if (!withTime) return date;
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$date, $h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  // ── what approval allows ──────────────────────────────────────────────────

  /// Plain description of a plan the founder may assign at creation.
  static String planSummary(SubscriptionPlanModel p) {
    final bits = <String>[];
    for (final e in p.limits.entries) {
      final v = e.value;
      final what = e.key.label.toLowerCase();
      bits.add(
        v < 0 || v >= SubscriptionPlanModel.unlimitedThreshold
            ? 'unlimited $what'
            : '$v $what',
      );
    }
    final price = p.price > 0
        ? '₹${p.price.round()} / ${p.durationMonths} month${p.durationMonths == 1 ? '' : 's'}'
        : 'no price set';
    return '${p.planName} — $price${bits.isEmpty ? '' : ' · ${bits.join(', ')}'}';
  }

  /// What creating the organization lets the owner do — the same for every
  /// request, because the platform has one kind of organization account.
  static const String whatCreationAllows =
      'The requester becomes the owner of a new organization on Trainersarena. '
      'They can sign in, add trainers and members up to the limits of the plan '
      'you choose, create workout and diet programs, and take member payments '
      'through the platform. The plan sets the limits and the expiry date.';

  // ── ordering & filtering ──────────────────────────────────────────────────

  /// Open queue: OLDEST first — the request that has waited longest is the one
  /// most at risk of being lost. Completed rows: newest first, so the most
  /// recent decision is on top. Missing dates sink to the bottom.
  static int compare(AccessRequestModel a, AccessRequestModel b) {
    final ao = groupOf(a.status).isOpen, bo = groupOf(b.status).isOpen;
    if (ao != bo) return ao ? -1 : 1;
    final ad = a.createdAt, bd = b.createdAt;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ao ? ad.compareTo(bd) : bd.compareTo(ad);
  }

  static List<AccessRequestModel> sorted(Iterable<AccessRequestModel> rows) =>
      rows.toList()..sort(compare);

  /// Free-text match on the things a person types: names, contact, place.
  static bool matches(AccessRequestModel r, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return r.organizationName.toLowerCase().contains(q) ||
        r.ownerName.toLowerCase().contains(q) ||
        r.email.toLowerCase().contains(q) ||
        r.phone.contains(q) ||
        r.whatsapp.contains(q) ||
        r.city.toLowerCase().contains(q) ||
        r.state.toLowerCase().contains(q) ||
        r.id.toLowerCase() == q;
  }

  /// Filter keys the screen offers: 'open' (default), 'all', a group name, or
  /// a raw status.
  static bool matchesFilter(
    AccessRequestModel r,
    String filter, {
    DateTime? now,
  }) {
    final g = groupOf(r.status);
    return switch (filter) {
      'all' => true,
      'open' => g.isOpen || g == RequestGroup.unknown,
      'overdue' =>
        waitLevel(r, now: now ?? DateTime.now()) == WaitLevel.overdue,
      'new' => g == RequestGroup.newRequests,
      'conversation' => g == RequestGroup.inConversation,
      'ready' => g == RequestGroup.readyToCreate,
      'created' => g == RequestGroup.created,
      'rejected' => g == RequestGroup.rejected,
      _ => r.status == filter,
    };
  }

  static String filterLabel(String filter) => switch (filter) {
    'open' => 'Needs attention',
    'overdue' => 'Overdue',
    'all' => 'All requests',
    'new' => 'New',
    'conversation' => 'In conversation',
    'ready' => 'Ready to create',
    'created' => 'Created',
    'rejected' => 'Rejected',
    _ => stageLabel(filter),
  };

  /// Rows completed within the recent window (for the two history tiles).
  static bool completedRecently(AccessRequestModel r, {required DateTime now}) {
    final t = r.provisionedAt ?? r.updatedAt ?? r.createdAt;
    if (t == null) return true; // a legacy row with no dates is still shown
    return now.difference(t).inDays < recentWindowDays;
  }
}
