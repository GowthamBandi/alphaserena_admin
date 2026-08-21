import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_food_controller.dart';
import '../../core/services/food_platform_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/food_errors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_food_model.dart';
import 'food_chrome.dart';

/// FOOD PLATFORM — the library dashboard.
///
/// Answers the only question a curator opens the console with: *is this
/// library healthy, and what needs my attention today?*
///
/// Every headline number is a server-side COUNT aggregation, so the dashboard
/// costs a handful of index reads rather than downloading the library — the
/// difference between a page that works at 500 foods and one that works at
/// 50,000. The queue panels are explicitly labelled as SAMPLES rather than
/// pretending to be exhaustive, because a dashboard that quietly truncates is
/// worse than one that admits it.
///
/// Every tile is a LINK. A number a curator cannot act on is decoration.
class FoodAnalyticsPanel extends StatelessWidget {
  final GlobalFoodController controller;

  /// Jumps to the foods list with a filter applied.
  final void Function(FoodQuery query) onDrillDown;

  /// Opens one food's detail page from a queue.
  final void Function(String foodId) onOpenFood;

  const FoodAnalyticsPanel({
    super.key,
    required this.controller,
    required this.onDrillDown,
    required this.onOpenFood,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final a = controller.analytics.value;
      if (controller.isLoadingAnalytics.value && a == null) {
        return _loading(context);
      }
      if (a == null) {
        return SingleChildScrollView(
          child: Column(
            children: [
              FoodErrorState(
                error:
                    controller.analyticsError.value ??
                    const FoodConsoleError(
                      kind: FoodErrorKind.unknown,
                      message: 'The dashboard could not be built.',
                    ),
                onRetry: controller.loadAnalytics,
              ),
              const SizedBox(height: 16),
              // The dashboard is a convenience, not a gate. Saying so — and
              // pointing at the tab that still works — is the difference
              // between a degraded console and one that looks dead.
              _stillWorks(context),
            ],
          ),
        );
      }
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headline(context, a),
            const SizedBox(height: 16),
            _attention(context, a),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 1000;
                final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topCategories(context, a),
                    const SizedBox(height: 16),
                    _mostUsed(context, a),
                  ],
                );
                final right = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _recentlyAdded(context, a),
                    const SizedBox(height: 16),
                    _neverUsed(context, a),
                  ],
                );
                if (!wide) {
                  return Column(
                    children: [left, const SizedBox(height: 16), right],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 16),
                    Expanded(child: right),
                  ],
                );
              },
            ),
          ],
        ),
      );
    });
  }

  /// Shown when the dashboard itself fails.
  ///
  /// Analytics is derived data. Losing it must not imply the library is gone,
  /// and an operator who cannot tell the difference will escalate a cosmetic
  /// failure as an outage.
  Widget _stillWorks(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: p.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Only this dashboard is affected. The Foods tab reads Firestore '
              'directly and still works — the library itself is intact.',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loading(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(minHeight: 3),
        const SizedBox(height: 20),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              const Expanded(child: FoodSkeletonRow()),
              if (i < 3) const SizedBox(width: 12),
            ],
          ],
        ),
        const SizedBox(height: 8),
        const FoodSkeletonRow(),
        const FoodSkeletonRow(),
      ],
    );
  }

  // ── Headline counters ──────────────────────────────────────────────

  Widget _headline(BuildContext context, FoodAnalytics a) {
    final p = context.palette;
    final tiles = <({String label, int value, Color? color, FoodQuery query})>[
      (
        label: 'Total foods',
        value: a.total,
        color: null,
        query: const FoodQuery(status: FoodStatusFilter.all),
      ),
      (
        label: 'Published',
        value: a.published,
        color: p.success,
        query: const FoodQuery(),
      ),
      (
        label: 'Drafts',
        value: a.draft,
        color: a.draft > 0 ? p.accent : null,
        query: const FoodQuery(status: FoodStatusFilter.draft),
      ),
      (
        label: 'Archived',
        value: a.archived,
        color: null,
        query: const FoodQuery(status: FoodStatusFilter.archived),
      ),
      (
        label: 'Official',
        value: a.official,
        color: p.accent,
        query: const FoodQuery(
          status: FoodStatusFilter.all,
          verification: 'official',
        ),
      ),
      (
        label: 'Verified',
        value: a.verified,
        color: p.success,
        query: const FoodQuery(
          status: FoodStatusFilter.all,
          verification: 'verified',
        ),
      ),
      (
        label: 'Unverified',
        value: a.unverified,
        color: a.unverified > 0 ? p.textMuted : null,
        query: const FoodQuery(
          status: FoodStatusFilter.all,
          verification: 'unverified',
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Four across on a normal console, two on a narrow window. Fixed
        // fractions rather than a wrap so the row never leaves a single orphan
        // tile on its own line.
        final perRow = constraints.maxWidth > 1180
            ? 4
            : constraints.maxWidth > 700
            ? 3
            : 2;
        final width =
            (constraints.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final t in tiles)
              SizedBox(
                width: width,
                child: _counterTile(context, t.label, t.value, t.color, t.query),
              ),
          ],
        );
      },
    );
  }

  Widget _counterTile(
    BuildContext context,
    String label,
    int value,
    Color? color,
    FoodQuery query,
  ) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: '$label: $value. Open the filtered list.',
      // The curated label above is strictly better than what the subtree would
      // merge to ("Verified 128" plus a stray icon), so the subtree is excluded
      // — and the action is re-declared here, because excluding it would
      // otherwise take the InkWell's tap and focus with it. See
      // test/a11y_no_excluded_tappables_test.dart, which allows an exclusion
      // ONLY when the action is restored on the same Semantics.
      excludeSemantics: true,
      onTap: () => onDrillDown(query),
      child: InkWell(
          onTap: () => onDrillDown(query),
          borderRadius: AppRadii.cardR,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.cardR,
              border: Border.all(color: p.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: AppText.title(
                    size: 30,
                  ).copyWith(color: color ?? p.textPrimary),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: AppText.body(
                          size: 12,
                        ).copyWith(color: p.textMuted),
                      ),
                    ),
                    Icon(Icons.arrow_outward, size: 13, color: p.textMuted),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
  }

  // ── Work queues ────────────────────────────────────────────────────

  /// The two queues that represent actual work: rows nobody has reviewed, and
  /// rows that are missing data. Everything else on this page is context.
  Widget _attention(BuildContext context, FoodAnalytics a) {
    final p = context.palette;
    if (a.awaitingReviewTotal == 0 && a.missingDataTotal == 0) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: p.success.withValues(alpha: 0.08),
          borderRadius: AppRadii.cardR,
          border: Border.all(color: p.success.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, size: 22, color: p.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                a.sampled == 0
                    ? 'Nothing to review — the library is empty.'
                    : 'Nothing needs review. Every food in the sampled '
                          '${a.sampled} rows is published, verified and '
                          'complete.',
                style: AppText.body(size: 13).copyWith(color: p.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _queueCard(
            context,
            title: 'NEEDS REVIEW',
            total: a.awaitingReviewTotal,
            subtitle:
                '${a.awaitingReviewTotal} unpublished draft'
                '${a.awaitingReviewTotal == 1 ? '' : 's'}'
                '${a.unverifiedTotal > 0 ? ', plus ${a.unverifiedTotal} unverified' : ''}'
                '. Nothing here is wrong — it is simply unreviewed.',
            rows: [for (final e in a.awaitingReview) (id: e.id, text: e.name)],
            onSeeAll: () => onDrillDown(
              const FoodQuery(status: FoodStatusFilter.draft),
            ),
            tone: p.accent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _queueCard(
            context,
            title: 'MISSING DATA',
            total: a.missingDataTotal,
            truncated: a.missingDataTruncated,
            subtitle:
                'Live foods with gaps, found in a sample of the library. They '
                'still work; coaches just see less than they could.',
            rows: [
              for (final e in a.missingData)
                (id: e.id, text: '${e.name} — no ${e.gaps.join(', ')}'),
            ],
            onSeeAll: null,
            tone: p.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _queueCard(
    BuildContext context, {
    required String title,
    required int total,
    required String subtitle,
    required List<({String id, String text})> rows,
    required VoidCallback? onSeeAll,
    required Color tone,
    bool truncated = false,
  }) {
    final p = context.palette;
    return FoodCard(
      title: title,
      trailing: onSeeAll == null
          ? null
          : TextButton(onPressed: onSeeAll, child: const Text('See all')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // A capped count is shown as a FLOOR. Presenting a limited
                // query's size as a total is how a work queue starts lying.
                truncated ? '$total+' : '$total',
                style: AppText.title(size: 26).copyWith(color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    subtitle,
                    style: AppText.body(size: 12).copyWith(color: p.textMuted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'Nothing in this queue.',
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            )
          else
            for (final row in rows.take(8)) _linkRow(context, row.id, row.text),
          if (rows.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '…and ${total - 8} more',
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  // ── Context panels ─────────────────────────────────────────────────

  Widget _topCategories(BuildContext context, FoodAnalytics a) {
    final p = context.palette;
    // EXACT counts from getFoodCategoryCounts, not a sample of the library.
    // The previous version derived these from the first 5,000 documents, which
    // made the headline category silently wrong on any larger library.
    final rows =
        [
          for (final e in controller.categoryCounts.entries)
            (categoryId: e.key, count: e.value),
          if (controller.uncategorisedCount.value > 0)
            (categoryId: '', count: controller.uncategorisedCount.value),
        ]..sort((x, y) => y.count.compareTo(x.count));
    final top = rows.take(12).toList();
    final max = top.isEmpty ? 1 : top.first.count.clamp(1, 1 << 30);
    return FoodCard(
      title: 'TOP CATEGORIES',
      child: top.isEmpty
          ? Text(
              'No categories in use yet.',
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            )
          : Column(
              children: [
                for (final row in top)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => onDrillDown(
                        FoodQuery(
                          status: FoodStatusFilter.all,
                          categoryId: row.categoryId.isEmpty
                              ? null
                              : row.categoryId,
                        ),
                      ),
                      borderRadius: AppRadii.smR,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              row.categoryId.isEmpty
                                  ? 'Uncategorised'
                                  : controller.categoryPath(row.categoryId),
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(size: 12.5).copyWith(
                                color: row.categoryId.isEmpty
                                    ? p.textMuted
                                    : p.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: row.count / max,
                                minHeight: 8,
                                backgroundColor: p.surfaceAlt,
                                valueColor: AlwaysStoppedAnimation(
                                  row.categoryId.isEmpty
                                      ? p.textMuted
                                      : p.accent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 42,
                            child: Text(
                              '${row.count}',
                              textAlign: TextAlign.right,
                              style: AppText.label(
                                size: 12.5,
                              ).copyWith(color: p.textPrimary),
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

  Widget _mostUsed(BuildContext context, FoodAnalytics a) {
    final p = context.palette;
    return FoodCard(
      title: 'MOST USED',
      child: a.mostUsed.isEmpty
          ? Text(
              'No usage measured yet. Usage is computed from the diet-plan '
              'index — run "Refresh usage" on a selection, or the usage '
              'migration under Tools, to populate it.',
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            )
          : Column(
              children: [
                for (final row in a.mostUsed)
                  _linkRow(
                    context,
                    row.id,
                    row.name,
                    trailing: '${row.plans} plan${row.plans == 1 ? '' : 's'}',
                  ),
              ],
            ),
    );
  }

  Widget _recentlyAdded(BuildContext context, FoodAnalytics a) {
    final p = context.palette;
    return FoodCard(
      title: 'RECENTLY ADDED',
      child: a.recent.isEmpty
          ? Text(
              'Nothing added yet.',
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            )
          : Column(
              children: [
                for (final row in a.recent)
                  _linkRow(
                    context,
                    row.id,
                    row.name,
                    trailing: foodWhen(row.at),
                    badge: row.status,
                  ),
              ],
            ),
    );
  }

  Widget _neverUsed(BuildContext context, FoodAnalytics a) {
    final p = context.palette;
    return FoodCard(
      title: 'NEVER USED',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.total == 0
                // Nothing exists yet: saying every food is used would be
                // vacuously true and read as nonsense on a fresh install.
                ? 'No foods in the library yet.'
                : a.neverUsedTotal == 0
                ? 'Every measured food is used by at least one plan.'
                : '${a.neverUsedTotal}${a.neverUsedTruncated ? '+' : ''} '
                      'measured foods have never appeared in a diet plan. That '
                      'is not automatically a problem — a new library is '
                      'entirely unused — but it is where to look before '
                      'growing it further.',
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          ),
          if (a.neverUsed.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final row in a.neverUsed.take(8))
              _linkRow(context, row.id, row.name),
            if (a.neverUsedTotal > 8)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '…and ${a.neverUsedTotal - 8}${a.neverUsedTruncated ? '+' : ''} more',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ),
          ],
          if (a.sampleTruncated) _sampleNote(context, a, 'Usage panels'),
        ],
      ),
    );
  }

  /// Says out loud when a panel is built from a bounded sample rather than the
  /// whole library. A dashboard that hides its own truncation is a dashboard
  /// that will eventually be wrong without anyone noticing.
  Widget _sampleNote(BuildContext context, FoodAnalytics a, String what) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        '$what are computed from the first ${a.sampled} foods, not the whole '
        'library. The headline counters above are exact.',
        style: AppText.body(size: 11).copyWith(color: p.textMuted),
      ),
    );
  }

  Widget _linkRow(
    BuildContext context,
    String id,
    String text, {
    String? trailing,
    String? badge,
  }) {
    final p = context.palette;
    return InkWell(
      onTap: () => onOpenFood(id),
      borderRadius: AppRadii.smR,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 12.5).copyWith(color: p.textPrimary),
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              FoodStatusPill(badge),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 10),
              Text(
                trailing,
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 16, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
