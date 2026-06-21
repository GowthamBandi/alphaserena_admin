import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/dashboard_controller.dart';
import '../../widgets/page_shell.dart';

// Status palette (self-contained — consistent in light & dark).
const _cActive = Color(0xFF1A7F5A);
const _cPending = Color(0xFF3B6FD4);
const _cWarning = Color(0xFFB06A00);
const _cBlocked = Color(0xFFD4341F);

final _inr = NumberFormat.decimalPattern('en_IN');
String _money(double v) => '₹${_inr.format(v.round())}';
String _count(double v) => _inr.format(v.round());

class DashboardScreenResponsive extends StatelessWidget {
  const DashboardScreenResponsive({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DashboardController>();
    final p = context.palette;

    return PageShell(
      title: "Dashboard",
      icon: Icons.dashboard_outlined,
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

  // ── KPI GRID ────────────────────────────────────────────────────────
  Widget _kpiGrid(BuildContext context, DashboardController ctrl) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _stat(context,
            label: "Organizations",
            icon: Icons.business_outlined,
            accent: _cPending,
            value: () => ctrl.orgsTotal.value.toDouble(),
            fmt: _count),
        _stat(context,
            label: "Active subscriptions",
            icon: Icons.verified_outlined,
            accent: _cActive,
            value: () => ctrl.orgsSubscribed.value.toDouble(),
            fmt: _count),
        _stat(context,
            label: "Trainers",
            icon: Icons.fitness_center_outlined,
            accent: const Color(0xFF6C5CE7),
            value: () => ctrl.trainersTotal.value.toDouble(),
            fmt: _count),
        _stat(context,
            label: "Members",
            icon: Icons.people_outline,
            accent: const Color(0xFF0E8FA8),
            value: () => ctrl.clientsTotal.value.toDouble(),
            fmt: _count),
        _stat(context,
            label: "Total revenue",
            icon: Icons.account_balance_wallet_outlined,
            accent: _cWarning,
            value: () => ctrl.revenueTotal.value,
            fmt: _money),
        _stat(context,
            label: "This month",
            icon: Icons.trending_up,
            accent: context.palette.accent,
            value: () => ctrl.revenueThisMonth.value,
            fmt: _money,
            trend: () => ctrl.revenueGrowthPct.value),
      ],
    );
  }

