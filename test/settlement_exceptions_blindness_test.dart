// "NO EXCEPTIONS" IS A CLAIM ABOUT A QUEUE THAT WAS READ.
//
// 🔴 THE DEFECT THIS GUARDS. The Settlements screen's Exceptions view lists
// `paymentAlerts` where `kind == charged_not_activated` — the money-integrity
// queue of members who were charged at the gateway and never activated. Its
// stream's `onError` set `exceptionsLoading = false`, wrote one `debugPrint`,
// and left the list empty. The view then rendered
//
//     "No exceptions — A payment lands here when it was captured at the
//      gateway but the membership was never activated…"
//
// which is the reassuring copy for a healthy platform, shown for a read that
// never happened. A denied rule, a missing index or an offline client all
// looked identical to "nobody has been charged without being activated".
//
// This is the SA-06 / SA-11 class, on the queue where being wrong means real
// members stay charged-and-unactivated while the console reports calm. The
// sibling stream in this same controller — the settlements queue — already
// carries a classified `ConsoleError`; the two now agree.
//
// The Operations Center raises its own card when ITS `paymentAlerts` listener
// fails (`telemetryError`), so the founder is not left with no signal anywhere.
// That does not make this screen's own sentence true.

import 'package:alphaserena_admin_portel/controllers/settlement_controller.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/core/widgets/console/console_chrome.dart';
import 'package:alphaserena_admin_portel/screens/settlement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _denied = ConsoleError(
  kind: ConsoleErrorKind.permission,
  message: 'Firestore refused this read.',
  remedy: 'From trainershq-backend:  firebase deploy --only firestore:rules',
);

class _OfflineSettlements extends SettlementController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

_OfflineSettlements _mount() {
  final c = Get.put<SettlementController>(_OfflineSettlements(),
      permanent: true) as _OfflineSettlements;
  c.view.value = SettlementView.exceptions;
  c.loading.value = false;
  c.exceptionsLoading.value = false;
  return c;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: SettlementScreen())),
  );
  await tester.pump();
}

void main() {
  tearDown(Get.reset);

  testWidgets('a failed exceptions read is not "No exceptions"',
      (tester) async {
    final c = _mount();
    c.exceptionsError.value = _denied;

    await _pump(tester);

    expect(find.byType(ConsoleErrorState), findsOneWidget,
        reason: 'the operator must be told the money-integrity queue could '
            'not be read');
    expect(find.text('No exceptions'), findsNothing,
        reason: 'that sentence asserts the queue is empty; nothing read it');
  });

  test('a failed webhook read must not be read as a webhook mis-registration',
      () {
    // 🔴 The GATEWAY EVENTS panel's empty state names a probable cause: "the
    // Razorpay webhook may not be registered". Its stream's onError only wrote
    // a debugPrint, so a denied read rendered that diagnosis — sending the
    // operator to investigate the gateway because Firestore refused a query.
    final c = _OfflineSettlements();

    c.onWebhookStreamError(Exception('permission-denied'));

    expect(c.webhookError.value, isTrue,
        reason: 'the panel needs to tell a failed read from "no events"');
  });

  testWidgets('CONTROL — a genuinely empty queue still says "No exceptions"',
      (tester) async {
    // Without this control, a fix that always errored would pass the test
    // above and destroy the screen's only positive signal.
    _mount();

    await _pump(tester);

    expect(find.byType(ConsoleErrorState), findsNothing);
    expect(find.text('No exceptions'), findsOneWidget);
  });
}
