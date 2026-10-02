// THE OPERATIONS CENTER, AS A NON-TECHNICAL OPERATOR MEETS IT.
//
// Real screen, real controllers with `onInit` suppressed, a fake write service.
// Scenarios mirror the redesign brief:
//   A  nothing is wrong           → one green sentence, no alarm anywhere
//   B  one payment needs review   → plain words, the right urgency, one action
//   C  an organization problem    → the organization is NAMED, action leads there
//   D  30 mixed events            → the three that matter are on top; the 20
//                                   failed-payment notes are Information
//   E  a dangerous action         → the dialog states target + consequence
//   F  an action fails            → the message says nothing was changed
// plus: partial feed failure, filters / filtered-empty, tabs, double-submit,
// technical details hidden by default, and a11y labels that name the action.

import 'dart:async';

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/controllers/communication_controller.dart';
import 'package:alphaserena_admin_portel/controllers/operations_controller.dart';
import 'package:alphaserena_admin_portel/controllers/support_controller.dart';
import 'package:alphaserena_admin_portel/core/services/ops_incident_service.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/models/ops_incident_model.dart';
import 'package:alphaserena_admin_portel/screens/operations_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class OfflineOps extends OperationsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class OfflineAdmins extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class OfflineSupport extends SupportController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class OfflineComms extends CommunicationController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class RecordingRoot extends AdminRootController {
  final opened = <int>[];
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  void changePage(int index) => opened.add(index);
}

/// A write service that records calls and can be told to fail or to hang.
class FakeService extends OpsIncidentService {
  final calls = <String>[];
  Object? failWith;
  Completer<void>? gate;

  Future<void> _go(String call) async {
    calls.add(call);
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> acknowledgeIncident(String id) => _go('ack:$id');
  @override
  Future<void> resolveIncident(String id, {required String note}) =>
      _go('resolve:$id:$note');
  @override
  Future<void> reopenIncident(String id) => _go('reopen:$id');
  @override
  Future<void> resolvePaymentAlert(String id, {required String note}) =>
      _go('resolvePayment:$id:$note');
}

late OfflineOps ops;
late OfflineAdmins admins;
late OfflineSupport support;
late OfflineComms comms;
late RecordingRoot root;
late FakeService service;

final now = DateTime.now();

void mount() {
  admins =
      Get.put<AdminController>(OfflineAdmins(), permanent: true)
          as OfflineAdmins;
  support =
      Get.put<SupportController>(OfflineSupport(), permanent: true)
          as OfflineSupport;
  comms =
      Get.put<CommunicationController>(OfflineComms(), permanent: true)
          as OfflineComms;
  root =
      Get.put<AdminRootController>(RecordingRoot(), permanent: true)
          as RecordingRoot;
  ops =
      Get.put<OperationsController>(OfflineOps(), permanent: true)
          as OfflineOps;
  service = FakeService();
  ops.service = service;
  // Every source finished loading, healthy and empty.
  admins.isLoading.value = false;
  support.feedbackLoading.value = false;
  support.reviewsLoading.value = false;
  comms.isLoading.value = false;
  ops.telemetryLoaded.value = true;
  ops.incidentsLoaded.value = true;
  ops.historyLoaded.value = true;
}

AdminModel org(String id, String name, {String status = 'active'}) =>
    AdminModel.fromMap({
      'organizationName': name,
      'name': 'owner',
      'status': status,
      'isSubscriptionActive': true,
      'createdAt': DateTime(2026, 8, 1).toIso8601String(),
    }, id);

OpsIncidentModel incident(
  String id,
  String type, {
  String severity = 'P1',
  String status = 'open',
  Map<String, String> ctx = const {},
}) => OpsIncidentModel(
  id: id,
  type: type,
  severity: severity,
  fn: 'fn',
  correlationId: 'ref_$id',
  summary: 'summary',
  action: 'guidance',
  context: ctx,
  status: status,
  occurrences: 1,
  firstSeenAt: now.subtract(const Duration(hours: 5)),
  lastSeenAt: now.subtract(const Duration(hours: 1)),
);

Future<void> pump(
  WidgetTester tester, {
  Size size = const Size(1500, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: OperationsScreen())),
  );
  await tester.pump();
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(Get.reset);
  _LiveCounts.register();

