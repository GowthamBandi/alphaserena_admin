// MEMBER LANGUAGE — the rules the Members screen states about a record, pinned
// against the producer contracts they were ported from (trainersHQ
// resolveClientIdentity + MembershipStatus, the backend's activation stage and
// account-deletion writers).
//
// Every assertion here is a fact the OLD screen got wrong or could not state:
// it showed "" for a name that lived in sharedProfile, called an expired term
// ACTIVE because the flag lagged, said "Unassigned" for an owner-coached
// member, and could not tell a deleted account from a never-claimed one.

import 'package:alphaserena_admin_portel/core/services/member_language.dart';
import 'package:alphaserena_admin_portel/core/services/organization_language.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/audit_log_model.dart';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:alphaserena_admin_portel/models/member_payment_model.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 24, 12);

ClientModel member(Map<String, dynamic> doc, [String id = 'm1']) =>
    ClientModel.fromMap({
      'adminId': 'org1',
      'authUid': 'uid-1',
      'createdAt': now.subtract(const Duration(days: 40)),
      ...doc,
    }, id);

AdminModel org({
  String id = 'org1',
  String status = 'active',
  bool subscriptionActive = true,
}) => AdminModel.fromMap({
  'name': 'Arjun',
  'organizationName': 'Iron Temple',
  'email': 'arjun@iron.in',
  'status': status,
  'isSubscriptionActive': subscriptionActive,
}, id);

TrainerModel trainer({
  String id = 't1',
  String status = 'active',
  String assignedBy = 'org1',
  bool deleted = false,
}) => TrainerModel.fromMap({
  'name': 'Priya',
  'email': 'priya@iron.in',
  'status': status,
  'assignedBy': assignedBy,
  if (deleted) 'isDeleted': true,
}, id);

List<MemberIssue> issues(
  ClientModel m, {
  AdminModel? org,
  bool orgKnown = true,
  TrainerModel? trainer,
  bool trainersKnown = true,
}) => MemberLanguage.issues(
  m,
  org: org,
  orgKnown: orgKnown,
  trainer: trainer,
  trainersKnown: trainersKnown,
  now: now,
);

Set<String> codes(List<MemberIssue> l) => l.map((i) => i.code).toSet();

