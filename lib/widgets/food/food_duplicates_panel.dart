import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_food_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_food_model.dart';
import 'food_chrome.dart';

/// FOOD PLATFORM — duplicate detection and resolution.
///
/// Five independent signals — identical name, shared barcode, shared alias,
/// similar name, similar nutrition — each reported with a confidence. They are
/// LEADS, never verdicts: the same pair can surface under more than one reason,
/// and **nothing is ever merged automatically**. A wrong automatic merge
/// silently rewrites what every organization on the platform sees, and there is
/// no undo that can restore a curator's confidence afterwards.
///
/// Resolution is always an explicit human decision, with exactly three
/// outcomes: ignore it, merge them into one survivor, or archive the extras.
class FoodDuplicatesPanel extends StatefulWidget {
  final GlobalFoodController controller;
  final void Function(String foodId) onOpenFood;

  const FoodDuplicatesPanel({
    super.key,
    required this.controller,
    required this.onOpenFood,
  });

  @override
  State<FoodDuplicatesPanel> createState() => _FoodDuplicatesPanelState();
}

class _FoodDuplicatesPanelState extends State<FoodDuplicatesPanel> {
  /// Groups the curator has dismissed this session. Held locally on purpose:
  /// "ignore" is a judgement about a scan, not a fact about the data, and
  /// persisting it would quietly hide a real duplicate from the next curator.
  final Set<String> _ignored = {};

  /// Which signals are shown. Fuzzy leads are noisier, so a curator can work
  /// the certain ones first.
  final Set<String> _reasons = {
    'exact',
    'barcode',
    'alias',
    'similar-name',
    'similar-nutrition',
  };

  GlobalFoodController get c => widget.controller;

