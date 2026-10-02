// lib/core/services/ops_language.dart
//
// THE OPERATIONS CENTER'S VOCABULARY AND ARITHMETIC — pure Dart, no Firebase,
// no GetX, no widgets. Everything an operator reads on that screen is built
// here from raw backend records, so it can be unit-tested and so the SAME
// wording is used everywhere.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY A LANGUAGE LAYER EXISTS
// ─────────────────────────────────────────────────────────────────────────────
// The backend writes what it knows: `settlement_create_failed`, `P0`,
// `fn settleMemberPayment`, `correlationId pay_Nx…`. That is the right record
// for an engineer and the wrong first sentence for the business owner who
// opens this screen at 8 a.m. The owner needs, in this order: what happened,
// why it matters, who is affected, when, how urgent, what to do. The raw
// record stays available under "Technical details" — it is evidence, not the
// headline.
//
// TERMINOLOGY (use exactly these words in operator-facing text):
//   Organization  — a gym / tenant (an `admins` document). Never "org",
//                   "tenant", "account" or "admin" in prose.
//   Owner         — the person who runs an organization (its admin user).
//   Trainer       — an organization's coaching staff.
//   Member        — a gym's end customer (a `clients` document).
//   Subscription  — an organization's paid plan with the platform.
//   Payment       — money an organization paid the platform (System A).
//   Payout        — money the platform owes onward to a gym (System B).
//   Announcement  — a platform-wide message the founder sends.
//   Support request / Review — feedback from organizations / from members.

import '../../models/admin_model.dart';
import '../../models/ops_incident_model.dart';
import '../../models/org_feedback_model.dart';
import '../../models/org_review_model.dart';
import '../../models/platform_announcement_model.dart';

// ═════════════════════════════════════════════════════════════════════════════
// ENUMS
// ═════════════════════════════════════════════════════════════════════════════

/// Four levels, deliberately no more. The operator must be able to tell them
/// apart by NAME, not by shade of red.
enum OpsUrgency { critical, high, attention, info }

extension OpsUrgencyX on OpsUrgency {
  int get rank => index;

  String get label => switch (this) {
    OpsUrgency.critical => 'Critical',
    OpsUrgency.high => 'High',
    OpsUrgency.attention => 'Needs attention',
    OpsUrgency.info => 'Informational',
  };

  /// One line the operator can read instead of decoding a colour.
  String get meaning => switch (this) {
    OpsUrgency.critical =>
      'Money or access is at risk right now. Deal with this first.',
    OpsUrgency.high =>
      'Needs a decision today — a customer or a payment is affected.',
    OpsUrgency.attention => 'Worth handling this week; nothing is broken.',
    OpsUrgency.info => 'For awareness only. No action is required.',
  };
}

/// The lifecycle an operator sees. Never inferred from colour.
enum OpsItemStatus { needsAttention, inProgress, resolved, informational }

extension OpsItemStatusX on OpsItemStatus {
  String get label => switch (this) {
    OpsItemStatus.needsAttention => 'Needs attention',
    OpsItemStatus.inProgress => 'In progress',
    OpsItemStatus.resolved => 'Resolved',
    OpsItemStatus.informational => 'Information',
  };
}

/// Where a row came from — drives which actions are real for it.
enum OpsSource {
  incident, // ops_incidents (server-raised, founder triages)
  paymentAlert, // paymentAlerts (server-raised, founder resolves)
  quota, // quotaAlerts (self-healing, no writer)
  organizations, // derived from the admins stream
  support, // derived from feedback / reviews
  announcements, // derived from platform_announcements
  feed, // one of the data feeds itself failed
}

enum OpsActionKind {
  navigate,
  acknowledge,
  resolve,
  reopen,
  retry,

  /// Re-run the CURRENT status's integrity legs for the organization the
  /// row names (`reapplyAdminStatusEffects`, C6).
  reapplyEffects,
}

class OpsAction {
  final String label;
  final OpsActionKind kind;

  /// For [OpsActionKind.navigate]: the console destination id and, for the
  /// Organizations screen, the status filter to pre-apply.
  final int? navIndex;
  final String? orgFilter;

  const OpsAction.navigate(this.label, this.navIndex, {this.orgFilter})
    : kind = OpsActionKind.navigate;
  const OpsAction.acknowledge()
    : label = 'Mark in progress',
      kind = OpsActionKind.acknowledge,
      navIndex = null,
      orgFilter = null;
  const OpsAction.resolve([this.label = 'Mark resolved'])
    : kind = OpsActionKind.resolve,
      navIndex = null,
      orgFilter = null;
  const OpsAction.reopen()
    : label = 'Reopen',
      kind = OpsActionKind.reopen,
      navIndex = null,
      orgFilter = null;
  const OpsAction.retry()
    : label = 'Try again',
      kind = OpsActionKind.retry,
      navIndex = null,
      orgFilter = null;
  const OpsAction.reapplyEffects()
    : label = 'Re-apply status effects',
      kind = OpsActionKind.reapplyEffects,
      navIndex = null,
      orgFilter = null;

  /// A write the row's lock must cover.
  bool get isWrite =>
      kind == OpsActionKind.acknowledge ||
      kind == OpsActionKind.resolve ||
      kind == OpsActionKind.reopen ||
      kind == OpsActionKind.reapplyEffects;
}

// ═════════════════════════════════════════════════════════════════════════════
// THE ITEM
// ═════════════════════════════════════════════════════════════════════════════