void main() {
  group('identity resolves per field (trainersHQ resolveClientIdentity)', () {
    test('sharedProfile displayName outranks an empty coach name', () {
      final m = member({
        'name': '',
        'sharedProfile': {
          'identity': {'displayName': 'Sai Kumar'},
          'contact': {'phone': '+91 98000 11111'},
        },
      });
      expect(MemberLanguage.displayName(m), 'Sai Kumar');
      expect(MemberLanguage.phoneOf(m), '+91 98000 11111');
      expect(MemberLanguage.initial(m), 'S');
    });

    test('an empty record says so instead of rendering a blank', () {
      final m = member({'name': ' '});
      expect(MemberLanguage.displayName(m), 'Name not recorded');
      expect(MemberLanguage.initial(m), '?');
      expect(MemberLanguage.contactLine(m), 'No contact recorded');
    });

    test('legacy clientName is read when name is absent', () {
      expect(
        MemberLanguage.displayName(member({'clientName': 'Legacy'})),
        'Legacy',
      );
    });

    test('a date of birth outranks a frozen integer age', () {
      final m = member({
        'age': 50,
        'sharedProfile': {
          'identity': {'dob': '2000-10-01'},
        },
      });
      expect(MemberLanguage.ageOf(m, now: now), 25); // birthday not yet reached
      expect(MemberLanguage.ageOf(member({'age': 31}), now: now), 31);
    });

    test('the document id is the record id; uid defaults to it', () {
      final m = member({}, 'abc123');
      expect(m.docId, 'abc123');
      expect(m.uid, 'abc123');
      expect(m.authUid, 'uid-1');
    });
  });

  group('membership state is derived, never read from the flag', () {
    test('no expiry and no flag → none', () {
      expect(
        MemberLanguage.membershipState(
          member({'membershipActive': false}),
          now: now,
        ),
        MembershipState.none,
      );
    });

    test('expired term with a lagging active flag → expired', () {
      final m = member({
        'membershipActive': true,
        'membershipExpiry': now
            .subtract(const Duration(days: 3))
            .toUtc()
            .toIso8601String(),
      });
      expect(
        MemberLanguage.membershipState(m, now: now),
        MembershipState.expired,
      );
      expect(
        MemberLanguage.flagDisagreement(m, now: now),
        'flag_active_after_expiry',
      );
      expect(
        codes(issues(m, org: org())),
        contains('flag_active_after_expiry'),
      );
    });

    test('the hourly sweep gets two hours before the flag is called stale', () {
      final m = member({
        'membershipActive': true,
        'membershipExpiry': now
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
      });
      expect(
        MemberLanguage.membershipState(m, now: now),
        MembershipState.expired,
      );
      expect(MemberLanguage.flagDisagreement(m, now: now), isNull);
    });

    test('inactive flag during a running term is the opposite defect', () {
      final m = member({
        'membershipActive': false,
        'membershipExpiry': now.add(const Duration(days: 20)).toIso8601String(),
      });
      expect(
        MemberLanguage.membershipState(m, now: now),
        MembershipState.active,
      );
      expect(
        codes(issues(m, org: org())),
        contains('flag_inactive_during_term'),
      );
    });

    test('≤7 days left → expiring soon; frozen wins over everything', () {
      final soon = member({
        'membershipActive': true,
        'membershipExpiry': now.add(const Duration(days: 5)).toIso8601String(),
      });
      expect(
        MemberLanguage.membershipState(soon, now: now),
        MembershipState.expiringSoon,
      );
      final frozen = member({
        'membershipActive': true,
        'membershipFrozen': true,
        'membershipExpiry': now
            .subtract(const Duration(days: 5))
            .toIso8601String(),
      });
      expect(
        MemberLanguage.membershipState(frozen, now: now),
        MembershipState.frozen,
      );
      expect(MemberLanguage.flagDisagreement(frozen, now: now), isNull);
    });

    test(
      'a Timestamp-shaped expiry (older docs) parses like the string one',
      () {
        final m = member({
          'membershipActive': true,
          'membershipExpiry': now.add(const Duration(days: 30)),
        });
        expect(
          MemberLanguage.membershipState(m, now: now),
          MembershipState.active,
        );
      },
    );

    test('source line names how the term was sold', () {
      expect(
        MemberLanguage.sourceLine(
          member({
            'membership': {'razorpayPaymentId': 'pay_1', 'couponCode': 'X10'},
          }),
        ),
        'Paid online via Razorpay (coupon X10)',
      );
      expect(
        MemberLanguage.sourceLine(
          member({
            'membership': {'source': 'offline', 'method': 'cash'},
          }),
        ),
        'Recorded offline by the owner (cash)',
      );
      expect(
        MemberLanguage.sourceLine(
          member({
            'membership': {
              'source': 'coupon_full_discount',
              'couponCode': 'FREE',
            },
          }),
        ),
        'Free with coupon FREE',
      );
      expect(MemberLanguage.sourceLine(member({})), 'Origin not recorded');
    });
  });

  group('coach = trainerId || owner', () {
    test('a missing trainerId is the OWNER, not "unassigned"', () {
      final m = member({});
      expect(MemberLanguage.isOwnerCoached(m), isTrue);
      expect(MemberLanguage.coachId(m), 'org1');
      expect(
        MemberLanguage.coachLine(m, trainer: null, trainersKnown: true),
        'Coached by the organization owner',
      );
      expect(codes(issues(m, org: org())), isNot(contains('coach_missing')));
    });

    test(
      'an empty-string trainerId (removeTrainer writes "") is the owner too',
      () {
        expect(
          MemberLanguage.isOwnerCoached(member({'trainerId': ''})),
          isTrue,
        );
      },
    );

    test(
      'trainerId equal to the owner uid is the owner, not a missing coach',
      () {
        final m = member({'trainerId': 'org1'});
        expect(MemberLanguage.isOwnerCoached(m), isTrue);
        expect(
          codes(issues(m, org: org(), trainersKnown: true)),
          isNot(contains('coach_missing')),
        );
      },
    );

    test(
      'a removed or on-hold coach is flagged; a foreign coach is urgent',
      () {
        final m = member({'trainerId': 't1'});
        expect(
          codes(
            issues(
              m,
              org: org(),
              trainer: trainer(status: 'removed', deleted: true),
            ),
          ),
          contains('coach_not_working'),
        );
        final foreign = issues(
          m,
          org: org(),
          trainer: trainer(assignedBy: 'org2'),
        );
        final f = foreign.firstWhere((i) => i.code == 'coach_foreign');
        expect(f.severity, OrgIssueSeverity.critical);
      },
    );

    test('coach missing is claimed only once the trainer list is known', () {
      final m = member({'trainerId': 'ghost'});
      expect(
        codes(issues(m, org: org(), trainersKnown: false)),
        isNot(contains('coach_missing')),
      );
      expect(
        codes(issues(m, org: org(), trainersKnown: true)),
        contains('coach_missing'),
      );
    });
  });

  group('organization', () {
    test('orphaned only once the org list is known; no org is critical', () {
      final m = member({});
      expect(
        codes(issues(m, org: null, orgKnown: false)),
        isNot(contains('orphaned')),
      );
      expect(codes(issues(m, org: null, orgKnown: true)), contains('orphaned'));
      final none = issues(member({'adminId': ''}), org: null);
      expect(
        none.firstWhere((i) => i.code == 'no_organization').severity,
        OrgIssueSeverity.critical,
      );
    });

    test('a paying member of a blocked organization needs attention', () {
      final m = member({
        'membershipActive': true,
        'membershipExpiry': now.add(const Duration(days: 20)).toIso8601String(),
      });
      expect(
        codes(issues(m, org: org(status: 'blocked'))),
        contains('org_cannot_operate'),
      );
      // An expired member of a blocked org is not "paying" — no double alarm.
      final lapsed = member({'membershipActive': false});
      expect(
        codes(issues(lapsed, org: org(status: 'blocked'))),
        isNot(contains('org_cannot_operate')),
      );
    });
  });

  group('account link and activity', () {
    test('deleted-by-member vs never-claimed are different facts', () {
      expect(MemberLanguage.accountLink(member({})), AccountLink.linked);
      expect(
        MemberLanguage.accountLink(
          member({
            'authUid': null,
            'authUnlinkReason': 'member_account_deleted',
            'authUnlinkedAt': now,
          }),
        ),
        AccountLink.deletedByMember,
      );
      expect(
        MemberLanguage.accountLink(member({'authUid': ''})),
        AccountLink.neverClaimed,
      );
    });

    test('activity buckets', () {
      expect(
        MemberLanguage.activityState(member({}), now: now),
        ActivityState.none,
      );
      expect(
        MemberLanguage.activityState(
          member({'lastActivityAt': now.subtract(const Duration(days: 2))}),
          now: now,
        ),
        ActivityState.recent,
      );
      expect(
        MemberLanguage.activityState(
          member({'lastActivityAt': now.subtract(const Duration(days: 20))}),
          now: now,
        ),
        ActivityState.quiet,
      );
      expect(
        MemberLanguage.activityState(
          member({'lastActivityAt': now.subtract(const Duration(days: 45))}),
          now: now,
        ),
        ActivityState.dormant,
      );
    });

    test('dormant on a paid term is flagged; a coaching pause excuses it', () {
      final base = {
        'membershipActive': true,
        'membershipExpiry': now.add(const Duration(days: 20)).toIso8601String(),
        'lastActivityAt': now.subtract(const Duration(days: 45)),
      };
      expect(codes(issues(member(base), org: org())), contains('dormant'));
      final paused = member({
        ...base,
        'coachingPause': {
          'from': now.subtract(const Duration(days: 60)),
          'to': null,
          'type': 'medical',
        },
      });
      expect(codes(issues(paused, org: org())), isNot(contains('dormant')));
      expect(codes(issues(paused, org: org())), contains('coaching_paused'));
    });

    test('activation stalled: paid 14+ days ago and still not set up', () {
      final m = member({
        'membershipActive': true,
        'membershipExpiry': now.add(const Duration(days: 20)).toIso8601String(),
        'activationStage': 'preparingPlan',
      });
      expect(codes(issues(m, org: org())), contains('activation_stalled'));
      final fresh = member({
        ...m.raw,
        'createdAt': now.subtract(const Duration(days: 3)),
      });
      expect(
        codes(issues(fresh, org: org())),
        isNot(contains('activation_stalled')),
      );
      final ready = member({...m.raw, 'activationStage': 'ready'});
      expect(
        codes(issues(ready, org: org())),
        isNot(contains('activation_stalled')),
      );
    });

    test('unknown status is flagged; inactive is informational', () {
      expect(
        codes(issues(member({'status': 'zombie'}), org: org())),
        contains('unknown_status'),
      );
      final off = issues(member({'status': 'inactive'}), org: org());
      expect(
        off.firstWhere((i) => i.code == 'switched_off').needsAttention,
        isFalse,
      );
    });
  });

  group('payment-level issues', () {
    test('an unconfirmed online capture is an attention item', () {
      final ok = MemberPaymentModel.fromMap({
        'razorpayPaymentId': 'p',
        'captureVerified': true,
      }, 'a');
      final bad = MemberPaymentModel.fromMap({
        'razorpayPaymentId': 'p',
        'captureVerified': false,
      }, 'b');
      final offline = MemberPaymentModel.fromMap({
        'source': 'offline',
        'method': 'cash',
      }, 'c');
      expect(MemberLanguage.paymentIssues([ok, offline]), isEmpty);
      expect(
        MemberLanguage.paymentIssues([ok, bad]).single.code,
        'capture_unverified',
      );
      expect(offline.captureUnverified, isFalse);
    });
  });

  group('search, filters, sort', () {
    test(
      'search matches name, shared email, phone digits, plan, org, coach and ids',
      () {
        final m = member({
          'name': '',
          'sharedProfile': {
            'identity': {'displayName': 'Sai Kumar'},
            'contact': {'email': 'sai@x.in', 'phone': '+91 98000-11111'},
          },
          'membership': {'planName': 'Gold Quarterly'},
        }, 'doc-9');
        expect(MemberLanguage.matches(m, 'kumar'), isTrue);
        expect(MemberLanguage.matches(m, 'SAI@X'), isTrue);
        expect(MemberLanguage.matches(m, '9800011'), isTrue);
        expect(MemberLanguage.matches(m, 'gold'), isTrue);
        expect(
          MemberLanguage.matches(m, 'iron', orgName: 'Iron Temple'),
          isTrue,
        );
        expect(MemberLanguage.matches(m, 'priya', coachName: 'Priya'), isTrue);
        expect(MemberLanguage.matches(m, 'doc-9'), isTrue);
        expect(MemberLanguage.matches(m, 'uid-1'), isTrue);
        expect(MemberLanguage.matches(m, 'nobody'), isFalse);
      },
    );

    test('every filter key has a label and the tiles are a subset', () {
      for (final k in MemberLanguage.filterKeys) {
        expect(MemberLanguage.filterLabel(k), isNot(startsWith('Filter "')));
      }
      expect(MemberLanguage.filterKeys, containsAll(MemberLanguage.tileKeys));
    });

    test('a soft-deleted record matches no filter, not even "all"', () {
      final m = member({'isDeleted': true});
      for (final k in MemberLanguage.filterKeys) {
        expect(
          MemberLanguage.matchesFilter(
            m,
            k,
            org: org(),
            orgKnown: true,
            trainer: null,
            trainersKnown: true,
            now: now,
          ),
          isFalse,
          reason: k,
        );
      }
    });

    test(
      'oldest / name Z–A are the mirrors of newest / name A–Z; undated stay last',
      () {
        final a = member({
          'name': 'Anil',
          'createdAt': now.subtract(const Duration(days: 90)),
        }, 'a');
        final b = member({
          'name': 'Bala',
          'createdAt': now.subtract(const Duration(days: 10)),
        }, 'b');
        final u = member({'name': 'Undated', 'createdAt': null}, 'u');
        List<String> ids(String key) => MemberLanguage.sorted(
          [u, b, a],
          key,
          orgNameOf: (_) => '',
          issuesOf: (_) => const [],
        ).map((m) => m.docId).toList();
        expect(ids('newest'), ['b', 'a', 'u']);
        expect(ids('oldest'), ['a', 'b', 'u']);
        expect(ids('name'), ['a', 'b', 'u']);
        expect(ids('nameDesc'), ['u', 'b', 'a']);
        for (final k in MemberLanguage.sortKeys) {
          expect(MemberLanguage.sortLabel(k), isNot(k), reason: k);
        }
      },
    );

    test('training state comes from the backend stage, never from a guess', () {
      expect(
        MemberLanguage.trainingLine(member({'activationStage': 'ready'})),
        'Plan assigned',
      );
      expect(
        MemberLanguage.trainingLine(
          member({'activationStage': 'preparingPlan'}),
        ),
        'No plan yet',
      );
      expect(
        MemberLanguage.trainingLine(member({})),
        'Training state not computed',
      );
      expect(
        MemberLanguage.hasNoPlanYet(member({})),
        isFalse,
      ); // unknown claims nothing
      final paying = {
        'membershipActive': true,
        'membershipExpiry': now.add(const Duration(days: 20)).toIso8601String(),
      };
      bool noPlan(Map<String, dynamic> d) => MemberLanguage.matchesFilter(
        member(d),
        'noPlan',
        org: org(),
        orgKnown: true,
        trainer: null,
        trainersKnown: true,
        now: now,
      );
      expect(noPlan({...paying, 'activationStage': 'onboarding'}), isTrue);
      expect(noPlan({...paying, 'activationStage': 'ready'}), isFalse);
      expect(noPlan({'activationStage': 'onboarding'}), isFalse); // not paying
    });

    test('sort by expiry puts undated last; attention puts critical first', () {
      final a = member({
        'membershipExpiry': now.add(const Duration(days: 30)).toIso8601String(),
      }, 'a');
      final b = member({
        'membershipExpiry': now.add(const Duration(days: 2)).toIso8601String(),
      }, 'b');
      final c = member({}, 'c');
      final byExpiry = MemberLanguage.sorted(
        [a, b, c],
        'expiry',
        orgNameOf: (_) => '',
        issuesOf: (_) => const [],
      );
      expect(byExpiry.map((m) => m.docId), ['b', 'a', 'c']);

      final critical = member({'adminId': ''}, 'crit');
      final fine = member({}, 'fine');
      final byAttention = MemberLanguage.sorted(
        [fine, critical],
        'attention',
        orgNameOf: (_) => '',
        issuesOf: (m) => issues(m, org: m.docId == 'fine' ? org() : null),
      );
      expect(byAttention.first.docId, 'crit');
    });
  });

  group('history', () {
    test(
      'audit rows become plain-language events; privileged reads are hidden',
      () {
        final e = MemberLanguage.fromAudit(
          const AuditLogModel(
            id: '1',
            action: 'offline_membership_recorded',
            actorUid: 'org1',
            details: {'planName': 'Gold'},
          ),
          actorOf: (u) => 'the owner',
        );
        expect(e!.title, 'Offline payment recorded by the owner');
        expect(e.detail, 'Gold');
        expect(
          MemberLanguage.fromAudit(
            const AuditLogModel(id: '2', action: 'privileged_read_x'),
            actorOf: (u) => u,
          ),
          isNull,
        );
      },
    );

    test(
      'set_client_coach reads the backend keys {from, to} and names the coach',
      () {
        final e = MemberLanguage.fromAudit(
          const AuditLogModel(
            id: '3',
            action: 'set_client_coach',
            actorUid: 'org1',
            details: {'from': '', 'to': 't1', 'source': 'manual'},
          ),
          actorOf: (u) => 'the owner',
          coachNameOf: (u) => u == 't1' ? 'Priya' : u,
        );
        expect(e!.title, 'Coach assigned to Priya');
        expect(e.detail, 'manual');
        final back = MemberLanguage.fromAudit(
          const AuditLogModel(
            id: '4',
            action: 'set_client_coach',
            actorUid: 'org1',
            details: {'from': 't1', 'to': ''},
          ),
          actorOf: (u) => 'the owner',
          coachNameOf: (u) => 'Priya',
        );
        expect(back!.title, 'Coach unassigned — back to the owner');
        expect(back.detail, 'from Priya');
      },
    );

    test('a receipt becomes an event that names the amount and the origin', () {
      final p = MemberPaymentModel.fromMap({
        'amount': 1999,
        'planName': 'Gold',
        'razorpayPaymentId': 'pay_1',
        'captureVerified': false,
        'createdAt': now,
      }, 'r1');
      final e = MemberLanguage.fromPayment(p);
      expect(e.title, 'Payment received');
      expect(e.detail, contains(OrganizationLanguage.rupees(1999)));
      expect(e.detail, contains('NOT confirmed'));
    });

    test('timeline is newest first with undated rows last', () {
      final t = MemberLanguage.timeline([
        MemberEvent(at: null, title: 'undated'),
        MemberEvent(at: now.subtract(const Duration(days: 2)), title: 'old'),
        MemberEvent(at: now, title: 'new'),
      ]);
      expect(t.map((e) => e.title), ['new', 'old', 'undated']);
    });
  });
}
