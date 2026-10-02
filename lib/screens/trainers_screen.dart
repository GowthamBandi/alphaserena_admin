// TRAINERS — platform-wide oversight of coaching staff. A work queue that
// opens into a read-only workspace.
//
// The platform cannot change a trainer (owner-gated backend, rules deny
// direct writes), so this screen's job is understanding and routing: which
// trainers cannot work and why, which organization to open to fix it.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/trainer_controller.dart';
import '../core/services/organization_language.dart';
import '../core/services/trainer_language.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_shadows.dart';
import '../core/theme/app_text.dart';
import '../core/widgets/console/console_chrome.dart';
import '../core/widgets/serena/serena_ui.dart';
import '../models/trainer_model.dart';
import '../widgets/page_shell.dart';
import 'organization/organization_workspace.dart'
    show severityColor, severityIcon;
import 'trainer/trainer_workspace.dart';

class TrainersScreen extends StatefulWidget {
  const TrainersScreen({super.key});

  @override
  State<TrainersScreen> createState() => _TrainersScreenState();
}

class _TrainersScreenState extends State<TrainersScreen> {
  final TrainerController ctrl = Get.find<TrainerController>();
  late final TextEditingController _searchCtrl = TextEditingController(
    text: ctrl.search.value,
  );
  Worker? _searchWorker;

