// MOD-1 / ORG-4 / ORG-5 / ORG-9 / ORG-10 / ORG-11 / ORG-12 / ORG-13 /
// ORG-17 / ORG-19 / ORPH-1 / ORPH-2 / C3 / C7 — THE ORGANIZATION'S HEALTH,
// TOLD HONESTLY, AND THE REMEDIES THAT ACTUALLY EXIST.
//
// 🔴 MOD-1: after a failed block leg (org_auth_enforcement_failed) the console
// told the founder to "Re-apply the same status from Organizations" — a call
// the console refuses on purpose ("Already blocked. Nothing was sent"). The
// blocked owner kept a working login. Now an explicit "Re-apply status
// effects" calls `reapplyAdminStatusEffects` from the workspace issue and the
// Operations Center row, and an undeployed backend is said to be one.

import 'dart:io';

import 'package:alphaserena_admin_portel/controllers/access_request_controller.dart';
import 'package:alphaserena_admin_portel/controllers/operations_controller.dart';
import 'package:alphaserena_admin_portel/core/services/action_outcomes.dart';
import 'package:alphaserena_admin_portel/core/services/org_moderation_service.dart';
import 'package:alphaserena_admin_portel/core/services/organization_language.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/audit_log_model.dart';
import 'package:alphaserena_admin_portel/models/ops_incident_model.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'organization_workspace_behaviour_test.dart' as w;
import 'organizations_screen_behaviour_test.dart' as list;

final now = list.now;

FirebaseFunctionsException ffe(String code, {Object? details}) =>
    FirebaseFunctionsException(code: code, message: code, details: details);

AdminModel org({
  String status = 'active',
  bool subActive = true,
  DateTime? expiry,
  Map<String, dynamic>? subscription,
  List<String> malformed = const [],
  List<String>? features,
  Map<String, dynamic>? metadata,
}) => AdminModel(
  docId: 'ok',
  uid: 'ok',
  name: 'Arjun Rao',
  email: 'arjun@iron.in',
  phone: '',
  organizationName: 'Iron Temple',
  role: 'admin',
  status: status,
  isSubscriptionActive: subActive,
  planName: 'Growth',
  planExpiry: expiry,
  subscription: subscription,
  subscriptionLimits: AdminSubscriptionLimits.empty(),
  createdAt: now.subtract(const Duration(days: 100)),
  updatedAt: now,
  malformedFields: malformed,
  features: features,
  metadata: metadata,
);

List<String> codes(AdminModel a) =>
    OrganizationLanguage.recordIssues(a, now: now).map((i) => i.code).toList();

OpsIncidentModel incident(
  String type, {
  String status = 'open',
  Map<String, String> context = const {},
  String correlationId = '',
}) => OpsIncidentModel(
  id: 'i-$type',
  type: type,
  severity: 'P1',
  fn: 'f',
  correlationId: correlationId,
  summary: '',
  action: '',
  context: context,
  status: status,
  occurrences: 1,
  firstSeenAt: now,
  lastSeenAt: now,
);

