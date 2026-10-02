// ORG-1 — ONE OWNER'S TYPE-DRIFTED WRITE MUST NOT BLANK THE FOUNDER'S LIST.
//
// The rules let an organization owner write most profile keys on their own
// `admins/{uid}` doc with ANY type (`spokenLanguages: 'English'`,
// `metadata: 'x'`). The old model did unchecked casts; the list parsed the
// whole snapshot inside one try whose catch only printed. On a fresh load the
// founder saw "No organizations yet — None exist on the platform so far"; on
// an open console the list froze under "Live, updated". The Dashboard parsed
// with no try at all (org KPIs spun forever) and cleared its name map BEFORE
// the throwing loop.
//
// The fix parses PER FIELD (never throws) and per document (never skips): the
// poisoned organization stays listed, flagged, and moderatable — skipping it
// would be exactly the moderation-evasion outcome.

import 'package:alphaserena_admin_portel/controllers/dashboard_controller.dart';
import 'package:alphaserena_admin_portel/controllers/organization_detail_controller.dart';
import 'package:alphaserena_admin_portel/core/services/organization_language.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/trainer_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'organization_workspace_behaviour_test.dart' as w;
import 'organizations_screen_behaviour_test.dart' as list;

Map<String, dynamic> good(String name, {String status = 'active'}) => {
  'organizationName': name,
  'name': 'Owner of $name',
  'email': '${name.toLowerCase()}@x.in',
  'status': status,
  'isSubscriptionActive': true,
  'planExpiry': list.now.add(const Duration(days: 60)).toIso8601String(),
  'createdAt': list.now.subtract(const Duration(days: 30)).toIso8601String(),
};

/// Every owner-writable key the verifier proved can be written with any type.
Map<String, dynamic> poisoned() => {
  ...good('Rogue Gym'),
  'spokenLanguages': 'English',
  'metadata': 'x',
  'phone': 9876543210,
  'name': {'first': 'R'},
  'lastLogin': 42,
  'createdAt': 'not a date',
};