  group('A — nothing is wrong', () {
    testWidgets('one green sentence, no alarm words, zero counts', (
      tester,
    ) async {
      mount();
      await pump(tester);
      expect(find.text("You're all caught up"), findsWidgets);
      expect(find.textContaining('need your attention'), findsNothing);
      expect(
        find.textContaining('Critical'),
        findsOneWidget,
        reason: 'the count tile label only',
      );
      expect(
        find.text('All caught up'),
        findsOneWidget,
        reason: 'header badge',
      );
    });

    testWidgets('still loading is "Checking", never "caught up"', (
      tester,
    ) async {
      mount();
      ops.telemetryLoaded.value = false;
      await pump(tester);
      expect(find.textContaining('caught up'), findsNothing);
      expect(find.text('Checking the platform…'), findsOneWidget);
    });
  });

  group('B — one payment needs review', () {
    testWidgets('plain words, critical urgency, resolve + open revenue', (
      tester,
    ) async {
      mount();
      admins.admins.add(org('org-a', 'Iron Temple Gym'));
      ops.paymentAlerts.add({
        'id': 'pa1',
        'kind': 'charged_not_activated',
        'status': 'open',
        'adminUid': 'org-a',
        'amountPaise': 499900,
        'createdAt': now.subtract(const Duration(hours: 2)),
      });
      await pump(tester);

      expect(find.text('1 thing needs your attention'), findsOneWidget);
      expect(find.textContaining('1 is critical'), findsOneWidget);
      expect(
        find.text('A payment was received but nothing was activated'),
        findsOneWidget,
      );
      expect(find.textContaining('Iron Temple Gym · ₹4,999'), findsOneWidget);
      expect(
        find.text('charged_not_activated'),
        findsNothing,
        reason: 'the backend id is not on the primary surface',
      );
      expect(find.text('Mark resolved'), findsOneWidget);
      expect(find.text('Open Revenue'), findsOneWidget);

      // Technical details are hidden until asked for.
      expect(find.text('Alert kind'), findsNothing);
      await tester.tap(find.text('Technical details'));
      await settle(tester);
      expect(find.text('Alert kind'), findsOneWidget);
      expect(find.text('charged_not_activated'), findsOneWidget);
    });
  });

  group('C — an organization access problem', () {
    testWidgets('names the organization and the action opens Organizations', (
      tester,
    ) async {
      mount();
      admins.admins.add(org('org-b', 'Pulse Fitness', status: 'blocked'));
      ops.opsIncidents.add(
        incident(
          'i1',
          'org_auth_enforcement_failed',
          ctx: {'adminUid': 'org-b'},
        ),
      );
      await pump(tester);

      expect(
        find.textContaining("An owner's sign-in was not updated"),
        findsOneWidget,
      );
      expect(find.textContaining('Pulse Fitness'), findsWidgets);
      await tester.tap(find.text('Open Organizations').first);
      expect(root.opened, [1]);
    });
  });

