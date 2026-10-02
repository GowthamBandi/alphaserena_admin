// MEMBERS — the words, rules and orderings of the member oversight workspace.
// PURE: no Firebase, no widgets. Change a rule HERE first; the list, the
// tiles, the workspace and the tests all read it from this one place.
//
// WHAT A MEMBER IS. `clients/{id}` is one person's membership record inside
// ONE organization (`adminId`). The document id is random; the person is
// `authUid`, and the same person may hold a record in several organizations.
// The record is created by a payment (online, coupon or offline), coached by
// the owner until delegated to a trainer (`trainerId`), kept alive by the
// member's own app activity (`lastActivityAt`, adherence, check-ins) and
// ends when its term expires. Nobody deletes it except the owner.
//
// WHO MAY CHANGE IT. The owner, in the Trainersarena app, and the member,
// through their own app. The platform (this console) reads and never writes —
// the rules deny the founder every field. Its power is understanding and
// ROUTING: a member issue points at the organization or the trainer, where the
// platform's real levers live.

import '../../models/admin_model.dart';
import '../../models/audit_log_model.dart';
import '../../models/clints_model.dart';
import '../../models/member_payment_model.dart';
import '../../models/trainer_model.dart';
import 'organization_language.dart';
import 'trainer_language.dart';

// ═════════════════════════════════════════════════════════════════════════════
// STATES
// ═════════════════════════════════════════════════════════════════════════════

/// Mirrors trainersHQ `MembershipStatus`, derived from the expiry and the
/// freeze flag — never from `membershipActive` alone, which lags the hourly
/// expiry sweep.
enum MembershipState { none, active, expiringSoon, frozen, expired }

extension MembershipStateX on MembershipState {
  String get label => switch (this) {
    MembershipState.none => 'No membership',
    MembershipState.active => 'Membership active',
    MembershipState.expiringSoon => 'Expiring soon',
    MembershipState.frozen => 'Frozen',
    MembershipState.expired => 'Expired',
  };

  String get meaning => switch (this) {
    MembershipState.none =>
      'No membership term is recorded. The member cannot use the app\'s '
          'coaching features until the organization records or sells one.',
    MembershipState.active => 'The current term has not ended.',
    MembershipState.expiringSoon =>
      'The current term ends within ${MemberLanguage.expiringSoonDays} days. '
          'Renewal is the organization\'s to sell.',
    MembershipState.frozen =>
      'The owner froze this membership; the expiry does not advance and the '
          'expiry sweep skips it until it is unfrozen.',
    MembershipState.expired =>
      'The term has ended. The backend switches access off within the hour; '
          'the organization can extend or sell a new term.',
  };

  bool get isCurrent =>
      this == MembershipState.active || this == MembershipState.expiringSoon;
}

/// Whether the record is tied to a signed-in person.
enum AccountLink { linked, deletedByMember, neverClaimed }

extension AccountLinkX on AccountLink {
  String get label => switch (this) {
    AccountLink.linked => 'App account linked',
    AccountLink.deletedByMember => 'Account deleted by member',
    AccountLink.neverClaimed => 'No app account yet',
  };
}

/// How recently the member's own app has produced activity.
enum ActivityState { recent, quiet, dormant, none }

extension ActivityStateX on ActivityState {
  String get label => switch (this) {
    ActivityState.recent => 'Active this week',
    ActivityState.quiet => 'Quiet',
    ActivityState.dormant => 'Dormant',
    ActivityState.none => 'No activity recorded',
  };
}

class MemberIssue {
  final String code;
  final OrgIssueSeverity severity;
  final String title;
  final String why;
  final String whatToDo;

  const MemberIssue({
    required this.code,
    required this.severity,
    required this.title,
    required this.why,
    required this.whatToDo,
  });

  bool get needsAttention => severity != OrgIssueSeverity.info;
}

class MemberEvent {
  final DateTime? at;
  final String title;
  final String detail;
  final String actor;
  final Map<String, dynamic> technical;

