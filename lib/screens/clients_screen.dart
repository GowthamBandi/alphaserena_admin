// MEMBERS — platform-wide oversight of every organization's members. A work
// queue that opens into a read-only workspace.
//
// The platform cannot change a member (owner- and member-gated backend, rules
// deny the founder every write), so this screen's job is understanding and
// routing: which members are paying and not being served, which are lapsing,
// which records are broken, and which organization or trainer to open to fix
// it.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/client_controller.dart';
import '../core/services/member_insights.dart';
import '../core/services/member_language.dart';
import '../core/services/organization_language.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_shadows.dart';
import '../core/theme/app_text.dart';
import '../core/widgets/console/console_chrome.dart';
import '../core/widgets/serena/serena_ui.dart';
import '../models/clints_model.dart';
import '../widgets/page_shell.dart';
import 'member/member_workspace.dart';
import 'organization/organization_workspace.dart'
    show severityColor, severityIcon;

SerenaStatus membershipStatus(MembershipState s) => switch (s) {
  MembershipState.active => SerenaStatus.active,
  MembershipState.expiringSoon => SerenaStatus.warning,
  MembershipState.frozen => SerenaStatus.pending,
  MembershipState.expired => SerenaStatus.blocked,
  MembershipState.none => SerenaStatus.neutral,
};

class ClientsScreen extends StatefulWidget {
  ClientsScreen({super.key}) {
    // Members is not pre-registered by the bootstrap (it tears the controller
    // down on sign-out); register on first open, once.
    if (!Get.isRegistered<ClientController>()) {
      Get.put<ClientController>(ClientController(), permanent: true);
    }
  }

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final ClientController ctrl = Get.find<ClientController>();
  late final TextEditingController _searchCtrl = TextEditingController(
    text: ctrl.search.value,
  );
  Worker? _searchWorker;

  static const _tileIcons = <String, IconData>{
    'all': Icons.people_outline,
    'attention': Icons.warning_amber_outlined,
    'current': Icons.verified_outlined,
    'expiring': Icons.hourglass_bottom_outlined,
    'lapsed': Icons.event_busy_outlined,
    'dormant': Icons.bedtime_outlined,
  };