/// One row of the Operations Center, fully worded for an operator.
class OpsItem {
  /// Stable within a session (backend doc id, or a derived key).
  final String id;
  final OpsSource source;
  final OpsUrgency urgency;
  final OpsItemStatus status;

  /// WHAT HAPPENED — one plain sentence, no identifiers.
  final String title;

  /// WHY IT MATTERS — the consequence if nothing is done.
  final String why;

  /// AFFECTED — organization / payment / component, in words.
  final String affected;

  /// WHEN — the most relevant instant (last seen, raised, due).
  final DateTime? when;

  /// How [when] should be introduced ("Last seen", "Raised", "Respond by").
  final String whenLabel;

  final OpsAction primary;
  final List<OpsAction> secondary;

  /// Diagnostic pairs shown only under "Technical details".
  final List<MapEntry<String, String>> technical;

  /// Aggregated rows: how many underlying records this line stands for.
  final int count;

  /// Resolution trail (resolved rows only).
  final String resolutionNote;
  final DateTime? resolvedAt;

  /// Backend record id for acknowledge/resolve/reopen. Null for derived rows.
  final String? recordId;

  /// The organization the row is about, when it names one — the target of
  /// "Re-apply status effects".
  final String? orgId;

  const OpsItem({
    required this.id,
    required this.source,
    required this.urgency,
    required this.status,
    required this.title,
    required this.why,
    required this.affected,
    required this.when,
    this.whenLabel = 'Last seen',
    required this.primary,
    this.secondary = const [],
    this.technical = const [],
    this.count = 1,
    this.resolutionNote = '',
    this.resolvedAt,
    this.recordId,
    this.orgId,
  });

  /// Compatibility alias — older tests and the Dashboard read `detail`.
  String get detail => why;

  bool get isActionable =>
      status == OpsItemStatus.needsAttention ||
      status == OpsItemStatus.inProgress;

  /// Free-text search surface: everything an operator might type.
  String get searchable => [
    title,
    why,
    affected,
    ...technical.map((e) => '${e.key} ${e.value}'),
  ].join(' ').toLowerCase();
}

// ═════════════════════════════════════════════════════════════════════════════
// TIME
// ═════════════════════════════════════════════════════════════════════════════

class OpsTime {
  OpsTime._();

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

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "Just now", "12 minutes ago", "Today 10:42 AM", "Yesterday 9:05 PM",
  /// "5 Sep, 3:10 PM", "5 Sep 2025". A missing time is SAID, never invented.
  static String human(DateTime? t, {required DateTime now}) {
    if (t == null) return 'Time not recorded';
    final d = now.difference(t);
    if (d.inSeconds < 60 && d.inSeconds >= 0) return 'Just now';
    if (d.inMinutes < 60 && d.inMinutes >= 1) {
      return '${d.inMinutes} minute${d.inMinutes == 1 ? '' : 's'} ago';
    }
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final days = today.difference(day).inDays;
    if (days == 0) return 'Today ${_clock(t)}';
    if (days == 1) return 'Yesterday ${_clock(t)}';
    if (days == -1) return 'Tomorrow ${_clock(t)}';
    if (t.year == now.year) {
      return '${t.day} ${_months[t.month - 1]}, ${_clock(t)}';
    }
    return '${t.day} ${_months[t.month - 1]} ${t.year}';
  }

  /// Exact form for tooltips and technical details.
  static String exact(DateTime? t) => t == null
      ? 'not recorded'
      : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${_clock(t)}';
}

// ═════════════════════════════════════════════════════════════════════════════
// LANGUAGE — backend type → operator words
// ═════════════════════════════════════════════════════════════════════════════

class _Words {
  final String title;
  final String why;
  final OpsUrgency? urgency; // null → derive from backend severity
  final int? navIndex; // where the fix lives
  final String navLabel;
  const _Words(
    this.title,
    this.why, {
    this.urgency,
    this.navIndex,
    this.navLabel = '',
  });
}

/// Console destination ids (see console_destinations.dart; pinned by
/// nav_reachability_test).
class OpsNav {
  OpsNav._();
  static const int organizations = 1;
  static const int trainers = 2;
  static const int revenue = 5;
  static const int support = 7;
  static const int announcements = 8;
  static const int settlements = 14;
  static const int accessRequests = 17;
  static const int crashReports = 18;
}

class OpsLanguage {
  OpsLanguage._();

  static const String unknownOrganization = 'Organization no longer exists';

  /// Incident types "Re-apply status effects" repairs (C6).
  static const Set<String> reapplyableTypes = {
    'org_cascade_failed',
    'org_auth_enforcement_failed',
  };