  group('D — thirty mixed events', () {
    void seedThirty() {
      admins.admins.addAll([
        org('org-a', 'Iron Temple Gym'),
        org('org-b', 'Pulse Fitness'),
      ]);
      for (int i = 0; i < 20; i++) {
        ops.paymentAlerts.add({
          'id': 'pf$i',
          'kind': 'payment_failed',
          'status': 'open',
          'createdAt': now.subtract(Duration(minutes: i + 1)),
        });
      }
      ops.paymentAlerts.add({
        'id': 'crit',
        'kind': 'dispute',
        'status': 'open',
        'adminUid': 'org-b',
        'amountPaise': 999900,
        'respondBy': now.add(const Duration(days: 3)),
        'createdAt': now,
      });
      ops.opsIncidents.addAll([
        incident('i-high', 'org_cascade_failed', ctx: {'adminUid': 'org-a'}),
        incident('i-att', 'crash_escalating', severity: 'P2'),
        incident('i-prog', 'scheduled_job_warning', status: 'acknowledged'),
      ]);
      ops.resolvedIncidents.addAll([
        for (int i = 0; i < 4; i++)
          OpsIncidentModel(
            id: 'done$i',
            type: 'webhook_handler_error',
            severity: 'P0',
            fn: 'f',
            correlationId: 'c',
            summary: 's',
            action: 'a',
            context: const {},
            status: 'resolved',
            occurrences: 1,
            resolvedAt: now.subtract(Duration(days: i)),
            resolutionNote: 'Fixed $i',
          ),
      ]);
    }

    testWidgets(
      'the banner counts only what needs a human; noise is Information',
      (tester) async {
        mount();
        seedThirty();
        await pump(tester);

        // 1 dispute + 1 high + 1 attention + 1 in progress = 4 need a human.
        expect(find.text('4 things need your attention'), findsOneWidget);
        expect(find.textContaining('1 is critical'), findsOneWidget);
        // Tabs carry counts: 3 open, 1 in progress, 4 resolved, 20 information.
        expect(find.text('Needs attention · 3'), findsOneWidget);
        expect(find.text('In progress · 1'), findsOneWidget);
        expect(find.text('Resolved · 4'), findsOneWidget);
        expect(find.text('Information · 20'), findsOneWidget);
        // The attention list does NOT contain the 20 failed payments.
        expect(find.text('A payment attempt failed'), findsNothing);
        // The critical item is first.
        final titles = tester
            .widgetList<Text>(
              find.byWidgetPredicate(
                (w) =>
                    w is Text &&
                    (w.data == 'A payment is being disputed (chargeback)' ||
                        w.data ==
                            "Trainer access did not follow an organization's new status" ||
                        w.data == 'A known app crash is spreading'),
              ),
            )
            .map((t) => t.data)
            .toList();
        expect(titles.first, 'A payment is being disputed (chargeback)');
      },
    );

    testWidgets(
      'urgency tile filters; filtered-empty explains itself; clear works',
      (tester) async {
        mount();
        seedThirty();
        await pump(tester);

        await tester.tap(find.bySemanticsLabel(RegExp(r'^High: 1\.')));
        await settle(tester);
        expect(find.text('Urgency: High'), findsOneWidget);
        expect(
          find.text('A payment is being disputed (chargeback)'),
          findsNothing,
        );
        expect(
          find.textContaining("Trainer access did not follow"),
          findsOneWidget,
        );

        // Search for something that does not exist under this tab.
        ops.search.value = 'zebra';
        await settle(tester);
        expect(find.text('No items match these filters'), findsOneWidget);
        expect(
          find.textContaining('none match your search or urgency filter'),
          findsOneWidget,
        );

        await tester.tap(find.text('Clear filters').first);
        await settle(tester);
        expect(ops.hasActiveFilters, isFalse);
        expect(
          find.text('A payment is being disputed (chargeback)'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'the Resolved tab shows notes; the Information tab shows the noise',
      (tester) async {
        mount();
        seedThirty();
        await pump(tester);

        await tester.tap(find.text('Resolved · 4'));
        await settle(tester);
        expect(find.textContaining('Fixed 0'), findsOneWidget);
        expect(find.text('Reopen'), findsNWidgets(4));

        await tester.tap(find.text('Information · 20'));
        await settle(tester);
        expect(find.text('A payment attempt failed'), findsNWidgets(20));
        expect(find.text('Dismiss'), findsNWidgets(20));
      },
    );
  });

  group('E — a consequential action explains itself first', () {
    testWidgets(
      'Mark resolved opens a dialog naming the item and the consequence, '
      'requires a note, then reports where the item went',
      (tester) async {
        mount();
        admins.admins.add(org('org-a', 'Iron Temple Gym'));
        ops.opsIncidents.add(
          incident(
            'i1',
            'settlement_create_failed',
            severity: 'P0',
            ctx: {'adminUid': 'org-a'},
          ),
        );
        await pump(tester);

        await tester.tap(find.text('Mark resolved'));
        await settle(tester);
        expect(find.text('Mark as resolved?'), findsOneWidget);
        expect(
          find.text("A member's payment has no payout record"),
          findsWidgets,
        );
        expect(
          find.textContaining('does not fix the underlying problem by itself'),
          findsOneWidget,
        );

        // Empty note is refused.
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Mark resolved'),
          ),
        );
        await settle(tester);
        expect(
          find.text('Write one line about what was done.'),
          findsOneWidget,
        );
        expect(service.calls, isEmpty);

        await tester.enterText(
          find.byType(TextField).last,
          'Created the settlement by hand',
        );
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Mark resolved'),
          ),
        );
        await settle(tester);
        expect(service.calls, ['resolve:i1:Created the settlement by hand']);
        expect(
          find.textContaining('now appears under "Resolved"'),
          findsOneWidget,
        );
        // Let the success snackbar animate out before teardown.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets('Cancel changes nothing', (tester) async {
      mount();
      ops.opsIncidents.add(incident('i1', 'scheduled_job_warning'));
      await pump(tester);
      await tester.tap(find.text('Mark resolved'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(service.calls, isEmpty);
    });

    testWidgets('Reopen confirms and says where the item goes', (tester) async {
      mount();
      ops.resolvedIncidents.add(
        OpsIncidentModel(
          id: 'r1',
          type: 'scheduled_job_warning',
          severity: 'P1',
          fn: 'f',
          correlationId: 'c',
          summary: 's',
          action: 'a',
          context: const {},
          status: 'resolved',
          occurrences: 1,
          resolvedAt: now,
          resolutionNote: 'done',
        ),
      );
      await pump(tester);
      await tester.tap(find.text('Resolved · 1'));
      await settle(tester);
      await tester.tap(find.text('Reopen'));
      await settle(tester);
      expect(find.text('Reopen this item?'), findsOneWidget);
      expect(
        find.textContaining('will move back to "Needs attention"'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Reopen'),
        ),
      );
      await settle(tester);
      expect(service.calls, ['reopen:r1']);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('F — a failed action says whether anything changed', () {
    testWidgets('permission denied → nothing was changed, what to do', (
      tester,
    ) async {
      mount();
      ops.opsIncidents.add(incident('i1', 'scheduled_job_warning'));
      service.failWith = FirebaseException(
        plugin: 'firestore',
        code: 'permission-denied',
      );
      await pump(tester);

      final r = await ops.acknowledge(ops.attentionItems.single);
      expect(r.ok, isFalse);
      expect(r.message, contains('Nothing was changed'));
      expect(r.message, contains('permission'));
      expect(
        ops.busyId.value,
        isNull,
        reason: 'the lock is released on failure',
      );
    });

    test('every failure wording states that nothing changed', () {
      for (final code in [
        'permission-denied',
        'unauthenticated',
        'not-found',
        'unavailable',
        'weird',
      ]) {
        final msg = OperationsController.friendlyFailure(
          FirebaseException(plugin: 'firestore', code: code),
        );
        expect(msg, contains('Nothing was changed'), reason: code);
        expect(msg.toLowerCase(), isNot(contains('exception')), reason: code);
      }
    });

    testWidgets('a derived row has no record to write and says so', (
      tester,
    ) async {
      mount();
      admins.admins.add(org('p', 'New Gym', status: 'pending'));
      await pump(tester);
      final row = ops.attentionItems.single;
      expect(row.primary.kind, OpsActionKind.navigate);
      final r = await ops.resolve(row, note: 'x');
      expect(r.ok, isFalse);
      expect(r.message, contains('Nothing was changed'));
    });
  });

  group('duplicate protection', () {
    testWidgets(
      'while one write is in flight every other write button is disabled '
      'and a second call is refused',
      (tester) async {
        mount();
        ops.opsIncidents.addAll([
          incident('i1', 'scheduled_job_warning'),
          incident('i2', 'scheduled_job_warning'),
        ]);
        service.gate = Completer<void>();
        await pump(tester);

        final first = ops.acknowledge(ops.attentionItems[0]);
        await tester.pump();
        expect(ops.busyId.value, isNotNull);

        final second = await ops.acknowledge(ops.attentionItems[1]);
        expect(second.ok, isFalse);
        expect(second.message, contains('still in progress'));

        // The other row's buttons are disabled while locked.
        final buttons = tester.widgetList<FilledButton>(
          find.byType(FilledButton),
        );
        expect(buttons.every((b) => b.onPressed == null), isTrue);

        service.gate!.complete();
        final r = await first;
        await settle(tester);
        expect(r.ok, isTrue);
        expect(service.calls, ['ack:i1']);
      },
    );
  });

  group('partial failure', () {
    testWidgets('a failed feed is a named row AND the banner names it', (
      tester,
    ) async {
      mount();
      admins.loadError.value = const ConsoleError(
        kind: ConsoleErrorKind.permission,
        message: 'denied',
      );
      await pump(tester);
      expect(find.textContaining('caught up'), findsNothing);
      expect(
        find.text("Organization information couldn't be loaded"),
        findsOneWidget,
      );
      expect(
        find.textContaining("Organizations could not be loaded"),
        findsOneWidget,
      );
    });

    testWidgets('own feed failure offers Try again', (tester) async {
      mount();
      ops.telemetryError.value = true;
      await pump(tester);
      expect(
        find.text(
          "Payment and plan-limit alert information couldn't be loaded",
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsWidgets);
    });
  });

  group('accessibility', () {
    testWidgets(
      'action buttons announce the item they act on; urgency is a word',
      (tester) async {
        mount();
        ops.opsIncidents.add(
          incident('i1', 'crash_widespread', severity: 'P0'),
        );
        await pump(tester);
        expect(
          find.bySemanticsLabel(
            RegExp(r'^Mark resolved: Many users are crashing'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'^Critical\. Needs attention\. Many users'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('Critical'),
          findsWidgets,
          reason: 'the word, not just a colour',
        );
      },
    );
  });

  group('responsive', () {
    testWidgets('renders at phone width without overflow', (tester) async {
      mount();
      admins.admins.add(
        org('org-a', 'A Very Long Organization Name That Keeps Going On'),
      );
      ops.paymentAlerts.add({
        'id': 'p',
        'kind': 'dispute',
        'status': 'open',
        'adminUid': 'org-a',
      });
      ops.opsIncidents.add(
        incident('i1', 'settlement_create_failed', severity: 'P0'),
      );
      await pump(tester, size: const Size(390, 2400));
      expect(tester.takeException(), isNull);
      expect(find.text('Mark resolved'), findsNWidgets(2));
    });
  });
}

// Appended after the emulator run of 2026-09-06 exposed it: the tab chips were
// computed inside a nested Builder, which Obx does not track, so after an
// acknowledge the list moved the row but "Needs attention · 16 / In progress · 1"
// stayed frozen. Reactive reads must happen inside the Obx closure itself.
class _LiveCounts {
  static void register() {
    testWidgets('tab counts and the banner follow a status change live', (
      tester,
    ) async {
      mount();
      ops.opsIncidents.add(incident('i1', 'scheduled_job_warning'));
      await pump(tester);
      expect(find.text('Needs attention · 1'), findsOneWidget);
      expect(find.text('In progress · 0'), findsOneWidget);

      // The stream delivers the same row, now acknowledged.
      ops.opsIncidents.assignAll([
        incident('i1', 'scheduled_job_warning', status: 'acknowledged'),
      ]);
      await settle(tester);
      expect(find.text('Needs attention · 0'), findsOneWidget);
      expect(find.text('In progress · 1'), findsOneWidget);
      expect(find.text('1 thing needs your attention'), findsOneWidget);

      // Typing a search shows "Clear filters" without any other change.
      ops.search.value = 'anything';
      await settle(tester);
      expect(find.text('Clear filters'), findsWidgets);
    });
  }
}
