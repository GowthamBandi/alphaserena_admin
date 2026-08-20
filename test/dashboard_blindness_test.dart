// THE FOUNDER'S HOME SCREEN MUST NOT REPORT NUMBERS IT DID NOT MEASURE.
//
// 🔴 THREE DEFECTS, ONE ROOT CAUSE. `DashboardController`'s stream `onError`
// handlers set `xLoaded = true` **alongside** `xError = true`, because "loaded"
// was written to mean "the first attempt has settled" rather than "the read
// succeeded". Three surfaces then read the wrong signal:
//
//  1. THE KPI GRID. `_stat` chooses between the real number and a dash on
//     `loaded()`, and its own comment states the rule: "Until the source has
//     loaded, a real 0 and 'not yet known' are indistinguishable — show a dash
//     instead of a misleading 0." A FAILED stream satisfies `loaded`, so the
//     grid printed **₹0 total revenue** and **0 organizations** as measured
//     facts. Not a missing number — a fabricated one, on the platform's money.
//
//  2. "EXPIRING SOON" had neither an error nor a loading guard, while every
//     sibling card on the same screen has at least one. A denied `admins` read
//     rendered "Nothing due — No subscriptions expiring this week" directly
//     beside "Pending approvals: couldn't load". The founder skips renewal
//     outreach for every organization expiring in the next seven days.
//
//  3. "PENDING APPROVALS" guarded the error but not the load, so it announced
//     "All clear — No gyms waiting for approval" during first paint.
//
// This is the SA-06 / SA-11 class on the screen the founder opens first.

import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/controllers/dashboard_controller.dart';
import 'package:alphaserena_admin_portel/controllers/operations_controller.dart';
import 'package:alphaserena_admin_portel/screens/dash_board_responsive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _OfflineDashboard extends DashboardController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineOps extends OperationsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineRoot extends AdminRootController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

_OfflineDashboard _mount() {
  Get.put<OperationsController>(_OfflineOps(), permanent: true);
  Get.put<AdminRootController>(_OfflineRoot(), permanent: true);
  return Get.put<DashboardController>(_OfflineDashboard(), permanent: true)
      as _OfflineDashboard;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    GetMaterialApp(home: Scaffold(body: DashboardScreenResponsive())),
  );
  await tester.pump();
  // `_CountUp` animates the KPI numbers; a ticker still running at teardown
  // fails the test with a message that reads like a defect in the code under
  // test. Pump past its duration.
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  tearDown(Get.reset);

  testWidgets('a FAILED revenue stream shows a dash, not ₹0', (tester) async {
    final c = _mount();
    // Exactly what onError does.
    c.revenueError.value = true;
    c.revenueLoaded.value = true;
    c.orgsLoaded.value = true;

    await _pump(tester);

    expect(c.revenueReady, isFalse,
        reason: 'a failed read is not a measurement');
  });

  testWidgets('a FAILED organizations stream shows a dash, not 0 orgs',
      (tester) async {
    final c = _mount();
    c.orgsError.value = true;
    c.orgsLoaded.value = true;

    await _pump(tester);

    expect(c.orgsReady, isFalse);
  });

  testWidgets('a FAILED organizations stream is not "Nothing due"',
      (tester) async {
    final c = _mount();
    c.orgsError.value = true;
    c.orgsLoaded.value = true;

    await _pump(tester);

    expect(find.text('Nothing due'), findsNothing,
        reason: 'the expiry list is derived from the stream that failed');
    expect(find.textContaining('No subscriptions expiring this week'),
        findsNothing);
  });

  testWidgets('LOADING is not "All clear" and not "Nothing due"',
      (tester) async {
    _mount(); // orgsLoaded defaults false — the boot state

    await _pump(tester);

    expect(find.text('All clear'), findsNothing);
    expect(find.text('Nothing due'), findsNothing);
  });

  testWidgets('CONTROL — loaded, healthy and empty still reports health',
      (tester) async {
    // Without this control, cards that never report good news would pass every
    // assertion above and the dashboard would lose its only positive signals.
    final c = _mount();
    c.orgsLoaded.value = true;
    c.orgsError.value = false;
    c.revenueLoaded.value = true;
    c.revenueError.value = false;

    await _pump(tester);

    expect(c.orgsReady, isTrue);
    expect(c.revenueReady, isTrue);
    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('Nothing due'), findsOneWidget);
  });
}
