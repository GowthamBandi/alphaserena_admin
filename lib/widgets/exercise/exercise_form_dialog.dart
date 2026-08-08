import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_exercise_controller.dart';
import '../../core/services/exercise_video_service.dart';
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
  late final TextEditingController _primaryMuscles;
  late final TextEditingController _secondaryMuscles;
  late final TextEditingController _instructions;
  late final TextEditingController _tips;
  late final TextEditingController _thumbnailUrl;
  late final TextEditingController _videoDurationSec;

  late String _category;
  late String _difficulty;
  late String _mechanics;
  late String _force;
  late bool _isActive;

  final _videos = ExerciseVideoService();

  /// Non-null only while bytes are in flight. Holding the task is what makes
  /// Cancel real: without it the button could hide the bar but not stop the
  /// upload, and the file would still land in the bucket.
  UploadTask? _uploadTask;
  double _uploadProgress = 0;
  String? _uploadError;
  String? _pickedFileName;

  /// The object path of the video this form REPLACED, deleted only after the
  /// save succeeds. Deleting on upload would destroy the live video of an
  /// exercise whose save then failed or was cancelled.
  String? _supersededPath;

  bool get _uploading => _uploadTask != null;

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
    _primaryMuscles = TextEditingController(
      text: e?.primaryMuscles.join(', ') ?? '',
    );
    _secondaryMuscles = TextEditingController(
      text: e?.secondaryMuscles.join(', ') ?? '',
    );
    _instructions = TextEditingController(text: e?.instructions ?? '');
    // Tips are a LIST but are edited one-per-line: a coaching cue routinely
    // contains a comma ("Brace, then press"), so comma-splitting them the way
    // aliases are split would silently shear one cue into two.
    _tips = TextEditingController(text: e?.tips.join('\n') ?? '');
    _thumbnailUrl = TextEditingController(text: e?.thumbnailUrl ?? '');
    _videoDurationSec = TextEditingController(
      text: (e?.videoDurationSec ?? 0) > 0 ? '${e!.videoDurationSec}' : '',
    );
    _difficulty = _knownOr(kExerciseDifficulties, e?.difficulty);
    _mechanics = _knownOr(kExerciseMechanics, e?.mechanics);
    _force = _knownOr(kExerciseForces, e?.force);
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

  /// Keeps a stored value this build does not recognise instead of rewriting it
  /// to the first option — the same reasoning as [_categoryOptions]. Here the
  /// unknown value is simply dropped to '' ("not stated") because, unlike
  /// category, these vocabularies are resolved by `pickEnum` server-side and an
  /// unrecognised value would already have been stored as ''.
  static String _knownOr(List<String> vocabulary, String? stored) {
    final value = (stored ?? '').trim().toLowerCase();
    return vocabulary.contains(value) ? value : '';
  }

  @override
  void dispose() {
    _name.dispose();
    _aliases.dispose();
    _videoUrl.dispose();
    _equipment.dispose();
    _primaryMuscles.dispose();
    _secondaryMuscles.dispose();
    _instructions.dispose();
    _tips.dispose();
    _thumbnailUrl.dispose();
    _videoDurationSec.dispose();
    // An in-flight upload outlives this widget otherwise, and its listener
    // would call setState on a disposed State.
    _uploadTask?.cancel();
    super.dispose();
  }

  /// Splits a comma/semicolon/pipe separated list the way the server's
  /// `stringList` does: trimmed, ≥2 characters, de-duplicated, capped.
  List<String> _splitList(String raw, int limit, {String pattern = r'[;,|]'}) {
    final seen = <String>{};
    final out = <String>[];
    for (final part in raw.split(RegExp(pattern))) {
      final value = part.trim();
      if (value.length < 2) continue;
      final key = value.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(value);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
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

                      _sectionHeading(
                        context,
                        'Classification',
                        'What the movement is. Shown to the member on their '
                            'workout screen — a blank here is a blank on '
                            'their phone.',
                      ),
                      _equipmentField(context),
                      const SizedBox(height: 18),
                      _enumRow(context),
                      const SizedBox(height: 18),
                      _primaryMusclesField(context),
                      const SizedBox(height: 18),
                      _secondaryMusclesField(context),

                      _sectionHeading(
                        context,
                        'Coaching',
                        'How to perform it. This is the difference between a '
                            'name and an exercise a member can actually do '
                            'unsupervised.',
                      ),
                      _instructionsField(context),
                      const SizedBox(height: 18),
                      _tipsField(context),

                      _sectionHeading(
                        context,
                        'Media',
                        'The demo video every organization inherits when they '
                            'pick this exercise.',
                      ),
                      _videoField(context),
                      const SizedBox(height: 18),
                      _thumbnailField(context),

                      _sectionHeading(context, 'Lifecycle', null),
                      _activeField(context),
                    ],
                  ),
                ),
              ),
            ),
            _writeError(context),
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

  /// A labelled divider. The form grew from six controls to fifteen, and an
  /// undifferentiated column of fifteen inputs is how an operator ends up
  /// filling none of them.
  Widget _sectionHeading(BuildContext context, String title, String? blurb) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: p.textMuted.withValues(alpha: 0.18), height: 1),
          const SizedBox(height: 16),
          Text(
            title.toUpperCase(),
            style: AppText.label(
              size: 11,
            ).copyWith(color: p.accent, letterSpacing: 0.9),
          ),
          if (blurb != null) ...[
            const SizedBox(height: 5),
            Text(
              blurb,
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _enumRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _enumField(
            context,
            label: 'Difficulty',
            value: _difficulty,
            options: kExerciseDifficulties,
            onChanged: (v) => setState(() => _difficulty = v),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _enumField(
            context,
            label: 'Mechanics',
            value: _mechanics,
            options: kExerciseMechanics,
            onChanged: (v) => setState(() => _mechanics = v),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _enumField(
            context,
            label: 'Force',
            value: _force,
            options: kExerciseForces,
            onChanged: (v) => setState(() => _force = v),
          ),
        ),
      ],
    );
  }

  Widget _enumField(
    BuildContext context, {
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: _decoration(context, label: label),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            // '' is a real, storable answer — "not stated" — so it is offered
            // as a named choice rather than left as an unexplained blank row.
            child: Text(option.isEmpty ? 'Not stated' : _titleCase(option)),
          ),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }

  static String _titleCase(String v) =>
      v.isEmpty ? v : v[0].toUpperCase() + v.substring(1);

  Widget _primaryMusclesField(BuildContext context) {
    return TextFormField(
      controller: _primaryMuscles,
      decoration: _decoration(
        context,
        label: 'Primary muscles (optional)',
        hint: 'Pectoralis Major, Anterior Deltoid',
        helper:
            'Comma-separated, up to $kMaxPrimaryMuscles. The muscles the '
            'movement is FOR.',
      ),
      validator: (v) => _listLimitError(v, kMaxPrimaryMuscles, 'muscles'),
    );
  }

  Widget _secondaryMusclesField(BuildContext context) {
    return TextFormField(
      controller: _secondaryMuscles,
      decoration: _decoration(
        context,
        label: 'Secondary muscles (optional)',
        hint: 'Triceps Brachii, Serratus Anterior',
        helper:
            'Comma-separated, up to $kMaxSecondaryMuscles. Assisting muscles.',
      ),
      validator: (v) => _listLimitError(v, kMaxSecondaryMuscles, 'muscles'),
    );
  }

  /// Refuses over-length input INLINE rather than letting the server truncate
  /// it. `stringList` caps silently, so without this the operator's 9th muscle
  /// would vanish on save with the form still reporting success.
  String? _listLimitError(String? raw, int limit, String noun) {
    final parsed = _splitList(raw ?? '', limit + 1);
    if (parsed.length > limit) return 'At most $limit $noun.';
    return null;
  }

  Widget _instructionsField(BuildContext context) {
    return TextFormField(
      controller: _instructions,
      minLines: 3,
      maxLines: 8,
      decoration: _decoration(
        context,
        label: 'Instructions (optional)',
        hint: 'Set the bench flat. Plant both feet…',
        helper:
            'How to perform the movement, in order. Rendered on the member\'s '
            'exercise screen.',
      ),
      validator: (v) => (v ?? '').length > kMaxInstructionsLength
          ? 'At most $kMaxInstructionsLength characters.'
          : null,
    );
  }

  Widget _tipsField(BuildContext context) {
    return TextFormField(
      controller: _tips,
      minLines: 2,
      maxLines: 6,
      decoration: _decoration(
        context,
        label: 'Coaching cues (optional)',
        hint: 'Keep the wrists neutral\nDrive through mid-foot',
        helper:
            'ONE PER LINE, up to $kMaxTips. Line-separated rather than '
            'comma-separated because a cue often contains a comma.',
      ),
      validator: (v) {
        final parsed = _splitList(v ?? '', kMaxTips + 1, pattern: r'[\r\n]');
        if (parsed.length > kMaxTips) return 'At most $kMaxTips cues.';
        final tooLong = parsed.where((t) => t.length > kMaxTipLength);
        if (tooLong.isNotEmpty) {
          return 'Each cue is at most $kMaxTipLength characters.';
        }
        return null;
      },
    );
  }

  Widget _thumbnailField(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _thumbnailUrl,
            decoration: _decoration(
              context,
              label: 'Thumbnail URL (optional)',
              hint: 'https://…',
              helper: 'Poster frame shown before the video plays.',
            ),
            validator: _httpsValidator,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _videoDurationSec,
            keyboardType: TextInputType.number,
            decoration: _decoration(
              context,
              label: 'Duration (s)',
              hint: '30',
              // Stated plainly rather than left to look broken: a browser
              // cannot read a video's duration without decoding it, and this
              // console has no decoder. The field is real and it persists.
              helper: 'Entered manually — the browser cannot read it.',
            ),
            validator: (v) {
              final value = (v ?? '').trim();
              if (value.isEmpty) return null;
              final n = int.tryParse(value);
              if (n == null || n < 0) return 'Whole seconds, or blank.';
              if (n > 60 * 60) return 'That is over an hour.';
              return null;
            },
          ),
        ),
      ],
    );
  }

  String? _httpsValidator(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    // Mirrors the server rule. A catalog every organization imports
    // from must never hand out a mixed-content or javascript: URL.
    if (!RegExp(r'^https://', caseSensitive: false).hasMatch(value)) {
      return 'Must start with https://';
    }
    return null;
  }

  Widget _videoField(BuildContext context) {
    final p = context.palette;
    final hasVideo = _videoUrl.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _videoUrl,
          readOnly: _uploading,
          decoration: _decoration(
            context,
            label: 'Video URL',
            hint: 'https://…',
            helper:
                'Filled automatically by the uploader. A hosted URL can also '
                'be pasted directly — both must be https.',
          ),
          validator: _httpsValidator,
        ),
        const SizedBox(height: 12),
        if (_uploading)
          _uploadProgressBar(context)
        else
          Row(
            children: [
              ExerciseVideoPill(hasVideo),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickAndUploadVideo,
                icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                label: Text(hasVideo ? 'Replace video' : 'Upload video'),
              ),
              if (hasVideo) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _clearVideo,
                  icon: const Icon(Icons.link_off, size: 16),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(foregroundColor: p.textMuted),
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _pickedFileName ?? 'MP4, MOV, WebM or M4V · up to 50 MB',
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                ),
              ),
            ],
          ),
        if (_uploadError != null) ...[
          const SizedBox(height: 8),
          Text(
            _uploadError!,
            style: AppText.body(size: 12).copyWith(color: p.error),
          ),
        ],
      ],
    );
  }

  Widget _uploadProgressBar(BuildContext context) {
    final p = context.palette;
    final pct = (_uploadProgress * 100).clamp(0, 100).toStringAsFixed(0);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              // Indeterminate until the first byte-count arrives, so the bar
              // never sits frozen at 0% looking hung.
              value: _uploadProgress > 0 ? _uploadProgress : null,
              minHeight: 7,
              backgroundColor: p.accent.withValues(alpha: 0.14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Uploading $pct%',
          style: AppText.body(size: 12).copyWith(color: p.textSecondary),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: _cancelUpload, child: const Text('Cancel')),
      ],
    );
  }

  Future<void> _pickAndUploadVideo() async {
    setState(() => _uploadError = null);
    final FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ExerciseVideoService.allowedExtensions,
        // The browser hands us bytes; there is no readable file path on web.
        withData: true,
      );
    } catch (e) {
      if (mounted) setState(() => _uploadError = 'Could not open the picker.');
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // Operator cancelled.

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        setState(() => _uploadError = 'That file could not be read.');
      }
      return;
    }

    final reason = ExerciseVideoService.rejectionReasonFor(
      fileName: file.name,
      sizeBytes: bytes.lengthInBytes,
    );
    if (reason != null) {
      if (mounted) setState(() => _uploadError = reason);
      return;
    }

    // Remember what we are about to supersede, but do NOT delete it yet — the
    // save can still fail or be cancelled, and the old video must remain live
    // for every member currently training on this exercise until the new URL
    // is actually committed.
    final previous = ExerciseVideoService.storagePathFromUrl(
      widget.existing?.videoUrl ?? '',
    );

    setState(() {
      _uploadProgress = 0;
      _pickedFileName = file.name;
    });

    try {
      final result = await _videos.upload(
        fileName: file.name,
        bytes: bytes,
        onTask: (t) {
          // ⚠️ BLOCK BODY, NOT AN ARROW — and that is not style.
          //
          // `UploadTask` IMPLEMENTS `Future<TaskSnapshot>`. An arrow closure
          // returns the value of the assignment, so `setState(() => _uploadTask
          // = t)` hands setState a Future and trips its assertion:
          // "setState() callback argument returned a Future". The upload then
          // fails at the very first progress callback, before a single byte is
          // acknowledged — which reads exactly like a network failure and is
          // why the old generic error message ("check the connection") kept
          // this hidden.
          if (mounted) {
            setState(() {
              _uploadTask = t;
            });
          }
        },
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _uploadTask = null;
        _videoUrl.text = result.downloadUrl;
        if (previous.isNotEmpty && previous != result.storagePath) {
          _supersededPath = previous;
        }
      });
    } on ExerciseVideoRejected catch (e) {
      if (mounted) {
        setState(() {
          _uploadTask = null;
          _uploadError = e.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadTask = null;
        // A cancel resolves through this path too; saying "failed" would be a
        // lie about something the operator did on purpose.
        _uploadError = _wasCancelled ? null : _describeUploadFailure(e);
        _wasCancelled = false;
      });
    }
  }

  /// Turns a Storage failure into something the operator can ACT on.
  ///
  /// The first version of this said "Check the connection and try again" for
  /// every exception. That sentence is a guess, and it is wrong for most of the
  /// ways an upload actually fails: a rules refusal, an unregistered bucket and
  /// a cancelled request are all indistinguishable from a flaky network under
  /// that message, so the operator retries forever on something retrying cannot
  /// fix. It also cost real debugging time during certification, which is
  /// exactly the cost it would impose on a founder at 2am.
  String _describeUploadFailure(Object e) {
    final code = e is FirebaseException ? e.code : '';
    switch (code) {
      case 'unauthorized':
        return 'Storage refused the upload. Your account must be a super '
            'admin and storage.rules must be deployed.';
      case 'unauthenticated':
        return 'Your session expired. Sign in again and retry.';
      case 'retry-limit-exceeded':
        return 'The upload timed out. Check the connection and try again.';
      case 'quota-exceeded':
        return 'The storage bucket is out of quota.';
      case 'canceled':
        return '';
      default:
        final detail = e is FirebaseException
            ? '${e.code}: ${e.message ?? ''}'
            : e.toString();
        // The raw reason is SHOWN, not just logged. A console the founder runs
        // themselves has no support channel to escalate an opaque failure to.
        return 'Upload failed — $detail';
    }
  }

  bool _wasCancelled = false;

  Future<void> _cancelUpload() async {
    final task = _uploadTask;
    if (task == null) return;
    _wasCancelled = true;
    try {
      await task.cancel();
    } catch (_) {
      // Already finished; the awaited future settles either way.
    }
    if (mounted) {
      setState(() {
        _uploadTask = null;
        _uploadProgress = 0;
        _pickedFileName = null;
      });
    }
  }

  /// Detaches the video from the exercise WITHOUT deleting the object.
  ///
  /// The bytes stay in Storage on purpose: an archived or re-pointed exercise
  /// may still be referenced by workouts a member is part-way through, and this
  /// platform's rule is that lifecycle changes never destroy media historical
  /// workouts depend on.
  void _clearVideo() {
    setState(() {
      _videoUrl.clear();
      _pickedFileName = null;
      _uploadError = null;
      _supersededPath = null;
    });
  }

  Widget _equipmentField(BuildContext context) {
    return TextFormField(
      controller: _equipment,
      decoration: _decoration(
        context,
        label: 'Equipment (optional)',
        hint: 'Barbell, flat bench',
        helper:
            'Shown to the member on their workout screen, so fill it in — a '
            'blank here is a blank on their phone.',
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

  /// Why the last save was refused, PINNED between the scrolling form and the
  /// buttons.
  ///
  /// It used to be the last child of the scroll view, below the Active switch.
  /// On a full form that lands BELOW THE FOLD, so pressing "Create exercise" —
  /// a button that sits in the fixed footer, already at the bottom of the
  /// dialog — produced no visible change whatsoever unless the operator thought
  /// to scroll down. The only other signal was a snackbar that clears itself in
  /// two seconds. A refused save that looks identical to a dead button is how a
  /// curator concludes the console is broken and retries the same write.
  /// Outside the scroll view it cannot be scrolled away from.
  Widget _writeError(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final failure = c.writeError.value;
      if (failure == null) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.08),
          borderRadius: AppRadii.smR,
          border: Border.all(color: p.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 17, color: p.error),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                failure.message,
                style: AppText.body(size: 12.5).copyWith(color: p.textPrimary),
              ),
            ),
          ],
        ),
      );
    });
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
      // ── Now authored by this form (was: carried through blind). ──
      primaryMuscles: _splitList(_primaryMuscles.text, kMaxPrimaryMuscles),
      secondaryMuscles: _splitList(
        _secondaryMuscles.text,
        kMaxSecondaryMuscles,
      ),
      difficulty: _difficulty,
      mechanics: _mechanics,
      force: _force,
      instructions: _instructions.text.trim(),
      tips: _splitList(_tips.text, kMaxTips, pattern: r'[\r\n]'),
      thumbnailUrl: _thumbnailUrl.text.trim(),
      videoDurationSec: int.tryParse(_videoDurationSec.text.trim()) ?? 0,
      // ── Still carried: no control owns it, and the round-trip rule stands
      // for anything this form does not edit. `videoProvider` describes where
      // the bytes are hosted and is set by whatever put them there.
      videoProvider: _resolvedVideoProvider(prev),
    );

    final saved = await c.save(draft, isActive: _isActive);
    // Only close on success. A failed save leaves the form open with the
    // server's refusal rendered inline, so nothing the operator typed is lost.
    if (!saved) return;

    // ONLY NOW is the old object safe to remove: the document has committed and
    // no member can still be served the superseded URL. Best-effort — an
    // orphaned object is a housekeeping cost, a failed save is a data loss.
    final superseded = _supersededPath;
    if (superseded != null && superseded.isNotEmpty) {
      await _videos.deleteObject(superseded);
    }
    Get.back();
  }

  /// `videoProvider` describes the HOST, so it must follow the URL rather than
  /// being carried blind: a row whose video was replaced by an upload but still
  /// claims 'youtube' would mislead every consumer that branches on it.
  String _resolvedVideoProvider(GlobalExerciseModel? prev) {
    final url = _videoUrl.text.trim();
    if (url.isEmpty) return '';
    if (ExerciseVideoService.storagePathFromUrl(url).isNotEmpty) {
      return 'firebase';
    }
    // A pasted third-party URL keeps whatever the row already said.
    return prev?.videoProvider ?? '';
  }
}
