// lib/screens/dash_board_responsive_screen.dart
//
// The founder's home screen. Answers, in order: what needs me (attention
// strip) → how big is the platform (KPI grid) → how is money moving (revenue
// chart + org mix) → what do I act on now (approvals, expiries, payments,
// top organizations). Every number here comes from DashboardController and
// is rendered ONLY when its source read succeeded; a failed or not-yet-loaded
// source shows a dash or an explicit error with retry, never a zero.
//
// Every KPI card and every list card is a door: tapping opens the console
// section that owns the underlying records, with the relevant filter applied
// where one exists. A dashboard number the founder cannot drill into is a
// number they have to go and find again.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/admin_controller.dart';
import '../../controllers/admin_root_controller.dart';
import '../../controllers/dashboard_controller.dart';
import '../../controllers/operations_controller.dart';
import '../../models/admin_model.dart';
import '../../widgets/page_shell.dart';

// Status palette (self-contained — consistent in light & dark).
const _cActive = Color(0xFF1A7F5A);
const _cPending = Color(0xFF3B6FD4);
const _cWarning = Color(0xFFB06A00);
const _cBlocked = Color(0xFFD4341F);
const _cOther = Color(0xFF7A7F87);

// Sidebar destination ids (AdminRootController._buildPage). These are STABLE
// IDENTIFIERS, not positions — see console_destinations.dart. Pinned by
// test/nav_reachability_test.dart so a renumbering cannot silently repoint a
// KPI card at the wrong screen.
const int opsNavIndex = 10; // Operations Center
const int _navOrganizations = 1;
const int _navTrainers = 2;
const int _navMembers = 3;
const int _navRevenue = 5;

final _inr = NumberFormat.decimalPattern('en_IN');

/// Rupees, paise-exact (receipts carry GST-inclusive / manual fractional
/// amounts; whole-rupee rounding misstated them).
String _money(double v) {
  if (!v.isFinite) return '₹—';
  final minor = (v * 100).round();
  final paise = minor.abs() % 100;
  final whole = _inr.format(minor.abs() ~/ 100);
  return '₹${minor < 0 ? '-' : ''}$whole'
      '${paise == 0 ? '' : '.${paise.toString().padLeft(2, '0')}'}';
}

String _count(double v) => _inr.format(v.round());
String _orgLabel(AdminModel a) =>
    a.organizationName.isNotEmpty ? a.organizationName : a.name;