  Widget _stat(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color accent,
    required double Function() value,
    required String Function(double) fmt,
    double Function()? trend,
  }) {
    final p = context.palette;
    return _HoverLift(
      child: Container(
        width: 232,
        padding: const EdgeInsets.all(18),
        decoration: _cardDeco(p),
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
                if (trend != null)
                  Obx(() {
                    final t = trend();
                    final up = t >= 0;
                    final c = up ? _cActive : _cBlocked;
                    return Row(children: [
                      Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                          size: 13, color: c),
                      const SizedBox(width: 2),
                      Text("${t.abs().toStringAsFixed(0)}%",
                          style: AppText.label(size: 12).copyWith(color: c)),
                    ]);
                  }),
              ],
            ),
            const SizedBox(height: 16),
            Obx(() => _CountUp(
                  value: value(),
                  format: fmt,
                  style: AppText.title(size: 26).copyWith(color: p.textPrimary),
                )),
            const SizedBox(height: 4),
            Text(label,
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          ],
        ),
      ),
    );
  }

  // ── CHARTS ROW ──────────────────────────────────────────────────────
  Widget _chartsRow(BuildContext context, DashboardController ctrl) {
    return LayoutBuilder(builder: (_, box) {
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
    });
  }

  Widget _revenueCard(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return _sectionCard(
      context,
      title: "Revenue",
      subtitle: "Last 6 months",
      trailing: Obx(() => Text(_money(ctrl.revenueTotal.value),
          style: AppText.title(size: 20).copyWith(color: p.textPrimary))),
      child: Obx(() {
        if (!ctrl.revenueLoaded.value) return _loadingBox(180);
        if (ctrl.revenueTotal.value <= 0) {
          return _empty(context, Icons.show_chart,
              "No revenue yet", "Payments appear here once gyms subscribe.");
        }
        return SizedBox(
          height: 220,
          child: _RevenueChart(
            data: ctrl.revenueByMonth.toList(),
            accent: p.accent,
            grid: p.border,
            label: p.textMuted,
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
      subtitle: "By status",
      child: Obx(() {
        if (!ctrl.orgsLoaded.value) return _loadingBox(180);
        if (ctrl.orgsTotal.value == 0) {
          return _empty(context, Icons.business,
              "No organizations yet", "Gyms that sign up will show here.");
        }
        return Column(
          children: [
            SizedBox(
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _StatusDonut(
                    active: ctrl.orgsActive.value,
                    pending: ctrl.orgsPending.value,
                    warning: ctrl.orgsWarning.value,
                    blocked: ctrl.orgsBlocked.value,
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("${ctrl.orgsTotal.value}",
                          style: AppText.title(size: 28)
                              .copyWith(color: p.textPrimary)),
                      Text("total",
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _legend(context, _cActive, "Active", ctrl.orgsActive.value),
                _legend(context, _cPending, "Pending", ctrl.orgsPending.value),
                _legend(context, _cWarning, "Warning", ctrl.orgsWarning.value),
                _legend(context, _cBlocked, "Blocked", ctrl.orgsBlocked.value),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _legend(BuildContext context, Color c, String label, int n) {
    final p = context.palette;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text("$label  ",
          style: AppText.body(size: 12).copyWith(color: p.textMuted)),
      Text("$n", style: AppText.label(size: 12).copyWith(color: p.textPrimary)),
    ]);
  }

  // ── INSIGHTS ROW ────────────────────────────────────────────────────
  Widget _insightsRow(BuildContext context, DashboardController ctrl) {
    return LayoutBuilder(builder: (_, box) {
      final pending = _pendingCard(context, ctrl);
      final expiring = _expiringCard(context, ctrl);
      final payments = _paymentsCard(context, ctrl);
      if (box.maxWidth > 1000) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: pending),
              const SizedBox(width: 16),
              Expanded(child: expiring),
              const SizedBox(width: 16),
              Expanded(child: payments),
            ],
          ),
        );
      }
      return Column(children: [
        pending,
        const SizedBox(height: 16),
        expiring,
        const SizedBox(height: 16),
        payments,
      ]);
    });
  }

  Widget _pendingCard(BuildContext context, DashboardController ctrl) {
    final p = context.palette;
    return _sectionCard(
      context,
      title: "Pending approvals",
      child: Obx(() {
        final list = ctrl.pendingApprovals;
        if (list.isEmpty) {
          return _empty(context, Icons.inbox_outlined, "All clear",
              "No gyms waiting for approval.");
        }
        return Column(
          children: list.take(5).map((a) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _avatar(context, a.organizationName.isNotEmpty
                      ? a.organizationName
                      : a.name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            a.organizationName.isNotEmpty
                                ? a.organizationName
                                : a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label(size: 13)
                                .copyWith(color: p.textPrimary)),
                        Text(a.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(size: 11)
                                .copyWith(color: p.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => ctrl.approveOrg(a.docId),
                    style: TextButton.styleFrom(
                      foregroundColor: _cActive,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    child: const Text("Approve"),
                  ),
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
      child: Obx(() {
        final list = ctrl.expiringSoon;
        if (list.isEmpty) {
          return _empty(context, Icons.event_available_outlined, "Nothing due",
              "No subscriptions expiring this week.");
        }
        final now = DateTime.now();
        return Column(
          children: list.take(5).map((a) {
            final days = a.planExpiry == null
                ? 0
                : a.planExpiry!.difference(now).inDays;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  _avatar(context, a.organizationName.isNotEmpty
                      ? a.organizationName
                      : a.name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        a.organizationName.isNotEmpty
                            ? a.organizationName
                            : a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label(size: 13)
                            .copyWith(color: p.textPrimary)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _cWarning.withValues(alpha: 0.12),
                      borderRadius: AppRadii.smR,
                    ),
                    child: Text(days <= 0 ? "today" : "${days}d",
                        style:
                            AppText.label(size: 11).copyWith(color: _cWarning)),
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
      child: Obx(() {
        if (!ctrl.revenueLoaded.value) return _loadingBox(120);
        final list = ctrl.recentPayments;
        if (list.isEmpty) {
          return _empty(context, Icons.receipt_long_outlined, "No payments yet",
              "Subscription payments will list here.");
        }
        return Column(
          children: list.take(5).map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _cActive.withValues(alpha: 0.12),
                      borderRadius: AppRadii.smR,
                    ),
                    child: const Icon(Icons.south_west,
                        size: 15, color: _cActive),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.plan.isEmpty ? "Subscription" : e.plan,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label(size: 13)
                                .copyWith(color: p.textPrimary)),
                        Text(
                            e.date == null
                                ? "—"
                                : DateFormat('d MMM, h:mm a').format(e.date!),
                            style: AppText.body(size: 11)
                                .copyWith(color: p.textMuted)),
                      ],
                    ),
                  ),
                  Text(_money(e.amount),
                      style: AppText.label(size: 13)
                          .copyWith(color: p.textPrimary)),
                ],
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  // ── SHARED PIECES ───────────────────────────────────────────────────
  Widget _sectionCard(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? trailing,
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.cardTitle(size: 15)
                          .copyWith(color: p.textPrimary)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted)),
                ],
              ),
              const Spacer(),
              if (trailing != null) trailing,
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
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(letter,
          style: AppText.label(size: 14).copyWith(color: p.accent)),
    );
  }

  Widget _empty(
      BuildContext context, IconData icon, String title, String sub) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(icon, size: 30, color: p.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(title,
              style: AppText.label(size: 13).copyWith(color: p.textSecondary)),
          const SizedBox(height: 2),
          Text(sub,
              textAlign: TextAlign.center,
              style: AppText.body(size: 12).copyWith(color: p.textMuted)),
        ],
      ),
    );
  }

  Widget _loadingBox(double h) => SizedBox(
        height: h,
        child: const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
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
      for (int i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].value)
    ];
    final small = AppText.body(size: 11).copyWith(color: label);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (data.length - 1).toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (v) => FlLine(color: grid, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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

  static String _compact(double v) {
    if (v >= 100000) return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k';
    return v.toInt().toString();
  }
}

// ============================================================================
// ORG STATUS DONUT (fl_chart)
// ============================================================================
class _StatusDonut extends StatelessWidget {
  final int active, pending, warning, blocked;
  const _StatusDonut({
    required this.active,
    required this.pending,
    required this.warning,
    required this.blocked,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <PieChartSectionData>[];

    void add(int n, Color c) {
      if (n <= 0) return;
      sections.add(PieChartSectionData(
        value: n.toDouble(),
        color: c,
        radius: 18,
        showTitle: false,
      ));
    }

    add(active, _cActive);
    add(pending, _cPending);
    add(warning, _cWarning);
    add(blocked, _cBlocked);

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
                    showTitle: false)
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
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

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
      cursor: SystemMouseCursors.basic,
      child: AnimatedScale(
        scale: _hover ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: widget.child,
      ),
    );
  }
}
