// THE DASHBOARD'S BEHAVIOURS THAT A RENDER-ONLY TEST CANNOT SEE.
//
// Each group here corresponds to a defect found on the emulator run of
// 2026-09-05 or to a door the audit added. The controllers are the REAL
// classes with `onInit` suppressed, so what is exercised is the production
// screen bound to production state — only the network is missing.
//
//   HEADCOUNTS  a failed `clients` aggregate used to print "0 Members" as a
//               measured fact because one shared flag flipped on EITHER
//               collection succeeding.
//   DOORS       KPI cards and legend entries navigate, and carry the filter.
//   DISCLOSURE  past-due expiries, refunds, unverified captures, undated
//               receipts and unknown organizations are named, not smoothed.
//   STRIP       loading ≠ all clear ≠ alerts.

import 'dart:async';

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/controllers/communication_controller.dart';
import 'package:alphaserena_admin_portel/controllers/dashboard_controller.dart';
import 'package:alphaserena_admin_portel/controllers/operations_controller.dart';
import 'package:alphaserena_admin_portel/controllers/support_controller.dart';
import 'package:alphaserena_admin_portel/core/services/dashboard_metrics.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:alphaserena_admin_portel/screens/dash_board_responsive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class OfflineDash extends DashboardController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class OfflineOps extends OperationsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class RecordingRoot extends AdminRootController {
  final List<int> opened = [];
  @override
  // ignore: must_call_super
  void onInit() {}
  @override
  void changePage(int index) => opened.add(index);
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

late OfflineDash dash;
late RecordingRoot root;
late OfflineAdmins admins;
late OfflineOps ops;

void _mount({bool withSources = true}) {
  ops = Get.put<OperationsController>(OfflineOps(), permanent: true) as OfflineOps;
  root = Get.put<AdminRootController>(RecordingRoot(), permanent: true) as RecordingRoot;
  if (withSources) {
    admins = Get.put<AdminController>(OfflineAdmins(), permanent: true) as OfflineAdmins;
    Get.put<SupportController>(OfflineSupport(), permanent: true);
    Get.put<CommunicationController>(OfflineComms(), permanent: true);
  }
  dash = Get.put<DashboardController>(OfflineDash(), permanent: true) as OfflineDash;
}

final _now = DateTime.now();

AdminModel _org(String id,
        {String status = 'active',
        bool subscribed = false,
        DateTime? expiry,
        String? plan}) =>
    AdminModel.fromMap({
      'name': '$id owner',
      'organizationName': id,
      'email': '$id@x.test',
      'status': status,
      'isSubscriptionActive': subscribed,
      if (plan != null) 'planName': plan,
      if (expiry != null) 'planExpiry': expiry.toIso8601String(),
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
    }, id);

void _orgsLoaded(List<AdminModel> list) {
  dash.orgStats.value = OrgStats.compute(list, now: _now);
  dash.orgsLoaded.value = true;
  dash.orgsError.value = false;
}

void _revenueLoaded() {
  dash.revenueLoaded.value = true;
  dash.revenueError.value = false;
}

