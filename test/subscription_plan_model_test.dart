import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Locks the backend-facing plan doc contract: the single cross-repo
// "unlimited" sentinel encoding (big int for EVERY resource — the retired
// 0-means-unlimited swept encoding locked TrainerHQ users out), the
// billing-period price/term mirror, fromMap∘toMap round-trip, and the
// customPoints (founder custom lines) contract with its legacy fallback.

SubscriptionPlanModel _plan({
  int months = 1,
  double monthly = 500,
  double yearly = 5000,
  Map<PlanResource, int>? limits,
  Map<String, bool>? caps,
  List<String> points = const ['Fast support'],
  List<String> customPoints = const [],
}) {
  return SubscriptionPlanModel(
    id: 'p1',
    docId: 'p1',
    planName: 'Pro',
    description: 'desc',
    badge: 'Popular',
    sortOrder: 3,
    isActive: true,
    featured: true,
    monthlyPrice: monthly,
    yearlyPrice: yearly,
    durationMonths: months,
    limits: limits ??
        {
          PlanResource.teamMembers: 5,
          PlanResource.activeClients: 100,
          PlanResource.workoutPlans: 50,
          PlanResource.dietPlans: 40,
          PlanResource.exerciseLibrary: 500,
        },
    capabilities: caps ??
        {
          for (final s in PlanCapabilities.slugs) s: false,
          PlanCapabilities.progress: true,
        },
    points: points,
    customPoints: customPoints,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
  );
}

