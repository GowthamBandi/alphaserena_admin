// The rules the Organizations section relies on, asserted without a widget.
// Every count, pill, sort and confirmation sentence on the screen comes from
// these predicates; if one of them is wrong the screen is wrong everywhere.

import 'package:alphaserena_admin_portel/core/services/organization_language.dart';
import 'package:alphaserena_admin_portel/models/access_request_model.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/audit_log_model.dart';
import 'package:alphaserena_admin_portel/models/clints_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_model.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 6, 12);

AdminModel org({
  String id = 'org-1',
  String orgName = 'Iron Temple',
  String owner = 'Arjun Rao',
  String email = 'arjun@iron.in',
  String phone = '+91 98000 11111',
  String status = 'active',
  bool subActive = true,
  DateTime? expiry,
  String? planName = 'Growth',
  Map<String, dynamic>? subscription,
  DateTime? created,
  bool createdKnown = true,
  List<String> trainerIds = const [],
  String? statusReason,
  Map<String, dynamic>? metadata,
  int maxTrainers = 5,
}) => AdminModel(
  docId: id,
  uid: id,
  name: owner,
  email: email,
  phone: phone,
  organizationName: orgName,
  role: 'admin',
  status: status,
  isSubscriptionActive: subActive,
  planExpiry: expiry,
  planName: planName,
  subscription: subscription,
  subscriptionLimits: AdminSubscriptionLimits(
    maxAdmins: 1,
    maxTrainers: maxTrainers,
    maxClients: 100,
    maxWorkoutPlans: 10,
    maxDietPlans: 10,
  ),
  createdAt: created ?? now.subtract(const Duration(days: 100)),
  createdAtKnown: createdKnown,
  updatedAt: now,
  trainerIds: trainerIds,
  statusReason: statusReason,
  metadata: metadata,
);

TrainerModel trainer(
  String id, {
  bool? orgActive,
  String status = 'active',
  bool deleted = false,
}) => TrainerModel(
  docId: id,
  uid: id,
  name: 'T $id',
  email: '$id@t.in',
  phone: '',
  status: status,
  isDeleted: deleted,
  assignedBy: 'org-1',
  orgActive: orgActive,
  createdAt: now,
  updatedAt: now,
);

ClientModel member(String id, {String? trainerId}) => ClientModel(
  docId: id,
  uid: id,
  name: 'M $id',
  email: '',
  phone: '',
  adminId: 'org-1',
  trainerId: trainerId,
  createdAt: now,
  updatedAt: now,
);

SubscriptionModel receipt({
  String id = 'r1',
  String pay = '',
  int amount = 4999,
  bool captureVerified = true,
  double refund = 0,
}) => SubscriptionModel(
  id: id,
  adminUid: 'org-1',
  adminDocId: 'org-1',
  planName: 'Growth',
  durationMonths: 1,
  amountPaid: amount,
  originalAmount: amount,
  couponApplied: false,
  discountAmount: 0,
  paymentId: pay.isEmpty ? id : pay,
  razorpayPaymentId: pay,
  startAt: now,
  expiryAt: now,
  createdAt: now,
  captureVerified: captureVerified,
  refundAmount: refund,
  maxAdmins: 1,
  maxTrainers: 5,
  maxClients: 100,
  maxWorkoutPlans: 10,
  maxWorkouts: 10,
  maxDietPlans: 10,
);

List<String> codes(List<OrgIssue> l) => l.map((i) => i.code).toList();

