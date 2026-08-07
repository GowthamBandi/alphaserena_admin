import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_exercise_controller.dart';
import '../../core/services/exercise_catalog_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_exercise_model.dart';
import 'exercise_chrome.dart';

/// GLOBAL EXERCISE LIBRARY — the catalog overview.
///
/// Answers the three questions a curator actually opens this console with: how
/// big is the catalog, where are the gaps, and what changed recently. Every
/// headline number is a server-side COUNT aggregation, so opening this tab
/// costs a handful of index reads rather than downloading the catalog.
class ExerciseOverviewPanel extends StatelessWidget {
  final GlobalExerciseController controller;
  final void Function(ExerciseQuery query) onDrillDown;

  const ExerciseOverviewPanel({
    super.key,
    required this.controller,
    required this.onDrillDown,
  });

  GlobalExerciseController get c => controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final failure = c.analyticsError.value;
      if (failure != null) {
        return SingleChildScrollView(
          child: ConsoleErrorState(error: failure, onRetry: c.loadAnalytics),
        );
      }

      final a = c.analytics.value;
      if (a == null) {
        return const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
        );
      }

      if (a.total == 0) {
        return SingleChildScrollView(
          child: ConsoleEmptyState(
            icon: Icons.fitness_center,
            title: 'The catalog has not been founded yet',
            message:
                'The master dataset ships with this console: 844 professionally '
                'named exercises across all 20 categories, with no videos. '
                'Import it once from the Import tab to found the library.',
          ),
        );
      }

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headline(context, a),
            const SizedBox(height: 16),
            _categories(context, a),
            const SizedBox(height: 16),
            _recent(context, a),
          ],
        ),
      );
    });
  }

  Widget _headline(BuildContext context, ExerciseAnalytics a) {
    final p = context.palette;
    return ConsoleCard(
      title: 'CATALOG',
      trailing: IconButton(
        tooltip: 'Refresh',
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: c.loadAnalytics,
      ),
      child: Wrap(
        spacing: 44,
        runSpacing: 20,
        children: [
          ConsoleStat(
            label: 'Exercises',
            value: '${a.total}',
            hint: 'Every document in the master catalog.',
          ),
          ConsoleStat(
            label: 'Active',
            value: '${a.active}',
            color: p.success,
            hint: 'Would be offered to an organization to import.',
          ),
          ConsoleStat(
            label: 'Inactive',
            value: '${a.inactive}',
            color: a.inactive > 0 ? p.textSecondary : null,
            hint: 'Kept in the catalog, not offered.',
          ),
          ConsoleStat(
            label: 'Categories',
            value: '${a.categories}',
            hint: 'The fixed catalog taxonomy.',
          ),
          ConsoleStat(
            label: 'With video',
            value: '${a.withVideo}',
            hint: 'The foundation ships with none — this is expected to be 0.',
          ),
          ConsoleStat(
            label: 'No video uploaded',
            value: '${a.withoutVideo}',
            color: p.textMuted,
            hint: 'The ordinary state today; the uploader is not built yet.',
          ),
        ],
      ),
    );
  }

  Widget _categories(BuildContext context, ExerciseAnalytics a) {
    final p = context.palette;
    final rows = a.categoryCounts;
    final max = rows.fold<int>(0, (m, r) => r.count > m ? r.count : m);
    final empty = a.emptyCategories;

    return ConsoleCard(
      title: 'BY CATEGORY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (empty.isNotEmpty) ...[
            // An empty category is either a gap to fill or one the catalog does
            // not need. Hiding it makes that undecidable, so it is named.
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                '${empty.length} categor${empty.length == 1 ? 'y holds' : 'ies hold'} '
                'nothing: ${empty.join(', ')}.',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              ),
            ),
          ],
          for (final row in rows)
            InkWell(
              onTap: () => onDrillDown(ExerciseQuery(category: row.category)),
              borderRadius: AppRadii.smR,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        row.category,
                        style: AppText.body(
                          size: 13,
                        ).copyWith(color: p.textSecondary),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: max == 0 ? 0 : row.count / max,
                          minHeight: 8,
                          backgroundColor: p.surfaceAlt,
                          valueColor: AlwaysStoppedAnimation(
                            row.isEmpty ? p.error : p.accent,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        row.inactive > 0
                            ? '${row.count}  (${row.inactive} off)'
                            : '${row.count}',
                        textAlign: TextAlign.right,
                        style: AppText.body(size: 12.5).copyWith(
                          color: row.isEmpty ? p.error : p.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recent(BuildContext context, ExerciseAnalytics a) {
    final p = context.palette;
    if (a.recent.isEmpty) {
      return const SizedBox.shrink();
    }
    return ConsoleCard(
      title: 'RECENTLY ADDED',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in a.recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r.name,
                      style: AppText.body(
                        size: 13,
                      ).copyWith(color: p.textPrimary),
                    ),
                  ),
                  ExerciseCategoryPill(r.category),
                  const SizedBox(width: 8),
                  ExerciseActivePill(r.isActive),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 84,
                    child: Text(
                      consoleWhen(r.at),
                      textAlign: TextAlign.right,
                      style: AppText.body(
                        size: 11.5,
                      ).copyWith(color: p.textMuted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
