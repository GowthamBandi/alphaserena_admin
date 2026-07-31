import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:alphaserena_admin_portel/widgets/plan_live_preview.dart';
import 'package:alphaserena_admin_portel/widgets/subscription_plan_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

// Widget tests for the LIVE Plan Editor — the real SubscriptionPlanDialog bound
// to the real SubscriptionController, so reactive-binding regressions (a toggle
// that does not repaint until some other interaction rebuilds the subtree) are
// caught here instead of in production.
//
// The controller resolves Firestore lazily, so a subclass that skips the
// realtime stream makes the whole editor testable without Firebase. Nothing in
// these tests reaches the network: no save, no status change, no delete.

class _OfflineSubscriptionController extends SubscriptionController {
  // Deliberately does NOT call super.onInit() — that would open the Firestore
  // snapshot stream. Everything else is the real controller.
  @override
  // ignore: must_call_super
  void onInit() {}
}

late SubscriptionController ctrl;

Future<void> _pumpEditor(WidgetTester tester,
    {bool isEdit = false, Size size = const Size(1400, 1200)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  // GetMaterialApp, like production: the editor raises Get snackbars, which
  // need Get's overlay.
  await tester.pumpWidget(
    GetMaterialApp(
        home: Scaffold(body: SubscriptionPlanDialog(isEdit: isEdit))),
  );
  await tester.pumpAndSettle();
}

/// The Premium Capabilities switch — the one inside the row that carries the
/// capability's own label, so the finder survives layout changes.
Finder _capabilitySwitch() => find.descendant(
      of: find
          .ancestor(
              of: find.text('Client Progress Tracking'),
              matching: find.byType(Row))
          .first,
      matching: find.byType(Switch),
    );

/// Scopes a finder to the buyer preview pane, so editor labels that share a
/// word with the card (e.g. "Unlimited") can't satisfy a preview assertion.
Finder _inPreview(Finder f) =>
    find.descendant(of: find.byType(PlanLivePreview), matching: f);

/// The Unlimited switch of one capacity row.
Finder _unlimitedSwitch(PlanResource r) => find.descendant(
      of: find.ancestor(of: find.text(r.label), matching: find.byType(Row)).first,
      matching: find.byType(Switch),
    );

/// The number field of one capacity row.
Finder _limitField(PlanResource r) => find.descendant(
      of: find.ancestor(of: find.text(r.label), matching: find.byType(Row)).first,
      matching: find.byType(TextField),
    );

bool _capabilitySwitchValue(WidgetTester tester) =>
    tester.widget<Switch>(_capabilitySwitch()).value;

/// The editor scrolls inside a height-capped dialog, so every interaction
/// scrolls its target into view first — exactly what a founder does.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
}

Future<void> _type(WidgetTester tester, Finder f, String text) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, text);
}

