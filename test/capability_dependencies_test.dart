import 'package:alphaserena_admin_portel/core/validation/capability_dependencies.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter_test/flutter_test.dart';

// The single source of "capability needs capacity" rules — used by both the
// editor (auto-disable) and save-time validation. The catalog is progress-only
// (only enforced capabilities are authorable), so the rule set is exactly:
// Client Progress Tracking needs Active Clients capacity.

const _u = SubscriptionPlanModel.unlimited;

Map<PlanResource, int> _limits({int clients = 100}) => {
      PlanResource.teamMembers: 5,
      PlanResource.activeClients: clients,
      PlanResource.workoutPlans: 50,
      PlanResource.dietPlans: 50,
      PlanResource.exerciseLibrary: 100,
    };

void main() {
  test('Progress is blocked when Active Clients is 0 (not included)', () {
    final blocker = CapabilityDependencies.blockerFor(
        PlanCapabilities.progress, _limits(clients: 0));
    expect(blocker, isNotNull);
    expect(blocker!.resource, PlanResource.activeClients);
    expect(blocker.explanation, contains('Active Clients'));
  });

  test('Progress is allowed with at least one client and with unlimited', () {
    expect(
        CapabilityDependencies.blockerFor(
            PlanCapabilities.progress, _limits(clients: 1)),
        isNull);
    expect(
        CapabilityDependencies.blockerFor(
            PlanCapabilities.progress, _limits(clients: _u)),
        isNull);
  });

  test('a missing Active Clients entry (no information) does not block', () {
    final limits = _limits()..remove(PlanResource.activeClients);
    expect(
        CapabilityDependencies.blockerFor(PlanCapabilities.progress, limits),
        isNull);
  });

  test('violations only reports ENABLED capabilities that conflict', () {
    // Disabled progress is ignored even when clients = 0.
    expect(
        CapabilityDependencies.violations(
            {PlanCapabilities.progress: false}, _limits(clients: 0)),
        isEmpty);
    // Enabled + clients 0 → exactly one violation.
    final v = CapabilityDependencies.violations(
        {PlanCapabilities.progress: true}, _limits(clients: 0));
    expect(v.length, 1);
    expect(v.single.capability, PlanCapabilities.progress);
    // Enabled + capacity present → no violation.
    expect(
        CapabilityDependencies.violations(
            {PlanCapabilities.progress: true}, _limits(clients: 10)),
        isEmpty);
  });

  test('every capability slug has a stable label and a description', () {
    for (final slug in PlanCapabilities.slugs) {
      expect(PlanCapabilities.labelOf(slug), isNotEmpty);
      expect(PlanCapabilities.descriptions[slug], isNotNull);
    }
  });
}
