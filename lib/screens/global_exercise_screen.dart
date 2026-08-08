import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/global_exercise_controller.dart';
import '../core/services/exercise_catalog_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_text.dart';
import '../models/global_exercise_model.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/exercise/exercise_form_dialog.dart';
import '../widgets/exercise/exercise_import_wizard.dart';
import '../widgets/exercise/exercise_list_panel.dart';
import '../widgets/exercise/exercise_overview_panel.dart';

/// GLOBAL EXERCISE LIBRARY — the Super Admin's master exercise catalog.
///
/// The single authoring surface for `exerciseCatalog`. Everything here operates
/// on the platform catalog only: an organization's own `exercises` library is
/// never listed, never searched and never editable from this screen — the
/// queries behind it cannot express anything but the catalog.
///
/// Nothing on this screen writes Firestore directly. Every action is a Cloud
/// Function call — the rules deny client writes to `exerciseCatalog` to
/// everyone including this console — so every change carries a server-written
/// audit entry.
///
/// ── THIS CATALOG IS LIVE ────────────────────────────────────────────────
/// TrainerHQ's workout builder searches these rows and a saved workout stores
/// the catalog id; AlphaSerena hydrates a member's exercise from it. Nothing is
/// copied into a gym's own `exercises` library — a workout REFERENCES this row.
/// So an edit made here is visible to every member already training on it, and
/// an archive withdraws the row from new selection without breaking the
/// workouts that already point at it.
class GlobalExerciseScreen extends StatefulWidget {
  const GlobalExerciseScreen({super.key});

  @override
  State<GlobalExerciseScreen> createState() => _GlobalExerciseScreenState();
}

enum _Tab { overview, exercises, importTools }

class _GlobalExerciseScreenState extends State<GlobalExerciseScreen> {
  /// Registered in [initState], not as a field initializer.
  ///
  /// AdminRootController swaps cached pages through an AnimatedSwitcher, so the
  /// OUTGOING screen's `dispose` can run AFTER the incoming screen's
  /// `initState`. Registering and tearing down blindly would let a departing
  /// screen delete the controller the arriving one just created.
  late final GlobalExerciseController c;

  _Tab _tab = _Tab.overview;

  @override
  void initState() {
    super.initState();
    // A stale instance from a previous visit is torn down properly rather than
    // silently replaced.
    if (Get.isRegistered<GlobalExerciseController>()) {
      Get.delete<GlobalExerciseController>(force: true);
    }
    c = Get.put(GlobalExerciseController());
  }

