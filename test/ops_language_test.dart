// THE OPERATIONS CENTER'S WORDS AND ORDER, PINNED.
//
// `OpsLanguage` turns raw backend records into what a business owner reads.
// These tests pin: every backend type has plain-language words (no type id in
// a title), urgency classification, status lifecycle, the priority order,
// filters, time wording, money formatting, deleted-organization handling and
// malformed records.

import 'package:alphaserena_admin_portel/core/services/ops_language.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/ops_incident_model.dart';
import 'package:alphaserena_admin_portel/models/org_feedback_model.dart';
import 'package:alphaserena_admin_portel/models/org_review_model.dart';
import 'package:alphaserena_admin_portel/models/platform_announcement_model.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 9, 6, 10, 30);

String? names(String uid) =>
    const {'org-a': 'Iron Temple Gym', 'org-b': 'Pulse Fitness'}[uid];

OpsIncidentModel incident(
  String type, {
  String severity = 'P1',
  String status = 'open',
  Map<String, String> context = const {},
  int occurrences = 1,
  DateTime? lastSeen,
}) => OpsIncidentModel(
  id: 'inc-$type',
  type: type,
  severity: severity,
  fn: 'someFunction',
  correlationId: 'pay_ABC123',
  summary: 'backend summary line',
  action: 'engineer guidance',
  context: context,
  status: status,
  occurrences: occurrences,
  firstSeenAt: now.subtract(const Duration(days: 2)),
  lastSeenAt: lastSeen ?? now.subtract(const Duration(hours: 3)),
  resolvedAt: status == 'resolved'
      ? now.subtract(const Duration(hours: 1))
      : null,
  resolutionNote: status == 'resolved' ? 'Fixed by hand' : '',
);

AdminModel org(
  String id, {
  String status = 'active',
  bool subscribed = true,
  DateTime? expiry,
}) => AdminModel.fromMap({
  'organizationName': names(id) ?? id,
  'name': 'owner',
  'status': status,
  'isSubscriptionActive': subscribed,
  if (expiry != null) 'planExpiry': expiry.toIso8601String(),
  'createdAt': DateTime(2026, 8, 1).toIso8601String(),
}, id);

