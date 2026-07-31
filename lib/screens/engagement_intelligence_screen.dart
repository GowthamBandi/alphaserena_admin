// lib/screens/engagement_intelligence_screen.dart
//
// DOMAIN 9 — ENGAGEMENT INTELLIGENCE (EP-6). The executive view of what the
// communication platform actually did: delivery, suppression, campaign and
// automation performance, read rate, trends, and the insights derived from
// them.
//
// Every number here is computed SERVER-SIDE by `getEngagementIntelligence`.
// This screen renders and never aggregates — the same discipline EP-2 set for
// recipient counts. It also states, in the UI, the metrics this platform
// CANNOT measure, so a missing figure is never mistaken for a zero.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/services/intelligence_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_shadows.dart';
import '../core/theme/app_text.dart';
import '../widgets/page_shell.dart';

const _cGood = Color(0xFF1A7F5A);
const _cWarn = Color(0xFFB06A00);
const _cBad = Color(0xFFD4341F);
const _cInfo = Color(0xFF3B6FD4);

String _pct(double v) => '${(v * 100).toStringAsFixed(v >= 0.1 ? 0 : 1)}%';

class EngagementIntelligenceScreen extends StatefulWidget {
  const EngagementIntelligenceScreen({super.key});

  @override
  State<EngagementIntelligenceScreen> createState() =>
      _EngagementIntelligenceScreenState();
}