  @override
  void dispose() {
    // Only tear down if the registered instance is still OURS. If a newer
    // screen has already replaced it, deleting here would kill the live one.
    if (Get.isRegistered<GlobalExerciseController>() &&
        identical(Get.find<GlobalExerciseController>(), c)) {
      Get.delete<GlobalExerciseController>(force: true);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          // the catalog list loses its infinite pagination.
          Expanded(
            child: switch (_tab) {
              _Tab.overview => ExerciseOverviewPanel(
                controller: c,
                onDrillDown: _drillDown,
              ),
              _Tab.exercises => ExerciseListPanel(
                controller: c,
                onEdit: (exercise) => _openForm(existing: exercise),
                onCreate: _openForm,
              ),
              _Tab.importTools => _toolsTab(context),
            },
          ),
        ],
      ),
    );
  }

  /// The console frame: the standard page header plus a BOUNDED body.
  ///
  /// Deliberately not `PageShell` — that helper wraps its child in a
  /// `SingleChildScrollView`, which would hand this screen an unbounded height.
  /// Every panel below scrolls internally, and the catalog list needs a real
  /// viewport to drive its infinite pagination; an outer scroll view would
  /// break both and throw on the first `Expanded`.
  Widget _shell(
    BuildContext context, {
    required Widget body,
    Widget? trailing,
  }) {
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
              child: Icon(Icons.sports_gymnastics_outlined, color: p.accent),
            ),
            const SizedBox(width: 14),
            Text(
              'Global Exercise Library',
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

  /// Jumps from an overview category row into the filtered list.
  void _drillDown(ExerciseQuery query) {
    setState(() => _tab = _Tab.exercises);
    c.setQuery(query);
  }

  Future<void> _openForm({GlobalExerciseModel? existing}) async {
    await Get.dialog(
      ExerciseFormDialog(controller: c, existing: existing),
      barrierDismissible: false,
    );
  }

  Future<void> _openImport({bool seedMode = false}) async {
    await Get.dialog(
      ExerciseImportWizard(controller: c, seedMode: seedMode),
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
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New exercise'),
        ),
      ],
    );
  }

  /// Makes the ownership boundary legible rather than assumed. A curator must
  /// never wonder whether an edit here reaches into a gym's own library, or
  /// whether deleting a row breaks somebody's programme.
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
              'The master catalog. Coaches SEARCH it from the workout builder '
              'and their workouts POINT AT these rows — nothing is ever copied '
              'into a gym\'s own library, and nothing here edits a gym\'s own '
              'exercises. Because workouts reference these rows, an edit here '
              'reaches every member already training on them; archiving '
              'withdraws a row from new selection while existing workouts keep '
              'working.',
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
      void select() => setState(() => _tab = value);
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        // An InkWell, NOT a Semantics-wrapped GestureDetector.
        //
        // This was `Semantics(button: true, label: …)` around
        // `ExcludeSemantics(GestureDetector(onTap: …))`. ExcludeSemantics
        // strips the detector's tap action out of the tree and the outer
        // Semantics never re-declared one, so each tab was published as a
        // button carrying no action and no focusability — verified in the
        // running console as a node with neither `flt-tappable` nor
        // `tabindex`. Assistive tech could announce the tab and not press it,
        // and a keyboard could not reach it at all. Everything on this screen
        // except the Overview — the list, search, every filter, all four
        // sorts, import and export — sits behind these three tabs.
        //
        // InkWell owns the whole contract: it is focusable (so it gets a
        // tabindex), it activates on Enter/Space as well as tap, and it
        // publishes its own button semantics whose label merges the child
        // Text — which means the tab's count badge is announced too, where
        // the hand-written `label:` silently dropped it.
        child: Semantics(
          selected: active,
          child: InkWell(
            onTap: select,
            borderRadius: AppRadii.smR,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    style: AppText.label(
                      size: 13,
                    ).copyWith(color: active ? Colors.white : p.textSecondary),
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
                            : p.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$badge',
                        style: AppText.body(size: 10.5).copyWith(
                          color: active ? Colors.white : p.accent,
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
      );
    }

    return Obx(() {
      final total = c.analytics.value?.total ?? 0;
      return Row(
        children: [
          tab('Overview', Icons.insights_outlined, _Tab.overview),
          tab(
            'Exercises',
            Icons.fitness_center_outlined,
            _Tab.exercises,
            badge: total,
          ),
          tab('Import & tools', Icons.build_outlined, _Tab.importTools),
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
              title: 'Found the catalog from the master dataset',
              body:
                  '844 professionally named exercises across all 20 '
                  'categories, bundled with this console. No videos — clean '
                  'names and categories only.\n\n'
                  'The importer always validates first and shows you exactly '
                  'what it would write before anything is created. Duplicates '
                  'are detected by normalized name, so running it twice is '
                  'harmless.',
              actions: [
                FilledButton.icon(
                  onPressed: c.isBusy.value
                      ? null
                      : () => _openImport(seedMode: true),
                  icon: const Icon(Icons.auto_awesome_motion, size: 17),
                  label: const Text('Open the master importer'),
                ),
              ],
            ),
            _toolCard(
              context,
              title: 'Import your own file',
              body:
                  'CSV or JSON. A CSV needs a name column and a category '
                  'column; every other column is optional and anything the '
                  'importer does not recognise is reported rather than '
                  'silently dropped.\n\n'
                  'Excel workbooks are a binary format this console cannot '
                  'read — export the sheet as CSV first.',
              actions: [
                OutlinedButton.icon(
                  onPressed: c.isBusy.value ? null : () => _openImport(),
                  icon: const Icon(Icons.upload_file, size: 17),
                  label: const Text('Open the importer'),
                ),
              ],
            ),
            _toolCard(
              context,
              title: 'Find duplicate names',
              body:
                  'Reports exercises whose names collapse to the same identity '
                  '("Push-Up" and "push up"). The importer already prevents '
                  'these, so a non-empty result means rows were created before '
                  'the catalog existed in this form, or by hand.',
              actions: [
                OutlinedButton.icon(
                  onPressed: c.isBusy.value ? null : c.scanDuplicates,
                  icon: const Icon(Icons.content_copy_outlined, size: 17),
                  label: const Text('Scan for duplicates'),
                ),
              ],
              footer: c.duplicateSummary.value == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.duplicateSummary.value!,
                          style: AppText.body(
                            size: 12.5,
                          ).copyWith(color: p.textSecondary),
                        ),
                        if (c.duplicateGroups.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          for (final g in c.duplicateGroups.take(20))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '"${g.name}" — ${g.ids.length} copies',
                                style: AppText.body(
                                  size: 12,
                                ).copyWith(color: p.error),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
            _toolCard(
              context,
              title: 'Export the catalog',
              body:
                  'Produces the whole catalog as JSON in the exact shape the '
                  'importer accepts, so an export from one environment imports '
                  'into another untransformed.',
              actions: [
                OutlinedButton(
                  onPressed: c.isBusy.value ? null : () => c.runExport(),
                  child: const Text('Export active'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: c.isBusy.value
                      ? null
                      : () => c.runExport(includeInactive: true),
                  child: const Text('Include inactive'),
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
              title: 'Video uploads',
              body:
                  'Deliberately NOT built in this foundation. The catalog '
                  'already stores everything an uploader will need — videoUrl, '
                  'thumbnailUrl, videoProvider and duration are on every '
                  'document — so adding one later is a feature, not a schema '
                  'change plus a re-import of 844 rows.\n\n'
                  'Until then an https video URL can be set by hand in the '
                  'exercise editor, and every exercise without one says "No '
                  'video uploaded" rather than showing an empty player.',
              actions: const [],
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
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 0, runSpacing: 8, children: actions),
          ],
          if (footer != null) ...[const SizedBox(height: 14), footer],
        ],
      ),
    );
  }
}
