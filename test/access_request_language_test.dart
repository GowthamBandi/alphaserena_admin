// ACCESS REQUESTS — the words and the arithmetic, pinned.
//
// `AccessRequestLanguage` is the single place that turns a raw
// `access_requests` document into what an operator reads: stage words,
// urgency-by-age, the next action, who did what, ordering and filtering.

import 'package:alphaserena_admin_portel/core/services/access_request_language.dart';
import 'package:alphaserena_admin_portel/models/access_request_model.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 6, 12);

AccessRequestModel req(
  String id, {
  String status = 'requested',
  String org = 'Iron Temple Gym',
  String owner = 'Arjun Rao',
  String message = 'We run two branches and want online payments.',
  DateTime? created,
  String? provisionedOrgUid,
  int? teamSize,
  String city = '',
  String state = '',
}) =>
    AccessRequestModel(
      id: id,
      organizationName: org,
      ownerName: owner,
      email: '$id@example.com',
      phone: '+9198000$id',
      whatsapp: '',
      city: city,
      state: state,
      teamSize: teamSize,
      message: message,
      status: status,
      provisionedOrgUid: provisionedOrgUid,
      createdAt: created ?? now.subtract(const Duration(hours: 5)),
    );

void main() {
  group('stages', () {
    test('every backend status maps to a group and business words', () {
      const statuses = [
        'requested',
        'contacted',
        'payment_pending',
        'payment_confirmed',
        'approved',
        'organization_created',
        'rejected',
      ];
      for (final s in statuses) {
        expect(AccessRequestLanguage.isKnownStatus(s), isTrue, reason: s);
        expect(AccessRequestLanguage.stageLabel(s).contains('_'), isFalse, reason: s);
        expect(AccessRequestLanguage.eventLabel(s).contains('_'), isFalse, reason: s);
      }
      expect(AccessRequestLanguage.groupOf('payment_pending'), RequestGroup.inConversation);
      expect(AccessRequestLanguage.groupOf('approved'), RequestGroup.readyToCreate);
      expect(AccessRequestLanguage.groupOf('organization_created'), RequestGroup.created);
    });

    test('an unknown or legacy status is surfaced, not hidden or acted on', () {
      final r = req('x', status: 'on_hold');
      expect(AccessRequestLanguage.groupOf('on_hold'), RequestGroup.unknown);
      expect(AccessRequestLanguage.stageLabel('on_hold'), 'Unrecognised stage');
      expect(AccessRequestLanguage.nextAction(r), isNull, reason: 'no guessing');
      expect(AccessRequestLanguage.matchesFilter(r, 'open'), isTrue,
          reason: 'it still needs a human');
    });

    test('next action follows the pipeline and only the pipeline', () {
      expect(AccessRequestLanguage.nextAction(req('a')), 'Mark as contacted');
      expect(AccessRequestLanguage.nextAction(req('a', status: 'contacted')), 'Payment link sent');
      expect(AccessRequestLanguage.nextAction(req('a', status: 'payment_pending')), 'Record payment');
      expect(AccessRequestLanguage.nextAction(req('a', status: 'payment_confirmed')), 'Create organization');
      expect(AccessRequestLanguage.nextAction(req('a', status: 'approved')), 'Create organization');
      expect(AccessRequestLanguage.nextAction(req('a', status: 'rejected')), 'Reopen');
      expect(AccessRequestLanguage.nextAction(req('a', status: 'organization_created', provisionedOrgUid: 'u1')),
          'Open organization');
      // A provisioned uid wins over whatever the status says.
      expect(AccessRequestLanguage.nextAction(req('a', status: 'approved', provisionedOrgUid: 'u1')),
          'Open organization');
    });

    test('the creation action says it cannot be undone', () {
      final m = AccessRequestLanguage.nextActionMeaning(req('a', status: 'payment_confirmed'));
      expect(m, contains('cannot be undone'));
      expect(AccessRequestLanguage.nextActionMeaning(req('a')), contains('Nothing is created'));
    });
  });

  group('who / what / why with missing data', () {
    test('missing names and reason are said, never blank', () {
      final r = req('a', org: '  ', owner: '', message: '');
      expect(AccessRequestLanguage.organizationName(r), 'Organization name not provided');
      expect(AccessRequestLanguage.requesterName(r), 'Name not provided');
      expect(AccessRequestLanguage.reason(r), 'Reason not provided');
      expect(AccessRequestLanguage.initial(r), '?');
    });

    test('what they want is one business sentence with size and place', () {
      expect(AccessRequestLanguage.whatTheyWant(req('a', teamSize: 6, city: 'Pune', state: 'MH')),
          'A Trainersarena organization account · team of 6 · Pune, MH');
      expect(AccessRequestLanguage.whatTheyWant(req('a')), 'A Trainersarena organization account');
    });

    test('actors: prospect, you, a colleague by email, unknown', () {
      String? staff(String uid) => uid == 'u-priya' ? 'priya@trainersarena.in' : null;
      expect(AccessRequestLanguage.actor('prospect', staffName: staff), 'the requester');
      expect(AccessRequestLanguage.actor('u-me', staffName: staff, currentUid: 'u-me'), 'you');
      expect(AccessRequestLanguage.actor('u-priya', staffName: staff), 'priya@trainersarena.in');
      expect(AccessRequestLanguage.actor('u-gone', staffName: staff), 'a super-admin');
      expect(AccessRequestLanguage.actor('', staffName: staff), 'Unknown');
    });
  });

  group('age and urgency', () {
    test('waiting thresholds: normal < 3 days, waiting 3–6, overdue 7+', () {
      expect(AccessRequestLanguage.waitLevel(req('a', created: now.subtract(const Duration(days: 2))), now: now),
          WaitLevel.fresh);
      expect(AccessRequestLanguage.waitLevel(req('a', created: now.subtract(const Duration(days: 3))), now: now),
          WaitLevel.waiting);
      expect(AccessRequestLanguage.waitLevel(req('a', created: now.subtract(const Duration(days: 7))), now: now),
          WaitLevel.overdue);
    });

    test('completed requests are never "overdue"', () {
      final old = now.subtract(const Duration(days: 40));
      expect(AccessRequestLanguage.waitLevel(req('a', status: 'rejected', created: old), now: now),
          WaitLevel.fresh);
      expect(AccessRequestLanguage.waitingLine(req('a', status: 'organization_created', created: old), now: now), '');
    });

    test('waiting line and relative age wording', () {
      expect(AccessRequestLanguage.waitingLine(req('a', created: now.subtract(const Duration(hours: 3))), now: now),
          'Received today');
      expect(AccessRequestLanguage.waitingLine(req('a', created: now.subtract(const Duration(days: 5))), now: now),
          'Waiting 5 days');
      expect(AccessRequestLanguage.ago(now.subtract(const Duration(minutes: 2)), now: now), '2 minutes ago');
      expect(AccessRequestLanguage.ago(now.subtract(const Duration(days: 1)), now: now), 'Yesterday');
      expect(AccessRequestLanguage.ago(DateTime(2026, 7, 1), now: now), '1 Jul 2026');
      expect(AccessRequestLanguage.ago(null, now: now), 'Time not recorded');
    });

    test('a request with no created date is not overdue and says so', () {
      final r = AccessRequestModel(
          id: 'legacy', organizationName: 'Old Gym', ownerName: 'X', email: '', phone: '', status: 'requested');
      expect(AccessRequestLanguage.waitLevel(r, now: now), WaitLevel.fresh);
      expect(AccessRequestLanguage.waitingLine(r, now: now), 'Waiting time unknown');
    });
  });

  group('ordering — a work queue, not an archive', () {
    test('open rows oldest first, then completed newest first, dateless last', () {
      final sorted = AccessRequestLanguage.sorted([
        req('done-new', status: 'organization_created', provisionedOrgUid: 'u', created: now.subtract(const Duration(days: 1))),
        req('open-old', created: now.subtract(const Duration(days: 9))),
        req('done-old', status: 'rejected', created: now.subtract(const Duration(days: 20))),
        req('open-new', created: now.subtract(const Duration(hours: 1))),
        AccessRequestModel(id: 'open-nodate', organizationName: 'x', ownerName: 'y', email: '', phone: '', status: 'contacted'),
      ]);
      expect(sorted.map((r) => r.id), ['open-old', 'open-new', 'open-nodate', 'done-new', 'done-old']);
    });
  });

  group('filters and search', () {
    final rows = [
      req('a', created: now.subtract(const Duration(days: 8)), city: 'Pune'),
      req('b', status: 'payment_pending', owner: 'Meera Shah'),
      req('c', status: 'payment_confirmed', org: 'Pulse Fitness'),
      req('d', status: 'organization_created', provisionedOrgUid: 'u'),
      req('e', status: 'rejected'),
      req('f', status: 'weird'),
    ];

    test('filter keys pick the right rows', () {
      List<String> ids(String f) =>
          rows.where((r) => AccessRequestLanguage.matchesFilter(r, f, now: now)).map((r) => r.id).toList();
      expect(ids('open'), ['a', 'b', 'c', 'f'], reason: 'unknown stage counts as open');
      expect(ids('new'), ['a']);
      expect(ids('conversation'), ['b']);
      expect(ids('ready'), ['c']);
      expect(ids('created'), ['d']);
      expect(ids('rejected'), ['e']);
      expect(ids('overdue'), ['a']);
      expect(ids('all').length, 6);
      expect(ids('payment_pending'), ['b'], reason: 'raw status still works');
    });

    test('search matches gym, requester, email, phone, city and exact id', () {
      bool m(String q, String id) => AccessRequestLanguage.matches(rows.firstWhere((r) => r.id == id), q);
      expect(m('pulse', 'c'), isTrue);
      expect(m('meera', 'b'), isTrue);
      expect(m('B@EXAMPLE', 'b'), isTrue);
      expect(m('98000a', 'a'), isTrue);
      expect(m('pune', 'a'), isTrue);
      expect(m('c', 'c'), isTrue, reason: 'exact id');
      expect(m('zzz', 'a'), isFalse);
      expect(m('   ', 'a'), isTrue, reason: 'blank matches all');
    });

    test('completed-recently window is 30 days; a dateless row is kept', () {
      expect(AccessRequestLanguage.completedRecently(req('a', created: now.subtract(const Duration(days: 29))), now: now), isTrue);
      expect(AccessRequestLanguage.completedRecently(req('a', created: now.subtract(const Duration(days: 31))), now: now), isFalse);
      expect(
          AccessRequestLanguage.completedRecently(
              AccessRequestModel(id: 'x', organizationName: 'x', ownerName: 'x', email: '', phone: '', status: 'rejected'),
              now: now),
          isTrue);
    });
  });

  group('plan summary — what approval allows', () {
    test('reads as price + limits with unlimited spelled out', () {
      final plan = SubscriptionPlanModel.fromMap({
        'title': 'Growth',
        'price': 4999,
        'months': 1,
        'isActive': true,
        'limits': {'trainers': 5, 'clients': 1000000000, 'workoutPlans': 20, 'dietPlans': 20, 'workouts': 100},
      }, 'growth');
      final s = AccessRequestLanguage.planSummary(plan);
      expect(s, startsWith('Growth — ₹4999 / 1 month'));
      expect(s, contains('5 team members'));
      expect(s, contains('unlimited active clients'));
    });
  });
}