  String _key(DuplicateGroup g) => '${g.reason}|${g.ids.join(",")}';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final all = c.duplicateGroups;
      final visible = all
          .where((g) => _reasons.contains(g.reason) && !_ignored.contains(_key(g)))
          .toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.duplicateSummary.value ??
                          'Scan the global library for foods that are probably '
                              'the same thing entered twice.',
                      style: AppText.body(
                        size: 12.5,
                      ).copyWith(color: p.textSecondary),
                    ),
                    if (_ignored.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_ignored.length} group'
                          '${_ignored.length == 1 ? '' : 's'} ignored for this '
                          'session. Re-scan to see them again.',
                          style: AppText.body(
                            size: 11.5,
                          ).copyWith(color: p.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Obx(
                () => FilledButton.icon(
                  onPressed: c.isBusy.value
                      ? null
                      : () {
                          setState(_ignored.clear);
                          c.scanDuplicates();
                        },
                  icon: const Icon(Icons.travel_explore, size: 18),
                  label: Text(all.isEmpty ? 'Run scan' : 'Re-scan'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (all.isNotEmpty) _reasonFilters(context, all),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(() {
              if (c.isBusy.value && all.isEmpty) {
                return ListView.builder(
                  itemCount: 4,
                  itemBuilder: (_, _) => const FoodSkeletonRow(),
                );
              }
              if (all.isEmpty) {
                return SingleChildScrollView(
                  child: FoodEmptyState(
                    icon: Icons.travel_explore,
                    title: c.duplicateSummary.value == null
                        ? 'No scan run yet'
                        : 'No duplicates found',
                    message: c.duplicateSummary.value == null
                        ? 'A scan compares every global food against every '
                              'other by name, barcode, alias and nutrition. It '
                              'reads the library once and writes nothing.'
                        : 'Nothing in the global library looks like a '
                              'duplicate of anything else.',
                  ),
                );
              }
              if (visible.isEmpty) {
                return SingleChildScrollView(
                  child: FoodEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Nothing left in this view',
                    message:
                        'Every group matching these signals has been ignored '
                        'or resolved. Widen the signal filters, or re-scan.',
                    action: FilledButton(
                      onPressed: () => setState(() {
                        _ignored.clear();
                        _reasons.addAll([
                          'exact',
                          'barcode',
                          'alias',
                          'similar-name',
                          'similar-nutrition',
                        ]);
                      }),
                      child: const Text('Show everything again'),
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: visible.length,
                itemBuilder: (_, i) => _groupCard(context, visible[i]),
              );
            }),
          ),
        ],
      );
    });
  }

  Widget _reasonFilters(BuildContext context, List<DuplicateGroup> all) {
    const labels = {
      'exact': 'Identical name',
      'barcode': 'Same barcode',
      'alias': 'Shared alias',
      'similar-name': 'Similar name',
      'similar-nutrition': 'Similar nutrition',
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in labels.entries)
          FoodChip(
            label: '${e.value} '
                '(${all.where((g) => g.reason == e.key).length})',
            active: _reasons.contains(e.key),
            onTap: () => setState(() {
              _reasons.contains(e.key)
                  ? _reasons.remove(e.key)
                  : _reasons.add(e.key);
            }),
          ),
      ],
    );
  }

  // ── One group ──────────────────────────────────────────────────────

  Widget _groupCard(BuildContext context, DuplicateGroup g) {
    final p = context.palette;
    final tone = g.isCertain ? p.error : p.textMuted;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FoodPill(
                label: g.reasonLabel,
                color: tone,
                icon: g.isCertain
                    ? Icons.priority_high
                    : Icons.help_outline,
              ),
              const SizedBox(width: 8),
              Text(
                '${(g.confidence * 100).round()}% confidence',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  g.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle(
                    size: 14,
                  ).copyWith(color: p.textPrimary),
                ),
              ),
              Text(
                '${g.ids.length} foods',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final id in g.ids)
            InkWell(
              onTap: () => widget.onOpenFood(id),
              borderRadius: AppRadii.smR,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(Icons.lunch_dining, size: 15, color: p.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.duplicateNames[id] ?? id,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          size: 12.5,
                        ).copyWith(color: p.textPrimary),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: p.textMuted),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                g.isCertain
                    ? 'These are almost certainly the same food.'
                    : 'A lead worth checking — open both before deciding.',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _ignored.add(_key(g))),
                child: const Text('Ignore'),
              ),
              const SizedBox(width: 6),
              Obx(
                () => FilledButton.icon(
                  onPressed: c.isBusy.value ? null : () => _openMerge(context, g),
                  icon: const Icon(Icons.merge_type, size: 17),
                  label: const Text('Resolve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Resolution ─────────────────────────────────────────────────────

  /// The merge dialog.
  ///
  /// The curator picks which food SURVIVES; the rest are archived and their
  /// names fold into the survivor as aliases, so a coach searching the old name
  /// still lands on the food that replaced it. Nothing is deleted, and every
  /// diet plan pointing at a loser keeps resolving exactly as before — which is
  /// precisely why archiving, not deletion, is the whole mechanism.
  Future<void> _openMerge(BuildContext context, DuplicateGroup g) async {
    final foods = await c.resolveFoods(g.ids);
    if (!context.mounted || foods.isEmpty) return;

    // Default the survivor to the most authoritative row: official beats
    // verified, then whichever is most used, then whichever is most complete.
    foods.sort((a, b) {
      final byBadge = _rank(b).compareTo(_rank(a));
      if (byBadge != 0) return byBadge;
      final byUse = (b.usage?.plans ?? 0).compareTo(a.usage?.plans ?? 0);
      if (byUse != 0) return byUse;
      return a.missingData.length.compareTo(b.missingData.length);
    });

    final keepId = foods.first.id.obs;
    final reason = TextEditingController();
    final p = context.palette;

    final choice = await Get.dialog<String>(
      AlertDialog(
        title: const Text('Resolve duplicates'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose which food survives. The others are ARCHIVED — never '
                  'deleted — and their names become aliases of the survivor, so '
                  'searches for the old names still find it. Diet plans that '
                  'already use an archived food keep working unchanged.',
                  style: AppText.body(
                    size: 12.5,
                  ).copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: 16),
                Obx(
                  () => Column(
                    children: [
                      for (final f in foods)
                        _survivorOption(context, f, keepId),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    helperText:
                        'Recorded in the revision history of every food '
                        'involved.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: 'archive'),
            child: const Text('Just archive the others'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: 'merge'),
            child: const Text('Merge'),
          ),
        ],
      ),
    );

    // Resolve the losers EAGERLY: the iterable is derived from keepId, and a
    // lazy one would re-evaluate against a value the dialog no longer owns.
    final losers = foods.where((f) => f.id != keepId.value).toList();
    final note = reason.text.trim();
    reason.dispose();

    if (choice == 'merge') {
      final ok = await c.mergeFoods(
        keepId: keepId.value,
        mergeIds: losers.map((f) => f.id).toList(),
        reason: note,
      );
      if (ok && mounted) setState(() => _ignored.add(_key(g)));
    } else if (choice == 'archive') {
      // Archive WITHOUT folding aliases across. The distinction matters: a
      // curator who is not sure two foods are the same should not have one
      // food start answering the other's name.
      //
      // `force` is correct here and not a shortcut: the curator has just been
      // shown each food's usage in the survivor picker and chose to withdraw
      // them anyway, so re-prompting per food would be noise.
      for (final food in losers) {
        await c.setStatus(food, 'archived', force: true, reason: note);
      }
      if (mounted) setState(() => _ignored.add(_key(g)));
    }
  }

  int _rank(GlobalFoodModel f) => f.isOfficial ? 2 : (f.isVerified ? 1 : 0);

  Widget _survivorOption(
    BuildContext context,
    GlobalFoodModel f,
    RxString keepId,
  ) {
    final p = context.palette;
    final chosen = keepId.value == f.id;
    return InkWell(
      onTap: () => keepId.value = f.id,
      borderRadius: AppRadii.smR,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: chosen ? p.accent.withValues(alpha: 0.07) : p.surfaceAlt,
          borderRadius: AppRadii.smR,
          border: Border.all(color: chosen ? p.accent : p.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(
                chosen
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 19,
                color: chosen ? p.accent : p.textMuted,
              ),
            ),
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
                            size: 13.5,
                          ).copyWith(color: p.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FoodStatusPill(f.status),
                      const SizedBox(width: 6),
                      FoodVerificationPill(f.verification),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (f.brand.isNotEmpty) f.brand,
                      '${f.calories.toStringAsFixed(0)} kcal · '
                          'P${f.protein.toStringAsFixed(0)} '
                          'C${f.carbs.toStringAsFixed(0)} '
                          'F${f.fat.toStringAsFixed(0)}',
                      foodUsageSummary(f.usage),
                      if (f.missingData.isEmpty)
                        'complete'
                      else
                        'missing ${f.missingData.length} fields',
                      'rev ${f.revision}',
                    ].join('  ·  '),
                    style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                  ),
                  if (chosen && f.aliases.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Keeps its ${f.aliases.length} existing alias'
                        '${f.aliases.length == 1 ? '' : 'es'}, plus the names '
                        'of everything merged in.',
                        style: AppText.body(
                          size: 11,
                        ).copyWith(color: p.textMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
