import 'package:alphaserena_admin_portel/core/validation/plan_validation.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Locks the "everything must fail safely" contract for the plan editor, and the
// shared "Unlimited" encoding that the backend depends on.

Map<PlanResource, int> _limits({
  int team = 5,
  int clients = 100,
  int workoutPlans = 50,
  int dietPlans = 50,
  int exercises = 500,
}) =>
    {
      PlanResource.teamMembers: team,
      PlanResource.activeClients: clients,
      PlanResource.workoutPlans: workoutPlans,
      PlanResource.dietPlans: dietPlans,
      PlanResource.exerciseLibrary: exercises,
    };

Map<String, bool> _caps({bool progress = false}) => {
      for (final s in PlanCapabilities.slugs) s: false,
      PlanCapabilities.progress: progress,
    };

List<String> _run({
  String name = 'Pro',
  String badge = '',
  int sortOrder = 1,
  bool active = true,
  bool featured = false,
  BillingPeriod period = BillingPeriod.monthly,
  int durationMonths = 1,
  double monthly = 500,
  double yearly = 5000,
  Map<PlanResource, int>? limits,
  Map<String, bool>? caps,
  List<PlanPeer> peers = const [],
  String selfDocId = '',
}) =>
    PlanValidation.validate(
      name: name,
      badge: badge,
      sortOrder: sortOrder,
      active: active,
      featured: featured,
      billingPeriod: period,
      durationMonths: durationMonths,
      monthlyPrice: monthly,
      yearlyPrice: yearly,
      limits: limits ?? _limits(),
      capabilities: caps ?? _caps(),
      peers: peers,
      selfDocId: selfDocId,
    );

void main() {
  test('a well-formed plan passes', () {
    expect(_run(), isEmpty);
  });

  test('empty name fails', () {
    expect(_run(name: '   '), contains('Plan name is required.'));
  });

  test('duplicate name (case-insensitive) fails', () {
    final peers = [
      const PlanPeer(
          docId: 'x', name: 'pro', badge: '', sortOrder: 9, isActive: true),
    ];
    expect(_run(name: 'PRO', peers: peers, sortOrder: 1),
        contains('A plan named "PRO" already exists.'));
  });

  test('editing self does not collide with own name', () {
    final peers = [
      const PlanPeer(
          docId: 'me', name: 'Pro', badge: '', sortOrder: 1, isActive: true),
    ];
    expect(_run(name: 'Pro', peers: peers, selfDocId: 'me'), isEmpty);
  });

  test('live monthly price must be > 0', () {
    expect(_run(period: BillingPeriod.monthly, monthly: 0),
        contains('Enter a valid monthly price greater than 0.'));
  });

  test('yearly plan ignores a zero monthly price but needs a yearly price', () {
    expect(_run(period: BillingPeriod.yearly, monthly: 0, yearly: 4000),
        isEmpty);
    expect(_run(period: BillingPeriod.yearly, yearly: 0),
        contains('Enter a valid yearly price greater than 0.'));
  });

  test('negative prices fail', () {
    expect(_run(monthly: -1), contains('Prices cannot be negative.'));
  });

  test('yearly dearer than 12x monthly fails', () {
    final errs = _run(monthly: 500, yearly: 7000);
    expect(errs.any((e) => e.contains('higher than 12 months')), isTrue);
  });

  // BOTH prices are charged now — the buyer picks a term in the app and the
  // backend charges the matching field from this one plan. A typo in the
  // non-default term used to be inert; it is now a live price.
  test('a year priced below a single month is rejected', () {
    final errs = _run(period: BillingPeriod.monthly, monthly: 999, yearly: 50);
    expect(errs.any((e) => e.contains('lower than a single month')), isTrue,
        reason: 'buyers could get a whole year for 50 rupees');
  });

  test('the floor applies whichever term is the default', () {
    final errs = _run(period: BillingPeriod.yearly, monthly: 999, yearly: 50);
    expect(errs.any((e) => e.contains('lower than a single month')), isTrue);
  });

  test('a genuine annual discount still passes', () {
    // 10 months' worth for a year — a normal, intended incentive.
    expect(_run(monthly: 999, yearly: 9990), isEmpty);
  });

  test('yearly equal to monthly is allowed (no saving, but not a typo)', () {
    expect(_run(monthly: 999, yearly: 999), isEmpty);
  });

  test('an unpriced term is not a typo — it just is not offered', () {
    expect(_run(period: BillingPeriod.monthly, monthly: 999, yearly: 0),
        isEmpty);
  });

  test('featured but inactive fails', () {
    expect(_run(active: false, featured: true, monthly: 500),
        contains('A featured plan must be active — you cannot feature a hidden plan.'));
  });

  test('duplicate sort order among active plans fails', () {
    final peers = [
      const PlanPeer(
          docId: 'x', name: 'Other', badge: '', sortOrder: 2, isActive: true),
    ];
    expect(_run(sortOrder: 2, peers: peers).any((e) => e.contains('Sort order 2')),
        isTrue);
  });

  test('duplicate sort order is allowed when the other plan is inactive', () {
    final peers = [
      const PlanPeer(
          docId: 'x', name: 'Other', badge: '', sortOrder: 2, isActive: false),
    ];
    expect(_run(sortOrder: 2, peers: peers), isEmpty);
  });

  test('duplicate badge among active plans fails', () {
    final peers = [
      const PlanPeer(
          docId: 'x',
          name: 'Other',
          badge: 'Most popular',
          sortOrder: 9,
          isActive: true),
    ];
    expect(
        _run(badge: 'most popular', peers: peers)
            .any((e) => e.contains('badge')),
        isTrue);
  });

  test('progress capability with no client capacity fails', () {
    final errs = _run(
      limits: _limits(clients: 0),
      caps: _caps(progress: true),
    );
    expect(errs.any((e) => e.contains('Client Progress Tracking')), isTrue);
  });

  test('progress capability is fine with unlimited clients', () {
    final errs = _run(
      limits: _limits(clients: SubscriptionPlanModel.unlimited),
      caps: _caps(progress: true),
    );
    expect(errs, isEmpty);
  });

  test('negative limit fails', () {
    expect(_run(limits: _limits(team: -5)),
        contains('Team Members limit cannot be negative.'));
  });

  test('team members = 0 fails (would block the feature)', () {
    final errs = _run(limits: _limits(team: 0));
    expect(errs.any((e) => e.contains('Team Members must be at least 1')), isTrue);
  });

  test('team members Unlimited passes', () {
    expect(_run(limits: _limits(team: SubscriptionPlanModel.unlimited)), isEmpty);
  });

  test('a finite 0 fails for EVERY resource (0 = not included and a stored '
      'legacy 0 would silently flip to Unlimited on reload)', () {
    final errs = _run(limits: _limits(clients: 0, workoutPlans: 0));
    expect(errs.any((e) => e.contains('Active Clients must be at least 1')),
        isTrue);
    expect(errs.any((e) => e.contains('Workout Programs must be at least 1')),
        isTrue);
  });

  test('swept-resource Unlimited passes', () {
    expect(
        _run(
            limits: _limits(
                clients: SubscriptionPlanModel.unlimited,
                workoutPlans: SubscriptionPlanModel.unlimited)),
        isEmpty);
  });

  test('a positive term is required', () {
    expect(_run(durationMonths: 0),
        contains('The billing term must be at least 1 month.'));
  });
}
