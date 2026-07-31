import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/food_errors.dart';
import '../../models/global_food_model.dart';

/// FOOD PLATFORM — the console's shared vocabulary.
///
/// Every status, badge, empty state and error state in the Global Food Database
/// is rendered by exactly one of these. That is the point: a CMS where an
/// archived food looks one way in the list and another in the detail view
/// teaches the curator that the interface cannot be trusted, and at 50,000 rows
/// trust is the whole product.

/// A small labelled pill. The console's only status affordance.
class FoodPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const FoodPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppText.body(size: 10.5).copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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

/// A labelled number. The console's only way to show a metric.
class FoodStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final String? hint;

  const FoodStat({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppText.title(size: 22).copyWith(color: color ?? p.textPrimary),
        ),
        Text(
          label,
          style: AppText.body(size: 11).copyWith(color: p.textMuted),
        ),
      ],
    );
    return hint == null ? content : Tooltip(message: hint!, child: content);
  }
}

/// The console's single empty state.
///
/// Always says WHY the list is empty and what to do next. "No results" alone
/// leaves a curator unable to tell an empty library from an over-narrow filter,
/// which is the difference between calm and a support ticket.
class FoodEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const FoodEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 32),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.10),
              borderRadius: AppRadii.smR,
            ),
            child: Icon(icon, size: 26, color: p.accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// The console's single error state.
///
/// Says WHAT broke, WHY, and HOW to fix it — and offers a retry only when
/// retrying could plausibly help. A "Try again" button in front of an
/// undeployed Cloud Function is an infinite loop dressed as an affordance,
/// and it is exactly what made the first production failure of this console
/// impossible to diagnose from the screen.
class FoodErrorState extends StatelessWidget {
  final FoodConsoleError error;
  final VoidCallback onRetry;

  const FoodErrorState({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tone = error.needsDeploy ? p.accent : p.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: tone.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(
            switch (error.kind) {
              FoodErrorKind.notDeployed => Icons.cloud_upload_outlined,
              FoodErrorKind.missingIndex => Icons.playlist_add_outlined,
              FoodErrorKind.permission => Icons.lock_outline,
              FoodErrorKind.offline => Icons.wifi_off_outlined,
              _ => Icons.error_outline,
            },
            size: 30,
            color: tone,
          ),
          const SizedBox(height: 14),
          Text(
            switch (error.kind) {
              FoodErrorKind.notDeployed => 'Backend not deployed',
              FoodErrorKind.missingIndex => 'A Firestore index is missing',
              FoodErrorKind.permission => 'Not authorized',
              FoodErrorKind.offline => 'Cannot reach the backend',
              FoodErrorKind.rejected => 'That request was refused',
              FoodErrorKind.unknown => 'Could not load this view',
            },
            style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              error.message,
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
          ),
          if (error.remedy != null) ...[
            const SizedBox(height: 14),
            // The exact command, selectable so it can be copied rather than
            // retyped from a screenshot.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: AppRadii.smR,
                border: Border.all(color: p.border),
              ),
              child: SelectableText(
                error.remedy!,
                style: AppText.body(size: 12).copyWith(color: p.textSecondary),
              ),
            ),
          ],
          if (error.url != null) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SelectableText(
                error.url!,
                textAlign: TextAlign.center,
                style: AppText.body(size: 11.5).copyWith(color: p.accent),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error.isRetryable)
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                )
              else
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Check again'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A shimmer-free skeleton row. Deliberately the same height as a real row so
/// the list does not jump when the data lands.
class FoodSkeletonRow extends StatelessWidget {
  const FoodSkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          bar(38, 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(180, 13),
                const SizedBox(height: 9),
                bar(260, 10),
              ],
            ),
          ),
          bar(70, 22),
        ],
      ),
    );
  }
}

/// A titled card. The console's only container.
class FoodCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  const FoodCard({
    super.key,
    this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: AppText.body(size: 11).copyWith(
                      color: p.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// A selectable chip. Used for every filter in the console.
class FoodChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  const FoodChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: active ? p.accent : p.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: active ? p.accent : p.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 13,
                    color: active ? Colors.white : p.textMuted,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppText.body(size: 12).copyWith(
                    color: active ? Colors.white : p.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short, human date. Absolute dates are unreadable in a busy audit trail
/// and relative ones are ambiguous past a week, so this switches at a week.
String foodWhen(DateTime? at) {
  if (at == null) return '—';
  final delta = DateTime.now().difference(at);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  final y = at.year.toString().padLeft(4, '0');
  final m = at.month.toString().padLeft(2, '0');
  final d = at.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

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
