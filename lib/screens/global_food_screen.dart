import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/global_food_controller.dart';
import '../core/services/food_platform_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_text.dart';
import '../models/global_food_model.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/food/food_analytics_panel.dart';
import '../widgets/food/food_categories_panel.dart';
import '../widgets/food/food_detail_panel.dart';
import '../widgets/food/food_duplicates_panel.dart';
import '../widgets/food/food_import_wizard.dart';
import '../widgets/food/food_list_panel.dart';
import '../widgets/food/food_wizard_dialog.dart';

/// FOOD PLATFORM — the Global Food Database console.
///
/// The Super Admin's sole authoring surface for platform food. Everything here
/// operates on `scope == 'global'` documents only: an organization's private
/// library is never listed, never searched and never editable from this screen,
/// because the queries behind it cannot express anything but the platform tier.
///
/// Nothing on this screen writes Firestore directly. Every action is a Cloud
/// Function call — the security rules deny client writes to `foodDatabase` to
/// everyone including this console — so every change carries a server-written
/// audit entry and an immutable revision record.
class GlobalFoodScreen extends StatefulWidget {
  const GlobalFoodScreen({super.key});

  @override
  State<GlobalFoodScreen> createState() => _GlobalFoodScreenState();
}

enum _Tab { dashboard, foods, categories, duplicates, tools }

class _GlobalFoodScreenState extends State<GlobalFoodScreen> {
  /// Registered in [initState], not as a field initializer.
  ///
  /// AdminRootController swaps cached pages through an AnimatedSwitcher, so the
  /// OUTGOING screen's `dispose` can run AFTER the incoming screen's
  /// `initState`. Registering and tearing down blindly would let a departing
  /// screen delete the controller the arriving one just created.
  late final GlobalFoodController c;

  _Tab _tab = _Tab.dashboard;

  @override
  void initState() {
    super.initState();
    // A stale instance from a previous visit is torn down properly (so its
    // Firestore category listener is cancelled) rather than silently replaced.
    if (Get.isRegistered<GlobalFoodController>()) {
      Get.delete<GlobalFoodController>(force: true);
    }
    c = Get.put(GlobalFoodController());
  }

