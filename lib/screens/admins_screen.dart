// ORGANIZATIONS — the list is a work queue; opening a row is a workspace.
//
// The list answers "how many, which are healthy, which need me, which are
// new" in the first second: six queue tiles that are also filters, a search
// over the human identifiers, a plan filter, a sort, an active-filter strip,
// and rows that carry standing + operating state + plan + owner + attention.
// Everything deeper lives in OrganizationWorkspace (screens/organization/),
// which this screen swaps in when `AdminController.selectedOrgId` is set.
//
// Words and rules come from core/services/organization_language.dart so
// every count on this screen is a unit-tested predicate, not a widget.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/admin_controller.dart';
import '../core/services/organization_language.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_shadows.dart';
import '../core/theme/app_text.dart';
import '../core/widgets/console/console_chrome.dart';
import '../core/widgets/serena/serena_ui.dart';
import '../models/admin_model.dart';
import '../widgets/page_shell.dart';
import 'organization/organization_action_dialogs.dart';
import 'organization/organization_workspace.dart';

class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});

  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  final AdminController ctrl = Get.find<AdminController>();
  late final TextEditingController _searchCtrl = TextEditingController(
    text: ctrl.search.value,
  );
  Worker? _searchWorker;

  /// The queue tiles, in the order an operator triages. Each is a filter key.
  static const _tiles = <(String, IconData)>[
    ('all', Icons.corporate_fare_outlined),
    ('attention', Icons.warning_amber_outlined),
    ('pending', Icons.how_to_reg_outlined),
    ('noSubscription', Icons.credit_card_off_outlined),
    ('expiring', Icons.hourglass_bottom_outlined),
    ('blocked', Icons.block_outlined),
    ('recent', Icons.fiber_new_outlined),
  ];

  @override
  void initState() {
    super.initState();
    // Another screen may set the search (Access Requests → Open organization);
    // the field must show what the list is actually filtered by.
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
      title: 'Organizations',
      icon: Icons.corporate_fare_outlined,
      trailing: Obx(() {
        if (ctrl.loadError.value != null) return const Text('—');
        if (ctrl.selectedOrgId.value.isNotEmpty) return const SizedBox.shrink();
        if (ctrl.isLoading.value && ctrl.admins.isEmpty) {
          return Text(
            'Loading…',
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          );
        }
        final t = ctrl.lastReceived.value;
        final attention = ctrl.countFor('attention');
        return Text(
          '${OrganizationLanguage.plural(ctrl.admins.length, 'organization')}'
          '${attention > 0 ? ' · $attention need attention' : ''}'
          '${t == null ? '' : ' · Live, updated ${OrganizationLanguage.exactTime(t)}'}',
          style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          textAlign: TextAlign.right,
        );
      }),
      child: Obx(() {
        final err = ctrl.loadError.value;
        final selected = ctrl.selectedOrgId.value;
        if (selected.isNotEmpty) {
          final d = ctrl.detail;
          if (d != null) return OrganizationWorkspace(ctrl: ctrl, detail: d);
        }
        // The classified failure comes BEFORE everything else, tiles included:
        // an undeployed rule and an empty platform must never look alike.
        if (err != null) {
          return ConsoleErrorState(error: err, onRetry: ctrl.retryLoad);
        }
        if (ctrl.isLoading.value && ctrl.admins.isEmpty) return _loading();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tilesRow(context),
            const SizedBox(height: 14),
            _toolbar(context),
            const SizedBox(height: 10),
            _activeFilters(context),
            _malformedNotice(context),
            _progress(context),
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

  // ── QUEUE TILES ─────────────────────────────────────────────────────────

  Widget _tilesRow(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // Two tiles per row on a phone: seven full-width tiles would push the
        // list below the fold before the operator has seen a single row.
        final tileW = box.maxWidth < 600 ? (box.maxWidth - 10) / 2 : 190.0;
        return Obx(() {
          final active = ctrl.statusFilter.value;
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
    final label = OrganizationLanguage.filterLabel(key);
    final accent = switch (key) {
      'attention' => context.serena.statusWarning,
      'blocked' => context.serena.statusBlocked,
      'pending' => context.serena.statusPending,
      'expiring' => context.serena.statusWarning,
      _ => p.accent,
    };
    // One semantics node carries label, role, selected state AND the tap
    // action — the sidebar tile's pattern, pinned by
    // test/a11y_no_excluded_tappables_test.dart.
    return Semantics(
      button: true,
      selected: selected,
      label: '$label: $count. Filter the list.',
      excludeSemantics: true,
      onTap: () => ctrl.statusFilter.value = key,
      child: Focus(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => ctrl.statusFilter.value = key,
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

  // ── TOOLBAR ─────────────────────────────────────────────────────────────

  Widget _toolbar(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 720;
        final search = TextField(
          controller: _searchCtrl,
          onChanged: (v) => ctrl.search.value = v,
          decoration: InputDecoration(
            hintText: 'Search by organization, owner, email, phone or id…',
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
        final plan = Obx(() {
          final names = ctrl.planNames;
          final value = names.contains(ctrl.planFilter.value)
              ? ctrl.planFilter.value
              : 'all';
          return DropdownButtonFormField<String>(
            key: ValueKey('plan-$value-${names.length}'),
            initialValue: value,
            isDense: true,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Plan', isDense: true),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('Any plan')),
              for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: (v) => ctrl.planFilter.value = v ?? 'all',
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
              for (final k in OrganizationLanguage.sortKeys)
                DropdownMenuItem(
                  value: k,
                  child: Text(OrganizationLanguage.sortLabel(k)),
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
                  Expanded(child: plan),
                  const SizedBox(width: 8),
                  Expanded(child: sort),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 3, child: search),
            const SizedBox(width: 10),
            SizedBox(width: 200, child: plan),
            const SizedBox(width: 10),
            SizedBox(width: 250, child: sort),
          ],
        );
      },
    );
  }

  Widget _activeFilters(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (!ctrl.hasActiveFilters) return const SizedBox.shrink();
      final parts = <String>[
        if (ctrl.statusFilter.value != 'all')
          OrganizationLanguage.filterLabel(ctrl.statusFilter.value),
        if (ctrl.planFilter.value != 'all') 'plan ${ctrl.planFilter.value}',
        if (ctrl.search.value.trim().isNotEmpty)
          'matching "${ctrl.search.value.trim()}"',
      ];
      final n = ctrl.filtered.length;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              'Showing ${OrganizationLanguage.plural(n, 'organization')}: ${parts.join(' · ')}',
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

  /// ORG-1: records that are malformed or unreadable are LISTED (never
  /// hidden — the organization that wrote them is the one the founder must
  /// still be able to find and block) and this line says how many, so their
  /// blanks are never read as the owner's real data.
  Widget _malformedNotice(BuildContext context) {
    return Obx(() {
      final bad = ctrl.malformedRecords;
      if (bad.isEmpty) return const SizedBox.shrink();
      final names = bad
          .take(3)
          .map(OrganizationLanguage.displayName)
          .join(', ');
      final more = bad.length > 3 ? ' and ${bad.length - 3} more' : '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.report_gmailerrorred_outlined,
              size: 16,
              color: context.serena.statusWarning,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${OrganizationLanguage.plural(bad.length, 'organization record')} '
                'with fields of the wrong type or unreadable: $names$more. '
                'Listed with blanks where the data cannot be read — never '
                'hidden — and still moderatable.',
                style: AppText.body(
                  size: 12.5,
                ).copyWith(color: context.serena.statusWarning),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _progress(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (ctrl.isProcessing.value) {
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                'Applying the change…',
                style: AppText.body(
                  size: 12.5,
                ).copyWith(color: p.textSecondary),
              ),
            ],
          ),
        );
      }
      final o = ctrl.lastOutcome.value;
      if (o == null) return const SizedBox.shrink();
      final color = o.ok ? context.serena.statusActive : context.serena.error;
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: AppRadii.smR,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  o.ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.title,
                        style: AppText.label(
                          size: 13.5,
                        ).copyWith(color: p.textPrimary),
                      ),
                      Text(
                        o.message,
                        style: AppText.body(
                          size: 12.5,
                        ).copyWith(color: p.textSecondary),
                      ),
                      Text(
                        switch (o.changed) {
                          true => 'The record changed.',
                          false => 'Nothing was changed.',
                          null =>
                            'Whether the record changed is not known — the list is live; check the row.',
                        },
                        style: AppText.body(
                          size: 11.5,
                        ).copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: ctrl.dismissOutcome,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // ── LIST ────────────────────────────────────────────────────────────────

  Widget _list(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final now = ctrl.clock();
      final all = ctrl.filtered;
      if (all.isEmpty) {
        if (ctrl.admins.isEmpty) {
          return const ConsoleEmptyState(
            icon: Icons.corporate_fare_outlined,
            title: 'No organizations yet',
            message:
                'Organizations are created from Access Requests once a prospect '
                'has paid. None exist on the platform so far.',
          );
        }
        return ConsoleEmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'No organizations match',
          message:
              'Nothing matches the current filters. Clear them to see all '
              '${OrganizationLanguage.plural(ctrl.admins.length, 'organization')}.',
          action: TextButton(
            onPressed: ctrl.clearFilters,
            child: const Text('Clear filters'),
          ),
        );
      }
      // One filter+sort per build: `ctrl.page` would run `filtered` again.
      final page = all.take(ctrl.visibleCount.value).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in page) ...[
            _row(context, a, now),
            const SizedBox(height: 8),
          ],
          if (page.length < all.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(
                    'Showing ${page.length} of ${all.length}',
                    style: AppText.body(
                      size: 12.5,
                    ).copyWith(color: p.textMuted),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: ctrl.showMore,
                    child: Text('Show ${AdminController.pageSize} more'),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _row(BuildContext context, AdminModel a, DateTime now) {
    final p = context.palette;
    final name = OrganizationLanguage.displayName(a);
    final standing = OrganizationLanguage.standingOf(a);
    final sub = OrganizationLanguage.subscriptionOf(a, now: now);
    final issues = OrganizationLanguage.recordIssues(a, now: now);
    final flagged = issues.where((i) => i.needsAttention).toList();
    final primary = OrganizationLanguage.primaryAction(a, now: now);
    final busy = ctrl.isProcessing.value;
    final planLine = sub.isActiveFlag
        ? '${sub.planName} · ${sub.label}'
              '${sub.endsAt != null ? ' · ends ${OrganizationLanguage.exact(sub.endsAt)}' : ''}'
        : sub.label;

    return Semantics(
      label:
          '$name. ${standing.label}. ${OrganizationLanguage.operatingLine(a)}. '
          '$planLine. Owner ${OrganizationLanguage.ownerName(a)}. '
          '${OrganizationLanguage.createdLine(a, now: now)}.'
          '${flagged.isEmpty ? '' : ' ${flagged.length} need attention: ${flagged.first.title}.'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.cardR,
          onTap: () => ctrl.openOrganization(a.docId),
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
                        AttentionPill(issues: issues),
                        if (OrganizationLanguage.isRecent(a, now: now))
                          ConsolePill(
                            label: 'New',
                            color: p.accent,
                            icon: Icons.fiber_new_outlined,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      OrganizationLanguage.operatingLine(a),
                      style: AppText.body(size: 12).copyWith(
                        color: OrganizationLanguage.canOperate(a)
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
                          Icons.workspace_premium_outlined,
                          planLine,
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.person_outline,
                          '${OrganizationLanguage.ownerName(a)} · ${OrganizationLanguage.ownerEmail(a)}',
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.groups_outlined,
                          '${OrganizationLanguage.plural(a.trainerIds.length, 'trainer seat')} in use',
                          metaW,
                        ),
                        _meta(
                          context,
                          Icons.calendar_today_outlined,
                          a.createdAtKnown
                              ? 'Created ${OrganizationLanguage.relative(a.createdAt, now: now)}'
                              : 'Creation date not recorded',
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
                final buttons = Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    // MergeSemantics: the labelled node IS the button, so a
                    // screen reader hears "Approve: Pulse Fitness" on the
                    // control it can press (a bare Semantics(label) publishes
                    // a separate, unpressable node).
                    if (primary != null)
                      MergeSemantics(
                        child: Semantics(
                          label:
                              '${OrganizationLanguage.actionLabelFor(primary, a)}: $name',
                          child: FilledButton.tonal(
                            onPressed: busy
                                ? null
                                : () => showOrgActionDialog(
                                    context,
                                    action: primary,
                                    org: a,
                                    ctrl: ctrl,
                                  ),
                            child: Text(
                              OrganizationLanguage.actionLabelFor(primary, a),
                            ),
                          ),
                        ),
                      ),
                    MergeSemantics(
                      child: Semantics(
                        label: 'Open organization: $name',
                        child: OutlinedButton.icon(
                          onPressed: () => ctrl.openOrganization(a.docId),
                          icon: const Icon(Icons.open_in_full, size: 14),
                          label: const Text('Open'),
                        ),
                      ),
                    ),
                  ],
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _avatar(context, a),
                          const SizedBox(width: 12),
                          Expanded(child: body),
                        ],
                      ),
                      const SizedBox(height: 10),
                      buttons,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _avatar(context, a),
                    const SizedBox(width: 12),
                    Expanded(child: body),
                    const SizedBox(width: 12),
                    buttons,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// A metadata fragment inside a Wrap. Capped at [maxWidth] and ellipsised,
  /// because a Row inside a Wrap otherwise takes its intrinsic width and a
  /// long owner email overflows a phone screen.
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

  Widget _avatar(BuildContext context, AdminModel a) {
    final p = context.palette;
    final url = (a.profilePicUrl ?? '').trim();
    final fallback = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        OrganizationLanguage.initial(a),
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
