import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/global_food_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_food_model.dart';
import '../app_snackbar.dart';
import 'food_chrome.dart';

/// FOOD PLATFORM — the food detail page.
///
/// Clicking a food deliberately does NOT open an editor. A curator about to
/// touch a row that hundreds of organizations build diet plans from needs to
/// see what it IS and what it AFFECTS first — its nutrition, its search
/// metadata, who uses it, and every change anyone has ever made to it. The
/// editor is one explicit click further away, which is exactly where it
/// belongs.
class FoodDetailPanel extends StatelessWidget {
  final GlobalFoodController controller;
  final GlobalFoodModel food;
  final VoidCallback onClose;
  final void Function(GlobalFoodModel food) onEdit;
  final void Function(GlobalFoodModel food) onDuplicate;

  const FoodDetailPanel({
    super.key,
    required this.controller,
    required this.food,
    required this.onClose,
    required this.onEdit,
    required this.onDuplicate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 1080;
              final left = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _overview(context),
                  const SizedBox(height: 16),
                  _nutrition(context),
                  const SizedBox(height: 16),
                  _micronutrients(context),
                  const SizedBox(height: 16),
                  _servingSizes(context),
                ],
              );
              final right = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _usage(context),
                  const SizedBox(height: 16),
                  _searchMetadata(context),
                  const SizedBox(height: 16),
                  _relationships(context),
                  const SizedBox(height: 16),
                  _history(context),
                ],
              );
              if (!wide) {
                return Column(children: [left, const SizedBox(height: 16), right]);
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: left),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: right),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Header + actions ───────────────────────────────────────────────

  Widget _header(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          tooltip: 'Back to the library',
          onPressed: onClose,
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title(
                        size: 26,
                      ).copyWith(color: p.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FoodStatusPill(food.status),
                  const SizedBox(width: 6),
                  FoodVerificationPill(food.verification),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (food.brand.isNotEmpty) food.brand,
                  controller.categoryPath(food.categoryId).isEmpty
                      ? 'Uncategorised'
                      : controller.categoryPath(food.categoryId),
                  food.foodType,
                  'revision ${food.revision}',
                  'updated ${foodWhen(food.updatedAt)}',
                ].join('  ·  '),
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // Flexible so the actions Wrap receives a bounded width and wraps its
        // buttons onto a second run instead of being measured single-line under
        // the Row's unbounded main-axis constraint — which starved the Expanded
        // title to ~0px and overflowed the header.
        Flexible(child: _actions(context)),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final busy = controller.isBusy.value;
      return Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => onEdit(food),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Edit'),
          ),
          OutlinedButton.icon(
            onPressed: () => onDuplicate(food),
            icon: const Icon(Icons.copy_all_outlined, size: 17),
            label: const Text('Duplicate'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: controller.exportCsv([food])),
              );
              AppSnackbar.show(
                title: 'Copied',
                message: 'This food is on your clipboard as CSV.',
              );
            },
            icon: const Icon(Icons.download_outlined, size: 17),
            label: const Text('Export'),
          ),
          if (food.isDraft)
            FilledButton.icon(
              onPressed: busy ? null : () => _setStatus(context, 'published'),
              icon: const Icon(Icons.public, size: 17),
              label: const Text('Publish'),
            ),
          if (food.isPublished)
            OutlinedButton.icon(
              onPressed: busy ? null : () => _setStatus(context, 'draft'),
              icon: const Icon(Icons.edit_note, size: 17),
              label: const Text('Unpublish'),
            ),
          if (food.isArchived)
            FilledButton.icon(
              onPressed: busy ? null : () => _setStatus(context, 'published'),
              icon: const Icon(Icons.unarchive_outlined, size: 17),
              label: const Text('Restore'),
            )
          else
            OutlinedButton.icon(
              onPressed: busy ? null : () => _setStatus(context, 'archived'),
              icon: const Icon(Icons.archive_outlined, size: 17),
              label: const Text('Archive'),
            ),
          PopupMenuButton<String>(
            tooltip: 'Verification',
            onSelected: (v) => controller.setVerification(food, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'official', child: Text('Mark official')),
              PopupMenuItem(value: 'verified', child: Text('Mark verified')),
              PopupMenuItem(value: 'unverified', child: Text('Mark unverified')),
            ],
            // A styled container, NOT a disabled button: a disabled Material
            // button reads as "unavailable" and does not reliably pass its
            // taps to the popup's gesture detector.
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: AppRadii.smR,
                border: Border.all(color: p.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 17,
                    color: p.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Verification',
                    style: AppText.body(
                      size: 13,
                    ).copyWith(color: p.textSecondary),
                  ),
                  Icon(Icons.arrow_drop_down, size: 18, color: p.textMuted),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Status changes ask for a reason and, for archive, surface the server's
  /// live usage refusal so the curator sees precisely what they are affecting
  /// before overriding it.
  Future<void> _setStatus(BuildContext context, String status) async {
    final reason = await _askReason(
      title: switch (status) {
        'archived' => 'Archive "${food.name}"?',
        'draft' => 'Unpublish "${food.name}"?',
        _ => 'Publish "${food.name}"?',
      },
      body: switch (status) {
        'archived' =>
          'It disappears from every organization\'s search and diet builder.\n\n'
              'It is NOT deleted. Diet plans that already use it keep working '
              'exactly as they are — the platform never deletes a food, '
              'because a plan may point at it forever.',
        'draft' =>
          'Coaches will stop seeing it in search immediately. Existing diet '
              'plans are untouched.',
        _ => 'Every organization on the platform will be able to search and '
            'use it.',
      },
      confirmLabel: switch (status) {
        'archived' => 'Archive',
        'draft' => 'Unpublish',
        _ => 'Publish',
      },
    );
    if (reason == null) return;

    final blocked = await controller.setStatus(food, status, reason: reason);
    if (blocked == null) return;

    // The server refused because the food is in use. Show exactly what it said
    // and let the curator decide — never silently force, never silently fail.
    final proceed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('This food is in use'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(blocked),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Keep it published'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Archive anyway'),
          ),
        ],
      ),
    );
    if (proceed == true) {
      await controller.setStatus(food, status, force: true, reason: reason);
    }
  }

  /// Returns the reason, or null when cancelled. Empty string is a valid
  /// answer — the reason is encouraged, not mandatory, because forcing one
  /// just trains people to type "update".
  Future<String?> _askReason({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final ctl = TextEditingController();
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(body),
              const SizedBox(height: 16),
              TextField(
                controller: ctl,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  helperText: 'Recorded in this food\'s revision history.',
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
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    final reason = ctl.text.trim();
    ctl.dispose();
    return ok == true ? reason : null;
  }

  // ── Sections ───────────────────────────────────────────────────────

  Widget _overview(BuildContext context) {
    final p = context.palette;
    final gaps = food.missingData;
    return FoodCard(
      title: 'OVERVIEW',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (gaps.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.textMuted.withValues(alpha: 0.08),
                borderRadius: AppRadii.smR,
              ),
              child: Text(
                'Incomplete: this food has no ${gaps.join(', ')}. It still '
                'works, but coaches see less than they could.',
                style: AppText.body(size: 12).copyWith(color: p.textSecondary),
              ),
            ),
            const SizedBox(height: 14),
          ],
          _grid(context, [
            ('Source', food.source),
            ('External reference', food.sourceRef.isEmpty ? '—' : food.sourceRef),
            ('Cuisine', food.cuisine.isEmpty ? 'Any' : food.cuisine),
            ('Barcode', food.barcode.isEmpty ? '—' : food.barcode),
            ('Basis', food.baseGrams == null ? 'per serving' : 'per 100 g'),
            ('Created', foodWhen(food.createdAt)),
            ('Created by', food.createdBy.isEmpty ? '—' : food.createdBy),
            ('Last updated by', food.updatedBy.isEmpty ? '—' : food.updatedBy),
          ]),
        ],
      ),
    );
  }

  Widget _nutrition(BuildContext context) {
    final p = context.palette;
    final estimate = food.energyFromMacros;
    return FoodCard(
      title: 'NUTRITION · PER 100 g',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 32,
            runSpacing: 16,
            children: [
              FoodStat(
                label: 'kcal',
                value: food.calories.toStringAsFixed(0),
                color: food.hasEnergyMismatch ? p.error : p.accent,
              ),
              FoodStat(
                label: 'protein',
                value: '${food.protein.toStringAsFixed(1)} g',
              ),
              FoodStat(label: 'carbs', value: '${food.carbs.toStringAsFixed(1)} g'),
              FoodStat(label: 'fat', value: '${food.fat.toStringAsFixed(1)} g'),
              FoodStat(label: 'fiber', value: '${food.fiber.toStringAsFixed(1)} g'),
              FoodStat(label: 'sugar', value: '${food.sugar.toStringAsFixed(1)} g'),
              FoodStat(
                label: 'saturated fat',
                value: '${food.saturatedFat.toStringAsFixed(1)} g',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            food.hasEnergyMismatch
                ? 'The macros imply ${estimate.toStringAsFixed(0)} kcal (4/4/9). '
                      'The declared value disagrees — this row was accepted with '
                      'an explicit energy-mismatch override, or predates '
                      'validation.'
                : 'The macros imply ${estimate.toStringAsFixed(0)} kcal (4/4/9), '
                      'consistent with the declared value.',
            style: AppText.body(size: 12).copyWith(
              color: food.hasEnergyMismatch ? p.error : p.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _micronutrients(BuildContext context) {
    final p = context.palette;
    return FoodCard(
      title: 'MICRONUTRIENTS · PER 100 g',
      child: food.micros.isEmpty
          ? Text(
              'None recorded. Micronutrients are optional — the platform stores '
              'only what a source actually published rather than inventing '
              'zeroes that would read as fact.',
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            )
          : Wrap(
              spacing: 28,
              runSpacing: 14,
              children: [
                for (final e in food.micros.entries)
                  FoodStat(
                    label: _microLabel(e.key),
                    value: '${e.value.toStringAsFixed(1)} ${_microUnit(e.key)}',
                  ),
              ],
            ),
    );
  }

  Widget _servingSizes(BuildContext context) {
    final p = context.palette;
    return FoodCard(
      title: 'SERVING SIZES',
      child: food.portions.isEmpty
          ? Text(
              'No household portions. Coaches can still enter grams, but a '
              'portion like "katori · 150 g" is what makes a plan quick to '
              'build.',
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            )
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final portion in food.portions)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: p.surfaceAlt,
                      borderRadius: AppRadii.smR,
                      border: Border.all(color: p.border),
                    ),
                    child: Text(
                      '${portion.label} · ${portion.grams.toStringAsFixed(0)} g'
                      '  ·  ${(food.calories * portion.grams / 100).toStringAsFixed(0)} kcal',
                      style: AppText.body(
                        size: 12.5,
                      ).copyWith(color: p.textPrimary),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _searchMetadata(BuildContext context) {
    final p = context.palette;
    return FoodCard(
      title: 'SEARCH METADATA',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What a coach can type to find this food.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 12),
          _labelled(context, 'Canonical name', food.name),
          if (food.brand.isNotEmpty) _labelled(context, 'Brand', food.brand),
          const SizedBox(height: 10),
          Text(
            'ALIASES',
            style: AppText.body(size: 10.5).copyWith(
              color: p.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
          if (food.aliases.isEmpty)
            Text(
              'None. An alias is how a regional name reaches a canonical food — '
              'file "Cottage Cheese" with the alias "Paneer" and both searches '
              'land on the same row.',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final alias in food.aliases)
                  FoodPill(label: alias, color: p.accent),
              ],
            ),
        ],
      ),
    );
  }

  Widget _relationships(BuildContext context) {
    final p = context.palette;
    return FoodCard(
      title: 'RELATIONSHIPS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelled(
            context,
            'Category',
            controller.categoryPath(food.categoryId).isEmpty
                ? 'Uncategorised'
                : controller.categoryPath(food.categoryId),
          ),
          _labelled(context, 'Type', food.foodType),
          if (food.mergedInto.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.error.withValues(alpha: 0.08),
                borderRadius: AppRadii.smR,
              ),
              child: Text(
                'This food was merged into another and archived. Plans that '
                'already use it still resolve; its name now searches as an '
                'alias of the food that replaced it.',
                style: AppText.body(size: 12).copyWith(color: p.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _usage(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final usage = controller.detailUsage.value;
      final loading = controller.isLoadingDetail.value;
      return FoodCard(
        title: 'USAGE',
        trailing: TextButton.icon(
          onPressed: loading ? null : controller.reloadDetail,
          icon: const Icon(Icons.refresh, size: 15),
          label: const Text('Refresh'),
        ),
        child: loading && usage == null
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : usage == null
            ? Text(
                'Usage could not be measured. It is computed live from the '
                'plan index, so this is a transient failure, not a zero.',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 28,
                    runSpacing: 14,
                    children: [
                      FoodStat(
                        label: 'diet plans',
                        value: '${usage.plans}${usage.truncated ? '+' : ''}',
                      ),
                      FoodStat(
                        label: 'organizations',
                        value: '${usage.organizations}',
                        color: usage.organizations > 0 ? p.accent : null,
                      ),
                      FoodStat(label: 'trainers', value: '${usage.trainers}'),
                      FoodStat(label: 'members', value: '${usage.members}'),
                      FoodStat(
                        label: 'assignments',
                        value: '${usage.assignments}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    usage.isUnused
                        ? 'Not used by anyone. Safe to archive.'
                        : 'Last used ${foodWhen(usage.lastUsedAt)}. Archiving '
                              'hides it from search; every existing plan keeps '
                              'working.',
                    style: AppText.body(size: 12).copyWith(color: p.textMuted),
                  ),
                  if (usage.computedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Measured live just now.',
                        style: AppText.body(
                          size: 11,
                        ).copyWith(color: p.textMuted),
                      ),
                    ),
                ],
              ),
      );
    });
  }

  Widget _history(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final entries = controller.detailHistory;
      return FoodCard(
        title: 'REVISION HISTORY',
        child: entries.isEmpty
            ? Text(
                controller.isLoadingDetail.value
                    ? 'Loading…'
                    : 'No recorded revisions. Entries are written by the server '
                          'on every change; a food created before the trail '
                          'existed starts empty.',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in entries) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6, right: 10),
                          decoration: BoxDecoration(
                            color: p.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${e.title}'
                                '${e.revision > 0 ? ' · rev ${e.revision}' : ''}',
                                style: AppText.label(
                                  size: 12.5,
                                ).copyWith(color: p.textPrimary),
                              ),
                              Text(
                                [
                                  foodWhen(e.at),
                                  if (e.actorUid.isNotEmpty) e.actorUid,
                                  if (e.from.isNotEmpty) '${e.from} → ${e.to}',
                                ].join('  ·  '),
                                style: AppText.body(
                                  size: 11,
                                ).copyWith(color: p.textMuted),
                              ),
                              if (e.reason.isNotEmpty)
                                Text(
                                  '"${e.reason}"',
                                  style: AppText.body(size: 11.5).copyWith(
                                    color: p.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              if (e.changes.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    e.changes
                                        .map((c) => '${c.field}: ${c.from} → ${c.to}')
                                        .join('   '),
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
                    const SizedBox(height: 14),
                  ],
                ],
              ),
      );
    });
  }

  // ── Small pieces ───────────────────────────────────────────────────

  Widget _grid(BuildContext context, List<(String, String)> rows) {
    return Wrap(
      spacing: 40,
      runSpacing: 14,
      children: [
        for (final row in rows)
          SizedBox(width: 200, child: _labelled(context, row.$1, row.$2)),
      ],
    );
  }

  Widget _labelled(BuildContext context, String label, String value) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.body(size: 10).copyWith(
              color: p.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppText.body(size: 13).copyWith(color: p.textPrimary),
          ),
        ],
      ),
    );
  }

  static String _microLabel(String key) => switch (key) {
    'saturatedFat' => 'saturated fat',
    'monounsaturatedFat' => 'mono fat',
    'polyunsaturatedFat' => 'poly fat',
    'transFat' => 'trans fat',
    'vitaminA' => 'vitamin A',
    'vitaminC' => 'vitamin C',
    'vitaminD' => 'vitamin D',
    'vitaminB12' => 'vitamin B12',
    _ => key,
  };

  /// Units follow the platform schema: µg for the fat-soluble vitamins and
  /// B12/folate, g for fat sub-types, mg for everything else.
  static String _microUnit(String key) => switch (key) {
    'vitaminA' || 'vitaminD' || 'vitaminB12' || 'folate' => 'µg',
    'transFat' || 'monounsaturatedFat' || 'polyunsaturatedFat' => 'g',
    _ => 'mg',
  };
}
