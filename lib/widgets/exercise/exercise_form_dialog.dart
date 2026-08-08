import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_exercise_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_exercise_model.dart';
import 'exercise_chrome.dart';

/// GLOBAL EXERCISE LIBRARY — the create / edit form.
///
/// Deliberately SMALL. The catalog's contract is a clean name in a real
/// category (mission Phase 2), and a form that demanded instructions, muscle
/// lists and difficulty for every one of 844 rows would guarantee that none of
/// them were ever filled in honestly. The future-ready fields are stored on
/// every document and simply not collected here yet.
///
/// The server re-validates everything and is the authority: it refuses a
/// duplicate name, an unknown category and a non-https video URL. This form
/// mirrors those rules only to give immediate feedback — it never replaces
/// them.
class ExerciseFormDialog extends StatefulWidget {
  final GlobalExerciseController controller;
  final GlobalExerciseModel? existing;

  const ExerciseFormDialog({
    super.key,
    required this.controller,
    this.existing,
  });

  @override
  State<ExerciseFormDialog> createState() => _ExerciseFormDialogState();
}

class _ExerciseFormDialogState extends State<ExerciseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _aliases;
  late final TextEditingController _videoUrl;
  late final TextEditingController _equipment;

  late String _category;
  late bool _isActive;

  GlobalExerciseController get c => widget.controller;
  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _aliases = TextEditingController(text: e?.aliases.join(', ') ?? '');
    _videoUrl = TextEditingController(text: e?.videoUrl ?? '');
    _equipment = TextEditingController(text: e?.equipment ?? '');
    // A stored category that is not in this build's vocabulary must not be
    // silently rewritten to "Chest" by a dropdown that cannot represent it.
    //
    // The vocabulary is declared twice — TypeScript on the server, Dart here —
    // so a console running one release behind can be handed a category it does
    // not know. Defaulting to the first entry would show the operator "Chest"
    // for a row that is not Chest, and then WRITE that lie the next time they
    // corrected a typo in the name. The stored value is kept verbatim instead
    // and [_categoryOptions] widens the dropdown to include it, so an edit to
    // some other field round-trips the category untouched.
    _category = e?.category.isNotEmpty == true
        ? e!.category
        : kExerciseCategories.first;
    _isActive = e?.isActive ?? true;
    // A previous failure belongs to a previous form.
    c.writeError.value = null;
  }

  @override
  void dispose() {
    _name.dispose();
    _aliases.dispose();
    _videoUrl.dispose();
    _equipment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _nameField(context),
                      const SizedBox(height: 18),
                      _categoryField(context),
                      const SizedBox(height: 18),
                      _aliasesField(context),
                      const SizedBox(height: 18),
                      _videoField(context),
                      const SizedBox(height: 18),
                      _equipmentField(context),
                      const SizedBox(height: 18),
                      _activeField(context),
                      // The inline write error. A toast that vanishes in two
                      // seconds is not adequate feedback for a refused save:
                      // the operator is left staring at a form that will not
                      // close with no statement of what is wrong.
                      Obx(() {
                        final failure = c.writeError.value;
                        if (failure == null) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 18),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: p.error.withValues(alpha: 0.08),
                            borderRadius: AppRadii.smR,
                            border: Border.all(
                              color: p.error.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline, size: 17, color: p.error),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SelectableText(
                                  failure.message,
                                  style: AppText.body(size: 12.5).copyWith(
                                    color: p.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: AppRadii.smR,
            ),
            child: Icon(
              isEditing ? Icons.edit_outlined : Icons.add,
              color: p.accent,
              size: 19,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit exercise' : 'New catalog exercise',
                  style: AppText.cardTitle(
                    size: 17,
                  ).copyWith(color: p.textPrimary),
                ),
                if (isEditing)
                  Text(
                    'Revision ${widget.existing!.revision} · '
                    '${widget.existing!.source}',
                    style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, size: 20),
            onPressed: Get.back,
          ),
        ],
      ),
    );
  }

  Widget _nameField(BuildContext context) {
    return TextFormField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: _decoration(
        context,
        label: 'Name',
        hint: 'Barbell Bench Press',
        helper:
            'The catalog treats "Push-Up", "push up" and "PUSH  UP" as one '
            'exercise, so a duplicate cannot be created by punctuation alone.',
      ),
      validator: (v) {
        final value = (v ?? '').trim();
        if (value.length < 2) return 'A name of at least 2 characters.';
        if (value.length > 120) return 'At most 120 characters.';
        return null;
      },
    );
  }

  /// The 20 known categories, plus the stored one when this build does not
  /// recognise it — a `DropdownButtonFormField` whose value is absent from its
  /// items asserts, and dropping the value instead is the silent rewrite this
  /// widens the list to prevent.
  List<String> get _categoryOptions => kExerciseCategories.contains(_category)
      ? kExerciseCategories
      : [_category, ...kExerciseCategories];

  Widget _categoryField(BuildContext context) {
    final unknown = !kExerciseCategories.contains(_category);
    return DropdownButtonFormField<String>(
      initialValue: _category,
      isExpanded: true,
      decoration: _decoration(
        context,
        label: 'Category',
        helper: unknown
            // Named, not hidden: the server WILL refuse this value, so the
            // operator needs to know why their save bounced and that choosing
            // a listed category is the fix.
            ? '"$_category" is not one of this build\'s 20 categories. It has '
                  'been left exactly as stored — saving will be refused by the '
                  'server until you pick one of the listed categories.'
            : 'One of the 20 catalog categories. The server refuses anything '
                  'else — a row in an unknown category is invisible in every '
                  'filter.',
      ),
      items: [
        for (final category in _categoryOptions)
          DropdownMenuItem(value: category, child: Text(category)),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _category = v);
      },
    );
  }

  Widget _aliasesField(BuildContext context) {
    return TextFormField(
      controller: _aliases,
      decoration: _decoration(
        context,
        label: 'Aliases (optional)',
        hint: 'Bench Press, Flat Press',
        helper:
            'Comma-separated. Indexed for search, so a coach who calls it '
            'something else still finds it.',
      ),
    );
  }

  Widget _videoField(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _videoUrl,
          decoration: _decoration(
            context,
            label: 'Video URL (optional)',
            hint: 'https://…',
            helper:
                'Must be https. The uploader is not built yet — this is the '
                'manual escape hatch until it is.',
          ),
          validator: (v) {
            final value = (v ?? '').trim();
            if (value.isEmpty) return null;
            // Mirrors the server rule. A catalog every organization imports
            // from must never hand out a mixed-content or javascript: URL.
            if (!RegExp(r'^https://', caseSensitive: false).hasMatch(value)) {
              return 'Must start with https://';
            }
            return null;
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            ExerciseVideoPill(_videoUrl.text.trim().isNotEmpty),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              // BUTTON ONLY (mission Phase 6). It says what it is rather than
              // opening a picker that would fail.
              onPressed: () => _explainUploader(context),
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('Upload video'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Not built yet',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _equipmentField(BuildContext context) {
    return TextFormField(
      controller: _equipment,
      decoration: _decoration(
        context,
        label: 'Equipment (optional)',
        hint: 'Barbell, flat bench',
        helper:
            'Stored today, read by nothing. It exists so that populating it '
            'later is a data change rather than a schema change.',
      ),
    );
  }

  Widget _activeField(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      // A ListTile paints its background and ink on the nearest Material
      // ANCESTOR, which here is the dialog's own surface — underneath this
      // decorated Container. Without a Material of its own the row's tap
      // feedback is painted where nothing can see it, and the framework
      // asserts. Transparent, so the Container's fill is still what shows.
      child: Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
          title: Text(
            'Active',
            style: AppText.label(size: 13.5).copyWith(color: p.textPrimary),
          ),
          // Organizations USE catalog rows in place; they do not import copies.
          // The old wording ("offered to organizations to import") described the
          // abandoned copy-on-import design and would send a founder looking
          // for an import screen that no longer exists.
          //
          // The archived case is called out separately because saving with the
          // switch ON genuinely RESTORES the exercise — `upsertGlobalExercise`
          // un-archives when the result is active — and a founder who cannot
          // see that is being asked to guess.
          subtitle: Text(
            (widget.existing?.isArchived ?? false)
                ? (_isActive
                      ? 'Saving will RESTORE this archived exercise — it '
                            'returns to every coach\'s exercise picker.'
                      : 'Archived. Existing workouts keep working; it is not '
                            'offered for new ones.')
                : _isActive
                ? 'Offered to every organization in the exercise picker.'
                : 'Kept in the catalog, but not offered. Nothing is deleted.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Obx(
        () => Row(
          children: [
            Expanded(
              child: Text(
                'Saved through a Cloud Function — the console cannot write the '
                'catalog directly.',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ),
            TextButton(
              onPressed: c.isSaving.value ? null : Get.back,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: c.isSaving.value ? null : _save,
              child: c.isSaving.value
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text(isEditing ? 'Save changes' : 'Create exercise'),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context, {
    required String label,
    String? hint,
    String? helper,
  }) {
    final p = context.palette;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      isDense: true,
      filled: true,
      fillColor: p.surface,
      border: OutlineInputBorder(
        borderRadius: AppRadii.smR,
        borderSide: BorderSide(color: p.border),
      ),
    );
  }

  void _explainUploader(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text('Upload video'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: const Text(
            'The video uploader is deliberately not built in this foundation.\n\n'
            'The catalog already stores everything it will need — videoUrl, '
            'thumbnailUrl, videoProvider and duration — so adding the uploader '
            'later needs no schema change and no re-import of the 844 '
            'exercises.\n\n'
            'Until then, paste an https video URL into the field above.',
          ),
        ),
        actions: [
          FilledButton(onPressed: Get.back, child: const Text('Understood')),
        ],
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final aliases = _aliases.text
        .split(RegExp(r'[;,|]'))
        .map((e) => e.trim())
        .where((e) => e.length >= 2)
        .toList();

    // ⚠️ EVERY FIELD THIS FORM DOES NOT EDIT MUST STILL BE SENT.
    //
    // `upsertGlobalExercise` builds its document from the WHOLE validated
    // payload and writes it with `ref.update({...doc})`. A field the payload
    // omits is not "unchanged" — `validateExercise` defaults it (''/[]/0) and
    // the update writes that default over the stored value.
    //
    // So this dialog, which edits six fields, used to construct a fresh model
    // and silently destroy the other nine: instructions, primaryMuscles,
    // secondaryMuscles, difficulty, mechanics, force, tips, thumbnailUrl,
    // videoProvider and videoDurationSec. Those are exactly the fields
    // AlphaSerena hydrates onto a member's workout — so a super admin fixing a
    // typo in an exercise NAME wiped the demo thumbnail and the coaching cues
    // for every member already training on it, platform-wide, with no warning
    // and nothing in the UI to show it had happened.
    //
    // Same defect, same remedy as `updateEmploymentRecord` in TrainerHQ:
    // round-trip what you do not own. Removing a CONTROL is not the same act as
    // deleting a CONCEPT. (A create has no previous row, so the defaults are
    // correct there — which is why this only ever corrupted edits.)
    final prev = widget.existing;
    final draft = GlobalExerciseModel(
      // An empty id means CREATE. Carrying the existing one means edit.
      id: prev?.id ?? '',
      name: _name.text.trim(),
      category: _category,
      videoUrl: _videoUrl.text.trim(),
      aliases: aliases,
      equipment: _equipment.text.trim(),
      isActive: _isActive,
      source: prev?.source ?? 'manual',
      sourceRef: prev?.sourceRef ?? '',
      // ── Carried through untouched; no control on this form owns them. ──
      primaryMuscles: prev?.primaryMuscles ?? const [],
      secondaryMuscles: prev?.secondaryMuscles ?? const [],
      difficulty: prev?.difficulty ?? '',
      mechanics: prev?.mechanics ?? '',
      force: prev?.force ?? '',
      instructions: prev?.instructions ?? '',
      tips: prev?.tips ?? const [],
      thumbnailUrl: prev?.thumbnailUrl ?? '',
      videoProvider: prev?.videoProvider ?? '',
      videoDurationSec: prev?.videoDurationSec ?? 0,
    );

    final saved = await c.save(draft, isActive: _isActive);
    // Only close on success. A failed save leaves the form open with the
    // server's refusal rendered inline, so nothing the operator typed is lost.
    if (saved) Get.back();
  }
}
