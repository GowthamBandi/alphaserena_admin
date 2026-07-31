// lib/core/validation/capability_dependencies.dart
//
// Data-driven capability dependency engine — the single owner of every
// "capability X needs capacity Y" business rule. The plan editor uses it to
// auto-disable impossible options with a human explanation, and
// PlanValidation uses the same rules at save time, so the logic exists exactly
// once and impossible plans can never be authored.
//
// The catalog now contains ONLY enforced capabilities (see PlanCapabilities),
// so the rule set is correspondingly small:
//   • Client Progress Tracking needs Active Clients capacity — no clients, no
//     progress to track. (Under the shared limit contract: 0 = not included,
//     Unlimited = the big sentinel.)

import '../../models/subscription_plan_model.dart';

class CapabilityRule {
  /// The capability slug this rule constrains.
  final String capability;

  /// The capacity that must support it.
  final PlanResource resource;

  /// Whether the given decoded limit value satisfies the rule.
  final bool Function(int limitValue) isSatisfied;

  /// Human explanation shown when the rule blocks the capability. Business
  /// language, no internal names.
  final String explanation;

  const CapabilityRule({
    required this.capability,
    required this.resource,
    required this.isSatisfied,
    required this.explanation,
  });
}

class CapabilityDependencies {
  static bool _unlimitedOrAtLeast(int v, int min) =>
      v == SubscriptionPlanModel.unlimited || v >= min;

  static final List<CapabilityRule> rules = [
    CapabilityRule(
      capability: PlanCapabilities.progress,
      resource: PlanResource.activeClients,
      isSatisfied: (v) => _unlimitedOrAtLeast(v, 1),
      explanation:
          'Client Progress Tracking needs Active Clients capacity to track.',
    ),
  ];

  /// The first rule blocking [capability] under [limits], or null when the
  /// capability is currently possible.
  static CapabilityRule? blockerFor(
    String capability,
    Map<PlanResource, int> limits,
  ) {
    for (final rule in rules) {
      if (rule.capability != capability) continue;
      final v = limits[rule.resource] ?? SubscriptionPlanModel.unlimited;
      if (!rule.isSatisfied(v)) return rule;
    }
    return null;
  }

  /// Every violation among ENABLED capabilities — used by save-time validation.
  static List<CapabilityRule> violations(
    Map<String, bool> capabilities,
    Map<PlanResource, int> limits,
  ) {
    final out = <CapabilityRule>[];
    for (final rule in rules) {
      if (capabilities[rule.capability] != true) continue;
      final v = limits[rule.resource] ?? SubscriptionPlanModel.unlimited;
      if (!rule.isSatisfied(v)) out.add(rule);
    }
    return out;
  }
}