Future<void> _pump(WidgetTester tester, {Size size = const Size(1800, 2800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: DashboardScreenResponsive())),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 3));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  tearDown(Get.reset);

  group('HEADCOUNTS — each aggregate reports for itself', () {
    test('one collection failing does not make the other one "0"', () async {
      _mount();
      dash.liveCountOverride = (c) async => c == 'trainers' ? 6 : null;
      await dash.refreshHeadcounts();

      expect(dash.trainersReady, isTrue);
      expect(dash.trainersTotal.value, 6);
      expect(dash.clientsReady, isFalse, reason: 'a failed count is not 0');
      expect(dash.clientsError.value, isTrue);
      expect(dash.headcountsAt.value, isNotNull,
          reason: 'one success is still a measurement time');
    });

    test('a later success clears the error and keeps the new number', () async {
      _mount();
      dash.liveCountOverride = (c) async => null;
      await dash.refreshHeadcounts();
      expect(dash.trainersReady, isFalse);
      expect(dash.headcountsAt.value, isNull, reason: 'nothing was measured');

      dash.liveCountOverride = (c) async => 3;
      await dash.refreshHeadcounts();
      expect(dash.trainersReady, isTrue);
      expect(dash.clientsReady, isTrue);
      expect(dash.clientsTotal.value, 3);
    });

    test('concurrent refreshes coalesce into one pass', () async {
      _mount();
      var calls = 0;
      dash.liveCountOverride = (c) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 1;
      };
      await Future.wait([dash.refreshHeadcounts(), dash.refreshHeadcounts()]);
      expect(calls, 2, reason: 'two collections, one pass — not four');
    });

    testWidgets('the failed card shows a dash and a retry hint; the good one a number',
        (tester) async {
      _mount();
      dash.liveCountOverride = (c) async => c == 'trainers' ? 6 : null;
      await dash.refreshHeadcounts();
      _orgsLoaded([]);
      _revenueLoaded();
      await _pump(tester);

      expect(find.text('6'), findsOneWidget);
      expect(find.text("Couldn't load · tap to retry"), findsOneWidget);
      // The Members card renders the dash, not a zero.
      final membersCard = find.ancestor(
          of: find.text('Members'), matching: find.byType(InkWell));
      expect(find.descendant(of: membersCard, matching: find.text('—')),
          findsOneWidget);
      expect(find.descendant(of: membersCard, matching: find.text('0')),
          findsNothing);
    });

    testWidgets('tapping the failed card retries instead of navigating',
        (tester) async {
      _mount();
      var calls = 0;
      dash.liveCountOverride = (c) async {
        calls++;
        return null;
      };
      await dash.refreshHeadcounts();
      _orgsLoaded([]);
      _revenueLoaded();
      await _pump(tester);
      calls = 0;

      await tester.tap(find.text("Couldn't load · tap to retry").first);
      await _settle(tester);
      expect(calls, 2, reason: 'a retry re-runs both aggregates');
      expect(root.opened, isEmpty, reason: 'a retry is not a navigation');
    });
  });

  group('DOORS — every number opens the screen that owns it', () {
    testWidgets('KPI cards navigate to their sections', (tester) async {
      _mount();
      _orgsLoaded([_org('a')]);
      _revenueLoaded();
      dash.liveCountOverride = (c) async => 2;
      await dash.refreshHeadcounts();
      await _pump(tester);

      await tester.tap(find.text('Trainers'));
      await tester.tap(find.text('Members'));
      await tester.tap(find.text('Total revenue'));
      await tester.tap(find.text('Organizations').first);
      expect(root.opened, [2, 3, 5, 1]);
    });

    testWidgets('a pending legend entry pre-filters Organizations to pending',
        (tester) async {
      _mount();
      _orgsLoaded([_org('a'), _org('b', status: 'pending')]);
      _revenueLoaded();
      await _pump(tester);

      await tester.tap(find.bySemanticsLabel(
          RegExp(r'^Pending 1\. Opens Organizations filtered to Pending')));
      expect(root.opened, [1]);
      expect(admins.statusFilter.value, 'pending');
    });

    testWidgets('the attention strip opens the Operations Center',
        (tester) async {
      _mount();
      ops.paymentAlerts.add({'id': 'pa1', 'kind': 'charged_not_activated', 'status': 'open'});
      ops.telemetryLoaded.value = true;
      _orgsLoaded([]);
      _revenueLoaded();
      await _pump(tester);

      // One alert reads "needs", several read "need" — match the tail.
      await tester.tap(find.textContaining('your attention'));
      expect(root.opened, [10]);
    });

    testWidgets('"View all N" appears only when the list is capped',
        (tester) async {
      _mount();
      _orgsLoaded([
        for (int i = 0; i < 7; i++) _org('p$i', status: 'pending'),
      ]);
      _revenueLoaded();
      await _pump(tester);

      expect(find.text('View all 7'), findsOneWidget);
      // Only five rows are rendered.
      expect(find.text('Approve'), findsNWidgets(5));

      await tester.tap(find.text('View all 7'));
      expect(root.opened, [1]);
      expect(admins.statusFilter.value, 'pending');
    });

    testWidgets('CONTROL — a short list has no View-all', (tester) async {
      _mount();
      _orgsLoaded([_org('p', status: 'pending')]);
      _revenueLoaded();
      await _pump(tester);
      expect(find.textContaining('View all'), findsNothing);
    });
  });

  group('DISCLOSURE — names what the smoothed version hid', () {
    testWidgets('an unmodelled status appears as "Other" and the slices reach the total',
        (tester) async {
      _mount();
      _orgsLoaded([_org('a'), _org('s', status: 'suspended')]);
      _revenueLoaded();
      await _pump(tester);

      expect(find.text('Other  '), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp(
              r'^2 organizations: 1 active, 0 pending, 0 warning, 0 blocked, 1 other')),
          findsOneWidget);
    });

    testWidgets('an expired-but-still-active plan is "expired", not "today"',
        (tester) async {
      _mount();
      _orgsLoaded([
        _org('stale', subscribed: true,
            expiry: _now.subtract(const Duration(hours: 2)), plan: 'Growth'),
        // Later today on the CALENDAR (not "+3h", which crosses midnight in
        // an evening test run and legitimately becomes "1d").
        _org('soon', subscribed: true,
            expiry: DateTime(_now.year, _now.month, _now.day, 23, 59, 59),
            plan: 'Growth'),
      ]);
      _revenueLoaded();
      await _pump(tester);

      expect(find.text('expired'), findsOneWidget);
      expect(find.text('today'), findsOneWidget);
      expect(find.textContaining('still marked active'), findsOneWidget);
    });

    testWidgets('recent payments name the organization and disclose refunds, '
        'unverified captures and missing dates', (tester) async {
      _mount();
      _orgsLoaded([]);
      _revenueLoaded();
      dash.recentPayments.value = [
        const PaymentEntry(
            orgId: 'a', orgName: 'Iron Temple', gross: 4999, net: 4999,
            date: null, plan: 'Growth', captureVerified: true),
        PaymentEntry(
            orgId: 'b', orgName: 'Pulse', gross: 9999, net: 5999,
            date: DateTime(2026, 8, 1, 10), plan: 'Scale', captureVerified: true),
        PaymentEntry(
            orgId: 'c', orgName: 'Zen', gross: 2999, net: 0,
            date: DateTime(2026, 8, 2, 10), plan: 'Growth', captureVerified: true),
        PaymentEntry(
            orgId: 'd', orgName: '', gross: 1999, net: 1999,
            date: DateTime(2026, 8, 3, 10), plan: 'Growth', captureVerified: false),
      ];
      await _pump(tester);

      expect(find.text('Iron Temple · Growth'), findsOneWidget);
      expect(find.text('date not recorded'), findsOneWidget);
      expect(find.textContaining('refunded ₹4,000'), findsOneWidget);
      expect(find.textContaining('fully refunded'), findsOneWidget);
      expect(find.textContaining('capture unverified'), findsOneWidget);
      expect(find.text('Unknown organization · Growth'), findsOneWidget);
    });

    testWidgets('a top organization with no admins doc is "Unknown organization", '
        'not a gym called "Organization"', (tester) async {
      _mount();
      _orgsLoaded([]);
      _revenueLoaded();
      dash.topOrgs.value = [
        const TopOrg('x', 'Unknown organization', 4999, isUnknown: true),
      ];
      await _pump(tester);
      expect(find.text('Unknown organization'), findsOneWidget);
      expect(find.text('Organization'), findsNothing);
    });

    testWidgets('undated receipts are disclosed on the total-revenue card',
        (tester) async {
      _mount();
      _orgsLoaded([]);
      _revenueLoaded();
      dash.paymentsUndated.value = 2;
      await _pump(tester);
      expect(find.textContaining('2 undated'), findsOneWidget);
    });

    testWidgets('paid-but-not-operable organizations are noted on the subscriptions card',
        (tester) async {
      _mount();
      _orgsLoaded([
        _org('a', subscribed: true),
        _org('b', status: 'blocked', subscribed: true),
        _org('c', status: 'pending', subscribed: true),
      ]);
      _revenueLoaded();
      await _pump(tester);
      expect(find.text('2 paid but pending/blocked'), findsOneWidget);
    });
  });

  group('STRIP — three states that must not look alike', () {
    testWidgets('sources still loading → nothing is claimed', (tester) async {
      _mount(); // telemetryLoaded defaults false
      _orgsLoaded([]);
      _revenueLoaded();
      await _pump(tester);
      expect(find.textContaining('All clear — nothing needs'), findsNothing);
      expect(find.textContaining('need your attention'), findsNothing);
    });

    testWidgets('loaded and empty → a positive all-clear', (tester) async {
      _mount();
      ops.telemetryLoaded.value = true;
      _orgsLoaded([]);
      _revenueLoaded();
      await _pump(tester);
      expect(find.textContaining('All clear — nothing needs'), findsOneWidget);
    });

    testWidgets('a missing source controller is never "all clear"', (tester) async {
      _mount(withSources: false);
      ops.telemetryLoaded.value = true;
      _orgsLoaded([]);
      _revenueLoaded();
      await _pump(tester);
      expect(find.textContaining('All clear — nothing needs'), findsNothing);
    });

    testWidgets('alerts → count wording says "alerts", critical count shown',
        (tester) async {
      _mount();
      ops.telemetryLoaded.value = true;
      // One critical payment alert + one organization over its limits.
      ops.paymentAlerts.add({'id': 'pa1', 'kind': 'charged_not_activated', 'status': 'open'});
      ops.quotaAlerts.add({'id': 'org-x', 'adminUid': 'org-x', 'violations': []});
      _orgsLoaded([]);
      _revenueLoaded();
      await _pump(tester);
      expect(find.text('2 alerts need your attention — 1 critical'),
          findsOneWidget);
    });
  });

  group('MODERATION — a row in flight is neither dead nor double-clickable', () {
    testWidgets('while approving, that row shows progress and every button locks',
        (tester) async {
      _mount();
      _orgsLoaded([
        _org('a', status: 'pending'),
        _org('b', status: 'pending'),
      ]);
      _revenueLoaded();
      await _pump(tester);

      dash.moderatingDocId.value = 'a';
      await tester.pump();

      // Row a: spinner instead of buttons. Row b: buttons present, disabled.
      expect(find.text('Approve'), findsOneWidget);
      final b = tester.widget<TextButton>(find.ancestor(
          of: find.text('Approve'), matching: find.byType(TextButton)));
      expect(b.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('a second tap during a call does not fire a second callable',
        (tester) async {
      _mount();
      var calls = 0;
      // A Completer, not a real delay: testWidgets runs under FakeAsync, so
      // an un-pumped Future.delayed never completes and the test hangs.
      final gate = Completer<void>();
      dash.moderationCall = (uid, status, {reason, expectedStatus}) async {
        calls++;
        await gate.future;
      };
      _orgsLoaded([_org('a', status: 'pending')]);
      _revenueLoaded();
      await _pump(tester);

      final f1 = dash.approveOrg('a');
      final f2 = dash.approveOrg('a');
      expect(dash.moderatingDocId.value, 'a');
      gate.complete();
      await Future.wait([f1, f2]);
      await _settle(tester); // let the success snackbar animate out
      expect(calls, 1);
      expect(dash.moderatingDocId.value, isNull);
    });
  });
}
