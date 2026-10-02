// ORGANIZATIONS — the words, rules and orderings of the organization
// command center. PURE: no Firebase, no widgets, so every rule the screen
// relies on is asserted by a unit test rather than by reading a widget tree.
//
// WHAT AN ORGANIZATION IS. `admins/{uid}` is the organization record: one
// document that is simultaneously the OWNER's account (name, email, phone,
// sign-in) and the ORGANIZATION (organizationName, address, GST/PAN,
// moderation status, subscription, limits, seat lists). Everything else hangs
// off that uid: `trainers.assignedBy`, `clients.adminId`,
// `admin_payments_history.adminUid`, `audit_logs.targetId`,
// `access_requests.provisionedOrgUid`, `organizationProfiles/{uid}` (the
// member-facing storefront), `org_feedback.adminId`, `settlements.adminId`.
//
// WHO MAY CHANGE IT. Nobody writes the record from this console. The owner may
// edit their own profile fields; status, subscription, limits, seats and every
// moderation stamp are written ONLY by Cloud Functions (`setAdminStatus`,
// `grantSubscription`, `provisionOrganization`, `verifyAndActivateSubscription`,
// `refundPayment`, `expireSubscriptions`, `createTrainer`/`removeTrainer`), and
// the rules deny direct writes — founder included. This layer therefore
// describes exactly five founder actions and invents no sixth.
//
// "CAN OPERATE" IS ONE FORMULA, copied from `orgCanOperate()` in
// firestore.rules and `computeOrgActive` in the backend: status is not pending,
// not blocked, and `isSubscriptionActive` is true. It is the flag the rules
// read — not the expiry date. When the two disagree that is an ISSUE this layer
// reports, never a state it silently picks.

import '../../models/access_request_model.dart';
import '../../models/admin_model.dart';
import '../../models/audit_log_model.dart';
import '../../models/clints_model.dart';
import '../../models/subscription_model.dart';
import 'ops_language.dart' show OpsLanguage;
import 'saas_onboarding_service.dart' show GrantResult;
import '../../models/trainer_model.dart';

// ═════════════════════════════════════════════════════════════════════════════
// STANDING — the moderation status, in words
// ═════════════════════════════════════════════════════════════════════════════

enum OrgStanding { awaitingApproval, approved, warning, blocked, unknown }

extension OrgStandingX on OrgStanding {
  String get label => switch (this) {
    OrgStanding.awaitingApproval => 'Awaiting approval',
    OrgStanding.approved => 'Approved',
    OrgStanding.warning => 'Approved · warning on file',
    OrgStanding.blocked => 'Blocked',
    OrgStanding.unknown => 'Unrecognised status',
  };

  String get meaning => switch (this) {
    OrgStanding.awaitingApproval =>
      'The account exists but the platform has not approved it. The owner can '
          'sign in but cannot operate — no trainers, members or plans — until '
          'you approve.',
    OrgStanding.approved =>
      'Approved by the platform. It operates as long as a subscription is '
          'active.',
    OrgStanding.warning =>
      'Approved and operating normally. An internal warning is on file; the '
          'organization is not told and nothing is restricted.',
    OrgStanding.blocked =>
      'The owner cannot sign in, the organization cannot change anything, its '
          'trainers are paused and its storefront is hidden.',
    OrgStanding.unknown =>
      'The stored status is not one this console knows. Nothing here is '
          'certain about what the organization can do.',
  };

