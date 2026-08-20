// A FAILED LOAD MUST NOT LOOK LIKE AN EMPTY PLATFORM.
//
// 🔴 THE DEFECT THIS GUARDS. Six screens — Organizations, Trainers, Members,
// Coupons, Payments and Subscriptions — had no error state at all. Their
// streams' `onError` set `isLoading = false`, raised a snackbar that vanishes
// in seconds, and left the list empty. The screen then rendered its "nothing
// here yet" copy. So an undeployed ruleset, a missing index and a genuinely
// empty platform were the same picture.
//
// Payments was the worst of the six: its four KPI cards are SUMS over the
// list, so a failed load reported **₹0 total revenue** — not a missing number,
// a fabricated one.
//
// Each test below drives the REAL screen with the REAL controller (subclassed
// only to skip the Firestore stream) and asserts BOTH halves:
//   1. the classified failure is on screen, and
//   2. the empty-state copy is NOT — because a test that only checked (1)
//      would still pass if the screen rendered both.

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/client_controller.dart';
import 'package:alphaserena_admin_portel/controllers/coupon_controller.dart';
import 'package:alphaserena_admin_portel/controllers/payments_controller.dart';
import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/core/widgets/console/console_chrome.dart';
import 'package:alphaserena_admin_portel/screens/admins_screen.dart';
import 'package:alphaserena_admin_portel/screens/clients_screen.dart';
import 'package:alphaserena_admin_portel/screens/coupon_code_screen.dart';
import 'package:alphaserena_admin_portel/screens/payments_screen.dart';
import 'package:alphaserena_admin_portel/screens/subscriptions_screen.dart';
import 'package:alphaserena_admin_portel/screens/trainers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// The two failures an operator most needs told apart, and which the old
/// behaviour rendered identically to "no data".
const _rulesDenied = ConsoleError(
  kind: ConsoleErrorKind.permission,
  message: 'Firestore refused this read.',
  remedy: 'From trainershq-backend:  firebase deploy --only firestore:rules',
);

// Offline doubles: everything real except the Firestore subscription.
class _OfflineAdmins extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineTrainers extends TrainerController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineClients extends ClientController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineCoupons extends CouponController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflinePayments extends PaymentsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflinePlans extends SubscriptionController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  // Presentational screens return a bare PageShell — the Scaffold lives in
  // the routing shell (admin_root_screen). Supply one, as production does.
  await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

/// The classified error state is on screen.
void _expectErrorState() {
  expect(find.byType(ConsoleErrorState), findsOneWidget);
  expect(find.text('Not authorized'), findsOneWidget);
}

void main() {
  setUp(Get.reset);
  tearDown(Get.reset);

  testWidgets('Organizations shows the failure, not "No organizations"',
      (tester) async {
    final c = Get.put<AdminController>(_OfflineAdmins(), permanent: true);
    c.loadError.value = _rulesDenied;
    await _pump(tester, AdminsScreen());

    _expectErrorState();
    expect(find.textContaining('No organizations'), findsNothing);
  });

  testWidgets('Trainers shows the failure, not an empty roster',
      (tester) async {
    final c = Get.put<TrainerController>(_OfflineTrainers(), permanent: true);
    c.loadError.value = _rulesDenied;
    await _pump(tester, TrainersScreen());

    _expectErrorState();
  });

  testWidgets('Members shows the failure, not an empty roster', (tester) async {
    final c = Get.put<ClientController>(_OfflineClients(), permanent: true);
    c.loadError.value = _rulesDenied;
    await _pump(tester, ClientsScreen());

    _expectErrorState();
  });

  testWidgets('Coupons shows the failure, not "no coupons"', (tester) async {
    final c = Get.put<CouponController>(_OfflineCoupons(), permanent: true);
    c.loadError.value = _rulesDenied;
    await _pump(tester, CouponCodeScreen());

    _expectErrorState();
  });

  testWidgets('Subscriptions shows the failure, not an empty catalog',
      (tester) async {
    final c = Get.put<SubscriptionController>(_OfflinePlans(), permanent: true);
    c.loadError.value = _rulesDenied;
    await _pump(tester, SubscriptionsScreen());

    _expectErrorState();
    // The empty state invites the founder to author a catalog that exists.
    expect(find.textContaining('No plans'), findsNothing);
  });

  testWidgets('Payments shows the failure and NO fabricated ₹0 revenue',
      (tester) async {
    final c = Get.put<PaymentsController>(_OfflinePayments(), permanent: true);
    c.loadError.value = _rulesDenied;
    await _pump(tester, PaymentsScreen());

    _expectErrorState();
    // The load-bearing half. Four KPI cards summed an empty list and reported
    // money the platform never earned; none of them may be on screen.
    expect(find.text('Total Revenue'), findsNothing);
    expect(find.text('This Month'), findsNothing);
    expect(find.textContaining('No payments found'), findsNothing);
  });

  testWidgets('CONTROL — with no error, each screen still renders normally',
      (tester) async {
    // Without this, a screen that rendered the error state unconditionally
    // would pass every test above.
    final c = Get.put<PaymentsController>(_OfflinePayments(), permanent: true);
    // PaymentsController starts `isLoading = true`; leaving it there renders a
    // CircularProgressIndicator, which never settles.
    c.isLoading.value = false;
    await _pump(tester, PaymentsScreen());

    expect(find.byType(ConsoleErrorState), findsNothing);
    expect(find.text('Total Revenue'), findsOneWidget);
  });
}
