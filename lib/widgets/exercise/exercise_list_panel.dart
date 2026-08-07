import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/global_exercise_controller.dart';
import '../../core/services/exercise_catalog_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_exercise_model.dart';
import '../app_snackbar.dart';
import 'exercise_chrome.dart';

/// GLOBAL EXERCISE LIBRARY — the catalog list.
///
/// Every filter and every sort is a server-side query and pagination is
/// cursor-based; nothing here is ever sorted or filtered in memory. The
/// alternative — download-then-filter — is the single most common reason an
/// internal CMS becomes unusable as its dataset grows.
class ExerciseListPanel extends StatefulWidget {
  final GlobalExerciseController controller;
  final void Function(GlobalExerciseModel exercise) onEdit;
  final VoidCallback onCreate;

  const ExerciseListPanel({
    super.key,
    required this.controller,
    required this.onEdit,
    required this.onCreate,
  });

  @override
  State<ExerciseListPanel> createState() => _ExerciseListPanelState();
}

class _ExerciseListPanelState extends State<ExerciseListPanel> {
  final _search = TextEditingController();
  final _scroll = ScrollController();

  GlobalExerciseController get c => widget.controller;

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

  /// Clears the filters AND the visible search box.
  ///
  /// `c.clearFilters()` resets the controller's own `searchText`, but the text
  /// the user can see lives in this widget's [TextEditingController], which the
  /// controller cannot reach. Calling the controller alone left the box showing
  /// a search term that was no longer being applied — and because the inline
  /// clear (×) is rendered only while `searchText` is non-empty, that stale text
  /// also lost its one affordance for removing it.
  void _clearFilters() {
    _search.clear();
    c.clearFilters();
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

  /// Responsive by construction: the search box flexes and the controls wrap,
  /// so a 13" laptop does not clip the actions off the edge of the screen.
  Widget _toolbar(BuildContext context) {
    final p = context.palette;

    final search = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 200),
      child: TextField(
        controller: _search,
        onChanged: c.onSearchChanged,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: 'Search the exercise catalog',
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

    // THE EXERCISE COUNT (mission Phase 6). Two numbers that answer two
    // different questions: how many rows are loaded here, and how big the
    // catalog actually is. Showing only the first would let a curator read
    // "50 shown" as "the catalog holds 50".
    final count = Obx(() {
      final total = c.analytics.value?.total;
      final loaded = c.exercises.length;
      return Text(
        c.isLoading.value
            ? 'Loading…'
            : '$loaded${c.hasMore.value ? '+' : ''} shown'
                  '${total == null ? '' : ' · $total in catalog'}',
        style: AppText.body(size: 12).copyWith(color: p.textMuted),
      );
    });

    final actions = [
      OutlinedButton.icon(
        onPressed: () => _copyCsv(c.exercises.toList()),
        icon: const Icon(Icons.download_outlined, size: 17),
        label: const Text('Export CSV'),
      ),
      FilledButton.icon(
        onPressed: widget.onCreate,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New exercise'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the controls cannot share a line without clipping one of
        // them off the edge of the screen.
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
      ExerciseSort.nameAsc: 'Name A→Z',
      ExerciseSort.nameDesc: 'Name Z→A',
      ExerciseSort.recentlyUpdated: 'Recently updated',
      ExerciseSort.recentlyCreated: 'Recently added',
    };
    return Obx(() {
      final active = c.query.value.sort;
      return PopupMenuButton<ExerciseSort>(
        tooltip: 'Sort',
        onSelected: (v) => c.setQuery(c.query.value.copyWith(sort: v)),
        itemBuilder: (_) => [
          for (final e in labels.entries)
            PopupMenuItem(value: e.key, child: Text(e.value)),
        ],
        child: _pseudoButton(context, Icons.sort, labels[active]!),
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
      final counts = c.categoryCounts;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final e in const {
            ExerciseActiveFilter.all: 'All',
            ExerciseActiveFilter.active: 'Active',
            ExerciseActiveFilter.inactive: 'Inactive',
          }.entries)
            ConsoleChip(
              label: e.value,
              active: q.active == e.key,
              onTap: () => c.setQuery(q.copyWith(active: e.key)),
            ),
          _divider(context),
          // CATEGORY FILTER (mission Phase 6). Every category is listed, with
          // its live count — including the empty ones, because an empty
          // category is either a gap to fill or one the catalog does not need,
          // and hiding it makes that undecidable.
          ConsoleChip(
            label: 'All categories',
            active: q.category == null || q.category!.isEmpty,
            onTap: () => c.setQuery(q.copyWith(category: null)),
          ),
          for (final category in kExerciseCategories)
            ConsoleChip(
              label: counts.containsKey(category)
                  ? '$category (${counts[category]})'
                  : category,
              active: q.category == category,
              onTap: () => c.setQuery(
                q.copyWith(
                  category: q.category == category ? null : category,
                ),
              ),
            ),
          if (q.hasFilters) ...[
            _divider(context),
            TextButton.icon(
              onPressed: _clearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
              label: const Text('Clear filters'),
            ),
          ],
        ],
      );
    });
  }

