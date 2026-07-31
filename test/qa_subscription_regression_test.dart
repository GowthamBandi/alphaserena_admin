// Regressions found during the Senior-QA browser pass over the Subscription
// module (2026-07-30). Each group pins one defect that was reproduced live in
// the browser against the real console, so it cannot silently return.

import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:alphaserena_admin_portel/widgets/page_shell.dart';
import 'package:alphaserena_admin_portel/widgets/plan_live_preview.dart';
import 'package:alphaserena_admin_portel/widgets/subscription_plan_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Offline extends SubscriptionController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

Future<void> _pumpPreview(
  WidgetTester tester, {
  required double monthlyPrice,
  required List<double> peerPerMonth,
  int termMonths = 1,
  double yearlyPrice = 0,
}) async {
  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PlanLivePreview(
          planName: 'Probe',
          badge: '',
          status: PlanStatus.published,
          featured: false,
          termMonths: termMonths,
          monthlyPrice: monthlyPrice,
          yearlyPrice: yearlyPrice,
          limits: const {PlanResource.activeClients: 50},
          capabilities: const {},
          customPoints: const [],
          peerPerMonth: peerPerMonth,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('Live preview value framing (QA: BEST VALUE on an unpriced plan)', () {
    testWidgets('a plan with no price yet earns NO value framing',
        (tester) async {
      // Reproduced in the browser: opening Create plan against a catalog with
      // one published ₹999/mo plan rendered "Untitled plan / BEST VALUE / ₹0".
      // A ₹0 plan cannot be sold at all (validation and the backend both reject
      // a non-positive live price), so awarding it the catalog's value crown is
      // a false commercial claim shown for the whole authoring session.
      await _pumpPreview(tester, monthlyPrice: 0, peerPerMonth: [999]);

      expect(find.text('BEST VALUE'), findsNothing);
    });

    testWidgets('a genuinely cheapest priced plan still earns BEST VALUE',
        (tester) async {
      // Guards against over-fixing: the framing must survive for real prices.
      await _pumpPreview(tester, monthlyPrice: 499, peerPerMonth: [999]);

      expect(find.text('BEST VALUE'), findsOneWidget);
    });

    testWidgets('no savings line is claimed for an unpriced yearly plan',
        (tester) async {
      await _pumpPreview(tester,
          monthlyPrice: 0, yearlyPrice: 0, termMonths: 12, peerPerMonth: [999]);

      expect(find.textContaining('save'), findsNothing);
    });
  });

  group('PageShell header (QA: 313px overflow at mobile width)', () {
    Future<void> pumpShell(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PageShell(
            title: 'Subscription Plans',
            icon: Icons.workspace_premium_outlined,
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Preview')),
                OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text('Compare')),
                ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New plan')),
              ],
            ),
            child: const SizedBox(height: 100),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('does not overflow at 375px and keeps every action on screen',
        (tester) async {
      await pumpShell(tester, const Size(375, 812));

      // The overflow Flutter reported in the browser ("RIGHT OVERFLOWED BY 313
      // PIXELS") surfaces here as a layout exception.
      expect(tester.takeException(), isNull);

      // The consequence that made it a blocker rather than a cosmetic issue:
      // Compare and New plan were pushed off-screen and became unclickable.
      for (final label in ['Preview', 'Compare', 'New plan']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.right, lessThanOrEqualTo(375),
            reason: '"$label" must stay within the viewport');
        expect(rect.left, greaterThanOrEqualTo(0));
      }
    });

    testWidgets('still lays out on one row on a desktop width', (tester) async {
      await pumpShell(tester, const Size(1512, 945));
      expect(tester.takeException(), isNull);

      // Title and actions share a row: the actions sit to the right of the title.
      final title = tester.getRect(find.text('Subscription Plans'));
      final action = tester.getRect(find.text('Preview'));
      expect(action.left, greaterThan(title.right));
    });
  });

  group('Capacity row (QA: capacity value clipped at mobile width)', () {
    setUp(() {
      Get.testMode = true;
      Get.put<SubscriptionController>(_Offline());
    });
    tearDown(Get.reset);

    testWidgets('the capacity number field stays wide enough to read its value',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        GetMaterialApp(home: Scaffold(body: SubscriptionPlanDialog())),
      );
      await tester.pumpAndSettle();

      // In the browser at 375px, "50" rendered as "5" and "100" as "1" — the
      // founder could not read the capacity they had set. Found by hint text so
      // the assertion survives the row switching to a stacked layout.
      final fields = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '0');
      expect(fields, findsNWidgets(PlanResource.values.length));

      for (var i = 0; i < PlanResource.values.length; i++) {
        final w = tester.getSize(fields.at(i)).width;
        expect(w, greaterThanOrEqualTo(72),
            reason:
                'a 3-4 digit capacity must be legible; row $i was ${w}px wide');
      }

      // The whole dialog must lay out cleanly at this width. flutter_test uses a
      // fixed-width test font wider than the shipped one, so this also proves
      // the layout has real slack rather than only just fitting.
      expect(tester.takeException(), isNull);
    });
  });
}
