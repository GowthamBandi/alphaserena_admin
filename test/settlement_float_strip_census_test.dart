// A PLATFORM HEALTH COUNTER MUST NOT INVENT A ZERO.
//
// 🔴 THE DEFECT THIS GUARDS. The Settlements float strip reports four
// platform-wide numbers. Two of them fabricate a confident zero when the server
// census they depend on could not be read:
//
//   • `needsAttentionCount` (settlement_controller.dart) falls back to
//     `countWhere((x) => x.status.needsAttention)` over the STREAMED PAGE
//     whenever `summary.value` is null. The controller's own comment three
//     lines above documents that exact derivation as a shipped defect:
//
//         "switching to 'Ready to pay' made the strip announce
//          'Needs attention 0 · Nothing blocked' while three settlements were
//          in fact blocked. A filtered view silently rewrote a platform health
//          indicator into a lie an operator would act on."
//
//     The fix moved the counter to the server census — and left the discredited
//     math as the null branch, so the lie returns on every census failure. On
//     the "Ready to pay" view the fallback is structurally 0: that view streams
//     `status == 'approved'`, which is disjoint from {under_review, failed}.
//
//   • `overdueTotal` is an `RxInt` initialised to 0 whose `count()` aggregate
//     failure is swallowed with a `debugPrint`, so the tile reads
//     "Overdue 0 · Clock on schedule".
//
// `refreshSummary()` runs ONCE at console boot and after money actions;
// switching views does not re-fetch. So a single cold-start 503 at sign-in
// leaves both tiles lying for the whole session.
//
// The decisive evidence that this is an oversight rather than a design: the
// SAME build method already renders '—' for the two tiles beside them when the
// census is missing. The author treats "unavailable" as a real state — just not
// for the two tiles that report blocked money.

import 'package:alphaserena_admin_portel/controllers/settlement_controller.dart';
import 'package:alphaserena_admin_portel/core/services/settlement_service.dart';
import 'package:alphaserena_admin_portel/screens/settlement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _OfflineSettlements extends SettlementController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

_OfflineSettlements _mount() {
  final c = Get.put<SettlementController>(_OfflineSettlements(), permanent: true)
      as _OfflineSettlements;
  c.loading.value = false;
  c.exceptionsLoading.value = false;
  c.summaryLoading.value = false;
  return c;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: SettlementScreen())),
  );
  await tester.pump();
}

void main() {
  tearDown(Get.reset);

  testWidgets('a census that could not be read is not "Nothing blocked"',
      (tester) async {
    final c = _mount();
    c.summary.value = null; // getSettlementSummary failed and was swallowed

    await _pump(tester);

    expect(find.text('Nothing blocked'), findsNothing,
        reason: 'the platform blocked-payout census was never read; claiming '
            'nothing is blocked is the exact lie the controller comment says '
            'this counter was moved server-side to stop telling');
  });

  testWidgets('an overdue count that could not be read is not "Clock on schedule"',
      (tester) async {
    final c = _mount();
    c.summary.value = null;

    await _pump(tester);

    expect(find.text('Clock on schedule'), findsNothing,
        reason: 'overdueTotal is still its initial 0 — nothing counted it');
  });

  testWidgets('CONTROL — a census that WAS read and is genuinely zero says so',
      (tester) async {
    // Without this control, tiles that never report health would pass both
    // assertions above and the strip would lose its only good-news signal.
    final c = _mount();
    c.summary.value = const SettlementSummary(byStatus: {});
    c.overdueAvailable.value = true;

    await _pump(tester);

    expect(find.text('Nothing blocked'), findsOneWidget);
    expect(find.text('Clock on schedule'), findsOneWidget);
  });
}
