import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:alphaserena_admin_portel/widgets/plan_comparison_dialog.dart';
import 'package:alphaserena_admin_portel/widgets/trainer_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Phase-10 UI verification for the two new pure catalog surfaces — they must
// build without overflow/exceptions and mirror the price/best-value framing.

SubscriptionPlanModel _plan({
  required String name,
  required double monthly,
  required double yearly,
  int months = 1,
  bool featured = false,
  int team = 5,
}) =>
    SubscriptionPlanModel(
      id: name,
      docId: name,
      planName: name,
      sortOrder: 1,
      isActive: true,
      featured: featured,
      monthlyPrice: monthly,
      yearlyPrice: yearly,
      durationMonths: months,
      limits: {
        for (final r in PlanResource.values) r: 10,
        PlanResource.teamMembers: team,
      },
      capabilities: {
        for (final s in PlanCapabilities.slugs) s: false,
        PlanCapabilities.progress: true,
      },
      points: const ['Priority support'],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  final plans = [
    _plan(name: 'Starter', monthly: 999, yearly: 9990, featured: false),
    _plan(name: 'Professional', monthly: 1999, yearly: 17990, featured: true),
    _plan(name: 'Enterprise', monthly: 4999, yearly: 44990, months: 12),
  ];

  testWidgets('comparison dialog renders every plan and section', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pump(tester, PlanComparisonDialog(plans: plans));

    expect(find.text('Compare plans'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    expect(find.text('Professional'), findsOneWidget);
    expect(find.text('Enterprise'), findsOneWidget);
    // Business-language row labels appear.
    expect(find.text('Team Members'), findsOneWidget);
    expect(find.text('Client Progress Tracking'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trainer preview renders cards without overflow', (tester) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pump(tester, TrainerPreviewDialog(plans: plans));

    expect(find.text('Trainer preview'), findsOneWidget);
    expect(find.text('Starter'), findsOneWidget);
    // Cheapest per-month plan wears BEST VALUE (Starter: 999/mo vs 1999/mo vs
    // 44990/12 ≈ 3749/mo).
    expect(find.text('BEST VALUE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview with a single plan shows no BEST VALUE badge', (tester) async {
    tester.view.physicalSize = const Size(700, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await _pump(tester, TrainerPreviewDialog(plans: [plans.first]));
    expect(find.text('BEST VALUE'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
