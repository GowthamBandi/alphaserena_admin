import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_food_controller.dart';
import '../../core/services/food_platform_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_food_model.dart';
import 'food_chrome.dart';

/// FOOD PLATFORM — the taxonomy manager.
///
/// Categories are platform-wide and Super-Admin-owned. A per-organization
/// vocabulary would fragment the taxonomy and make cross-org nutrition
/// reporting impossible, so every gym reads the same list and none can add
/// to it.
///
/// The tree is deliberately TWO levels. Deeper nesting is unnavigable in a
/// coach's filter chips, and the server refuses a third level outright — the
/// picker here simply never offers one, so the refusal is a backstop rather
/// than an error the curator has to discover.
class FoodCategoriesPanel extends StatelessWidget {
  final GlobalFoodController controller;

  /// Opens the foods list filtered to one category.
  final void Function(FoodQuery query) onDrillDown;

  const FoodCategoriesPanel({
    super.key,
    required this.controller,
    required this.onDrillDown,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final tree = controller.categoryTree;
      final orphanCount = controller.uncategorisedCount.value;

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Every organization reads this list and files its own foods '
                    'against it; none can add to it. That is what keeps the '
                    'vocabulary from fragmenting across hundreds of gyms.',
                    style: AppText.body(
                      size: 12.5,
                    ).copyWith(color: p.textSecondary),
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: controller.loadCategoryCounts,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('Refresh counts'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _openEditor(context, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New category'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (tree.isEmpty)
              FoodEmptyState(
                icon: Icons.category_outlined,
                title: 'No categories yet',
                message:
                    'Start with a handful of top-level groups — Protein, '
                    'Carbohydrates, Vegetables, Fruit, Drinks, Supplements — '
                    'then nest the specifics underneath them. Coaches filter '
                    'the library by these, so a shallow, obvious taxonomy '
                    'beats an exhaustive one.',
                action: FilledButton.icon(
                  onPressed: () => _openEditor(context, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create the first category'),
                ),
              )
            else
              for (final branch in tree) ...[
                _branch(context, branch.parent, branch.children),
                const SizedBox(height: 12),
              ],
            if (orphanCount > 0) ...[
              const SizedBox(height: 4),
              _uncategorised(context, orphanCount),
            ],
          ],
        ),
      );
    });
  }

  // ── Tree ───────────────────────────────────────────────────────────

  Widget _branch(
    BuildContext context,
    FoodCategoryModel parent,
    List<FoodCategoryModel> children,
  ) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          _row(context, parent, isChild: false),
          if (children.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 28, right: 12, bottom: 8),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: p.border, width: 2)),
              ),
              child: Column(
                children: [
                  for (final child in children)
                    _row(context, child, isChild: true),
                ],
              ),
            ),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openEditor(context, null, parentId: parent.id),
                  icon: const Icon(Icons.subdirectory_arrow_right, size: 15),
                  label: const Text('Add a subcategory'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    FoodCategoryModel cat, {
    required bool isChild,
  }) {
    final p = context.palette;
    final dimmed = cat.isArchived;
    return Padding(
      padding: EdgeInsets.fromLTRB(isChild ? 4 : 16, isChild ? 8 : 14, 12, isChild ? 8 : 6),
      child: Row(
        children: [
          Icon(
            isChild ? Icons.subdirectory_arrow_right : Icons.folder_outlined,
            size: isChild ? 15 : 18,
            color: dimmed ? p.textMuted : p.accent,
          ),
          const SizedBox(width: 10),
          Text(
            cat.name,
            style:
                (isChild
                        ? AppText.body(size: 13.5)
                        : AppText.cardTitle(size: 14.5))
                    .copyWith(
                      color: dimmed ? p.textMuted : p.textPrimary,
                      decoration: dimmed ? TextDecoration.lineThrough : null,
                    ),
          ),
          const SizedBox(width: 10),
          // The food count is what makes a taxonomy judgeable: an empty
          // category is either a gap to fill or a mistake to archive, and the
          // list alone cannot tell you which.
          _countChip(context, cat),
          if (cat.isArchived) ...[
            const SizedBox(width: 8),
            FoodPill(label: 'Archived', color: p.textMuted),
          ],
          const Spacer(),
          Text(
            'order ${cat.sortOrder}',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Edit or move',
            onPressed: () => _openEditor(context, cat),
            icon: Icon(Icons.edit_outlined, size: 17, color: p.textMuted),
          ),
          IconButton(
            tooltip: cat.isArchived ? 'Restore' : 'Archive',
            onPressed: () => _confirmArchive(context, cat),
            icon: Icon(
              cat.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              size: 17,
              color: p.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(BuildContext context, FoodCategoryModel cat) {
    final p = context.palette;
    final empty = cat.foodCount == 0;
    return Semantics(
      button: !empty,
      label: '${cat.foodCount} foods in ${cat.name}',
      // Curated label wins over the merged subtree; the action is re-declared
      // so the exclusion does not strip it. Null when empty, matching both the
      // InkWell and `button: !empty` — an empty category is genuinely not
      // activatable, and announcing it as one would be the same lie in reverse.
      excludeSemantics: true,
      onTap: empty
          ? null
          : () => onDrillDown(
              FoodQuery(status: FoodStatusFilter.all, categoryId: cat.id),
            ),
      child: InkWell(
          onTap: empty
              ? null
              : () => onDrillDown(
                  FoodQuery(
                    status: FoodStatusFilter.all,
                    categoryId: cat.id,
                  ),
                ),
          borderRadius: BorderRadius.circular(8),
          child: FoodPill(
            label: empty ? 'empty' : '${cat.foodCount} foods',
            color: empty ? p.textMuted : p.accent,
          ),
        ),
    );
  }

  Widget _uncategorised(BuildContext context, int count) {
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
          Icon(Icons.help_outline, size: 18, color: p.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$count published foods have no category. Coaches cannot filter '
              'to them, so they are only findable by name.',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => onDrillDown(
              const FoodQuery(status: FoodStatusFilter.all, categoryId: ''),
            ),
            child: const Text('Review them'),
          ),
        ],
      ),
    );
  }

  // ── Editor ─────────────────────────────────────────────────────────

  /// Create, rename and MOVE in one dialog. Moving a category is changing its
  /// parent, so making it a separate action would be a second way to do the
  /// same thing — and a second place for the hierarchy rules to drift.
  Future<void> _openEditor(
    BuildContext context,
    FoodCategoryModel? existing, {
    String parentId = '',
  }) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final order = TextEditingController(
      text: (existing?.sortOrder ?? 100).toString(),
    );
    final selectedParent = (existing?.parentId ?? parentId).obs;

    // A category with children cannot itself become a child — that would be
    // the third level the platform refuses. The picker simply does not offer
    // the move, which is kinder than letting the server reject it.
    final hasChildren = controller.categories.any(
      (c) => c.parentId == existing?.id && (existing?.id.isNotEmpty ?? false),
    );

    final parents = controller.categories
        .where((c) => c.isTopLevel && !c.isArchived && c.id != existing?.id)
        .toList();

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text(existing == null ? 'New category' : 'Edit "${existing.name}"'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'Coaches see this in their filter chips.',
                ),
              ),
              const SizedBox(height: 16),
              if (hasChildren)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.surfaceAlt,
                    borderRadius: AppRadii.smR,
                  ),
                  child: Text(
                    'This category has subcategories, so it must stay at the '
                    'top level — the taxonomy is two levels deep at most.',
                    style: AppText.body(
                      size: 12,
                    ).copyWith(color: context.palette.textSecondary),
                  ),
                )
              else
                Obx(() {
                  // Read the observable UNCONDITIONALLY before using it.
                  //
                  // The previous version read it only inside
                  // `parents.any((c) => c.id == selectedParent.value)`. On a
                  // fresh install `parents` is EMPTY, `any` short-circuits
                  // without ever invoking the closure, so Obx saw zero
                  // observable subscriptions and threw "improper use of GetX"
                  // — which meant the New Category dialog was broken for
                  // exactly the first category anyone ever creates.
                  final current = selectedParent.value;
                  final safe = parents.any((c) => c.id == current) ? current : '';
                  return DropdownButtonFormField<String>(
                    initialValue: safe,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Sits under',
                      helperText: 'Leave as top level, or nest one level deep.',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Top level'),
                      ),
                      for (final c in parents)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => selectedParent.value = v ?? '',
                  );
                }),
              const SizedBox(height: 16),
              TextField(
                controller: order,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sort order',
                  helperText: 'Lower comes first in every picker.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          Obx(
            () => FilledButton(
              onPressed: controller.isSaving.value
                  ? null
                  // Save from INSIDE the dialog and close only on success.
                  //
                  // The previous version closed first and saved afterwards, so
                  // a server rejection (a duplicate name, an invalid parent)
                  // threw away everything the operator had typed and left only
                  // a snackbar that vanished in two seconds. The food wizard
                  // already behaved correctly; this now matches it.
                  : () async {
                      final saved = await controller.saveCategory(
                        id: existing?.id,
                        name: name.text,
                        parentId: hasChildren ? '' : selectedParent.value,
                        sortOrder: int.tryParse(order.text.trim()) ?? 100,
                      );
                      if (saved) Get.back(result: true);
                    },
              child: Text(existing == null ? 'Create' : 'Save'),
            ),
          ),
        ],
      ),
    );

    // `ok` is now purely informational — the save already happened inside the
    // dialog, which is the only place that can keep the form open on failure.
    if (ok == true) await controller.loadCategoryCounts();
    name.dispose();
    order.dispose();
  }

  /// Archiving a category never orphans a food and never rewrites one — the
  /// confirmation says so explicitly, because "archive" reads as "delete" to
  /// anyone who has not been told otherwise.
  Future<void> _confirmArchive(
    BuildContext context,
    FoodCategoryModel cat,
  ) async {
    final archiving = !cat.isArchived;
    final children = controller.categories
        .where((c) => c.parentId == cat.id && !c.isArchived)
        .length;

    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text(
          archiving ? 'Archive "${cat.name}"?' : 'Restore "${cat.name}"?',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Text(
            archiving
                ? 'It disappears from every picker and filter across the '
                      'platform.\n\n'
                      '${cat.foodCount} food${cat.foodCount == 1 ? '' : 's'} '
                      'keep their category exactly as it is — nothing is '
                      'orphaned and no food document is rewritten. They simply '
                      'show as uncategorised until you restore it or refile '
                      'them.'
                      '${children > 0 ? '\n\nIts $children active subcategor${children == 1 ? 'y stays' : 'ies stay'} visible; archive them separately if you want them gone too.' : ''}'
                : 'It becomes available again in every picker and filter.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text(archiving ? 'Archive' : 'Restore'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.setCategoryArchived(cat, archiving);
  }
}
