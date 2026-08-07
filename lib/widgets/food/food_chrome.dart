import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/console/console_chrome.dart';
import '../../models/global_food_model.dart';

export '../../core/widgets/console/console_chrome.dart';

/// FOOD PLATFORM — the console's shared vocabulary.
///
/// Every status, badge, empty state and error state in the Global Food Database
/// is rendered by exactly one of these. That is the point: a CMS where an
/// archived food looks one way in the list and another in the detail view
/// teaches the curator that the interface cannot be trusted, and at 50,000 rows
/// trust is the whole product.
///
/// The GENERIC pieces now live in `core/widgets/console/console_chrome.dart`,
/// shared with the Global Exercise Library — nothing about a pill, a card or an
/// error state is food-specific, and a second copy would drift. The names below
/// are UNCHANGED aliases, so every existing food call site compiles and behaves
/// identically. What remains defined here is what genuinely is food: the
/// editorial-status pill, the verification badge, and the usage sentence.

/// A small labelled pill. The console's only status affordance.
typedef FoodPill = ConsolePill;

/// A labelled number. The console's only way to show a metric.
typedef FoodStat = ConsoleStat;

/// The console's single empty state.
typedef FoodEmptyState = ConsoleEmptyState;

/// The console's single error state.
typedef FoodErrorState = ConsoleErrorState;

/// A shimmer-free skeleton row, the same height as a real one.
typedef FoodSkeletonRow = ConsoleSkeletonRow;

/// A titled card. The console's only container.
typedef FoodCard = ConsoleCard;

/// A selectable chip. Used for every filter in the console.
typedef FoodChip = ConsoleChip;

/// The editorial status of a food, rendered identically everywhere.
class FoodStatusPill extends StatelessWidget {
  final String status;
  const FoodStatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return switch (status) {
      'draft' => FoodPill(
        label: 'Draft',
        color: p.textMuted,
        icon: Icons.edit_note,
      ),
      'archived' => FoodPill(
        label: 'Archived',
        color: p.error,
        icon: Icons.archive_outlined,
      ),
      _ => FoodPill(
        label: 'Published',
        color: p.success,
        icon: Icons.public,
      ),
    };
  }
}

/// The curation badge. `official` is the platform's own seal and the only one
/// an organization can never award itself.
class FoodVerificationPill extends StatelessWidget {
  final String verification;
  const FoodVerificationPill(this.verification, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return switch (verification) {
      'official' => FoodPill(
        label: 'Official',
        color: p.accent,
        icon: Icons.verified,
      ),
      'verified' => FoodPill(
        label: 'Verified',
        color: p.success,
        icon: Icons.check_circle_outline,
      ),
      _ => FoodPill(
        label: 'Unverified',
        color: p.textMuted,
        icon: Icons.help_outline,
      ),
    };
  }
}

/// A short, human date. Absolute dates are unreadable in a busy audit trail
/// and relative ones are ambiguous past a week, so this switches at a week.
String foodWhen(DateTime? at) => consoleWhen(at);

/// A one-line summary of how widely a food is used.
String foodUsageSummary(FoodUsage? usage) {
  if (usage == null) return 'Usage not measured';
  if (usage.isUnused) return 'Not used in any plan';
  final orgs = usage.organizations;
  return '${usage.plans} plan${usage.plans == 1 ? '' : 's'} · '
      '$orgs org${orgs == 1 ? '' : 's'} · '
      '${usage.members} member${usage.members == 1 ? '' : 's'}'
      '${usage.truncated ? '+' : ''}';
}