  @override
  void dispose() {
    // Only tear down if the registered instance is still OURS. If a newer
    // screen has already replaced it, deleting here would kill the live one.
    if (Get.isRegistered<GlobalFoodController>() &&
        identical(Get.find<GlobalFoodController>(), c)) {
      Get.delete<GlobalFoodController>(force: true);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final open = c.detail.value;
      // The detail view REPLACES the shell rather than stacking a dialog on it:
      // a curator reading a food's usage and revision history needs the whole
      // width, and a modal over a list is the classic way to lose your place.
      if (open != null) {
        // The detail panel scrolls itself, so it gets the remaining height
        // rather than an unbounded one.
        return _shell(
          context,
          body: FoodDetailPanel(
            controller: c,
            food: open,
            onClose: c.closeDetail,
            onEdit: (food) => _openWizard(existing: food),
            onDuplicate: (food) =>
                _openWizard(existing: food, duplicating: true),
          ),
        );
      }

      return _shell(
        context,
        trailing: _headerActions(context),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ownershipBanner(context),
            const SizedBox(height: 16),
            _tabs(context),
            const SizedBox(height: 18),
            // Each tab is given the remaining height so its own list can scroll
            // internally — the shell must never become one giant scroll view or
            // the foods list loses its infinite pagination.
            Expanded(
              child: switch (_tab) {
                _Tab.dashboard => FoodAnalyticsPanel(
                  controller: c,
                  onDrillDown: _drillDown,
                  onOpenFood: _openById,
                ),
                _Tab.foods => FoodListPanel(
                  controller: c,
                  onOpen: c.openDetail,
                  onCreate: _openWizard,
                ),
                _Tab.categories => FoodCategoriesPanel(
                  controller: c,
                  onDrillDown: _drillDown,
                ),
                _Tab.duplicates => FoodDuplicatesPanel(
                  controller: c,
                  onOpenFood: _openById,
                ),
                _Tab.tools => _toolsTab(context),
              },
            ),
          ],
        ),
      );
    });
  }

  /// The console frame: the standard page header plus a BOUNDED body.
  ///
  /// Deliberately not `PageShell` — that helper wraps its child in a
  /// `SingleChildScrollView`, which would hand this screen an unbounded height.
  /// Every panel below scrolls internally, and the foods list needs a real
  /// viewport to drive its infinite pagination; an outer scroll view would
  /// break both and throw on the first `Expanded`.
  Widget _shell(BuildContext context, {required Widget body, Widget? trailing}) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.smR,
              ),
              child: Icon(Icons.restaurant_menu_outlined, color: p.accent),
            ),
            const SizedBox(width: 14),
            Text(
              'Global Food Database',
              style: AppText.title(size: 26).copyWith(color: p.textPrimary),
            ),
            const Spacer(),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 20),
        Expanded(child: body),
      ],
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────

  /// Jumps from a dashboard tile or a category count into the filtered list.
  void _drillDown(FoodQuery query) {
    setState(() => _tab = _Tab.foods);
    c.setQuery(query);
  }

  /// Opens a food from a panel that only holds its id.
  Future<void> _openById(String id) async {
    final matches = await c.resolveFoods([id]);
    if (matches.isEmpty) {
      AppSnackbar.show(
        title: 'Not found',
        message: 'That food no longer exists.',
      );
      return;
    }
    await c.openDetail(matches.first);
  }

  Future<void> _openWizard({
    GlobalFoodModel? existing,
    bool duplicating = false,
  }) async {
    await Get.dialog(
      FoodWizardDialog(
        controller: c,
        existing: existing,
        duplicating: duplicating,
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _openImport({bool seedMode = false}) async {
    await Get.dialog(
      FoodImportWizard(controller: c, seedMode: seedMode),
      barrierDismissible: false,
    );
  }

  // ── Chrome ─────────────────────────────────────────────────────────

  Widget _headerActions(BuildContext context) {
    return Wrap(
      spacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: () => _openImport(),
          icon: const Icon(Icons.upload_file, size: 17),
          label: const Text('Import'),
        ),
        FilledButton.icon(
          onPressed: () => _openWizard(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New food'),
        ),
      ],
    );
  }

  /// Makes the ownership boundary legible rather than assumed. A curator must
  /// never wonder whether an edit here reaches into a gym's private recipes.
  Widget _ownershipBanner(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.08),
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.public, size: 18, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Platform foods only. Every organization on the platform can read '
              'these; none can edit them. Organizations own their private '
              'recipes separately and nothing here touches them.',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs(BuildContext context) {
    final p = context.palette;

    Widget tab(String label, IconData icon, _Tab value, {int? badge}) {
      final active = _tab == value;
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        // Same fix as the Exercise Library tabs, and for the same reason:
        // ExcludeSemantics stripped the detector's tap action out of the tree
        // and the outer Semantics never re-declared one, so each tab was a
        // button with no action and no focusability. InkWell restores both,
        // and its merged label announces the badge count too — which the
        // hand-written `label:` silently dropped.
        child: Semantics(
          selected: active,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _tab = value),
              borderRadius: AppRadii.smR,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: active ? p.accent : p.surface,
                  borderRadius: AppRadii.smR,
                  border: Border.all(color: active ? p.accent : p.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: active ? Colors.white : p.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: AppText.label(size: 13).copyWith(
                        color: active ? Colors.white : p.textSecondary,
                      ),
                    ),
                    if (badge != null && badge > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.white.withValues(alpha: 0.25)
                              : p.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$badge',
                          style: AppText.body(size: 10.5).copyWith(
                            color: active ? Colors.white : p.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Obx(() {
      final needsReview = c.analytics.value?.awaitingReviewTotal ?? 0;
      return Row(
        children: [
          tab('Dashboard', Icons.insights_outlined, _Tab.dashboard),
          tab('Foods', Icons.set_meal_outlined, _Tab.foods, badge: needsReview),
          tab('Categories', Icons.category_outlined, _Tab.categories),
          tab(
            'Duplicates',
            Icons.content_copy_outlined,
            _Tab.duplicates,
            badge: c.duplicateGroups.length,
          ),
          tab('Tools', Icons.build_outlined, _Tab.tools),
        ],
      );
    });
  }

  // ── Tools ──────────────────────────────────────────────────────────

  Widget _toolsTab(BuildContext context) {
    final p = context.palette;
    return Obx(
      () => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.isBusy.value)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            _toolCard(
              context,
              title: 'Found the library from the seed catalog',
              body:
                  'The curated Indian dataset that used to be bundled inside '
                  'the TrainerHQ app. It is frozen migration data now — no app '
                  'reads it at runtime. Import it ONCE to found the global '
                  'library.\n\n'
                  'The importer always validates first and shows you exactly '
                  'what it would write before anything is created.',
              actions: [
                FilledButton.icon(
                  onPressed: c.isBusy.value
                      ? null
                      : () => _openImport(seedMode: true),
                  icon: const Icon(Icons.auto_awesome_motion, size: 17),
                  label: const Text('Open seed importer'),
                ),
              ],
            ),
            _toolCard(
              context,
              title: 'Export the global library',
              body:
                  'Produces the full global tier as JSON in the exact shape the '
                  'importer accepts, so an export from one environment imports '
                  'into another untransformed.',
              actions: [
                OutlinedButton(
                  onPressed: c.isBusy.value ? null : () => c.runExport(),
                  child: const Text('Export published'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: c.isBusy.value
                      ? null
                      : () => c.runExport(includeArchived: true),
                  child: const Text('Include archived'),
                ),
                if (c.lastExportJson.value != null) ...[
                  const SizedBox(width: 10),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: c.lastExportJson.value!),
                      );
                      AppSnackbar.show(
                        title: 'Copied',
                        message: 'The export is on your clipboard.',
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ],
              ],
              footer: c.lastExportJson.value == null
                  ? null
                  : Text(
                      '${c.lastExportJson.value!.length} characters ready to '
                      'copy.',
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: p.textMuted),
                    ),
            ),
            _toolCard(
              context,
              title: 'Measure usage across the platform',
              body:
                  'Usage answers "what would archiving this food affect". It is '
                  'computed from a flat index of the foods each diet plan and '
                  'assignment references.\n\n'
                  'Plans written before that index existed carry no entry, so '
                  'run this ONCE per collection to populate it. Purely '
                  'additive and idempotent: it writes a single derived field '
                  'and touches nothing a member can see.',
              actions: [
                OutlinedButton(
                  onPressed: c.isBusy.value
                      ? null
                      : () => c.runBackfill(
                          dryRun: true,
                          usageCollection: 'dietPlans',
                        ),
                  child: const Text('Dry run · plans'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: c.isBusy.value
                      ? null
                      : () => c.runBackfill(
                          dryRun: false,
                          usageCollection: 'dietPlans',
                        ),
                  child: const Text('Index diet plans'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: c.isBusy.value
                      ? null
                      : () => c.runBackfill(
                          dryRun: false,
                          usageCollection: 'client_plan_assignments',
                        ),
                  child: const Text('Index assignments'),
                ),
              ],
            ),
            _toolCard(
              context,
              title: 'Upgrade legacy organization foods',
              body:
                  'Stamps the platform fields onto foods authored before the '
                  'platform existed. Purely additive and idempotent: nutrition, '
                  'portions, ownership and document ids are never touched, so '
                  'no diet plan can shift underneath a member.\n\n'
                  'The platform is already CORRECT without this — organization '
                  'queries use only fields every legacy document has. This '
                  'upgrades those foods to server-side token search.',
              actions: [
                OutlinedButton(
                  onPressed: c.isBusy.value
                      ? null
                      : () => c.runBackfill(dryRun: true),
                  child: const Text('Dry run'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: c.isBusy.value
                      ? null
                      : () => c.runBackfill(dryRun: false),
                  child: const Text('Run'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolCard(
    BuildContext context, {
    required String title,
    required String body,
    required List<Widget> actions,
    Widget? footer,
  }) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 0, runSpacing: 8, children: actions),
          if (footer != null) ...[const SizedBox(height: 14), footer],
        ],
      ),
    );
  }
}
