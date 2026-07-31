import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/global_food_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../models/global_food_model.dart';
import 'food_chrome.dart';

/// FOOD PLATFORM — the bulk import wizard.
///
/// Upload → schema validation → nutrition validation → duplicate detection →
/// preview → conflict resolution → import → summary.
///
/// The governing rule is that **nothing is ever imported silently**. Every row
/// that lands, updates, is skipped or fails is counted and named. That is not
/// pedantry: a bulk import is the only operation in the console that can put
/// thousands of unreviewed rows in front of every organization on the platform
/// at once, and an import that quietly drops a third of a file is how a
/// nutrition library stops being trustworthy.
///
/// Imported rows land as DRAFTS by default, so even a bad file is not live.
class FoodImportWizard extends StatefulWidget {
  final GlobalFoodController controller;

  /// Pre-loads the frozen seed catalog instead of asking for a file.
  final bool seedMode;

  const FoodImportWizard({
    super.key,
    required this.controller,
    this.seedMode = false,
  });

  @override
  State<FoodImportWizard> createState() => _FoodImportWizardState();
}

enum _Stage { source, preview, done }

/// Dialog dimensions that never exceed the window.
double _dialogWidth(BuildContext context, double preferred) {
  final available = MediaQuery.sizeOf(context).width - 80;
  return available < preferred ? (available < 280 ? 280 : available) : preferred;
}

double _dialogHeight(BuildContext context, double preferred) {
  final available = MediaQuery.sizeOf(context).height - 220;
  return available < preferred ? (available < 240 ? 240 : available) : preferred;
}

class _FoodImportWizardState extends State<FoodImportWizard> {
  _Stage _stage = _Stage.source;

  // Source
  final _paste = TextEditingController();
  String _fileName = '';
  List<Map<String, dynamic>> _rows = const [];
  List<String> _unmapped = const [];
  String? _sourceError;
  bool _reading = false;

  // Options
  String _conflictMode = 'skip';
  String _status = 'draft';
  String _categoryId = '';

  // Results
  FoodImportReport? _dryRun;
  FoodImportReport? _result;

  GlobalFoodController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    if (widget.seedMode) _loadSeed();
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  // ── Source ─────────────────────────────────────────────────────────

