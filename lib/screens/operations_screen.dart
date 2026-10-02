// lib/screens/operations_screen.dart
//
// OPERATIONS CENTER — rendered for a business owner, not an engineer.
//
// The screen answers, top to bottom:
//   1. Is everything okay?            → status banner (one sentence)
//   2. What needs attention, and how
//      urgent is it?                  → urgency counts + the Needs-attention tab
//   3. What can I do?                 → one primary action per row
//   4. What is already being handled? → In progress tab
//   5. What was handled recently?     → Resolved tab (30 days)
//   6. What else happened?            → Information tab (no action needed)
//
// Every row shows WHAT HAPPENED · WHY IT MATTERS · AFFECTED · WHEN · URGENCY ·
// STATUS · ACTION in words. Backend identifiers live under "Technical
// details". Nothing on this screen is inferred from colour alone.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/admin_controller.dart';
import '../controllers/admin_root_controller.dart';
import '../controllers/operations_controller.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/page_shell.dart';

const _cCritical = Color(0xFFD4341F);
const _cHigh = Color(0xFFC2410C);
const _cAttention = Color(0xFFB06A00);
const _cInfo = Color(0xFF3B6FD4);
const _cClear = Color(0xFF1A7F5A);
const _cProgress = Color(0xFF6C5CE7);

Color _urgencyColor(OpsUrgency u) => switch (u) {
  OpsUrgency.critical => _cCritical,
  OpsUrgency.high => _cHigh,
  OpsUrgency.attention => _cAttention,
  OpsUrgency.info => _cInfo,
};

IconData _urgencyIcon(OpsUrgency u) => switch (u) {
  OpsUrgency.critical => Icons.error_rounded,
  OpsUrgency.high => Icons.warning_amber_rounded,
  OpsUrgency.attention => Icons.flag_outlined,
  OpsUrgency.info => Icons.info_outline,
};

Color _statusColor(OpsItemStatus s) => switch (s) {
  OpsItemStatus.needsAttention => _cHigh,
  OpsItemStatus.inProgress => _cProgress,
  OpsItemStatus.resolved => _cClear,
  OpsItemStatus.informational => _cInfo,
};

class OperationsScreen extends StatelessWidget {
  OperationsScreen({super.key});

