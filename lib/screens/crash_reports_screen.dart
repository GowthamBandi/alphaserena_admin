// lib/screens/crash_reports_screen.dart
//
// GOVERNANCE · Crash Reports — the founder's answer to "what broke, when,
// on which build, and was it once or every session?". Read-only; the
// collection is append-only for everyone including the founder.
import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/crash_reports_controller.dart';
import '../models/crash_report_model.dart';
import '../models/crash_signature_model.dart';
import '../widgets/page_shell.dart';

class CrashReportsScreen extends StatelessWidget {
  CrashReportsScreen({super.key});

  final CrashReportsController ctrl = Get.find<CrashReportsController>();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Crash Reports',
      icon: Icons.bug_report_outlined,
      trailing: Obx(() => Text(
            ctrl.hasError
                ? '—'
                : ctrl.atCap
                    ? '${ctrl.reports.length}+ (newest first)'
                    : '${ctrl.reports.length} total',
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctrl.searchField,
            onChanged: (v) => ctrl.search.value = v,
            decoration: InputDecoration(
              hintText: 'Search error, section, build, commit…',
              prefixIcon: Icon(Icons.search, color: p.textMuted),
              filled: true,
              fillColor: p.surface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.smR,
                  borderSide: BorderSide(color: p.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.smR,
                  borderSide: BorderSide(color: p.accent)),
            ),
          ),
          const SizedBox(height: 12),
          Obx(() => Wrap(spacing: 8, children: [
                for (final (value, label) in const [
                  ('all', 'All'),
                  ('fatal', 'Fatal'),
                  ('nonfatal', 'Non-fatal'),
                  ('production', 'Production only'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: ctrl.kindFilter.value == value,
                    onSelected: (_) => ctrl.kindFilter.value = value,
                  ),
              ])),
          const SizedBox(height: 8),
          // The APP dimension: which product surface reported. 'Console' is
          // this app's own reports; the other two are the mobile apps writing
          // into app_crash_reports.
          Obx(() => Wrap(spacing: 8, children: [
                for (final (value, label) in const [
                  ('all', 'All apps'),
                  ('trainersarena', 'Trainersarena'),
                  ('alphasarena', 'Alphasarena'),
                  ('console', 'Console'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: ctrl.appFilter.value == value,
                    onSelected: (_) => ctrl.appFilter.value = value,
                  ),
              ])),
          const SizedBox(height: 8),
          // INCIDENTS vs REPORTS. Incidents is one row per DEFECT (server-built
          // `crash_signatures`); Reports is the raw append-only evidence. The
          // triage question is asked of the first and answered with the second,
          // so Incidents leads and Reports stays one tap away.
          Obx(() => Wrap(spacing: 8, children: [
                for (final (value, label) in const [
                  ('incidents', 'Incidents'),
                  ('reports', 'All reports'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: ctrl.view.value == value,
                    onSelected: (_) => ctrl.view.value = value,
                  ),
              ])),
          const SizedBox(height: 14),
          // One source failing must not silently narrow the truth: say which
          // half of the picture is missing while still showing the other.
          Obx(() {
            final warning = ctrl.partialError;
            if (warning == null) return const SizedBox.shrink();
            final p2 = context.palette;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: p2.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$warning The reports below are incomplete.',
                    style:
                        AppText.body(size: 12).copyWith(color: p2.accent),
                  ),
                ),
                TextButton(
                    onPressed: ctrl.retry, child: const Text('Retry')),
              ]),
            );
          }),
          // PLAIN COLUMN, NOT A ListView: PageShell already wraps its child in
          // a SingleChildScrollView, and an Expanded list inside that scroll
          // context collapses to ZERO height with no exception — found live on
          // the first production open of this screen ("1 total", blank list).
          // The Audit Log renders its rows exactly this way for this reason.
          Obx(() => ctrl.view.value == 'incidents'
              ? _incidentsBody(context)
              : _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (ctrl.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.hasError) {
      return _message(
        context,
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load crash reports",
        body: 'Check your connection, then retry. If this persists, the '
            'founder-only read rule may not be deployed.',
        action: FilledButton.icon(
          onPressed: ctrl.retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }
    final rows = ctrl.filtered;
    if (rows.isEmpty) {
      return switch (ctrl.emptyReason) {
        CrashEmptyReason.noReportsAtAll => _message(
            context,
            icon: Icons.verified_outlined,
            title: 'No crash reports',
            body: 'Nothing has been reported by the console or either '
                'mobile app. That is the healthy state.',
          ),
        CrashEmptyReason.noMatchAnywhere => _message(
            context,
            icon: Icons.search_off_outlined,
            title: 'No matching report',
            body: 'Every report is loaded, and none matches these filters.',
          ),
        CrashEmptyReason.noMatchInLoadedWindow => _message(
            context,
            icon: Icons.history_outlined,
            title: 'Not found in the newest ${ctrl.reports.length}',
            body: 'Older reports exist beyond the loaded window — this is '
                '"not found yet", never "none".',
            action: OutlinedButton(
              onPressed: ctrl.loadMore,
              child: Text(
                  'Load ${CrashReportsController.pageSize} older reports'),
            ),
          ),
      };
    }
    final counts = ctrl.incidentCounts;
    return Column(
      children: [
        for (final r in rows) ...[
          _row(context, r, counts[r.incidentKey] ?? 1),
          const SizedBox(height: 8),
        ],
        if (ctrl.atCap)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: ctrl.isLoadingMore.value
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    onPressed: ctrl.loadMore,
                    child: Text('Load '
                        '${CrashReportsController.pageSize} older reports'),
                  ),
          ),
      ],
    );
  }

  /// THE TRIAGE VIEW — one row per defect, worst first.
  Widget _incidentsBody(BuildContext context) {
    final p = context.palette;
    if (ctrl.signaturesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.signaturesError) {
      return _message(
        context,
        icon: Icons.cloud_off_outlined,
        title: "Couldn't load incidents",
        body: 'The crash_signatures rollup could not be read. Raw reports may '
            'still be available under "All reports".',
        action: FilledButton.icon(
          onPressed: ctrl.retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }
    final rows = ctrl.filteredSignatures;
    if (rows.isEmpty) {
      // AN EMPTY ROLLUP OVER A NON-EMPTY FIREHOSE IS NOT HEALTH.
      // It is the projection not running, and saying "nothing has crashed"
      // there would be the console's worst possible sentence — a confident
      // all-clear derived from missing measurement rather than from calm.
      if (ctrl.rollupStalled) {
        return _message(
          context,
          icon: Icons.report_problem_outlined,
          title: 'Incidents are not being built',
          body: '${ctrl.appReports.length} mobile crash report'
              '${ctrl.appReports.length == 1 ? '' : 's'} exist, but no incident '
              'rollup describes them — ${ctrl.unprojectedReportCount} carry no '
              'signature. The onCrashReportCreated trigger is most likely not '
              'deployed or is failing; check its logs. The raw evidence is '
              'intact under "All reports".',
          action: FilledButton.icon(
            onPressed: () => ctrl.view.value = 'reports',
            icon: const Icon(Icons.list_alt),
            label: const Text('Open all reports'),
          ),
        );
      }
      return _message(
        context,
        icon: Icons.verified_outlined,
        title: ctrl.isNarrowed ? 'No matching incident' : 'No open incidents',
        body: ctrl.isNarrowed
            ? 'No defect matches these filters.'
            : 'No defect has been recorded in either mobile app. That is the '
                'healthy state. (The console\'s own reports are evidence-only '
                'and are not rolled up — see "All reports".)',
      );
    }
    final counts = ctrl.priorityCounts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The one line that answers "what needs attention" before any reading.
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            for (final level in const ['P0', 'P1', 'P2', 'P3'])
              if ((counts[level] ?? 0) > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _priorityColor(context, level)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$level · ${counts[level]}',
                      style: AppText.label(size: 12)
                          .copyWith(color: _priorityColor(context, level))),
                ),
            Text('${rows.length} distinct defect${rows.length == 1 ? '' : 's'}',
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          ]),
        ),
        for (final s in rows) ...[
          _incidentRow(context, s),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Color _priorityColor(BuildContext context, String priority) {
    final p = context.palette;
    return switch (priority) {
      'P0' => p.accent,
      'P1' => p.accent,
      'P2' => p.textSecondary,
      _ => p.textMuted,
    };
  }

  Widget _incidentRow(BuildContext context, CrashSignatureModel s) {
    final p = context.palette;
    final last = s.lastSeenAt == null
        ? 'time unknown'
        : DateFormat('d MMM · HH:mm').format(s.lastSeenAt!.toLocal());
    return Material(
      color: p.surface,
      borderRadius: AppRadii.smR,
      child: InkWell(
        borderRadius: AppRadii.smR,
        onTap: () => _openIncident(context, s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _priorityColor(context, s.priority)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(s.priority,
                    style: AppText.label(size: 11).copyWith(
                        color: _priorityColor(context, s.priority),
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.errorClass} — ${s.normalized}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 13.5)
                          .copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    // BREADTH FIRST. "8 users" is the number that decides
                    // whether this is an outage; the occurrence count is
                    // context, not the headline.
                    Text(
                      '${s.appLabel} · ${s.isFatal ? 'FATAL' : 'non-fatal'} · '
                      '${s.affectedUsersLabel} user'
                      '${s.affectedUsers == 1 && !s.affectedUsersTruncated ? '' : 's'} · '
                      '${s.occurrences} occurrence'
                      '${s.occurrences == 1 ? '' : 's'} · $last',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 11.5)
                          .copyWith(color: p.textMuted),
                    ),
                    if (s.isSingleBuild) ...[
                      const SizedBox(height: 4),
                      // The strongest signal a crash system emits: every
                      // occurrence came from ONE build.
                      Text('only in build ${s.buildsRanked.first.key}',
                          style: AppText.label(size: 11)
                              .copyWith(color: p.accent)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _openIncident(BuildContext context, CrashSignatureModel s) {
    final p = context.palette;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _priorityColor(context, s.priority)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(s.priority,
                        style: AppText.label(size: 11).copyWith(
                            color: _priorityColor(context, s.priority))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(s.errorClass,
                        style: AppText.title(size: 16)
                            .copyWith(color: p.textPrimary)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  [
                    s.appLabel,
                    s.isFatal ? 'fatal' : 'non-fatal',
                    if (s.production) 'production' else 'non-production',
                    '${s.affectedUsersLabel} affected',
                    '${s.occurrences} occurrences',
                    if (s.firstSeenAt != null)
                      'first ${DateFormat('d MMM yyyy · HH:mm').format(s.firstSeenAt!.toLocal())}',
                    if (s.lastSeenAt != null)
                      'last ${DateFormat('d MMM yyyy · HH:mm').format(s.lastSeenAt!.toLocal())}',
                  ].join(' · '),
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      _section(context, 'Where it happens',
                          SelectableText(
                              'section: ${s.sampleSection.isEmpty ? 'unknown' : s.sampleSection}'
                              '\nlabel: ${s.label}',
                              style: _mono(p))),
                      _section(
                        context,
                        'Builds affected',
                        SelectableText(
                          s.buildsRanked.isEmpty
                              ? 'unknown'
                              : s.buildsRanked
                                  .map((e) => '${e.key}  ×${e.value}')
                                  .join('\n'),
                          style: _mono(p),
                        ),
                      ),
                      _section(context, 'Sample error',
                          SelectableText(s.sampleError, style: _mono(p))),
                      if (s.sampleStack.isNotEmpty)
                        _section(context, 'Sample stack',
                            SelectableText(s.sampleStack, style: _mono(p))),
                      _section(
                        context,
                        'Signature',
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(s.id, style: _mono(p)),
                            const SizedBox(height: 8),
                            // The join key is stamped on BOTH sides by the
                            // trigger, so this is a real jump rather than an
                            // instruction to go and type an id by hand.
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                ctrl.showOccurrencesOf(s.id);
                              },
                              icon: const Icon(Icons.list_alt, size: 16),
                              label: Text(
                                'See every occurrence '
                                '(${s.occurrences}) with its own breadcrumbs '
                                'and stack',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Centered state card: loading error, healthy-empty, and the two honest
  /// no-match states share one layout.
  Widget _message(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
  }) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: p.textMuted),
            const SizedBox(height: 12),
            Text(title,
                style: AppText.title(size: 15).copyWith(color: p.textPrimary)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted)),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, CrashReportModel r, int repeats) {
    final p = context.palette;
    final when = r.at == null
        ? 'time unknown'
        : DateFormat('d MMM yyyy · HH:mm').format(r.at!.toLocal());
    return Material(
      color: p.surface,
      borderRadius: AppRadii.smR,
      child: InkWell(
        borderRadius: AppRadii.smR,
        onTap: () => _openDetail(context, r, repeats),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _kindChip(context, r),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.error.split('\n').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 13.5)
                          .copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${r.appLabel} · $when · ${r.label} · ${r.section} · '
                      'build ${r.build} (${r.commit}) · ${r.env}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.body(size: 11.5).copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              if (repeats > 1) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('×$repeats',
                      style: AppText.label(size: 12)
                          .copyWith(color: p.accent)),
                ),
              ],
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 18, color: p.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindChip(BuildContext context, CrashReportModel r) {
    final p = context.palette;
    final color = r.isFatal ? p.accent : p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        r.isFatal ? 'FATAL' : 'NON-FATAL',
        style: AppText.label(size: 10.5)
            .copyWith(color: color, letterSpacing: 0.5),
      ),
    );
  }

  void _openDetail(BuildContext context, CrashReportModel r, int repeats) {
    final p = context.palette;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _kindChip(context, r),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(r.label,
                          style: AppText.title(size: 16)
                              .copyWith(color: p.textPrimary)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    r.appLabel,
                    if (r.platform.isNotEmpty) r.platform,
                    if (r.at != null)
                      DateFormat('d MMM yyyy · HH:mm:ss')
                          .format(r.at!.toLocal()),
                    'build ${r.build} (${r.commit}, ${r.mode})',
                    r.env,
                    r.section,
                    if (repeats > 1) '×$repeats in the loaded window',
                  ].join(' · '),
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      _section(context, 'Error',
                          SelectableText(r.error, style: _mono(p))),
                      if (r.breadcrumbs.isNotEmpty)
                        _section(
                          context,
                          'Breadcrumbs (oldest first)',
                          SelectableText(r.breadcrumbs.join('\n'),
                              style: _mono(p)),
                        ),
                      if (r.stack.isNotEmpty)
                        _section(context, 'Stack trace',
                            SelectableText(r.stack, style: _mono(p))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: AppText.label(size: 11).copyWith(
                  color: p.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.background,
              borderRadius: AppRadii.smR,
              border: Border.all(color: p.border),
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  TextStyle _mono(AppPalette p) => const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        height: 1.45,
      ).copyWith(color: p.textPrimary);
}
