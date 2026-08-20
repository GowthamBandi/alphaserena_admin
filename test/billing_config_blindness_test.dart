// THE TAX EDITOR MUST NOT SHOW "NO TAX" FOR A READ THAT DID NOT HAPPEN.
//
// 🔴 THE DEFECT THIS GUARDS. `BillingConfigController`'s snapshot listener set
// `isLoading = false` on error, raised a snackbar that vanishes in seconds, and
// left `enabled = false` with an empty `taxes` list. The dialog then rendered
// its normal editor — master switch OFF, no rules — which is EXACTLY what a
// platform that has never charged tax looks like.
//
// That is the SA-06 class of defect on the one screen where it is destructive
// rather than merely misleading. The six list screens SA-06 fixed are
// read-only; this one has a Save button, and `setCommerceConfig` writes
// `taxes` and `authoredTaxes` as whole arrays. So the sequence
//
//     open the dialog → the read fails → the editor shows "tax is off" → Save
//
// republishes `{enabled: false, taxes: []}` over the live table and the
// platform silently stops charging tax on every subsequent order.
//
// The model's own `fromMap` already documents this hazard on the READ leg
// ("without the fallback the first load ... the first save would wipe the live
// table"). These tests close the ERROR leg of the same hazard.
//
// Each test drives the REAL dialog with the REAL controller (subclassed only
// to skip the Firestore stream) and asserts BOTH halves: the failure is on
// screen, AND the editor that would overwrite the table is not.

import 'dart:async';

import 'package:alphaserena_admin_portel/controllers/billing_config_controller.dart';
import 'package:alphaserena_admin_portel/core/utils/console_errors.dart';
import 'package:alphaserena_admin_portel/core/widgets/console/console_chrome.dart';
import 'package:alphaserena_admin_portel/models/billing_config_model.dart';
import 'package:alphaserena_admin_portel/widgets/billing_config_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _denied = ConsoleError(
  kind: ConsoleErrorKind.permission,
  message: 'Firestore refused this read.',
  remedy: 'From trainershq-backend:  firebase deploy --only firestore:rules',
);

/// Everything real except the Firestore subscription.
class _OfflineBilling extends BillingConfigController {
  int published = 0;
  final List<Map<String, dynamic>> payloads = [];

  /// Held open by the test so a save is "in flight" deterministically rather
  /// than by racing a timer.
  Completer<void> inFlight = Completer<void>();

  _OfflineBilling() {
    publishCall = (payload) async {
      published++;
      payloads.add(payload);
      await inFlight.future;
    };
  }

  @override
  // ignore: must_call_super
  void onInit() {}
}

/// `save()` raises Get snackbars, which need Get's overlay. A bare
/// GetMaterialApp supplies it without touching Firebase.
Future<void> _mountGet(WidgetTester tester) async {
  await tester.pumpWidget(const GetMaterialApp(home: SizedBox.shrink()));
}

/// A Get snackbar schedules a dismissal Timer that closing it does not cancel;
/// a pending timer at teardown fails the test with a message that reads like a
/// defect in the code under test.
Future<void> _drain(WidgetTester tester) async {
  Get.closeAllSnackbars();
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    const GetMaterialApp(home: Scaffold(body: BillingConfigDialog())),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(Get.reset);

  testWidgets('a failed read shows the classified failure, not "tax is off"',
      (tester) async {
    final c = _OfflineBilling();
    Get.put<BillingConfigController>(c);
    c.isLoading.value = false;
    c.loadError.value = _denied;

    await _pump(tester);

    expect(find.byType(ConsoleErrorState), findsOneWidget,
        reason: 'the operator must be told the read failed');
    expect(find.text('Charge tax'), findsNothing,
        reason: 'a master switch reading OFF over a failed read is a claim '
            'the console cannot support');
  });

  testWidgets('a failed read does not offer Save', (tester) async {
    final c = _OfflineBilling();
    Get.put<BillingConfigController>(c);
    c.isLoading.value = false;
    c.loadError.value = _denied;

    await _pump(tester);

    expect(find.text('Save settings'), findsNothing,
        reason: 'Save over a failed read publishes {enabled:false, taxes:[]} '
            'and wipes the live tax table');
  });

  testWidgets('CONTROL — a genuinely untaxed platform still renders the editor',
      (tester) async {
    // Without this, a "fix" that always shows an error would pass every
    // assertion above while breaking the screen.
    final c = _OfflineBilling();
    Get.put<BillingConfigController>(c);
    c.isLoading.value = false;
    c.loadError.value = null;
    c.enabled.value = false;
    c.taxes.clear();

    await _pump(tester);

    expect(find.byType(ConsoleErrorState), findsNothing);
    expect(find.text('Charge tax'), findsOneWidget);
    expect(find.text('Save settings'), findsOneWidget);
  });

  testWidgets('the Currency field is not offered as editable', (tester) async {
    // 🔴 It used to be, with helper text reading "the order is created in it".
    // `createRazorpayOrder` hardcodes currency: "INR" and `priceQuote`'s
    // optional currency has no caller, so the stored value reached nothing but
    // this dialog's own preview symbol.
    final c = _OfflineBilling();
    Get.put<BillingConfigController>(c);
    c.isLoading.value = false;

    await _pump(tester);

    final field = tester.widget<TextFormField>(
        find.byKey(const Key('billing-currency')));
    expect(field.enabled, isFalse,
        reason: 'a control that cannot do what it appears to do must not '
            'accept input — the SA-08 rule');
    expect(find.textContaining('Every order is created in INR'), findsOneWidget);
  });

  testWidgets('CONTROL — a healthy load renders the authored rules',
      (tester) async {
    final c = _OfflineBilling();
    Get.put<BillingConfigController>(c);
    c.isLoading.value = false;
    c.enabled.value = true;
    c.taxes.assignAll(const [TaxRule(name: 'GST', percent: 18)]);

    await _pump(tester);

    expect(find.byType(ConsoleErrorState), findsNothing);
    expect(find.text('Save settings'), findsOneWidget);
  });

  testWidgets('two rapid saves publish once', (tester) async {
    await _mountGet(tester);
    final c = _OfflineBilling();
    c.enabled.value = true;
    c.taxes.assignAll(const [TaxRule(name: 'GST', percent: 18)]);

    // The founder double-clicks Save on a cold-started callable. The UI
    // disables the button, but a UI guard is not the controller's guard.
    final first = c.save();
    final second = c.save();

    expect(c.published, 1, reason: 'one intent, one setCommerceConfig call');

    c.inFlight.complete();
    await Future.wait([first, second]);
    await _drain(tester);
  });

  testWidgets('CONTROL — a second save AFTER the first completes still publishes',
      (tester) async {
    await _mountGet(tester);
    // Proves the guard gates concurrency, not the feature.
    final c = _OfflineBilling();
    c.enabled.value = true;
    c.taxes.assignAll(const [TaxRule(name: 'GST', percent: 18)]);

    c.inFlight.complete();
    await c.save();
    await c.save();

    expect(c.published, 2);
    await _drain(tester);
  });
}
