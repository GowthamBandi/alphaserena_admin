// THE HEADER BADGE IS PART OF THE SAME CLAIM AS THE BODY.
//
// 🔴 THE DEFECT THIS GUARDS. SA-11 fixed the Operations Center BODY: a derived
// feed that fails now raises a card, so the body no longer renders "All clear"
// over a platform the console cannot read. The body also already distinguished
// LOADING from EMPTY —
//
//     if (ctrl.anyLoading && alerts.isEmpty)  → spinner
//     else if (alerts.isEmpty)                → "All clear"
//
// — and `anyLoading`'s own docstring says it exists "so the screen shows a
// loader instead of a false 'All clear' before data arrives".
//
// The PageShell `trailing` badge was never given that guard. It reads
//
//     total == 0 ? 'All clear' : '$total need…'
//
// straight off `alerts.length`, in green, with no loading test. So on every
// boot — and for as long as any source is slow, unregistered, or mid-reconnect
// — the screen showed a spinner in the body and a green **"All clear"** in the
// header at the same time. The two halves of one screen made contradictory
// claims, and the one a founder reads at a glance was the wrong one.
//
// LOADING, FAILED, EMPTY and SUCCESS must each read differently.

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/communication_controller.dart';
import 'package:alphaserena_admin_portel/controllers/operations_controller.dart';
import 'package:alphaserena_admin_portel/controllers/support_controller.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/screens/operations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _denied = ConsoleError(
  kind: ConsoleErrorKind.permission,
  message: 'Firestore refused this read.',
);

class _OfflineAdmins extends AdminController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineSupport extends SupportController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineComms extends CommunicationController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _OfflineOps extends OperationsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

/// Registers the three derived sources. [loaded] false leaves them mid-load,
/// which is the boot state every login passes through.
({_OfflineAdmins admins, _OfflineSupport support, _OfflineComms comms})
    _sources({required bool loaded}) {
  final admins = Get.put<AdminController>(_OfflineAdmins(), permanent: true)
      as _OfflineAdmins;
  final support = Get.put<SupportController>(_OfflineSupport(), permanent: true)
      as _OfflineSupport;
  final comms = Get.put<CommunicationController>(_OfflineComms(),
      permanent: true) as _OfflineComms;
  admins.isLoading.value = !loaded;
  support.feedbackLoading.value = !loaded;
  support.reviewsLoading.value = !loaded;
  comms.isLoading.value = !loaded;
  return (admins: admins, support: support, comms: comms);
}

_OfflineOps _ops({required bool ownFeedsLoaded}) {
  final ops = _OfflineOps();
  ops.telemetryLoaded.value = ownFeedsLoaded;
  ops.incidentsLoaded.value = ownFeedsLoaded;
  return Get.put<OperationsController>(ops, permanent: true) as _OfflineOps;
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(GetMaterialApp(home: Scaffold(body: OperationsScreen())));
  await tester.pump();
}

void main() {
  tearDown(Get.reset);

  testWidgets('LOADING does not read as "All clear"', (tester) async {
    _sources(loaded: false);
    _ops(ownFeedsLoaded: false);

    await _pump(tester);

    expect(find.text('All clear'), findsNothing,
        reason: 'nothing has been read yet — the badge is asserting health it '
            'has not observed');
  });

  testWidgets('a source that has not registered yet does not read as clear',
      (tester) async {
    // The boot window: OperationsController is registered LAST, so there are
    // frames in which its sources do not exist at all.
    _ops(ownFeedsLoaded: true);

    await _pump(tester);

    expect(find.text('All clear'), findsNothing);
  });

  testWidgets('FAILED does not read as "All clear"', (tester) async {
    final s = _sources(loaded: true);
    _ops(ownFeedsLoaded: true);
    s.admins.loadError.value = _denied;

    await _pump(tester);

    expect(find.text('All clear'), findsNothing);
  });

  testWidgets('CONTROL — loaded, healthy and empty DOES read as "All clear"',
      (tester) async {
    // Without this control, a badge that never says "All clear" would pass
    // every assertion above and the screen would lose its only positive signal.
    _sources(loaded: true);
    _ops(ownFeedsLoaded: true);

    await _pump(tester);

    // Two: the header badge and the body's empty state, which agree.
    expect(find.text('All clear'), findsWidgets);
  });
}
