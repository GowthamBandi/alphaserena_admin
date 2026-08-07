import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_exercise_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_exercise_model.dart';
import 'exercise_chrome.dart';

/// GLOBAL EXERCISE LIBRARY — the bulk importer (mission Phase 4).
///
/// ONE pipeline. The bundled master dataset, an uploaded CSV, an uploaded JSON
/// and a pasted payload all funnel into the same reader and the same callable,
/// so the seed cannot take a shortcut an operator's own file would not survive.
///
/// It ALWAYS validates before it writes. The dry run returns the identical
/// report, writes nothing, and shows exactly which rows would be created,
/// skipped as duplicates or rejected — before a single document exists. An
/// importer that writes first and reports afterwards is how a catalog every
/// organization reads gets poisoned.
class ExerciseImportWizard extends StatefulWidget {
  final GlobalExerciseController controller;

  /// Opens straight onto the bundled master dataset rather than the file
  /// picker. The founding path.
  final bool seedMode;

  const ExerciseImportWizard({
    super.key,
    required this.controller,
    this.seedMode = false,
  });

  @override
  State<ExerciseImportWizard> createState() => _ExerciseImportWizardState();
}

class _ExerciseImportWizardState extends State<ExerciseImportWizard> {
  final _paste = TextEditingController();

  List<Map<String, dynamic>> _rows = const [];
  List<String> _unmapped = const [];
  String? _fileName;
  String? _sourceError;
  bool _reading = false;

  /// 'skip' leaves an existing exercise alone — the mission's "duplicates
  /// should be ignored". 'update' refreshes it from the imported row.
  String _conflictMode = 'skip';
  bool _importActive = true;

  GlobalExerciseController get c => widget.controller;

  bool get _validated =>
      c.lastImport.value != null && c.lastImport.value!.dryRun;