  static const _tiles = <(String, IconData)>[
    ('all', Icons.fitness_center_outlined),
    ('attention', Icons.warning_amber_outlined),
    ('active', Icons.check_circle_outline),
    ('inactive', Icons.pause_circle_outline),
    ('removed', Icons.person_off_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _searchWorker = ever(ctrl.search, (String v) {
      if (_searchCtrl.text != v) _searchCtrl.text = v;
    });
  }

  @override
  void dispose() {
    _searchWorker?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Trainers',
      icon: Icons.fitness_center_outlined,
      trailing: Obx(() {
        if (ctrl.loadError.value != null) return const Text('—');
        if (ctrl.selectedTrainerId.value.isNotEmpty) {
          return const SizedBox.shrink();
        }
        if (ctrl.isLoading.value && ctrl.trainers.isEmpty) {
          return Text(
            'Loading…',
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          );
        }
        final t = ctrl.lastReceived.value;
        final attention = ctrl.countFor('attention');
        return Text(
          '${OrganizationLanguage.plural(ctrl.totalCount, 'trainer')} across the platform'
          '${attention > 0 ? ' · $attention need attention' : ''}'
          '${t == null ? '' : ' · Live, updated ${OrganizationLanguage.exactTime(t)}'}',
          style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          textAlign: TextAlign.right,
        );
      }),
      child: Obx(() {
        final err = ctrl.loadError.value;
        if (ctrl.selectedTrainerId.value.isNotEmpty) {
          final d = ctrl.detail;
          if (d != null) return TrainerWorkspace(ctrl: ctrl, detail: d);
        }
        if (err != null) {
          return ConsoleErrorState(error: err, onRetry: ctrl.retryLoad);
        }
        if (ctrl.isLoading.value && ctrl.trainers.isEmpty) return _loading();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tilesRow(context),
            const SizedBox(height: 14),
            _toolbar(context),
            const SizedBox(height: 10),
            _orgJoinWarning(context),
            _activeFilters(context),
            const SizedBox(height: 8),
            _list(context),
          ],
        );
      }),
    );
  }

  Widget _loading() => Column(
    children: [
      for (var i = 0; i < 6; i++) ...[
        const ConsoleSkeletonRow(),
        const SizedBox(height: 10),
      ],
    ],
  );

  // ── tiles ─────────────────────────────────────────────────────────────────

  Widget _tilesRow(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final tileW = box.maxWidth < 600 ? (box.maxWidth - 10) / 2 : 190.0;
        return Obx(() {
          final active = ctrl.selectedStatus.value;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (key, icon) in _tiles)
                _tile(
                  context,
                  key,
                  icon,
                  ctrl.countFor(key),
                  active == key,
                  tileW,
                ),
            ],
          );
        });
      },
    );
  }

  Widget _tile(
    BuildContext context,
    String key,
    IconData icon,
    int count,
    bool selected,
    double width,
  ) {
    final p = context.palette;
    final label = TrainerLanguage.filterLabel(key);
    final accent = switch (key) {
      'attention' => context.serena.statusWarning,
      'removed' => context.serena.statusBlocked,
      'inactive' => context.serena.statusPending,
      'active' => context.serena.statusActive,
      _ => p.accent,
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label: $count. Filter the list.',
      excludeSemantics: true,
      onTap: () => ctrl.selectedStatus.value = key,
      child: Focus(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => ctrl.selectedStatus.value = key,
            borderRadius: AppRadii.smR,
            child: Container(
              width: width,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? accent.withValues(alpha: 0.10) : p.surface,
                borderRadius: AppRadii.smR,
                border: Border.all(
                  color: selected ? accent : p.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: selected ? accent : p.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 11.5).copyWith(
                            color: selected ? accent : p.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count',
                    style: AppText.title(
                      size: 24,
                    ).copyWith(color: selected ? accent : p.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── toolbar ───────────────────────────────────────────────────────────────

  Widget _toolbar(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 720;
        final search = TextField(
          controller: _searchCtrl,
          onChanged: (v) => ctrl.search.value = v,
          decoration: InputDecoration(
            hintText: 'Search by name, email, phone, organization or id…',
            prefixIcon: Icon(Icons.search, color: p.textMuted),
            suffixIcon: Obx(
              () => ctrl.search.value.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        ctrl.search.value = '';
                      },
                    ),
            ),
            filled: true,
            fillColor: p.surface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.border),
            ),
          ),
        );
        final org = Obx(() {
          final opts = ctrl.orgOptions;
          final value = opts.any((e) => e.key == ctrl.orgFilter.value)
              ? ctrl.orgFilter.value
              : 'all';
          return DropdownButtonFormField<String>(
            key: ValueKey('org-$value-${opts.length}'),
            initialValue: value,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Organization',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(
                value: 'all',
                child: Text('Any organization'),
              ),
              for (final e in opts)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => ctrl.orgFilter.value = v ?? 'all',
          );
        });
        final sort = Obx(
          () => DropdownButtonFormField<String>(
            key: ValueKey('sort-${ctrl.sortKey.value}'),
            initialValue: ctrl.sortKey.value,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sort', isDense: true),
            items: [
              for (final k in TrainerLanguage.sortKeys)
                DropdownMenuItem(
                  value: k,
                  child: Text(TrainerLanguage.sortLabel(k)),
                ),
            ],
            onChanged: (v) => ctrl.sortKey.value = v ?? 'attention',
          ),
        );
        if (narrow) {
          return Column(
            children: [
              search,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: org),
                  const SizedBox(width: 8),
                  Expanded(child: sort),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: search),
            const SizedBox(width: 10),
            SizedBox(width: 240, child: org),
            const SizedBox(width: 10),
            SizedBox(width: 250, child: sort),
          ],
        );
      },
    );
  }

  /// The organization list is a separate stream; if it failed, every
  /// organization-derived word on this screen is unavailable — say so once.
  Widget _orgJoinWarning(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final e = ctrl.orgsError;
      if (e == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: p.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'The organization list could not be loaded, so organization names and '
                'organization-related checks are unavailable on this screen. ${e.message}',
                style: AppText.body(size: 12.5).copyWith(color: p.error),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _activeFilters(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (!ctrl.hasActiveFilters) return const SizedBox.shrink();
      final orgLabel = ctrl.orgOptions
          .where((e) => e.key == ctrl.orgFilter.value)
          .map((e) => e.value)
          .firstOrNull;
      final parts = <String>[
        if (ctrl.selectedStatus.value != 'all')
          TrainerLanguage.filterLabel(ctrl.selectedStatus.value),
        if (ctrl.orgFilter.value != 'all')
          'organization ${orgLabel ?? ctrl.orgFilter.value}',
        if (ctrl.search.value.trim().isNotEmpty)
          'matching "${ctrl.search.value.trim()}"',
      ];
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              'Showing ${OrganizationLanguage.plural(ctrl.filteredTrainers.length, 'trainer')}: ${parts.join(' · ')}',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
            TextButton(
              onPressed: ctrl.clearFilters,
              child: const Text('Clear filters'),
            ),
          ],
        ),
      );
    });
  }

  // ── list ──────────────────────────────────────────────────────────────────

  Widget _list(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final now = ctrl.clock();
      final all = ctrl.filteredTrainers;
      if (all.isEmpty) {
        if (ctrl.trainers.isEmpty) {
          return const ConsoleEmptyState(
            icon: Icons.fitness_center_outlined,
            title: 'No trainers yet',
            message:
                'Organization owners add trainers in the Trainersarena app. '
                'None exist on the platform so far.',
          );
        }
        return ConsoleEmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'No trainers match',
          message:
              'Nothing matches the current filters. Clear them to see all '
              '${OrganizationLanguage.plural(ctrl.totalCount, 'trainer')}'
              '${ctrl.removedCount > 0 ? ' (and ${ctrl.removedCount} removed under their own filter)' : ''}.',
          action: TextButton(
            onPressed: ctrl.clearFilters,
            child: const Text('Clear filters'),
          ),
        );
      }
      final page = ctrl.page;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in page) ...[
            _row(context, t, now),
            const SizedBox(height: 8),
          ],
          if (page.length < all.length)
            Row(
              children: [
                Text(
                  'Showing ${page.length} of ${all.length}',
                  style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: ctrl.showMore,
                  child: Text('Show ${TrainerController.pageSize} more'),
                ),
              ],
            ),
        ],
      );
    });
  }

  Widget _row(BuildContext context, TrainerModel t, DateTime now) {
    final p = context.palette;
    final name = TrainerLanguage.displayName(t);
    final org = ctrl.orgOf(t);
    final standing = TrainerLanguage.standingOf(t);
    final issues = TrainerLanguage.issues(
      t,
      org: org,
      orgKnown: ctrl.orgsKnown,
      now: now,
    );
    final flagged = issues.where((i) => i.needsAttention).toList();
    final orgName = ctrl.orgName(t);
    final working = TrainerLanguage.workingLine(t, org);
    return Semantics(
      label:
          '$name, $orgName. ${standing.label}. $working. '
          '${TrainerLanguage.signInLine(t, now: now)}.'
          '${flagged.isEmpty ? '' : ' ${flagged.length} need attention: ${flagged.first.title}.'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.cardR,
          onTap: () => ctrl.openTrainer(t.docId),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.cardR,
              border: Border.all(
                color:
                    flagged.any((i) => i.severity == OrgIssueSeverity.critical)
                    ? context.serena.error.withValues(alpha: 0.5)
                    : p.border,
              ),
              boxShadow: AppShadows.card(p.isDark),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final narrow = box.maxWidth < 640;
                final metaW = box.maxWidth - 60;
                final body = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          name,
                          style: AppText.label(
                            size: 14.5,
                          ).copyWith(color: p.textPrimary),
                        ),
                        SerenaStatusPill(
                          label: standing.label,
                          status: standingStatus(standing),
                        ),
                        if (standing != TrainerStanding.removed)
                          ConsolePill(
                            label: TrainerLanguage.accessLabel(t),
                            color: t.orgActive == true
                                ? context.serena.statusActive
                                : p.textMuted,
                          ),
                        if (flagged.isNotEmpty)
                          ConsolePill(
                            label:
                                flagged.first.severity ==
                                    OrgIssueSeverity.critical
                                ? 'Urgent · ${flagged.length}'
                                : 'Needs attention · ${flagged.length}',
                            color: severityColor(
                              context,
                              flagged.first.severity,
                            ),
                            icon: severityIcon(flagged.first.severity),
                          ),
                        if (TrainerLanguage.isRecent(t, now: now) &&
                            standing != TrainerStanding.removed)
                          ConsolePill(
                            label: 'New',
                            color: p.accent,
                            icon: Icons.fiber_new_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      working,
                      style: AppText.body(size: 12).copyWith(
                        color: working.startsWith('Working')
                            ? context.serena.statusActive
                            : p.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 14,
                      runSpacing: 2,
                      children: [
                        _meta(
                          context,
                          Icons.corporate_fare_outlined,
                          orgName,
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.mail_outline,
                          TrainerLanguage.email(t),
                          metaW,
                        ),
                        if ((t.specialization ?? '').trim().isNotEmpty)
                          _meta(
                            context,
                            Icons.sports_gymnastics_outlined,
                            t.specialization!.trim(),
                            metaW,
                          ),
                        _meta(
                          context,
                          Icons.calendar_today_outlined,
                          'Added ${OrganizationLanguage.relative(t.createdAt, now: now)}',
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.login_outlined,
                          TrainerLanguage.signInLine(t, now: now),
                          metaW,
                        ),
                      ],
                    ),
                    if (flagged.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        flagged.first.title +
                            (flagged.length > 1
                                ? ' · +${flagged.length - 1} more'
                                : ''),
                        style: AppText.body(size: 12).copyWith(
                          color: severityColor(context, flagged.first.severity),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                );
                final open = MergeSemantics(
                  child: Semantics(
                    label: 'Open trainer: $name',
                    child: OutlinedButton.icon(
                      onPressed: () => ctrl.openTrainer(t.docId),
                      icon: const Icon(Icons.open_in_full, size: 14),
                      label: const Text('Open'),
                    ),
                  ),
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _avatar(context, t),
                          const SizedBox(width: 12),
                          Expanded(child: body),
                        ],
                      ),
                      const SizedBox(height: 10),
                      open,
                    ],
                  );
                }
                return Row(
                  children: [
                    _avatar(context, t),
                    const SizedBox(width: 12),
                    Expanded(child: body),
                    const SizedBox(width: 12),
                    open,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _meta(
    BuildContext context,
    IconData icon,
    String text,
    double maxWidth,
  ) {
    final p = context.palette;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: p.textMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, TrainerModel t) {
    final p = context.palette;
    final url = (t.profilePicUrl ?? '').trim();
    final fallback = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        TrainerLanguage.initial(t),
        style: AppText.label(size: 16).copyWith(color: p.accent),
      ),
    );
    if (url.isEmpty) return ExcludeSemantics(child: fallback);
    return ExcludeSemantics(
      child: ClipOval(
        child: Image.network(
          url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (_, e, s) => fallback,
        ),
      ),
    );
  }
}

SerenaStatus standingStatus(TrainerStanding s) => switch (s) {
  TrainerStanding.working => SerenaStatus.active,
  TrainerStanding.onHold => SerenaStatus.pending,
  TrainerStanding.removed => SerenaStatus.blocked,
  TrainerStanding.unknown => SerenaStatus.neutral,
};
