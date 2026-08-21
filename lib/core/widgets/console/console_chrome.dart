import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radii.dart';
import '../../theme/app_text.dart';
import '../../utils/console_errors.dart';

/// CONSOLE — the shared vocabulary of the platform's data libraries.
///
/// Every status pill, empty state, error state and skeleton row in the Global
/// Food Database and the Global Exercise Library is rendered by exactly one of
/// these. That is the point: a console where an inactive row looks one way in
/// the list and another in the detail view teaches the curator that the
/// interface cannot be trusted, and at a thousand rows trust is the whole
/// product.
///
/// Extracted from `widgets/food/food_chrome.dart` when the second library was
/// built. `food_chrome.dart` now aliases these types under its original names,
/// so every existing food call site is unchanged.

/// A small labelled pill. The consoles' only status affordance.
class ConsolePill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const ConsolePill({
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

/// A labelled number. The consoles' only way to show a metric.
class ConsoleStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final String? hint;

  const ConsoleStat({
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

/// The consoles' single empty state.
///
/// Always says WHY the list is empty and what to do next. "No results" alone
/// leaves a curator unable to tell an empty library from an over-narrow filter,
/// which is the difference between calm and a support ticket.
class ConsoleEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const ConsoleEmptyState({
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

/// The consoles' single error state.
///
/// Says WHAT broke, WHY, and HOW to fix it — and offers a retry only when
/// retrying could plausibly help. A "Try again" button in front of an
/// undeployed Cloud Function is an infinite loop dressed as an affordance, and
/// it is exactly what made the first production failure of the food console
/// impossible to diagnose from the screen.
class ConsoleErrorState extends StatelessWidget {
  final ConsoleError error;
  final VoidCallback onRetry;

  const ConsoleErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

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
              ConsoleErrorKind.notDeployed => Icons.cloud_upload_outlined,
              ConsoleErrorKind.missingIndex => Icons.playlist_add_outlined,
              ConsoleErrorKind.permission => Icons.lock_outline,
              ConsoleErrorKind.offline => Icons.wifi_off_outlined,
              _ => Icons.error_outline,
            },
            size: 30,
            color: tone,
          ),
          const SizedBox(height: 14),
          Text(
            switch (error.kind) {
              ConsoleErrorKind.notDeployed => 'Backend not deployed',
              ConsoleErrorKind.missingIndex => 'A Firestore index is missing',
              ConsoleErrorKind.permission => 'Not authorized',
              ConsoleErrorKind.offline => 'Cannot reach the backend',
              ConsoleErrorKind.rejected => 'That request was refused',
              ConsoleErrorKind.unknown => 'Could not load this view',
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
class ConsoleSkeletonRow extends StatelessWidget {
  const ConsoleSkeletonRow({super.key});

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

/// A titled card. The consoles' only container.
class ConsoleCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;

  const ConsoleCard({
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

/// A selectable chip. Used for every filter in the consoles.
class ConsoleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  const ConsoleChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // An InkWell, NOT a Semantics-wrapped GestureDetector.
    //
    // This was `Semantics(button: true, label: …)` around
    // `ExcludeSemantics(GestureDetector(onTap: …))`. ExcludeSemantics strips
    // the detector's tap ACTION out of the tree, and the outer Semantics never
    // re-declared one — so every chip was published as a button carrying no
    // action and no focusability. Assistive tech could announce a filter and
    // not press it, and a keyboard could not reach it at all.
    //
    // This is the single highest-leverage instance of that bug: ConsoleChip is
    // THE filter control across Subscriptions, Support, Settlements and both
    // content consoles. The identical fix is already documented on the
    // Exercise Library tabs; this brings the shared widget in line with it.
    //
    // InkWell owns the whole contract: focusable (so it gets a tabindex),
    // activates on Enter/Space as well as tap, and publishes its own button
    // semantics whose label merges the child Text — so the label is announced
    // without hand-maintaining a `label:` that can drift from what is drawn.
    return Semantics(
      selected: active,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
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

/// A short, human date. Absolute dates are unreadable in a busy audit trail and
/// relative ones are ambiguous past a week, so this switches at a week.
String consoleWhen(DateTime? at) {
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