  final OperationsController ctrl = Get.find<OperationsController>();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Operations Center',
      icon: Icons.monitor_heart_outlined,
      trailing: Obx(() {
        // "All caught up" IS A CLAIM ABOUT DATA THAT HAS BEEN READ: the badge
        // is gated on anyLoading exactly like the body (SA-15).
        final total = ctrl.totalCount;
        final unproven = total == 0 && ctrl.anyLoading;
        final failed = ctrl.failedFeeds;
        final text = unproven
            ? 'Checking…'
            : failed.isNotEmpty && total == 0
            ? 'Some information unavailable'
            : total == 0
            ? 'All caught up'
            : '$total need${total == 1 ? 's' : ''} attention';
        return Text(
          text,
          style: AppText.body(size: 13).copyWith(
            color: !unproven && total == 0 && failed.isEmpty
                ? _cClear
                : p.textMuted,
          ),
        );
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusBanner(context),
          const SizedBox(height: 16),
          _urgencyRow(context),
          const SizedBox(height: 18),
          _tabs(context),
          const SizedBox(height: 12),
          _filters(context),
          const SizedBox(height: 14),
          _list(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── NAVIGATION ─────────────────────────────────────────────────────────
  static void _go(OpsAction a) {
    if (a.navIndex == null) return;
    if (a.orgFilter != null && Get.isRegistered<AdminController>()) {
      final admins = Get.find<AdminController>();
      admins.statusFilter.value = a.orgFilter!;
      admins.search.value = '';
    }
    if (Get.isRegistered<AdminRootController>()) {
      Get.find<AdminRootController>().changePage(a.navIndex!);
    }
  }

  // ── 1. STATUS BANNER ───────────────────────────────────────────────────
  Widget _statusBanner(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final loading = ctrl.anyLoading && ctrl.totalCount == 0;
      final failed = ctrl.failedFeeds;
      final total = ctrl.totalCount;
      final critical = ctrl.criticalCount;
      final updated = ctrl.lastUpdatedAt.value;

      Color c;
      IconData icon;
      String headline;
      String sub;
      if (loading) {
        c = p.textMuted;
        icon = Icons.hourglass_top_rounded;
        headline = 'Checking the platform…';
        sub = 'Loading organizations, payments, support and system alerts.';
      } else if (total == 0 && failed.isEmpty) {
        c = _cClear;
        icon = Icons.check_circle_rounded;
        headline = "You're all caught up";
        sub =
            'No payments, organizations, support requests or system alerts '
            'need you right now.';
      } else if (total == 0) {
        c = _cAttention;
        icon = Icons.visibility_off_outlined;
        headline = 'Some information could not be loaded';
        sub =
            '${failed.join(', ')} could not be read, so this screen may be '
            'missing problems. Nothing else needs you.';
      } else {
        c = critical > 0 ? _cCritical : _cHigh;
        icon = critical > 0 ? Icons.error_rounded : Icons.warning_amber_rounded;
        headline =
            '$total thing${total == 1 ? '' : 's'} need${total == 1 ? 's' : ''} your attention';
        sub = critical > 0
            ? '$critical ${critical == 1 ? 'is' : 'are'} critical — money or '
                  'access is at risk. Start at the top of the list.'
            : 'None are critical. Work down the list; the most important is '
                  'first.';
        if (failed.isNotEmpty) {
          sub += ' Also: ${failed.join(', ')} could not be loaded.';
        }
      }

      // The texts are read as they are; the "Try again" button inside keeps
      // its own action (no ExcludeSemantics over a tappable — a11y guard).
      return Semantics(
        container: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: AppRadii.cardR,
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Semantics(
            label: 'Platform status',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: c, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: AppText.title(
                          size: 22,
                        ).copyWith(color: p.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        style: AppText.body(
                          size: 13,
                        ).copyWith(color: p.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.sensors, size: 14, color: p.textMuted),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              updated == null
                                  ? 'Live updates · waiting for first data'
                                  : 'Live updates · last change ${OpsTime.human(updated, now: DateTime.now())}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(
                                size: 12,
                              ).copyWith(color: p.textMuted),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (failed.isNotEmpty)
                            TextButton.icon(
                              onPressed: ctrl.retryTelemetry,
                              icon: const Icon(Icons.refresh, size: 14),
                              label: const Text('Try again'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // ── 2. URGENCY COUNTS (tappable filters) ───────────────────────────────
  Widget _urgencyRow(BuildContext context) {
    return Obx(() {
      final counts = {
        OpsUrgency.critical: ctrl.criticalCount,
        OpsUrgency.high: ctrl.highCount,
        OpsUrgency.attention: ctrl.attentionCount,
        OpsUrgency.info: ctrl.infoCount,
      };
      final active = ctrl.urgencyFilter.value;
      return LayoutBuilder(
        builder: (_, box) {
          final tileWidth = box.maxWidth < 700
              ? (box.maxWidth - 12) / 2
              : (box.maxWidth - 36) / 4;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final u in OpsUrgency.values)
                SizedBox(
                  width: tileWidth,
                  child: _urgencyTile(context, u, counts[u]!, active == u),
                ),
            ],
          );
        },
      );
    });
  }

  Widget _urgencyTile(BuildContext context, OpsUrgency u, int n, bool active) {
    final p = context.palette;
    final c = _urgencyColor(u);
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: active,
        label:
            '${u.label}: $n. ${u.meaning} ${active ? 'Filter active, tap to clear.' : 'Tap to show only these.'}',
        child: Tooltip(
          message: u.meaning,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadii.cardR,
              onTap: () {
                ctrl.urgencyFilter.value = active ? null : u;
                if (!active && u == OpsUrgency.info) {
                  ctrl.tab.value = OpsTab.information;
                } else if (!active && ctrl.tab.value == OpsTab.information) {
                  ctrl.tab.value = OpsTab.attention;
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: active ? c.withValues(alpha: 0.10) : p.surface,
                  borderRadius: AppRadii.cardR,
                  border: Border.all(
                    color: active
                        ? c
                        : (n > 0 ? c.withValues(alpha: 0.4) : p.border),
                    width: active ? 1.5 : 1,
                  ),
                  boxShadow: AppShadows.card(p.isDark),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(
                        _urgencyIcon(u),
                        size: 18,
                        color: n > 0 ? c : p.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$n',
                              style: AppText.title(
                                size: 22,
                              ).copyWith(color: n > 0 ? c : p.textMuted),
                            ),
                            Text(
                              u.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(
                                size: 12,
                              ).copyWith(color: p.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 3. TABS ────────────────────────────────────────────────────────────
  Widget _tabs(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final current = ctrl.tab.value;
      // Read every count INSIDE the Obx closure. A nested Builder ran later,
      // outside Obx's tracking, so the chips froze at their first values while
      // the list below them updated — proven on the emulator after an
      // acknowledge (see [[obx-ignores-child-widget-reads]]).
      final counts = {
        for (final t in OpsTab.values) t: ctrl.itemsFor(t).length,
      };
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in OpsTab.values)
            Builder(
              builder: (_) {
                final n = counts[t]!;
                final selected = t == current;
                final c = t == OpsTab.resolved
                    ? _cClear
                    : t == OpsTab.inProgress
                    ? _cProgress
                    : t == OpsTab.information
                    ? _cInfo
                    : _cHigh;
                // MergeSemantics: one node carries the label AND the chip's
                // tap action (an unmerged label node cannot be activated).
                return MergeSemantics(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: '${t.label}, $n item${n == 1 ? '' : 's'}',
                    child: ChoiceChip(
                      label: ExcludeSemantics(child: Text('${t.label} · $n')),
                      selected: selected,
                      onSelected: (_) => ctrl.tab.value = t,
                      selectedColor: c.withValues(alpha: 0.14),
                      labelStyle: AppText.label(
                        size: 13,
                      ).copyWith(color: selected ? c : p.textSecondary),
                      side: BorderSide(color: selected ? c : p.border),
                      showCheckmark: false,
                    ),
                  ),
                );
              },
            ),
        ],
      );
    });
  }

  // ── 4. FILTERS ─────────────────────────────────────────────────────────
  Widget _filters(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final u = ctrl.urgencyFilter.value;
      // Read reactive state here, not inside LayoutBuilder (untracked there).
      final searchText = ctrl.search.value;
      final hasFilters = ctrl.hasActiveFilters;
      return LayoutBuilder(
        builder: (_, box) {
          final narrow = box.maxWidth < 620;
          final field = _SearchField(
            initial: searchText,
            onChanged: (v) => ctrl.search.value = v,
          );
          final chips = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (u != null)
                InputChip(
                  label: Text('Urgency: ${u.label}'),
                  onDeleted: () => ctrl.urgencyFilter.value = null,
                  deleteButtonTooltipMessage: 'Remove urgency filter',
                  labelStyle: AppText.label(
                    size: 12,
                  ).copyWith(color: _urgencyColor(u)),
                  side: BorderSide(
                    color: _urgencyColor(u).withValues(alpha: 0.5),
                  ),
                ),
              if (hasFilters) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: ctrl.clearFilters,
                  child: const Text('Clear filters'),
                ),
              ],
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field,
                if (hasFilters) ...[const SizedBox(height: 8), chips],
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: 12),
              chips,
              if (!hasFilters)
                Text(
                  'Newest and most urgent first',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
            ],
          );
        },
      );
    });
  }

  // ── 5. THE LIST ────────────────────────────────────────────────────────
  Widget _list(BuildContext context) {
    return Obx(() {
      final tab = ctrl.tab.value;
      final items = ctrl.visibleItems;
      final unfiltered = ctrl.itemsFor(tab);

      if (ctrl.anyLoading && ctrl.allItems.isEmpty) {
        return _loading(context);
      }
      if (tab == OpsTab.resolved &&
          !ctrl.historyLoaded.value &&
          items.isEmpty &&
          !ctrl.historyError.value) {
        return _loading(context);
      }
      if (items.isEmpty) {
        if (unfiltered.isNotEmpty || ctrl.hasActiveFilters) {
          return _emptyState(
            context,
            icon: Icons.filter_alt_off_outlined,
            title: 'No items match these filters',
            body:
                'There ${unfiltered.length == 1 ? 'is' : 'are'} ${unfiltered.length} item${unfiltered.length == 1 ? '' : 's'} under "${tab.label}" — none match your search or urgency filter.',
            action: TextButton(
              onPressed: ctrl.clearFilters,
              child: const Text('Clear filters'),
            ),
          );
        }
        return switch (tab) {
          OpsTab.attention => _emptyState(
            context,
            icon: Icons.check_circle_outline,
            title: "You're all caught up",
            body:
                'Nothing needs your attention right now. New problems '
                'appear here automatically.',
            color: _cClear,
          ),
          OpsTab.inProgress => _emptyState(
            context,
            icon: Icons.hourglass_empty,
            title: 'Nothing in progress',
            body:
                'Items you mark as "in progress" wait here until you '
                'resolve them.',
          ),
          OpsTab.resolved => _emptyState(
            context,
            icon: Icons.history,
            title: 'Nothing resolved in the last 30 days',
            body: 'Items you mark as resolved are kept here for 30 days.',
          ),
          OpsTab.information => _emptyState(
            context,
            icon: Icons.info_outline,
            title: 'No information items',
            body:
                'Events that are worth knowing but need no action appear '
                'here.',
          ),
        };
      }
      return Column(
        children: [
          for (final item in items) ...[
            _OpsItemCard(
              item: item,
              ctrl: ctrl,
              onNavigate: _go,
              onResolve: (it) => _resolveFlow(context, it),
              onReopen: (it) => _reopenFlow(context, it),
              onReapply: (it) => _reapplyFlow(context, it),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    });
  }

  Widget _loading(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        for (int i = 0; i < 3; i++) ...[
          Container(
            height: 92,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.cardR,
              border: Border.all(color: p.border),
            ),
            alignment: Alignment.center,
            child: i == 1
                ? Semantics(
                    label: 'Loading',
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _emptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    Widget? action,
    Color? color,
  }) {
    final p = context.palette;
    final c = color ?? p.textMuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Container(
            height: 56,
            width: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: c),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppText.title(size: 18).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          if (action != null) ...[const SizedBox(height: 8), action],
        ],
      ),
    );
  }

  // ── ACTION FLOWS ───────────────────────────────────────────────────────
  Future<void> _resolveFlow(BuildContext context, OpsItem item) async {
    final dismiss = item.status == OpsItemStatus.informational;
    final note = await Get.dialog<String>(
      _ResolveDialog(item: item, dismiss: dismiss),
      barrierDismissible: false,
    );
    if (note == null) return;
    final r = await ctrl.resolve(item, note: note);
    _report(r);
  }

  Future<void> _reopenFlow(BuildContext context, OpsItem item) async {
    final p = context.palette;
    final ok = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: p.surface,
        title: Text(
          'Reopen this item?',
          style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
        ),
        content: Text(
          '"${item.title}" will move back to "Needs attention". Its earlier '
          'resolution note is kept.',
          style: AppText.body(size: 13).copyWith(color: p.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Reopen'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    if (ok != true) return;
    _report(await ctrl.reopen(item));
  }

  Future<void> _reapplyFlow(BuildContext context, OpsItem item) async {
    final p = context.palette;
    final org = item.affected.isEmpty ? 'this organization' : item.affected;
    final ok = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: p.surface,
        title: Text(
          'Re-apply status effects?',
          style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
        ),
        content: Text(
          'Re-runs trainer access and the owner\'s sign-in enforcement for '
          '$org\'s CURRENT status. It never changes the status, never '
          'notifies anyone and is safe to repeat. When every step succeeds, '
          'the backend resolves this incident.',
          style: AppText.body(size: 13).copyWith(color: p.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Re-apply'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    if (ok != true) return;
    _report(await ctrl.reapplyEffects(item));
  }

  static void _report(OpsActionResult r) {
    AppSnackbar.show(
      title: r.title ?? (r.ok ? 'Done' : 'Nothing was changed'),
      message: r.message,
      background: r.ok ? _cClear : _cCritical,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SEARCH FIELD (owns its controller)
// ═════════════════════════════════════════════════════════════════════════════
class _SearchField extends StatefulWidget {
  const _SearchField({required this.initial, required this.onChanged});
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void didUpdateWidget(covariant _SearchField old) {
    super.didUpdateWidget(old);
    // "Clear filters" empties the controller's search; mirror it here.
    if (widget.initial.isEmpty && _c.text.isNotEmpty) _c.clear();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        hintText: 'Search by organization, payment, reference…',
        hintStyle: AppText.body(size: 13).copyWith(color: p.textMuted),
        border: OutlineInputBorder(
          borderRadius: AppRadii.smR,
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.smR,
          borderSide: BorderSide(color: p.border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ONE ITEM
// ═════════════════════════════════════════════════════════════════════════════
class _OpsItemCard extends StatefulWidget {
  const _OpsItemCard({
    required this.item,
    required this.ctrl,
    required this.onNavigate,
    required this.onResolve,
    required this.onReopen,
    required this.onReapply,
  });

  final OpsItem item;
  final OperationsController ctrl;
  final void Function(OpsAction) onNavigate;
  final void Function(OpsItem) onResolve;
  final void Function(OpsItem) onReopen;
  final void Function(OpsItem) onReapply;

  @override
  State<_OpsItemCard> createState() => _OpsItemCardState();
}

class _OpsItemCardState extends State<_OpsItemCard> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final item = widget.item;
    final c = _urgencyColor(item.urgency);
    final now = DateTime.now();

    return Obx(() {
      final busy = widget.ctrl.busyId.value == item.id;
      final locked = widget.ctrl.busyId.value != null;
      return Semantics(
        container: true,
        label:
            '${item.urgency.label}. ${item.status.label}. ${item.title}. ${item.why} Affected: ${item.affected}. ${item.whenLabel} ${OpsTime.human(item.when, now: now)}.',
        child: Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
            boxShadow: AppShadows.card(p.isDark),
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Urgency bar — a second, colour-independent cue sits in the
                // pill beside it, so colour is never the only signal.
                Container(width: 5, color: c),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pills: urgency (icon + word) and status (word).
                        ExcludeSemantics(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _pill(
                                _urgencyIcon(item.urgency),
                                item.urgency.label,
                                c,
                              ),
                              _pill(
                                null,
                                item.status.label,
                                _statusColor(item.status),
                              ),
                              if (item.count > 1)
                                Text(
                                  '${item.count} ${item.source == OpsSource.incident ? 'occurrences' : 'records'}',
                                  style: AppText.body(
                                    size: 12,
                                  ).copyWith(color: p.textMuted),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ExcludeSemantics(
                          child: Text(
                            item.title,
                            style: AppText.cardTitle(
                              size: 15,
                            ).copyWith(color: p.textPrimary),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ExcludeSemantics(
                          child: Text(
                            item.why,
                            style: AppText.body(
                              size: 13,
                            ).copyWith(color: p.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ExcludeSemantics(
                          child: Wrap(
                            spacing: 18,
                            runSpacing: 4,
                            children: [
                              _meta(
                                context,
                                Icons.business_outlined,
                                'Affected',
                                item.affected.isEmpty ? '—' : item.affected,
                              ),
                              Tooltip(
                                message: OpsTime.exact(item.when),
                                child: _meta(
                                  context,
                                  Icons.schedule,
                                  item.whenLabel,
                                  OpsTime.human(item.when, now: now),
                                ),
                              ),
                              if (item.status == OpsItemStatus.resolved &&
                                  item.resolutionNote.isNotEmpty)
                                _meta(
                                  context,
                                  Icons.notes_outlined,
                                  'Resolution',
                                  item.resolutionNote,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Actions.
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              _actionButton(
                                item.primary,
                                item,
                                primary: true,
                                locked: locked,
                              ),
                            if (!busy)
                              for (final a in item.secondary)
                                _actionButton(
                                  a,
                                  item,
                                  primary: false,
                                  locked: locked,
                                ),
                            if (item.technical.isNotEmpty)
                              TextButton.icon(
                                onPressed: () =>
                                    setState(() => _details = !_details),
                                icon: Icon(
                                  _details
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  size: 16,
                                ),
                                label: Text(
                                  _details
                                      ? 'Hide technical details'
                                      : 'Technical details',
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: p.textMuted,
                                ),
                              ),
                          ],
                        ),
                        if (_details && item.technical.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: p.surfaceAlt,
                              borderRadius: AppRadii.smR,
                              border: Border.all(color: p.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'For troubleshooting — share these with support or engineering.',
                                  style: AppText.body(
                                    size: 11,
                                  ).copyWith(color: p.textMuted),
                                ),
                                const SizedBox(height: 6),
                                for (final e in item.technical)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 150,
                                          child: Text(
                                            e.key,
                                            style: AppText.label(
                                              size: 11,
                                            ).copyWith(color: p.textMuted),
                                          ),
                                        ),
                                        Expanded(
                                          child: SelectableText(
                                            e.value,
                                            style: AppText.body(
                                              size: 12,
                                            ).copyWith(color: p.textPrimary),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _actionButton(
    OpsAction a,
    OpsItem item, {
    required bool primary,
    required bool locked,
  }) {
    final isWrite = a.isWrite;
    final VoidCallback? onPressed = (isWrite && locked)
        ? null
        : () {
            switch (a.kind) {
              case OpsActionKind.navigate:
                widget.onNavigate(a);
              case OpsActionKind.acknowledge:
                widget.ctrl.acknowledge(item).then(OperationsScreen._report);
              case OpsActionKind.resolve:
                widget.onResolve(item);
              case OpsActionKind.reopen:
                widget.onReopen(item);
              case OpsActionKind.retry:
                widget.ctrl.retryTelemetry();
              case OpsActionKind.reapplyEffects:
                widget.onReapply(item);
            }
          };
    final label = Text(a.label);
    final semanticsLabel = '${a.label}: ${item.title}';
    // MergeSemantics: label and the button's tap action become one node, so a
    // screen reader announces "Mark resolved: <what>" on the thing it presses.
    return MergeSemantics(
      child: Semantics(
        label: semanticsLabel,
        child: primary
            ? FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: a.kind == OpsActionKind.reopen
                      ? _cProgress
                      : _urgencyColor(item.urgency),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                child: ExcludeSemantics(child: label),
              )
            : OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                child: ExcludeSemantics(child: label),
              ),
      ),
    );
  }

  Widget _pill(IconData? icon, String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
        ],
        Text(text, style: AppText.label(size: 11).copyWith(color: c)),
      ],
    ),
  );

  Widget _meta(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: p.textMuted),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: AppText.label(size: 12).copyWith(color: p.textMuted),
        ),
        // Flexible inside a min-width Row: the Wrap above bounds the run, so a
        // long organization name ellipsizes instead of overflowing a phone.
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(size: 12).copyWith(color: p.textPrimary),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// RESOLVE / DISMISS DIALOG
// ═════════════════════════════════════════════════════════════════════════════
/// Owns its TextEditingController so disposal happens in a State that has
/// genuinely left the tree — never via `.whenComplete` on the dialog future
/// (a crash this console has shipped twice).
class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({required this.item, required this.dismiss});
  final OpsItem item;
  final bool dismiss;

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  late final TextEditingController _note = TextEditingController(
    text: widget.dismiss ? 'Reviewed — no action needed.' : '',
  );
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final item = widget.item;
    return AlertDialog(
      backgroundColor: p.surface,
      title: Text(
        widget.dismiss ? 'Dismiss this item?' : 'Mark as resolved?',
        style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: AppText.label(size: 13).copyWith(color: p.textPrimary),
            ),
            if (item.affected.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Affected: ${item.affected}',
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              widget.dismiss
                  ? 'This moves the item to "Resolved". It does not change any '
                        'payment or organization — it only records that you '
                        'reviewed it.'
                  : 'This moves the item to "Resolved" and removes it from '
                        '"Needs attention". It does not fix the underlying '
                        'problem by itself — record what was actually done so '
                        'the next person understands.',
              style: AppText.body(size: 13).copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'What was done (required)',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final n = _note.text.trim();
            if (n.isEmpty) {
              setState(() => _error = 'Write one line about what was done.');
              return;
            }
            Navigator.of(context).pop(n);
          },
          child: Text(widget.dismiss ? 'Dismiss' : 'Mark resolved'),
        ),
      ],
    );
  }
}