void main() {
  tearDown(Get.reset);

  group('AdminModel parses per FIELD and never throws', () {
    test('each owner-writable type drift reads as blank and is recorded', () {
      final a = AdminModel.fromMap(poisoned(), 'rogue');
      expect(a.organizationName, 'Rogue Gym');
      expect(a.spokenLanguages, isEmpty);
      expect(a.metadata, isNull);
      expect(a.phone, '9876543210', reason: 'a readable scalar is kept');
      expect(a.name, '');
      expect(a.lastLogin, isNull);
      expect(a.createdAtKnown, isFalse);
      expect(
        a.malformedFields,
        containsAll([
          'spokenLanguages',
          'metadata',
          'phone',
          'name',
          'lastLogin',
          'createdAt',
        ]),
      );
      expect(a.hasMalformedFields, isTrue);
      expect(a.unreadable, isFalse);
      expect(a.status, 'active', reason: 'moderation fields still read');
    });

    test('lists of mixed types, maps, booleans and dates are tolerated', () {
      final a = AdminModel.fromMap({
        'spokenLanguages': [
          'Telugu',
          3,
          null,
          {'x': 1},
        ],
        'subscription': 'broken',
        'subscriptionLimits': 'broken',
        'isVerified': 'yes',
        'isSubscriptionActive': 'true',
        'planExpiry': {'seconds': 1, 'nanoseconds': 0},
        'trainerIds': 'one',
        'features': 'all',
      }, 'd');
      expect(a.spokenLanguages, ['Telugu', '3']);
      expect(a.subscription, isNull);
      expect(a.subscriptionLimits.maxTrainers, 0);
      expect(a.isVerified, isFalse);
      expect(a.isSubscriptionActive, isFalse);
      expect(a.planExpiry, isNull);
      expect(a.trainerIds, isEmpty);
      expect(a.features, isNull);
      expect(
        a.malformedFields,
        containsAll([
          'spokenLanguages',
          'subscription',
          'subscriptionLimits',
          'isVerified',
          'isSubscriptionActive',
          'planExpiry',
          'trainerIds',
          'features',
        ]),
      );
    });

    test('a clean record has no malformed fields', () {
      final a = AdminModel.fromMap(good('Iron'), 'iron');
      expect(a.malformedFields, isEmpty);
      expect(a.hasMalformedFields, isFalse);
    });

    test('a non-map document becomes a moderatable placeholder, never an '
        'exception', () {
      final a = AdminModel.parseDoc('ghost', 'not a map');
      expect(a.unreadable, isTrue);
      expect(a.docId, 'ghost');
      expect(a.status, 'pending');
      expect(
        OrganizationLanguage.recordIssues(a, now: list.now).map((i) => i.code),
        contains('unreadable_record'),
      );
    });

    test(
      'the model and the fresh server read normalise status identically',
      () {
        expect(AdminModel.normalizeStatus(null), 'pending');
        expect(AdminModel.normalizeStatus('approved'), 'active');
        expect(AdminModel.normalizeStatus('blocked'), 'blocked');
        expect(AdminModel.normalizeStatus(7), '7');
      },
    );

    test('a malformed-field record is flagged as a record issue', () {
      final issues = OrganizationLanguage.recordIssues(
        AdminModel.fromMap(poisoned(), 'rogue'),
        now: list.now,
      );
      final i = issues.firstWhere((i) => i.code == 'malformed_fields');
      expect(i.severity, OrgIssueSeverity.attention);
      expect(i.why, contains('spokenLanguages'));
      expect(i.why, contains('owner can write these fields'));
    });

    test('TrainerModel reads a type-drifted trainer doc without throwing', () {
      final t = TrainerModel.fromMap({
        'name': 7,
        'email': {'x': 1},
        'clientIds': 'm1',
        'isVerified': 'yes',
        'metadata': 'x',
        'status': null,
      }, 't1');
      expect(t.name, '7');
      expect(t.email, '');
      expect(t.clientIds, isEmpty);
      expect(t.isVerified, isFalse);
      expect(t.metadata, isNull);
      expect(t.status, 'pending');
    });
  });

  group('AdminController ingests one document at a time', () {
    test(
      '3 good + 1 poisoned → 4 rows, the poisoned one flagged, no error',
      () {
        final c = list.FakeAdmins();
        c.ingestDocs([
          ('a', good('Alpha')),
          ('rogue', poisoned()),
          ('b', good('Bravo')),
          ('c', good('Charlie')),
        ]);
        expect(c.admins.length, 4);
        expect(c.loadError.value, isNull);
        expect(c.lastReceived.value, isNotNull);
        expect(c.malformedRecords.map((a) => a.docId), ['rogue']);
        expect(c.byId('rogue')!.organizationName, 'Rogue Gym');
      },
    );

    test('a document that is not a map is still a row (never skipped)', () {
      final c = list.FakeAdmins();
      c.ingestDocs([('a', good('Alpha')), ('x', 12)]);
      expect(c.admins.length, 2);
      expect(c.byId('x')!.unreadable, isTrue);
    });

    testWidgets(
      'a fresh load whose only record is poisoned is NEVER "No organizations '
      'yet" — it is listed, flagged and can still be blocked',
      (tester) async {
        list.mount(rows: const []);
        list.ctrl.ingestDocs([('rogue', poisoned())]);
        await list.pump(tester);
        expect(find.text('No organizations yet'), findsNothing);
        expect(find.text('Rogue Gym'), findsWidgets);
        expect(
          find.textContaining('with fields of the wrong type or unreadable'),
          findsOneWidget,
          reason: 'the list names how many records are malformed',
        );
        expect(
          find.textContaining('Record has fields of the wrong type'),
          findsOneWidget,
        );
        // Moderation still works on the poisoned record.
        final ok = await list.ctrl.block(list.ctrl.byId('rogue')!, 'tamper');
        expect(ok, isTrue);
        expect(list.ctrl.moderationCalls, 1);
      },
    );
  });

  group('DashboardController ingests one document at a time', () {
    DashboardController dash() =>
        DashboardController()..liveCountOverride = ((_) async => 0);

    test('a poisoned record in the middle neither stalls the KPIs nor '
        'blanks the names of the organizations after it', () {
      final d = dash();
      d.ingestAdmins([
        ('a', good('Alpha')),
        ('rogue', poisoned()),
        ('z', good('Zulu')),
      ]);
      expect(d.orgsLoaded.value, isTrue);
      expect(d.orgsError.value, isFalse);
      expect(d.orgsTotal, 3);
      expect(d.orgsMalformed.value, 1);
      expect(d.orgName('z'), 'Zulu', reason: 'names after the bad doc survive');
      expect(d.orgName('rogue'), 'Rogue Gym');
      d.onClose();
    });

    test('the name map is replaced whole, not cleared first', () {
      final d = dash();
      d.ingestAdmins([('a', good('Alpha'))]);
      d.ingestAdmins([('b', good('Bravo'))]);
      expect(d.orgName('a'), isNull);
      expect(d.orgName('b'), 'Bravo');
      d.onClose();
    });

    test('"capture unverified" is never raised for a manual receipt', () {
      final d = dash();
      d.ingestPayments([
        (
          'manual',
          {
            'adminUid': 'a',
            'amount': 4999,
            'method': 'manual',
            'reference': 'UTR-1',
            'captureVerified': false,
            'createdAt': list.now.toIso8601String(),
          },
        ),
        (
          'online',
          {
            'adminUid': 'a',
            'amount': 999,
            'razorpayPaymentId': 'pay_1',
            'captureVerified': false,
            'createdAt': list.now
                .subtract(const Duration(days: 1))
                .toIso8601String(),
          },
        ),
      ]);
      final byGross = {for (final e in d.recentPayments) e.gross: e};
      expect(byGross[4999]!.captureVerified, isTrue);
      expect(byGross[4999]!.recordedManually, isTrue);
      expect(byGross[999]!.captureVerified, isFalse);
      d.onClose();
    });
  });

  group('OrganizationDetailController keeps the last GOOD copy', () {
    test('lastReceived is stamped only after a successful parse', () {
      final d = OrganizationDetailController('rogue');
      d.ingestRecord(exists: true, data: good('Rogue Gym'));
      final firstStamp = d.lastReceived.value;
      expect(firstStamp, isNotNull);
      expect(d.admin.value!.organizationName, 'Rogue Gym');

      d.ingestRecord(exists: true, data: 'garbage');
      expect(d.admin.value!.organizationName, 'Rogue Gym', reason: 'last good');
      expect(d.recordUnreadable.value, isTrue);
      expect(d.adminError.value, isNotNull);
      expect(d.lastReceived.value, same(firstStamp), reason: 'not re-stamped');

      d.ingestRecord(exists: true, data: good('Rogue Gym 2'));
      expect(d.recordUnreadable.value, isFalse);
      expect(d.adminError.value, isNull);
      expect(d.admin.value!.organizationName, 'Rogue Gym 2');
    });

    test('an unreadable FIRST version still yields a moderatable row', () {
      final d = OrganizationDetailController('ghost');
      d.ingestRecord(exists: true, data: 42);
      expect(d.admin.value, isNotNull);
      expect(d.admin.value!.unreadable, isTrue);
      expect(d.lastReceived.value, isNull);
    });

    test('a record with malformed fields is a readable version — shown and '
        'stamped', () {
      final d = OrganizationDetailController('rogue');
      d.ingestRecord(exists: true, data: poisoned());
      expect(d.lastReceived.value, isNotNull);
      expect(d.recordUnreadable.value, isFalse);
      expect(d.admin.value!.malformedFields, contains('metadata'));
    });

    test('Timestamp dates are read (the production shape)', () {
      final d = OrganizationDetailController('o');
      d.ingestRecord(
        exists: true,
        data: {
          ...good('Iron'),
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
        },
      );
      expect(d.admin.value!.createdAtKnown, isTrue);
      expect(d.admin.value!.malformedFields, isEmpty);
    });
  });

  group('the workspace says when the record is not a clean live copy', () {
    testWidgets('stream failed with a record present → "last good copy"', (
      tester,
    ) async {
      await w.open(
        tester,
        seed: (d) {
          w.seedHealthy(d, w.a_);
          d.adminError.value = const ConsoleError(
            kind: ConsoleErrorKind.offline,
            message: 'Could not reach Firestore.',
          );
        },
      );
      expect(
        find.text('Not live — showing the last good copy'),
        findsOneWidget,
      );
      expect(find.text('Reconnect'), findsOneWidget);
      expect(find.text('Iron Temple'), findsWidgets, reason: 'record stays');
    });

    testWidgets('an unreadable version → "Unreadable record" banner', (
      tester,
    ) async {
      await w.open(
        tester,
        seed: (d) {
          w.seedHealthy(d, w.a_);
          d.recordUnreadable.value = true;
          d.adminError.value = const ConsoleError(
            kind: ConsoleErrorKind.unknown,
            message: 'x',
          );
        },
      );
      expect(
        find.text('Unreadable record — showing the last good copy'),
        findsOneWidget,
      );
    });

    testWidgets('malformed fields are named above the record', (tester) async {
      final a = AdminModel.fromMap(poisoned(), 'ok');
      await w.open(tester, org: a, seed: (d) => w.seedHealthy(d, a));
      expect(
        find.text('Some fields on this record are of the wrong type'),
        findsOneWidget,
      );
      expect(find.textContaining('spokenLanguages'), findsWidgets);
    });

    testWidgets('a clean live record shows no banner', (tester) async {
      await w.open(tester);
      expect(find.textContaining('last good copy'), findsNothing);
      expect(find.textContaining('wrong type'), findsNothing);
    });
  });
}
