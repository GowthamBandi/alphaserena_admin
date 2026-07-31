import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:alphaserena_admin_portel/widgets/plan_live_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Widget tests for the designer's live buyer preview (PlanLivePreview). The
// full SubscriptionPlanDialog needs SubscriptionController, which constructs
// FirebaseFirestore.instance — not instantiable in a plain widget test — so
// the preview is tested standalone with explicit values (it was designed to
// accept plain values for exactly this reason).

const _u = SubscriptionPlanModel.unlimited;

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 360, child: child),
        ),
      ),
    );

PlanLivePreview _preview({
  String name = 'Pro',
  String badge = 'Popular',
  PlanStatus status = PlanStatus.published,
  bool featured = false,
  int termMonths = 1,
  double monthly = 999,
  double yearly = 9990,
  Map<PlanResource, int>? limits,
  Map<String, bool>? capabilities,
  List<String> customPoints = const [],
  List<double> peerPerMonth = const [],
}) =>
    PlanLivePreview(
      planName: name,
      badge: badge,
      status: status,
      featured: featured,
      termMonths: termMonths,
      monthlyPrice: monthly,
      yearlyPrice: yearly,
      limits: limits ??
          {
            PlanResource.teamMembers: 5,
            PlanResource.activeClients: 100,
            PlanResource.workoutPlans: 20,
            PlanResource.dietPlans: 10,
            PlanResource.exerciseLibrary: _u,
          },
      capabilities: capabilities ?? {PlanCapabilities.progress: true},
      customPoints: customPoints,
      peerPerMonth: peerPerMonth,
    );

void main() {
  testWidgets('renders name, price hero and status strip — badge is NOT shown',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(_preview()));
    await tester.pumpAndSettle();

    expect(find.text('Pro'), findsOneWidget);
    // TrainerHQ never renders the badge field — the buyer card must not
    // either; a console-only note explains why.
    expect(find.text('Popular'), findsNothing);
    expect(
        find.text(
            "Badge and Featured organize this console — buyers don't see them."),
        findsOneWidget);
    expect(find.text('₹999'), findsOneWidget);
    expect(find.text('Published — live to buyers'), findsOneWidget);
    expect(find.text('1 Month'), findsOneWidget);
    // Monthly term: no per-month line, no savings framing.
    expect(find.textContaining('/mo'), findsNothing);
    expect(find.textContaining('save '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'yearly term shows per-month price; savings/BEST VALUE only appear '
      'against published peers (TrainerHQ cross-catalog math)',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // Alone in the catalog: per-month shows, but no invented savings claim.
    await tester
        .pumpWidget(_wrap(_preview(termMonths: 12, monthly: 1000, yearly: 9600)));
    await tester.pumpAndSettle();
    expect(find.text('₹9,600'), findsOneWidget);
    expect(find.text('₹800/mo'), findsOneWidget);
    expect(find.textContaining('save '), findsNothing);
    expect(find.text('BEST VALUE'), findsNothing);

    // A monthly peer at ₹1,000/mo exists: baseline 1000, this plan 800/mo →
    // save 20% and BEST VALUE, exactly as TrainerHQ computes it.
    await tester.pumpWidget(_wrap(_preview(
        termMonths: 12,
        monthly: 1000,
        yearly: 9600,
        peerPerMonth: const [1000])));
    await tester.pumpAndSettle();
    expect(find.text('12 Months  ·  save 20% / month'), findsOneWidget);
    expect(find.text('BEST VALUE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a costlier plan than its peers shows no savings or BEST VALUE',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // This yearly plan is ₹1,000/mo; a peer sells at ₹800/mo — the peer is
    // the best value, so this card must not claim anything.
    await tester.pumpWidget(_wrap(_preview(
        termMonths: 12,
        monthly: 1200,
        yearly: 12000,
        peerPerMonth: const [800])));
    await tester.pumpAndSettle();
    expect(find.text('BEST VALUE'), findsNothing);
    // Savings vs the costliest per-month (itself = baseline) is 0 → hidden.
    expect(find.textContaining('save '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'renders ONLY the founder\'s highlights — capacity and capabilities '
      'generate no bullets', (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(_preview(
        customPoints: ['Priority support', 'priority support', '  '])));
    await tester.pumpAndSettle();

    // The fixture has 5 trainer seats, 100 clients and progress enabled —
    // none of that may appear as a bullet.
    expect(find.text('5 trainer seats'), findsNothing);
    expect(find.text('Up to 100 active clients'), findsNothing);
    expect(find.text('Client progress tracking'), findsNothing);
    // The founder's line appears exactly once (duplicate + blank sanitized).
    expect(find.text('Priority support'), findsOneWidget);
    // ...while capacity is still fully stated by the chips.
    expect(find.text('Clients '), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no highlights → the card says so and shows no bullets',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(_preview(customPoints: const [])));
    await tester.pumpAndSettle();

    expect(find.text('No highlights yet — add them in the Highlights section.'),
        findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limit chips use TrainerHQ wording and show Unlimited',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(_preview()));
    await tester.pumpAndSettle();

    expect(find.text('Trainers '), findsOneWidget);
    expect(find.text('Clients '), findsOneWidget);
    expect(find.text('Exercises '), findsOneWidget);
    // exerciseLibrary is unlimited in the fixture: the chip carries it.
    expect(find.text('Unlimited'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden and archived status strips', (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(_preview(status: PlanStatus.hidden)));
    await tester.pumpAndSettle();
    expect(find.text("Hidden — buyers won't see this"), findsOneWidget);

    await tester.pumpWidget(_wrap(_preview(status: PlanStatus.archived)));
    await tester.pumpAndSettle();
    expect(find.text('Archived — retired from sale'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty name falls back to placeholder; no badge/featured → no console note',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrap(_preview(
        name: '   ',
        badge: '',
        limits: const {},
        capabilities: const {},
        customPoints: const [])));
    await tester.pumpAndSettle();

    expect(find.text('Untitled plan'), findsOneWidget);
    expect(
        find.text('No highlights yet — add them in the Highlights section.'),
        findsOneWidget);
    expect(
        find.text(
            "Badge and Featured organize this console — buyers don't see them."),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