void main() {
  group('incident language', () {
    test(
      'every registered backend type reads as a sentence, never as its id',
      () {
        const types = [
          'settlement_create_failed',
          'webhook_signature_rejected',
          'gateway_request_failed',
          'webhook_handler_error',
          'crash_new_fatal_signature',
          'crash_widespread',
          'crash_escalating',
          'admin_status_audit_failed',
          'org_cascade_failed',
          'org_auth_enforcement_failed',
          'scheduled_job_warning',
        ];
        for (final t in types) {
          final item = OpsLanguage.fromIncident(incident(t), orgName: names);
          expect(
            item.title.contains('_'),
            isFalse,
            reason: '$t title leaks an id',
          );
          expect(item.title, isNot(contains(t)));
          expect(
            item.why,
            isNotEmpty,
            reason: '$t has no consequence sentence',
          );
          expect(
            item.technical.any((e) => e.value == t),
            isTrue,
            reason: 'the raw type must survive under Technical details',
          );
        }
      },
    );

    test(
      'urgency follows the backend severity unless the words override it',
      () {
        expect(
          OpsLanguage.fromIncident(
            incident('settlement_create_failed', severity: 'P0'),
            orgName: names,
          ).urgency,
          OpsUrgency.critical,
        );
        expect(
          OpsLanguage.fromIncident(
            incident('org_cascade_failed', severity: 'P1'),
            orgName: names,
          ).urgency,
          OpsUrgency.high,
        );
        // crash_escalating is P2 and deliberately "a trend, not an outage".
        expect(
          OpsLanguage.fromIncident(
            incident('crash_escalating', severity: 'P2'),
            orgName: names,
          ).urgency,
          OpsUrgency.attention,
        );
      },
    );

    test('an unknown type is still an item, worded honestly, with details', () {
      final item = OpsLanguage.fromIncident(
        incident('brand_new_type'),
        orgName: names,
      );
      expect(item.title, 'The system flagged a problem');
      expect(item.why, 'backend summary line');
      expect(item.urgency, OpsUrgency.high, reason: 'P1 default');
      expect(item.technical.first.value, 'brand_new_type');
    });

    test(
      'status lifecycle: open → needs attention, acknowledged → in progress, '
      'resolved → resolved with reopen as the only action',
      () {
        final open = OpsLanguage.fromIncident(incident('x'), orgName: names);
        expect(open.status, OpsItemStatus.needsAttention);
        expect(open.primary.kind, OpsActionKind.resolve);
        expect(
          open.secondary.any((a) => a.kind == OpsActionKind.acknowledge),
          isTrue,
        );

        final ack = OpsLanguage.fromIncident(
          incident('x', status: 'acknowledged'),
          orgName: names,
        );
        expect(ack.status, OpsItemStatus.inProgress);
        expect(
          ack.secondary.any((a) => a.kind == OpsActionKind.acknowledge),
          isFalse,
          reason: 'cannot mark in progress twice',
        );

        final res = OpsLanguage.fromIncident(
          incident('x', status: 'resolved'),
          orgName: names,
        );
        expect(res.status, OpsItemStatus.resolved);
        expect(res.primary.kind, OpsActionKind.reopen);
        expect(res.resolutionNote, 'Fixed by hand');
      },
    );

    test(
      'affected organization is named from context; a missing one is said',
      () {
        final named = OpsLanguage.fromIncident(
          incident('org_cascade_failed', context: {'adminUid': 'org-a'}),
          orgName: names,
        );
        expect(named.affected, 'Iron Temple Gym');
        final gone = OpsLanguage.fromIncident(
          incident('org_cascade_failed', context: {'adminUid': 'deleted'}),
          orgName: names,
        );
        expect(gone.affected, OpsLanguage.unknownOrganization);
        final crash = OpsLanguage.fromIncident(
          incident('crash_widespread'),
          orgName: names,
        );
        expect(crash.affected, 'App users');
      },
    );

    test('a record with no timestamps still renders and says so', () {
      final i = OpsIncidentModel.fromMap({
        'type': 'scheduled_job_warning',
      }, 'legacy');
      final item = OpsLanguage.fromIncident(i, orgName: names);
      expect(item.when, isNull);
      expect(OpsTime.human(item.when, now: now), 'Time not recorded');
      expect(item.count, 1, reason: 'occurrences 0 is shown as 1, never 0');
    });
  });

  group('payment alert language', () {
    test('each backend kind maps to plain words and the right urgency', () {
      final cases = {
        'charged_not_activated': OpsUrgency.critical,
        'dispute': OpsUrgency.critical,
        'settlement_stuck_in_flight': OpsUrgency.high,
        'refund_inconsistent': OpsUrgency.high,
        'payment_failed': OpsUrgency.info,
      };
      cases.forEach((kind, urgency) {
        final item = OpsLanguage.fromPaymentAlert({
          'id': 'a1',
          'kind': kind,
          'status': 'open',
          'amountPaise': 499900,
        }, orgName: names);
        expect(item.urgency, urgency, reason: kind);
        expect(item.title.contains('_'), isFalse, reason: kind);
        expect(item.affected, contains('₹4,999'));
      });
    });

    test(
      'a failed payment attempt is INFORMATION with a Dismiss, not an alarm',
      () {
        final item = OpsLanguage.fromPaymentAlert({
          'id': 'a1',
          'kind': 'payment_failed',
          'status': 'open',
        }, orgName: names);
        expect(item.status, OpsItemStatus.informational);
        expect(item.primary.kind, OpsActionKind.resolve);
        expect(item.primary.label, 'Dismiss');
      },
    );

    test('a dispute leads with its response deadline', () {
      final due = now.add(const Duration(days: 3));
      final item = OpsLanguage.fromPaymentAlert({
        'id': 'd1',
        'kind': 'dispute',
        'status': 'open',
        'respondBy': due,
        'createdAt': now,
      }, orgName: names);
      expect(item.whenLabel, 'Respond by');
      expect(item.when, due);
    });

    test(
      'legacy `type` field and unknown kinds still produce a reviewable item',
      () {
        final legacy = OpsLanguage.fromPaymentAlert({
          'id': 'l',
          'type': 'refund_inconsistent',
          'status': 'open',
          'adminUid': 'org-b',
        }, orgName: names);
        expect(legacy.title, 'A refund left the records inconsistent');
        expect(legacy.affected, 'Pulse Fitness');
        final unknown = OpsLanguage.fromPaymentAlert({
          'id': 'u',
          'status': 'open',
        }, orgName: names);
        expect(unknown.title, 'A payment needs review');
        expect(unknown.urgency, OpsUrgency.high);
      },
    );

    test(
      'a resolved alert is resolved, keeps its note, and cannot be re-resolved',
      () {
        final item = OpsLanguage.fromPaymentAlert({
          'id': 'r',
          'kind': 'charged_not_activated',
          'status': 'resolved',
          'resolutionNote': 'Activated manually',
        }, orgName: names);
        expect(item.status, OpsItemStatus.resolved);
        expect(item.resolutionNote, 'Activated manually');
        expect(item.primary.kind, OpsActionKind.navigate);
      },
    );
  });

  group('quota alerts', () {
    test(
      'names the organization and translates resources into business words',
      () {
        final item = OpsLanguage.fromQuotaAlert({
          'id': 'org-a',
          'adminUid': 'org-a',
          'violations': [
            {'resource': 'clients', 'used': 60, 'limit': 50},
            {'resource': 'workoutPlans', 'used': 25, 'limit': 20},
          ],
        }, orgName: names);
        expect(item.title, 'Iron Temple Gym is over its plan limits');
        expect(item.why, contains('60 of 50 members'));
        expect(item.why, contains('25 of 20 workout plans'));
        expect(item.urgency, OpsUrgency.attention);
        expect(item.primary.kind, OpsActionKind.navigate);
      },
    );

    test('a deleted organization is said, not shown as a blank name', () {
      final item = OpsLanguage.fromQuotaAlert({
        'id': 'gone',
        'violations': [],
      }, orgName: names);
      expect(item.title, startsWith(OpsLanguage.unknownOrganization));
    });
  });

  group('organizations', () {
    test(
      'pending, expired, expiring and moderated each become one worded row',
      () {
        final items = OpsLanguage.fromOrganizations([
          org('p1', status: 'pending', subscribed: false),
          org('p2', status: 'pending', subscribed: false),
          org(
            'org-a',
            subscribed: false,
            expiry: now.subtract(const Duration(days: 3)),
          ),
          org('org-b', expiry: now.add(const Duration(days: 2))),
          org('w', status: 'warning'),
        ], now: now);
        final byId = {for (final i in items) i.id: i};
        expect(
          byId['orgs:pending']!.title,
          '2 organizations are waiting for approval',
        );
        expect(byId['orgs:pending']!.primary.orgFilter, 'pending');
        expect(
          byId['orgs:lapsed']!.title,
          "Iron Temple Gym's subscription has expired",
        );
        expect(byId['orgs:lapsed']!.urgency, OpsUrgency.high);
        expect(
          byId['orgs:expiring']!.title,
          "Pulse Fitness's subscription ends within 7 days",
        );
        expect(byId['orgs:moderated']!.status, OpsItemStatus.informational);
      },
    );

    test(
      'expiring uses calendar days: expired an hour ago is lapsed, not expiring',
      () {
        final items = OpsLanguage.fromOrganizations([
          org(
            'org-a',
            subscribed: false,
            expiry: now.subtract(const Duration(hours: 1)),
          ),
          org('org-b', expiry: now.add(const Duration(days: 7, hours: 5))),
        ], now: now);
        expect(items.map((i) => i.id), contains('orgs:lapsed'));
        expect(
          items.map((i) => i.id),
          contains('orgs:expiring'),
          reason: '7 calendar days ahead is still inside the window',
        );
      },
    );

    test('a healthy roster yields no rows', () {
      expect(
        OpsLanguage.fromOrganizations([
          org('org-a', expiry: now.add(const Duration(days: 40))),
        ], now: now),
        isEmpty,
      );
    });
  });

  group('support and announcements', () {
    test('a complaint raises urgency to high; plain feedback is attention', () {
      OrgFeedbackModel fb(String cat) => OrgFeedbackModel.fromMap({
        'adminId': 'org-a',
        'adminName': 'Iron Temple Gym',
        'category': cat,
        'subject': 's',
        'message': 'm',
        'status': 'open',
      }, 'f-$cat');
      final plain = OpsLanguage.fromSupport(
        [fb('feature')],
        [],
        orgName: names,
      );
      expect(plain.single.urgency, OpsUrgency.attention);
      expect(
        plain.single.title,
        'Iron Temple Gym is waiting for a support reply',
      );
      final complaint = OpsLanguage.fromSupport(
        [fb('complaint'), fb('bug')],
        [],
        orgName: names,
      );
      expect(complaint.single.urgency, OpsUrgency.high);
      expect(complaint.single.count, 2);
    });

    test('low reviews are attention; resolved feedback is ignored', () {
      final r = OrgReviewModel.fromMap({'adminId': 'org-b', 'rating': 1}, 'r1');
      final resolved = OrgFeedbackModel.fromMap({
        'adminId': 'org-a',
        'status': 'resolved',
        'category': 'complaint',
      }, 'f');
      final items = OpsLanguage.fromSupport([resolved], [r], orgName: names);
      expect(items.length, 1);
      expect(items.single.id, 'support:reviews');
      expect(items.single.affected, 'Pulse Fitness');
    });

    test(
      'announcements: failed is high, stuck-in-queue only after 15 minutes',
      () {
        PlatformAnnouncementModel ann(
          String id,
          String status, {
          DateTime? queuedAt,
        }) => PlatformAnnouncementModel.fromMap({
          'title': 'Title $id',
          'body': 'b',
          'status': status,
          if (queuedAt != null) 'queuedAt': queuedAt.toIso8601String(),
        }, id);
        final items = OpsLanguage.fromAnnouncements([
          ann('f', 'failed'),
          ann(
            'fresh',
            'queued',
            queuedAt: now.subtract(const Duration(minutes: 2)),
          ),
          ann(
            'stale',
            'queued',
            queuedAt: now.subtract(const Duration(minutes: 40)),
          ),
        ], now: now);
        final ids = items.map((i) => i.id).toList();
        expect(
          ids,
          containsAll(['announcements:failed', 'announcements:stalled']),
        );
        expect(
          items.firstWhere((i) => i.id == 'announcements:stalled').count,
          1,
          reason: 'a two-minute-old queue entry is healthy, not stuck',
        );
      },
    );
  });

  group('priority and filters — the 30-event scenario', () {
    List<OpsItem> mixed() => [
      for (int i = 0; i < 20; i++)
        OpsLanguage.fromPaymentAlert({
          'id': 'pf$i',
          'kind': 'payment_failed',
          'status': 'open',
          'createdAt': now.subtract(Duration(minutes: i)),
        }, orgName: names),
      OpsLanguage.fromIncident(
        incident('crash_escalating', severity: 'P2'),
        orgName: names,
      ),
      OpsLanguage.fromIncident(
        incident(
          'org_cascade_failed',
          severity: 'P1',
          context: {'adminUid': 'org-a'},
        ),
        orgName: names,
      ),
      OpsLanguage.fromIncident(
        incident('scheduled_job_warning', severity: 'P1'),
        orgName: names,
      ),
      OpsLanguage.fromPaymentAlert({
        'id': 'crit',
        'kind': 'charged_not_activated',
        'status': 'open',
        'adminUid': 'org-b',
        'createdAt': now,
      }, orgName: names),
      for (int i = 0; i < 4; i++)
        OpsLanguage.fromIncident(
          incident('done$i', status: 'resolved'),
          orgName: names,
        ),
      OpsLanguage.fromIncident(
        incident(
          'org_auth_enforcement_failed',
          status: 'acknowledged',
          context: {'adminUid': 'org-b'},
        ),
        orgName: names,
      ),
    ];

    test(
      'the one critical item is first; informational noise sinks to the bottom',
      () {
        final sorted = OpsLanguage.sorted(mixed());
        expect(sorted.first.id, 'payment:crit');
        expect(sorted.first.urgency, OpsUrgency.critical);
        // Everything that needs a human comes before the 20 failed-payment notes.
        final firstInfo = sorted.indexWhere(
          (i) => i.status == OpsItemStatus.informational,
        );
        final lastActionable = sorted.lastIndexWhere(
          (i) => i.isActionable && i.urgency != OpsUrgency.info,
        );
        expect(lastActionable, lessThan(firstInfo));
        // Resolved rows are last.
        expect(
          sorted.where((i) => i.status == OpsItemStatus.resolved).length,
          4,
        );
        expect(sorted.last.status, OpsItemStatus.resolved);
      },
    );

    test(
      'within one urgency, open comes before in-progress, then newest first',
      () {
        final a = OpsLanguage.fromIncident(
          incident('x', status: 'acknowledged', lastSeen: now),
          orgName: names,
        );
        final b = OpsLanguage.fromIncident(
          incident('y', lastSeen: now.subtract(const Duration(hours: 5))),
          orgName: names,
        );
        final c = OpsLanguage.fromIncident(
          incident('z', lastSeen: now),
          orgName: names,
        );
        final sorted = OpsLanguage.sorted([a, b, c]);
        expect(sorted.map((i) => i.id), [
          'incident:inc-z',
          'incident:inc-y',
          'incident:inc-x',
        ]);
      },
    );

    test('filter by urgency and by text (organization, reference, id)', () {
      final all = mixed();
      expect(OpsLanguage.filter(all, urgency: OpsUrgency.critical).length, 1);
      expect(
        OpsLanguage.filter(all, query: 'iron temple').single.id,
        'incident:inc-org_cascade_failed',
      );
      expect(
        OpsLanguage.filter(all, query: 'pay_ABC123').length,
        greaterThan(1),
        reason: 'technical references are searchable',
      );
      expect(OpsLanguage.filter(all, query: 'zzz-nothing'), isEmpty);
      expect(
        OpsLanguage.filter(all, query: '   ').length,
        all.length,
        reason: 'blank search matches everything',
      );
    });
  });

  group('time and money wording', () {
    test('human times', () {
      expect(
        OpsTime.human(now.subtract(const Duration(seconds: 20)), now: now),
        'Just now',
      );
      expect(
        OpsTime.human(now.subtract(const Duration(minutes: 12)), now: now),
        '12 minutes ago',
      );
      expect(
        OpsTime.human(now.subtract(const Duration(hours: 3)), now: now),
        'Today 7:30 AM',
      );
      expect(
        OpsTime.human(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday 10:30 AM',
      );
      expect(
        OpsTime.human(DateTime(2026, 9, 1, 15, 5), now: now),
        '1 Sep, 3:05 PM',
      );
      expect(OpsTime.human(DateTime(2025, 12, 25), now: now), '25 Dec 2025');
      expect(OpsTime.human(null, now: now), 'Time not recorded');
    });

    test('rupees from paise, Indian grouping', () {
      expect(OpsLanguage.rupees(499900), '₹4,999');
      expect(OpsLanguage.rupees(12345600), '₹1,23,456');
      // Paise-exact: a ₹0.50 refund is not "₹1" (REF-12 / ORG-15).
      expect(OpsLanguage.rupees(50), '₹0.50');
      expect(OpsLanguage.rupees(117882), '₹1,178.82');
      expect(OpsLanguage.rupees(null), '');
    });
  });

  test('feed-unavailable rows are actionable and never informational', () {
    final row = OpsLanguage.feedUnavailable(
      key: 'k',
      feedName: 'Organization',
      hides: 'Approvals',
      primary: const OpsAction.retry(),
    );
    expect(row.status, OpsItemStatus.needsAttention);
    expect(row.title, "Organization information couldn't be loaded");
    expect(row.why, contains('Nothing here is wrong with the platform itself'));
  });
}