  static const _extraFilters = <(String, IconData)>[
    ('frozen', Icons.ac_unit_outlined),
    ('ownerCoached', Icons.person_pin_outlined),
    ('noPlan', Icons.assignment_late_outlined),
    ('unlinked', Icons.link_off_outlined),
    ('recent', Icons.fiber_new_outlined),
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
      title: 'Members',
      icon: Icons.people_outline,
      trailing: Obx(() {
        if (ctrl.loadError.value != null) return const Text('—');
        if (ctrl.selectedMemberId.value.isNotEmpty) {
          return const SizedBox.shrink();
        }
        if (ctrl.isLoading.value && ctrl.clients.isEmpty) {
          return Text(
            'Loading…',
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          );
        }
        final t = ctrl.lastReceived.value;
        final attention = ctrl.countFor('attention');
        final current = ctrl.countFor('current');
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                'Platform-wide member intelligence · '
                '${OrganizationLanguage.plural(ctrl.totalCount, 'member')}'
                ' · $current with a running membership'
                '${attention > 0 ? ' · $attention need attention' : ''}'
                '${t == null ? '' : ' · Live, updated ${OrganizationLanguage.exactTime(t)}'}',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
                textAlign: TextAlign.right,
              ),
            ),
            Tooltip(
              message: 'Refresh members, organizations and trainers',
              child: IconButton(
                onPressed: ctrl.refreshAll,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ),
          ],
        );
      }),
      child: Obx(() {
        final err = ctrl.loadError.value;
        if (ctrl.selectedMemberId.value.isNotEmpty) {
          final d = ctrl.detail;
          if (d != null) return MemberWorkspace(ctrl: ctrl, detail: d);
        }
        if (err != null) {
          return ConsoleErrorState(error: err, onRetry: ctrl.retryLoad);
        }
        if (ctrl.isLoading.value && ctrl.clients.isEmpty) return _loading();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tilesRow(context),
            const SizedBox(height: 14),
            _toolbar(context),
            const SizedBox(height: 10),
            _extraFilterRow(context),
            const SizedBox(height: 10),
            _joinWarnings(context),
            _activeFilters(context),
            _insights(context),
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
        final tileW = box.maxWidth < 600 ? (box.maxWidth - 10) / 2 : 176.0;
        return Obx(() {
          final active = ctrl.selectedFilter.value;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final key in MemberLanguage.tileKeys)
                _tile(
                  context,
                  key,
                  _tileIcons[key] ?? Icons.circle_outlined,
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

  Color _accentFor(BuildContext context, String key) {
    final p = context.palette;
    return switch (key) {
      'attention' => context.serena.statusWarning,
      'lapsed' => context.serena.statusBlocked,
      'expiring' => context.serena.statusWarning,
      'current' => context.serena.statusActive,
      'dormant' => context.serena.statusPending,
      'frozen' => context.serena.info,
      _ => p.accent,
    };
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
    final label = MemberLanguage.filterLabel(key);
    final accent = _accentFor(context, key);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label: $count. Filter the list.',
      excludeSemantics: true,
      onTap: () => ctrl.selectedFilter.value = key,
      child: Focus(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => ctrl.selectedFilter.value = key,
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
            hintText:
                'Search by name, email, phone, plan, organization, coach or id…',
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
              for (final k in MemberLanguage.sortKeys)
                DropdownMenuItem(
                  value: k,
                  child: Text(MemberLanguage.sortLabel(k)),
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

  /// The less common queues, as chips (they share the tile filter).
  Widget _extraFilterRow(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final active = ctrl.selectedFilter.value;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'More queues:',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          for (final (key, icon) in _extraFilters)
            ConsoleChip(
              label:
                  '${MemberLanguage.shortFilterLabel(key)} · ${ctrl.countFor(key)}',
              icon: icon,
              active: active == key,
              onTap: () =>
                  ctrl.selectedFilter.value = active == key ? 'all' : key,
            ),
        ],
      );
    });
  }

  /// The organization and trainer lists are separate streams; if either
  /// failed, every word derived from it is unavailable — say so once.
  Widget _joinWarnings(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final rows = <String>[
        if (ctrl.orgsError != null)
          'The organization list could not be loaded, so organization names and '
              'organization-related checks are unavailable here. ${ctrl.orgsError!.message}',
        if (ctrl.trainersError != null)
          'The trainer list could not be loaded, so coach names and coach-related '
              'checks are unavailable here. ${ctrl.trainersError!.message}',
      ];
      if (rows.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: p.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r,
                        style: AppText.body(
                          size: 12.5,
                        ).copyWith(color: p.error),
                      ),
                    ),
                  ],
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
        if (ctrl.selectedFilter.value != 'all')
          MemberLanguage.filterLabel(ctrl.selectedFilter.value),
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
              'Showing ${OrganizationLanguage.plural(ctrl.filteredClients.length, 'member')}: ${parts.join(' · ')}',
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

  // ── insights (platform-wide; hidden while hunting with filters) ───────────

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Widget _insights(BuildContext context) {
    return Obx(() {
      if (ctrl.hasActiveFilters || ctrl.totalCount == 0) {
        return const SizedBox.shrink();
      }
      final live = ctrl.live.toList();
      final series = clientGrowthSeries(live, now: ctrl.clock());
      final goals = clientGoalBreakdown(live);
      return LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 760;
          final growth = ConsoleCard(
            title: 'NEW MEMBERS BY MONTH',
            child: SizedBox(height: 120, child: _growthChart(context, series)),
          );
          // The goals card takes chart height only when it has bars to draw;
          // a one-line "nothing recorded" note must not float in 120px of air.
          final goalCard = ConsoleCard(
            title: 'GOALS, AS RECORDED',
            child: goals.hasAnyRecorded
                ? SizedBox(height: 120, child: _goals(context, goals))
                : _goals(context, goals),
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: narrow
                ? Column(
                    children: [growth, const SizedBox(height: 10), goalCard],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: growth),
                      const SizedBox(width: 10),
                      Expanded(child: goalCard),
                    ],
                  ),
          );
        },
      );
    });
  }

  Widget _growthChart(BuildContext context, GrowthSeries series) {
    final p = context.palette;
    if (!series.hasAnyDated) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          series.undated > 0
              ? 'No member has a recorded join date (${series.undated} without one).'
              : 'No members joined in the last 6 months.',
          style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in series.months)
                Expanded(
                  child: Semantics(
                    label:
                        '${_monthNames[m.month.month - 1]}: ${OrganizationLanguage.plural(m.count, 'new member')}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${m.count}',
                            style: AppText.body(size: 11).copyWith(
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            height: series.peak == 0
                                ? 2.0
                                : 4 + (54 * m.count / series.peak),
                            decoration: BoxDecoration(
                              color: p.accent.withValues(
                                alpha: m.count == 0 ? 0.25 : 0.85,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _monthNames[m.month.month - 1],
                            style: AppText.body(
                              size: 10,
                            ).copyWith(color: p.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (series.undated > 0)
          Text(
            '${OrganizationLanguage.plural(series.undated, 'member has', 'members have')} no recorded join date and are not counted here.',
            style: AppText.body(size: 10.5).copyWith(color: p.textMuted),
          ),
      ],
    );
  }

  Widget _goals(BuildContext context, GoalBreakdown b) {
    final p = context.palette;
    if (!b.hasAnyRecorded) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'No member has a goal recorded (${b.notRecorded} of ${b.total}). '
          'Goals come from the member\'s own profile or the coach record.',
          style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
        ),
      );
    }
    final max = b.goals.first.count;
    return SingleChildScrollView(
      child: Column(
        children: [
          for (final g in b.goals) _goalRow(context, g.label, g.count, max),
          if (b.notRecorded > 0)
            _goalRow(context, 'Not recorded', b.notRecorded, max, muted: true),
        ],
      ),
    );
  }

  Widget _goalRow(
    BuildContext context,
    String label,
    int count,
    int max, {
    bool muted = false,
  }) {
    final p = context.palette;
    final frac = max == 0 ? 0.0 : (count / max).clamp(0.0, 1.0);
    return Semantics(
      label: '$label: ${OrganizationLanguage.plural(count, 'member')}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(
                  size: 12,
                ).copyWith(color: muted ? p.textMuted : p.textSecondary),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 8,
                  backgroundColor: p.surfaceAlt,
                  color: muted ? p.textMuted : p.accent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: AppText.body(
                size: 12,
              ).copyWith(color: p.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // ── list ──────────────────────────────────────────────────────────────────

  Widget _list(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final now = ctrl.clock();
      final all = ctrl.filteredClients;
      if (all.isEmpty) {
        if (ctrl.totalCount == 0) {
          return const ConsoleEmptyState(
            icon: Icons.people_outline,
            title: 'No members yet',
            message:
                'Members appear when someone buys or is sold a membership in an '
                'organization. None exist on the platform so far.',
          );
        }
        return ConsoleEmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'No members match',
          message:
              'Nothing matches the current filters. Clear them to see all '
              '${OrganizationLanguage.plural(ctrl.totalCount, 'member')}.',
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
          for (final m in page) ...[
            _row(context, m, now),
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
                  child: Text('Show ${ClientController.pageSize} more'),
                ),
              ],
            ),
        ],
      );
    });
  }

  Widget _row(BuildContext context, ClientModel m, DateTime now) {
    final p = context.palette;
    final name = MemberLanguage.displayName(m);
    final state = MemberLanguage.membershipState(m, now: now);
    final issues = ctrl.issuesOf(m, now: now);
    final flagged = issues.where((i) => i.needsAttention).toList();
    final orgName = ctrl.orgName(m);
    final coach = ctrl.coachLine(m);
    final membership = MemberLanguage.membershipLine(m, now: now);
    final link = MemberLanguage.accountLink(m);
    return Semantics(
      label:
          '$name, $orgName. ${state.label}. $membership. $coach. '
          '${MemberLanguage.activityLine(m, now: now)}.'
          '${flagged.isEmpty ? '' : ' ${flagged.length} need attention: ${flagged.first.title}.'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.cardR,
          onTap: () => ctrl.openMember(m.docId),
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
                          label: state.label,
                          status: membershipStatus(state),
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
                        if (link != AccountLink.linked)
                          ConsolePill(
                            label: link.label,
                            color: p.textMuted,
                            icon: Icons.link_off_outlined,
                          ),
                        if (MemberLanguage.statusIsInactive(m))
                          ConsolePill(
                            label: 'Switched off by owner',
                            color: p.textMuted,
                            icon: Icons.toggle_off_outlined,
                          ),
                        if (MemberLanguage.isRecent(m, now: now))
                          ConsolePill(
                            label: 'New',
                            color: p.accent,
                            icon: Icons.fiber_new_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      membership,
                      style: AppText.body(size: 12).copyWith(
                        color: state.isCurrent
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
                          Icons.sports_gymnastics_outlined,
                          coach,
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.assignment_outlined,
                          MemberLanguage.trainingLine(m),
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.alternate_email,
                          MemberLanguage.contactLine(m),
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.calendar_today_outlined,
                          m.createdAtKnown
                              ? 'Joined ${OrganizationLanguage.relative(m.createdAt, now: now)}'
                              : 'Join date not recorded',
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.bolt_outlined,
                          MemberLanguage.activityLine(m, now: now),
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
                    label: 'Open member: $name',
                    child: OutlinedButton.icon(
                      onPressed: () => ctrl.openMember(m.docId),
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
                          memberAvatar(context, m),
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
                    memberAvatar(context, m),
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
}

/// The member's photo (their own profile photo first, the coach record's
/// second) or their initial. Shared with the workspace.
Widget memberAvatar(BuildContext context, ClientModel m, {double size = 40}) {
  final p = context.palette;
  final url = MemberLanguage.photoUrl(m) ?? '';
  final fallback = Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: p.accent.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Text(
      MemberLanguage.initial(m),
      style: AppText.label(size: size * 0.4).copyWith(color: p.accent),
    ),
  );
  if (url.isEmpty) return ExcludeSemantics(child: fallback);
  return ExcludeSemantics(
    child: ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, e, s) => fallback,
      ),
    ),
  );
}
