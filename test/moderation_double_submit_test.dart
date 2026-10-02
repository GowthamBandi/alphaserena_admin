// ONE HUMAN DECISION MUST PRODUCE ONE AUDIT ROW.
//
// 🔴 THE DEFECT THIS GUARDS. `AdminController._setStatus` set `isProcessing`
// but never checked it, and the Organizations screen never rendered it — so
// Approve / Warn / Block looked completely inert between the tap and the
// `setAdminStatus` round trip returning. A cold-started callable takes seconds.
// The founder taps again.
//
// `setAdminStatus` is NOT idempotent in its effects. Each call:
//   • writes an `audit_logs` row (`runAdminStatusEffects` → `writeAudit`), and
//   • re-runs `propagateOrgActive` across every trainer in the organization.
//
// So the compliance record showed two approvals for one decision — on the one
// surface whose entire purpose is answering "who did this, and when".
//
// The sibling path, `DashboardController._moderate`, has always guarded with
// `if (_moderating) return`. These tests pin the two paths to the same rule.

import 'dart:async';

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/models/admin_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _CountingAdminController extends AdminController {
  int calls = 0;
  final List<String> statuses = [];
  final List<String?> reasons = [];

  /// Completed by the test, so a call is held "in flight" deterministically
  /// rather than by racing a timer.
  final inFlight = Completer<void>();

  _CountingAdminController() {
    // The stale-state guard re-reads the record before every call; here the
    // record always says what the fixture says, so the guard passes and the
    // test isolates the RE-ENTRY guard.
    freshStatusRead = (uid) async => uid == 'org-2' ? 'active' : 'pending';
    moderationCall = (adminUid, status, {reason, expectedStatus}) async {
      calls++;
      statuses.add(status);
      reasons.add(reason);
      await inFlight.future;
    };
  }

  // No Firestore stream in a unit test.
  @override
  // ignore: must_call_super
  void onInit() {}
}

AdminModel org(String id, {String status = 'pending'}) => AdminModel(
      docId: id,
      uid: id,
      name: 'Owner $id',
      email: '$id@example.com',
      phone: '',
      organizationName: 'Org $id',
      role: 'admin',
      status: status,
      subscriptionLimits: AdminSubscriptionLimits.empty(),
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// The controller raises Get snackbars, which need Get's overlay. A bare
/// GetMaterialApp supplies it without touching Firebase.
Future<void> mountGet(WidgetTester tester) async {
  await tester.pumpWidget(const GetMaterialApp(home: SizedBox.shrink()));
}

/// A Get snackbar animates; leaving one running leaks its ticker past teardown
/// and the failure then reads like a defect in the code under test.
Future<void> drain(WidgetTester tester) async {
  // AppSnackbar schedules a dismissal Timer; closing the snackbar does not
  // cancel it, and a pending timer at teardown fails the test with a message
  // that looks like a defect in the code under test. Pump past its duration.
  Get.closeAllSnackbars();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('a second Approve while the first is in flight is refused',
      (tester) async {
    await mountGet(tester);
    final c = _CountingAdminController();

    final first = c.approve(org('org-1'));
    // The founder taps again before the round trip returns — exactly what the
    // inert UI invited.
    final second = c.approve(org('org-1'));
    // The call follows the server re-read (a microtask); the GUARD is
    // synchronous, which is what makes the second tap impossible.
    expect(c.isProcessing.value, isTrue);
    await tester.pump();

    expect(c.calls, 1, reason: 'one decision, one setAdminStatus invocation');
    expect(c.isProcessing.value, isTrue, reason: 'the screen must show this');

    c.inFlight.complete();
    await Future.wait([first, second]);
    await tester.pump();

    expect(c.calls, 1);
    expect(c.isProcessing.value, isFalse, reason: 'the guard must release');
    await drain(tester);
  });

  testWidgets('a rapid burst of taps still produces exactly one call',
      (tester) async {
    await mountGet(tester);
    final c = _CountingAdminController();
    final futures = [for (var i = 0; i < 8; i++) c.block(org('org-1'), 'spam')];
    await tester.pump();

    expect(c.calls, 1);

    c.inFlight.complete();
    await Future.wait(futures);
    await tester.pump();
    expect(c.calls, 1);
    await drain(tester);
  });

  testWidgets('CONTROL — the guard gates concurrency, not the feature',
      (tester) async {
    // If `isProcessing` ever leaked (or never released) every later moderation
    // would silently do nothing — a worse defect than the one being fixed.
    await mountGet(tester);
    final c = _CountingAdminController();

    final first = c.approve(org('org-1'));
    c.inFlight.complete();
    await first;
    await tester.pump();
    expect(c.isProcessing.value, isFalse);

    // A SECOND, different decision on the same controller must go through.
    await c.warn(org('org-2', status: 'active'), 'late payments');
    await tester.pump();

    expect(c.calls, 2);
    expect(c.statuses, ['active', 'warning']);
    expect(c.reasons.last, 'late payments');
    await drain(tester);
  });

  testWidgets('the reason reaches the backend unedited', (tester) async {
    await mountGet(tester);
    final c = _CountingAdminController();
    c.block(org('org-1'), '  repeated chargebacks  ');
    await tester.pump();
    expect(c.reasons.single, '  repeated chargebacks  ',
        reason: 'trimming belongs to the service, not a silent edit here');
    c.inFlight.complete();
    await tester.pumpAndSettle();
    await drain(tester);
  });
}