void main() {
  tearDown(Get.reset);

  group('MOD-1 — "Re-apply status effects" is a real action', () {
    test('a failed cascade / auth leg OFFERS it; an audit-only incident does '
        'not; acknowledged incidents still count (ORG-11)', () {
      final i = OrganizationLanguage.incidentIssues([
        {'type': 'org_auth_enforcement_failed', 'status': 'acknowledged'},
      ]).single;
      expect(i.offers, OrgAction.reapplyEffects);
      expect(i.why, contains('marked in progress'));
      expect(i.whatToDo, contains('never changes the status'));
      final audit = OrganizationLanguage.incidentIssues([
        {'type': 'admin_status_audit_failed', 'status': 'open'},
      ]).single;
      expect(audit.offers, isNull);
      expect(
        OrganizationLanguage.incidentIssues([
          {'type': 'org_cascade_failed', 'status': 'resolved'},
        ]),
        isEmpty,
      );
    });

    test('no copy anywhere prescribes the impossible "re-apply the same '
        'status"', () {
      for (final f in [
        'lib/core/services/ops_language.dart',
        'lib/core/services/organization_language.dart',
        'lib/core/services/trainer_language.dart',
      ]) {
        final src = File(f).readAsStringSync();
        expect(src.contains('Re-apply the same status'), isFalse, reason: f);
        expect(src.contains('same status here re-runs'), isFalse, reason: f);
        expect(
          src.contains("Re-applying the organization\\'s status"),
          isFalse,
        );
      }
    });

    testWidgets('the workspace issue calls reapplyAdminStatusEffects and '
        'reports the legs', (tester) async {
      final calls = <String>[];
      await w.open(
        tester,
        seed: (d) {
          w.seedHealthy(d, w.a_);
          d.incidents.succeed([
            {
              'id': 'i1',
              'type': 'org_auth_enforcement_failed',
              'status': 'open',
            },
          ]);
        },
      );
      w.ctrl.reapplyCall = (uid) async {
        calls.add(uid);
        return const ReapplyResult(status: 'active', cascade: 'ok', auth: 'ok');
      };
      final button = find.widgetWithText(
        OutlinedButton,
        'Re-apply status effects',
      );
      expect(button, findsOneWidget);
      await tester.tap(button);
      await list.settle(tester);
      expect(
        w.inDialog(find.textContaining('does NOT change')),
        findsOneWidget,
      );
      await tester.tap(w.inDialog(find.text('Re-apply')));
      await list.settle(tester);
      expect(calls, ['ok']);
      expect(find.text('Status effects re-applied'), findsOneWidget);
    });

    testWidgets('an undeployed callable is "not available on this backend '
        'yet"; a web CORS-404 (internal) says it may be', (tester) async {
      list.mount(
        rows: [list.org(id: 'ok', status: 'blocked', subActive: false)],
      );
      await list.pump(tester);
      list.ctrl.reapplyCall = (_) async => throw ffe('not-found');
      await list.ctrl.reapplyStatusEffects(list.ctrl.byId('ok')!);
      await list.settle(tester);
      expect(find.text('Not available on this backend yet'), findsOneWidget);
      expect(find.text('Nothing was changed.'), findsOneWidget);
      list.ctrl.reapplyCall = (_) async => throw ffe('internal');
      await list.ctrl.reapplyStatusEffects(list.ctrl.byId('ok')!);
      await list.settle(tester);
      expect(find.text('Re-apply outcome unknown'), findsOneWidget);
      expect(
        find.textContaining('may not be available on this backend yet'),
        findsOneWidget,
      );
    });

    test(
      'a partial success names the failed leg and keeps the incident open',
      () {
        final v = ActionOutcomes.reapplySucceeded(
          const ReapplyResult(status: 'blocked', cascade: 'ok', auth: 'failed'),
          name: 'Iron Temple',
        );
        expect(v.ok, isFalse);
        expect(v.title, 'Re-apply did not fully succeed');
        expect(v.message, contains('owner sign-in enforcement FAILED'));
        expect(
          ReapplyResult.fromMap({
            'ok': true,
            'status': 'blocked',
            'legs': {'cascade': 'ok', 'auth': 'skipped'},
          }).auth,
          'skipped',
        );
      },
    );

    test('the Operations Center row carries the action and the org id', () {
      final item = OpsLanguage.fromIncident(
        incident('org_cascade_failed', context: const {'adminUid': 'ok'}),
        orgName: (_) => 'Iron Temple',
      );
      expect(item.orgId, 'ok');
      expect(
        item.secondary.map((a) => a.kind),
        contains(OpsActionKind.reapplyEffects),
      );
      expect(item.why, contains('Re-apply status effects'));
      final byCorrelation = OpsLanguage.fromIncident(
        incident('org_auth_enforcement_failed', correlationId: 'ok'),
        orgName: (_) => null,
      );
      expect(byCorrelation.orgId, 'ok');
      final resolved = OpsLanguage.fromIncident(
        incident(
          'org_cascade_failed',
          status: 'resolved',
          context: const {'adminUid': 'ok'},
        ),
        orgName: (_) => null,
      );
      expect(
        resolved.secondary.map((a) => a.kind),
        isNot(contains(OpsActionKind.reapplyEffects)),
      );
      expect(const OpsAction.reapplyEffects().isWrite, isTrue);
    });

    test(
      'OperationsController.reapplyEffects returns the shared words',
      () async {
        final c = OperationsController();
        c.reapplyCall = (_) async => throw ffe('unimplemented');
        final item = OpsLanguage.fromIncident(
          incident('org_cascade_failed', context: const {'adminUid': 'ok'}),
          orgName: (_) => 'Iron Temple',
        );
        final r = await c.reapplyEffects(item);
        expect(r.ok, isFalse);
        expect(r.title, 'Not available on this backend yet');
        expect(c.busyId.value, isNull);
        c.reapplyCall = (_) async =>
            const ReapplyResult(status: 'blocked', cascade: 'ok', auth: 'ok');
        final ok = await c.reapplyEffects(item);
        expect(ok.ok, isTrue);
        expect(ok.title, 'Status effects re-applied');
      },
    );
  });

  group('Operations Center words for the new kinds and types (C3, C7)', () {
    test(
      'every new payment alert kind and incident type reads as a sentence',
      () {
        for (final kind in [
          'refund_at_gateway',
          'refund_failed',
          'refund_outcome_unknown',
          'refund_unmatched',
          'refund_before_settlement',
        ]) {
          final item = OpsLanguage.fromPaymentAlert({
            'id': 'a',
            'kind': kind,
            'status': 'open',
            'amountMinor': 117882,
          }, orgName: (_) => null);
          expect(item.title, isNot('A payment needs review'), reason: kind);
          expect(item.title.contains('_'), isFalse, reason: kind);
          expect(item.affected, contains('₹1,178.82'), reason: kind);
        }
        expect(
          OpsLanguage.fromPaymentAlert({
            'id': 'a',
            'kind': 'refund_outcome_unknown',
            'status': 'open',
            'requestedMinor': 50000,
            'intentId': 'rf_1',
          }, orgName: (_) => null).urgency,
          OpsUrgency.critical,
        );
        for (final type in [
          'provision_rollback_failed',
          'provision_commit_unconfirmed',
          'grant_commit_unconfirmed',
        ]) {
          final item = OpsLanguage.fromIncident(
            incident(type),
            orgName: (_) => null,
          );
          expect(
            item.title,
            isNot('The system flagged a problem'),
            reason: type,
          );
          expect(item.title.contains('_'), isFalse, reason: type);
        }
      },
    );

    test('a dispute on an ORGANIZATION payment is worded for it; phases read '
        'differently', () {
      final opened = OpsLanguage.fromPaymentAlert({
        'id': 'd',
        'kind': 'dispute',
        'status': 'open',
        'adminUid': 'ok',
        'disputeId': 'disp_1',
        'phase': 'opened',
      }, orgName: (_) => 'Iron Temple');
      expect(opened.title, 'A payment is being disputed (chargeback)');
      expect(opened.why, contains("organization's bank"));
      expect(opened.why, contains('subscription payment'));
      expect(opened.urgency, OpsUrgency.critical);
      final lost = OpsLanguage.fromPaymentAlert({
        'id': 'd2',
        'kind': 'dispute',
        'status': 'open',
        'adminUid': 'ok',
        'phase': 'lost',
      }, orgName: (_) => 'Iron Temple');
      expect(lost.title, contains('lost'));
      expect(lost.why, contains('access was NOT changed'));
      final won = OpsLanguage.fromPaymentAlert({
        'id': 'd3',
        'kind': 'dispute',
        'status': 'open',
        'phase': 'won',
      }, orgName: (_) => null);
      expect(won.status, OpsItemStatus.informational);
      final member = OpsLanguage.fromPaymentAlert({
        'id': 'd4',
        'kind': 'dispute',
        'status': 'open',
        'settlementId': 's1',
      }, orgName: (_) => null);
      expect(member.why, isNot(contains("organization's bank")));
    });
  });

  group('ORG-11 — the organization Health reads payment alerts', () {
    test('unresolved alerts naming the org are an issue; resolved are not', () {
      final issues = OrganizationLanguage.paymentAlertIssues([
        {'kind': 'refund_outcome_unknown', 'status': 'open', 'adminUid': 'ok'},
        {'type': 'refund_inconsistent', 'status': 'open', 'adminUid': 'ok'},
        {'kind': 'refund_at_gateway', 'status': 'resolved', 'adminUid': 'ok'},
      ]);
      final i = issues.single;
      expect(i.severity, OrgIssueSeverity.critical);
      expect(i.title, startsWith('2 payment alerts'));
      expect(i.why, contains('A refund may or may not have gone through'));
      expect(i.whatToDo, contains('Razorpay dashboard'));
      expect(OrganizationLanguage.paymentAlertIssues(const []), isEmpty);
    });

    testWidgets('the workspace Health shows them', (tester) async {
      await w.open(
        tester,
        seed: (d) {
          w.seedHealthy(d, w.a_);
          d.paymentAlerts.succeed([
            {
              'id': 'p1',
              'kind': 'refund_failed',
              'status': 'open',
              'adminUid': 'ok',
            },
          ]);
        },
      );
      expect(
        find.textContaining('1 payment alert on this organization'),
        findsOneWidget,
      );
      expect(find.text('Everything looks good'), findsNothing);
    });
  });

  group('ORPH-1 / ORPH-2 — subscription states the backend never repairs', () {
    test('switched off while paid-through: its own state, never "no '
        'subscription", and a payment is not offered as the fix', () {
      final a = org(
        subActive: false,
        expiry: now.add(const Duration(days: 40)),
      );
      final sub = OrganizationLanguage.subscriptionOf(a, now: now);
      expect(sub.state, SubscriptionState.offBeforeEnd);
      expect(sub.isActiveFlag, isFalse);
      expect(codes(a), contains('switched_off_while_paid'));
      expect(codes(a), isNot(contains('approved_no_subscription')));
      final issue = OrganizationLanguage.recordIssues(
        a,
        now: now,
      ).firstWhere((i) => i.code == 'switched_off_while_paid');
      expect(issue.offers, isNull);
      expect(issue.severity, OrgIssueSeverity.critical);
      expect(issue.whatToDo, contains('Do not record a new payment'));
      expect(OrganizationLanguage.primaryAction(a, now: now), isNull);
      // Past the end date with the flag off is the ordinary lapsed case.
      final lapsed = org(
        subActive: false,
        expiry: now.subtract(const Duration(days: 2)),
      );
      expect(codes(lapsed), contains('approved_no_subscription'));
      expect(
        OrganizationLanguage.primaryAction(lapsed, now: now),
        OrgAction.grant,
      );
      // Blocked: the block is the headline; the flag fact is information.
      final blocked = org(
        status: 'blocked',
        subActive: false,
        expiry: now.add(const Duration(days: 40)),
      );
      expect(
        OrganizationLanguage.recordIssues(
          blocked,
          now: now,
        ).firstWhere((i) => i.code == 'switched_off_while_paid').severity,
        OrgIssueSeverity.info,
      );
    });

    test('active with no READABLE plan end date is critical — the last '
        "payment's date is never a substitute", () {
      final missing = org(
        subActive: true,
        expiry: null,
        subscription: {
          'expiry': now.add(const Duration(days: 30)).toIso8601String(),
        },
      );
      final sub = OrganizationLanguage.subscriptionOf(missing, now: now);
      expect(sub.state, SubscriptionState.activeNoEndDate);
      expect(sub.lastPaymentEndsAt, isNotNull);
      final i = OrganizationLanguage.recordIssues(
        missing,
        now: now,
      ).firstWhere((i) => i.code == 'active_no_end_date');
      expect(i.severity, OrgIssueSeverity.critical);
      expect(i.why, contains('last payment says'));
      expect(i.why, contains('Nothing will ever expire'));
      final garbled = org(
        subActive: true,
        expiry: null,
        malformed: ['planExpiry'],
      );
      expect(
        OrganizationLanguage.recordIssues(
          garbled,
          now: now,
        ).firstWhere((i) => i.code == 'active_no_end_date').title,
        contains('unreadable end date'),
      );
      expect(
        OrganizationLanguage.recordIssues(garbled, now: now).map((i) => i.code),
        isNot(contains('malformed_fields')),
        reason: 'the end date has its own, sharper issue',
      );
    });
  });

  group('ORG-4 / ORG-9 — owner-editable fields are never platform facts', () {
    test('the feature whitelist is the TOP-LEVEL field, tri-state', () {
      expect(
        OrganizationLanguage.featuresLine(org()),
        contains('legacy organization'),
      );
      expect(
        OrganizationLanguage.featuresLine(org(features: const [])),
        contains('None'),
      );
      expect(
        OrganizationLanguage.featuresLine(
          org(features: const ['advanced_reports']),
        ),
        'Allowed: advanced_reports',
      );
    });

    testWidgets('an owner-planted metadata.features is NOT shown as a '
        'capability; the real top-level list is', (tester) async {
      final a = AdminModel.fromMap({
        'organizationName': 'Iron Temple',
        'status': 'active',
        'isSubscriptionActive': true,
        'planExpiry': now.add(const Duration(days: 60)).toIso8601String(),
        'features': ['advanced_reports'],
        'metadata': {
          'features': ['fake_premium'],
        },
      }, 'ok');
      await w.open(tester, org: a, seed: (d) => w.seedHealthy(d, a));
      await w.tab(tester, 'Subscription');
      expect(find.text('advanced_reports'), findsOneWidget);
      expect(find.text('fake_premium'), findsNothing);
    });

    test('the workspace never reads metadata.features (source guard)', () {
      final src = File(
        'lib/screens/organization/organization_workspace.dart',
      ).readAsStringSync();
      expect(src.contains("metadata?['features']"), isFalse);
      expect(src.contains("subscription?['features']"), isFalse);
    });
  });

  group('ORG-5 — "Approved by" comes from the audit trail', () {
    AuditLogModel row(
      String action,
      String actor,
      int day, [
      Map<String, dynamic> d = const {},
    ]) => AuditLogModel(
      id: '$action-$day',
      actorUid: actor,
      action: action,
      targetId: 'ok',
      details: d,
      createdAt: DateTime(2026, 9, day),
    );

    test('a pending → active transition wins; a later block does not rename '
        'the approver', () {
      final ap = OrganizationLanguage.approvalFromAudit([
        row('set_admin_status', 'founderA', 1, {
          'from': 'pending',
          'to': 'active',
        }),
        row('set_admin_status', 'founderB', 5, {
          'from': 'active',
          'to': 'blocked',
        }),
      ])!;
      expect(ap.actorUid, 'founderA');
      expect(ap.how, 'approved from awaiting approval');
    });

    test('legacy rows ({status}) → the FIRST move to Approved; provisioning '
        'counts as created-approved', () {
      expect(
        OrganizationLanguage.approvalFromAudit([
          row('set_admin_status', 'late', 9, {'status': 'active'}),
          row('set_admin_status', 'first', 2, {'status': 'active'}),
        ])!.actorUid,
        'first',
      );
      expect(
        OrganizationLanguage.approvalFromAudit([
          row('provision_organization', 'maker', 3),
        ])!.how,
        contains('created already approved'),
      );
      expect(OrganizationLanguage.approvalFromAudit(const []), isNull);
    });

    test('set_admin_status rows read the new {from, to} shape', () {
      final e = OrganizationLanguage.fromAudit(
        row('set_admin_status', 'me', 1, {
          'from': 'active',
          'to': 'blocked',
          'reason': 'x',
        }),
        actorOf: (u) => u,
      )!;
      expect(e.title, 'Status changed to Blocked');
      expect(e.detail, contains('from Approved'));
    });

    testWidgets('the History tab names the approver from the audit, and labels '
        'the record field as the last status changer', (tester) async {
      final a = AdminModel(
        docId: 'ok',
        uid: 'ok',
        name: 'Arjun',
        email: 'a@b.in',
        phone: '',
        organizationName: 'Iron Temple',
        role: 'admin',
        status: 'blocked',
        approvedBy: 'blocker',
        isSubscriptionActive: false,
        subscriptionLimits: AdminSubscriptionLimits.empty(),
        createdAt: now,
        updatedAt: now,
      );
      await w.open(
        tester,
        org: a,
        seed: (d) {
          w.seedHealthy(d, a);
          d.audit.succeed([
            row('set_admin_status', 'me', 1, {
              'from': 'pending',
              'to': 'active',
            }),
            row('set_admin_status', 'blocker', 5, {
              'from': 'active',
              'to': 'blocked',
            }),
          ]);
        },
      );
      await w.tab(tester, 'History');
      expect(
        find.textContaining('you — approved from awaiting approval'),
        findsOneWidget,
      );
      expect(
        find.textContaining('names the last person to change the status'),
        findsOneWidget,
      );
    });
  });

  group(
    'provisioning (C5): a lost or half-done creation is not "not created"',
    () {
      test('internal / unavailable while creating are unclear, never "Nothing '
          'was changed"', () {
        for (final code in ['internal', 'unavailable', 'deadline-exceeded']) {
          final m = AccessRequestController.friendlyError(
            ffe(code),
            creating: true,
          );
          expect(
            m,
            contains('unclear whether the organization was created'),
            reason: code,
          );
          expect(m, isNot(contains('Nothing was changed')), reason: code);
        }
        expect(
          AccessRequestController.friendlyError(
            ffe('failed-precondition'),
            creating: true,
          ),
          contains('Nothing was changed'),
        );
      });

      test(
        'the screen titles only a definite refusal "Organization not created"',
        () {
          final src = File(
            'lib/screens/access_requests_screen.dart',
          ).readAsStringSync();
          expect(src.contains('ctrl.createFailureDefinite.value'), isTrue);
          expect(src.contains("'Creation outcome unknown'"), isTrue);
        },
      );
    },
  );

  group('ORG-10 / ORG-17 / ORG-19 / ORG-12 / ORG-13', () {
    test('no window claims "most recent" over an unordered read', () {
      final src = File(
        'lib/screens/organization/organization_workspace.dart',
      ).readAsStringSync();
      expect(src.contains('Showing the most recent'), isFalse);
      expect(src.contains('not ordered by date'), isTrue);
    });

    testWidgets('an outcome for organization A never lands in B\'s workspace, '
        'and B\'s feeds are not reloaded for it', (tester) async {
      list.mount(
        rows: [
          list.org(id: 'A', orgName: 'Alpha'),
          list.org(id: 'B', orgName: 'Bravo'),
        ],
      );
      await list.pump(tester);
      list.ctrl.openOrganization('A');
      await list.settle(tester);
      final a = list.ctrl.byId('A')!;
      list.ctrl.openOrganization('B');
      await list.settle(tester);
      final detailB = list.ctrl.detail!;
      var refreshed = 0;
      detailB.trainers.loading.listen((_) => refreshed++);
      await list.ctrl.warn(a, 'late');
      await list.settle(tester);
      expect(list.ctrl.lastOutcome.value!.orgId, 'A');
      expect(find.text('Warning recorded'), findsNothing, reason: 'not on B');
      expect(refreshed, 0);
    });

    test('the attention sort ranks each organization once (source guard) and '
        'the order is unchanged', () {
      final src = File(
        'lib/core/services/organization_language.dart',
      ).readAsStringSync();
      final sortBody = src.substring(src.indexOf("case 'attention':"));
      expect(sortBody.substring(0, 900).contains('rank[x]!'), isTrue);
      final rows = [
        list.org(id: 'clean', orgName: 'Clean'),
        list.org(
          id: 'exp',
          orgName: 'Exp',
          expiry: now.add(const Duration(days: 2)),
        ),
        list.org(
          id: 'past',
          orgName: 'Past',
          expiry: now.subtract(const Duration(days: 2)),
        ),
      ];
      expect(
        OrganizationLanguage.sorted(
          rows,
          'attention',
          now: now,
        ).map((a) => a.docId),
        ['past', 'exp', 'clean'],
      );
    });

    test('the Dashboard approve path never blames a colleague for its own '
        'lost call (ORG-12)', () {
      final v = ActionOutcomes.statusFailed(
        ffe('unavailable'),
        friendly: OrgModerationService.friendlyError,
      );
      expect(v.changed, isNull);
      expect(v.title, 'Status change outcome unknown');
      expect(v.message, contains(ActionOutcomes.cannotTell));
      final src = File(
        'lib/controllers/dashboard_controller.dart',
      ).readAsStringSync();
      expect(src.contains('ActionOutcomes.statusFailed('), isTrue);
    });

    test('clearing a warning says the owner gets the "approved" notification '
        '(ORG-13)', () {
      final plan = OrganizationLanguage.planFor(
        OrgAction.reactivate,
        org(status: 'warning', expiry: now.add(const Duration(days: 30))),
        now: now,
      );
      expect(plan.consequences.join(' '), contains('Organization approved'));
      expect(
        plan.consequences.join(' '),
        contains('never told about the warning'),
      );
    });

    test(
      'an unknown status-change outcome is not "Could not change the status"',
      () {
        final v = ActionOutcomes.statusFailed(
          ffe('internal'),
          friendly: OrgModerationService.friendlyError,
        );
        expect(v.title, isNot('Could not change the status'));
        final refused = ActionOutcomes.statusFailed(
          ffe('failed-precondition'),
          friendly: OrgModerationService.friendlyError,
        );
        expect(refused.title, 'Could not change the status');
        expect(refused.changed, isFalse);
      },
    );
  });
}