  /// The raw value `setAdminStatus` accepts for this standing (null for
  /// unknown). `approved` is normalised to `active` by the model.
  String? get backendStatus => switch (this) {
    OrgStanding.awaitingApproval => 'pending',
    OrgStanding.approved => 'active',
    OrgStanding.warning => 'warning',
    OrgStanding.blocked => 'blocked',
    OrgStanding.unknown => null,
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// SUBSCRIPTION — what the record says about the plan, dated honestly
// ═════════════════════════════════════════════════════════════════════════════

enum SubscriptionState {
  /// Never subscribed, or the subscription lapsed and the flag is off.
  none,
  active,

  /// Active and ending within [OrganizationLanguage.expiringSoonDays].
  expiringSoon,

  /// Flag says active but the end date has passed — the hourly sweep has not
  /// flipped it (or failed). The organization is STILL operating.
  activePastEnd,

  /// Flag says active but there is no READABLE plan end date. The hourly
  /// sweep reads only `planExpiry` and skips a record it cannot date, so this
  /// subscription never expires (ORPH-2).
  activeNoEndDate,

  /// Flag is OFF although the plan end date lies ahead: switched off while
  /// paid-through (ORPH-1). Nothing in the platform turns the flag back on
  /// except a new grant — which would stack a new term on top of the days
  /// already paid for. Never "no subscription".
  offBeforeEnd,
}

enum SubscriptionSource { online, manual, none }

/// Client-side preview of the pricing evidence (see
/// OrganizationLanguage.grantPreview). Display only; the server recomputes.
class GrantPreview {
  final String basis; // plan_term | negotiated_term | unpriced
  final double? listPrice;
  final int? listTermMonths;
  final double collected;
  final double? discount;
  final double? overpayment;

  /// The sold term the list price belongs to (`monthly` | `yearly` |
  /// `custom`), when known — what the server stamps as `pricing.term`.
  final String? term;
  const GrantPreview({
    required this.basis,
    required this.listPrice,
    required this.listTermMonths,
    required this.collected,
    required this.discount,
    required this.overpayment,
    this.term,
  });
  bool get isComped => collected == 0;
  bool get differsFromList =>
      basis == 'plan_term' && ((discount ?? 0) > 0 || (overpayment ?? 0) > 0);
}

class SubscriptionView {
  final SubscriptionState state;
  final String planName;
  final DateTime? endsAt;
  final DateTime? startedAt;

  /// Calendar days until [endsAt]; negative when past. Null without a date.
  final int? daysLeft;

  /// The end date on the LAST PAYMENT (`subscription.expiry`), shown beside
  /// a missing plan end date. Never used to decide the state: the expiry
  /// sweep reads `planExpiry` alone.
  final DateTime? lastPaymentEndsAt;
  final SubscriptionSource source;
  final double? amount;
  final int? months;
  final String? reference;

  const SubscriptionView({
    required this.state,
    required this.planName,
    required this.endsAt,
    required this.startedAt,
    required this.daysLeft,
    required this.source,
    this.lastPaymentEndsAt,
    this.amount,
    this.months,
    this.reference,
  });

  bool get isActiveFlag =>
      state != SubscriptionState.none &&
      state != SubscriptionState.offBeforeEnd;

  String get label => switch (state) {
    SubscriptionState.none => 'No active subscription',
    SubscriptionState.active => 'Active',
    SubscriptionState.expiringSoon =>
      'Ends in $daysLeft day${daysLeft == 1 ? '' : 's'}',
    SubscriptionState.activePastEnd => 'Marked active but end date has passed',
    SubscriptionState.activeNoEndDate => 'Marked active with no end date',
    SubscriptionState.offBeforeEnd => 'Switched off before its end date',
  };

  String get sourceLabel => switch (source) {
    SubscriptionSource.online => 'Paid online (Razorpay)',
    SubscriptionSource.manual => 'Recorded by the team',
    SubscriptionSource.none => 'Not recorded',
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// ISSUES — what needs attention, from authoritative signals only
// ═════════════════════════════════════════════════════════════════════════════

enum OrgIssueSeverity { critical, attention, info }

extension OrgIssueSeverityX on OrgIssueSeverity {
  String get label => switch (this) {
    OrgIssueSeverity.critical => 'Urgent',
    OrgIssueSeverity.attention => 'Needs attention',
    OrgIssueSeverity.info => 'For information',
  };
}

class OrgIssue {
  /// Stable machine key, for tests and de-duplication.
  final String code;
  final OrgIssueSeverity severity;
  final String title;
  final String why;
  final String whatToDo;

  /// The founder action that resolves it, when one exists.
  final OrgAction? offers;

  /// Extra machine-readable context (incident types, alert kinds).
  final List<String> tags;

  const OrgIssue({
    required this.code,
    required this.severity,
    required this.title,
    required this.why,
    required this.whatToDo,
    this.offers,
    this.tags = const [],
  });

  bool get needsAttention => severity != OrgIssueSeverity.info;
}

// ═════════════════════════════════════════════════════════════════════════════
// ACTIONS — the five things a founder can do, and what each one means
// ═════════════════════════════════════════════════════════════════════════════

/// [reapplyEffects] is not a status change: it re-runs the integrity legs
/// of the CURRENT status (`reapplyAdminStatusEffects`, C6). It is offered
/// only from an issue that it resolves — never in the header row.
enum OrgAction { approve, warn, block, reactivate, grant, reapplyEffects }

extension OrgActionX on OrgAction {
  String get label => switch (this) {
    OrgAction.approve => 'Approve',
    OrgAction.warn => 'Issue warning',
    OrgAction.block => 'Block',
    OrgAction.reactivate => 'Reactivate',
    OrgAction.grant => 'Record payment / change plan',
    OrgAction.reapplyEffects => 'Re-apply status effects',
  };

  bool get isDestructive => this == OrgAction.block;
}

/// Everything a confirmation dialog must say before the button is pressed.
class OrgActionPlan {
  final OrgAction action;
  final String title;

  /// WHAT will happen, one sentence.
  final String what;

  /// WHO is affected.
  final String who;

  /// What CHANGES for the organization and its people.
  final List<String> consequences;
  final String reversibility;
  final bool requiresReason;

  /// Destructive: the founder types the organization name to continue.
  final bool requiresTypedName;
  final String confirmLabel;

  const OrgActionPlan({
    required this.action,
    required this.title,
    required this.what,
    required this.who,
    required this.consequences,
    required this.reversibility,
    required this.requiresReason,
    required this.requiresTypedName,
    required this.confirmLabel,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// RECEIPTS — one payment record, honestly classified
// ═════════════════════════════════════════════════════════════════════════════

enum ReceiptState {
  paid,
  recordedManually,

  /// Written by the RETIRED client-side checkout: the money came through the
  /// gateway, but the receipt carries no server-verified gateway id (ORG-20).
  legacyGateway,
  unverified,
  partiallyRefunded,
  refunded,
}

extension ReceiptStateX on ReceiptState {
  String get label => switch (this) {
    ReceiptState.paid => 'Paid',
    ReceiptState.recordedManually => 'Recorded by the team',
    ReceiptState.legacyGateway => 'Paid online (legacy checkout)',
    ReceiptState.unverified => 'Not confirmed by the gateway',
    ReceiptState.partiallyRefunded => 'Partly refunded',
    ReceiptState.refunded => 'Refunded',
  };

  String get meaning => switch (this) {
    ReceiptState.paid => 'The gateway confirmed the money was captured.',
    ReceiptState.recordedManually =>
      'The team recorded a payment collected outside the platform. The '
          'reference is the evidence; no gateway confirmation exists.',
    ReceiptState.legacyGateway =>
      'Paid through the gateway by the organization\'s own app, before the '
          'server recorded receipts. It carries no server-verified gateway '
          'id, so it cannot be refunded from here — use the Razorpay '
          'dashboard.',
    ReceiptState.unverified =>
      'The plan was activated before the gateway confirmed capture. The money '
          'may not have arrived — check the gateway before treating this as '
          'revenue.',
    ReceiptState.partiallyRefunded => 'Part of this payment was returned.',
    ReceiptState.refunded => 'The whole payment was returned.',
  };
}

// ═════════════════════════════════════════════════════════════════════════════
// EVENTS — one line of history, from a source that recorded it
// ═════════════════════════════════════════════════════════════════════════════

enum OrgEventKind { admin, payment, system, origin, record }

extension OrgEventKindX on OrgEventKind {
  String get label => switch (this) {
    OrgEventKind.admin => 'Platform action',
    OrgEventKind.payment => 'Payment',
    OrgEventKind.system => 'Automatic',
    OrgEventKind.origin => 'Access request',
    OrgEventKind.record => 'Record',
  };
}

class OrgEvent {
  final DateTime? at;
  final OrgEventKind kind;
  final String title;
  final String detail;

  /// Resolved actor words: "you", a colleague's name, "the owner", "the
  /// system", or "" when the source did not record one.
  final String actor;
  final Map<String, dynamic> technical;

  /// Which source produced it, for the technical expander.
  final String source;

  const OrgEvent({
    required this.at,
    required this.kind,
    required this.title,
    this.detail = '',
    this.actor = '',
    this.technical = const {},
    this.source = '',
  });
}

/// Who approved an organization, derived from the audit trail (ORG-5).
class OrgApproval {
  final String actorUid;
  final DateTime? at;

  /// How it was derived, in words ("approved from awaiting approval", …).
  final String how;
  const OrgApproval({
    required this.actorUid,
    required this.at,
    required this.how,
  });
}

/// One term a plan SELLS, with the list price the backend will measure a
/// grant of exactly that many months against (CONTRACTS C4).
class SoldTerm {
  /// `monthly` | `yearly` | `plan` (the document's own live term).
  final String key;
  final String label;
  final int months;

  /// Null when the plan carries no price for this term.
  final double? listPrice;

  /// `monthly` | `yearly` | `custom` — what the server stamps as
  /// `pricing.term`.
  final String term;
  const SoldTerm({
    required this.key,
    required this.label,
    required this.months,
    required this.listPrice,
    required this.term,
  });
}

/// The list the server resolves for a grant of N months.
class GrantList {
  final String? term;
  final double? listPrice;
  final int? listTermMonths;
  const GrantList({this.term, this.listPrice, this.listTermMonths});
}

// ═════════════════════════════════════════════════════════════════════════════
// THE LANGUAGE
// ═════════════════════════════════════════════════════════════════════════════

class OrganizationLanguage {
  OrganizationLanguage._();

  /// A subscription ending inside this window is called out. Same window the
  /// Dashboard's "expiring" list uses, so the two screens agree.
  static const int expiringSoonDays = 7;

  /// "Recently created" for the list tile.
  static const int recentDays = 30;

  // ── identity ──────────────────────────────────────────────────────────────

  /// The name the operator recognises. Falls back to the owner's name and
  /// says so through [nameIsOwnerFallback].
  static String displayName(AdminModel a) {
    final org = a.organizationName.trim();
    if (org.isNotEmpty) return org;
    final owner = a.name.trim();
    return owner.isNotEmpty ? owner : 'Unnamed organization';
  }

  static bool nameIsOwnerFallback(AdminModel a) =>
      a.organizationName.trim().isEmpty && a.name.trim().isNotEmpty;

  static String ownerName(AdminModel a) =>
      a.name.trim().isEmpty ? 'Owner name not recorded' : a.name.trim();

  /// The email ON THE ORGANIZATION RECORD. The owner can edit it (the rules
  /// do not denylist `email`), so it is never called the sign-in identity:
  /// the Auth account's email lives in Firebase Authentication, which the
  /// console cannot read.
  static String ownerEmail(AdminModel a) =>
      a.email.trim().isEmpty ? 'No email on the record' : a.email.trim();

  /// Profile fields the OWNER can rewrite on their own record. Shown to the
  /// founder as what the record says — never as platform facts.
  static const List<String> ownerEditableFields = [
    'name',
    'email',
    'phone',
    'address',
    'area',
    'state',
    'pincode',
    'gstNumber',
    'panNumber',
    'spokenLanguages',
    'profilePicUrl',
    'metadata',
    'createdAt',
    'lastLogin',
  ];

  static String initial(AdminModel a) {
    final n = displayName(a).trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  static String id(AdminModel a) => a.uid.isNotEmpty ? a.uid : a.docId;

  /// The label for an organization known only by its uid — the shape every
  /// money record uses (`admin_payments_history.adminUid`,
  /// `settlements.adminId`, `audit_logs.targetId`).
  ///
  /// 🔴 WHY THIS EXISTS. The Revenue screen rendered `s.adminUid` verbatim, so
  /// "Top Paying Admins" and every transaction row showed a raw Firebase uid.
  /// On the emulator's seeded ids that merely looked odd ("org-iron-temple");
  /// in production EVERY organization uid is a 28-character token like
  /// `9otLbZLeNz23l6kiCWuGsQKBNR6Z`, so the one screen that answers "who is
  /// paying us" could not name a single customer. Observed 2026-09-09.
  ///
  /// An id that matches no known organization is NOT silently prettified — the
  /// founder is told it is unknown and still shown enough of the id to trace it.
  static String labelForUid(String uid, Iterable<AdminModel> organizations) {
    final id = uid.trim();
    if (id.isEmpty) return 'Organization not recorded';
    for (final a in organizations) {
      if (a.uid == id || a.docId == id) return displayName(a);
    }
    final short = id.length <= 10 ? id : '${id.substring(0, 8)}…';
    return 'Unknown organization ($short)';
  }

  // ── standing ──────────────────────────────────────────────────────────────

  static OrgStanding standingOf(AdminModel a) =>
      switch (a.status.toLowerCase()) {
        'pending' => OrgStanding.awaitingApproval,
        'active' || 'approved' => OrgStanding.approved,
        'warning' => OrgStanding.warning,
        'blocked' => OrgStanding.blocked,
        _ => OrgStanding.unknown,
      };

  /// `orgCanOperate()` — the flag the rules read, not the date.
  static bool canOperate(AdminModel a) {
    final s = standingOf(a);
    return s != OrgStanding.awaitingApproval &&
        s != OrgStanding.blocked &&
        s != OrgStanding.unknown &&
        a.isSubscriptionActive;
  }

  static String operatingLine(AdminModel a) {
    if (canOperate(a)) {
      return 'Operating — can create trainers, members and plans';
    }
    final s = standingOf(a);
    if (s == OrgStanding.blocked) return 'Cannot operate — blocked';
    if (s == OrgStanding.awaitingApproval) {
      return 'Cannot operate — awaiting approval';
    }
    if (s == OrgStanding.unknown) return 'Operating state unknown';
    return 'Cannot operate — no active subscription';
  }

  // ── subscription ──────────────────────────────────────────────────────────

  static int _calendarDays(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    try {
      // Firestore Timestamp without importing the SDK here.
      final d = (v as dynamic).toDate();
      if (d is DateTime) return d;
    } catch (_) {}
    return null;
  }

  static SubscriptionView subscriptionOf(
    AdminModel a, {
    required DateTime now,
  }) {
    final sub = a.subscription ?? const <String, dynamic>{};
    final gateway = (sub['razorpayPaymentId'] ?? '').toString().trim();
    final reference = (sub['reference'] ?? '').toString().trim();
    final method = (sub['method'] ?? '').toString().trim();
    final source = gateway.isNotEmpty
        ? SubscriptionSource.online
        : (reference.isNotEmpty || method == 'manual')
        ? SubscriptionSource.manual
        : SubscriptionSource.none;
    // The PLAN end date alone decides the state: it is the only date the
    // hourly expiry sweep reads. The last payment's own end date is kept for
    // display beside a missing plan end date, never as a substitute — a
    // record with no readable `planExpiry` never expires, whatever its last
    // receipt says (ORPH-2).
    final endsAt = a.planExpiry;
    final lastPaymentEnd = _date(sub['expiry']);
    final startedAt = _date(sub['startedAt']);
    final days = endsAt == null ? null : _calendarDays(now, endsAt);
    final planName = (a.planName ?? sub['planName'] ?? '').toString().trim();

    SubscriptionState state;
    if (!a.isSubscriptionActive) {
      state = (endsAt != null && endsAt.isAfter(now))
          ? SubscriptionState.offBeforeEnd
          : SubscriptionState.none;
    } else if (endsAt == null) {
      state = SubscriptionState.activeNoEndDate;
    } else if (days! < 0) {
      state = SubscriptionState.activePastEnd;
    } else if (days <= expiringSoonDays) {
      state = SubscriptionState.expiringSoon;
    } else {
      state = SubscriptionState.active;
    }
    final amt = sub['amount'];
    final months = sub['months'];
    return SubscriptionView(
      state: state,
      planName: planName.isEmpty ? 'No plan recorded' : planName,
      endsAt: endsAt,
      startedAt: startedAt,
      daysLeft: days,
      source: source,
      lastPaymentEndsAt: lastPaymentEnd,
      amount: amt is num ? amt.toDouble() : null,
      months: months is num ? months.toInt() : null,
      reference: gateway.isNotEmpty
          ? gateway
          : (reference.isEmpty ? null : reference),
    );
  }

  static bool isExpiringSoon(AdminModel a, {required DateTime now}) =>
      subscriptionOf(a, now: now).state == SubscriptionState.expiringSoon;

  static bool isRecent(AdminModel a, {required DateTime now}) =>
      a.createdAtKnown && _calendarDays(a.createdAt, now) <= recentDays;

  // ── origin ────────────────────────────────────────────────────────────────

  /// How the organization entered the system. [accessRequestFound] is the
  /// server-only evidence: an `access_requests` record whose
  /// `provisionedOrgUid` is this organization (client writes to that
  /// collection are denied outright). `metadata.createdFrom` is OWNER-EDITABLE
  /// and is only ever quoted as what the record CLAIMS (ORG-9).
  static String originLine(AdminModel a, {bool accessRequestFound = false}) {
    if (accessRequestFound) return 'Created by the team from an access request';
    final from = (a.metadata?['createdFrom'] ?? '').toString();
    return switch (from) {
      'provisionOrganization' =>
        'The record claims it was created by the team from an access request '
            '(owner-editable field; no access request confirms it)',
      'registerAdmin' =>
        'The record says the owner self-registered (legacy sign-up; '
            'owner-editable field)',
      _ => 'How it entered the system was not recorded',
    };
  }

  static bool cameFromAccessRequest(AdminModel a) =>
      (a.metadata?['createdFrom'] ?? '') == 'provisionOrganization';

  // ── issues from the record alone (list level) ─────────────────────────────

  static List<OrgIssue> recordIssues(AdminModel a, {required DateTime now}) {
    final out = <OrgIssue>[];
    final standing = standingOf(a);
    final sub = subscriptionOf(a, now: now);

    // ORG-1. A record that is unreadable, or has fields of the wrong type,
    // stays in the list — skipping it would hide exactly the organization
    // that wrote it from moderation — and is FLAGGED so the blanks are never
    // mistaken for the owner's real data.
    if (a.unreadable) {
      out.add(
        const OrgIssue(
          code: 'unreadable_record',
          severity: OrgIssueSeverity.critical,
          title: 'This organization\'s record could not be read',
          why:
              'The document is in a shape the console cannot parse, so only '
              'its id (and its status, when readable) is shown. It is listed '
              'so it can still be found and moderated.',
          whatToDo:
              'Block it if it should not be on the platform; otherwise report '
              'it — the record needs a repair by the backend team.',
        ),
      );
    } else {
      final shown = a.malformedFields.where((f) => f != 'planExpiry').toList();
      if (shown.isNotEmpty) {
        final owner = shown.any(ownerEditableFields.contains);
        out.add(
          OrgIssue(
            code: 'malformed_fields',
            severity: OrgIssueSeverity.attention,
            title: 'Record has fields of the wrong type',
            why:
                'These fields are stored with a type the console cannot read, '
                'so they show as blank here: ${shown.join(', ')}.'
                '${owner ? ' The owner can write these fields directly, so this may be deliberate.' : ''}',
            whatToDo:
                'Nothing is blocked: the organization stays listed and every '
                'action still works. Ask the owner to re-save their profile; if '
                'it recurs, treat it as tampering.',
            tags: shown,
          ),
        );
      }
    }

    if (standing == OrgStanding.unknown) {
      out.add(
        OrgIssue(
          code: 'unknown_status',
          severity: OrgIssueSeverity.critical,
          title: 'Status "${a.status}" is not recognised',
          why:
              'The rules and the apps only understand pending, active, warning '
              'and blocked. This organization may be operating, or locked out, '
              'and the console cannot tell which.',
          whatToDo:
              'Set a known status: Reactivate approves it, Block locks it.',
        ),
      );
    }
    if (standing == OrgStanding.awaitingApproval) {
      out.add(
        const OrgIssue(
          code: 'awaiting_approval',
          severity: OrgIssueSeverity.attention,
          title: 'Awaiting your approval',
          why:
              'The owner can sign in but cannot add trainers, members or plans '
              'until the platform approves the organization.',
          whatToDo:
              'Approve it, or block it if it should not be on the platform.',
          offers: OrgAction.approve,
        ),
      );
    }
    if (sub.state == SubscriptionState.activePastEnd) {
      out.add(
        OrgIssue(
          code: 'active_past_end',
          severity: OrgIssueSeverity.critical,
          title:
              'Subscription is marked active but ended ${-sub.daysLeft!} day${sub.daysLeft == -1 ? '' : 's'} ago',
          why:
              'The hourly expiry sweep has not switched it off. Until it does, '
              'the organization keeps operating without a paid plan.',
          whatToDo:
              'Record the renewal if they have paid. Otherwise the sweep '
              'will end access; if this persists for more than a few hours, '
              'check the Operations Center.',
          offers: OrgAction.grant,
        ),
      );
    }
    if (sub.state == SubscriptionState.activeNoEndDate) {
      // ORPH-2. The hourly sweep reads ONLY `planExpiry` and skips a record
      // it cannot date: such an organization operates indefinitely.
      final unreadable = a.malformedFields.contains('planExpiry');
      final paymentEnd = sub.lastPaymentEndsAt;
      out.add(
        OrgIssue(
          code: 'active_no_end_date',
          severity: OrgIssueSeverity.critical,
          title: unreadable
              ? 'Subscription is marked active with an unreadable end date'
              : 'Subscription is marked active with no end date',
          why:
              '${unreadable ? 'The stored plan end date cannot be read — by this console or by the hourly expiry sweep. ' : 'The record has no plan end date. '}'
              '${paymentEnd != null ? 'The last payment says ${exact(paymentEnd)}, but the sweep reads only the plan end date. ' : ''}'
              'Nothing will ever expire this subscription: the organization '
              'keeps operating with no end. This is a data problem, not a plan.',
          whatToDo:
              'Record their next real payment — that writes a proper end date. '
              'If they have not paid, do not invent one: raise it with the '
              'backend team.',
          offers: OrgAction.grant,
        ),
      );
    }
    if (sub.state == SubscriptionState.offBeforeEnd) {
      // ORPH-1. Never "no subscription", and never "record a payment": a
      // grant extends from max(now, planExpiry), so it would charge again
      // for months stacked on top of days the organization already paid for.
      out.add(
        OrgIssue(
          code: 'switched_off_while_paid',
          // A blocked organization cannot operate anyway — the block is the
          // headline there; the flag still matters once it is reactivated.
          severity: standing == OrgStanding.blocked
              ? OrgIssueSeverity.info
              : OrgIssueSeverity.critical,
          title: 'Switched off although paid until ${exact(sub.endsAt)}',
          why:
              'The subscription flag is off, so the organization cannot '
              'operate, but its plan end date is ${exact(sub.endsAt)} '
              '(${relative(sub.endsAt, now: now)}). Nothing in the platform '
              'turns the flag back on except a new grant, and a new grant would '
              'ADD a term on top of those unused days.',
          whatToDo:
              'Do not record a new payment to fix this. Check History for a '
              'refund or an expiry that should not have happened and raise it '
              'with the backend team — restoring access needs a backend repair; '
              'the console has no action for it.',
        ),
      );
    }
    if (sub.state == SubscriptionState.expiringSoon) {
      out.add(
        OrgIssue(
          code: 'expiring_soon',
          severity: OrgIssueSeverity.attention,
          title: sub.daysLeft == 0
              ? 'Subscription ends today'
              : 'Subscription ends in ${sub.daysLeft} day${sub.daysLeft == 1 ? '' : 's'}',
          why:
              'When it ends the organization stops operating and its trainers '
              'are paused automatically.',
          whatToDo: 'Record the renewal payment once it is collected.',
          offers: OrgAction.grant,
        ),
      );
    }
    if ((standing == OrgStanding.approved || standing == OrgStanding.warning) &&
        sub.state == SubscriptionState.none) {
      out.add(
        const OrgIssue(
          code: 'approved_no_subscription',
          severity: OrgIssueSeverity.attention,
          title: 'Approved but cannot operate — no active subscription',
          why:
              'The owner can sign in, but every attempt to add a trainer, '
              'member or plan is refused until a subscription is active.',
          whatToDo: 'Record their payment to start or renew the plan.',
          offers: OrgAction.grant,
        ),
      );
    }
    if (standing == OrgStanding.blocked) {
      out.add(
        OrgIssue(
          code: 'blocked',
          severity: OrgIssueSeverity.info,
          title: 'Blocked',
          why: (a.statusReason ?? '').trim().isEmpty
              ? 'No reason was recorded.'
              : 'Reason on file: ${a.statusReason!.trim()}',
          whatToDo: 'Reactivate when the matter is resolved.',
          offers: OrgAction.reactivate,
        ),
      );
    }
    if (standing == OrgStanding.warning) {
      out.add(
        OrgIssue(
          code: 'warning_on_file',
          severity: OrgIssueSeverity.info,
          title: 'Internal warning on file',
          why: (a.statusReason ?? '').trim().isEmpty
              ? 'No reason was recorded.'
              : 'Reason on file: ${a.statusReason!.trim()}',
          whatToDo: 'Clear it with Reactivate, or escalate to Block.',
        ),
      );
    }
    if (a.email.trim().isEmpty && !a.unreadable) {
      out.add(
        const OrgIssue(
          code: 'no_owner_email',
          severity: OrgIssueSeverity.attention,
          title: 'No owner email on the organization record',
          why:
              'The record carries no email. The owner can edit this field, so '
              'it says nothing certain about the sign-in account — which lives '
              'in Firebase Authentication, where the console cannot look.',
          whatToDo:
              'Check the account in Firebase Auth; this cannot be fixed '
              'from here.',
        ),
      );
    }
    if (a.organizationName.trim().isEmpty && !a.unreadable) {
      out.add(
        const OrgIssue(
          code: 'no_org_name',
          severity: OrgIssueSeverity.info,
          title: 'No organization name — showing the owner\'s name instead',
          why: 'The owner has not named their organization yet.',
          whatToDo: 'Nothing required. The owner sets this in their app.',
        ),
      );
    }
    if (!a.createdAtKnown) {
      out.add(
        const OrgIssue(
          code: 'no_created_at',
          severity: OrgIssueSeverity.info,
          title: 'Creation date not recorded',
          why: 'A legacy record. Age-based views cannot place it.',
          whatToDo: 'Nothing required.',
        ),
      );
    }
    return out;
  }

  static bool needsAttention(AdminModel a, {required DateTime now}) =>
      recordIssues(a, now: now).any((i) => i.needsAttention);

  // ── issues from relationships (detail level) ──────────────────────────────

  static bool trainerIsRemoved(TrainerModel t) =>
      t.isDeleted || t.status == 'removed';

  static List<OrgIssue> relationshipIssues({
    required AdminModel admin,
    required List<TrainerModel> trainers,
    required List<ClientModel> members,
    required List<SubscriptionModel> receipts,
    required List<AccessRequestModel> requests,
    required Map<String, dynamic>? storefront,
    required DateTime now,
  }) {
    final out = <OrgIssue>[];
    final operating = canOperate(admin);
    final live = trainers.where((t) => !trainerIsRemoved(t)).toList();

    final seatIds = admin.trainerIds.toSet();
    final liveIds = live.map((t) => t.uid.isNotEmpty ? t.uid : t.docId).toSet();
    if (seatIds.length != liveIds.length || !seatIds.containsAll(liveIds)) {
      out.add(
        OrgIssue(
          code: 'trainer_roster_mismatch',
          severity: OrgIssueSeverity.attention,
          title: 'Trainer seat list does not match the trainer accounts',
          why:
              'The organization record lists ${seatIds.length} seat${seatIds.length == 1 ? '' : 's'} '
              'but ${liveIds.length} trainer account${liveIds.length == 1 ? '' : 's'} '
              'belong to it. Seat limits are enforced against the list, so the '
              'owner may be over or under their real usage.',
          whatToDo:
              'Nothing here fixes it; the backend re-syncs seats when a '
              'trainer is added, removed or restored. Report it if it persists.',
        ),
      );
    }

    final stale = live
        .where((t) => t.orgActive != null && t.orgActive != operating)
        .length;
    if (stale > 0) {
      out.add(
        OrgIssue(
          code: 'trainer_access_stale',
          severity: OrgIssueSeverity.critical,
          title:
              '$stale trainer${stale == 1 ? '' : 's'} ${stale == 1 ? 'has' : 'have'} the wrong access state',
          why: operating
              ? 'The organization can operate, but these trainers are still '
                    'paused in their app.'
              : 'The organization cannot operate, but these trainers still '
                    'appear active in their app (their writes are refused).',
          whatToDo:
              'The backend re-syncs trainers on every status or subscription '
              'change. "Re-apply status effects" re-runs that sync now for the '
              'current status, without changing it or notifying anyone.',
          offers: OrgAction.reapplyEffects,
        ),
      );
    }

    final orgTrainerIds = trainers
        .map((t) => t.uid.isNotEmpty ? t.uid : t.docId)
        .toSet();
    final foreign = members.where((m) {
      final t = (m.trainerId ?? '').trim();
      return t.isNotEmpty && !orgTrainerIds.contains(t) && t != id(admin);
    }).length;
    if (foreign > 0) {
      out.add(
        OrgIssue(
          code: 'member_coach_outside_org',
          severity: OrgIssueSeverity.attention,
          title:
              '$foreign member${foreign == 1 ? '' : 's'} assigned to a coach who is not in this organization',
          why:
              'The coach id on the member record does not match any trainer '
              'here. That member may be invisible to the team.',
          whatToDo: 'Ask the owner to reassign the member in their app.',
        ),
      );
    }

    if (storefront != null) {
      final sfActive = storefront['orgActive'];
      if (sfActive is bool && sfActive != operating) {
        out.add(
          OrgIssue(
            code: 'storefront_stale',
            severity: OrgIssueSeverity.attention,
            title: operating
                ? 'Storefront is hidden from Discover although the organization can operate'
                : 'Storefront is still listed in Discover although the organization cannot operate',
            why:
                'The member app lists an organization only when its storefront '
                'says it can operate. That flag is out of step with the record.',
            whatToDo:
                'It re-syncs on the next status or subscription change. '
                'If it persists, the lifecycle backfill (backend) repairs it.',
          ),
        );
      }
    } else {
      out.add(
        const OrgIssue(
          code: 'no_storefront',
          severity: OrgIssueSeverity.info,
          title: 'No storefront yet',
          why:
              'The owner has not built a member-facing page, so the organization '
              'cannot appear in Discover.',
          whatToDo: 'Nothing required. The owner builds it in their app.',
        ),
      );
    }

    if (admin.isSubscriptionActive && receipts.isEmpty) {
      out.add(
        const OrgIssue(
          code: 'no_receipt_for_subscription',
          severity: OrgIssueSeverity.info,
          title: 'No payment record for the current subscription',
          why:
              'The plan is active but no receipt names this organization. '
              'Legacy activations predate receipts.',
          whatToDo: 'Nothing required unless the plan was expected to be paid.',
        ),
      );
    }

    if (requests.length > 1) {
      out.add(
        OrgIssue(
          code: 'multiple_access_requests',
          severity: OrgIssueSeverity.attention,
          title:
              '${requests.length} access requests point to this organization',
          why:
              'Creation is meant to happen once per request. More than one '
              'record claiming this organization suggests a duplicate intake.',
          whatToDo:
              'Open Access Requests and check which one is the real origin.',
        ),
      );
    }

    final sub = admin.subscription;
    if (sub != null && admin.planExpiry != null) {
      final subEnd = _date(sub['expiry']);
      if (subEnd != null &&
          (subEnd.difference(admin.planExpiry!).inHours).abs() > 24) {
        out.add(
          const OrgIssue(
            code: 'end_dates_disagree',
            severity: OrgIssueSeverity.attention,
            title: 'Two end dates on the record disagree',
            why:
                'The plan end date and the last payment\'s end date differ by '
                'more than a day. The expiry sweep uses the plan end date.',
            whatToDo: 'Recording the next payment rewrites both.',
          ),
        );
      }
    }
    return out;
  }

  // ── issues from server-maintained signals (detail level) ──────────────────

  /// `quotaAlerts/{uid}` — written by the daily `checkQuotaCompliance` sweep
  /// and deleted by it when the organization comes back under its limits.
  /// The document existing IS the signal; `violations` says which limits.
  static List<OrgIssue> quotaIssues(Map<String, dynamic>? alert) {
    if (alert == null) return const [];
    final status = (alert['status'] ?? 'open').toString();
    if (status != 'open') return const [];
    final raw = alert['violations'];
    final parts = <String>[];
    if (raw is List) {
      for (final v in raw) {
        if (v is Map) {
          final r = (v['resource'] ?? '').toString();
          final used = v['used'];
          final limit = v['limit'];
          parts.add('$r $used of $limit');
        }
      }
    }
    return [
      OrgIssue(
        code: 'over_plan_limits',
        severity: OrgIssueSeverity.attention,
        title: 'Using more than the plan allows',
        why: parts.isEmpty
            ? 'The daily compliance check found usage above a plan limit.'
            : 'Detected by the daily compliance check: ${parts.join(', ')}. '
                  'Nothing is blocked automatically.',
        whatToDo:
            'Move them to a larger plan by recording a payment, or ask '
            'the owner to reduce usage. The check clears itself once they are '
            'within limits.',
        offers: OrgAction.grant,
      ),
    ];
  }

  /// Incident types whose failed leg `reapplyAdminStatusEffects` re-runs.
  static const Set<String> reapplyableIncidentTypes = {
    'org_cascade_failed',
    'org_auth_enforcement_failed',
  };

  /// `ops_incidents` whose `correlationId` is this organization — the
  /// backend records one when a status change's audit row, trainer cascade
  /// or sign-in enforcement failed. Every UNRESOLVED one is an issue: an
  /// incident an operator marked "in progress" (acknowledged) is seen, not
  /// fixed, so it keeps the Health verdict honest (ORG-11).
  static List<OrgIssue> incidentIssues(List<Map<String, dynamic>> incidents) {
    final unresolved = incidents
        .where((i) => (i['status'] ?? 'open').toString() != 'resolved')
        .toList();
    if (unresolved.isEmpty) return const [];
    final typeSet = unresolved
        .map((i) => (i['type'] ?? 'incident').toString())
        .toSet();
    final types = typeSet.join(', ');
    final inProgress = unresolved
        .where((i) => (i['status'] ?? '').toString() == 'acknowledged')
        .length;
    final reapply = typeSet.any(reapplyableIncidentTypes.contains);
    return [
      OrgIssue(
        code: 'failed_backend_operation',
        severity: OrgIssueSeverity.critical,
        title:
            '${plural(unresolved.length, 'backend operation')} on this organization failed and ${unresolved.length == 1 ? 'is' : 'are'} unresolved',
        why:
            'A status or subscription change did not fully apply ($types). '
            'What the owner, their trainers or the audit log see may be out '
            'of step with the record.'
            '${inProgress > 0 ? ' ${inProgress == unresolved.length ? 'It is' : '$inProgress of them are'} marked in progress in the Operations Center — seen, not fixed.' : ''}',
        whatToDo: reapply
            ? '"Re-apply status effects" re-runs trainer access and the '
                  'owner\'s sign-in enforcement for the CURRENT status — it '
                  'never changes the status and never notifies anyone. The '
                  'backend resolves these incidents when every step succeeds.'
            : 'Open the Operations Center, read the incident and resolve it '
                  'there.',
        offers: reapply ? OrgAction.reapplyEffects : null,
        tags: typeSet.toList(),
      ),
    ];
  }

  /// Payment alert kinds that mean money may have moved without a reliable
  /// record — always urgent on the organization's Health.
  static const Set<String> _urgentAlertKinds = {
    'refund_outcome_unknown',
    'refund_inconsistent',
    'refund_failed',
    'refund_at_gateway',
    'dispute',
    'charged_not_activated',
  };

  /// `paymentAlerts` naming this organization (`adminUid`) that are not
  /// resolved — refund follow-ups, gateway refunds, disputes (ORG-11). Read
  /// with a single-field query and filtered here, so it needs no index.
  static List<OrgIssue> paymentAlertIssues(List<Map<String, dynamic>> alerts) {
    final open = alerts
        .where((a) => (a['status'] ?? 'open').toString() != 'resolved')
        .toList();
    if (open.isEmpty) return const [];
    final kinds = <String>{
      for (final a in open) (a['kind'] ?? a['type'] ?? '').toString(),
    };
    final titles = {
      for (final k in kinds) OpsLanguage.paymentAlertTitle(k),
    }.toList();
    final urgent = kinds.any(_urgentAlertKinds.contains);
    return [
      OrgIssue(
        code: 'open_payment_alerts',
        severity: urgent
            ? OrgIssueSeverity.critical
            : OrgIssueSeverity.attention,
        title:
            '${plural(open.length, 'payment alert')} on this organization ${open.length == 1 ? 'is' : 'are'} unresolved',
        why: '${titles.join('; ')}.',
        whatToDo:
            'Review and resolve them in the Operations Center.'
            '${kinds.contains('refund_outcome_unknown') ? ' A refund whose outcome is unknown must be checked in the Razorpay dashboard before anything is refunded again.' : ''}',
        tags: kinds.toList(),
      ),
    ];
  }

  /// Seat usage against the plan, in words. Limits of 0 mean "not set".
  static String seatLine(int used, int limit, String noun) {
    if (limit <= 0) return '$used $noun · no limit set';
    if (limit >= 100000000) return '$used $noun · unlimited';
    final over = used > limit;
    return '$used of $limit $noun${over ? ' · OVER LIMIT' : ''}';
  }

  static List<OrgIssue> sortIssues(List<OrgIssue> issues) {
    final copy = [...issues];
    copy.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return copy;
  }

  // ── list: search, filter, sort ────────────────────────────────────────────

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool matches(AdminModel a, String query) {
    final q = _norm(query);
    if (q.isEmpty) return true;
    if (a.docId == query.trim() || a.uid == query.trim()) return true;
    return _norm(a.organizationName).contains(q) ||
        _norm(a.name).contains(q) ||
        _norm(a.email).contains(q) ||
        _norm(a.phone).replaceAll(' ', '').contains(q.replaceAll(' ', ''));
  }

  /// Filter keys. `active|pending|warning|blocked` are the raw-status keys the
  /// Dashboard's drill-downs already set; the rest are this screen's own.
  static const List<String> filterKeys = [
    'all',
    'attention',
    'operating',
    'pending',
    'noSubscription',
    'expiring',
    'active',
    'warning',
    'blocked',
    'recent',
  ];

  static bool matchesFilter(AdminModel a, String key, {required DateTime now}) {
    final standing = standingOf(a);
    return switch (key) {
      'all' => true,
      'attention' => needsAttention(a, now: now),
      'operating' => canOperate(a),
      'pending' => standing == OrgStanding.awaitingApproval,
      'noSubscription' =>
        !a.isSubscriptionActive &&
            standing != OrgStanding.blocked &&
            standing != OrgStanding.awaitingApproval,
      'expiring' => isExpiringSoon(a, now: now),
      'active' => a.status.toLowerCase() == 'active',
      'warning' => standing == OrgStanding.warning,
      'blocked' => standing == OrgStanding.blocked,
      'recent' => isRecent(a, now: now),
      _ => a.status.toLowerCase() == key.toLowerCase(),
    };
  }

  static String filterLabel(String key) => switch (key) {
    'all' => 'All organizations',
    'attention' => 'Needs attention',
    'operating' => 'Operating',
    'pending' => 'Awaiting approval',
    'noSubscription' => 'No active subscription',
    'expiring' => 'Ending within $expiringSoonDays days',
    'active' => 'Approved',
    'warning' => 'Warning on file',
    'blocked' => 'Blocked',
    'recent' => 'Created in the last $recentDays days',
    _ => 'Status "$key"',
  };

  static bool matchesPlan(AdminModel a, String plan) =>
      plan == 'all' || (a.planName ?? '').trim() == plan;

  static const List<String> sortKeys = [
    'attention',
    'newest',
    'oldest',
    'name',
    'expiry',
  ];

  static String sortLabel(String key) => switch (key) {
    'attention' => 'Needs attention first',
    'newest' => 'Newest first',
    'oldest' => 'Oldest first',
    'name' => 'Name A–Z',
    'expiry' => 'Subscription ending soonest',
    _ => key,
  };

  static int _rank(OrgIssueSeverity? s) =>
      s == null ? 3 : s.index; // critical 0, attention 1, info 2, none 3

  static OrgIssueSeverity? worstSeverity(
    AdminModel a, {
    required DateTime now,
  }) {
    OrgIssueSeverity? worst;
    for (final i in recordIssues(a, now: now)) {
      if (worst == null || i.severity.index < worst.index) worst = i.severity;
    }
    return worst;
  }

  static List<AdminModel> sorted(
    Iterable<AdminModel> orgs,
    String key, {
    required DateTime now,
  }) {
    final list = orgs.toList();
    // Undated (legacy) records rank FIRST in the date orders, never last: a
    // record with no date must stay visible in a long list, not be buried
    // under every dated one — the same rule as core/utils/list_ordering.dart.
    int byNewest(AdminModel x, AdminModel y) {
      if (x.createdAtKnown != y.createdAtKnown) {
        return x.createdAtKnown ? 1 : -1;
      }
      return y.createdAt.compareTo(x.createdAt);
    }

    int byName(AdminModel x, AdminModel y) =>
        _norm(displayName(x)).compareTo(_norm(displayName(y)));
    switch (key) {
      case 'oldest':
        list.sort((x, y) {
          if (x.createdAtKnown != y.createdAtKnown) {
            return x.createdAtKnown ? 1 : -1;
          }
          return x.createdAt.compareTo(y.createdAt);
        });
      case 'name':
        list.sort((x, y) {
          final c = byName(x, y);
          return c != 0 ? c : byNewest(x, y);
        });
      case 'expiry':
        list.sort((x, y) {
          final ex = subscriptionOf(x, now: now);
          final ey = subscriptionOf(y, now: now);
          final dx = ex.isActiveFlag ? ex.endsAt : null;
          final dy = ey.isActiveFlag ? ey.endsAt : null;
          if (dx == null && dy == null) return byNewest(x, y);
          if (dx == null) return 1;
          if (dy == null) return -1;
          final c = dx.compareTo(dy);
          return c != 0 ? c : byName(x, y);
        });
      case 'attention':
        // One issue pass per organization, not two per comparison: the old
        // comparator recomputed recordIssues 2·N·log N times per sort.
        // Computed per call with this `now`, so it is never stale.
        final rank = <AdminModel, int>{
          for (final a in list) a: _rank(worstSeverity(a, now: now)),
        };
        list.sort((x, y) {
          final c = rank[x]!.compareTo(rank[y]!);
          return c != 0 ? c : byNewest(x, y);
        });
      default: // newest
        list.sort(byNewest);
    }
    return list;
  }

  // ── actions ───────────────────────────────────────────────────────────────

  /// What the backend will accept for this organization right now.
  /// `setAdminStatus` accepts any of its four statuses on any record;
  /// `grantSubscription` refuses a blocked one. The offers below are the
  /// business-meaningful subset — never a button whose call is always refused.
  static List<OrgAction> actionsFor(AdminModel a) => switch (standingOf(a)) {
    OrgStanding.awaitingApproval => const [
      OrgAction.approve,
      OrgAction.grant,
      OrgAction.block,
    ],
    OrgStanding.approved => const [
      OrgAction.grant,
      OrgAction.warn,
      OrgAction.block,
    ],
    OrgStanding.warning => const [
      OrgAction.grant,
      OrgAction.reactivate,
      OrgAction.block,
    ],
    OrgStanding.blocked => const [OrgAction.reactivate],
    OrgStanding.unknown => const [OrgAction.reactivate, OrgAction.block],
  };

  /// The primary verb for a row: the one thing most worth doing.
  static OrgAction? primaryAction(AdminModel a, {required DateTime now}) {
    if (a.unreadable) return null;
    final s = standingOf(a);
    if (s == OrgStanding.awaitingApproval) return OrgAction.approve;
    if (s == OrgStanding.blocked) return null;
    final sub = subscriptionOf(a, now: now);
    // Paid-through but switched off: a payment is NOT the remedy (ORPH-1).
    if (sub.state == SubscriptionState.offBeforeEnd) return null;
    if (!a.isSubscriptionActive ||
        sub.state == SubscriptionState.expiringSoon ||
        sub.state == SubscriptionState.activePastEnd) {
      return OrgAction.grant;
    }
    return null;
  }

  static String actionLabelFor(OrgAction action, AdminModel a) {
    if (action == OrgAction.reactivate) {
      return switch (standingOf(a)) {
        OrgStanding.warning => 'Clear warning',
        OrgStanding.unknown => 'Set to Approved',
        _ => 'Reactivate',
      };
    }
    if (action == OrgAction.grant) {
      return a.isSubscriptionActive
          ? 'Record renewal / change plan'
          : 'Record payment';
    }
    return action.label;
  }

  static OrgActionPlan planFor(
    OrgAction action,
    AdminModel a, {
    required DateTime now,
  }) {
    final name = displayName(a);
    final owner = '${ownerName(a)} (${ownerEmail(a)})';
    final who = '$name — owner $owner';
    switch (action) {
      case OrgAction.approve:
        return OrgActionPlan(
          action: action,
          title: 'Approve $name',
          what: 'Marks the organization as approved by the platform.',
          who: who,
          consequences: [
            if (a.isSubscriptionActive)
              'They can start operating immediately: add trainers, members and plans.'
            else
              'They still cannot operate until a subscription is recorded — '
                  'approval alone does not start service.',
            'The owner is notified that the organization is approved.',
            'Trainer access and the storefront are updated to match.',
            'The action is written to the audit log with your name.',
          ],
          reversibility: 'Reversible — you can issue a warning or block later.',
          requiresReason: false,
          requiresTypedName: false,
          confirmLabel: 'Approve',
        );
      case OrgAction.warn:
        return OrgActionPlan(
          action: action,
          title: 'Issue an internal warning — $name',
          what:
              'Records a warning on the organization, visible only to the platform team.',
          who: who,
          consequences: [
            'Nothing changes for the organization: they keep full access and are not notified.',
            'The reason is visible here and in the audit log, nowhere else.',
          ],
          reversibility: 'Reversible — "Clear warning" returns it to Approved.',
          requiresReason: true,
          requiresTypedName: false,
          confirmLabel: 'Record warning',
        );
      case OrgAction.block:
        return OrgActionPlan(
          action: action,
          title: 'Block $name',
          what: 'Locks the organization out of the platform.',
          who: who,
          consequences: [
            'The owner\'s sign-in is disabled and live sessions end within the hour.',
            'Every trainer of the organization is paused in their app.',
            'Members can no longer see the organization in Discover.',
            'Nothing is deleted. Members, trainers, plans and payment history stay intact.',
            'The owner is notified that the organization is blocked — but not why. Record the reason here for your own trail.',
          ],
          reversibility:
              'Reversible — Reactivate restores sign-in and access. A blocked '
              'organization cannot be granted a subscription until reactivated.',
          requiresReason: true,
          requiresTypedName: true,
          confirmLabel: 'Block organization',
        );
      case OrgAction.reactivate:
        final s = standingOf(a);
        return OrgActionPlan(
          action: action,
          title: s == OrgStanding.warning
              ? 'Clear the warning — $name'
              : 'Reactivate $name',
          what: s == OrgStanding.warning
              ? 'Returns the organization to Approved with no warning on file.'
              : 'Returns the organization to Approved.',
          who: who,
          consequences: [
            if (s == OrgStanding.blocked)
              'The owner\'s sign-in is enabled again.',
            if (a.isSubscriptionActive)
              'They can operate immediately — the subscription is active.'
            else
              'They still cannot operate: no subscription is active. Record a payment next.',
            if (s != OrgStanding.warning)
              'The owner is notified that the organization is approved.'
            else
              'The owner is sent the standard "Organization approved — your '
                  'workspace is ready" notification (the backend sends it on '
                  'every return to Approved), although they were never told '
                  'about the warning.',
            'Trainer access and the storefront are updated to match.',
          ],
          reversibility: 'Reversible — you can block again at any time.',
          requiresReason: false,
          requiresTypedName: false,
          confirmLabel: s == OrgStanding.warning
              ? 'Clear warning'
              : 'Reactivate',
        );
      case OrgAction.grant:
        final sub = subscriptionOf(a, now: now);
        return OrgActionPlan(
          action: action,
          title: 'Record a payment — $name',
          what:
              'Records money the team already collected and starts, extends or changes the plan.',
          who: who,
          consequences: [
            sub.isActiveFlag && sub.endsAt != null && sub.daysLeft! >= 0
                ? 'The new term is added on top of the current end date, ${exact(sub.endsAt)}.'
                : 'The new term starts today.',
            'Plan limits and features are replaced by the chosen plan\'s.',
            'A receipt is written and the owner is sent a notification (best '
                'effort — a failed notification does not undo the payment).',
            if (standingOf(a) == OrgStanding.awaitingApproval)
              'The organization stays awaiting approval — recording payment does not approve it.',
          ],
          reversibility:
              'Cannot be undone from here. A payment reference can be used only once.',
          requiresReason: false,
          requiresTypedName: false,
          confirmLabel: 'Record payment',
        );
      case OrgAction.reapplyEffects:
        final s = standingOf(a);
        return OrgActionPlan(
          action: action,
          title: 'Re-apply status effects — $name',
          what:
              'Re-runs the steps that make the CURRENT status '
              '(${s.label}) real, for steps that failed when it was set.',
          who: who,
          consequences: [
            'Trainer access is re-synced to the organization\'s current '
                'state (${canOperate(a) ? 'operating' : 'not operating'}).',
            if (s == OrgStanding.blocked)
              'The owner\'s sign-in is disabled again and their sessions are '
                  'revoked — already-issued sign-in tokens can keep reading for '
                  'up to about an hour.'
            else
              'The owner\'s sign-in is enabled to match the status.',
            'The status itself does NOT change, nobody is notified and no '
                'automation runs.',
            'Written to the audit log with your name. When every step '
                'succeeds, the backend resolves the matching open incidents.',
          ],
          reversibility:
              'Safe to repeat — it only re-applies what the status already '
              'says.',
          requiresReason: false,
          requiresTypedName: false,
          confirmLabel: 'Re-apply',
        );
    }
  }

  // ── receipts ──────────────────────────────────────────────────────────────

  static ReceiptState receiptState(SubscriptionModel s) {
    if (s.isFullyRefunded) return ReceiptState.refunded;
    if (s.refundMinor > 0) return ReceiptState.partiallyRefunded;
    if (s.isLegacyGatewayReceipt) return ReceiptState.legacyGateway;
    if (s.razorpayPaymentId.isEmpty) return ReceiptState.recordedManually;
    if (!s.captureVerified) return ReceiptState.unverified;
    return ReceiptState.paid;
  }

  /// A receipt is refundable from the console only when the gateway holds the
  /// money (a `pay_…` id exists) and something is left to return.
  static bool canRefund(SubscriptionModel s) =>
      s.razorpayPaymentId.isNotEmpty && !s.isFullyRefunded && s.amountMinor > 0;

  /// The most a PARTIAL refund may ask for: whole rupees (the callable's
  /// unit), never above what is left on the receipt. A full refund sends no
  /// amount and returns the exact remainder, paise included.
  static int maxPartialRefundRupees(SubscriptionModel s) => s.netMinor ~/ 100;

  // ── the refund ledger (C1) ────────────────────────────────────────────────

  static String refundStatusLabel(ReceiptRefund r) => switch (r.status) {
    'created' || 'pending' => 'pending at the gateway',
    'processed' => 'processed',
    'failed' => 'failed — no money left, not counted',
    _ => 'status not recorded',
  };

  static String refundSourceLabel(ReceiptRefund r) => switch (r.source) {
    'console' => 'issued from this console',
    'gateway' => 'made in the Razorpay dashboard',
    _ => 'source not recorded',
  };

  /// One ledger entry in a line: amount · status · source · date.
  static String refundLine(ReceiptRefund r) {
    final when = r.at == null ? 'date not recorded' : exact(r.at);
    final legacy = r.legacy
        ? ' · recorded before the per-refund ledger existed'
              '${(r.legacyCount ?? 0) > 1 ? ' (a total of ${r.legacyCount} refunds)' : ''}'
        : '';
    return '${rupeesMinor(r.amountMinor)} · ${refundStatusLabel(r)} · '
        '${refundSourceLabel(r)} · $when$legacy';
  }

  /// Every refund on a receipt as a History event AT ITS OWN TIME (ORG-6),
  /// plus a second event when the gateway later reported it failed.
  static List<OrgEvent> refundEvents(
    SubscriptionModel s, {
    required String Function(String uid) actorOf,
  }) {
    final out = <OrgEvent>[];
    final plan = s.planName.isEmpty ? 'plan not named' : s.planName;
    for (final r in s.refunds) {
      final actor = r.fromGateway
          ? 'the Razorpay dashboard'
          : ((r.requestedBy ?? '').isEmpty ? '' : actorOf(r.requestedBy!));
      out.add(
        OrgEvent(
          at: r.at,
          kind: OrgEventKind.payment,
          title: r.fromGateway
              ? 'Refund made in the Razorpay dashboard · ${rupeesMinor(r.amountMinor)}'
              : 'Refund · ${rupeesMinor(r.amountMinor)}',
          detail: [
            refundStatusLabel(r),
            'receipt of ${rupeesMinor(s.amountMinor)} for $plan',
            if ((r.reason ?? '').isNotEmpty) r.reason!,
            if (r.legacy) 'recorded before the per-refund ledger existed',
          ].join(' · '),
          actor: actor,
          technical: {
            'refundId': r.id,
            'receiptId': s.id,
            'razorpayPaymentId': s.razorpayPaymentId,
            'amountMinor': r.amountMinor,
            'status': r.status,
            'source': r.source,
            if (r.intentId != null) 'intentId': r.intentId,
            if (r.legacy) 'legacy': true,
          },
          source: 'admin_payments_history.refunds',
        ),
      );
      if (r.isFailed && r.failedAt != null) {
        out.add(
          OrgEvent(
            at: r.failedAt,
            kind: OrgEventKind.payment,
            title:
                'Refund failed at the gateway · ${rupeesMinor(r.amountMinor)}',
            detail:
                'The money did not leave; it no longer counts against the '
                'receipt of ${rupeesMinor(s.amountMinor)} for $plan.',
            actor: 'the payment gateway',
            technical: {'refundId': r.id, 'receiptId': s.id},
            source: 'admin_payments_history.refunds',
          ),
        );
      }
    }
    return out;
  }

  /// Refund ids already on a loaded receipt's ledger — the audit rows that
  /// merely RECORD one of them are the same event and are not shown twice.
  static Set<String> ledgerRefundIds(Iterable<SubscriptionModel> receipts) => {
    for (final s in receipts)
      for (final r in s.refunds)
        if (!r.legacy) r.id,
  };

  static const Set<String> _refundRecordActions = {
    'refund_recorded',
    'subscription_refund_recorded',
    'subscription_refund_failed',
  };

  /// The whole History timeline: audit rows, the access request, receipts
  /// and their refunds — each at its own time, newest first, with an audit
  /// row that only records a ledger refund dropped in favour of the ledger
  /// entry (which carries the refund's CURRENT status).
  static List<OrgEvent> historyEvents({
    required Iterable<AuditLogModel> audit,
    required Iterable<AccessRequestModel> requests,
    required Iterable<SubscriptionModel> receipts,
    required String Function(String uid) actorOf,
  }) {
    final ledger = ledgerRefundIds(receipts);
    final events = <OrgEvent>[];
    for (final l in audit) {
      if (_refundRecordActions.contains(l.action) &&
          ledger.contains((l.details['refundId'] ?? '').toString())) {
        continue;
      }
      final e = fromAudit(l, actorOf: actorOf);
      if (e != null) events.add(e);
    }
    for (final r in requests) {
      events.addAll(fromAccessRequest(r, actorOf: actorOf));
    }
    for (final r in receipts) {
      events.add(fromReceipt(r));
      events.addAll(refundEvents(r, actorOf: actorOf));
    }
    return timeline(events);
  }

  /// Who APPROVED the organization, from the audit trail — `approvedBy` on
  /// the record is rewritten by `setAdminStatus` on EVERY status change, so a
  /// blocked organization's record names whoever blocked it (ORG-5). Prefers
  /// a recorded pending → approved transition (newer audit rows carry
  /// `from`); for older rows without `from`, the FIRST move to Approved; for
  /// an organization created already approved, the provisioning row.
  static OrgApproval? approvalFromAudit(Iterable<AuditLogModel> audit) {
    final rows = audit.toList()
      ..sort((a, b) {
        final x = a.createdAt, y = b.createdAt;
        if (x == null && y == null) return 0;
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y);
      });
    bool toApproved(AuditLogModel l) {
      final to = (l.details['to'] ?? l.details['status'] ?? '').toString();
      return l.action == 'set_admin_status' &&
          (to == 'active' || to == 'approved');
    }

    final fromPending = rows.where(
      (l) => toApproved(l) && (l.details['from'] ?? '').toString() == 'pending',
    );
    if (fromPending.isNotEmpty) {
      final l = fromPending.last;
      return OrgApproval(
        actorUid: l.actorUid,
        at: l.createdAt,
        how: 'approved from awaiting approval',
      );
    }
    final legacy = rows.where(
      (l) => toApproved(l) && l.details['from'] == null,
    );
    if (legacy.isNotEmpty) {
      final l = legacy.first;
      return OrgApproval(
        actorUid: l.actorUid,
        at: l.createdAt,
        how: 'first moved to Approved',
      );
    }
    final created = rows.where((l) => l.action == 'provision_organization');
    if (created.isNotEmpty) {
      final l = created.first;
      return OrgApproval(
        actorUid: l.actorUid,
        at: l.createdAt,
        how: 'created already approved, from an access request',
      );
    }
    return null;
  }

  /// The organization's feature whitelist in words (ORG-4). Read ONLY from
  /// the top-level `features` the backend writes — never from the
  /// owner-editable `metadata`. Tri-state, as the backend reads it.
  static String featuresLine(AdminModel a) {
    final f = a.features;
    if (f == null) {
      if (a.malformedFields.contains('features')) {
        return 'The feature list on the record cannot be read.';
      }
      return 'Not set on the record — a legacy organization: the coach app '
          'gates no premium feature for it.';
    }
    if (f.isEmpty) {
      return 'None — every gated premium feature is switched off for this '
          'organization.';
    }
    return 'Allowed: ${f.join(', ')}';
  }

  // ── history ───────────────────────────────────────────────────────────────

  /// The actor's words. [staffName] resolves a founder-console uid to a
  /// colleague's name; [ownerUid] identifies the organization's owner.
  static String actor(
    String uid, {
    required String? currentUid,
    required String? Function(String uid) staffName,
    String? ownerUid,
  }) {
    final u = uid.trim();
    if (u.isEmpty) return '';
    if (u == 'system') return 'the system';
    if (u == 'razorpay_webhook') return 'the Razorpay webhook';
    if (currentUid != null && u == currentUid) return 'you';
    if (ownerUid != null && u == ownerUid) return 'the owner';
    final staff = staffName(u);
    if (staff != null && staff.trim().isNotEmpty) return staff.trim();
    return 'a platform admin (${u.length > 8 ? u.substring(0, 8) : u}…)';
  }

  static String _money(dynamic v) {
    if (v is! num) return '';
    return rupees(v.toDouble());
  }

  static OrgEvent? fromAudit(
    AuditLogModel l, {
    required String Function(String uid) actorOf,
  }) {
    final d = l.details;
    final actor = actorOf(l.actorUid);
    final tech = <String, dynamic>{
      'action': l.action,
      'actorUid': l.actorUid,
      ...d,
    };
    switch (l.action) {
      case 'set_admin_status':
        // Newer rows carry {from, to, reason, guarded} (C6); older ones
        // {status}. Both are read.
        final s = (d['to'] ?? d['status'] ?? '').toString();
        OrgStanding standingFor(String v) => switch (v) {
          'pending' => OrgStanding.awaitingApproval,
          'active' || 'approved' => OrgStanding.approved,
          'warning' => OrgStanding.warning,
          'blocked' => OrgStanding.blocked,
          _ => OrgStanding.unknown,
        };
        final standing = standingFor(s);
        final from = (d['from'] ?? '').toString();
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.admin,
          title: standing == OrgStanding.unknown
              ? 'Status changed to "$s"'
              : 'Status changed to ${standing.label}',
          detail: [
            if (from.isNotEmpty)
              'from ${standingFor(from) == OrgStanding.unknown ? '"$from"' : standingFor(from).label}',
            if ((d['reason'] ?? '').toString().isNotEmpty)
              d['reason'].toString(),
          ].join(' · '),
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
      case 'reapply_status_effects':
        final legs = d['legs'];
        final Map lm = legs is Map ? legs : const {};
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.admin,
          title: 'Status effects re-applied',
          detail: [
            if ((d['status'] ?? '').toString().isNotEmpty)
              'for status ${d['status']}',
            if (lm['cascade'] != null) 'trainer sync ${lm['cascade']}',
            if (lm['auth'] != null) 'owner sign-in ${lm['auth']}',
          ].join(' · '),
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
      case 'grant_subscription':
        final parts = <String>[
          if (d['months'] is num)
            '${d['months']} month${d['months'] == 1 ? '' : 's'}',
          if (d['amount'] is num) _money(d['amount']),
          if ((d['reference'] ?? '').toString().isNotEmpty)
            'ref ${d['reference']}',
        ];
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.payment,
          title: 'Payment recorded by the team',
          detail: parts.join(' · '),
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
      case 'activate_subscription':
        final parts = <String>[
          if ((d['planName'] ?? '').toString().isNotEmpty)
            d['planName'].toString(),
          if (d['months'] is num)
            '${d['months']} month${d['months'] == 1 ? '' : 's'}',
          if (d['amount'] is num) _money(d['amount']),
        ];
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.payment,
          title: 'Subscription paid online',
          detail: parts.join(' · '),
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
      case 'provision_organization':
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.origin,
          title: 'Organization created from an access request',
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
      case 'register_admin':
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.record,
          title: 'Owner registered the organization',
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
      case 'subscription_expired':
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.system,
          title: 'Subscription expired — access ended automatically',
          actor: 'the system',
          technical: tech,
          source: 'audit_logs',
        );
      case 'refund_payment':
        // Written BEFORE the gateway call (the audit-first rule), so it is
        // the founder's DECISION, not proof that money moved — the receipt's
        // refund entries say what the gateway did. Amount: `amountMinor`
        // (paise) if present, else `amount` (rupees; null = full), else the
        // older `requestedAmountRupees` (0 = full).
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.payment,
          title: 'Refund requested from the console',
          detail: [
            refundAuditAmount(d),
            if (d['revokeAccess'] == true) 'end of subscription requested',
            if ((d['reason'] ?? '').toString().isNotEmpty)
              d['reason'].toString(),
          ].where((x) => x.isNotEmpty).join(' · '),
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
      case 'refund_recorded':
      case 'subscription_refund_recorded':
      case 'subscription_refund_failed':
        final failed = l.action == 'subscription_refund_failed';
        final gateway =
            l.action == 'subscription_refund_recorded' ||
            (d['source'] ?? '').toString() == 'gateway';
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.payment,
          title: failed
              ? 'A refund failed at the gateway'
              : gateway
              ? 'Refund made in the Razorpay dashboard recorded'
              : 'Refund recorded',
          detail: [
            refundAuditAmount(d),
            if ((d['status'] ?? '').toString().isNotEmpty)
              refundStatusLabel(
                ReceiptRefund(
                  id: '',
                  amountMinor: 0,
                  status: d['status'].toString(),
                ),
              ),
            if (failed) 'no money left; not counted against the receipt',
          ].where((x) => x.isNotEmpty).join(' · '),
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
      default:
        if (l.action.startsWith('privileged_read')) return null;
        return OrgEvent(
          at: l.createdAt,
          kind: OrgEventKind.admin,
          title: l.actionLabel,
          actor: actor,
          technical: tech,
          source: 'audit_logs',
        );
    }
  }

  /// The amount an audit row about a refund names, in words, or '' when it
  /// names none. Reads paise (`amountMinor`) before rupees (`amount`), and
  /// the older `requestedAmountRupees` (0 = full) last.
  static String refundAuditAmount(Map<String, dynamic> d) {
    final minor = d['amountMinor'];
    if (minor is num && minor.isFinite) return rupeesMinor(minor.round());
    final amount = d['amount'];
    if (amount is num && amount > 0) return rupees(amount.toDouble());
    final requested = d['requestedAmountRupees'];
    if (requested is num && requested > 0) return rupees(requested.toDouble());
    if (d['full'] == true ||
        (requested is num && requested == 0) ||
        d.containsKey('amount')) {
      return 'full refund';
    }
    return '';
  }

  static OrgEvent fromReceipt(SubscriptionModel s) {
    final state = receiptState(s);
    return OrgEvent(
      at: s.createdAtKnown ? s.createdAt : null,
      kind: OrgEventKind.payment,
      title:
          'Receipt · ${rupeesMinor(s.amountMinor)} · ${s.planName.isEmpty ? 'plan not named' : s.planName}',
      detail:
          '${state.label}${s.termKnown ? ' · ${plural(s.durationMonths, 'month')}' : ' · term not recorded'}'
          '${receiptPricingLine(s).isEmpty ? '' : ' · ${receiptPricingLine(s)}'}'
          '${s.refundMinor > 0 ? ' · ${rupeesMinor(s.refundMinor)} refunded' : ''}'
          '${(s.reference ?? '').isEmpty ? '' : ' · ref ${s.reference}'}',
      technical: {
        'receiptId': s.id,
        'razorpayPaymentId': s.razorpayPaymentId,
        'paymentId': s.paymentId,
        'captureVerified': s.captureVerified,
        'startAt': s.startKnown ? s.startAt.toIso8601String() : 'not recorded',
        'expiryAt': s.expiryKnown
            ? s.expiryAt.toIso8601String()
            : 'not recorded',
        'pricingBasis':
            s.pricingBasis ?? 'not stamped (receipt predates evidence)',
        'listPrice': s.listPrice,
        'discount': s.pricingDiscount,
        if (s.pricingTerm != null) 'pricingTerm': s.pricingTerm,
        'coverageStart': s.hasCoverageEvidence
            ? (s.coverageStart?.toIso8601String() ?? 'unreadable')
            : 'not recorded',
      },
      source: 'admin_payments_history',
    );
  }

  // ── pricing evidence (the words for what the SERVER stamped) ──────────────

  /// What span the receipt paid for — and ONLY what it proves (ORG-7).
  ///
  /// `startedAt` is the moment of PAYMENT; for an early renewal the term is
  /// added on top of the previous end date, so `Covers payment → end`
  /// claimed more months than were sold and overlapped the previous receipt.
  /// A receipt stamped with `coverageStart` (the base the server extended
  /// from) covers exactly `coverageStart → expiry`; an older receipt says
  /// when it was paid and when the plan runs until, and nothing else. A
  /// receipt with no recorded dates never prints the model's placeholders.
  static String receiptCoverageLine(SubscriptionModel s) {
    if (!s.startKnown && !s.expiryKnown && !s.hasCoverageEvidence) {
      return 'Term dates not recorded';
    }
    final end = s.expiryKnown ? exact(s.expiryAt) : 'end not recorded';
    if (s.hasCoverageEvidence && s.coverageStart != null) {
      return 'Covers ${exact(s.coverageStart)} → $end';
    }
    final paid = s.startKnown ? exact(s.startAt) : 'payment date not recorded';
    return 'Paid $paid · runs until $end · coverage start not recorded';
  }

  /// The renewal context stamped on newer receipts: what the term was added
  /// to. '' when the receipt predates the evidence.
  static String receiptCoverageDetail(SubscriptionModel s) {
    if (!s.hasCoverageEvidence) return '';
    final prevPlan = (s.previousPlanName ?? '').isEmpty
        ? ''
        : ' (previous plan ${s.previousPlanName})';
    final prev = s.previousExpiry;
    final paidAt = s.startKnown
        ? s.startAt
        : (s.createdAtKnown ? s.createdAt : null);
    if (prev != null && paidAt != null && prev.isAfter(paidAt)) {
      return 'Early renewal: added on top of the previous end date '
          '${exact(prev)}$prevPlan; paid ${exact(paidAt)}.';
    }
    if (prev != null) {
      return 'Started fresh: the previous term had ended on ${exact(prev)}$prevPlan.';
    }
    return 'Started fresh: no previous end date on record$prevPlan.';
  }

  /// The receipt's list-price evidence in one clause, or '' when the receipt
  /// predates the evidence. Never guesses a discount from the amount alone.
  static String _termWord(String? t) => switch (t) {
    'monthly' => ' (monthly term)',
    'yearly' => ' (yearly term)',
    'custom' => ' (custom term)',
    _ => '',
  };

  static String receiptPricingLine(SubscriptionModel s) {
    switch (s.pricingBasis) {
      case 'plan_term':
        final list = s.listPrice;
        if (list == null) return '';
        final d = s.pricingDiscount ?? 0;
        final o = s.overpayment ?? 0;
        final term = _termWord(s.pricingTerm);
        if (d > 0) {
          return 'list ${rupees(list)}$term · discount ${rupees(d)}'
              '${(s.pricingCoupon ?? '').isEmpty ? '' : ' (coupon ${s.pricingCoupon})'}';
        }
        if (o > 0) return 'list ${rupees(list)}$term · ${rupees(o)} above list';
        return 'at list price$term';
      case 'negotiated_term':
        return 'negotiated term — list ${s.listPrice == null ? 'unknown' : rupees(s.listPrice!)} '
            'is for ${plural(s.listTermMonths ?? 0, 'month')}; no discount computed';
      case 'unpriced':
        return 'plan carried no list price when recorded';
      default:
        return '';
    }
  }

  /// The sentence the founder reads after a grant: the SERVER's evidence,
  /// never the dialog's preview.
  static String pricingSentence(GrantResult r) {
    final collected = r.collected;
    final term = _termWord(r.pricingTerm);
    switch (r.pricingBasis) {
      case 'plan_term':
        final list = r.listPrice;
        if (list == null || collected == null) return '';
        if ((r.discount ?? 0) > 0) {
          return 'Recorded ${rupees(collected)} against a list price of '
              '${rupees(list)}$term — a discount of ${rupees(r.discount!)} is on the receipt.';
        }
        if ((r.overpayment ?? 0) > 0) {
          return 'Recorded ${rupees(collected)}, which is ${rupees(r.overpayment!)} '
              'above the list price of ${rupees(list)}$term — check the reference.';
        }
        return 'Recorded ${rupees(collected)}, the list price$term.';
      case 'negotiated_term':
        return 'Recorded ${collected == null ? 'the amount' : rupees(collected)} for a '
            'negotiated term; the list price (${r.listPrice == null ? 'unknown' : rupees(r.listPrice!)} '
            'for ${plural(r.listTermMonths ?? 0, 'month')}) is on the receipt, no discount was computed.';
      case 'unpriced':
        return 'The plan carried no list price, so the receipt records the amount only.';
      default:
        return '';
    }
  }

  // ── grant PREVIEW (client-side, mirrors the backend rule for display) ─────

  /// The date a grant extends from: max(now, current planExpiry) — exactly
  /// `renewalBaseMs` in the backend, which reads `planExpiry` alone. The
  /// old preview also consulted `isSubscriptionActive`, so a record whose
  /// flag was off but whose expiry lay ahead previewed "starts today" while
  /// the server extended from the expiry.
  static DateTime grantBase(AdminModel a, {required DateTime now}) {
    final e = a.planExpiry;
    return (e != null && e.isAfter(now)) ? e : now;
  }

  /// Same day-of-month clamping as the backend's addMonthsClamped (in UTC).
  static DateTime addMonthsClamped(DateTime from, int months) {
    final d = from.toUtc();
    final total = d.month - 1 + months;
    final y = d.year + (total ~/ 12);
    final m = (total % 12) + 1;
    final lastDay = DateTime.utc(y, m + 1, 0).day;
    return DateTime.utc(
      y,
      m,
      d.day > lastDay ? lastDay : d.day,
      d.hour,
      d.minute,
      d.second,
    );
  }

  /// The preview of what the server will stamp — the same arithmetic as the
  /// backend's `pricingEvidence`, computed for DISPLAY before confirmation.
  /// The confirmation shows the server's own result afterwards.
  static GrantPreview grantPreview({
    required double? listPrice,
    required int? listTermMonths,
    required int months,
    required double amount,
    String? term,
  }) {
    final priced =
        listPrice != null &&
        listPrice.isFinite &&
        listPrice > 0 &&
        listTermMonths != null &&
        listTermMonths > 0;
    if (!priced || !amount.isFinite) {
      return GrantPreview(
        basis: 'unpriced',
        listPrice: null,
        listTermMonths: null,
        collected: amount,
        discount: null,
        overpayment: null,
      );
    }
    if (listTermMonths != months) {
      return GrantPreview(
        basis: 'negotiated_term',
        listPrice: listPrice,
        listTermMonths: listTermMonths,
        collected: amount,
        discount: null,
        overpayment: null,
        term: term,
      );
    }
    // In PAISE: a float subtraction of rupees produced 0.8199999… figures.
    final diffMinor = (listPrice * 100).round() - (amount * 100).round();
    return GrantPreview(
      basis: 'plan_term',
      listPrice: listPrice,
      listTermMonths: listTermMonths,
      collected: amount,
      discount: diffMinor >= 0 ? diffMinor / 100 : 0,
      overpayment: diffMinor < 0 ? -diffMinor / 100 : 0,
      term: term,
    );
  }

  static String termOfMonths(int m) => switch (m) {
    1 => 'monthly',
    12 => 'yearly',
    _ => 'custom',
  };

  /// The list the SERVER resolves for a grant of [months] (C4), mirrored for
  /// display and for the `expectedListPrice` assertion:
  ///   • 12 months and the document AUTHORS a yearly price → yearly price;
  ///   • 1 month and it authors a monthly price → monthly price;
  ///   • otherwise the document's own live term (price / months) — a
  ///     different length is then a negotiated term, priced against it.
  /// [authoredMonthly] / [authoredYearly] are 0 when the document does not
  /// carry the field (a migrated legacy price is NOT authored).
  static GrantList listForGrant({
    required double livePrice,
    required int liveMonths,
    required double authoredMonthly,
    required double authoredYearly,
    required int months,
  }) {
    if (months == 12 && authoredYearly > 0) {
      return GrantList(
        term: 'yearly',
        listPrice: authoredYearly,
        listTermMonths: 12,
      );
    }
    if (months == 1 && authoredMonthly > 0) {
      return GrantList(
        term: 'monthly',
        listPrice: authoredMonthly,
        listTermMonths: 1,
      );
    }
    if (livePrice > 0 && liveMonths > 0) {
      return GrantList(
        term: termOfMonths(liveMonths),
        listPrice: livePrice,
        listTermMonths: liveMonths,
      );
    }
    return const GrantList();
  }

  /// Every term the plan SELLS — both terms of a dual-priced plan, plus the
  /// document's own live term when it is neither (a legacy 3-month plan).
  /// 'Plan term' in the grant dialog offers exactly these.
  static List<SoldTerm> soldTerms({
    required double livePrice,
    required int liveMonths,
    required double authoredMonthly,
    required double authoredYearly,
  }) {
    final out = <SoldTerm>[
      if (authoredMonthly > 0)
        SoldTerm(
          key: 'monthly',
          label: 'Monthly',
          months: 1,
          listPrice: authoredMonthly,
          term: 'monthly',
        ),
      if (authoredYearly > 0)
        SoldTerm(
          key: 'yearly',
          label: 'Yearly',
          months: 12,
          listPrice: authoredYearly,
          term: 'yearly',
        ),
    ];
    if (!out.any((t) => t.months == liveMonths)) {
      out.add(
        SoldTerm(
          key: 'plan',
          label: 'Plan term',
          months: liveMonths > 0 ? liveMonths : 1,
          listPrice: livePrice > 0 ? livePrice : null,
          term: termOfMonths(liveMonths),
        ),
      );
    }
    return out;
  }

  static List<OrgEvent> fromAccessRequest(
    AccessRequestModel r, {
    required String Function(String uid) actorOf,
  }) {
    final out = <OrgEvent>[
      OrgEvent(
        at: r.createdAt,
        kind: OrgEventKind.origin,
        title: 'Access request received',
        detail: r.ownerName.trim().isEmpty
            ? r.organizationName
            : '${r.ownerName} asked for ${r.organizationName}',
        actor: 'the requester',
        technical: {'requestId': r.id, 'status': r.status},
        source: 'access_requests',
      ),
    ];
    for (final e in r.statusHistory) {
      if (e.status == 'requested') continue;
      out.add(
        OrgEvent(
          at: e.at,
          kind: OrgEventKind.origin,
          title: switch (e.status) {
            'contacted' => 'Requester contacted',
            'payment_pending' => 'Payment link sent',
            'payment_confirmed' => 'Payment recorded on the request',
            'approved' => 'Request approved',
            'organization_created' => 'Organization created from the request',
            'rejected' => 'Request rejected',
            _ => 'Request moved to "${e.status}"',
          },
          detail: e.note,
          actor: e.by == 'prospect' ? 'the requester' : actorOf(e.by),
          technical: {'requestId': r.id, 'status': e.status, 'by': e.by},
          source: 'access_requests',
        ),
      );
    }
    return out;
  }

  /// Newest first; undated events last (they are real, but cannot be placed).
  static List<OrgEvent> timeline(Iterable<OrgEvent> events) {
    final list = events.toList();
    list.sort((a, b) {
      if (a.at == null && b.at == null) return 0;
      if (a.at == null) return 1;
      if (b.at == null) return -1;
      return b.at!.compareTo(a.at!);
    });
    return list;
  }

  // ── words for numbers and time ────────────────────────────────────────────

  /// Rupees, PAISE-EXACT, Indian grouping: ₹4,999 · ₹1,178.82 · ₹0.40.
  /// Whole-rupee rounding printed a GST-inclusive ₹1,178.82 receipt as
  /// ₹1,179 and a ₹0.40 overpayment as "₹0 ABOVE the list price".
  static String rupees(double r) {
    if (!r.isFinite) return '₹—';
    return rupeesMinor((r * 100).round());
  }

  /// Integer paise → rupees text.
  static String rupeesMinor(int minor) {
    final neg = minor < 0;
    final abs = minor.abs();
    final whole = abs ~/ 100;
    final paise = abs % 100;
    final s = whole.toString();
    String grouped;
    if (s.length <= 3) {
      grouped = s;
    } else {
      final last3 = s.substring(s.length - 3);
      var rest = s.substring(0, s.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      grouped = '${parts.join(',')},$last3';
    }
    final fraction = paise == 0 ? '' : '.${paise.toString().padLeft(2, '0')}';
    return '₹${neg ? '-' : ''}$grouped$fraction';
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

  static String exact(DateTime? t) =>
      t == null ? 'not recorded' : '${t.day} ${_months[t.month - 1]} ${t.year}';

  static String exactTime(DateTime? t) {
    if (t == null) return 'not recorded';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '${exact(t)}, $h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }

  /// "3 days ago" / "in 5 days" / "today".
  static String relative(DateTime? t, {required DateTime now}) {
    if (t == null) return 'date not recorded';
    final days = _calendarDays(now, t);
    if (days == 0) return 'today';
    if (days == 1) return 'tomorrow';
    if (days == -1) return 'yesterday';
    if (days > 0) {
      if (days < 30) return 'in $days days';
      if (days < 365) return 'in ${plural((days / 30).round(), 'month')}';
      return 'in ${plural((days / 365).round(), 'year')}';
    }
    final ago = -days;
    if (ago < 30) return '$ago days ago';
    if (ago < 365) return '${plural((ago / 30).round(), 'month')} ago';
    final y = (ago / 365).round();
    return '$y year${y == 1 ? '' : 's'} ago';
  }

  static String createdLine(AdminModel a, {required DateTime now}) =>
      a.createdAtKnown
      ? 'Created ${exact(a.createdAt)} (${relative(a.createdAt, now: now)})'
      : 'Creation date not recorded';

  /// `lastLogin` is OWNER-WRITABLE and no backend writes it, so a value is
  /// only ever what the owner's own app (or the owner) put there (ORG-9).
  static String lastSignInLine(AdminModel a, {required DateTime now}) =>
      a.lastLogin == null
      ? 'No sign-in time on the record — the platform does not record '
            'owner sign-ins here, so it is unknown whether they never signed in'
      : 'The record says the owner last signed in '
            '${relative(a.lastLogin, now: now)} (owner-editable field, not '
            'verified by the platform)';

  static String plural(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';
}