  Future<void> _loadSeed() async {
    // Assigned directly rather than through setState: this runs from
    // initState, before the first build, where there is no frame to schedule.
    _reading = true;
    try {
      final rows = await c.loadSeedCatalog();
      setState(() {
        _rows = rows;
        _fileName = 'Frozen seed catalog';
        _sourceError = rows.isEmpty ? 'The seed catalog is empty.' : null;
        _unmapped = const [];
      });
    } catch (_) {
      setState(() => _sourceError = 'Could not read the seed catalog.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
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
    final report = await c.runImport(
      _rows,
      dryRun: true,
      categoryId: _categoryId.isEmpty ? null : _categoryId,
      source: widget.seedMode ? 'seed' : 'import',
      conflictMode: _conflictMode,
      status: _status,
    );
    if (report == null || !mounted) return;
    setState(() {
      _dryRun = report;
      _stage = _Stage.preview;
    });
  }

  Future<void> _import() async {
    final report = await c.runImport(
      _rows,
      dryRun: false,
      categoryId: _categoryId.isEmpty ? null : _categoryId,
      source: widget.seedMode ? 'seed' : 'import',
      conflictMode: _conflictMode,
      status: _status,
    );
    if (report == null || !mounted) return;
    setState(() {
      _result = report;
      _stage = _Stage.done;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.seedMode ? 'Import the seed catalog' : 'Import foods',
            style: AppText.title(size: 22).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            switch (_stage) {
              _Stage.source => 'Step 1 of 3 — choose a dataset',
              _Stage.preview => 'Step 2 of 3 — review what will happen',
              _Stage.done => 'Step 3 of 3 — summary',
            },
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ],
      ),
      // Clamped to the window: a dialog wider than the viewport clips its
      // own content, and the operator cannot scroll a dialog sideways.
      content: SizedBox(
        width: _dialogWidth(context, 760),
        height: _dialogHeight(context, 480),
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.isBusy.value || _reading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: switch (_stage) {
                    _Stage.source => _sourceStage(context),
                    _Stage.preview => _previewStage(context),
                    _Stage.done => _doneStage(context),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: switch (_stage) {
        _Stage.source => [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          Obx(() {
            // Read the observable FIRST, unconditionally: `_rows.isEmpty ||
            // c.isBusy.value` short-circuits before touching c.isBusy when the
            // list is empty (the initial Step-1 state), so the Obx would track
            // no observable and GetX throws "improper use of GetX", rendering a
            // red error over the whole wizard.
            final busy = c.isBusy.value;
            return FilledButton(
              onPressed: _rows.isEmpty || busy ? null : _validate,
              child: const Text('Validate'),
            );
          }),
        ],
        _Stage.preview => [
          TextButton(
            onPressed: () => setState(() => _stage = _Stage.source),
            child: const Text('Back'),
          ),
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          Obx(() {
            // Same short-circuit hazard as the Validate button: read the
            // observable before the `== 0 || c.isBusy.value` guard, which would
            // otherwise skip c.isBusy whenever there are no importable rows.
            final busy = c.isBusy.value;
            final ready = (_dryRun?.accepted ?? 0) + (_dryRun?.willUpdate ?? 0);
            return FilledButton.icon(
              onPressed: ready == 0 || busy ? null : _import,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text('Import $ready rows'),
            );
          }),
        ],
        _Stage.done => [
          FilledButton(onPressed: Get.back, child: const Text('Done')),
        ],
      },
    );
  }

  // ── Stage 1 ────────────────────────────────────────────────────────

  Widget _sourceStage(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.seedMode) ...[
          Row(
            children: [
              FilledButton.icon(
                onPressed: _reading ? null : _pickFile,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Choose a file'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'CSV or JSON. Excel workbooks are binary — export the sheet '
                  'as CSV first.',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _paste,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: '…or paste CSV / JSON',
              hintText: 'name,calories,protein,carbs,fat\nRolled Oats,379,13.2,67.7,6.5',
              suffixIcon: IconButton(
                tooltip: 'Read pasted text',
                onPressed: _ingestPaste,
                icon: const Icon(Icons.subdirectory_arrow_left),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_sourceError != null)
          Container(
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
                  child: Text(
                    _sourceError!,
                    style: AppText.body(
                      size: 12.5,
                    ).copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 4),
          FoodCard(
            title: 'READY TO VALIDATE',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_fileName — ${_rows.length} rows',
                  style: AppText.cardTitle(
                    size: 14,
                  ).copyWith(color: p.textPrimary),
                ),
                if (_unmapped.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Columns the importer does not understand and will ignore: '
                    '${_unmapped.join(', ')}.',
                    style: AppText.body(
                      size: 12,
                    ).copyWith(color: p.textSecondary),
                  ),
                ],
                const SizedBox(height: 14),
                _sample(context),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _options(context),
        ],
      ],
    );
  }

  Widget _sample(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FIRST ROWS AS THE IMPORTER READ THEM',
          style: AppText.body(size: 10).copyWith(
            color: p.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        for (final row in _rows.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${row['name']}  ·  ${row['calories'] ?? '—'} kcal  ·  '
              'P${row['protein'] ?? 0} C${row['carbs'] ?? 0} F${row['fat'] ?? 0}',
              style: AppText.body(size: 12).copyWith(color: p.textSecondary),
            ),
          ),
        if (_rows.length > 4)
          Text(
            '…and ${_rows.length - 4} more',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
      ],
    );
  }

  Widget _options(BuildContext context) {
    final p = context.palette;
    return FoodCard(
      title: 'IMPORT OPTIONS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHEN A FOOD ALREADY EXISTS',
            style: AppText.body(size: 10).copyWith(
              color: p.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FoodChip(
                label: 'Skip it',
                active: _conflictMode == 'skip',
                onTap: () => setState(() => _conflictMode = 'skip'),
              ),
              const SizedBox(width: 8),
              FoodChip(
                label: 'Update it from this file',
                active: _conflictMode == 'update',
                onTap: () => setState(() => _conflictMode = 'update'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _conflictMode == 'update'
                ? 'Existing foods will be overwritten from this file. Their '
                      'publish state and verification badge are preserved, so '
                      're-importing never un-publishes a live library.'
                : 'Existing foods are left exactly as they are and reported as '
                      'skipped.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 18),
          Text(
            'NEW ROWS LAND AS',
            style: AppText.body(size: 10).copyWith(
              color: p.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FoodChip(
                label: 'Drafts',
                icon: Icons.edit_note,
                active: _status == 'draft',
                onTap: () => setState(() => _status = 'draft'),
              ),
              const SizedBox(width: 8),
              FoodChip(
                label: 'Published',
                icon: Icons.public,
                active: _status == 'published',
                onTap: () => setState(() => _status = 'published'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _status == 'published'
                ? 'Every organization sees these the moment the import '
                      'finishes. Only choose this for a dataset you have '
                      'already reviewed.'
                : 'Nothing reaches coaches until someone publishes it. This is '
                      'the safe default for an unreviewed dataset.',
            style: AppText.body(size: 12).copyWith(
              color: _status == 'published' ? p.error : p.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'File everything under (optional)',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('No category')),
              for (final cat in c.activeCategories)
                DropdownMenuItem(
                  value: cat.id,
                  child: Text(c.categoryPath(cat.id)),
                ),
            ],
            onChanged: (v) => setState(() => _categoryId = v ?? ''),
          ),
        ],
      ),
    );
  }

  // ── Stage 2 ────────────────────────────────────────────────────────

  Widget _previewStage(BuildContext context) {
    final r = _dryRun;
    if (r == null) return const SizedBox.shrink();
    final p = context.palette;
    final willWrite = r.accepted + r.willUpdate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FoodCard(
          title: 'WHAT WILL HAPPEN',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 32,
                runSpacing: 14,
                children: [
                  FoodStat(label: 'rows read', value: '${r.received}'),
                  FoodStat(
                    label: 'will be created',
                    value: '${r.accepted}',
                    color: r.accepted > 0 ? p.success : null,
                  ),
                  if (_conflictMode == 'update')
                    FoodStat(
                      label: 'will be updated',
                      value: '${r.willUpdate}',
                      color: r.willUpdate > 0 ? p.accent : null,
                    ),
                  FoodStat(
                    label: 'skipped as duplicates',
                    value: '${r.duplicates.length}',
                  ),
                  FoodStat(
                    label: 'rejected',
                    value: '${r.rejected.length}',
                    color: r.rejected.isNotEmpty ? p.error : null,
                  ),
                  FoodStat(label: 'with warnings', value: '${r.warnings.length}'),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                willWrite == 0
                    ? 'Nothing would be written. Every row was either rejected '
                          'or already exists.'
                    : '$willWrite of ${r.received} rows will be written, as '
                          '${_status == 'draft' ? 'drafts' : 'published foods'}. '
                          'Nothing has been written yet — this was a dry run.',
                style: AppText.body(size: 12.5).copyWith(
                  color: willWrite == 0 ? p.error : p.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (r.rejected.isNotEmpty) ...[
          const SizedBox(height: 14),
          _rowList(
            context,
            'REJECTED — THESE WILL NOT BE IMPORTED',
            p.error,
            [for (final e in r.rejected) '${e.name} — ${e.errors.join('; ')}'],
          ),
        ],
        if (r.duplicates.isNotEmpty) ...[
          const SizedBox(height: 14),
          _rowList(
            context,
            'ALREADY IN THE LIBRARY',
            p.textMuted,
            [for (final e in r.duplicates) '${e.name} — ${e.reason}'],
          ),
        ],
        if (r.warnings.isNotEmpty) ...[
          const SizedBox(height: 14),
          _rowList(
            context,
            'IMPORTED WITH WARNINGS',
            p.textSecondary,
            [for (final e in r.warnings) '${e.name} — ${e.warnings.join('; ')}'],
          ),
        ],
      ],
    );
  }

  Widget _rowList(
    BuildContext context,
    String title,
    Color color,
    List<String> lines,
  ) {
    final p = context.palette;
    return FoodCard(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines.take(40))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                line,
                style: AppText.body(size: 12).copyWith(color: color),
              ),
            ),
          if (lines.length > 40)
            Text(
              '…and ${lines.length - 40} more',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
        ],
      ),
    );
  }

  // ── Stage 3 ────────────────────────────────────────────────────────

  Widget _doneStage(BuildContext context) {
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    final p = context.palette;
    final total = r.imported + r.updated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.success.withValues(alpha: 0.08),
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.success.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 28, color: p.success),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import complete',
                      style: AppText.cardTitle(
                        size: 16,
                      ).copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$total food${total == 1 ? '' : 's'} written'
                      '${_status == 'draft' ? ' as drafts' : ' and published'}.',
                      style: AppText.body(
                        size: 12.5,
                      ).copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FoodCard(
          title: 'SUMMARY',
          child: Wrap(
            spacing: 32,
            runSpacing: 14,
            children: [
              FoodStat(label: 'rows read', value: '${r.received}'),
              FoodStat(
                label: 'imported',
                value: '${r.imported}',
                color: p.success,
              ),
              FoodStat(label: 'updated', value: '${r.updated}'),
              FoodStat(label: 'skipped', value: '${r.duplicates.length}'),
              FoodStat(
                label: 'failed',
                value: '${r.rejected.length}',
                color: r.rejected.isNotEmpty ? p.error : null,
              ),
              FoodStat(label: 'warnings', value: '${r.warnings.length}'),
            ],
          ),
        ),
        if (_status == 'draft' && total > 0) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: AppRadii.smR,
            ),
            child: Text(
              'These are drafts — no organization can see them yet. Review them '
              'under the Drafts filter, then publish in bulk when you are '
              'satisfied.',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
          ),
        ],
        if (r.rejected.isNotEmpty) ...[
          const SizedBox(height: 14),
          _rowList(
            context,
            'FAILED ROWS',
            p.error,
            [for (final e in r.rejected) '${e.name} — ${e.errors.join('; ')}'],
          ),
        ],
      ],
    );
  }
}
