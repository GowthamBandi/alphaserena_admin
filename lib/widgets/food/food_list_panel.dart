import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/global_food_controller.dart';
import '../../core/services/food_platform_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_food_model.dart';
import '../app_snackbar.dart';
import 'food_chrome.dart';

/// FOOD PLATFORM — the foods list.
///
/// Built for a library of tens of thousands of rows: every filter and every
/// sort is a server-side query, pagination is cursor-based, and nothing is ever
/// sorted or filtered in memory. The alternative — download-then-filter — is
/// the single most common reason an internal CMS becomes unusable at scale.
class FoodListPanel extends StatefulWidget {
  final GlobalFoodController controller;
  final void Function(GlobalFoodModel food) onOpen;
  final VoidCallback onCreate;

  const FoodListPanel({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onCreate,
  });

  @override
  State<FoodListPanel> createState() => _FoodListPanelState();
}

class _FoodListPanelState extends State<FoodListPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  GlobalFoodController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _search.text = c.searchText.value;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Loads the next page a little before the bottom, so scrolling never stalls.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      c.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolbar(context),
        const SizedBox(height: 12),
        _filters(context),
        Obx(
          () => c.hasSelection
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _bulkBar(context),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        Expanded(child: Obx(() => _body(context))),
      ],
    );
  }

  // ── Toolbar ────────────────────────────────────────────────────────

  /// Responsive by construction.
  ///
  /// The previous version was a fixed Row and overflowed by 255px at 800px
  /// wide — invisible to `flutter analyze`, and immediately visible to anyone
  /// on a 13" laptop. The search box now flexes and the controls wrap.
  Widget _toolbar(BuildContext context) {
    final p = context.palette;

    final search = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 200),
      child: TextField(
        controller: _search,
        onChanged: c.onSearchChanged,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: 'Search the global library',
          isDense: true,
          filled: true,
          fillColor: p.surface,
          suffixIcon: Obx(
            () => c.searchText.value.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _search.clear();
                      c.onSearchChanged('');
                    },
                  ),
          ),
          border: OutlineInputBorder(
            borderRadius: AppRadii.smR,
            borderSide: BorderSide(color: p.border),
          ),
        ),
      ),
    );

    final count = Obx(
      () => Text(
        c.isLoading.value
            ? 'Loading…'
            : '${c.foods.length}${c.hasMore.value ? '+' : ''} shown',
        style: AppText.body(size: 12).copyWith(color: p.textMuted),
      ),
    );

    final actions = [
      OutlinedButton.icon(
        onPressed: () => _copyCsv(c.foods.toList()),
        icon: const Icon(Icons.download_outlined, size: 17),
        label: const Text('Export CSV'),
      ),
      FilledButton.icon(
        onPressed: widget.onCreate,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New food'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the five controls cannot share a line without clipping
        // one of them off the edge of the screen.
        final tight = constraints.maxWidth < 900;
        if (tight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [_sortMenu(context), count, ...actions],
              ),
            ],
          );
        }
        return Row(
          children: [
            Flexible(child: search),
            const SizedBox(width: 12),
            _sortMenu(context),
            const Spacer(),
            count,
            const SizedBox(width: 12),
            actions[0],
            const SizedBox(width: 10),
            actions[1],
          ],
        );
      },
    );
  }

  Widget _sortMenu(BuildContext context) {
    const labels = {
      FoodSort.nameAsc: 'Name A→Z',
      FoodSort.nameDesc: 'Name Z→A',
      FoodSort.recentlyUpdated: 'Recently updated',
      FoodSort.recentlyCreated: 'Recently added',
      FoodSort.caloriesDesc: 'Highest calories',
    };
    return Obx(() {
      final active = c.query.value.sort;
      // A date filter forces the ordering (Firestore requires the range field
      // to sort first), so the control says so instead of lying.
      final locked = c.query.value.updatedAfter != null;
      return PopupMenuButton<FoodSort>(
        tooltip: locked
            ? 'Sorting is fixed to recently updated while a date filter is on'
            : 'Sort',
        enabled: !locked,
        onSelected: (v) => c.setQuery(c.query.value.copyWith(sort: v)),
        itemBuilder: (_) => [
          for (final e in labels.entries)
            PopupMenuItem(value: e.key, child: Text(e.value)),
        ],
        child: _pseudoButton(
          context,
          Icons.sort,
          locked ? 'Recently updated' : labels[active]!,
        ),
      );
    });
  }

  Widget _pseudoButton(BuildContext context, IconData icon, String label) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: p.textMuted),
          const SizedBox(width: 8),
          Text(
            label,
            style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, size: 18, color: p.textMuted),
        ],
      ),
    );
  }

  // ── Filters ────────────────────────────────────────────────────────

  Widget _filters(BuildContext context) {
    return Obx(() {
      final q = c.query.value;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Status
          for (final e in const {
            FoodStatusFilter.published: 'Published',
            FoodStatusFilter.draft: 'Drafts',
            FoodStatusFilter.archived: 'Archived',
            FoodStatusFilter.all: 'All',
          }.entries)
            FoodChip(
              label: e.value,
              active: q.status == e.key,
              onTap: () => c.setQuery(q.copyWith(status: e.key)),
            ),
          _divider(context),
          // Category
          FoodChip(
            label: 'All categories',
            active: q.categoryId == null,
            onTap: () => c.setQuery(q.copyWith(categoryId: null)),
          ),
          for (final cat in c.activeCategories)
            FoodChip(
              label: cat.name,
              active: q.categoryId == cat.id,
              onTap: () => c.setQuery(q.copyWith(categoryId: cat.id)),
            ),
          _divider(context),
          // Verification
          for (final e in const {
            'official': 'Official',
            'verified': 'Verified',
            'unverified': 'Unverified',
          }.entries)
            FoodChip(
              label: e.value,
              active: q.verification == e.key,
              onTap: () => c.setQuery(
                q.copyWith(verification: q.verification == e.key ? null : e.key),
              ),
            ),
          _divider(context),
          // Source
          for (final e in const {
            'manual': 'Hand-authored',
            'seed': 'Seed',
            'import': 'Imported',
            'usda': 'USDA',
          }.entries)
            FoodChip(
              label: e.value,
              active: q.source == e.key,
              onTap: () =>
                  c.setQuery(q.copyWith(source: q.source == e.key ? null : e.key)),
            ),
          _divider(context),
          // Date
          for (final e in const {7: 'Last 7 days', 30: 'Last 30 days'}.entries)
            FoodChip(
              label: e.value,
              icon: Icons.schedule,
              active: _daysAgo(q.updatedAfter) == e.key,
              onTap: () => c.setQuery(
                q.copyWith(
                  updatedAfter: _daysAgo(q.updatedAfter) == e.key
                      ? null
                      : DateTime.now().subtract(Duration(days: e.key)),
                ),
              ),
            ),
          if (q.hasFilters) ...[
            _divider(context),
            TextButton.icon(
              onPressed: () {
                _search.clear();
                c.clearFilters();
              },
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      );
    });
  }

  int? _daysAgo(DateTime? at) {
    if (at == null) return null;
    final days = DateTime.now().difference(at).inDays;
    if (days <= 7) return 7;
    if (days <= 31) return 30;
    return null;
  }

  Widget _divider(BuildContext context) => Container(
    width: 1,
    height: 20,
    color: context.palette.border,
  );

  // ── Bulk bar ───────────────────────────────────────────────────────

  Widget _bulkBar(BuildContext context) {
    final p = context.palette;
    final count = c.selected.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.10),
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.checklist, size: 18, color: p.accent),
          const SizedBox(width: 10),
          Text(
            '$count selected',
            style: AppText.label(size: 13).copyWith(color: p.textPrimary),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: c.selectAllLoaded,
            child: const Text('Select all loaded'),
          ),
          TextButton(onPressed: c.clearSelection, child: const Text('Clear')),
          const SizedBox(width: 12),
          // Wraps rather than overflows: five actions plus a label do not fit
          // one line on a small desktop.
          Expanded(
            child: Obx(
              () => Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                _bulkAction(
                  context,
                  'Publish',
                  Icons.public,
                  c.isBusy.value ? null : () => _bulk(status: 'published'),
                ),
                _bulkAction(
                  context,
                  'Verify',
                  Icons.verified_outlined,
                  c.isBusy.value ? null : () => _bulk(verification: 'verified'),
                ),
                _bulkAction(
                  context,
                  'Archive',
                  Icons.archive_outlined,
                  c.isBusy.value ? null : () => _bulk(status: 'archived'),
                ),
                _bulkAction(
                  context,
                  'Refresh usage',
                  Icons.insights_outlined,
                  c.isBusy.value
                      ? null
                      : () => c.refreshUsageFor(c.selected.toList()),
                ),
                _bulkAction(
                    context,
                    'Export CSV',
                    Icons.download_outlined,
                    () => _copyCsv(
                      c.foods.where((f) => c.selected.contains(f.id)).toList(),
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

  Widget _bulkAction(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback? onTap,
  ) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  /// Runs a bulk action, then surfaces anything the server refused.
  ///
  /// A bulk archive is exactly where a curator is least likely to be paying
  /// attention, so refusals are shown as an explicit dialog naming every food
  /// still in use — never a snackbar that scrolls away.
  Future<void> _bulk({String? status, String? verification}) async {
    if (status == 'archived') {
      final confirmed = await _confirm(
        title: 'Archive ${c.selected.length} foods?',
        body:
            'Archiving hides them from every organization\'s search and diet '
            'builder.\n\nNothing is deleted. Diet plans that already use them '
            'keep working exactly as they are.\n\nAnything currently in use '
            'will be skipped and listed for you.',
        confirmLabel: 'Archive',
      );
      if (!confirmed) return;
    }

    final res = await c.bulkApply(status: status, verification: verification);
    if (res == null || res.blocked.isEmpty) return;
    if (!mounted) return;

    final proceed = await _confirm(
      title: '${res.blocked.length} food'
          '${res.blocked.length == 1 ? '' : 's'} skipped',
      body: [
        if (res.changed > 0) '${res.changed} updated.\n',
        'These are actively used by organizations:\n',
        ...res.blocked.take(12).map((b) => '• ${b.name} — ${b.reason}'),
        if (res.blocked.length > 12) '• …and ${res.blocked.length - 12} more',
        '\nArchiving them is still safe — existing plans keep working — but '
            'coaches will lose them from search.',
      ].join('\n'),
      confirmLabel: 'Archive anyway',
    );
    if (proceed) {
      await c.bulkApply(status: status, verification: verification, force: true);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(child: Text(body)),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _copyCsv(List<GlobalFoodModel> rows) {
    if (rows.isEmpty) {
      AppSnackbar.show(title: 'Nothing to export', message: 'No rows selected.');
      return;
    }
    Clipboard.setData(ClipboardData(text: c.exportCsv(rows)));
    AppSnackbar.show(
      title: 'Copied',
      message: '${rows.length} rows are on your clipboard as CSV.',
    );
  }

  // ── Body ───────────────────────────────────────────────────────────

  Widget _body(BuildContext context) {
    if (c.error.value != null) {
      return SingleChildScrollView(
        child: FoodErrorState(error: c.error.value!, onRetry: c.refreshList),
      );
    }
    if (c.isLoading.value) {
      return ListView.builder(
        itemCount: 6,
        itemBuilder: (_, _) => const FoodSkeletonRow(),
      );
    }
    if (c.foods.isEmpty) return SingleChildScrollView(child: _empty(context));

    return ListView.builder(
      controller: _scroll,
      itemCount: c.foods.length + 1,
      itemBuilder: (_, i) {
        if (i == c.foods.length) return _footer(context);
        return _row(context, c.foods[i]);
      },
    );
  }

  Widget _empty(BuildContext context) {
    final q = c.query.value;
    if (q.hasFilters) {
      return FoodEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'No foods match these filters',
        message:
            'The library is not empty — this combination of filters is. Widen '
            'the search or clear the filters to see everything again.',
        action: FilledButton(
          onPressed: () {
            _search.clear();
            c.clearFilters();
          },
          child: const Text('Clear filters'),
        ),
      );
    }
    return FoodEmptyState(
      icon: Icons.set_meal_outlined,
      title: 'The global library is empty',
      message:
          'Nothing has been published to the platform yet. Import the seed '
          'catalog from the Import tab to found the library, or create the '
          'first food by hand.',
      action: FilledButton.icon(
        onPressed: widget.onCreate,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Create the first food'),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (c.isLoadingMore.value) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        );
      }
      // A page that failed to load is reported IN PLACE, so the rows already
      // on screen survive and the operator can retry just the failed page.
      final pageError = c.loadMoreError.value;
      if (pageError != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 17, color: p.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Could not load more. ${pageError.message}',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ),
              TextButton(
                onPressed: c.loadMore,
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      if (c.hasMore.value) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: OutlinedButton(
              onPressed: c.loadMore,
              child: const Text('Load more'),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'End of results · ${c.foods.length} foods',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ),
      );
    });
  }

  // ── One row ────────────────────────────────────────────────────────

  Widget _row(BuildContext context, GlobalFoodModel f) {
    final p = context.palette;
    return Obx(() {
      final isSelected = c.selected.contains(f.id);
      final category = c.categoryPath(f.categoryId);
      final gaps = f.missingData;

      return Semantics(
        button: true,
        selected: isSelected,
        label:
            '${f.name}. ${f.status}. ${f.calories.round()} kcal per 100 grams. '
            '${category.isEmpty ? 'Uncategorised' : category}. '
            'Open details.',
        child: ExcludeSemantics(
          child: InkWell(
            onTap: () => widget.onOpen(f),
            borderRadius: AppRadii.cardR,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(10, 14, 16, 14),
              decoration: BoxDecoration(
                color: isSelected ? p.accent.withValues(alpha: 0.06) : p.surface,
                borderRadius: AppRadii.cardR,
                border: Border.all(
                  color: isSelected ? p.accent : p.border,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => c.toggleSelected(f.id),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                f.name,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.cardTitle(
                                  size: 14.5,
                                ).copyWith(color: p.textPrimary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FoodStatusPill(f.status),
                            const SizedBox(width: 6),
                            FoodVerificationPill(f.verification),
                            if (f.hasEnergyMismatch) ...[
                              const SizedBox(width: 6),
                              FoodPill(
                                label: 'Energy mismatch',
                                color: p.error,
                                icon: Icons.warning_amber_rounded,
                              ),
                            ],
                            if (gaps.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Missing: ${gaps.join(', ')}',
                                child: FoodPill(
                                  label: '${gaps.length} gaps',
                                  color: p.textMuted,
                                  icon: Icons.info_outline,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (f.brand.isNotEmpty) f.brand,
                            if (category.isNotEmpty) category else 'Uncategorised',
                            f.foodType,
                            '${f.calories.toStringAsFixed(0)} kcal · '
                                'P${f.protein.toStringAsFixed(0)} '
                                'C${f.carbs.toStringAsFixed(0)} '
                                'F${f.fat.toStringAsFixed(0)}',
                            foodUsageSummary(f.usage),
                            'rev ${f.revision} · ${foodWhen(f.updatedAt)}',
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            size: 11.5,
                          ).copyWith(color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.chevron_right, size: 20, color: p.textMuted),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