void main() {
  _labelForUidTests();
  group('standing and operating', () {
    test('raw statuses map to standings; approved normalises to active', () {
      expect(
        OrganizationLanguage.standingOf(org(status: 'pending')),
        OrgStanding.awaitingApproval,
      );
      expect(
        OrganizationLanguage.standingOf(org(status: 'active')),
        OrgStanding.approved,
      );
      expect(
        OrganizationLanguage.standingOf(org(status: 'approved')),
        OrgStanding.approved,
      );
      expect(
        OrganizationLanguage.standingOf(org(status: 'warning')),
        OrgStanding.warning,
      );
      expect(
        OrganizationLanguage.standingOf(org(status: 'blocked')),
        OrgStanding.blocked,
      );
      expect(
        OrganizationLanguage.standingOf(org(status: 'on_hold')),
        OrgStanding.unknown,
      );
    });

    test(
      'canOperate is the rules formula: not pending, not blocked, flag on',
      () {
        expect(OrganizationLanguage.canOperate(org()), isTrue);
        expect(OrganizationLanguage.canOperate(org(status: 'warning')), isTrue);
        expect(
          OrganizationLanguage.canOperate(org(status: 'pending')),
          isFalse,
        );
        expect(
          OrganizationLanguage.canOperate(org(status: 'blocked')),
          isFalse,
        );
        expect(OrganizationLanguage.canOperate(org(subActive: false)), isFalse);
        expect(OrganizationLanguage.canOperate(org(status: 'weird')), isFalse);
      },
    );

    test(
      'the flag, not the date, decides operating — a past date is an ISSUE',
      () {
        final past = org(expiry: now.subtract(const Duration(days: 3)));
        expect(OrganizationLanguage.canOperate(past), isTrue);
        expect(
          codes(OrganizationLanguage.recordIssues(past, now: now)),
          contains('active_past_end'),
        );
      },
    );
  });

  group('subscription view', () {
    test('five states, dated honestly', () {
      SubscriptionState s(AdminModel a) =>
          OrganizationLanguage.subscriptionOf(a, now: now).state;
      expect(s(org(subActive: false)), SubscriptionState.none);
      expect(s(org(expiry: null)), SubscriptionState.activeNoEndDate);
      expect(
        s(org(expiry: now.subtract(const Duration(days: 1)))),
        SubscriptionState.activePastEnd,
      );
      expect(
        s(org(expiry: now.add(const Duration(days: 3)))),
        SubscriptionState.expiringSoon,
      );
      expect(
        s(org(expiry: now.add(const Duration(days: 7)))),
        SubscriptionState.expiringSoon,
      );
      expect(
        s(org(expiry: now.add(const Duration(days: 8)))),
        SubscriptionState.active,
      );
    });

    test('expiring is measured in CALENDAR days', () {
      // 23:59 tonight is "today" (0 days), not -1 because of hours.
      final tonight = DateTime(now.year, now.month, now.day, 23, 59);
      final v = OrganizationLanguage.subscriptionOf(
        org(expiry: tonight),
        now: now,
      );
      expect(v.daysLeft, 0);
      expect(v.label, 'Ends in 0 days');
    });

    test(
      'source is online when a gateway id exists, manual on reference/method, else none',
      () {
        expect(
          OrganizationLanguage.subscriptionOf(
            org(subscription: {'razorpayPaymentId': 'pay_1'}),
            now: now,
          ).source,
          SubscriptionSource.online,
        );
        expect(
          OrganizationLanguage.subscriptionOf(
            org(subscription: {'method': 'manual', 'reference': 'UTR1'}),
            now: now,
          ).source,
          SubscriptionSource.manual,
        );
        expect(
          OrganizationLanguage.subscriptionOf(org(), now: now).source,
          SubscriptionSource.none,
        );
      },
    );

    test('a missing plan name is said, never blank', () {
      expect(
        OrganizationLanguage.subscriptionOf(
          org(planName: null),
          now: now,
        ).planName,
        'No plan recorded',
      );
    });
  });

  group('record issues', () {
    test('a healthy approved organization has no issues', () {
      expect(
        OrganizationLanguage.recordIssues(
          org(expiry: now.add(const Duration(days: 60))),
          now: now,
        ),
        isEmpty,
      );
    });

    test('each code fires on its own signal', () {
      expect(
        codes(
          OrganizationLanguage.recordIssues(org(status: 'pending'), now: now),
        ),
        contains('awaiting_approval'),
      );
      expect(
        codes(OrganizationLanguage.recordIssues(org(status: 'zzz'), now: now)),
        contains('unknown_status'),
      );
      expect(
        codes(OrganizationLanguage.recordIssues(org(expiry: null), now: now)),
        contains('active_no_end_date'),
      );
      expect(
        codes(
          OrganizationLanguage.recordIssues(
            org(expiry: now.add(const Duration(days: 2))),
            now: now,
          ),
        ),
        contains('expiring_soon'),
      );
      expect(
        codes(
          OrganizationLanguage.recordIssues(org(subActive: false), now: now),
        ),
        contains('approved_no_subscription'),
      );
      expect(
        codes(
          OrganizationLanguage.recordIssues(org(status: 'blocked'), now: now),
        ),
        contains('blocked'),
      );
      expect(
        codes(
          OrganizationLanguage.recordIssues(
            org(status: 'warning', expiry: now.add(const Duration(days: 60))),
            now: now,
          ),
        ),
        contains('warning_on_file'),
      );
      expect(
        codes(
          OrganizationLanguage.recordIssues(
            org(email: '', expiry: now.add(const Duration(days: 60))),
            now: now,
          ),
        ),
        contains('no_owner_email'),
      );
      expect(
        codes(
          OrganizationLanguage.recordIssues(
            org(orgName: '', expiry: now.add(const Duration(days: 60))),
            now: now,
          ),
        ),
        contains('no_org_name'),
      );
      expect(
        codes(
          OrganizationLanguage.recordIssues(
            org(createdKnown: false, expiry: now.add(const Duration(days: 60))),
            now: now,
          ),
        ),
        contains('no_created_at'),
      );
    });

    test('needsAttention ignores informational issues', () {
      // blocked is info-only (the founder chose it); no-org-name is info.
      expect(
        OrganizationLanguage.needsAttention(
          org(status: 'blocked', subActive: false),
          now: now,
        ),
        isFalse,
      );
      expect(
        OrganizationLanguage.needsAttention(
          org(orgName: '', expiry: now.add(const Duration(days: 60))),
          now: now,
        ),
        isFalse,
      );
      expect(
        OrganizationLanguage.needsAttention(org(status: 'pending'), now: now),
        isTrue,
      );
      expect(
        OrganizationLanguage.needsAttention(
          org(expiry: now.subtract(const Duration(days: 1))),
          now: now,
        ),
        isTrue,
      );
    });

    test(
      'a blocked organization is never "no subscription" — block explains it',
      () {
        expect(
          codes(
            OrganizationLanguage.recordIssues(
              org(status: 'blocked', subActive: false),
              now: now,
            ),
          ),
          isNot(contains('approved_no_subscription')),
        );
      },
    );

    test('the reason on file is quoted in the blocked / warning issue', () {
      final i = OrganizationLanguage.recordIssues(
        org(status: 'blocked', statusReason: 'chargebacks'),
        now: now,
      ).firstWhere((i) => i.code == 'blocked');
      expect(i.why, contains('chargebacks'));
      expect(i.offers, OrgAction.reactivate);
    });
  });

  group('relationship issues', () {
    final base = org(
      expiry: now.add(const Duration(days: 60)),
      trainerIds: ['t1', 't2'],
    );

    test(
      'a consistent organization reports nothing but "no storefront" info',
      () {
        final issues = OrganizationLanguage.relationshipIssues(
          admin: base,
          trainers: [
            trainer('t1', orgActive: true),
            trainer('t2', orgActive: true),
          ],
          members: [member('m1', trainerId: 't1')],
          receipts: [receipt()],
          requests: [],
          storefront: {'orgActive': true},
          now: now,
        );
        expect(issues, isEmpty);
      },
    );

    test('seat list vs live trainers; removed trainers do not count', () {
      final issues = OrganizationLanguage.relationshipIssues(
        admin: base,
        trainers: [
          trainer('t1', orgActive: true),
          trainer('t3', orgActive: true, deleted: true, status: 'removed'),
        ],
        members: const [],
        receipts: [receipt()],
        requests: const [],
        storefront: {'orgActive': true},
        now: now,
      );
      expect(codes(issues), contains('trainer_roster_mismatch'));
      expect(issues.first.why, contains('2 seats'));
      expect(issues.first.why, contains('1 trainer account'));
    });

    test(
      'a trainer whose access flag disagrees with the organization is CRITICAL',
      () {
        final issues = OrganizationLanguage.relationshipIssues(
          admin: base,
          trainers: [
            trainer('t1', orgActive: false),
            trainer('t2', orgActive: true),
          ],
          members: const [],
          receipts: [receipt()],
          requests: const [],
          storefront: {'orgActive': true},
          now: now,
        );
        final i = issues.firstWhere((i) => i.code == 'trainer_access_stale');
        expect(i.severity, OrgIssueSeverity.critical);
        expect(i.title, startsWith('1 trainer has'));
      },
    );

    test('an unstamped trainer (orgActive null) is not "stale"', () {
      final issues = OrganizationLanguage.relationshipIssues(
        admin: base,
        trainers: [trainer('t1'), trainer('t2')],
        members: const [],
        receipts: [receipt()],
        requests: const [],
        storefront: {'orgActive': true},
        now: now,
      );
      expect(codes(issues), isNot(contains('trainer_access_stale')));
    });

    test(
      'a member coached by someone outside the org; the owner as coach is fine',
      () {
        final issues = OrganizationLanguage.relationshipIssues(
          admin: base,
          trainers: [
            trainer('t1', orgActive: true),
            trainer('t2', orgActive: true),
          ],
          members: [
            member('m1', trainerId: 'stranger'),
            member('m2', trainerId: 'org-1'),
            member('m3'),
          ],
          receipts: [receipt()],
          requests: const [],
          storefront: {'orgActive': true},
          now: now,
        );
        final i = issues.firstWhere(
          (i) => i.code == 'member_coach_outside_org',
        );
        expect(i.title, startsWith('1 member assigned'));
      },
    );

    test('storefront listed while the organization cannot operate', () {
      final blocked = org(status: 'blocked', trainerIds: const []);
      final issues = OrganizationLanguage.relationshipIssues(
        admin: blocked,
        trainers: const [],
        members: const [],
        receipts: [receipt()],
        requests: const [],
        storefront: {'orgActive': true},
        now: now,
      );
      expect(
        issues.firstWhere((i) => i.code == 'storefront_stale').title,
        contains('still listed'),
      );
    });

    test(
      'no receipt for an active subscription is informational; duplicate requests are not',
      () {
        final issues = OrganizationLanguage.relationshipIssues(
          admin: base,
          trainers: [
            trainer('t1', orgActive: true),
            trainer('t2', orgActive: true),
          ],
          members: const [],
          receipts: const [],
          requests: [
            AccessRequestModel(
              id: 'a',
              organizationName: 'x',
              ownerName: '',
              email: '',
              phone: '',
              message: '',
              status: 'organization_created',
            ),
            AccessRequestModel(
              id: 'b',
              organizationName: 'x',
              ownerName: '',
              email: '',
              phone: '',
              message: '',
              status: 'organization_created',
            ),
          ],
          storefront: null,
          now: now,
        );
        expect(
          issues
              .firstWhere((i) => i.code == 'no_receipt_for_subscription')
              .severity,
          OrgIssueSeverity.info,
        );
        expect(
          issues
              .firstWhere((i) => i.code == 'multiple_access_requests')
              .severity,
          OrgIssueSeverity.attention,
        );
        expect(codes(issues), contains('no_storefront'));
      },
    );

    test('two end dates that disagree by more than a day', () {
      final a = org(
        expiry: now.add(const Duration(days: 60)),
        subscription: {
          'expiry': now.add(const Duration(days: 30)).toIso8601String(),
        },
        trainerIds: const [],
      );
      final issues = OrganizationLanguage.relationshipIssues(
        admin: a,
        trainers: const [],
        members: const [],
        receipts: [receipt()],
        requests: const [],
        storefront: {'orgActive': true},
        now: now,
      );
      expect(codes(issues), contains('end_dates_disagree'));
    });
  });

  group('server-maintained signals', () {
    test(
      'an open quota alert names the violated limits and offers a plan change',
      () {
        final issues = OrganizationLanguage.quotaIssues({
          'status': 'open',
          'violations': [
            {'resource': 'trainers', 'used': 7, 'limit': 5},
          ],
        });
        expect(issues.single.code, 'over_plan_limits');
        expect(issues.single.why, contains('trainers 7 of 5'));
        expect(issues.single.offers, OrgAction.grant);
      },
    );

    test('no alert, or a non-open one, is silence', () {
      expect(OrganizationLanguage.quotaIssues(null), isEmpty);
      expect(OrganizationLanguage.quotaIssues({'status': 'resolved'}), isEmpty);
    });

    test('open incidents are critical; resolved ones are not counted', () {
      final issues = OrganizationLanguage.incidentIssues([
        {'type': 'org_cascade_failed', 'status': 'open'},
        {'type': 'org_auth_enforcement_failed', 'status': 'resolved'},
      ]);
      expect(issues.single.severity, OrgIssueSeverity.critical);
      expect(issues.single.title, startsWith('1 backend operation'));
      expect(issues.single.why, contains('org_cascade_failed'));
      expect(
        OrganizationLanguage.incidentIssues([
          {'type': 'x', 'status': 'resolved'},
        ]),
        isEmpty,
      );
    });

    test('seat lines say no-limit, unlimited and over-limit in words', () {
      expect(
        OrganizationLanguage.seatLine(3, 0, 'trainers'),
        '3 trainers · no limit set',
      );
      expect(
        OrganizationLanguage.seatLine(3, 1000000000, 'trainers'),
        '3 trainers · unlimited',
      );
      expect(
        OrganizationLanguage.seatLine(7, 5, 'trainers'),
        '7 of 5 trainers · OVER LIMIT',
      );
      expect(
        OrganizationLanguage.seatLine(2, 5, 'trainers'),
        '2 of 5 trainers',
      );
    });
  });

  group('search', () {
    final a = org(
      orgName: 'Iron  Temple Fitness',
      owner: 'Arjun Rao',
      email: 'Arjun@Iron.in',
      phone: '+91 98000 11111',
    );

    test(
      'partial, case-insensitive, whitespace-normalised across the human fields',
      () {
        expect(OrganizationLanguage.matches(a, 'iron temple'), isTrue);
        expect(OrganizationLanguage.matches(a, '  IRON   temple '), isTrue);
        expect(OrganizationLanguage.matches(a, 'rao'), isTrue);
        expect(OrganizationLanguage.matches(a, 'ARJUN@iron'), isTrue);
        expect(OrganizationLanguage.matches(a, '9800011111'), isTrue);
        expect(OrganizationLanguage.matches(a, 'zebra'), isFalse);
      },
    );

    test('an exact id matches even though ids are not in the text fields', () {
      expect(OrganizationLanguage.matches(a, 'org-1'), isTrue);
      expect(OrganizationLanguage.matches(a, 'org-'), isFalse);
    });

    test('special characters are literal, never a pattern', () {
      expect(OrganizationLanguage.matches(a, '.*'), isFalse);
      expect(OrganizationLanguage.matches(a, '('), isFalse);
      expect(OrganizationLanguage.matches(a, ''), isTrue);
    });
  });

  group('filters', () {
    final rows = [
      org(id: 'ok', expiry: now.add(const Duration(days: 60))),
      org(id: 'pend', status: 'pending', subActive: false),
      org(id: 'nosub', subActive: false),
      org(id: 'exp', expiry: now.add(const Duration(days: 2))),
      org(id: 'blk', status: 'blocked', subActive: false),
      org(
        id: 'warn',
        status: 'warning',
        expiry: now.add(const Duration(days: 60)),
      ),
      org(
        id: 'new',
        expiry: now.add(const Duration(days: 60)),
        created: now.subtract(const Duration(days: 3)),
      ),
      org(id: 'past', expiry: now.subtract(const Duration(days: 2))),
    ];
    List<String> ids(String key) => rows
        .where((a) => OrganizationLanguage.matchesFilter(a, key, now: now))
        .map((a) => a.docId)
        .toList();

    test('every key selects exactly the documented rows', () {
      expect(ids('all').length, rows.length);
      expect(ids('attention'), ['pend', 'nosub', 'exp', 'past']);
      expect(ids('operating'), ['ok', 'exp', 'warn', 'new', 'past']);
      expect(ids('pending'), ['pend']);
      expect(ids('noSubscription'), ['nosub']);
      expect(ids('expiring'), ['exp']);
      expect(ids('active'), ['ok', 'nosub', 'exp', 'new', 'past']);
      expect(ids('warning'), ['warn']);
      expect(ids('blocked'), ['blk']);
      expect(ids('recent'), ['new']);
    });

    test(
      'an unknown key falls back to the raw status, so a Dashboard drill-down still narrows',
      () {
        expect(ids('BLOCKED'), ['blk']);
        expect(ids('nothing'), isEmpty);
      },
    );

    test('plan filter is exact', () {
      expect(
        OrganizationLanguage.matchesPlan(org(planName: 'Growth'), 'Growth'),
        isTrue,
      );
      expect(
        OrganizationLanguage.matchesPlan(org(planName: 'Growth'), 'Grow'),
        isFalse,
      );
      expect(
        OrganizationLanguage.matchesPlan(org(planName: null), 'all'),
        isTrue,
      );
    });
  });

  group('sorting', () {
    final a = org(
      id: 'a',
      orgName: 'Beta',
      created: now.subtract(const Duration(days: 10)),
      expiry: now.add(const Duration(days: 30)),
    );
    final b = org(
      id: 'b',
      orgName: 'alpha',
      created: now.subtract(const Duration(days: 5)),
      expiry: now.add(const Duration(days: 2)),
    );
    final c = org(
      id: 'c',
      orgName: 'Gamma',
      createdKnown: false,
      status: 'pending',
      subActive: false,
    );
    final d = org(
      id: 'd',
      orgName: 'Delta',
      created: now.subtract(const Duration(days: 1)),
      expiry: now.subtract(const Duration(days: 1)),
    );
    List<String> ids(String key) => OrganizationLanguage.sorted(
      [a, b, c, d],
      key,
      now: now,
    ).map((o) => o.docId).toList();

    test('newest / oldest keep undated rows visible at the top', () {
      expect(ids('newest'), ['c', 'd', 'b', 'a']);
      expect(ids('oldest'), ['c', 'a', 'b', 'd']);
    });

    test(
      'name is case-insensitive',
      () => expect(ids('name'), ['b', 'a', 'd', 'c']),
    );

    test('expiry soonest first; no active end date last', () {
      expect(ids('expiry'), ['d', 'b', 'a', 'c']);
    });

    test('attention: critical, then attention, then clean; ties by newest', () {
      // d: active_past_end (critical); c: awaiting (attention); b: expiring (attention); a: clean
      expect(ids('attention'), ['d', 'c', 'b', 'a']);
    });
  });

  group('actions', () {
    test('what each standing offers, and blocked offers only Reactivate', () {
      expect(OrganizationLanguage.actionsFor(org(status: 'pending')), [
        OrgAction.approve,
        OrgAction.grant,
        OrgAction.block,
      ]);
      expect(OrganizationLanguage.actionsFor(org()), [
        OrgAction.grant,
        OrgAction.warn,
        OrgAction.block,
      ]);
      expect(OrganizationLanguage.actionsFor(org(status: 'warning')), [
        OrgAction.grant,
        OrgAction.reactivate,
        OrgAction.block,
      ]);
      expect(OrganizationLanguage.actionsFor(org(status: 'blocked')), [
        OrgAction.reactivate,
      ]);
      expect(OrganizationLanguage.actionsFor(org(status: 'odd')), [
        OrgAction.reactivate,
        OrgAction.block,
      ]);
    });

    test('the primary verb is the one thing most worth doing', () {
      expect(
        OrganizationLanguage.primaryAction(org(status: 'pending'), now: now),
        OrgAction.approve,
      );
      expect(
        OrganizationLanguage.primaryAction(org(subActive: false), now: now),
        OrgAction.grant,
      );
      expect(
        OrganizationLanguage.primaryAction(
          org(expiry: now.add(const Duration(days: 1))),
          now: now,
        ),
        OrgAction.grant,
      );
      expect(
        OrganizationLanguage.primaryAction(
          org(expiry: now.add(const Duration(days: 90))),
          now: now,
        ),
        isNull,
      );
      expect(
        OrganizationLanguage.primaryAction(org(status: 'blocked'), now: now),
        isNull,
      );
    });

    test('labels are contextual', () {
      expect(
        OrganizationLanguage.actionLabelFor(
          OrgAction.reactivate,
          org(status: 'warning'),
        ),
        'Clear warning',
      );
      expect(
        OrganizationLanguage.actionLabelFor(
          OrgAction.reactivate,
          org(status: 'odd'),
        ),
        'Set to Approved',
      );
      expect(
        OrganizationLanguage.actionLabelFor(OrgAction.grant, org()),
        'Record renewal / change plan',
      );
      expect(
        OrganizationLanguage.actionLabelFor(
          OrgAction.grant,
          org(subActive: false),
        ),
        'Record payment',
      );
    });

    test(
      'Block is the only destructive plan: reason AND typed name; grant is irreversible',
      () {
        final block = OrganizationLanguage.planFor(
          OrgAction.block,
          org(),
          now: now,
        );
        expect(block.requiresReason, isTrue);
        expect(block.requiresTypedName, isTrue);
        expect(block.consequences.join(' '), contains('Nothing is deleted'));
        expect(block.reversibility, contains('Reversible'));
        final warn = OrganizationLanguage.planFor(
          OrgAction.warn,
          org(),
          now: now,
        );
        expect(warn.requiresReason, isTrue);
        expect(warn.requiresTypedName, isFalse);
        final approve = OrganizationLanguage.planFor(
          OrgAction.approve,
          org(status: 'pending', subActive: false),
          now: now,
        );
        expect(approve.requiresReason, isFalse);
        expect(approve.consequences.first, contains('still cannot operate'));
        final grant = OrganizationLanguage.planFor(
          OrgAction.grant,
          org(status: 'pending', subActive: false),
          now: now,
        );
        expect(grant.reversibility, contains('Cannot be undone'));
        expect(
          grant.consequences.join(' '),
          contains('stays awaiting approval'),
        );
      },
    );

    test('the WHO line names organization and owner', () {
      final p = OrganizationLanguage.planFor(
        OrgAction.approve,
        org(status: 'pending'),
        now: now,
      );
      expect(p.who, 'Iron Temple — owner Arjun Rao (arjun@iron.in)');
    });
  });

  group('receipts', () {
    test('states in precedence order', () {
      expect(
        OrganizationLanguage.receiptState(receipt(pay: 'pay_1', refund: 4999)),
        ReceiptState.refunded,
      );
      expect(
        OrganizationLanguage.receiptState(receipt(pay: 'pay_1', refund: 100)),
        ReceiptState.partiallyRefunded,
      );
      expect(
        OrganizationLanguage.receiptState(receipt()),
        ReceiptState.recordedManually,
      );
      expect(
        OrganizationLanguage.receiptState(
          receipt(pay: 'pay_1', captureVerified: false),
        ),
        ReceiptState.unverified,
      );
      expect(
        OrganizationLanguage.receiptState(receipt(pay: 'pay_1')),
        ReceiptState.paid,
      );
    });

    test('only an online receipt with money left can be refunded', () {
      expect(OrganizationLanguage.canRefund(receipt()), isFalse);
      expect(OrganizationLanguage.canRefund(receipt(pay: 'pay_1')), isTrue);
      expect(
        OrganizationLanguage.canRefund(receipt(pay: 'pay_1', refund: 4999)),
        isFalse,
      );
      expect(
        OrganizationLanguage.canRefund(receipt(pay: 'pay_1', amount: 0)),
        isFalse,
      );
    });
  });

  group('history', () {
    test(
      'actors resolve to you / the owner / the system / a colleague / a short uid',
      () {
        String who(String uid) => OrganizationLanguage.actor(
          uid,
          currentUid: 'me',
          staffName: (u) => u == 'col' ? 'colleague@x.in' : null,
          ownerUid: 'org-1',
        );
        expect(who('me'), 'you');
        expect(who('org-1'), 'the owner');
        expect(who('system'), 'the system');
        expect(who('col'), 'colleague@x.in');
        expect(who('abcdefghijkl'), 'a platform admin (abcdefgh…)');
        expect(who(''), '');
      },
    );

    test('audit rows become sentences; privileged reads are dropped', () {
      OrgEvent? ev(String action, Map<String, dynamic> d) =>
          OrganizationLanguage.fromAudit(
            AuditLogModel(
              id: 'x',
              actorUid: 'me',
              action: action,
              targetId: 'org-1',
              details: d,
              createdAt: now,
            ),
            actorOf: (_) => 'you',
          );
      expect(
        ev('set_admin_status', {'status': 'blocked'})!.title,
        'Status changed to Blocked',
      );
      expect(
        ev('grant_subscription', {
          'months': 3,
          'amount': 12000,
          'reference': 'UTR9',
        })!.detail,
        '3 months · ₹12,000 · ref UTR9',
      );
      expect(ev('subscription_expired', {})!.actor, 'the system');
      expect(ev('provision_organization', {})!.kind, OrgEventKind.origin);
      expect(ev('privileged_read:getX', {}), isNull);
      expect(ev('something_new', {})!.title, 'Something new');
    });

    test(
      'an access request yields the intake event plus each stage after "requested"',
      () {
        final r = AccessRequestModel(
          id: 'ar1',
          organizationName: 'Iron Temple',
          ownerName: 'Arjun',
          email: '',
          phone: '',
          message: '',
          status: 'organization_created',
          createdAt: now.subtract(const Duration(days: 9)),
          statusHistory: [
            AccessRequestEvent(
              status: 'requested',
              at: now.subtract(const Duration(days: 9)),
              by: 'prospect',
            ),
            AccessRequestEvent(
              status: 'payment_confirmed',
              at: now.subtract(const Duration(days: 4)),
              by: 'me',
            ),
            AccessRequestEvent(
              status: 'organization_created',
              at: now.subtract(const Duration(days: 3)),
              by: 'me',
            ),
          ],
        );
        final events = OrganizationLanguage.fromAccessRequest(
          r,
          actorOf: (_) => 'you',
        );
        expect(events.map((e) => e.title), [
          'Access request received',
          'Payment recorded on the request',
          'Organization created from the request',
        ]);
        expect(events.first.actor, 'the requester');
        expect(events.last.actor, 'you');
      },
    );

    test('timeline is newest first with undated events last', () {
      final t = OrganizationLanguage.timeline([
        OrgEvent(at: null, kind: OrgEventKind.record, title: 'undated'),
        OrgEvent(
          at: now.subtract(const Duration(days: 2)),
          kind: OrgEventKind.admin,
          title: 'older',
        ),
        OrgEvent(at: now, kind: OrgEventKind.admin, title: 'newest'),
      ]);
      expect(t.map((e) => e.title), ['newest', 'older', 'undated']);
    });
  });

  group('words', () {
    test('rupees use Indian grouping', () {
      expect(OrganizationLanguage.rupees(0), '₹0');
      expect(OrganizationLanguage.rupees(999), '₹999');
      expect(OrganizationLanguage.rupees(4999), '₹4,999');
      expect(OrganizationLanguage.rupees(125000), '₹1,25,000');
      expect(OrganizationLanguage.rupees(12345678), '₹1,23,45,678');
    });

    test('relative and exact dates; never invented', () {
      expect(OrganizationLanguage.relative(now, now: now), 'today');
      expect(
        OrganizationLanguage.relative(
          now.add(const Duration(days: 1)),
          now: now,
        ),
        'tomorrow',
      );
      expect(
        OrganizationLanguage.relative(
          now.subtract(const Duration(days: 40)),
          now: now,
        ),
        '1 month ago',
      );
      expect(
        OrganizationLanguage.relative(null, now: now),
        'date not recorded',
      );
      expect(OrganizationLanguage.exact(null), 'not recorded');
      expect(OrganizationLanguage.exact(DateTime(2026, 9, 6)), '6 Sep 2026');
      expect(
        OrganizationLanguage.createdLine(org(createdKnown: false), now: now),
        'Creation date not recorded',
      );
      // No sign-in time is UNKNOWN, not "never signed in" (ORG-9).
      expect(
        OrganizationLanguage.lastSignInLine(org(), now: now),
        contains('unknown whether they never signed in'),
      );
    });

    test(
      'origin is a FACT only from the server-only access request; '
      'metadata.createdFrom (owner-editable) is quoted as a claim (ORG-9)',
      () {
        expect(
          OrganizationLanguage.originLine(org(), accessRequestFound: true),
          'Created by the team from an access request',
        );
        final claim = OrganizationLanguage.originLine(
          org(metadata: {'createdFrom': 'provisionOrganization'}),
        );
        expect(claim, startsWith('The record claims'));
        expect(claim, contains('owner-editable'));
        expect(claim, contains('no access request confirms it'));
        expect(
          OrganizationLanguage.originLine(
            org(metadata: {'createdFrom': 'registerAdmin'}),
          ),
          contains('owner-editable'),
        );
        expect(
          OrganizationLanguage.originLine(org()),
          'How it entered the system was not recorded',
        );
      },
    );

    test('identity falls back to the owner and says so', () {
      expect(OrganizationLanguage.displayName(org(orgName: '')), 'Arjun Rao');
      expect(
        OrganizationLanguage.nameIsOwnerFallback(org(orgName: '')),
        isTrue,
      );
      expect(
        OrganizationLanguage.displayName(org(orgName: '', owner: '')),
        'Unnamed organization',
      );
      // The email on the record is owner-editable: never "the sign-in".
      expect(
        OrganizationLanguage.ownerEmail(org(email: '')),
        'No email on the record',
      );
    });
  });
}

