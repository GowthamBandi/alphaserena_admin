// lib/core/validation/plan_validation.dart
//
// Pure, dependency-free validation for the commercial plan editor. Kept out of
// the controller so it is unit-testable and so every "fail safely" rule is in
// one auditable place. Returns a list of human-readable errors (empty = valid).

import '../../models/subscription_plan_model.dart';
import 'capability_dependencies.dart';

/// A minimal snapshot of another existing plan, used for cross-plan uniqueness
/// checks (name / sort order / badge).
class PlanPeer {
  final String docId;
  final String name;
  final String badge;
  final int sortOrder;
  final bool isActive;

  const PlanPeer({
    required this.docId,
    required this.name,
    required this.badge,
    required this.sortOrder,
    required this.isActive,
  });
}

class PlanValidation {
  /// Validates a plan about to be saved. `selfDocId` is empty when creating.
  /// `limits` are DECODED values (SubscriptionPlanModel.unlimited == -1).
  static List<String> validate({
    required String name,
    required String badge,
    required int sortOrder,
    required bool active,
    required bool featured,
    required BillingPeriod billingPeriod,
    required int durationMonths,
    required double monthlyPrice,
    required double yearlyPrice,
    required Map<PlanResource, int> limits,
    required Map<String, bool> capabilities,
    required List<PlanPeer> peers,
    required String selfDocId,
  }) {
    final errors = <String>[];
    final trimmedName = name.trim();
    final trimmedBadge = badge.trim();

    // ── Identity ──────────────────────────────────────────────────────────
    if (trimmedName.isEmpty) {
      errors.add('Plan name is required.');
    } else {
      final dupName = peers.any((p) =>
          p.docId != selfDocId &&
          p.name.trim().toLowerCase() == trimmedName.toLowerCase());
      if (dupName) errors.add('A plan named "$trimmedName" already exists.');
    }

    if (sortOrder < 0) {
      errors.add('Sort order cannot be negative.');
    } else if (active) {
      // Sort order + badge only need to be unique among VISIBLE (active) plans.
      final dupOrder = peers.any((p) =>
          p.docId != selfDocId && p.isActive && p.sortOrder == sortOrder);
      if (dupOrder) {
        final other =
            peers.firstWhere((p) => p.docId != selfDocId && p.isActive && p.sortOrder == sortOrder);
        errors.add('Sort order $sortOrder is already used by "${other.name}".');
      }
    }

    if (trimmedBadge.isNotEmpty && active) {
      final dupBadge = peers.any((p) =>
          p.docId != selfDocId &&
          p.isActive &&
          p.badge.trim().toLowerCase() == trimmedBadge.toLowerCase());
      if (dupBadge) {
        errors.add('The badge "$trimmedBadge" is already used by another live plan.');
      }
    }

    // ── Visibility / status ───────────────────────────────────────────────
    if (featured && !active) {
      errors.add('A featured plan must be active — you cannot feature a hidden plan.');
    }

    // ── Duration ──────────────────────────────────────────────────────────
    if (durationMonths <= 0) {
      errors.add('The billing term must be at least 1 month.');
    }

    // ── Pricing ───────────────────────────────────────────────────────────
    if (monthlyPrice < 0 || yearlyPrice < 0) {
      errors.add('Prices cannot be negative.');
    }
    // The backend rejects a plan whose live (charged) price is not > 0.
    final livePrice =
        billingPeriod == BillingPeriod.yearly ? yearlyPrice : monthlyPrice;
    if (!(livePrice > 0)) {
      errors.add(
          'Enter a valid ${billingPeriod.label.toLowerCase()} price greater than 0.');
    }
    // A yearly price that is not cheaper than 12× monthly earns no savings — a
    // hard error only if it is strictly more expensive (almost always a typo).
    if (monthlyPrice > 0 && yearlyPrice > 0 && yearlyPrice > monthlyPrice * 12) {
      errors.add(
          'The yearly price is higher than 12 months at the monthly rate — customers would pay more to commit annually.');
    }
    // BOTH prices are now genuinely charged: the buyer picks a term in the app
    // and the backend charges the matching field from this ONE plan. Until
    // that change the non-default term's price was inert data, so a typo in it
    // cost nothing. A year priced below a single month is never intentional —
    // and it would be sold at that price to everyone who toggled Yearly.
    if (monthlyPrice > 0 && yearlyPrice > 0 && yearlyPrice < monthlyPrice) {
      errors.add(
          'The yearly price is lower than a single month — customers could buy '
          'a whole year for less than one month.');
    }

    // ── Limits ────────────────────────────────────────────────────────────
    for (final entry in limits.entries) {
      final r = entry.key;
      final v = entry.value;
      if (v == SubscriptionPlanModel.unlimited) continue; // unlimited is valid
      if (v < 0) {
        errors.add('${r.label} limit cannot be negative.');
        continue;
      }
      // A finite 0 is rejected for EVERY resource: 0 means "not included /
      // blocked" across the whole platform, which is almost never what a
      // founder intends to author. This also forces an EXPLICIT choice when
      // editing a legacy doc that carries a 0/missing limit (retired
      // 0-means-unlimited era) — the founder must pick Unlimited or a real
      // capacity of at least 1.
      if (v == 0) {
        errors.add(
            '${r.label} must be at least 1 (or set it to Unlimited). A value of 0 blocks the feature entirely.');
      }
    }

    // ── Capability ↔ capacity dependencies ────────────────────────────────
    // Delegated to the single data-driven dependency engine so this rule set
    // lives in exactly one place (also consumed by the editor for auto-disable).
    for (final rule in CapabilityDependencies.violations(capabilities, limits)) {
      errors.add(rule.explanation);
    }

    return errors;
  }
}