class _EngagementIntelligenceScreenState
    extends State<EngagementIntelligenceScreen> {
  final IntelligenceService _svc = IntelligenceService();

  EngagementIntelligence? _data;
  bool _loading = true;
  String? _error;
  int _days = 30;
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _svc.load(days: _days);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load engagement intelligence.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Engagement Intelligence',
      icon: Icons.insights_outlined,
      trailing: _windowPicker(context),
      child: Builder(builder: (context) {
        if (_loading && _data == null) {
          return const SizedBox(
            height: 260,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        }
        if (_error != null) {
          return _panel(
            context,
            child: Column(
              children: [
                const Icon(Icons.error_outline, size: 26, color: _cBad),
                const SizedBox(height: 8),
                Text(_error!,
                    style:
                        AppText.body(size: 13).copyWith(color: p.textMuted)),
                const SizedBox(height: 10),
                OutlinedButton(
                    onPressed: _load, child: const Text('Retry')),
              ],
            ),
          );
        }
        final d = _data!;
        return Opacity(
          opacity: _loading ? 0.55 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headline(context, d),
              const SizedBox(height: 18),
              _sectionTitle(context, 'INSIGHTS'),
              _insights(context, d),
              const SizedBox(height: 18),
              _sectionTitle(context, 'DELIVERY TREND'),
              _trend(context, d),
              const SizedBox(height: 18),
              _sectionTitle(context, 'SUPPRESSION BREAKDOWN'),
              _suppression(context, d),
              const SizedBox(height: 18),
              _sectionTitle(context, 'CAMPAIGN PERFORMANCE'),
              _campaigns(context, d),
              const SizedBox(height: 18),
              _sectionTitle(context, 'AUTOMATION EFFECTIVENESS'),
              _automations(context, d),
              const SizedBox(height: 18),
              _sectionTitle(context, 'MESSAGING & CALLS'),
              _messaging(context, d),
              const SizedBox(height: 18),
              _sectionTitle(context, 'NOT MEASURED'),
              _unavailable(context, d),
            ],
          ),
        );
      }),
    );
  }

  Widget _windowPicker(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in const [7, 30, 90]) ...[
          InkWell(
            onTap: _loading
                ? null
                : () {
                    setState(() => _days = d);
                    _load();
                  },
            borderRadius: BorderRadius.circular(999),
            child: Container(
              margin: const EdgeInsets.only(left: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _days == d
                    ? p.accent.withValues(alpha: 0.12)
                    : p.surface,
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: _days == d ? p.accent : p.border),
              ),
              child: Text('${d}d',
                  style: AppText.label(size: 12).copyWith(
                      color: _days == d ? p.accent : p.textSecondary)),
            ),
          ),
        ],
      ],
    );
  }

  // ── headline cards ──────────────────────────────────────────────────
  Widget _headline(BuildContext context, EngagementIntelligence d) {
    final read = d.read;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _kpi(context,
            label: 'Notifications created',
            value: NumberFormat.decimalPattern().format(d.delivery.created),
            change: d.delivery.createdChange,
            icon: Icons.notifications_active_outlined),
        _kpi(context,
            label: 'Reached the in-app centre',
            value: _pct(d.delivery.persistRate),
            sub: '${d.delivery.persisted} of ${d.delivery.created}',
            icon: Icons.inbox_outlined),
        _kpi(context,
            label: 'Reached a device',
            value: _pct(d.delivery.pushRate),
            sub: 'push accepted — not an open',
            change: d.delivery.pushChange,
            icon: Icons.phone_iphone_outlined),
        _kpi(context,
            label: 'Suppressed by preference',
            value: _pct(d.delivery.suppressionRate),
            sub: '${d.delivery.suppressedTotal} silenced',
            change: d.delivery.suppressedChange,
            invertChange: true,
            icon: Icons.volume_off_outlined),
        _kpi(context,
            label: 'Read rate',
            // A rate with no settled cohort is not a number worth showing.
            value: read.cohorts > 0 ? _pct(read.rate) : '—',
            sub: read.cohorts > 0
                ? '${read.read} of ${read.items} · settled cohorts only'
                : 'not enough settled data yet',
            icon: Icons.mark_email_read_outlined),
        _kpi(context,
            label: 'Campaigns',
            value: '${d.campaignTotal}',
            sub: d.campaignStatusMix.entries
                .map((e) => '${e.value} ${e.key}')
                .take(3)
                .join(' · '),
            icon: Icons.campaign_outlined),
        _kpi(context,
            label: 'Automations active',
            value: '${d.rulesEnabled}/${d.ruleCount}',
            sub: d.rulesFailing > 0
                ? '${d.rulesFailing} need attention'
                : '${d.automationEvaluations} evaluations',
            icon: Icons.bolt_outlined),
      ],
    );
  }

  Widget _kpi(BuildContext context,
      {required String label,
      required String value,
      String? sub,
      double? change,
      bool invertChange = false,
      required IconData icon}) {
    final p = context.palette;
    final up = (change ?? 0) >= 0;
    final good = invertChange ? !up : up;
    return Container(
      width: 236,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: p.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 11.5)
                        .copyWith(color: p.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: AppText.label(size: 22)
                      .copyWith(color: p.textPrimary)),
              const SizedBox(width: 8),
              // A null change means there was no baseline period. Rendering
              // that as "+100%" would invent a trend out of nothing.
              if (change != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${up ? '▲' : '▼'} ${_pct(change.abs())}',
                    style: AppText.body(size: 11.5)
                        .copyWith(color: good ? _cGood : _cBad),
                  ),
                ),
            ],
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub,
                maxLines: 2,
                style:
                    AppText.body(size: 11).copyWith(color: p.textSecondary)),
          ],
        ],
      ),
    );
  }

  // ── insights ────────────────────────────────────────────────────────
  Widget _insights(BuildContext context, EngagementIntelligence d) {
    final p = context.palette;
    if (d.insights.isEmpty) {
      return _panel(context,
          child: Row(children: [
            const Icon(Icons.check_circle_outline, size: 18, color: _cGood),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nothing needs attention in this window.',
                style: AppText.body(size: 13).copyWith(color: p.textSecondary),
              ),
            ),
          ]));
    }
    return Column(
      children: [
        for (final i in d.insights) ...[
          _insightCard(context, i),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _insightCard(BuildContext context, EngagementInsight i) {
    final p = context.palette;
    final c = switch (i.severity) {
      'critical' => _cBad,
      'warning' => _cWarn,
      _ => _cInfo,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: AppRadii.cardR,
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              i.severity == 'critical'
                  ? Icons.error_outline
                  : i.severity == 'warning'
                      ? Icons.warning_amber_outlined
                      : Icons.info_outline,
              size: 18,
              color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.title,
                    style: AppText.label(size: 13.5).copyWith(color: c)),
                const SizedBox(height: 3),
                Text(i.detail,
                    style: AppText.body(size: 12.5)
                        .copyWith(color: p.textSecondary)),
                const SizedBox(height: 6),
                // The working, always shown. A recommendation a founder
                // cannot verify is just an opinion.
                Text('Evidence — ${i.evidence}',
                    style:
                        AppText.body(size: 11.5).copyWith(color: p.textMuted)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_forward, size: 13, color: p.accent),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(i.recommendation,
                          style: AppText.body(size: 12)
                              .copyWith(color: p.accent)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── trend ───────────────────────────────────────────────────────────
  Widget _trend(BuildContext context, EngagementIntelligence d) {
    final p = context.palette;
    if (d.trend.isEmpty) {
      return _panel(context,
          child: Text('No activity in this window.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)));
    }
    final maxV = d.trend
        .map((t) => math.max(t.created, t.pushDelivered))
        .fold<int>(1, math.max);
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _legend(context, _cInfo, 'Created'),
              const SizedBox(width: 14),
              _legend(context, _cGood, 'Pushed'),
              const Spacer(),
              Text('peak $maxV/day',
                  style:
                      AppText.body(size: 11).copyWith(color: p.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: Semantics(
              label: 'Daily notification volume over the last '
                  '${d.windowDays} days. Peak $maxV per day.',
              child: LayoutBuilder(builder: (context, c) {
                // Quiet days are real zero-height bars, not gaps: the backend
                // emits a dense series precisely so a quiet week cannot be
                // drawn as steady traffic.
                final w = math.max(2.0, (c.maxWidth / d.trend.length) - 2);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final t in d.trend)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Tooltip(
                          message: '${t.day}\n${t.created} created\n'
                              '${t.pushDelivered} pushed\n'
                              '${t.suppressed} suppressed',
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: w,
                                height: 118 * (t.created / maxV),
                                decoration: BoxDecoration(
                                  color: _cInfo.withValues(alpha: 0.28),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(2)),
                                ),
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: w,
                                  height: 118 *
                                      (t.pushDelivered / maxV),
                                  decoration: BoxDecoration(
                                    color: _cGood.withValues(alpha: 0.85),
                                    borderRadius:
                                        const BorderRadius.vertical(
                                            top: Radius.circular(2)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(d.trend.first.day,
                  style:
                      AppText.body(size: 10.5).copyWith(color: p.textMuted)),
              Text(d.trend.last.day,
                  style:
                      AppText.body(size: 10.5).copyWith(color: p.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, Color c, String label) {
    final p = context.palette;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 9,
          height: 9,
          decoration:
              BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(label,
          style: AppText.body(size: 11.5).copyWith(color: p.textSecondary)),
    ]);
  }

  // ── suppression ─────────────────────────────────────────────────────
  Widget _suppression(BuildContext context, EngagementIntelligence d) {
    final p = context.palette;
    final reasons = d.delivery.suppressedByReason.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (reasons.isEmpty) {
      return _panel(context,
          child: Text('Nothing was suppressed in this window.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)));
    }
    final total = reasons.fold<int>(0, (a, e) => a + e.value);
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suppression is users exercising their preferences, not a fault.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 10),
          for (final e in reasons) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(e.key,
                        style: AppText.body(size: 12.5)
                            .copyWith(color: p.textSecondary)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total > 0 ? e.value / total : 0,
                        minHeight: 8,
                        backgroundColor: p.surfaceAlt,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_cWarn),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 80,
                    child: Text('${e.value}',
                        textAlign: TextAlign.right,
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── campaigns ───────────────────────────────────────────────────────
  Widget _campaigns(BuildContext context, EngagementIntelligence d) {
    final p = context.palette;
    final q = _search.text.trim().toLowerCase();
    bool match(CampaignPerf c) =>
        q.isEmpty || '${c.title} ${c.audience} ${c.status}'.toLowerCase().contains(q);
    final top = d.topCampaigns.where(match).toList();
    final worst = d.worstCampaigns.where(match).toList();
    if (d.topCampaigns.isEmpty) {
      return _panel(context,
          child: Text(
              'No campaign has completed a delivery run yet.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Search campaigns',
            prefixIcon: Icon(Icons.search, size: 18, color: p.textMuted),
            filled: true,
            fillColor: p.inputFill,
            isDense: true,
            enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.smR,
                borderSide: BorderSide(color: p.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.smR,
                borderSide: BorderSide(color: p.accent)),
          ),
        ),
        const SizedBox(height: 10),
        _campaignTable(context, 'Best delivery', top, _cGood),
        const SizedBox(height: 10),
        _campaignTable(context, 'Needs attention', worst, _cWarn),
      ],
    );
  }

  Widget _campaignTable(
      BuildContext context, String heading, List<CampaignPerf> rows, Color c) {
    final p = context.palette;
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: AppText.label(size: 12).copyWith(color: c)),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text('No matches.',
                style: AppText.body(size: 12).copyWith(color: p.textMuted))
          else
            // Wide content scrolls inside its own box rather than forcing the
            // page to scroll sideways.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 26,
                headingRowHeight: 34,
                dataRowMinHeight: 38,
                dataRowMaxHeight: 46,
                columns: const [
                  DataColumn(label: Text('Campaign')),
                  DataColumn(label: Text('Audience')),
                  DataColumn(label: Text('Delivered'), numeric: true),
                  DataColumn(label: Text('Rate'), numeric: true),
                  DataColumn(label: Text('Push reach'), numeric: true),
                  DataColumn(label: Text('Failed'), numeric: true),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [
                      DataCell(SizedBox(
                        width: 190,
                        child: Text(r.title.isEmpty ? r.id : r.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      )),
                      DataCell(Text(r.audience)),
                      DataCell(Text('${r.sentCount}/${r.targetCount}')),
                      DataCell(Text(_pct(r.deliveryRate),
                          style: TextStyle(
                              color: r.deliveryRate >= 0.9 ? _cGood : _cWarn))),
                      DataCell(Text(_pct(r.pushReach))),
                      DataCell(Text('${r.failedCount}',
                          style: TextStyle(
                              color: r.failedCount > 0 ? _cBad : null))),
                    ]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── automations ─────────────────────────────────────────────────────
  Widget _automations(BuildContext context, EngagementIntelligence d) {
    final p = context.palette;
    if (d.automations.isEmpty) {
      return _panel(context,
          child: Text('No automation has been evaluated in this window.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)));
    }
    return _panel(
      context,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 24,
          headingRowHeight: 34,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 52,
          columns: const [
            DataColumn(label: Text('Rule')),
            DataColumn(label: Text('Trigger')),
            DataColumn(label: Text('Evaluated'), numeric: true),
            DataColumn(label: Text('Fired'), numeric: true),
            DataColumn(label: Text('Fire rate'), numeric: true),
            DataColumn(label: Text('Delivered'), numeric: true),
            DataColumn(label: Text('Top skip reason')),
          ],
          rows: [
            for (final a in d.automations)
              DataRow(cells: [
                DataCell(SizedBox(
                  width: 150,
                  child: Row(children: [
                    if (a.firedWithNoRecipients > 0)
                      const Padding(
                        padding: EdgeInsets.only(right: 5),
                        child: Tooltip(
                          message: 'Fired but delivered to nobody',
                          child:
                              Icon(Icons.error_outline, size: 14, color: _cBad),
                        ),
                      ),
                    Expanded(
                      child: Text(a.ruleId,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                )),
                DataCell(Text(a.trigger)),
                DataCell(Text('${a.evaluations}')),
                DataCell(Text('${a.fired}')),
                DataCell(Text(_pct(a.fireRate))),
                DataCell(Text('${a.delivered}')),
                DataCell(Text(_topReason(a),
                    style:
                        AppText.body(size: 12).copyWith(color: p.textMuted))),
              ]),
          ],
        ),
      ),
    );
  }

  static String _topReason(AutomationPerf a) {
    if (a.skipReasons.isEmpty) return '—';
    final e = a.skipReasons.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return '${e.first.key} (${e.first.value})';
  }

  // ── messaging ───────────────────────────────────────────────────────
  Widget _messaging(BuildContext context, EngagementIntelligence d) {
    final m = d.messaging;
    final p = context.palette;
    if (m.values.every((v) => v == 0)) {
      return _panel(context,
          child: Text('No chat or call activity in this window.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)));
    }
    return _panel(
      context,
      child: Wrap(
        spacing: 26,
        runSpacing: 12,
        children: [
          _stat(context, 'Messages', m['messages'] ?? 0),
          _stat(context, 'Images', m['images'] ?? 0),
          _stat(context, 'Voice notes', m['voiceMessages'] ?? 0),
          _stat(context, 'Chat pushes sent', m['pushSent'] ?? 0),
          _stat(context, 'Chat pushes missed', m['pushMissed'] ?? 0),
          _stat(context, 'Calls placed', m['callsPlaced'] ?? 0),
          _stat(context, 'Calls connected', m['callsConnected'] ?? 0),
          _stat(context, 'Calls missed', m['callsMissed'] ?? 0),
          _stat(context, 'Call minutes', m['callMinutes'] ?? 0),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, int value) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(NumberFormat.decimalPattern().format(value),
            style: AppText.label(size: 17).copyWith(color: p.textPrimary)),
        Text(label,
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
      ],
    );
  }

  // ── not measured ────────────────────────────────────────────────────
  Widget _unavailable(BuildContext context, EngagementIntelligence d) {
    final p = context.palette;
    if (d.unavailable.isEmpty) return const SizedBox.shrink();
    return _panel(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'These are deliberately absent, not zero. Nothing in the platform '
            'records them today.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 10),
          for (final u in d.unavailable) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.do_not_disturb_on_outlined,
                      size: 15, color: p.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(children: [
                        TextSpan(
                          text: '${u.metric} — ',
                          style: AppText.label(size: 12.5)
                              .copyWith(color: p.textSecondary),
                        ),
                        TextSpan(
                          text: u.reason,
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── shared chrome ───────────────────────────────────────────────────
  Widget _sectionTitle(BuildContext context, String t) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: AppText.label(size: 11).copyWith(color: p.textMuted)),
    );
  }

  Widget _panel(BuildContext context, {required Widget child}) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: child,
    );
  }
}