// ── labelForUid (added 2026-09-09, Superadmin ↔ Trainersarena E2E run) ───────
//
// 🔴 The Revenue screen printed `admin_payments_history.adminUid` verbatim, so
// "Top Paying Admins" and every transaction row showed a raw Firebase uid. In
// production those are 28-character tokens, so the screen that answers "who is
// paying us" could not name one customer.
void _labelForUidTests() {
  group('labelForUid', () {
    final orgs = [
      org(id: '9otLbZLeNz23l6kiCWuGsQKBNR6Z', orgName: 'Pulse Fitness Club'),
      org(id: 'org-iron-temple', orgName: 'Iron Temple Fitness'),
      org(id: 'org-no-name', orgName: '', owner: 'Ghost Owner'),
    ];

    test('resolves a uid to the organization name', () {
      expect(
        OrganizationLanguage.labelForUid('9otLbZLeNz23l6kiCWuGsQKBNR6Z', orgs),
        'Pulse Fitness Club',
      );
    });

    test('falls back to the owner name exactly like displayName', () {
      expect(
        OrganizationLanguage.labelForUid('org-no-name', orgs),
        'Ghost Owner',
      );
    });

    test('an unknown id is named as unknown, not prettified or hidden', () {
      final label = OrganizationLanguage.labelForUid('zzzzzzzzzzzzzzzz', orgs);
      expect(label, startsWith('Unknown organization ('));
      // Enough of the id survives to trace the record.
      expect(label, contains('zzzzzzzz'));
    });

    test('a short unknown id is shown whole', () {
      expect(
        OrganizationLanguage.labelForUid('abc123', orgs),
        'Unknown organization (abc123)',
      );
    });

    test('an empty id says so rather than rendering nothing', () {
      expect(
        OrganizationLanguage.labelForUid('  ', orgs),
        'Organization not recorded',
      );
    });
  });
}
