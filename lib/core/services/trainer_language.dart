// TRAINERS — the words, rules and orderings of the trainer oversight
// workspace. PURE: no Firebase, no widgets.
//
// WHAT A TRAINER IS. `trainers/{uid}` is a coach account created by an
// organization owner (`createTrainer`); the document id IS the Firebase Auth
// uid. It belongs to exactly one organization (`assignedBy` = the owner uid,
// immutable by rules). Its `status` is one of active | inactive | removed —
// the only values any backend writer produces. `orgActive` is a cascade of
// the ORGANIZATION's operate-state, stamped by the backend whenever the
// organization's standing or subscription changes.
//
// WHO MAY CHANGE IT. The organization owner, in the Trainersarena app —
// `setTrainerStatus`, `removeTrainer`, `restoreTrainer`, `setTrainerPermissions`
// are all owner-gated; the rules deny direct writes and creation/deletion to
// everyone. The platform (this console) reads and never writes. Its power on
// this screen is understanding and ROUTING: every issue points at the
// organization, where the platform's real actions live.

import '../../models/admin_model.dart';
import '../../models/audit_log_model.dart';
import '../../models/clints_model.dart';
import '../../models/trainer_model.dart';
import 'organization_language.dart';

// ═════════════════════════════════════════════════════════════════════════════
// STANDING — the trainer's own status, in words
// ═════════════════════════════════════════════════════════════════════════════

enum TrainerStanding { working, onHold, removed, unknown }

extension TrainerStandingX on TrainerStanding {
  String get label => switch (this) {
    TrainerStanding.working => 'Active',
    TrainerStanding.onHold => 'On hold',
    TrainerStanding.removed => 'Removed',
    TrainerStanding.unknown => 'Unrecognised status',
  };

  String get meaning => switch (this) {
    TrainerStanding.working =>
      'The owner has this trainer active. They can sign in and work as long '
          'as the organization can operate.',
    TrainerStanding.onHold =>
      'The owner has paused this trainer, or restored them after a removal. '
          'Their sign-in is disabled until the owner reactivates them.',
    TrainerStanding.removed =>
      'The owner removed this trainer. The account is disabled, it occupies '
          'no seat, and its members were unassigned. The owner can restore it.',
    TrainerStanding.unknown =>
      'The stored status is not one the platform writes. The console cannot '
          'say whether this trainer can work.',
  };
}

/// Whether the trainer's APP ACCESS is on, as the backend stamped it.
enum TrainerAccess { on, paused, notStamped }

// ═════════════════════════════════════════════════════════════════════════════
// ISSUES
// ═════════════════════════════════════════════════════════════════════════════

class TrainerIssue {
  final String code;
  final OrgIssueSeverity severity;
  final String title;
  final String why;
  final String whatToDo;

  const TrainerIssue({
    required this.code,
    required this.severity,
    required this.title,
    required this.why,
    required this.whatToDo,
  });

  bool get needsAttention => severity != OrgIssueSeverity.info;
}

// ═════════════════════════════════════════════════════════════════════════════
// EVENTS
// ═════════════════════════════════════════════════════════════════════════════

class TrainerEvent {
  final DateTime? at;
  final String title;
  final String detail;
  final String actor;
  final Map<String, dynamic> technical;