void main() {
  test('a monthly plan mirrors the monthly price and 1 month term', () {
    final m = _plan(months: 1, monthly: 499).toMap();
    expect(m['price'], 499);
    expect(m['months'], 1);
    expect(m['duration'], '1 Month');
  });

  test('a yearly plan mirrors the yearly price and 12 month term', () {
    final m = _plan(months: 12, yearly: 4999).toMap();
    expect(m['price'], 4999);
    expect(m['months'], 12);
    expect(m['duration'], '12 Months');
  });

  test('UNLIMITED encodes to the shared big sentinel for EVERY resource — '
      'NEVER 0 (TrainerHQ blocks creation at limit <= 0)', () {
    final m = _plan(limits: {
      for (final r in PlanResource.values) r: SubscriptionPlanModel.unlimited,
    }).toMap();
    final limits = m['limits'] as Map;
    for (final key in [
      'trainers',
      'clients',
      'workoutPlans',
      'dietPlans',
      'workouts',
      'exerciseLibrary',
    ]) {
      expect(
        limits[key],
        greaterThanOrEqualTo(SubscriptionPlanModel.unlimitedThreshold),
        reason: '$key must carry the unlimited sentinel',
      );
    }
  });

  test('a stored 0 decodes as 0 for EVERY resource — including swept ones '
      '(uniform decode; the console shows what TrainerHQ enforces)', () {
    final legacy = {
      'title': 'Old Zeroes',
      'price': 999,
      'months': 1,
      'limits': {'trainers': 3, 'clients': 0, 'workoutPlans': 0},
      'isActive': true,
    };
    final p = SubscriptionPlanModel.fromMap(legacy, 'old1');
    expect(p.limitOf(PlanResource.activeClients), 0);
    expect(p.limitOf(PlanResource.workoutPlans), 0);
    expect(p.isUnlimited(PlanResource.activeClients), isFalse);
    expect(p.isUnlimited(PlanResource.workoutPlans), isFalse);
    // Missing fields also decode as 0 — never silently escalated to the
    // unlimited sentinel.
    expect(p.limitOf(PlanResource.dietPlans), 0);
    final saved = p.toMap()['limits'] as Map;
    expect(saved['clients'], 0);
    expect(saved['workoutPlans'], 0);
    expect(saved['dietPlans'], 0);
  });

  test('unlimited threshold boundary: 99,999,999 is finite; '
      '100,000,000 decodes as unlimited', () {
    final doc = {
      'title': 'Boundary',
      'price': 999,
      'months': 1,
      'limits': {'clients': 99999999, 'workoutPlans': 100000000},
      'isActive': true,
    };
    final p = SubscriptionPlanModel.fromMap(doc, 'b1');
    expect(p.limitOf(PlanResource.activeClients), 99999999);
    expect(p.isUnlimited(PlanResource.activeClients), isFalse);
    expect(p.isUnlimited(PlanResource.workoutPlans), isTrue);
  });

  test('flat limit mirrors equal the nested limits in toMap', () {
    final m = _plan(limits: {
      PlanResource.teamMembers: SubscriptionPlanModel.unlimited,
      PlanResource.activeClients: 250,
      PlanResource.workoutPlans: 30,
      PlanResource.dietPlans: 40,
      PlanResource.exerciseLibrary: 500,
    }).toMap();
    final nested = m['limits'] as Map;
    expect(m['maxTrainers'], nested['trainers']);
    expect(m['maxClients'], nested['clients']);
    expect(m['maxWorkoutPlans'], nested['workoutPlans']);
    expect(m['maxWorkouts'], nested['workouts']);
    expect(m['maxDietPlans'], nested['dietPlans']);
    expect(nested['exerciseLibrary'], nested['workouts']); // alias mirror
  });

  test('trainers = 0 stays 0 (no seats), distinct from unlimited', () {
    final m = _plan(limits: {
      PlanResource.teamMembers: 0,
      PlanResource.activeClients: 10,
      PlanResource.workoutPlans: 10,
      PlanResource.dietPlans: 10,
      PlanResource.exerciseLibrary: 10,
    }).toMap();
    expect((m['limits'] as Map)['trainers'], 0);
  });

  test('round-trips unlimited, zero, and finite values correctly', () {
    final original = _plan(
      months: 12,
      limits: {
        PlanResource.teamMembers: SubscriptionPlanModel.unlimited,
        PlanResource.activeClients: 250,
        PlanResource.workoutPlans: SubscriptionPlanModel.unlimited,
        PlanResource.dietPlans: 40,
        PlanResource.exerciseLibrary: 999,
      },
    );
    final back = SubscriptionPlanModel.fromMap(original.toMap(), 'p1');

    expect(back.limitOf(PlanResource.teamMembers), SubscriptionPlanModel.unlimited);
    expect(back.limitOf(PlanResource.activeClients), 250);
    expect(back.limitOf(PlanResource.workoutPlans), SubscriptionPlanModel.unlimited);
    expect(back.limitOf(PlanResource.dietPlans), 40);
    expect(back.limitOf(PlanResource.exerciseLibrary), 999);
    expect(back.billingPeriod, BillingPeriod.yearly);
    expect(back.monthlyPrice, 500);
    expect(back.yearlyPrice, 5000);
    expect(back.featured, isTrue);
    expect(back.badge, 'Popular');
    expect(back.sortOrder, 3);
    expect(back.capable(PlanCapabilities.progress), isTrue);
    expect(back.yearlySavingsPct, greaterThan(0)); // 5000 < 6000
  });

  test('preserves an off-catalog legacy term through a round-trip (no collapse)', () {
    final legacy = {
      'title': 'Half-year',
      'price': 3000,
      'months': 6,
      'limits': {'trainers': 3, 'clients': 50},
      'isActive': true,
    };
    final p = SubscriptionPlanModel.fromMap(legacy, 'h1');
    expect(p.durationMonths, 6); // NOT collapsed to 1 or 12
    final round = SubscriptionPlanModel.fromMap(p.toMap(), 'h1');
    expect(round.durationMonths, 6);
    expect((p.toMap())['months'], 6);
    expect((p.toMap())['price'], 3000);
  });

  test('migrates a legacy single-price doc into the billing period', () {
    final legacy = {
      'title': 'Legacy',
      'price': 6000,
      'months': 12,
      'limits': {'trainers': 3, 'clients': 50},
      'isActive': true,
    };
    final p = SubscriptionPlanModel.fromMap(legacy, 'legacy1');
    expect(p.billingPeriod, BillingPeriod.yearly);
    expect(p.yearlyPrice, 6000);
    expect(p.price, 6000);
    expect(p.limitOf(PlanResource.teamMembers), 3);
    expect(p.limitOf(PlanResource.activeClients), 50);
  });

  test('capabilityKeys projects exactly the enabled slugs (set equality)', () {
    final m = _plan(caps: {
      for (final s in PlanCapabilities.slugs) s: false,
      PlanCapabilities.progress: true,
    }).toMap();
    final keys = (m['capabilityKeys'] as List).cast<String>().toSet();
    expect(keys, {PlanCapabilities.progress});
  });

  // ── customPoints contract ──────────────────────────────────────────────

  test('legacy doc without customPoints falls back to the whole points list',
      () {
    final legacy = {
      'title': 'Legacy',
      'price': 999,
      'months': 1,
      'points': ['Up to 50 active clients', 'Priority support'],
      'isActive': true,
    };
    final p = SubscriptionPlanModel.fromMap(legacy, 'l1');
    expect(p.customPoints, p.points);
    expect(p.customPoints, ['Up to 50 active clients', 'Priority support']);
  });

  test('a doc WITH customPoints keeps them distinct from points', () {
    final doc = {
      'title': 'V2',
      'price': 999,
      'months': 1,
      'points': ['5 trainer seats', 'Priority support'],
      'customPoints': ['Priority support'],
      'isActive': true,
    };
    final p = SubscriptionPlanModel.fromMap(doc, 'v2');
    expect(p.points, ['5 trainer seats', 'Priority support']);
    expect(p.customPoints, ['Priority support']);
  });

  test('toMap writes customPoints and round-trips it', () {
    final original = _plan(
      points: const ['5 trainer seats', 'Priority support'],
      customPoints: const ['Priority support'],
    );
    final m = original.toMap();
    expect(m['customPoints'], ['Priority support']);
    expect(m['points'], ['5 trainer seats', 'Priority support']);
    final back = SubscriptionPlanModel.fromMap(m, 'p1');
    expect(back.customPoints, ['Priority support']);
    expect(back.points, ['5 trainer seats', 'Priority support']);
  });

  // ── docId is an ADDRESS, never mirrored data ────────────────────────────
  test('docId always follows the real document id, never the stored field',
      () {
    // A doc hand-copied in the Firebase console keeps the ORIGINAL plan's
    // docId field. Every console write addresses doc(docId), so trusting the
    // field would have an edit/publish silently overwrite the other plan.
    final p = SubscriptionPlanModel.fromMap({
      'docId': 'some-other-plan',
      'planName': 'Copied plan',
      'price': 999,
      'months': 1,
    }, 'the-real-doc-id');

    expect(p.docId, 'the-real-doc-id');
    expect(p.id, 'the-real-doc-id');
    // ...and a re-save repairs the stale mirror.
    expect(p.toMap()['docId'], 'the-real-doc-id');
  });
}