class DashboardScreenResponsive extends StatelessWidget {
  const DashboardScreenResponsive({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DashboardController>();
    final p = context.palette;

    return PageShell(
      title: "Dashboard",
      icon: Icons.dashboard_outlined,
      trailing: _refreshAction(context, ctrl),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Platform overview",
              style: AppText.body(size: 14).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 18),

            _attentionStrip(context),

            _FadeInUp(delayMs: 0, child: _kpiGrid(context, ctrl)),
            const SizedBox(height: 22),

            _FadeInUp(delayMs: 120, child: _chartsRow(context, ctrl)),
            const SizedBox(height: 22),

            _FadeInUp(delayMs: 240, child: _insightsRow(context, ctrl)),
          ],
        ),
      ),
    );
  }

  // ── NAVIGATION ──────────────────────────────────────────────────────
  static void _go(int index) {
    if (Get.isRegistered<AdminRootController>()) {
      Get.find<AdminRootController>().changePage(index);
    }
  }

  /// Open Organizations with its status filter pre-set, so "4 pending" on the
  /// dashboard lands on the four pending rows, not on the full list.
  static void _goOrganizations({String filter = 'all'}) {
    if (Get.isRegistered<AdminController>()) {
      final admins = Get.find<AdminController>();
      admins.statusFilter.value = filter;
      admins.search.value = '';
    }
    _go(_navOrganizations);
  }

  // ── HEADER ACTION ───────────────────────────────────────────────────
  /// The two streams are live; the trainer/member headcounts are aggregate
  /// snapshots. This says when they were last counted and re-counts on demand.
  Widget _refreshAction(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return Obx(() {
      final at = ctrl.headcountsAt.value;
      final busy = ctrl.headcountsRefreshing.value;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (at != null)
            Text(
              "Headcounts as of ${DateFormat('h:mm a').format(at)}",
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          const SizedBox(width: 8),
          Tooltip(
            message: "Re-count trainers and members now",
            child: OutlinedButton.icon(
              onPressed: busy ? null : ctrl.refreshAll,
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: const Text("Refresh"),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.textSecondary,
                side: BorderSide(color: p.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  // ── ATTENTION STRIP ─────────────────────────────────────────────────
  /// The 30-second answer to "what needs me?" — a one-line summary of the
  /// Operations Center feed (which owns all the attention logic). Three
  /// states, because two of them used to look identical:
  ///   • sources still loading → nothing (a blank is not a claim)
  ///   • loaded, nothing open  → a quiet "all clear" (a positive fact)
  ///   • alerts                → the count, tap to open the feed
  Widget _attentionStrip(BuildContext context) {
    if (!Get.isRegistered<OperationsController>()) {
      return const SizedBox.shrink();
    }
    final ops = Get.find<OperationsController>();
    final p = context.palette;
    return Obx(() {
      final ready = ops.sourcesReady && ops.telemetryLoaded.value;
      final total = ops.totalCount;
      if (total == 0) {
        if (!ready) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 16, color: _cActive),
              const SizedBox(width: 8),
              Text(
                "All clear — nothing needs your attention right now",
                style: AppText.body(size: 13).copyWith(color: p.textMuted),
              ),
            ],
          ),
        );
      }
      final critical = ops.criticalCount;
      final c = critical > 0 ? _cBlocked : _cWarning;
      final message = critical > 0
          ? "$total alert${total == 1 ? '' : 's'} need${total == 1 ? 's' : ''} your attention — $critical critical"
          : "$total alert${total == 1 ? '' : 's'} need${total == 1 ? 's' : ''} your attention";
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: MergeSemantics(
          child: Semantics(
            button: true,
            label: "$message. Open Operations Center",
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AppRadii.cardR,
                onTap: () => _go(opsNavIndex),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.08),
                    borderRadius: AppRadii.cardR,
                    border: Border.all(color: c.withValues(alpha: 0.35)),
                  ),
                  child: LayoutBuilder(
                    builder: (_, box) {
                      // On a phone the trailing label ate the message itself
                      // ("7 items need yo…"); below 560px only the chevron stays.
                      final showLabel = box.maxWidth >= 560;
                      return Row(
                        children: [
                          Icon(
                            critical > 0
                                ? Icons.priority_high_rounded
                                : Icons.notifications_active_outlined,
                            size: 18,
                            color: c,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ExcludeSemantics(
                              child: Text(
                                message,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.label(
                                  size: 13,
                                ).copyWith(color: c),
                              ),
                            ),
                          ),
                          if (showLabel)
                            ExcludeSemantics(
                              child: Text(
                                "Open Operations Center",
                                style: AppText.label(
                                  size: 12,
                                ).copyWith(color: c),
                              ),
                            ),
                          Icon(Icons.chevron_right, size: 18, color: c),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  // ── KPI GRID ────────────────────────────────────────────────────────
  Widget _kpiGrid(BuildContext context, DashboardController ctrl) {
    return LayoutBuilder(
      builder: (_, box) {
        // A 232px card in a 340px column left 30% of a phone screen empty.
        final cardWidth = box.maxWidth < 520 ? box.maxWidth : 232.0;
        final prevMonth = DateFormat(
          'MMM',
        ).format(DateTime(DateTime.now().year, DateTime.now().month - 1));
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _stat(
              context,
              width: cardWidth,
              label: "Organizations",
              icon: Icons.business_outlined,
              accent: _cPending,
              value: () => ctrl.orgsTotal.toDouble(),
              fmt: _count,
              ready: () => ctrl.orgsReady,
              error: () => ctrl.orgsError.value,
              onRetry: ctrl.retryOrgs,
              onOpen: () => _goOrganizations(),
              destination: "Organizations",
            ),
            _stat(
              context,
              width: cardWidth,
              label: "Active subscriptions",
              icon: Icons.verified_outlined,
              accent: _cActive,
              value: () => ctrl.orgsSubscribed.toDouble(),
              fmt: _count,
              ready: () => ctrl.orgsReady,
              error: () => ctrl.orgsError.value,
              onRetry: ctrl.retryOrgs,
              // A paid-but-blocked or paid-but-pending org still holds a
              // subscription; say how many of the paid cannot operate.
              note: () {
                final gap = ctrl.orgsSubscribed - ctrl.orgsOperable;
                return gap > 0 ? "$gap paid but pending/blocked" : null;
              },
              onOpen: () => _goOrganizations(filter: 'active'),
              destination: "Organizations",
            ),
            _stat(
              context,
              width: cardWidth,
              label: "Trainers",
              icon: Icons.fitness_center_outlined,
              accent: const Color(0xFF6C5CE7),
              value: () => ctrl.trainersTotal.value.toDouble(),
              fmt: _count,
              ready: () => ctrl.trainersReady,
              error: () => ctrl.trainersError.value,
              onRetry: ctrl.refreshHeadcounts,
              onOpen: () => _go(_navTrainers),
              destination: "Trainers",
            ),
            _stat(
              context,
              width: cardWidth,
              label: "Members",
              icon: Icons.people_outline,
              accent: const Color(0xFF0E8FA8),
              value: () => ctrl.clientsTotal.value.toDouble(),
              fmt: _count,
              ready: () => ctrl.clientsReady,
              error: () => ctrl.clientsError.value,
              onRetry: ctrl.refreshHeadcounts,
              onOpen: () => _go(_navMembers),
              destination: "Members",
            ),
            _stat(
              context,
              width: cardWidth,
              label: "Total revenue",
              icon: Icons.account_balance_wallet_outlined,
              accent: _cWarning,
              value: () => ctrl.revenueTotal.value,
              fmt: _money,
              ready: () => ctrl.revenueReady,
              error: () => ctrl.revenueError.value,
              onRetry: ctrl.retryRevenue,
              note: () {
                final n = ctrl.paymentsUndated.value;
                // Short enough for a 232px card in the test font too.
                return n > 0
                    ? "net of refunds · $n undated"
                    : "all-time, net of refunds";
              },
              onOpen: () => _go(_navRevenue),
              destination: "Revenue",
            ),
            _stat(
              context,
              width: cardWidth,
              label: "This month so far",
              icon: Icons.trending_up,
              accent: context.palette.accent,
              value: () => ctrl.revenueThisMonth.value,
              fmt: _money,
              ready: () => ctrl.revenueReady,
              error: () => ctrl.revenueError.value,
              onRetry: ctrl.retryRevenue,
              trend: () => ctrl.revenueGrowthPct.value,
              trendTooltip: () =>
                  "vs $prevMonth (${_money(ctrl.revenuePrevMonth.value)} for the full month)",
              note: () =>
                  "vs $prevMonth ${_money(ctrl.revenuePrevMonth.value)}",
              onOpen: () => _go(_navRevenue),
              destination: "Revenue",
            ),
          ],
        );
      },
    );
  }

  Widget _stat(
    BuildContext context, {
    required double width,
    required String label,
    required IconData icon,
    required Color accent,
    required double Function() value,
    required String Function(double) fmt,
    required bool Function() ready,
    required bool Function() error,
    required VoidCallback onRetry,
    required VoidCallback onOpen,
    required String destination,
    double Function()? trend,
    String Function()? trendTooltip,
    String? Function()? note,
  }) {
    final p = context.palette;
    return Obx(() {
      final isReady = ready();
      final isError = error();
      final shown = isReady ? fmt(value()) : "—";
      final state = isError
          ? "unavailable, tap to retry"
          : isReady
          ? shown
          : "loading";
      final noteText = isReady ? note?.call() : null;
      // MergeSemantics: the label and the InkWell's tap action become ONE
      // node. Without it a screen reader announced the label on a node that
      // had no action — proven in the browser, where activating the labelled
      // node did nothing.
      return MergeSemantics(
        child: Semantics(
          button: true,
          label: "$label: $state. Opens $destination",
          child: _HoverLift(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: AppRadii.cardR,
                onTap: isError ? onRetry : onOpen,
                child: Container(
                  width: width,
                  padding: const EdgeInsets.all(18),
                  decoration: _cardDeco(p),
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: AppRadii.smR,
                              ),
                              child: Icon(icon, color: accent, size: 20),
                            ),
                            const Spacer(),
                            if (trend != null && isReady)
                              Tooltip(
                                message: trendTooltip?.call() ?? '',
                                child: _trendChip(trend()),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Until the source has loaded, a real 0 and "not yet
                        // known" are indistinguishable — show a dash.
                        isReady
                            ? _CountUp(
                                value: value(),
                                format: fmt,
                                style: AppText.title(
                                  size: 26,
                                ).copyWith(color: p.textPrimary),
                              )
                            : Text(
                                "—",
                                style: AppText.title(
                                  size: 26,
                                ).copyWith(color: p.textMuted),
                              ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: AppText.body(
                            size: 13,
                          ).copyWith(color: p.textMuted),
                        ),
                        if (isError)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  size: 13,
                                  color: _cBlocked,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    "Couldn't load · tap to retry",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.label(
                                      size: 11,
                                    ).copyWith(color: _cBlocked),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (noteText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              noteText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(
                                size: 11,
                              ).copyWith(color: p.textMuted),
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
    });
  }

  Widget _trendChip(double t) {
    final up = t >= 0;
    final c = up ? _cActive : _cBlocked;
    return Row(
      children: [
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 13,
          color: c,
        ),
        const SizedBox(width: 2),
        Text(
          "${t.abs().toStringAsFixed(0)}%",
          style: AppText.label(size: 12).copyWith(color: c),
        ),
      ],
    );
  }

  // ── CHARTS ROW ──────────────────────────────────────────────────────
  Widget _chartsRow(BuildContext context, DashboardController ctrl) {
    return LayoutBuilder(
      builder: (_, box) {
        final wide = box.maxWidth > 1000;
        final revenue = _revenueCard(context, ctrl);
        final donut = _orgDonutCard(context, ctrl);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: revenue),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: donut),
            ],
          );
        }
        return Column(children: [revenue, const SizedBox(height: 16), donut]);
      },
    );
  }

  Widget _revenueCard(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return _sectionCard(
      context,
      title: "Revenue",
      subtitle: "Net, last 6 months",
      // The figure beside a six-month chart is the six-month sum. The
      // all-time total has its own KPI card and used to sit here too, which
      // read as "the chart adds up to this" when it did not.
      trailing: Obx(
        () => ctrl.revenueReady
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(ctrl.revenueWindow.value),
                    style: AppText.title(
                      size: 20,
                    ).copyWith(color: p.textPrimary),
                  ),
                  Text(
                    "6-month total",
                    style: AppText.body(size: 11).copyWith(color: p.textMuted),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
      onOpen: () => _go(_navRevenue),
      openLabel: "Open Revenue",
      child: Obx(() {
        if (!ctrl.revenueLoaded.value) return _loadingBox(180);
        if (ctrl.revenueError.value) {
          return _errorState(context, ctrl.retryRevenue);
        }
        if (ctrl.revenueWindow.value <= 0) {
          return _empty(
            context,
            Icons.show_chart,
            "No revenue in this window",
            "Payments from the last six months chart here.",
          );
        }
        return Semantics(
          label:
              "Net revenue by month: ${ctrl.revenueByMonth.map((m) => '${m.label} ${_money(m.value)}').join(', ')}",
          child: SizedBox(
            height: 220,
            child: _RevenueChart(
              data: ctrl.revenueByMonth.toList(),
              accent: p.accent,
              grid: p.border,
              label: p.textMuted,
            ),
          ),
        );
      }),
    );
  }

  Widget _orgDonutCard(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return _sectionCard(
      context,
      title: "Organizations",
      subtitle: "By moderation status",
      onOpen: () => _goOrganizations(),
      openLabel: "Open Organizations",
      child: Obx(() {
        if (!ctrl.orgsLoaded.value) return _loadingBox(180);
        if (ctrl.orgsError.value) {
          return _errorState(context, ctrl.retryOrgs);
        }
        if (ctrl.orgsTotal == 0) {
          return _empty(
            context,
            Icons.business,
            "No organizations yet",
            "Gyms that sign up will show here.",
          );
        }
        final s = ctrl.orgStats.value;
        return Column(
          children: [
            Semantics(
              label:
                  "${s.total} organizations: ${s.active} active, ${s.pending} pending, ${s.warning} warning, ${s.blocked} blocked${s.other > 0 ? ', ${s.other} other' : ''}",
              child: SizedBox(
                height: 170,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _StatusDonut(
                      active: s.active,
                      pending: s.pending,
                      warning: s.warning,
                      blocked: s.blocked,
                      other: s.other,
                    ),
                    ExcludeSemantics(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "${s.total}",
                            style: AppText.title(
                              size: 28,
                            ).copyWith(color: p.textPrimary),
                          ),
                          Text(
                            "total",
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _legend(
                  context,
                  _cActive,
                  "Active",
                  s.active,
                  onTap: () => _goOrganizations(filter: 'active'),
                ),
                _legend(
                  context,
                  _cPending,
                  "Pending",
                  s.pending,
                  onTap: () => _goOrganizations(filter: 'pending'),
                ),
                _legend(
                  context,
                  _cWarning,
                  "Warning",
                  s.warning,
                  onTap: () => _goOrganizations(filter: 'warning'),
                ),
                _legend(
                  context,
                  _cBlocked,
                  "Blocked",
                  s.blocked,
                  onTap: () => _goOrganizations(filter: 'blocked'),
                ),
                // Statuses the console does not model still exist in the
                // data; a slice that says so beats a total the legend cannot
                // reach.
                if (s.other > 0)
                  Tooltip(
                    message:
                        "Organizations whose status is none of the four above — check them in Organizations",
                    child: _legend(
                      context,
                      _cOther,
                      "Other",
                      s.other,
                      onTap: () => _goOrganizations(),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _legend(
    BuildContext context,
    Color c,
    String label,
    int n, {
    VoidCallback? onTap,
  }) {
    final p = context.palette;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          "$label  ",
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        Text(
          "$n",
          style: AppText.label(size: 12).copyWith(color: p.textPrimary),
        ),
      ],
    );
    if (onTap == null) return row;
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: "$label $n. Opens Organizations filtered to $label",
        child: InkWell(
          borderRadius: AppRadii.smR,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: ExcludeSemantics(child: row),
          ),
        ),
      ),
    );
  }

  // ── INSIGHTS ROW ────────────────────────────────────────────────────
  Widget _insightsRow(BuildContext context, DashboardController ctrl) {
    return LayoutBuilder(
      builder: (_, box) {
        final cards = [
          _pendingCard(context, ctrl),
          _expiringCard(context, ctrl),
          _paymentsCard(context, ctrl),
          _topOrgsCard(context, ctrl),
        ];
        Widget row(List<Widget> children) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: children[i]),
              ],
            ],
          ),
        );
        // Large monitor: all four abreast. Desktop: 2×2. Narrow: stacked.
        if (box.maxWidth > 1500) return row(cards);
        if (box.maxWidth > 1000) {
          return Column(
            children: [
              row(cards.sublist(0, 2)),
              const SizedBox(height: 16),
              row(cards.sublist(2, 4)),
            ],
          );
        }
        return Column(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              cards[i],
            ],
          ],
        );
      },
    );
  }

  Widget _topOrgsCard(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return _sectionCard(
      context,
      title: "Top organizations",
      subtitle: "By all-time net revenue",
      onOpen: () => _go(_navRevenue),
      openLabel: "Open Revenue",
      child: Obx(() {
        if (!ctrl.revenueLoaded.value) return _loadingBox(120);
        if (ctrl.revenueError.value) {
          return _errorState(context, ctrl.retryRevenue);
        }
        final list = ctrl.topOrgs;
        if (list.isEmpty) {
          return _empty(
            context,
            Icons.leaderboard_outlined,
            "No revenue yet",
            "Top-earning gyms rank here.",
          );
        }
        final maxRevenue = list.first.revenue;
        return Column(
          children: [
            for (int i = 0; i < list.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        "${i + 1}",
                        style: AppText.label(
                          size: 12,
                        ).copyWith(color: p.textMuted),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          list[i].isUnknown
                              // A receipt whose organization has no admins
                              // doc any more. Say so — "Organization" read as
                              // a gym called Organization.
                              ? Tooltip(
                                  message:
                                      "No organization record for id ${list[i].orgId}",
                                  child: Text(
                                    "Unknown organization",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.label(size: 13).copyWith(
                                      color: p.textMuted,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                )
                              : Text(
                                  list[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppText.label(
                                    size: 13,
                                  ).copyWith(color: p.textPrimary),
                                ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: maxRevenue <= 0
                                  ? 0
                                  : (list[i].revenue / maxRevenue).clamp(
                                      0.0,
                                      1.0,
                                    ),
                              minHeight: 4,
                              backgroundColor: p.border,
                              valueColor: AlwaysStoppedAnimation(p.accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _money(list[i].revenue),
                      style: AppText.label(
                        size: 13,
                      ).copyWith(color: p.textPrimary),
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }

  /// Confirmation before the destructive path: reject = `blocked` via the
  /// setAdminStatus CF, which also disables the org's sign-in.
  void _confirmReject(
    BuildContext context,
    DashboardController ctrl,
    String docId,
    String orgName,
  ) {
    final p = context.palette;
    Get.dialog(
      AlertDialog(
        backgroundColor: p.surface,
        title: Text(
          "Reject $orgName?",
          style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
        ),
        content: Text(
          "The organization is blocked and its owner can no longer sign in. "
          "You can reverse this later from the Organizations screen.",
          style: AppText.body(size: 13).copyWith(color: p.textSecondary),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Get.back();
              ctrl.rejectOrg(docId);
            },
            style: TextButton.styleFrom(foregroundColor: _cBlocked),
            child: const Text("Reject organization"),
          ),
        ],
      ),
    );
  }

  static const int _listCap = 5;

  Widget _pendingCard(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return _sectionCard(
      context,
      title: "Pending approvals",
      trailing: Obx(() {
        final n = ctrl.orgsReady ? ctrl.pendingApprovals.length : 0;
        if (n <= _listCap) return const SizedBox.shrink();
        return _viewAll(
          context,
          "View all $n",
          () => _goOrganizations(filter: 'pending'),
        );
      }),
      onOpen: () => _goOrganizations(filter: 'pending'),
      openLabel: "Open Organizations · pending",
      child: Obx(() {
        if (ctrl.orgsError.value) {
          return _errorState(context, ctrl.retryOrgs);
        }
        // An empty list before the first snapshot is not "All clear" — it is
        // "not counted yet". Same rule the KPI grid states above.
        if (!ctrl.orgsLoaded.value) {
          return _loadingState(context);
        }
        final list = ctrl.pendingApprovals;
        if (list.isEmpty) {
          return _empty(
            context,
            Icons.inbox_outlined,
            "All clear",
            "No gyms waiting for approval.",
          );
        }
        final busyId = ctrl.moderatingDocId.value;
        return Column(
          children: list.take(_listCap).map((a) {
            final name = _orgLabel(a);
            final busy = busyId == a.docId;
            final locked = busyId != null;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _avatar(context, name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(
                            size: 13,
                          ).copyWith(color: p.textPrimary),
                        ),
                        Text(
                          "${a.email} · signed up ${DateFormat('d MMM').format(a.createdAt)}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            size: 11,
                          ).copyWith(color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else ...[
                    Semantics(
                      label: "Approve $name",
                      child: TextButton(
                        onPressed: locked
                            ? null
                            : () => ctrl.approveOrg(a.docId),
                        style: TextButton.styleFrom(
                          foregroundColor: _cActive,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                        ),
                        child: const ExcludeSemantics(child: Text("Approve")),
                      ),
                    ),
                    Semantics(
                      label: "Reject $name",
                      child: TextButton(
                        onPressed: locked
                            ? null
                            : () =>
                                  _confirmReject(context, ctrl, a.docId, name),
                        style: TextButton.styleFrom(
                          foregroundColor: _cBlocked,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                        ),
                        child: const ExcludeSemantics(child: Text("Reject")),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  Widget _expiringCard(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return _sectionCard(
      context,
      title: "Expiring soon",
      subtitle: "Paid plans ending within 7 days",
      trailing: Obx(() {
        final n = ctrl.orgsReady ? ctrl.expiring.length : 0;
        if (n <= _listCap) return const SizedBox.shrink();
        return _viewAll(
          context,
          "View all $n",
          () => _goOrganizations(filter: 'active'),
        );
      }),
      onOpen: () => _goOrganizations(filter: 'active'),
      openLabel: "Open Organizations",
      child: Obx(() {
        // "Nothing due" is a claim about the organizations stream; a denied
        // read must never render it.
        if (ctrl.orgsError.value) {
          return _errorState(context, ctrl.retryOrgs);
        }
        if (!ctrl.orgsLoaded.value) {
          return _loadingState(context);
        }
        final list = ctrl.expiring;
        if (list.isEmpty) {
          return _empty(
            context,
            Icons.event_available_outlined,
            "Nothing due",
            "No subscriptions expiring this week.",
          );
        }
        return Column(
          children: list.take(_listCap).map((e) {
            final a = e.org;
            final name = _orgLabel(a);
            // Past-due = expired on the calendar but still flagged active
            // (the hourly backend sweep has not run yet). More urgent than
            // "3d", so it is red and sorts first.
            final past = e.isPastDue;
            final chipColor = past ? _cBlocked : _cWarning;
            final chipText = past
                ? "expired"
                : e.daysLeft <= 0
                ? "today"
                : "${e.daysLeft}d";
            final expiryText = a.planExpiry == null
                ? ''
                : DateFormat('d MMM').format(a.planExpiry!);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _avatar(context, name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(
                            size: 13,
                          ).copyWith(color: p.textPrimary),
                        ),
                        Text(
                          "${a.planName ?? 'Plan'}${expiryText.isEmpty ? '' : ' · ends $expiryText'}${past ? ' · still marked active' : ''}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            size: 11,
                          ).copyWith(color: p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: past
                        ? "Plan expiry has passed but isSubscriptionActive is still true — the hourly expiry sweep has not run yet"
                        : "Days until the plan expires",
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: 0.12),
                        borderRadius: AppRadii.smR,
                      ),
                      child: Text(
                        chipText,
                        style: AppText.label(
                          size: 11,
                        ).copyWith(color: chipColor),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  Widget _paymentsCard(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return _sectionCard(
      context,
      title: "Recent payments",
      subtitle: "Subscription receipts, newest first",
      onOpen: () => _go(_navRevenue),
      openLabel: "Open Revenue",
      child: Obx(() {
        if (!ctrl.revenueLoaded.value) return _loadingBox(120);
        if (ctrl.revenueError.value) {
          return _errorState(context, ctrl.retryRevenue);
        }
        final list = ctrl.recentPayments;
        if (list.isEmpty) {
          return _empty(
            context,
            Icons.receipt_long_outlined,
            "No payments yet",
            "Subscription payments will list here.",
          );
        }
        return Column(
          children: list.take(_listCap).map((e) {
            final flagged = e.isRefunded || !e.captureVerified;
            final iconColor = e.isFullyRefunded
                ? _cBlocked
                : flagged
                ? _cWarning
                : _cActive;
            final icon = e.isRefunded
                ? Icons.undo
                : !e.captureVerified
                ? Icons.help_outline
                : Icons.south_west;
            final who = e.orgName.isNotEmpty
                ? e.orgName
                : "Unknown organization";
            final when = e.date == null
                ? "date not recorded"
                : DateFormat('d MMM, h:mm a').format(e.date!);
            final tags = <String>[
              if (e.isFullyRefunded)
                "fully refunded"
              else if (e.isRefunded)
                "refunded ${_money(e.refunded)}",
              // Only ONLINE receipts can be "capture unverified": a manual
              // receipt is unverified by definition, not by doubt.
              if (!e.captureVerified) "capture unverified",
              if (e.recordedManually) "recorded by the team",
            ];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Tooltip(
                    message: !e.captureVerified
                        ? "The gateway did not confirm this capture at activation — verify the money actually arrived"
                        : e.isRefunded
                        ? "Refunded; the amount shown is what was kept"
                        : e.recordedManually
                        ? "Recorded by the team — collected outside the platform; the reference is the evidence"
                        : "Captured payment",
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: AppRadii.smR,
                      ),
                      child: Icon(icon, size: 15, color: iconColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "$who · ${e.plan.isEmpty ? "Subscription" : e.plan}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(
                            size: 13,
                          ).copyWith(color: p.textPrimary),
                        ),
                        Text(
                          tags.isEmpty ? when : "$when · ${tags.join(' · ')}",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(
                            size: 11,
                          ).copyWith(color: flagged ? iconColor : p.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _money(e.net),
                    style: AppText.label(size: 13).copyWith(
                      color: p.textPrimary,
                      decoration: e.isFullyRefunded
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  // ── SHARED PIECES ───────────────────────────────────────────────────
  Widget _viewAll(BuildContext context, String label, VoidCallback onTap) {
    final p = context.palette;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: AppText.label(size: 12)),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onOpen,
    String? openLabel,
    required Widget child,
  }) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(p),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.cardTitle(
                        size: 15,
                      ).copyWith(color: p.textPrimary),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: AppText.body(
                          size: 12,
                        ).copyWith(color: p.textMuted),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
              if (onOpen != null)
                Tooltip(
                  message: openLabel ?? "Open",
                  child: IconButton(
                    onPressed: onOpen,
                    icon: Icon(
                      Icons.arrow_outward,
                      size: 16,
                      color: p.textMuted,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: null,
                    // The visible tooltip carries the label; this is what a
                    // screen reader announces.
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(foregroundColor: p.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, String name) {
    final p = context.palette;
    final letter = name.trim().isEmpty ? "?" : name.trim()[0].toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Text(
          letter,
          style: AppText.label(size: 14).copyWith(color: p.accent),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, IconData icon, String title, String sub) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(icon, size: 30, color: p.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(
            title,
            style: AppText.label(size: 13).copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }

  /// Shown while a source's FIRST read is still in flight, so an empty list
  /// cannot be reported as "All clear" or "Nothing due" before anything has
  /// been counted.
  Widget _loadingState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Semantics(
          label: "Loading",
          child: const CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }

  /// A failed stream renders as an explicit error with retry — never as a
  /// misleading empty state.
  Widget _errorState(BuildContext context, VoidCallback onRetry) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 30,
            color: _cBlocked.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          Text(
            "Couldn't load this data",
            style: AppText.label(size: 13).copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("Retry"),
          ),
        ],
      ),
    );
  }

  Widget _loadingBox(double h) => SizedBox(
    height: h,
    child: Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: Semantics(
          label: "Loading",
          child: const CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    ),
  );

  BoxDecoration _cardDeco(AppPalette p) => BoxDecoration(
    color: p.surface,
    borderRadius: AppRadii.cardR,
    border: Border.all(color: p.border),
    boxShadow: AppShadows.card(p.isDark),
  );
}

// ============================================================================
// REVENUE AREA CHART (fl_chart)
// ============================================================================
class _RevenueChart extends StatelessWidget {
  final List<MonthRevenue> data;
  final Color accent;
  final Color grid;
  final Color label;
  const _RevenueChart({
    required this.data,
    required this.accent,
    required this.grid,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = data.fold<double>(0, (m, e) => e.value > m ? e.value : m);
    final maxY = maxVal <= 0 ? 100.0 : maxVal * 1.25;
    final interval = maxY / 4;
    final spots = [
      for (int i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].value),
    ];
    final small = AppText.body(size: 11).copyWith(color: label);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    '${data[s.x.round().clamp(0, data.length - 1)].label}  ${_money(s.y)}',
                    AppText.label(size: 12).copyWith(color: Colors.white),
                  ),
                )
                .toList(),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: grid, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              interval: interval,
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(_compact(v), style: small),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, m) {
                final i = v.round();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(data[i].label, style: small),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: accent,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.28),
                  accent.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Indian short scale: ₹1.5L, ₹12k — the founder's own reading of rupees.
  static String _compact(double v) {
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
    return '₹${v.toInt()}';
  }
}

// ============================================================================
// ORG STATUS DONUT (fl_chart)
// ============================================================================
class _StatusDonut extends StatelessWidget {
  final int active, pending, warning, blocked, other;
  const _StatusDonut({
    required this.active,
    required this.pending,
    required this.warning,
    required this.blocked,
    this.other = 0,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[];

    void add(int n, Color c) {
      if (n <= 0) return;
      sections.add(
        PieChartSectionData(
          value: n.toDouble(),
          color: c,
          radius: 18,
          showTitle: false,
        ),
      );
    }

    add(active, _cActive);
    add(pending, _cPending);
    add(warning, _cWarning);
    add(blocked, _cBlocked);
    add(other, _cOther);

    return PieChart(
      PieChartData(
        sectionsSpace: sections.length > 1 ? 3 : 0,
        centerSpaceRadius: 54,
        startDegreeOffset: -90,
        sections: sections.isEmpty
            ? [
                PieChartSectionData(
                  value: 1,
                  color: context.palette.border,
                  radius: 18,
                  showTitle: false,
                ),
              ]
            : sections,
      ),
    );
  }
}

// ============================================================================
// COUNT-UP NUMBER
// ============================================================================
class _CountUp extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  const _CountUp({
    required this.value,
    required this.format,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(format(v), style: style),
    );
  }
}

// ============================================================================
// ENTRANCE ANIMATION (fade + slide up, once)
// ============================================================================
class _FadeInUp extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _FadeInUp({required this.child, this.delayMs = 0});

  @override
  State<_FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<_FadeInUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - _a.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

// ============================================================================
// HOVER LIFT (web pointer feedback)
// ============================================================================
class _HoverLift extends StatefulWidget {
  final Widget child;
  const _HoverLift({required this.child});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: widget.child,
      ),
    );
  }
}