  const TrainerEvent({
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

class TrainerLanguage {
  TrainerLanguage._();

  /// "Recently added" for the list.
  static const int recentDays = 30;

  /// The five permission keys the backend enforces, in display order, with
  /// the words an owner would use.
  static const Map<String, String> permissionLabels = {
    'workoutPlans': 'Workout plans',
    'dietPlans': 'Diet plans',
    'weeklyPlans': 'Weekly plans',
    'exercises': 'Exercise library',
    'food': 'Food library',
  };

  // ── identity ──────────────────────────────────────────────────────────────

  static String displayName(TrainerModel t) =>
      t.name.trim().isEmpty ? 'Name not recorded' : t.name.trim();

  static String email(TrainerModel t) =>
      t.email.trim().isEmpty ? 'No sign-in email on record' : t.email.trim();

  static String initial(TrainerModel t) {
    final n = t.name.trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  static String id(TrainerModel t) => t.uid.isNotEmpty ? t.uid : t.docId;

  // ── standing / access ─────────────────────────────────────────────────────

  static bool isRemoved(TrainerModel t) => t.isDeleted || t.status == 'removed';

  /// The document carries no `status` at all; the model defaults it to
  /// `pending`, which the backend never writes. Said as "not recorded".
  static bool statusNotRecorded(TrainerModel t) =>
      t.status == 'pending' &&
      (t.metadata?['createdFrom'] ?? '') != 'createTrainer';

  static TrainerStanding standingOf(TrainerModel t) {
    if (isRemoved(t)) return TrainerStanding.removed;
    return switch (t.status) {
      'active' => TrainerStanding.working,
      'inactive' => TrainerStanding.onHold,
      // A missing status field reads as 'pending' from the model — a legacy
      // shape the backend never writes. Treat as on hold (cannot be proven
      // working) and say so through [statusNotRecorded].
      'pending' => TrainerStanding.onHold,
      _ => TrainerStanding.unknown,
    };
  }

  static TrainerAccess accessOf(TrainerModel t) => switch (t.orgActive) {
    true => TrainerAccess.on,
    false => TrainerAccess.paused,
    null => TrainerAccess.notStamped,
  };

  static String accessLabel(TrainerModel t) {
    if (isRemoved(t)) return 'Sign-in disabled';
    return switch (accessOf(t)) {
      TrainerAccess.on => 'App access on',
      TrainerAccess.paused => 'App access paused',
      TrainerAccess.notStamped => 'Access state not stamped',
    };
  }

  /// One line answering "can this person work right now?", combining the
  /// trainer's own status with the organization's ability to operate.
  static String workingLine(TrainerModel t, AdminModel? org) {
    final s = standingOf(t);
    if (s == TrainerStanding.removed) return 'Removed — cannot sign in';
    if (s == TrainerStanding.onHold) {
      return 'On hold — sign-in disabled by the owner';
    }
    if (s == TrainerStanding.unknown) return 'Working state unknown';
    if (org == null) return 'Active, but the organization record is missing';
    if (!OrganizationLanguage.canOperate(org)) {
      return 'Active, but the organization cannot operate — ${_orgWhy(org)}';
    }
    return 'Working — can coach members and author plans';
  }

  static String _orgWhy(AdminModel org) {
    final st = OrganizationLanguage.standingOf(org);
    if (st == OrgStanding.blocked) return 'it is blocked';
    if (st == OrgStanding.awaitingApproval) return 'it is awaiting approval';
    if (st == OrgStanding.unknown) return 'its status is unrecognised';
    return 'no active subscription';
  }

  static bool isRecent(TrainerModel t, {required DateTime now}) =>
      _calendarDays(t.createdAt, now) <= recentDays &&
      _calendarDays(t.createdAt, now) >= 0;

  static int _calendarDays(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  // ── issues ────────────────────────────────────────────────────────────────

  /// Issues computable from the trainer record plus the organization record
  /// the list already has. [orgKnown] is false while the organization list is
  /// unread — then "organization missing" cannot be claimed.
  static List<TrainerIssue> issues(
    TrainerModel t, {
    required AdminModel? org,
    required bool orgKnown,
    required DateTime now,
  }) {
    final out = <TrainerIssue>[];
    final s = standingOf(t);
    final removed = s == TrainerStanding.removed;

    if (s == TrainerStanding.unknown) {
      out.add(
        TrainerIssue(
          code: 'unknown_status',
          severity: OrgIssueSeverity.critical,
          title: 'Status "${t.status}" is not recognised',
          why:
              'The platform only writes active, inactive and removed. The apps '
              'and the rules cannot tell whether this trainer can work.',
          whatToDo:
              'Ask the owner to deactivate and reactivate the trainer in '
              'their app, which rewrites the status.',
        ),
      );
    }

    if ((t.assignedBy ?? '').trim().isEmpty) {
      out.add(
        const TrainerIssue(
          code: 'no_organization',
          severity: OrgIssueSeverity.critical,
          title: 'Not attached to any organization',
          why:
              'Every trainer belongs to exactly one organization. Without one, '
              'no owner can manage this account and the rules refuse its writes.',
          whatToDo: 'A backend correction is needed; nothing here can fix it.',
        ),
      );
    } else if (orgKnown && org == null) {
      out.add(
        TrainerIssue(
          code: 'orphaned',
          severity: OrgIssueSeverity.critical,
          title: 'Organization record is missing',
          why:
              'The trainer points at organization ${t.assignedBy}, but no such '
              'organization exists. Nobody can manage this account and the '
              'backend treats it as not operating.',
          whatToDo:
              'Check the Audit Log for what happened to the organization; '
              'a backend correction is needed.',
        ),
      );
    }

    if (org != null) {
      final operating = OrganizationLanguage.canOperate(org);
      if (!removed && t.orgActive != null && t.orgActive != operating) {
        out.add(
          TrainerIssue(
            code: 'access_out_of_step',
            severity: OrgIssueSeverity.critical,
            title: operating
                ? 'App access is paused although the organization can operate'
                : 'App access is on although the organization cannot operate',
            why:
                'The access flag on this trainer is a copy of the organization\'s '
                'state, re-stamped by the backend on every status or '
                'subscription change. It is out of step, so the coach app shows '
                'the wrong state.',
            whatToDo:
                'Open the organization: its Health offers "Re-apply status '
                'effects", which re-runs this sync for the current status '
                'without changing it or notifying anyone.',
          ),
        );
      }
      if (s == TrainerStanding.working && !operating && t.orgActive != true) {
        out.add(
          TrainerIssue(
            code: 'org_cannot_operate',
            severity: OrgIssueSeverity.attention,
            title: 'Active, but the organization cannot operate',
            why:
                'The trainer is active, but ${_orgWhy(org)} — every write from '
                'this trainer is refused until the organization is restored.',
            whatToDo:
                'Resolve it on the organization: approve, reactivate or '
                'record their payment.',
          ),
        );
      }
      final seated = org.trainerIds.contains(id(t));
      if (removed && seated) {
        out.add(
          const TrainerIssue(
            code: 'removed_still_seated',
            severity: OrgIssueSeverity.attention,
            title: 'Removed, but still counted as a seat',
            why:
                'The organization\'s seat list still contains this trainer, so '
                'the owner is paying for a seat nobody uses.',
            whatToDo:
                'The backend re-syncs seats on the next remove or restore. '
                'If it persists, report it.',
          ),
        );
      } else if (!removed && !seated) {
        out.add(
          const TrainerIssue(
            code: 'not_on_seat_list',
            severity: OrgIssueSeverity.attention,
            title: 'Live trainer missing from the organization\'s seat list',
            why:
                'Seat limits are enforced against that list, so the owner may '
                'be able to add more trainers than their plan allows.',
            whatToDo:
                'The backend re-syncs seats on the next trainer change. '
                'If it persists, report it.',
          ),
        );
      }
    }

    if (t.email.trim().isEmpty) {
      out.add(
        const TrainerIssue(
          code: 'no_email',
          severity: OrgIssueSeverity.attention,
          title: 'No sign-in email on record',
          why: 'The console cannot tell who signs in as this trainer.',
          whatToDo:
              'Check the account in Firebase Auth; nothing here can fix it.',
        ),
      );
    }

    if (statusNotRecorded(t) && !removed) {
      out.add(
        const TrainerIssue(
          code: 'status_not_recorded',
          severity: OrgIssueSeverity.info,
          title: 'Status not recorded — shown as on hold',
          why:
              'A legacy document with no status field. The backend writes one '
              'on the next owner action.',
          whatToDo: 'Nothing required.',
        ),
      );
    }
    if (s == TrainerStanding.onHold &&
        !removed &&
        t.removedAt == null &&
        (t.metadata?['createdFrom'] ?? '') == 'createTrainer' &&
        t.status == 'inactive') {
      // Nothing further: a plain deactivation.
    }
    if (!removed && t.lastLogin == null) {
      out.add(
        const TrainerIssue(
          code: 'never_signed_in',
          severity: OrgIssueSeverity.info,
          title: 'Never signed in (or sign-in is not recorded)',
          why: 'The coach app stamps the last sign-in; none is on record.',
          whatToDo:
              'Nothing required. The owner can resend the sign-in details.',
        ),
      );
    }
    if (removed) {
      out.add(
        TrainerIssue(
          code: 'removed',
          severity: OrgIssueSeverity.info,
          title:
              'Removed by the owner${t.removedAt != null ? ' on ${OrganizationLanguage.exact(t.removedAt)}' : ''}',
          why:
              'The account is disabled and occupies no seat. The owner can restore '
              'it, after which sign-in stays disabled until they reactivate it.',
          whatToDo: 'Nothing required.',
        ),
      );
    }
    return out;
  }

  /// Issues that need the members feed (detail level).
  static List<TrainerIssue> memberIssues(
    TrainerModel t,
    List<ClientModel> members,
  ) {
    final s = standingOf(t);
    if (members.isEmpty || s == TrainerStanding.working) return const [];
    return [
      TrainerIssue(
        code: 'members_without_working_coach',
        severity: OrgIssueSeverity.attention,
        title:
            '${OrganizationLanguage.plural(members.length, 'member is', 'members are')} still assigned to this ${s == TrainerStanding.removed ? 'removed' : 'on-hold'} trainer',
        why:
            'Those members have a coach who cannot sign in. Their plans and '
            'check-ins go unattended until they are reassigned.',
        whatToDo: 'Ask the owner to reassign them in their app.',
      ),
    ];
  }

  static bool needsAttention(
    TrainerModel t, {
    required AdminModel? org,
    required bool orgKnown,
    required DateTime now,
  }) => issues(
    t,
    org: org,
    orgKnown: orgKnown,
    now: now,
  ).any((i) => i.needsAttention);

  static OrgIssueSeverity? worstSeverity(
    TrainerModel t, {
    required AdminModel? org,
    required bool orgKnown,
    required DateTime now,
  }) {
    OrgIssueSeverity? worst;
    for (final i in issues(t, org: org, orgKnown: orgKnown, now: now)) {
      if (worst == null || i.severity.index < worst.index) worst = i.severity;
    }
    return worst;
  }

  static List<TrainerIssue> sortIssues(List<TrainerIssue> l) {
    final c = [...l];
    c.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return c;
  }

  // ── list: search, filter, sort ────────────────────────────────────────────

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool matches(TrainerModel t, String query, {String orgName = ''}) {
    final q = _norm(query);
    if (q.isEmpty) return true;
    if (t.docId == query.trim() || t.uid == query.trim()) return true;
    return _norm(t.name).contains(q) ||
        _norm(t.email).contains(q) ||
        _norm(t.phone).replaceAll(' ', '').contains(q.replaceAll(' ', '')) ||
        _norm(t.specialization ?? '').contains(q) ||
        _norm(orgName).contains(q);
  }

  /// `all` = every SEAT (removed excluded); `active`/`inactive`/`removed` are
  /// the keys the existing KPI/filter contract uses; the rest are this
  /// screen's own.
  static const List<String> filterKeys = [
    'all',
    'attention',
    'active',
    'inactive',
    'removed',
    'recent',
  ];

  static String filterLabel(String key) => switch (key) {
    'all' => 'All trainers',
    'attention' => 'Needs attention',
    'active' => 'Active',
    'inactive' => 'On hold',
    'removed' => 'Removed',
    'recent' => 'Added in the last $recentDays days',
    _ => 'Status "$key"',
  };

  static bool matchesFilter(
    TrainerModel t,
    String key, {
    required AdminModel? org,
    required bool orgKnown,
    required DateTime now,
  }) {
    final s = standingOf(t);
    return switch (key) {
      'all' => s != TrainerStanding.removed,
      'attention' => needsAttention(t, org: org, orgKnown: orgKnown, now: now),
      'active' => s == TrainerStanding.working,
      'inactive' => s == TrainerStanding.onHold || s == TrainerStanding.unknown,
      'removed' => s == TrainerStanding.removed,
      'recent' => s != TrainerStanding.removed && isRecent(t, now: now),
      _ => t.status == key,
    };
  }

  static const List<String> sortKeys = [
    'attention',
    'newest',
    'name',
    'organization',
    'signin',
  ];

  static String sortLabel(String key) => switch (key) {
    'attention' => 'Needs attention first',
    'newest' => 'Newest first',
    'name' => 'Name A–Z',
    'organization' => 'Organization A–Z',
    'signin' => 'Last sign-in, most recent',
    _ => key,
  };

  static int _rank(OrgIssueSeverity? s) => s == null ? 3 : s.index;

  static List<TrainerModel> sorted(
    Iterable<TrainerModel> rows,
    String key, {
    required AdminModel? Function(TrainerModel) orgOf,
    required bool orgKnown,
    required DateTime now,
  }) {
    final list = rows.toList();
    int byNewest(TrainerModel a, TrainerModel b) =>
        b.createdAt.compareTo(a.createdAt);
    int byName(TrainerModel a, TrainerModel b) =>
        _norm(displayName(a)).compareTo(_norm(displayName(b)));
    String orgName(TrainerModel t) {
      final o = orgOf(t);
      return o == null ? '' : _norm(OrganizationLanguage.displayName(o));
    }

    switch (key) {
      case 'name':
        list.sort((a, b) {
          final c = byName(a, b);
          return c != 0 ? c : byNewest(a, b);
        });
      case 'organization':
        list.sort((a, b) {
          final c = orgName(a).compareTo(orgName(b));
          return c != 0 ? c : byName(a, b);
        });
      case 'signin':
        list.sort((a, b) {
          final x = a.lastLogin, y = b.lastLogin;
          if (x == null && y == null) return byName(a, b);
          if (x == null) return 1;
          if (y == null) return -1;
          return y.compareTo(x);
        });
      case 'attention':
        list.sort((a, b) {
          final c =
              _rank(
                worstSeverity(a, org: orgOf(a), orgKnown: orgKnown, now: now),
              ).compareTo(
                _rank(
                  worstSeverity(b, org: orgOf(b), orgKnown: orgKnown, now: now),
                ),
              );
          return c != 0 ? c : byNewest(a, b);
        });
      default:
        list.sort(byNewest);
    }
    return list;
  }

  // ── history ───────────────────────────────────────────────────────────────

  static TrainerEvent? fromAudit(
    AuditLogModel l, {
    required String Function(String) actorOf,
  }) {
    final d = l.details;
    final tech = <String, dynamic>{
      'action': l.action,
      'actorUid': l.actorUid,
      ...d,
    };
    final actor = actorOf(l.actorUid);
    switch (l.action) {
      case 'create_trainer':
        return TrainerEvent(
          at: l.createdAt,
          title: 'Trainer account created',
          actor: actor,
          technical: tech,
        );
      case 'set_trainer_status':
        final s = (d['status'] ?? '').toString();
        return TrainerEvent(
          at: l.createdAt,
          title: s == 'active'
              ? 'Reactivated by the owner'
              : s == 'inactive'
              ? 'Put on hold by the owner'
              : 'Status changed to "$s"',
          actor: actor,
          technical: tech,
        );
      case 'remove_trainer':
        final n = d['clientsUnassigned'];
        return TrainerEvent(
          at: l.createdAt,
          title: 'Removed by the owner',
          detail: n is num && n > 0
              ? '${OrganizationLanguage.plural(n.toInt(), 'member')} unassigned'
              : '',
          actor: actor,
          technical: tech,
        );
      case 'restore_trainer':
        return TrainerEvent(
          at: l.createdAt,
          title: 'Restored by the owner (on hold until reactivated)',
          actor: actor,
          technical: tech,
        );
      case 'set_trainer_permissions':
        return TrainerEvent(
          at: l.createdAt,
          title: 'Permissions changed',
          detail: _permissionDiff(d['before'], d['after']),
          actor: actor,
          technical: tech,
        );
      default:
        if (l.action.startsWith('privileged_read')) return null;
        return TrainerEvent(
          at: l.createdAt,
          title: l.actionLabel,
          actor: actor,
          technical: tech,
        );
    }
  }

  static String _permissionDiff(dynamic before, dynamic after) {
    if (before is! Map || after is! Map) return '';
    final parts = <String>[];
    for (final k in permissionLabels.keys) {
      final b = before[k], a = after[k];
      if (b != a) {
        parts.add(
          '${permissionLabels[k]}: ${a == true ? 'granted' : 'revoked'}',
        );
      }
    }
    return parts.join(' · ');
  }

  static List<TrainerEvent> timeline(Iterable<TrainerEvent> events) {
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

  static String joinedLine(TrainerModel t, {required DateTime now}) =>
      'Added ${OrganizationLanguage.exact(t.createdAt)} (${OrganizationLanguage.relative(t.createdAt, now: now)})';

  static String signInLine(TrainerModel t, {required DateTime now}) =>
      t.lastLogin == null
      ? 'Never signed in (or not recorded)'
      : 'Signed in ${OrganizationLanguage.relative(t.lastLogin, now: now)}';

  /// The permissions in words: granted keys, then revoked, then "not set".
  static String permissionsLine(Map<String, dynamic>? perms) {
    if (perms == null || perms.isEmpty) return 'Not recorded — defaults apply';
    final granted = <String>[], revoked = <String>[];
    for (final e in permissionLabels.entries) {
      final v = perms[e.key];
      if (v == true) {
        granted.add(e.value);
      } else if (v == false) {
        revoked.add(e.value);
      }
    }
    final parts = <String>[
      if (granted.isNotEmpty) 'Can use: ${granted.join(', ')}',
      if (revoked.isNotEmpty) 'Cannot use: ${revoked.join(', ')}',
    ];
    return parts.isEmpty ? 'Not recorded — defaults apply' : parts.join('. ');
  }
}