void main() {
  setUp(() {
    ctrl = _OfflineSubscriptionController();
    Get.put<SubscriptionController>(ctrl);
  });

  tearDown(Get.reset);

  group('Premium Capabilities toggle (BUG 1 — stale switch)', () {
    testWidgets('tapping the capability switch repaints it immediately',
        (tester) async {
      await _pumpEditor(tester);

      // A new plan starts with Client Progress Tracking ON (the ungated
      // TrainerHQ baseline) and 50 active clients, so the row is enabled.
      expect(ctrl.capabilities[PlanCapabilities.progress], isTrue);
      expect(_capabilitySwitchValue(tester), isTrue);

      // Turn it OFF. One pump = one frame; no other interaction, no refresh.
      await _tap(tester, _capabilitySwitch());
      await tester.pump();

      expect(ctrl.capabilities[PlanCapabilities.progress], isFalse,
          reason: 'controller state must change on tap');
      expect(_capabilitySwitchValue(tester), isFalse,
          reason: 'the switch must repaint on the very next frame');

      // ...and back ON.
      await _tap(tester, _capabilitySwitch());
      await tester.pump();
      expect(ctrl.capabilities[PlanCapabilities.progress], isTrue);
      expect(_capabilitySwitchValue(tester), isTrue);
    });

    testWidgets('rapid repeated toggling stays in sync with the controller',
        (tester) async {
      await _pumpEditor(tester);

      for (var i = 0; i < 6; i++) {
        await _tap(tester, _capabilitySwitch());
        await tester.pump();
        expect(_capabilitySwitchValue(tester),
            ctrl.capabilities[PlanCapabilities.progress],
            reason: 'switch and controller diverged on toggle #$i');
      }
    });

    testWidgets(
        'a capacity that cannot support the capability disables and clears it',
        (tester) async {
      await _pumpEditor(tester);
      expect(_capabilitySwitchValue(tester), isTrue);

      // Active Clients → 0 blocks Client Progress Tracking.
      await _type(tester, _limitField(PlanResource.activeClients), '0');
      await tester.pump();

      expect(ctrl.capabilities[PlanCapabilities.progress], isFalse);
      expect(_capabilitySwitchValue(tester), isFalse);
      expect(
          find.text(
              'Client Progress Tracking needs Active Clients capacity to track.'),
          findsOneWidget);
    });
  });

  group('Highlights (BUG 2 — no auto-generated bullets)', () {
    testWidgets('a fresh plan previews NO highlights until one is added',
        (tester) async {
      await _pumpEditor(tester);

      // Default capacities are set (50 clients, 2 trainers, ...) — none of
      // them may become a preview bullet.
      expect(_inPreview(find.textContaining('active clients')), findsNothing);
      expect(_inPreview(find.textContaining('trainer seat')), findsNothing);
      expect(
          _inPreview(find.text('Client progress tracking')), findsNothing);
      expect(_inPreview(find.textContaining('No highlights yet')),
          findsOneWidget);

      // The capacity chips still carry the capacity story.
      expect(_inPreview(find.text('Clients ')), findsOneWidget);
      expect(_inPreview(find.text('50')), findsWidgets);
    });

    testWidgets('adding, duplicating and removing a highlight', (tester) async {
      await _pumpEditor(tester);

      await _type(tester, find.widgetWithText(TextField, 'Add a highlight'),
          'Priority support');
      await _tap(tester, find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      expect(ctrl.points, ['Priority support']);
      // Chip in the editor + bullet in the preview.
      expect(find.text('Priority support'), findsNWidgets(2));
      expect(_inPreview(find.textContaining('No highlights yet')), findsNothing);

      // A case-insensitive duplicate must not create a second chip that the
      // preview would silently drop.
      await _type(tester, find.widgetWithText(TextField, 'Add a highlight'),
          'priority SUPPORT');
      await _tap(tester, find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pump();
      expect(ctrl.points, ['Priority support']);
      expect(find.text('Already added'), findsOneWidget,
          reason: 'the founder must be told, not silently ignored');
      // Let the 2s snackbar retire before the next interaction.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Blank input adds nothing.
      await _type(
          tester, find.widgetWithText(TextField, 'Add a highlight'), '   ');
      await _tap(tester, find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();
      expect(ctrl.points, ['Priority support']);

      // Remove it → preview empties again.
      await _tap(tester, find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();
      expect(ctrl.points, isEmpty);
      expect(_inPreview(find.textContaining('No highlights yet')),
          findsOneWidget);
    });

    testWidgets('editing an existing plan keeps ONLY its custom highlights',
        (tester) async {
      ctrl.loadPlanForEdit(SubscriptionPlanModel(
        id: 'p1',
        docId: 'p1',
        planName: 'Growth',
        sortOrder: 1,
        isActive: true,
        monthlyPrice: 1999,
        yearlyPrice: 19990,
        durationMonths: 1,
        limits: {for (final r in PlanResource.values) r: 25},
        capabilities: const {PlanCapabilities.progress: true},
        // A legacy doc whose rendered list was generated + custom.
        points: const [
          '25 trainer seats',
          'Up to 25 active clients',
          'Priority support',
        ],
        customPoints: const ['Priority support'],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await _pumpEditor(tester, isEdit: true);

      expect(ctrl.points, ['Priority support']);
      expect(find.textContaining('trainer seats'), findsNothing);
      expect(find.textContaining('Up to 25 active clients'), findsNothing);
      expect(_inPreview(find.text('Priority support')), findsOneWidget);
    });
  });

  group('Live preview freshness', () {
    testWidgets('name, price, term and status reach the preview immediately',
        (tester) async {
      await _pumpEditor(tester);
      expect(find.text('Untitled plan'), findsOneWidget);

      await _type(
          tester, find.widgetWithText(TextField, 'Plan name'), 'Growth');
      await tester.pump();
      expect(_inPreview(find.text('Growth')), findsOneWidget);

      await _type(tester, find.widgetWithText(TextField, 'Monthly price (₹)'),
          '1499');
      await tester.pump();
      expect(find.text('₹1,499'), findsOneWidget);

      await _tap(tester, find.text('Yearly'));
      await tester.pump();
      expect(find.text('12 Months'), findsOneWidget);

      await _tap(tester, find.text('Hidden'));
      await tester.pump();
      expect(find.text("Hidden — buyers won't see this"), findsOneWidget);
    });

    testWidgets('an Unlimited toggle reaches the preview chip immediately',
        (tester) async {
      await _pumpEditor(tester);
      expect(_inPreview(find.text('Unlimited')), findsNothing);

      await _tap(tester, _unlimitedSwitch(PlanResource.teamMembers));
      await tester.pump();
      expect(_inPreview(find.text('Unlimited')), findsOneWidget);
    });
  });

  group('Layout', () {
    testWidgets('single-column layout (narrow window) builds without overflow',
        (tester) async {
      // Below the 940px two-pane threshold the preview folds into the column.
      await _pumpEditor(tester, size: const Size(700, 900));

      expect(find.byType(PlanLivePreview), findsOneWidget);
      expect(find.text('Buyer preview'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The editor still works there.
      await _tap(tester, _capabilitySwitch());
      await tester.pump();
      expect(_capabilitySwitchValue(tester),
          ctrl.capabilities[PlanCapabilities.progress]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a very long plan name and highlight do not overflow',
        (tester) async {
      await _pumpEditor(tester);
      final long = 'Enterprise ${'Ultra ' * 40}Plan';

      await _type(tester, find.widgetWithText(TextField, 'Plan name'), long);
      await tester.pump();
      await _type(
          tester, find.widgetWithText(TextField, 'Add a highlight'), long);
      await _tap(tester, find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();

      expect(ctrl.points.single, long.trim());
      expect(tester.takeException(), isNull);
    });
  });

  group('Capacity edge cases', () {
    testWidgets('Unlimited on → off leaves an empty field, never a hard 0',
        (tester) async {
      await _pumpEditor(tester);
      final f = _limitField(PlanResource.workoutPlans);

      await _type(tester, f, '0');
      await _tap(tester, _unlimitedSwitch(PlanResource.workoutPlans));
      await tester.pump();
      expect(ctrl.limitUnlimited[PlanResource.workoutPlans], isTrue);

      await _tap(tester, _unlimitedSwitch(PlanResource.workoutPlans));
      await tester.pump();
      expect(ctrl.limitCtrls[PlanResource.workoutPlans]!.text, isEmpty,
          reason: 'a leftover 0 would be rejected at save with no explanation');
    });

    testWidgets('rapid Unlimited toggling stays consistent', (tester) async {
      await _pumpEditor(tester);
      final sw = _unlimitedSwitch(PlanResource.dietPlans);
      for (var i = 0; i < 6; i++) {
        await _tap(tester, sw);
        await tester.pump();
        expect(tester.widget<Switch>(sw).value,
            ctrl.limitUnlimited[PlanResource.dietPlans]);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('an emptied capacity field is "no information", not 0',
        (tester) async {
      await _pumpEditor(tester);
      // Mid-edit (select-all + delete) must not silently kill the capability.
      await _type(tester, _limitField(PlanResource.activeClients), '');
      await tester.pump();
      expect(ctrl.capabilities[PlanCapabilities.progress], isTrue);
      expect(_capabilitySwitchValue(tester), isTrue);
    });

    testWidgets(
        'DOCUMENTED BEHAVIOUR: a capability disabled by a 0 capacity does NOT '
        'come back when the capacity is restored', (tester) async {
      await _pumpEditor(tester);
      await _type(tester, _limitField(PlanResource.activeClients), '0');
      await tester.pump();
      expect(ctrl.capabilities[PlanCapabilities.progress], isFalse);

      await _type(tester, _limitField(PlanResource.activeClients), '50');
      await tester.pump();
      // Re-enabling is a deliberate act by the founder — the editor never
      // re-sells a capability on its own. See the sprint report, risk R1.
      expect(ctrl.capabilities[PlanCapabilities.progress], isFalse);
      expect(_capabilitySwitchValue(tester), isFalse);
    });
  });

  group('Pricing input', () {
    testWidgets('a fractional legacy price survives being edited',
        (tester) async {
      ctrl.loadPlanForEdit(SubscriptionPlanModel(
        id: 'p1',
        docId: 'p1',
        planName: 'Legacy',
        sortOrder: 1,
        isActive: true,
        monthlyPrice: 999.5,
        yearlyPrice: 9995.5,
        durationMonths: 1,
        limits: {for (final r in PlanResource.values) r: 10},
        capabilities: const {PlanCapabilities.progress: true},
        points: const [],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await _pumpEditor(tester, isEdit: true);
      expect(ctrl.monthlyPriceCtrl.text, '999.5');

      // Appending a digit must not strip the decimal point (a digits-only
      // formatter rewrote the whole value → ₹9995, a 10× price error).
      await _type(tester, find.widgetWithText(TextField, 'Monthly price (₹)'),
          '999.50');
      await tester.pump();
      expect(ctrl.monthlyPriceCtrl.text, '999.50');
      expect(_inPreview(find.text('₹1,000')), findsOneWidget); // rounded hero

      // A second decimal point is refused rather than producing an
      // unparseable value that would silently read back as ₹0.
      await _type(tester, find.widgetWithText(TextField, 'Monthly price (₹)'),
          '999.50.7');
      await tester.pump();
      expect(ctrl.monthlyPriceCtrl.text, '999.50');
    });

    testWidgets('a capacity beyond the parseable range cannot be typed',
        (tester) async {
      await _pumpEditor(tester);
      await _type(tester, _limitField(PlanResource.activeClients),
          '99999999999999999999');
      await tester.pump();
      final text = ctrl.limitCtrls[PlanResource.activeClients]!.text;
      expect(text.length, lessThanOrEqualTo(9));
      expect(int.tryParse(text), isNotNull,
          reason: 'an unparseable capacity would read back as a 0 '
              'the founder never typed');
    });
  });

  group('Form defaults and reset', () {
    testWidgets('a new plan is authored with the ungated TrainerHQ baseline',
        (tester) async {
      // clearForm() runs on every Create — it must not silently drop the
      // capability the backend projects onto admins/{uid}.features.
      ctrl.clearForm();
      await _pumpEditor(tester);
      expect(ctrl.capabilities[PlanCapabilities.progress], isTrue);
      expect(_capabilitySwitchValue(tester), isTrue);
    });

    testWidgets('opening Create after an Edit shows no leftover state',
        (tester) async {
      ctrl.loadPlanForEdit(SubscriptionPlanModel(
        id: 'p1',
        docId: 'p1',
        planName: 'Growth',
        badge: 'POPULAR',
        sortOrder: 3,
        isActive: true,
        monthlyPrice: 1999,
        yearlyPrice: 19990,
        durationMonths: 12,
        limits: {for (final r in PlanResource.values) r: 25},
        capabilities: const {PlanCapabilities.progress: true},
        points: const ['Priority support'],
        customPoints: const ['Priority support'],
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      // Now the founder closes it and hits "New plan" (isEdit: false →
      // clearForm in initState).
      await _pumpEditor(tester);

      expect(ctrl.editingDocId.value, isEmpty);
      expect(ctrl.points, isEmpty);
      expect(ctrl.planNameCtrl.text, isEmpty);
      expect(ctrl.badgeCtrl.text, isEmpty);
      expect(ctrl.termMonths.value, 1);
      expect(find.text('Untitled plan'), findsOneWidget);
    });
  });
}