  const MemberEvent({
    required this.at,
    required this.title,
    this.detail = '',
    this.actor = '',
    this.technical = const {},
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// THE LANGUAGE
// ═════════════════════════════════════════════════════════════════════════════

class MemberLanguage {
  MemberLanguage._();

  static const int recentDays = 30;
  static const int expiringSoonDays = 7;
  static const int quietAfterDays = 7;
  static const int dormantAfterDays = 30;
  static const int stalledAfterDays = 14;

  /// Every value the producers write, and nothing else.
  static const Set<String> knownStatuses = {'active', 'inactive'};
  static const Set<String> knownStages = {
    'onboarding',
    'awaitingTrainer',
    'preparingPlan',
    'ready',
  };

  // ── per-field identity, mirroring trainersHQ resolveClientIdentity ────────

  static Map<String, dynamic> _section(Map<String, dynamic>? shared, String k) {
    final v = shared?[k];
    if (v is Map) return v.map((a, b) => MapEntry(a.toString(), b));
    return const {};
  }

  static String? _clean(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String displayName(ClientModel m) {
    final identity = _section(m.sharedProfile, 'identity');
    return _clean(identity['displayName']) ??
        _clean(identity['name']) ??
        _clean(m.name) ??
        'Name not recorded';
  }

  static bool nameIsRecorded(ClientModel m) =>
      displayName(m) != 'Name not recorded';

  static String? emailOf(ClientModel m) =>
      _clean(_section(m.sharedProfile, 'contact')['email']) ?? _clean(m.email);

  static String? phoneOf(ClientModel m) =>
      _clean(_section(m.sharedProfile, 'contact')['phone']) ?? _clean(m.phone);

  static String email(ClientModel m) => emailOf(m) ?? 'No email on record';

  static String phone(ClientModel m) => phoneOf(m) ?? 'No phone on record';

  static String contactLine(ClientModel m) {
    final parts = [emailOf(m), phoneOf(m)].whereType<String>().toList();
    return parts.isEmpty ? 'No contact recorded' : parts.join(' · ');
  }

  static String? photoUrl(ClientModel m) =>
      _clean(_section(m.sharedProfile, 'identity')['photoUrl']) ??
      _clean(m.profilePicUrl);

  static String? genderOf(ClientModel m) =>
      _clean(_section(m.sharedProfile, 'identity')['gender']) ??
      _clean(m.gender);

  static DateTime? dateOfBirth(ClientModel m) {
    final raw = _clean(_section(m.sharedProfile, 'identity')['dob']);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// A real date of birth outranks a frozen integer typed once.
  static int? ageOf(ClientModel m, {required DateTime now}) {
    final dob = dateOfBirth(m);
    if (dob != null) {
      var a = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        a--;
      }
      return a < 0 || a > 120 ? null : a;
    }
    return m.age;
  }

  static double? _num(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  static double? heightCm(ClientModel m) =>
      _num(_section(m.sharedProfile, 'bodyMetrics')['heightCm']) ?? m.height;

  static double? weightKg(ClientModel m) =>
      _num(_section(m.sharedProfile, 'bodyMetrics')['weightKg']) ?? m.weight;

  static double? goalWeightKg(ClientModel m) =>
      _num(_section(m.sharedProfile, 'bodyMetrics')['goalWeightKg']);

  static String? goalOf(ClientModel m) {
    final goals = _section(m.sharedProfile, 'goals');
    return _clean(goals['primary']) ?? _clean(goals['goal']) ?? _clean(m.goal);
  }

  static String initial(ClientModel m) {
    final n = displayName(m);
    return n == 'Name not recorded' ? '?' : n[0].toUpperCase();
  }

  static String id(ClientModel m) => m.docId;

  /// The member's profile came from their own app (not only the coach record).
  static bool hasSharedProfile(ClientModel m) =>
      _section(m.sharedProfile, 'identity').isNotEmpty ||
      _section(m.sharedProfile, 'contact').isNotEmpty;

  // ── membership ────────────────────────────────────────────────────────────

  static bool hasMembershipRecord(ClientModel m) =>
      m.membershipExpiry != null || m.membershipActive;

  static int? daysLeft(ClientModel m, {required DateTime now}) {
    final e = m.membershipExpiry;
    if (e == null) return null;
    final ms = e.difference(now).inMilliseconds;
    return (ms / Duration.millisecondsPerDay).ceil();
  }

  static MembershipState membershipState(
    ClientModel m, {
    required DateTime now,
  }) {
    if (!hasMembershipRecord(m)) return MembershipState.none;
    if (m.membershipFrozen) return MembershipState.frozen;
    final e = m.membershipExpiry;
    if (e == null) {
      return m.membershipActive ? MembershipState.active : MembershipState.none;
    }
    if (now.isAfter(e)) return MembershipState.expired;
    if ((daysLeft(m, now: now) ?? 0) <= expiringSoonDays) {
      return MembershipState.expiringSoon;
    }
    return MembershipState.active;
  }

  /// `membershipActive` disagrees with the derived state: the flag says active
  /// after the term ended (the expiry sweep lags or failed), or inactive while
  /// the term still runs (a failed activation write).
  static String? flagDisagreement(ClientModel m, {required DateTime now}) {
    if (m.membershipFrozen) return null;
    final e = m.membershipExpiry;
    if (e == null) return null;
    final expired = now.isAfter(e);
    if (m.membershipActive && expired) {
      // The sweep runs hourly; only call it stale after it has had its chance.
      if (now.difference(e) < const Duration(hours: 2)) return null;
      return 'flag_active_after_expiry';
    }
    if (!m.membershipActive && !expired) return 'flag_inactive_during_term';
    return null;
  }

  static String planName(ClientModel m) =>
      _clean(m.membership?['planName']) ?? 'Plan not recorded';

  static String? planId(ClientModel m) => _clean(m.membership?['planId']);

  static double? amountPaid(ClientModel m) => _num(m.membership?['amount']);

  /// "Online via Razorpay" / "Free with coupon X" / "Offline, cash" / "Manual
  /// extension by the owner".
  static String sourceLine(ClientModel m) => sourceOf(
    source: _clean(m.membership?['source']),
    method: _clean(m.membership?['method']),
    coupon: _clean(m.membership?['couponCode']),
    online:
        _clean(m.membership?['razorpayPaymentId']) != null ||
        _clean(m.membership?['razorpayOrderId']) != null,
  );

  static String sourceOf({
    String? source,
    String? method,
    String? coupon,
    required bool online,
  }) {
    switch (source) {
      case 'coupon_full_discount':
        return 'Free with coupon${coupon == null ? '' : ' $coupon'}';
      case 'offline':
        return 'Recorded offline by the owner${method == null ? '' : ' ($method)'}';
      case 'manual':
        return 'Extended manually by the owner';
    }
    if (online) {
      return 'Paid online via Razorpay${coupon == null ? '' : ' (coupon $coupon)'}';
    }
    if (method != null) return 'Recorded by the owner ($method)';
    return 'Origin not recorded';
  }

  static String termLine(ClientModel m, {required DateTime now}) {
    final start =
        memberDate(m.membership?['termStartAt']) ??
        memberDate(m.membership?['startedAt']);
    final end = m.membershipExpiry ?? memberDate(m.membership?['expiry']);
    if (start == null && end == null) return 'No term recorded';
    final a = start == null
        ? 'start not recorded'
        : OrganizationLanguage.exact(start);
    final b = end == null
        ? 'no end recorded'
        : '${OrganizationLanguage.exact(end)} (${OrganizationLanguage.relative(end, now: now)})';
    return '$a → $b';
  }

  static String membershipLine(ClientModel m, {required DateTime now}) {
    final s = membershipState(m, now: now);
    final plan = _clean(m.membership?['planName']);
    switch (s) {
      case MembershipState.none:
        return 'No membership on record';
      case MembershipState.frozen:
        return 'Frozen${plan == null ? '' : ' · $plan'}'
            '${m.membershipFrozenAt == null ? '' : ' since ${OrganizationLanguage.exact(m.membershipFrozenAt)}'}';
      case MembershipState.expired:
        return 'Expired ${OrganizationLanguage.relative(m.membershipExpiry, now: now)}'
            '${plan == null ? '' : ' · $plan'}';
      case MembershipState.expiringSoon:
      case MembershipState.active:
        final e = m.membershipExpiry;
        return '${plan ?? 'Membership'} · '
            '${e == null ? 'no expiry recorded' : 'ends ${OrganizationLanguage.relative(e, now: now)}'}';
    }
  }

  // ── coach ─────────────────────────────────────────────────────────────────

  /// The person responsible: the delegated trainer, else the owner.
  static String coachId(ClientModel m) {
    final t = (m.trainerId ?? '').trim();
    if (t.isNotEmpty) return t;
    return (m.adminId ?? '').trim();
  }

  /// Owner-coached when `trainerId` is absent, empty, OR equal to the owner's
  /// own uid — the coach app writes the owner's uid there when the owner
  /// coaches directly (seen live 2026-09-24: nine of twenty records), and
  /// the Organizations workspace already reads it that way.
  static bool isOwnerCoached(ClientModel m) {
    final t = (m.trainerId ?? '').trim();
    if (t.isEmpty) return true;
    final o = (m.adminId ?? '').trim();
    return o.isNotEmpty && t == o;
  }

  /// One line: "Coached by the owner" / "Coach Priya (active)" / …
  static String coachLine(
    ClientModel m, {
    required TrainerModel? trainer,
    required bool trainersKnown,
    bool trainersFailed = false,
  }) {
    if ((m.adminId ?? '').trim().isEmpty && isOwnerCoached(m)) {
      return 'No coach — the record has no organization';
    }
    if (isOwnerCoached(m)) return 'Coached by the organization owner';
    if (trainer != null) {
      final st = TrainerLanguage.standingOf(trainer);
      final name = TrainerLanguage.displayName(trainer);
      return switch (st) {
        TrainerStanding.working => 'Coach $name',
        TrainerStanding.onHold => 'Coach $name (on hold)',
        TrainerStanding.removed => 'Coach $name (removed)',
        TrainerStanding.unknown => 'Coach $name (status unrecognised)',
      };
    }
    if (trainersFailed) return 'Coach unavailable (trainer list failed)';
    if (!trainersKnown) return 'Loading coach…';
    return 'Coach record missing';
  }

  // ── account / activity / activation ───────────────────────────────────────

  static AccountLink accountLink(ClientModel m) {
    if (m.authUid.trim().isNotEmpty) return AccountLink.linked;
    if ((m.authUnlinkReason ?? '') == 'member_account_deleted' ||
        m.authUnlinkedAt != null) {
      return AccountLink.deletedByMember;
    }
    return AccountLink.neverClaimed;
  }

  static int? daysSinceActivity(ClientModel m, {required DateTime now}) {
    final t = m.lastActivityAt;
    if (t == null) return null;
    return _calendarDays(t, now);
  }

  static ActivityState activityState(ClientModel m, {required DateTime now}) {
    final d = daysSinceActivity(m, now: now);
    if (d == null) return ActivityState.none;
    if (d <= quietAfterDays) return ActivityState.recent;
    if (d <= dormantAfterDays) return ActivityState.quiet;
    return ActivityState.dormant;
  }

  static String activityLine(ClientModel m, {required DateTime now}) {
    final t = m.lastActivityAt;
    if (t == null) return 'No app activity recorded';
    return 'Last active ${OrganizationLanguage.relative(t, now: now)}';
  }

  static String activationLabel(String? stage) => switch (stage) {
    'onboarding' => 'Onboarding not finished',
    'awaitingTrainer' => 'Waiting for an organization',
    'preparingPlan' => 'Onboarded, plan not assigned yet',
    'ready' => 'Set up — has a plan',
    null || '' => 'Setup stage not computed',
    _ => 'Setup stage "$stage"',
  };

  /// The backend's training signal: `activationStage == 'ready'` means a plan
  /// is assigned. Any other computed stage means no plan yet; an uncomputed
  /// stage (legacy record) is unknown and claims nothing.
  static bool hasPlan(ClientModel m) => m.activationStage == 'ready';
  static bool hasNoPlanYet(ClientModel m) {
    final s = m.activationStage ?? '';
    return s.isNotEmpty && s != 'ready';
  }

  /// One short line for the directory's training column.
  static String trainingLine(ClientModel m) => switch (m.activationStage) {
    'ready' => 'Plan assigned',
    'preparingPlan' => 'No plan yet',
    'onboarding' => 'Onboarding not finished',
    'awaitingTrainer' => 'Waiting for an organization',
    null || '' => 'Training state not computed',
    _ => 'Stage "${m.activationStage}"',
  };

  static bool statusIsInactive(ClientModel m) => m.status != 'active';
  static bool statusIsUnknown(ClientModel m) =>
      !knownStatuses.contains(m.status);

  static String adherenceLine(ClientModel m) {
    final a = m.adherence;
    final score = _num(a?['score']);
    if (a == null || score == null) return 'Not computed yet';
    final w = _num(a['workoutPct']);
    final d = _num(a['dietPct']);
    final win = a['windowDays'];
    return 'Score ${score.round()}'
        '${w == null ? '' : ' · workouts ${w.round()}%'}'
        '${d == null ? '' : ' · diet ${d.round()}%'}'
        '${win == null ? '' : ' · last $win days'}';
  }

  static String checkInLine(ClientModel m, {required DateTime now}) {
    final st = (m.scheduleStatus ?? 'active');
    if (m.checkInCadenceDays == null && m.nextCheckInAt == null) {
      return 'No check-in cadence set';
    }
    if (st != 'active') return 'Check-in schedule $st';
    final next = m.nextCheckInAt;
    final cadence = m.checkInCadenceDays == null
        ? ''
        : ' · every ${m.checkInCadenceDays} days';
    if (next == null) return 'Cadence set$cadence';
    final overdue = now.isAfter(next);
    return '${overdue ? 'Check-in overdue since' : 'Next check-in'} '
        '${OrganizationLanguage.exact(next)}$cadence';
  }

  /// A coaching pause that covers [now].
  static bool pauseIsActive(ClientModel m, {required DateTime now}) {
    final p = m.coachingPause;
    if (p == null) return false;
    final from = memberDate(p['from']);
    final to = memberDate(p['to']);
    if (from != null && now.isBefore(from)) return false;
    if (to != null && now.isAfter(to)) return false;
    return true;
  }

  static String pauseLine(ClientModel m, {required DateTime now}) {
    final p = m.coachingPause;
    if (p == null) return 'No coaching pause';
    final type = _clean(p['type']) ?? 'pause';
    final to = memberDate(p['to']);
    final active = pauseIsActive(m, now: now);
    return '${active ? 'Paused' : 'Pause recorded'} ($type)'
        '${to == null ? ', open-ended' : ' until ${OrganizationLanguage.exact(to)}'}'
        '${_clean(p['note']) == null ? '' : ' — ${p['note']}'}';
  }

  static bool isRecent(ClientModel m, {required DateTime now}) =>
      m.createdAtKnown &&
      _calendarDays(m.createdAt, now) <= recentDays &&
      _calendarDays(m.createdAt, now) >= 0;

  static int _calendarDays(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  // ── issues ────────────────────────────────────────────────────────────────

  /// Issues computable from the record plus the organization and trainer
  /// lists the console already streams. [orgKnown] / [trainersKnown] are
  /// false while those lists are unread — then "missing" cannot be claimed.
  static List<MemberIssue> issues(
    ClientModel m, {
    required AdminModel? org,
    required bool orgKnown,
    required TrainerModel? trainer,
    required bool trainersKnown,
    required DateTime now,
  }) {
    final out = <MemberIssue>[];
    final state = membershipState(m, now: now);
    final orgId = (m.adminId ?? '').trim();

    if (orgId.isEmpty) {
      out.add(
        const MemberIssue(
          code: 'no_organization',
          severity: OrgIssueSeverity.critical,
          title: 'Not attached to any organization',
          why:
              'Every member record belongs to one organization. Without one no '
              'owner or coach can see this member, and the rules refuse every write.',
          whatToDo: 'A backend correction is needed; nothing here can fix it.',
        ),
      );
    } else if (orgKnown && org == null) {
      out.add(
        MemberIssue(
          code: 'orphaned',
          severity: OrgIssueSeverity.critical,
          title: 'Organization record is missing',
          why:
              'The member points at organization $orgId, but no such organization '
              'exists. Nobody can coach or renew this member.',
          whatToDo:
              'Check the Audit Log for what happened to the organization; '
              'a backend correction is needed.',
        ),
      );
    }

    if (statusIsUnknown(m)) {
      out.add(
        MemberIssue(
          code: 'unknown_status',
          severity: OrgIssueSeverity.attention,
          title: 'Status "${m.status}" is not recognised',
          why:
              'The apps only write active and inactive. The coach app treats '
              'anything else as switched off.',
          whatToDo:
              'Ask the owner to toggle the member off and on in their app, '
              'which rewrites the status.',
        ),
      );
    }

    final flag = flagDisagreement(m, now: now);
    if (flag == 'flag_active_after_expiry') {
      out.add(
        MemberIssue(
          code: flag!,
          severity: OrgIssueSeverity.attention,
          title: 'Still marked active although the term ended',
          why:
              'The term expired ${OrganizationLanguage.relative(m.membershipExpiry, now: now)}, '
              'but the record still says the membership is active. The hourly '
              'expiry sweep should have switched it off; the member may still '
              'have access they no longer pay for.',
          whatToDo:
              'Check the Operations Center for a failed sweep. The organization '
              'can also extend or re-sell the term, which resets the flag.',
        ),
      );
    } else if (flag == 'flag_inactive_during_term') {
      out.add(
        MemberIssue(
          code: flag!,
          severity: OrgIssueSeverity.attention,
          title: 'Marked inactive although the term has not ended',
          why:
              'The recorded term runs until ${OrganizationLanguage.exact(m.membershipExpiry)}, '
              'but the active flag is off — the member is locked out of '
              'something they paid for.',
          whatToDo:
              'The owner can re-record the term (extend) in their app, which '
              'switches access back on. If this repeats, report it.',
        ),
      );
    }

    if (org != null &&
        !OrganizationLanguage.canOperate(org) &&
        state.isCurrent) {
      out.add(
        MemberIssue(
          code: 'org_cannot_operate',
          severity: OrgIssueSeverity.attention,
          title: 'Paying member of an organization that cannot operate',
          why:
              'The organization is ${_orgWhy(org)}, so its coaches cannot write '
              'plans, reviews or check-ins for this member while the member\'s '
              'own term is still running.',
          whatToDo:
              'Resolve it on the organization: approve, reactivate or record '
              'their payment.',
        ),
      );
    }

    // Coach
    if (!isOwnerCoached(m)) {
      if (trainer != null) {
        final st = TrainerLanguage.standingOf(trainer);
        if (st != TrainerStanding.working) {
          out.add(
            MemberIssue(
              code: 'coach_not_working',
              severity: OrgIssueSeverity.attention,
              title: st == TrainerStanding.removed
                  ? 'Assigned to a removed trainer'
                  : 'Assigned to a trainer who is on hold',
              why:
                  'The coach cannot sign in, so this member\'s plans and '
                  'check-ins go unattended until they are reassigned.',
              whatToDo: 'Ask the owner to reassign the member in their app.',
            ),
          );
        }
        if (orgId.isNotEmpty && (trainer.assignedBy ?? '') != orgId) {
          out.add(
            MemberIssue(
              code: 'coach_foreign',
              severity: OrgIssueSeverity.critical,
              title: 'Coach belongs to a different organization',
              why:
                  'The assigned trainer works for another organization. The '
                  'rules stop them from reading this member, and the '
                  'organization\'s own staff do not see the assignment.',
              whatToDo:
                  'Ask the owner to reassign the member; report it if it recurs.',
            ),
          );
        }
      } else if (trainersKnown) {
        out.add(
          MemberIssue(
            code: 'coach_missing',
            severity: OrgIssueSeverity.attention,
            title: 'Assigned coach record is missing',
            why:
                'The member points at trainer ${m.trainerId}, but no such '
                'trainer exists. Their coaching has effectively stopped.',
            whatToDo: 'Ask the owner to reassign the member in their app.',
          ),
        );
      }
    }

    // Activation
    final stage = m.activationStage;
    if (stage != null &&
        stage.isNotEmpty &&
        stage != 'ready' &&
        state.isCurrent &&
        m.createdAtKnown &&
        _calendarDays(m.createdAt, now) >= stalledAfterDays) {
      out.add(
        MemberIssue(
          code: 'activation_stalled',
          severity: OrgIssueSeverity.attention,
          title:
              'Joined ${_calendarDays(m.createdAt, now)} days ago and still not set up',
          why:
              '${activationLabel(stage)}. A paying member without a plan is the '
              'strongest churn signal the platform records.',
          whatToDo: stage == 'onboarding'
              ? 'The member has not finished onboarding in their app; the '
                    'organization can nudge them.'
              : 'The coach has not assigned a plan; the owner can chase it.',
        ),
      );
    }

    // Dormancy on a paid term
    if (state.isCurrent && !pauseIsActive(m, now: now)) {
      final d = daysSinceActivity(m, now: now);
      if (d != null && d > dormantAfterDays) {
        out.add(
          MemberIssue(
            code: 'dormant',
            severity: OrgIssueSeverity.attention,
            title: 'No app activity for $d days on a running membership',
            why:
                'The member is paying but not using the app. Dormant members '
                'do not renew.',
            whatToDo:
                'Nothing here can act on a member directly; the organization '
                'and coach can reach out.',
          ),
        );
      }
    }

    if (emailOf(m) == null && phoneOf(m) == null) {
      out.add(
        const MemberIssue(
          code: 'no_contact',
          severity: OrgIssueSeverity.attention,
          title: 'No contact details on record',
          why:
              'Neither the coach record nor the member\'s own profile carries '
              'an email or phone. Nobody can reach this member outside the app.',
          whatToDo: 'The organization can add a phone in their app.',
        ),
      );
    }

    // Informational
    if (state == MembershipState.expiringSoon) {
      out.add(
        MemberIssue(
          code: 'expiring_soon',
          severity: OrgIssueSeverity.info,
          title:
              'Term ends ${OrganizationLanguage.relative(m.membershipExpiry, now: now)}',
          why:
              'Renewal is sold by the organization, in their app or the member\'s.',
          whatToDo: 'Nothing required.',
        ),
      );
    }
    if (state == MembershipState.frozen) {
      out.add(
        MemberIssue(
          code: 'frozen',
          severity: OrgIssueSeverity.info,
          title:
              'Membership frozen${m.membershipFrozenAt == null ? '' : ' since ${OrganizationLanguage.exact(m.membershipFrozenAt)}'}',
          why: 'The owner paused the term; it does not expire while frozen.',
          whatToDo: 'Nothing required.',
        ),
      );
    }
    if (pauseIsActive(m, now: now)) {
      out.add(
        MemberIssue(
          code: 'coaching_paused',
          severity: OrgIssueSeverity.info,
          title: pauseLine(m, now: now),
          why: 'The coach paused prescriptions; missed days are not counted.',
          whatToDo: 'Nothing required.',
        ),
      );
    }
    if (statusIsInactive(m) && !statusIsUnknown(m)) {
      out.add(
        const MemberIssue(
          code: 'switched_off',
          severity: OrgIssueSeverity.info,
          title: 'Switched off by the owner',
          why:
              'The owner marked this member inactive in their app; coaching '
              'features are off regardless of the membership term.',
          whatToDo: 'Nothing required.',
        ),
      );
    }
    switch (accountLink(m)) {
      case AccountLink.deletedByMember:
        out.add(
          MemberIssue(
            code: 'account_deleted',
            severity: OrgIssueSeverity.info,
            title:
                'Member deleted their account${m.authUnlinkedAt == null ? '' : ' on ${OrganizationLanguage.exact(m.authUnlinkedAt)}'}',
            why:
                'The organization\'s record is retained (their business record), '
                'but nobody can sign in as this member any more.',
            whatToDo: 'Nothing required.',
          ),
        );
      case AccountLink.neverClaimed:
        out.add(
          const MemberIssue(
            code: 'never_claimed',
            severity: OrgIssueSeverity.info,
            title: 'No app account linked yet',
            why:
                'The record exists but no member has signed in against it, so '
                'there is no activity, progress or check-in data to show.',
            whatToDo:
                'The member claims the record by signing up with the same phone.',
          ),
        );
      case AccountLink.linked:
        break;
    }
    return out;
  }

  static String _orgWhy(AdminModel org) {
    final st = OrganizationLanguage.standingOf(org);
    if (st == OrgStanding.blocked) return 'blocked';
    if (st == OrgStanding.awaitingApproval) return 'awaiting approval';
    if (st == OrgStanding.unknown) return 'in an unrecognised status';
    return 'without an active subscription';
  }

  /// Issues that need the payment feed (detail level).
  static List<MemberIssue> paymentIssues(List<MemberPaymentModel> payments) {
    final unverified = payments.where((p) => p.captureUnverified).length;
    if (unverified == 0) return const [];
    return [
      MemberIssue(
        code: 'capture_unverified',
        severity: OrgIssueSeverity.attention,
        title:
            '${OrganizationLanguage.plural(unverified, 'online payment was', 'online payments were')} activated without gateway confirmation',
        why:
            'The membership was switched on although Razorpay did not confirm '
            'the capture. This is the only kind of receipt that can describe '
            'money the platform does not hold.',
        whatToDo:
            'Open Settlements for this member; the settlement engine holds '
            'unconfirmed captures until the webhook resolves them.',
      ),
    ];
  }

  /// One person, several organizations (detail level, from the sibling feed).
  static List<MemberIssue> siblingIssues(int otherRecords) {
    if (otherRecords <= 0) return const [];
    return [
      MemberIssue(
        code: 'multiple_records',
        severity: OrgIssueSeverity.info,
        title:
            'Also a member of ${OrganizationLanguage.plural(otherRecords, 'other organization')}',
        why:
            'A person holds one record per organization they join. Each has its '
            'own term, coach and activity.',
        whatToDo:
            'Nothing required. The other records are listed under Profile.',
      ),
    ];
  }

  static bool needsAttention(
    ClientModel m, {
    required AdminModel? org,
    required bool orgKnown,
    required TrainerModel? trainer,
    required bool trainersKnown,
    required DateTime now,
  }) => issues(
    m,
    org: org,
    orgKnown: orgKnown,
    trainer: trainer,
    trainersKnown: trainersKnown,
    now: now,
  ).any((i) => i.needsAttention);

  static OrgIssueSeverity? worstSeverity(List<MemberIssue> issues) {
    OrgIssueSeverity? worst;
    for (final i in issues) {
      if (worst == null || i.severity.index < worst.index) worst = i.severity;
    }
    return worst;
  }

  static List<MemberIssue> sortIssues(List<MemberIssue> l) {
    final c = [...l];
    c.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return c;
  }

  // ── list: search, filter, sort ────────────────────────────────────────────

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool matches(
    ClientModel m,
    String query, {
    String orgName = '',
    String coachName = '',
  }) {
    final q = _norm(query);
    if (q.isEmpty) return true;
    final exact = query.trim();
    if (m.docId == exact || m.authUid == exact) return true;
    final digits = q.replaceAll(RegExp(r'[^0-9+]'), '');
    return _norm(displayName(m)).contains(q) ||
        _norm(m.name).contains(q) ||
        _norm(emailOf(m) ?? '').contains(q) ||
        (digits.length >= 4 &&
            _norm(
              phoneOf(m) ?? '',
            ).replaceAll(RegExp(r'[^0-9+]'), '').contains(digits)) ||
        _norm(planName(m)).contains(q) ||
        _norm(goalOf(m) ?? '').contains(q) ||
        _norm(orgName).contains(q) ||
        _norm(coachName).contains(q);
  }

  /// `all` = every live record. The rest are this screen's own work queues.
  static const List<String> filterKeys = [
    'all',
    'attention',
    'current',
    'expiring',
    'lapsed',
    'frozen',
    'ownerCoached',
    'dormant',
    'noPlan',
    'unlinked',
    'recent',
  ];

  /// The tiles shown above the list, in order.
  static const List<String> tileKeys = [
    'all',
    'attention',
    'current',
    'expiring',
    'lapsed',
    'dormant',
  ];

  static String filterLabel(String key) => switch (key) {
    'all' => 'All members',
    'attention' => 'Needs attention',
    'current' => 'Membership active',
    'expiring' => 'Expiring in $expiringSoonDays days',
    'lapsed' => 'Expired or none',
    'frozen' => 'Frozen',
    'ownerCoached' => 'Coached by the owner',
    'dormant' => 'Dormant on a paid term',
    'noPlan' => 'Paying, no plan assigned yet',
    'unlinked' => 'No app account',
    'recent' => 'Joined in the last $recentDays days',
    _ => 'Filter "$key"',
  };

  /// Chip-length labels for the secondary queues (the tiles use the full ones).
  static String shortFilterLabel(String key) => switch (key) {
    'frozen' => 'Frozen',
    'ownerCoached' => 'Owner-coached',
    'unlinked' => 'No app account',
    'noPlan' => 'No plan yet',
    'recent' => 'New ($recentDays days)',
    _ => filterLabel(key),
  };

  static bool matchesFilter(
    ClientModel m,
    String key, {
    required AdminModel? org,
    required bool orgKnown,
    required TrainerModel? trainer,
    required bool trainersKnown,
    required DateTime now,
  }) {
    if (m.isDeleted) return false;
    final s = membershipState(m, now: now);
    return switch (key) {
      'all' => true,
      'attention' => needsAttention(
        m,
        org: org,
        orgKnown: orgKnown,
        trainer: trainer,
        trainersKnown: trainersKnown,
        now: now,
      ),
      'current' => s.isCurrent,
      'expiring' => s == MembershipState.expiringSoon,
      'lapsed' => s == MembershipState.expired || s == MembershipState.none,
      'frozen' => s == MembershipState.frozen,
      'ownerCoached' => isOwnerCoached(m),
      'dormant' =>
        s.isCurrent &&
            activityState(m, now: now) == ActivityState.dormant &&
            !pauseIsActive(m, now: now),
      'unlinked' => accountLink(m) != AccountLink.linked,
      'noPlan' => s.isCurrent && hasNoPlanYet(m),
      'recent' => isRecent(m, now: now),
      _ => false,
    };
  }

  static const List<String> sortKeys = [
    'attention',
    'newest',
    'oldest',
    'name',
    'nameDesc',
    'organization',
    'expiry',
    'activity',
  ];

  static String sortLabel(String key) => switch (key) {
    'attention' => 'Needs attention first',
    'newest' => 'Newest first',
    'oldest' => 'Oldest first',
    'name' => 'Name A–Z',
    'nameDesc' => 'Name Z–A',
    'organization' => 'Organization A–Z',
    'expiry' => 'Membership ending soonest',
    'activity' => 'Last active, most recent',
    _ => key,
  };

  static int _rank(OrgIssueSeverity? s) => s == null ? 3 : s.index;

  static List<ClientModel> sorted(
    Iterable<ClientModel> rows,
    String key, {
    required String Function(ClientModel) orgNameOf,
    required List<MemberIssue> Function(ClientModel) issuesOf,
  }) {
    final list = rows.toList();
    int byNewest(ClientModel a, ClientModel b) {
      if (a.createdAtKnown != b.createdAtKnown) {
        return a.createdAtKnown ? -1 : 1;
      }
      return b.createdAt.compareTo(a.createdAt);
    }

    int byName(ClientModel a, ClientModel b) =>
        _norm(displayName(a)).compareTo(_norm(displayName(b)));

    switch (key) {
      case 'name':
        list.sort((a, b) {
          final c = byName(a, b);
          return c != 0 ? c : byNewest(a, b);
        });
      case 'nameDesc':
        list.sort((a, b) {
          final c = byName(b, a);
          return c != 0 ? c : byNewest(a, b);
        });
      case 'oldest':
        list.sort((a, b) {
          // Undated records cannot claim to be oldest; they stay last.
          if (a.createdAtKnown != b.createdAtKnown) {
            return a.createdAtKnown ? -1 : 1;
          }
          return a.createdAt.compareTo(b.createdAt);
        });
      case 'organization':
        list.sort((a, b) {
          final c = _norm(orgNameOf(a)).compareTo(_norm(orgNameOf(b)));
          return c != 0 ? c : byName(a, b);
        });
      case 'expiry':
        list.sort((a, b) {
          final x = a.membershipExpiry, y = b.membershipExpiry;
          if (x == null && y == null) return byName(a, b);
          if (x == null) return 1;
          if (y == null) return -1;
          return x.compareTo(y);
        });
      case 'activity':
        list.sort((a, b) {
          final x = a.lastActivityAt, y = b.lastActivityAt;
          if (x == null && y == null) return byName(a, b);
          if (x == null) return 1;
          if (y == null) return -1;
          return y.compareTo(x);
        });
      case 'attention':
        list.sort((a, b) {
          final c = _rank(
            worstSeverity(issuesOf(a)),
          ).compareTo(_rank(worstSeverity(issuesOf(b))));
          return c != 0 ? c : byNewest(a, b);
        });
      default:
        list.sort(byNewest);
    }
    return list;
  }

  // ── history ───────────────────────────────────────────────────────────────

  static MemberEvent? fromAudit(
    AuditLogModel l, {
    required String Function(String) actorOf,
    String Function(String coachUid)? coachNameOf,
  }) {
    final d = l.details;
    final tech = <String, dynamic>{
      'action': l.action,
      'actorUid': l.actorUid,
      ...d,
    };
    final actor = actorOf(l.actorUid);
    String plan() => _clean(d['planName']) ?? _clean(d['planId']) ?? '';
    switch (l.action) {
      case 'membership_activated_online':
      case 'membership_activated':
        return MemberEvent(
          at: l.createdAt,
          title: 'Membership activated (online payment)',
          detail: plan(),
          actor: actor,
          technical: tech,
        );
      case 'membership_activated_free':
        return MemberEvent(
          at: l.createdAt,
          title: 'Membership activated with a 100% coupon',
          detail: plan(),
          actor: actor,
          technical: tech,
        );
      case 'offline_membership_recorded':
        return MemberEvent(
          at: l.createdAt,
          title: 'Offline payment recorded by the owner',
          detail: plan(),
          actor: actor,
          technical: tech,
        );
      case 'membership_expired':
        return MemberEvent(
          at: l.createdAt,
          title: 'Membership expired (automatic sweep)',
          actor: actor,
          technical: tech,
        );
      case 'set_client_coach':
        // assignments_coach.ts writes {from, to, source, reason}; older rows
        // may carry toCoachId. An empty `to` is a hand-back to the owner.
        final to = (d['to'] ?? d['toCoachId'] ?? '').toString().trim();
        final from = (d['from'] ?? d['fromCoachId'] ?? '').toString().trim();
        final source = (d['source'] ?? '').toString().replaceAll('_', ' ');
        return MemberEvent(
          at: l.createdAt,
          title: to.isEmpty
              ? 'Coach unassigned — back to the owner'
              : 'Coach assigned to ${coachNameOf == null ? 'trainer $to' : coachNameOf(to)}',
          detail: [
            if (from.isNotEmpty)
              'from ${coachNameOf == null ? 'trainer $from' : coachNameOf(from)}',
            if (source.isNotEmpty) source,
            if (_clean(d['reason']) != null) d['reason'].toString(),
          ].join(' · '),
          actor: actor,
          technical: tech,
        );
      case 'set_coaching_pause':
        return MemberEvent(
          at: l.createdAt,
          title: d['cleared'] == true
              ? 'Coaching pause cleared'
              : 'Coaching paused',
          detail: _clean(d['type']) ?? '',
          actor: actor,
          technical: tech,
        );
      case 'claim_client_account':
        return MemberEvent(
          at: l.createdAt,
          title: 'Member linked their app account to this record',
          actor: actor,
          technical: tech,
        );
      case 'set_nutrition_targets':
        return MemberEvent(
          at: l.createdAt,
          title: 'Nutrition targets set',
          actor: actor,
          technical: tech,
        );
      case 'member_account_deleted':
      case 'delete_member_account':
        return MemberEvent(
          at: l.createdAt,
          title: 'Member deleted their account',
          actor: actor,
          technical: tech,
        );
      default:
        if (l.action.startsWith('privileged_read')) return null;
        return MemberEvent(
          at: l.createdAt,
          title: l.actionLabel,
          actor: actor,
          technical: tech,
        );
    }
  }

  static MemberEvent fromPayment(MemberPaymentModel p) {
    final amount = p.amount == null
        ? ''
        : OrganizationLanguage.rupees(p.amount!);
    return MemberEvent(
      at: p.createdAt,
      title: p.source == 'coupon_full_discount'
          ? 'Free membership via coupon'
          : p.source == 'offline'
          ? 'Offline payment recorded'
          : p.source == 'manual'
          ? 'Term extended manually'
          : 'Payment received',
      detail: [
        if (p.planName.isNotEmpty) p.planName,
        if (amount.isNotEmpty) amount,
        sourceOf(
          source: p.source.isEmpty ? null : p.source,
          method: p.method.isEmpty ? null : p.method,
          coupon: p.couponCode.isEmpty ? null : p.couponCode,
          online: p.isOnline,
        ),
        if (p.captureUnverified) 'capture NOT confirmed by the gateway',
      ].join(' · '),
      technical: {'receiptId': p.id, ...p.raw},
    );
  }

  static MemberEvent fromCoachEvent(
    Map<String, dynamic> e,
    String id, {
    required String Function(String) coachNameOf,
  }) {
    final to = (e['toCoachId'] ?? '').toString();
    final from = (e['fromCoachId'] ?? '').toString();
    final source = (e['source'] ?? '').toString();
    return MemberEvent(
      at: memberDate(e['at']) ?? memberDate(e['createdAt']),
      title: to.isEmpty
          ? 'Coach unassigned — back to the owner'
          : 'Coach changed to ${coachNameOf(to)}',
      detail: [
        if (from.isNotEmpty) 'from ${coachNameOf(from)}',
        if (source.isNotEmpty) source.replaceAll('_', ' '),
        if (_clean(e['reason']) != null) e['reason'].toString(),
      ].join(' · '),
      actor: (e['actorName'] ?? '').toString(),
      technical: {'eventId': id, ...e},
    );
  }

  static List<MemberEvent> timeline(Iterable<MemberEvent> events) {
    final list = events.toList();
    list.sort((a, b) {
      if (a.at == null && b.at == null) return 0;
      if (a.at == null) return 1;
      if (b.at == null) return -1;
      return b.at!.compareTo(a.at!);
    });
    return list;
  }

  // ── words ─────────────────────────────────────────────────────────────────

  static String joinedLine(ClientModel m, {required DateTime now}) =>
      m.createdAtKnown
      ? 'Joined ${OrganizationLanguage.exact(m.createdAt)} (${OrganizationLanguage.relative(m.createdAt, now: now)})'
      : 'Join date not recorded';

  static String bodyLine(ClientModel m, {required DateTime now}) {
    final parts = <String>[
      if (genderOf(m) != null) genderOf(m)!,
      if (ageOf(m, now: now) != null) '${ageOf(m, now: now)} yrs',
      if (heightCm(m) != null) '${_fmt(heightCm(m)!)} cm',
      if (weightKg(m) != null) '${_fmt(weightKg(m)!)} kg',
    ];
    return parts.isEmpty ? 'Not recorded' : parts.join(' · ');
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