  Widget _divider(BuildContext context) => Container(
    width: 1,
    height: 22,
    color: context.palette.border,
  );

  // ── Bulk bar ───────────────────────────────────────────────────────

  Widget _bulkBar(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.08),
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.accent.withValues(alpha: 0.3)),
      ),
      child: Obx(
        () => Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${c.selected.length} selected',
              style: AppText.label(size: 13).copyWith(color: p.textPrimary),
            ),
            TextButton(
              onPressed: c.selectAllLoaded,
              child: const Text('Select all loaded'),
            ),
            TextButton(
              onPressed: c.clearSelection,
              child: const Text('Clear'),
            ),
            OutlinedButton.icon(
              onPressed: c.isBusy.value ? null : () => c.bulkSetActive(true),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Activate'),
            ),
            OutlinedButton.icon(
              onPressed: c.isBusy.value ? null : () => c.bulkSetActive(false),
              icon: const Icon(Icons.visibility_off_outlined, size: 16),
              label: const Text('Deactivate'),
            ),
            // BULK DELETE (mission Phase 6). Destructive and irreversible from
            // the console, so it is tinted as such and always confirmed.
            OutlinedButton.icon(
              onPressed: c.isBusy.value ? null : _confirmBulkDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: p.error,
                side: BorderSide(color: p.error.withValues(alpha: 0.5)),
              ),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────

  Widget _body(BuildContext context) {
    if (c.isLoading.value) {
      return ListView(
        children: const [
          ConsoleSkeletonRow(),
          ConsoleSkeletonRow(),
          ConsoleSkeletonRow(),
          ConsoleSkeletonRow(),
          ConsoleSkeletonRow(),
          ConsoleSkeletonRow(),
        ],
      );
    }

    final failure = c.error.value;
    if (failure != null) {
      return SingleChildScrollView(
        child: ConsoleErrorState(error: failure, onRetry: c.refreshList),
      );
    }

    if (c.exercises.isEmpty) {
      // An EMPTY CATALOG and an OVER-NARROW FILTER are different problems with
      // different fixes, and a shared "No results" makes them indistinguishable.
      final filtered = c.query.value.hasFilters;
      return SingleChildScrollView(
        child: ConsoleEmptyState(
          icon: filtered ? Icons.filter_alt_off_outlined : Icons.fitness_center,
          title: filtered ? 'Nothing matches those filters' : 'The catalog is empty',
          message: filtered
              ? 'No exercise matches this combination of search, category and '
                    'activation state. Clearing the filters shows the whole '
                    'catalog again.'
              : 'No exercise has been created yet. Import the master dataset '
                    'from the Import tab to found the catalog with 844 '
                    'professionally-named exercises, or add one by hand.',
          action: filtered
              ? OutlinedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                  label: const Text('Clear filters'),
                )
              : FilledButton.icon(
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New exercise'),
                ),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      // One extra row for the pagination footer.
      itemCount: c.exercises.length + 1,
      itemBuilder: (context, i) {
        if (i == c.exercises.length) return _footer(context);
        return _row(context, c.exercises[i]);
      },
    );
  }

  Widget _footer(BuildContext context) {
    final p = context.palette;
    final failure = c.loadMoreError.value;
    if (failure != null) {
      // The rows already on screen STAY. Throwing away 200 loaded rows because
      // page 5 failed is a worse outcome than the failure itself.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: AppText.body(size: 12.5).copyWith(color: p.error),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: c.loadMore,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry this page'),
            ),
          ],
        ),
      );
    }
    if (c.isLoadingMore.value) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (!c.hasMore.value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: Text(
            'End of results · ${c.exercises.length} exercise'
            '${c.exercises.length == 1 ? '' : 's'}',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ),
      );
    }
    return const SizedBox(height: 40);
  }

  Widget _row(BuildContext context, GlobalExerciseModel e) {
    final p = context.palette;
    return Obx(() {
      final checked = c.selected.contains(e.id);
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(
            color: checked ? p.accent.withValues(alpha: 0.6) : p.border,
          ),
        ),
        child: InkWell(
          onTap: () => widget.onEdit(e),
          borderRadius: AppRadii.cardR,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Checkbox(
                  value: checked,
                  onChanged: (_) => c.toggleSelected(e.id),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name,
                        style: AppText.cardTitle(size: 14).copyWith(
                          color: e.isActive ? p.textPrimary : p.textMuted,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ExerciseCategoryPill(
                            e.category,
                            unknown: e.hasUnknownCategory,
                          ),
                          ExerciseActivePill(e.isActive),
                          ExerciseVideoPill(e.hasVideo),
                          if (e.aliases.isNotEmpty)
                            Text(
                              'also: ${e.aliases.take(2).join(', ')}',
                              style: AppText.body(
                                size: 11.5,
                              ).copyWith(color: p.textMuted),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  consoleWhen(e.updatedAt ?? e.createdAt),
                  style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                ),
                _rowMenu(context, e),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _rowMenu(BuildContext context, GlobalExerciseModel e) {
    final p = context.palette;
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            widget.onEdit(e);
          case 'activate':
            await c.setActive(e, true);
          case 'deactivate':
            await c.setActive(e, false);
          case 'video':
            _explainVideoUpload(context, e);
          case 'delete':
            await _confirmDelete(e);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (e.isActive)
          const PopupMenuItem(value: 'deactivate', child: Text('Deactivate'))
        else
          const PopupMenuItem(value: 'activate', child: Text('Activate')),
        const PopupMenuItem(value: 'video', child: Text('Upload video')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: p.error)),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Icon(Icons.more_vert, size: 18),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────

  /// The Upload Video affordance (mission Phase 6: BUTTON ONLY).
  ///
  /// It deliberately explains that the uploader is not built rather than
  /// opening a picker that would fail, or silently doing nothing. A control
  /// that appears to work and does not is worse than one that says so.
  void _explainVideoUpload(BuildContext context, GlobalExerciseModel e) {
    Get.dialog(
      AlertDialog(
        title: const Text('Upload video'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            e.hasVideo
                ? '"${e.name}" already has a video attached.\n\n'
                      'The uploader itself is not built yet. Until it is, a '
                      'video URL can be set by hand in the exercise editor — '
                      'it must be an https link, which the server enforces.'
                : '"${e.name}" has no video uploaded.\n\n'
                      'The video uploader is deliberately not built in this '
                      'foundation. The catalog already stores everything it '
                      'needs — videoUrl, thumbnailUrl, videoProvider and '
                      'duration — so adding the uploader later needs no schema '
                      'change and no re-import.\n\n'
                      'An https video URL can be set by hand in the exercise '
                      'editor in the meantime.',
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Get.back();
              widget.onEdit(e);
            },
            child: const Text('Open editor'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _confirmDelete(GlobalExerciseModel e) async {
    final confirmed = await _confirm(
      title: 'Delete "${e.name}"?',
      body:
          'This permanently removes the exercise from the master catalog. It '
          'cannot be undone from this console.\n\n'
          'Nothing in TrainerHQ or AlphaSerena references the catalog, so no '
          'workout, program or assignment is affected. If you only want to '
          'stop offering it, Deactivate keeps the row and its history.',
      confirmLabel: 'Delete permanently',
    );
    if (confirmed) await c.delete(e);
  }

  Future<void> _confirmBulkDelete() async {
    final count = c.selected.length;
    final confirmed = await _confirm(
      title: 'Delete $count exercise${count == 1 ? '' : 's'}?',
      body:
          'This permanently removes ${count == 1 ? 'it' : 'them'} from the '
          'master catalog. It cannot be undone from this console.\n\n'
          'Only the rows you can currently see are selected — the selection is '
          'cleared whenever the list reloads, so this can never reach an '
          'exercise you have not looked at.',
      confirmLabel: 'Delete $count permanently',
    );
    if (confirmed) await c.bulkDelete();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final p = context.palette;
    final result = await Get.dialog<bool>(
      AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(body),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.error),
            onPressed: () => Get.back(result: true),
            child: Text(confirmLabel),
          ),
        ],
      ),
      // A mid-request outside tap could pop the wrong route.
      barrierDismissible: false,
    );
    return result == true;
  }

  void _copyCsv(List<GlobalExerciseModel> rows) {
    if (rows.isEmpty) {
      AppSnackbar.show(
        title: 'Nothing to export',
        message: 'The list is empty.',
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: c.exportCsv(rows)));
    AppSnackbar.show(
      title: 'Copied',
      message: '${rows.length} row${rows.length == 1 ? '' : 's'} of CSV are on '
          'your clipboard.',
    );
  }
}
