import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/console/console_chrome.dart';

export '../../core/widgets/console/console_chrome.dart';

/// GLOBAL EXERCISE LIBRARY — the console's shared vocabulary.
///
/// The generic pieces (pill, card, chip, stat, skeleton, empty and error
/// states) come from `core/widgets/console/console_chrome.dart` and are shared
/// with the Global Food Database. What is defined here is only what is
/// exercise-specific: the activation pill and the video state.

/// Whether the exercise would be offered to an organization to import.
///
/// Deliberately not called a "status": there is no editorial workflow here, no
/// draft state and no archive. An exercise is either offered or it is not, and
/// naming it anything more elaborate would imply a lifecycle that does not
/// exist.
class ExerciseActivePill extends StatelessWidget {
  final bool isActive;

  /// Whether the row has been WITHDRAWN, not merely retired.
  ///
  /// Archiving writes `isArchived: true` AND `isActive: false`, so before this
  /// existed an archived exercise was indistinguishable from a deactivated one:
  /// both rendered "Inactive". Two different decisions, one label — and the
  /// archived one is the only state that also hides the row from every gym's
  /// picker, so it is the one worth naming.
  final bool isArchived;

  const ExerciseActivePill(this.isActive, {this.isArchived = false, super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Archived wins the label. It is the stronger statement, and it is the flag
    // TrainerHQ actually reads first.
    if (isArchived) {
      return ConsolePill(
        label: 'Archived',
        color: p.error,
        icon: Icons.inventory_2_outlined,
      );
    }
    return isActive
        ? ConsolePill(
            label: 'Active',
            color: p.success,
            icon: Icons.check_circle_outline,
          )
        : ConsolePill(
            label: 'Inactive',
            color: p.textMuted,
            icon: Icons.visibility_off_outlined,
          );
  }
}

/// The video state of an exercise.
///
/// The catalog ships with no videos at all (mission Phase 5), so "no video" is
/// the ORDINARY case, not a fault — it is rendered in the muted tone rather
/// than as a warning. Saying it explicitly on every row is what stops a curator
/// wondering whether the video simply failed to load.
class ExerciseVideoPill extends StatelessWidget {
  final bool hasVideo;
  const ExerciseVideoPill(this.hasVideo, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return hasVideo
        ? ConsolePill(
            label: 'Video',
            color: p.accent,
            icon: Icons.play_circle_outline,
          )
        : ConsolePill(
            label: 'No video uploaded',
            color: p.textMuted,
            icon: Icons.videocam_off_outlined,
          );
  }
}

/// A category badge. Neutral by design — a category is a filter, not a state,
/// and colouring twenty of them would turn the list into a rainbow that carries
/// no information.
class ExerciseCategoryPill extends StatelessWidget {
  final String category;
  final bool unknown;

  const ExerciseCategoryPill(this.category, {super.key, this.unknown = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (category.isEmpty) {
      return ConsolePill(
        label: 'Uncategorised',
        color: p.error,
        icon: Icons.help_outline,
      );
    }
    return ConsolePill(
      label: category,
      // An unknown category is a real problem: the row is invisible in every
      // filter, so it is flagged rather than rendered as if it were fine.
      color: unknown ? p.error : p.textSecondary,
      icon: unknown ? Icons.warning_amber_outlined : Icons.label_outline,
    );
  }
}