  @override
  void initState() {
    super.initState();
    c.lastImport.value = null;
    if (widget.seedMode) _loadSeed();
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  // ── Sources ────────────────────────────────────────────────────────

  Future<void> _loadSeed() async {
    setState(() {
      _reading = true;
      _sourceError = null;
    });
    final result = await c.loadSeedCatalog();
    if (!mounted) return;
    setState(() {
      _rows = result.rows;
      _fileName = 'Bundled master dataset';
      _unmapped = const [];
      _sourceError = result.error ??
          (result.rows.isEmpty ? 'The bundled dataset is empty.' : null);
      _reading = false;
    });
  }

  Future<void> _pickFile() async {
    setState(() {
      _reading = true;
      _sourceError = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv', 'json', 'txt', 'tsv'],
        withData: true, // web has no path; bytes are the portable route
      );
      final file = picked?.files.singleOrNull;
      if (file == null) return;

      final bytes = file.bytes;
      if (bytes == null) {
        setState(() => _sourceError = 'That file could not be read.');
        return;
      }
      // Datasets are routinely exported as UTF-8 with stray bytes; decoding
      // leniently beats refusing a file over one bad character.
      final content = utf8.decode(bytes, allowMalformed: true);
      _ingest(file.name, content);
    } catch (_) {
      setState(() => _sourceError = 'That file could not be opened.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  void _ingest(String name, String content) {
    final parsed = c.parseImportFile(name, content);
    setState(() {
      _fileName = name;
      _rows = parsed.rows;
      _unmapped = parsed.unmapped;
      _sourceError = parsed.error ??
          (parsed.rows.isEmpty ? 'No usable rows found in that file.' : null);
    });
    c.lastImport.value = null;
  }

  void _ingestPaste() {
    final text = _paste.text.trim();
    if (text.isEmpty) {
      setState(() => _sourceError = 'Nothing pasted.');
      return;
    }
    // Guess the format from the content: a JSON payload starts with a bracket.
    final looksJson = text.startsWith('[') || text.startsWith('{');
    _ingest(looksJson ? 'pasted.json' : 'pasted.csv', text);
  }

  // ── Validation & import ────────────────────────────────────────────

  Future<void> _validate() async {
    await c.runImport(
      _rows,
      dryRun: true,
      source: widget.seedMode ? 'seed' : 'import',
      conflictMode: _conflictMode,
      isActive: _importActive,
    );
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final report = await c.runImport(
      _rows,
      dryRun: false,
      source: widget.seedMode ? 'seed' : 'import',
      conflictMode: _conflictMode,
      isActive: _importActive,
    );
    if (report == null || !mounted) return;
    setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 780),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(context),
            Obx(
              () => c.isBusy.value
                  ? const LinearProgressIndicator(minHeight: 3)
                  : const SizedBox(height: 3),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _sourceSection(context),
                    const SizedBox(height: 18),
                    if (_rows.isNotEmpty) ...[
                      _optionsSection(context),
                      const SizedBox(height: 18),
                    ],
                    Obx(() {
                      final report = c.lastImport.value;
                      return report == null
                          ? const SizedBox.shrink()
                          : _reportSection(context, report);
                    }),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.border)),
              ),
              child: _actions(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              borderRadius: AppRadii.smR,
            ),
            child: Icon(Icons.upload_file, color: p.accent, size: 19),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.seedMode
                      ? 'Found the catalog from the master dataset'
                      : 'Import exercises',
                  style: AppText.cardTitle(
                    size: 17,
                  ).copyWith(color: p.textPrimary),
                ),
                Text(
                  'Nothing is written until you have seen what would be '
                  'written.',
                  style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          Obx(
            () => IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close, size: 20),
              onPressed: c.isBusy.value ? null : Get.back,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceSection(BuildContext context) {
    final p = context.palette;
    return ConsoleCard(
      title: '1 · SOURCE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.seedMode)
            Text(
              'The master dataset that ships with this console: 844 '
              'professionally named exercises across all 20 categories, with no '
              'videos. It is read through the SAME parser an uploaded file '
              'uses, so it cannot take a shortcut your own file would not '
              'survive.',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            )
          else
            Text(
              'A CSV needs a name column and a category column; every other '
              'column is optional. JSON may be a bare array or '
              '{"exercises": [...]} — the exact shape Export produces.',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (widget.seedMode)
                OutlinedButton.icon(
                  onPressed: _reading ? null : _loadSeed,
                  icon: const Icon(Icons.refresh, size: 17),
                  label: const Text('Reload dataset'),
                )
              else ...[
                FilledButton.icon(
                  onPressed: _reading ? null : _pickFile,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Choose a file'),
                ),
                OutlinedButton.icon(
                  onPressed: _reading ? null : _loadSeed,
                  icon: const Icon(Icons.auto_awesome_motion, size: 17),
                  label: const Text('Use the master dataset'),
                ),
              ],
              if (_reading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
            ],
          ),
          if (!widget.seedMode) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _paste,
              maxLines: 4,
              style: AppText.body(size: 12.5),
              decoration: InputDecoration(
                hintText: '…or paste CSV / JSON here',
                isDense: true,
                filled: true,
                fillColor: p.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: AppRadii.smR,
                  borderSide: BorderSide(color: p.border),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _reading ? null : _ingestPaste,
                child: const Text('Read pasted text'),
              ),
            ),
          ],
          if (_sourceError != null) ...[
            const SizedBox(height: 14),
            _notice(context, _sourceError!, tone: p.error),
          ],
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 14),
            _notice(
              context,
              '${_rows.length} row${_rows.length == 1 ? '' : 's'} read from '
              '${_fileName ?? 'the file'}.',
              tone: p.success,
            ),
          ],
          if (_unmapped.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Columns are never dropped in silence. An operator who does not
            // know a column was ignored believes data landed that did not.
            _notice(
              context,
              'These columns were not recognised and will be ignored: '
              '${_unmapped.join(', ')}.',
              tone: p.textMuted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _optionsSection(BuildContext context) {
    final p = context.palette;
    return ConsoleCard(
      title: '2 · OPTIONS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'When an exercise already exists',
            style: AppText.label(size: 12.5).copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ConsoleChip(
                label: 'Skip it',
                active: _conflictMode == 'skip',
                onTap: () => setState(() {
                  _conflictMode = 'skip';
                  c.lastImport.value = null;
                }),
              ),
              ConsoleChip(
                label: 'Update it',
                active: _conflictMode == 'update',
                onTap: () => setState(() {
                  _conflictMode = 'update';
                  c.lastImport.value = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _conflictMode == 'skip'
                ? 'Existing exercises are left exactly as they are. Re-running '
                      'the same import is therefore harmless.'
                : 'Existing exercises are overwritten from the file. Their '
                      'active state is never overwritten, so a retired exercise '
                      'is not silently resurrected.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          // ConsoleCard is a filled Container, so it hides the ink this tile
          // would paint on the Material above it. Its own transparent Material
          // keeps the tap feedback visible without altering the card's fill.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _importActive,
              onChanged: (v) => setState(() {
                _importActive = v;
                c.lastImport.value = null;
              }),
              title: Text(
                'Import as active',
                style: AppText.label(size: 13).copyWith(color: p.textPrimary),
              ),
              subtitle: Text(
                _importActive
                    ? 'New rows are immediately available. Nothing consumes the '
                          'catalog yet, so this is safe.'
                    : 'New rows land inactive and must be activated before they '
                          'are offered.',
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportSection(BuildContext context, ExerciseImportReport report) {
    final p = context.palette;
    return ConsoleCard(
      title: report.dryRun ? '3 · PREVIEW (nothing written)' : '3 · RESULT',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 40,
            runSpacing: 16,
            children: [
              ConsoleStat(label: 'Rows read', value: '${report.received}'),
              ConsoleStat(
                label: report.dryRun ? 'Would create' : 'Created',
                value: '${report.dryRun ? report.accepted : report.imported}',
                color: p.success,
              ),
              if (report.conflictMode == 'update')
                ConsoleStat(
                  label: report.dryRun ? 'Would update' : 'Updated',
                  value: '${report.dryRun ? report.willUpdate : report.updated}',
                  color: p.accent,
                ),
              ConsoleStat(
                label: 'Duplicates skipped',
                value: '${report.duplicates.length}',
                color: report.duplicates.isEmpty ? null : p.textSecondary,
                hint: 'Already in the catalog, or repeated inside this file.',
              ),
              ConsoleStat(
                label: 'Rejected',
                value: '${report.rejected.length}',
                color: report.rejected.isEmpty ? null : p.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // The importer's core promise, ASSERTED rather than assumed: every
          // received row landed in exactly one bucket.
          if (!report.isAccounted)
            _notice(
              context,
              'The server and this console disagree about what happened to '
              '${report.received} rows. Do not trust these numbers — check the '
              'catalog directly before importing again.',
              tone: p.error,
            )
          else
            _notice(
              context,
              report.dryRun
                  ? 'Every one of the ${report.received} rows is accounted for. '
                        '${report.willWrite} would be written.'
                  : '${report.didWrite} exercise'
                        '${report.didWrite == 1 ? '' : 's'} written. Every one '
                        'of the ${report.received} rows is accounted for.',
              tone: report.dryRun ? p.textMuted : p.success,
            ),
          if (report.rejected.isNotEmpty) ...[
            const SizedBox(height: 16),
            _rowList(
              context,
              title: 'Rejected',
              tone: p.error,
              rows: [
                for (final r in report.rejected.take(25))
                  '${r.name} — ${r.errors.join('; ')}',
              ],
              more: report.rejected.length - 25,
            ),
          ],
          if (report.duplicates.isNotEmpty) ...[
            const SizedBox(height: 16),
            _rowList(
              context,
              title: 'Skipped as duplicates',
              tone: p.textSecondary,
              rows: [
                for (final d in report.duplicates.take(25))
                  '${d.name} — ${d.reason}',
              ],
              more: report.duplicates.length - 25,
            ),
          ],
          if (report.warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            _rowList(
              context,
              title: 'Imported with warnings',
              tone: p.textMuted,
              rows: [
                for (final w in report.warnings.take(15))
                  '${w.name} — ${w.warnings.join('; ')}',
              ],
              more: report.warnings.length - 15,
            ),
          ],
        ],
      ),
    );
  }

  Widget _rowList(
    BuildContext context, {
    required String title,
    required Color tone,
    required List<String> rows,
    required int more,
  }) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.label(size: 12.5).copyWith(color: tone),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 190),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: AppRadii.smR,
            border: Border.all(color: p.border),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              [
                ...rows,
                if (more > 0) '…and $more more',
              ].join('\n'),
              style: AppText.body(size: 12).copyWith(color: p.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notice(BuildContext context, String message, {required Color tone}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: AppRadii.smR,
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: AppText.body(size: 12.5).copyWith(color: tone),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final report = c.lastImport.value;
      final done = report != null && !report.dryRun;
      return Row(
        children: [
          Expanded(
            child: Text(
              done
                  ? 'Written through a Cloud Function; the change is in the '
                        'audit log.'
                  : 'Validate first — the preview writes nothing.',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ),
          TextButton(
            onPressed: c.isBusy.value ? null : Get.back,
            child: Text(done ? 'Close' : 'Cancel'),
          ),
          const SizedBox(width: 8),
          if (!done) ...[
            OutlinedButton(
              onPressed: (_rows.isEmpty || c.isBusy.value) ? null : _validate,
              child: const Text('Validate'),
            ),
            const SizedBox(width: 10),
            FilledButton(
              // Import is unreachable until a dry run has been seen. That is
              // the whole guarantee this wizard offers.
              onPressed: (!_validated || c.isBusy.value || _rows.isEmpty)
                  ? null
                  : _import,
              child: Text(
                report == null
                    ? 'Import'
                    : 'Import ${report.willWrite} exercise'
                          '${report.willWrite == 1 ? '' : 's'}',
              ),
            ),
          ],
        ],
      );
    });
  }
}