  // ── ops_incidents types (backend lib/ops_incident.ts INCIDENT_TYPES) ──────
  static const Map<String, _Words> _incidents = {
    'audit_write_failed': _Words(
      'A subscription grant was recorded but its audit entry failed',
      'The payment and the plan are correct and the reference is already '
          'used, so do NOT record it again — a retry is refused as a '
          'duplicate. The compliance trail has a hole to fill by hand from '
          'the receipt.',
      navIndex: OpsNav.organizations,
      navLabel: 'Open Organizations',
    ),
    'settlement_create_failed': _Words(
      "A member's payment has no payout record",
      'The member paid and was activated, but the money owed to their gym was '
          'never recorded. Until it is, the gym will not be paid for this sale.',
      navIndex: OpsNav.settlements,
      navLabel: 'Open Settlements',
    ),
    'webhook_signature_rejected': _Words(
      'Payment updates from Razorpay are being rejected',
      'The platform refused to trust a payment notification. Payments may not '
          'be marked complete until the connection to Razorpay is fixed.',
    ),
    'gateway_request_failed': _Words(
      'Razorpay refused a payment request',
      'Someone may have been unable to pay. Check the Razorpay dashboard '
          'before retrying anything.',
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    'webhook_handler_error': _Words(
      'A payment update could not be processed',
      'Razorpay will retry for 24 hours. After that the update is lost and a '
          'payment may stay unrecorded.',
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    'crash_new_fatal_signature': _Words(
      'A new kind of app crash has appeared',
      'Users are hitting an error the platform has never recorded before — '
          'this usually arrives with a new release.',
      navIndex: OpsNav.crashReports,
      navLabel: 'Open Crash Reports',
    ),
    'crash_widespread': _Words(
      'Many users are crashing on the same error',
      'Five or more people cannot use the app right now. This is an outage '
          'in progress, not one person\'s bad day.',
      navIndex: OpsNav.crashReports,
      navLabel: 'Open Crash Reports',
    ),
    'crash_escalating': _Words(
      'A known app crash is spreading',
      'It is happening ten times more often than before. A trend to watch, '
          'not yet an outage.',
      urgency: OpsUrgency.attention,
      navIndex: OpsNav.crashReports,
      navLabel: 'Open Crash Reports',
    ),
    'admin_status_audit_failed': _Words(
      'An organization status change was not written to the audit log',
      'The change itself happened. Only the compliance record is missing, so '
          'note who changed what, and when.',
      navIndex: OpsNav.organizations,
      navLabel: 'Open Organizations',
    ),
    'org_cascade_failed': _Words(
      "Trainer access did not follow an organization's new status",
      "A blocked organization's trainers may still be able to work. Use "
          '"Re-apply status effects" to re-run the trainer sync for the '
          'current status — it never changes the status or notifies anyone, '
          'and the incident resolves itself when every step succeeds.',
      navIndex: OpsNav.organizations,
      navLabel: 'Open Organizations',
    ),
    'org_auth_enforcement_failed': _Words(
      "An owner's sign-in was not updated to match their organization's status",
      'A blocked owner may still be able to sign in. Use "Re-apply status '
          'effects" to disable (or re-enable) the sign-in for the current '
          'status — it never changes the status or notifies anyone, and the '
          'incident resolves itself when every step succeeds.',
      navIndex: OpsNav.organizations,
      navLabel: 'Open Organizations',
    ),
    'provision_rollback_failed': _Words(
      'An organization that failed to be created left an owner account behind',
      'Creating the organization failed and the automatic clean-up of the '
          "owner's sign-in account did not finish. The account may exist "
          'with no organization record — check Firebase Authentication before '
          'creating the organization again.',
      navIndex: OpsNav.accessRequests,
      navLabel: 'Open Access Requests',
    ),
    'provision_commit_unconfirmed': _Words(
      'The platform cannot confirm whether an organization was created',
      'Creating the organization lost contact at the final step, so it may or '
          'may not exist. Nothing was deleted. Check Organizations for it '
          'before trying again — a second attempt on the same request is '
          'recognised and does not create a duplicate.',
      navIndex: OpsNav.accessRequests,
      navLabel: 'Open Access Requests',
    ),
    'grant_commit_unconfirmed': _Words(
      'The platform cannot confirm whether a payment was recorded',
      'Recording a subscription payment lost contact at the final step, so '
          'the receipt and the new end date may or may not exist. Check the '
          "organization's receipts before recording it again — the same "
          'payment reference is never recorded twice.',
      navIndex: OpsNav.organizations,
      navLabel: 'Open Organizations',
    ),
    'scheduled_job_warning': _Words(
      'A background job reported a warning',
      'No payment or access is affected. Read the details when convenient.',
      urgency: OpsUrgency.attention,
    ),
  };

  // ── paymentAlerts kinds (reconcile.ts / webhooks.ts / refunds.ts /
  //    settlement_scheduler.ts) ───────────────────────────────────────────────
  static const Map<String, _Words> _paymentKinds = {
    'charged_not_activated': _Words(
      'A payment was received but nothing was activated',
      'The buyer paid and got no subscription. Activate it or refund it '
          'before it turns into a dispute.',
      urgency: OpsUrgency.critical,
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    'dispute': _Words(
      'A payment is being disputed (chargeback)',
      'If nobody responds by the deadline, the money is lost by default. '
          'Respond in the Razorpay dashboard.',
      urgency: OpsUrgency.critical,
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    'settlement_stuck_in_flight': _Words(
      'A payout to a gym is stuck',
      'Money the platform owes a gym has been "in transfer" for too long. '
          'Check whether the transfer actually happened before retrying.',
      urgency: OpsUrgency.high,
      navIndex: OpsNav.settlements,
      navLabel: 'Open Settlements',
    ),
    'refund_inconsistent': _Words(
      'A refund left the records inconsistent',
      'The money was refunded, but part of the follow-up failed. Check the '
          "organization's subscription state matches the refund.",
      urgency: OpsUrgency.high,
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    'payment_failed': _Words(
      'A payment attempt failed',
      "The buyer's payment did not go through. Nothing needs fixing on the "
          'platform; they can try again.',
      urgency: OpsUrgency.info,
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    // ── refund kinds (CONTRACTS C3) ─────────────────────────────────────────
    'refund_at_gateway': _Words(
      "An organization's payment was refunded outside this console",
      'Someone refunded a subscription payment in the Razorpay dashboard. '
          'The receipt now records it, but the organization keeps its access — '
          "the platform never ends a subscription on its own. Decide whether "
          'their access should continue.',
      urgency: OpsUrgency.high,
      navIndex: OpsNav.organizations,
      navLabel: 'Open Organizations',
    ),
    'refund_failed': _Words(
      'A refund failed at the gateway',
      'Razorpay reported that a refund did not go through, so the money never '
          'left. The receipt no longer counts it. If the payer is still owed '
          'money, it has to be refunded again.',
      urgency: OpsUrgency.high,
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    'refund_outcome_unknown': _Words(
      'A refund may or may not have gone through',
      'The refund was sent but the gateway never answered, so nobody knows '
          'whether money moved. Check the payment in the Razorpay dashboard '
          'before refunding anything again — a second refund could pay the '
          'money back twice.',
      urgency: OpsUrgency.critical,
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    'refund_unmatched': _Words(
      'A refund matched no payment record',
      'Razorpay reported a refund for a payment the platform has no receipt '
          'or payout for. Money left the account with nothing on file to '
          'explain it — find the payment in the Razorpay dashboard.',
      urgency: OpsUrgency.high,
      navIndex: OpsNav.revenue,
      navLabel: 'Open Revenue',
    ),
    'refund_before_settlement': _Words(
      "A member's refund arrived before the gym's payout record existed",
      'The payout record for this membership payment was not there yet when '
          "the refund came in. Check that the gym's payout does not still "
          'include the refunded money.',
      urgency: OpsUrgency.high,
      navIndex: OpsNav.settlements,
      navLabel: 'Open Settlements',
    ),
  };

  /// A payment alert kind's title — for the organization workspace's Health,
  /// which names the alerts that concern one organization.
  static String paymentAlertTitle(String kind) =>
      _paymentKinds[kind]?.title ?? 'A payment needs review';

  static OpsUrgency urgencyFromSeverity(String severity) => switch (severity) {
    'P0' => OpsUrgency.critical,
    'P1' => OpsUrgency.high,
    'P2' => OpsUrgency.attention,
    _ => OpsUrgency.high,
  };

  /// Money in paise → "₹4,999" / "₹1,178.82" (Indian grouping, paise kept
  /// when there are any — a refund of ₹0.50 is not "₹1").
  static String rupees(num? paise) {
    if (paise == null || !paise.isFinite) return '';
    final minor = paise.round();
    final neg = minor < 0;
    final abs = minor.abs();
    final whole = abs ~/ 100;
    final fraction = abs % 100 == 0
        ? ''
        : '.${(abs % 100).toString().padLeft(2, '0')}';
    final s = whole.toString();
    if (s.length <= 3) return '₹${neg ? '-' : ''}$s$fraction';
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '₹${neg ? '-' : ''}${parts.join(',')},$last3$fraction';
  }

  static String plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  // ── builders ──────────────────────────────────────────────────────────────

  /// `ops_incidents` row → item. [orgName] resolves an organization id found
  /// in the incident context to its name (null when no such organization).
  static OpsItem fromIncident(
    OpsIncidentModel i, {
    required String? Function(String uid) orgName,
  }) {
    final w = _incidents[i.type];
    final urgency = w?.urgency ?? urgencyFromSeverity(i.severity);
    final status = i.isResolved
        ? OpsItemStatus.resolved
        : i.isAcknowledged
        ? OpsItemStatus.inProgress
        : OpsItemStatus.needsAttention;

    final orgId =
        i.context['adminUid'] ??
        i.context['adminId'] ??
        i.context['orgId'] ??
        i.context['organizationId'];
    String affected;
    if (orgId != null && orgId.isNotEmpty) {
      affected = orgName(orgId) ?? unknownOrganization;
    } else if (i.type.startsWith('crash_')) {
      affected = 'App users';
    } else if (i.type.startsWith('webhook_') ||
        i.type == 'gateway_request_failed') {
      affected = 'Payment processing';
    } else {
      affected = 'Platform';
    }

    // The organization a status-effects incident is about: its context, or
    // the correlation id the backend keys these incidents on.
    final reapplyable = reapplyableTypes.contains(i.type);
    final targetOrg = (orgId != null && orgId.isNotEmpty)
        ? orgId
        : (reapplyable && i.correlationId.isNotEmpty ? i.correlationId : null);

    final secondary = <OpsAction>[];
    if (reapplyable && targetOrg != null && status != OpsItemStatus.resolved) {
      secondary.add(const OpsAction.reapplyEffects());
    }
    if (status == OpsItemStatus.needsAttention) {
      secondary.add(const OpsAction.acknowledge());
    }
    if (w?.navIndex != null && status != OpsItemStatus.resolved) {
      secondary.add(OpsAction.navigate(w!.navLabel, w.navIndex));
    }

    return OpsItem(
      id: 'incident:${i.id}',
      recordId: i.id,
      orgId: targetOrg,
      source: OpsSource.incident,
      urgency: urgency,
      status: status,
      title: w?.title ?? 'The system flagged a problem',
      why:
          w?.why ??
          (i.summary.isNotEmpty
              ? i.summary
              : 'The backend raised an incident of a type this console does '
                    'not yet describe. Read the technical details.'),
      affected: affected,
      when: i.lastSeenAt ?? i.firstSeenAt,
      whenLabel: i.occurrences > 1 ? 'Last seen' : 'Raised',
      primary: status == OpsItemStatus.resolved
          ? const OpsAction.reopen()
          : const OpsAction.resolve(),
      secondary: secondary,
      count: i.occurrences < 1 ? 1 : i.occurrences,
      resolutionNote: i.resolutionNote,
      resolvedAt: i.resolvedAt,
      technical: [
        MapEntry('Incident type', i.type),
        MapEntry('Backend severity', i.severity),
        if (i.summary.isNotEmpty) MapEntry('Backend summary', i.summary),
        if (i.action.isNotEmpty) MapEntry('Engineer guidance', i.action),
        if (i.fn.isNotEmpty) MapEntry('Function', i.fn),
        if (i.correlationId.isNotEmpty) MapEntry('Reference', i.correlationId),
        MapEntry('Occurrences', '${i.occurrences}'),
        MapEntry('First seen', OpsTime.exact(i.firstSeenAt)),
        MapEntry('Last seen', OpsTime.exact(i.lastSeenAt)),
        for (final e in i.context.entries) MapEntry(e.key, e.value),
        MapEntry('Record id', i.id),
      ],
    );
  }

  /// `paymentAlerts` row → item. Docs are heterogeneous (five writers), so
  /// every field is read defensively.
  static OpsItem fromPaymentAlert(
    Map<String, dynamic> a, {
    required String? Function(String uid) orgName,
  }) {
    final id = (a['id'] ?? '').toString();
    final kind = (a['kind'] ?? a['type'] ?? '').toString();
    final w = _paymentKinds[kind];
    final statusRaw = (a['status'] ?? 'open').toString();
    final resolved = statusRaw == 'resolved';
    final phase = (a['phase'] ?? '').toString();
    final informational =
        w?.urgency == OpsUrgency.info || (kind == 'dispute' && phase == 'won');
    final status = resolved
        ? OpsItemStatus.resolved
        : (informational
              ? OpsItemStatus.informational
              : OpsItemStatus.needsAttention);

    final orgId = (a['adminUid'] ?? a['adminId'] ?? '').toString();
    num? paise(String k) => a[k] is num ? a[k] as num : null;
    final amount = rupees(
      paise('amountPaise') ??
          paise('amountMinor') ??
          paise('requestedMinor') ??
          paise('netMinor'),
    );
    String affected = orgId.isNotEmpty
        ? (orgName(orgId) ?? unknownOrganization)
        : ((a['memberUid'] ?? '').toString().isNotEmpty
              ? 'A member'
              : 'A buyer');
    if (amount.isNotEmpty) affected = '$affected · $amount';

    final respondBy = _date(a['respondBy']);
    final created = _date(a['createdAt']);

    // A dispute is now also raised for ORGANIZATION (subscription) payments
    // and carries its phase (C3). The words follow both.
    var title = w?.title ?? 'A payment needs review';
    var why =
        w?.why ??
        'The payment system recorded something it could not settle on its '
            'own. Review it before treating the payment as complete.';
    var urgency = w?.urgency ?? OpsUrgency.high;
    if (kind == 'dispute') {
      final orgPayment =
          orgId.isNotEmpty &&
          (a['settlementId'] ?? '').toString().isEmpty &&
          (a['memberUid'] ?? '').toString().isEmpty;
      final whose = orgPayment
          ? "an organization's subscription payment to the platform"
          : 'a payment';
      switch ((a['phase'] ?? 'opened').toString()) {
        case 'won':
          title = 'A chargeback was decided in the platform\'s favour';
          why =
              'The dispute on $whose was won: the money stays with the '
              'platform. Nothing else to do.';
          urgency = OpsUrgency.info;
        case 'lost':
          title = 'A chargeback was lost — the money was taken back';
          why = orgPayment
              ? 'The bank returned the organization\'s subscription payment to '
                    'the payer. Their access was NOT changed automatically — '
                    'decide whether it should continue, and check the receipt.'
              : 'The bank returned the money to the payer. Check whether the '
                    'gym\'s payout still includes it.';
          urgency = OpsUrgency.high;
        case 'closed':
          title = 'A chargeback was closed';
          why =
              'The dispute on $whose is closed. Check the Razorpay dashboard '
              'for how it ended.';
          urgency = OpsUrgency.attention;
        default:
          if (orgPayment) {
            why =
                'The organization\'s bank is disputing its subscription '
                'payment to the platform. If nobody responds by the deadline, '
                'the money is lost by default — respond in the Razorpay '
                'dashboard. The organization\'s access is not changed '
                'automatically.';
          }
      }
    }

    return OpsItem(
      id: 'payment:$id',
      recordId: id,
      orgId: orgId.isEmpty ? null : orgId,
      source: OpsSource.paymentAlert,
      urgency: urgency,
      status: status,
      title: title,
      why: why,
      affected: affected,
      when: kind == 'dispute' && respondBy != null ? respondBy : created,
      whenLabel: kind == 'dispute' && respondBy != null
          ? 'Respond by'
          : 'Raised',
      primary: resolved
          ? const OpsAction.navigate('Open Revenue', OpsNav.revenue)
          : (status == OpsItemStatus.informational
                ? const OpsAction.resolve('Dismiss')
                : const OpsAction.resolve()),
      secondary: [
        if (!resolved && w?.navIndex != null)
          OpsAction.navigate(w!.navLabel, w.navIndex),
      ],
      resolutionNote: (a['resolutionNote'] ?? '').toString(),
      resolvedAt: _date(a['resolvedAt']),
      technical: [
        MapEntry('Alert kind', kind.isEmpty ? 'unknown' : kind),
        for (final k in const [
          'orderId',
          'paymentId',
          'disputeId',
          'refundId',
          'settlementId',
          'historyDocId',
          'intentId',
          'phase',
          'fullyRefunded',
          'isCurrentPayment',
          'planId',
          'type',
          'reason',
          'reasonCode',
          'description',
          'payoutRail',
          'payoutIdempotencyKey',
          'railPayoutId',
          'gatewayEventId',
        ])
          if ((a[k] ?? '').toString().isNotEmpty) MapEntry(k, a[k].toString()),
        if (a['issues'] is List)
          MapEntry('Issues', (a['issues'] as List).join(', ')),
        if (orgId.isNotEmpty) MapEntry('Organization id', orgId),
        if (amount.isNotEmpty) MapEntry('Amount', amount),
        MapEntry('Raised', OpsTime.exact(created)),
        MapEntry('Record id', id),
      ],
    );
  }

  /// `quotaAlerts/{adminUid}` → item (self-healing; no writer, so no resolve).
  static OpsItem fromQuotaAlert(
    Map<String, dynamic> q, {
    required String? Function(String uid) orgName,
  }) {
    final id = (q['id'] ?? q['adminUid'] ?? '').toString();
    final name = orgName(id) ?? unknownOrganization;
    final violations = <String>[];
    if (q['violations'] is List) {
      for (final v in q['violations'] as List) {
        if (v is Map) {
          final res = _resourceWord((v['resource'] ?? '').toString());
          violations.add('${v['used']} of ${v['limit']} $res');
        }
      }
    }
    return OpsItem(
      id: 'quota:$id',
      recordId: id,
      source: OpsSource.quota,
      urgency: OpsUrgency.attention,
      status: OpsItemStatus.needsAttention,
      title: '$name is over its plan limits',
      why: violations.isEmpty
          ? 'The organization is using more than its plan allows. Offer an '
                'upgrade, or enforce the limit.'
          : 'Using ${violations.join(', ')}. Offer an upgrade, or enforce the '
                'limit. This clears itself once usage drops.',
      affected: name,
      when: _date(q['checkedAt']) ?? _date(q['firstDetectedAt']),
      whenLabel: 'Last checked',
      primary: const OpsAction.navigate(
        'Review organization',
        OpsNav.organizations,
      ),
      technical: [
        MapEntry('Organization id', id),
        for (final v in violations) MapEntry('Over limit', v),
        MapEntry('First detected', OpsTime.exact(_date(q['firstDetectedAt']))),
        MapEntry('Last checked', OpsTime.exact(_date(q['checkedAt']))),
      ],
    );
  }

  static String _resourceWord(String r) => switch (r) {
    'trainers' => 'trainers',
    'clients' => 'members',
    'workoutPlans' => 'workout plans',
    'dietPlans' => 'diet plans',
    'exercises' => 'exercises',
    _ => r,
  };

  /// Organization-derived rows (from the live `admins` list).
  static List<OpsItem> fromOrganizations(
    List<AdminModel> admins, {
    required DateTime now,
  }) {
    final out = <OpsItem>[];
    final pending = admins
        .where((a) => a.status.toLowerCase() == 'pending')
        .toList();
    if (pending.isNotEmpty) {
      out.add(
        OpsItem(
          id: 'orgs:pending',
          source: OpsSource.organizations,
          urgency: OpsUrgency.attention,
          status: OpsItemStatus.needsAttention,
          title: pending.length == 1
              ? '${_name(pending.first)} is waiting for approval'
              : '${pending.length} organizations are waiting for approval',
          why: 'New organizations cannot start working until you approve them.',
          affected: _names(pending),
          when: pending
              .map((a) => a.createdAt)
              .reduce((a, b) => a.isBefore(b) ? a : b),
          whenLabel: 'Waiting since',
          primary: const OpsAction.navigate(
            'Review approvals',
            OpsNav.organizations,
            orgFilter: 'pending',
          ),
          count: pending.length,
        ),
      );
    }

    final lapsed = admins.where((a) {
      final exp = a.planExpiry;
      return a.status.toLowerCase() == 'active' &&
          !a.isSubscriptionActive &&
          exp != null &&
          exp.isBefore(now);
    }).toList();
    if (lapsed.isNotEmpty) {
      out.add(
        OpsItem(
          id: 'orgs:lapsed',
          source: OpsSource.organizations,
          urgency: OpsUrgency.high,
          status: OpsItemStatus.needsAttention,
          title: lapsed.length == 1
              ? "${_name(lapsed.first)}'s subscription has expired"
              : '${lapsed.length} organizations have expired subscriptions',
          why:
              'They can no longer add trainers, members or plans. Follow up on '
              'renewal, or they will quietly churn.',
          affected: _names(lapsed),
          when: lapsed
              .map((a) => a.planExpiry!)
              .reduce((a, b) => a.isBefore(b) ? a : b),
          whenLabel: 'Expired',
          primary: const OpsAction.navigate(
            'Review organizations',
            OpsNav.organizations,
            orgFilter: 'active',
          ),
          count: lapsed.length,
        ),
      );
    }

    final expiring = admins.where((a) {
      final exp = a.planExpiry;
      if (!a.isSubscriptionActive || exp == null) return false;
      if (exp.isBefore(now)) return false;
      final days = DateTime(
        exp.year,
        exp.month,
        exp.day,
      ).difference(DateTime(now.year, now.month, now.day)).inDays;
      return days <= 7;
    }).toList();
    if (expiring.isNotEmpty) {
      out.add(
        OpsItem(
          id: 'orgs:expiring',
          source: OpsSource.organizations,
          urgency: OpsUrgency.attention,
          status: OpsItemStatus.needsAttention,
          title: expiring.length == 1
              ? "${_name(expiring.first)}'s subscription ends within 7 days"
              : '${expiring.length} subscriptions end within 7 days',
          why: 'Reach out before they lapse to keep the renewal.',
          affected: _names(expiring),
          when: expiring
              .map((a) => a.planExpiry!)
              .reduce((a, b) => a.isBefore(b) ? a : b),
          whenLabel: 'First expiry',
          primary: const OpsAction.navigate(
            'Review organizations',
            OpsNav.organizations,
            orgFilter: 'active',
          ),
          count: expiring.length,
        ),
      );
    }

    final moderated = admins.where((a) {
      final s = a.status.toLowerCase();
      return s == 'blocked' || s == 'warning';
    }).toList();
    if (moderated.isNotEmpty) {
      out.add(
        OpsItem(
          id: 'orgs:moderated',
          source: OpsSource.organizations,
          urgency: OpsUrgency.info,
          status: OpsItemStatus.informational,
          title: moderated.length == 1
              ? '${_name(moderated.first)} is currently warned or blocked'
              : '${moderated.length} organizations are currently warned or blocked',
          why:
              'A reminder of who is under moderation. Nothing to do unless you '
              'want to lift it.',
          affected: _names(moderated),
          when: moderated
              .map((a) => a.statusUpdatedAt)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (m, d) => m == null || d.isAfter(m) ? d : m,
              ),
          whenLabel: 'Since',
          primary: const OpsAction.navigate(
            'Open Organizations',
            OpsNav.organizations,
            orgFilter: 'blocked',
          ),
          count: moderated.length,
        ),
      );
    }
    return out;
  }

  /// Support-derived rows.
  static List<OpsItem> fromSupport(
    List<OrgFeedbackModel> feedback,
    List<OrgReviewModel> reviews, {
    required String? Function(String uid) orgName,
  }) {
    final out = <OpsItem>[];
    final open = feedback.where((f) => !f.isResolved).toList();
    if (open.isNotEmpty) {
      final complaints = open
          .where((f) => f.category.toLowerCase() == 'complaint')
          .length;
      final names = open
          .map(
            (f) => f.adminName.isNotEmpty
                ? f.adminName
                : (orgName(f.adminId) ?? unknownOrganization),
          )
          .toSet()
          .toList();
      out.add(
        OpsItem(
          id: 'support:open',
          source: OpsSource.support,
          urgency: complaints > 0 ? OpsUrgency.high : OpsUrgency.attention,
          status: OpsItemStatus.needsAttention,
          title: open.length == 1
              ? '${names.first} is waiting for a support reply'
              : '${open.length} support requests are waiting for a reply',
          why: complaints > 0
              ? '${plural(complaints, 'complaint')} among them. Unanswered '
                    'complaints are how organizations leave.'
              : 'Organizations are waiting to hear back from you.',
          affected: _join(names),
          when: open
              .map((f) => f.createdAt)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (m, d) => m == null || d.isBefore(m) ? d : m,
              ),
          whenLabel: 'Oldest waiting since',
          primary: const OpsAction.navigate('Open Support', OpsNav.support),
          count: open.length,
        ),
      );
    }
    final critical = reviews.where((r) => r.isCritical).toList();
    if (critical.isNotEmpty) {
      final names = critical
          .map((r) => orgName(r.adminId) ?? unknownOrganization)
          .toSet()
          .toList();
      out.add(
        OpsItem(
          id: 'support:reviews',
          source: OpsSource.support,
          urgency: OpsUrgency.attention,
          status: OpsItemStatus.needsAttention,
          title:
              '${plural(critical.length, 'member review')} rated 2 stars or less',
          why:
              'Low ratings are an early sign an organization is at risk of '
              'losing members.',
          affected: _join(names),
          when: critical
              .map((r) => r.lastActivity)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (m, d) => m == null || d.isAfter(m) ? d : m,
              ),
          whenLabel: 'Latest',
          primary: const OpsAction.navigate('View reviews', OpsNav.support),
          count: critical.length,
        ),
      );
    }
    return out;
  }

  /// Announcement-derived rows.
  static List<OpsItem> fromAnnouncements(
    List<PlatformAnnouncementModel> anns, {
    required DateTime now,
  }) {
    final out = <OpsItem>[];
    final failed = anns
        .where((a) => a.statusEnum == AnnouncementStatus.failed)
        .toList();
    if (failed.isNotEmpty) {
      out.add(
        OpsItem(
          id: 'announcements:failed',
          source: OpsSource.announcements,
          urgency: OpsUrgency.high,
          status: OpsItemStatus.needsAttention,
          title: failed.length == 1
              ? 'The announcement "${failed.first.title}" failed to send'
              : '${failed.length} announcements failed to send',
          why:
              'Recipients did not get the message. Review the error and resend.',
          affected: _join(failed.map((a) => a.title).toList()),
          when: failed
              .map((a) => a.sentAt ?? a.queuedAt)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (m, d) => m == null || d.isAfter(m) ? d : m,
              ),
          whenLabel: 'Failed',
          primary: const OpsAction.navigate(
            'Open Announcements',
            OpsNav.announcements,
          ),
          count: failed.length,
          technical: [
            for (final a in failed)
              if ((a.lastError ?? '').isNotEmpty)
                MapEntry(a.title, a.lastError!),
          ],
        ),
      );
    }
    final stranded = anns.where((a) => a.isScheduled).toList();
    if (stranded.isNotEmpty) {
      out.add(
        OpsItem(
          id: 'announcements:stranded',
          source: OpsSource.announcements,
          urgency: OpsUrgency.attention,
          status: OpsItemStatus.needsAttention,
          title:
              '${plural(stranded.length, 'scheduled announcement')} will never send',
          why:
              'Scheduling is no longer supported, so these will sit forever. '
              'Send them now, or delete them.',
          affected: _join(stranded.map((a) => a.title).toList()),
          when: stranded
              .map((a) => a.scheduledAt)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (m, d) => m == null || d.isBefore(m) ? d : m,
              ),
          whenLabel: 'Was due',
          primary: const OpsAction.navigate(
            'Open Announcements',
            OpsNav.announcements,
          ),
          count: stranded.length,
        ),
      );
    }
    final stalled = anns.where((a) {
      if (!a.isQueued) return false;
      final q = a.queuedAt;
      return q != null && now.difference(q) > const Duration(minutes: 15);
    }).toList();
    if (stalled.isNotEmpty) {
      out.add(
        OpsItem(
          id: 'announcements:stalled',
          source: OpsSource.announcements,
          urgency: OpsUrgency.high,
          status: OpsItemStatus.needsAttention,
          title:
              '${plural(stalled.length, 'announcement')} stuck while sending',
          why:
              'Queued more than 15 minutes ago and still not delivered — the '
              'sending service may be down.',
          affected: _join(stalled.map((a) => a.title).toList()),
          when: stalled
              .map((a) => a.queuedAt)
              .whereType<DateTime>()
              .fold<DateTime?>(
                null,
                (m, d) => m == null || d.isBefore(m) ? d : m,
              ),
          whenLabel: 'Queued',
          primary: const OpsAction.navigate(
            'Open Announcements',
            OpsNav.announcements,
          ),
          count: stalled.length,
        ),
      );
    }
    return out;
  }

  /// A data feed this screen depends on could not be read. Always a row —
  /// a blank list over an unreadable feed is the one lie this screen must
  /// never tell.
  static OpsItem feedUnavailable({
    required String key,
    required String feedName,
    required String hides,
    required OpsAction primary,
    OpsUrgency urgency = OpsUrgency.high,
  }) => OpsItem(
    id: 'feed:$key',
    source: OpsSource.feed,
    urgency: urgency,
    status: OpsItemStatus.needsAttention,
    title: "$feedName information couldn't be loaded",
    why:
        '$hides cannot be checked right now, so this screen may be '
        'missing problems. Nothing here is wrong with the platform itself '
        '— the console could not read the data.',
    affected: 'This screen',
    when: null,
    whenLabel: 'Noticed',
    primary: primary,
  );

  // ── ordering & filtering ─────────────────────────────────────────────────

  /// Most important first. Resolved rows ALWAYS sink below live ones (a
  /// handled P0 must not outrank an open P2); among live rows: urgency, then
  /// lifecycle (open before in-progress before informational), then newest,
  /// then widest.
  static int compare(OpsItem a, OpsItem b) {
    final ar = a.status == OpsItemStatus.resolved ? 1 : 0;
    final br = b.status == OpsItemStatus.resolved ? 1 : 0;
    if (ar != br) return ar.compareTo(br);
    final u = a.urgency.rank.compareTo(b.urgency.rank);
    if (u != 0) return u;
    final s = a.status.index.compareTo(b.status.index);
    if (s != 0) return s;
    final aw = a.when, bw = b.when;
    if (aw != null && bw != null && aw != bw) return bw.compareTo(aw);
    if (aw == null && bw != null) return 1;
    if (aw != null && bw == null) return -1;
    return b.count.compareTo(a.count);
  }

  static List<OpsItem> sorted(Iterable<OpsItem> items) =>
      items.toList()..sort(compare);

  /// Text + urgency filter. An empty query matches everything.
  static List<OpsItem> filter(
    Iterable<OpsItem> items, {
    String query = '',
    OpsUrgency? urgency,
  }) {
    final q = query.trim().toLowerCase();
    return items.where((i) {
      if (urgency != null && i.urgency != urgency) return false;
      if (q.isEmpty) return true;
      return i.searchable.contains(q);
    }).toList();
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  static String _name(AdminModel a) =>
      a.organizationName.isNotEmpty ? a.organizationName : a.name;

  static String _names(List<AdminModel> list) =>
      _join(list.map(_name).toList());

  static String _join(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length <= 3) return names.join(', ');
    return '${names.take(3).join(', ')} and ${names.length - 3} more';
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    // Firestore Timestamp without importing cloud_firestore here.
    try {
      final toDate = (v as dynamic).toDate;
      if (toDate is Function) return toDate() as DateTime;
    } catch (_) {}
    return null;
  }
}
