// lib/screens/automation_screen.dart
//
// DOMAIN 8 — AUTOMATION (EP-5). The founder's view of WHY communication
// happens: which rules exist, whether each is on, how often it has fired, and
// — crucially — the reason each evaluation did or did not send.
//
// This screen writes nothing directly. Rules are Cloud-Function-owned; the
// only mutation offered is the enable/disable toggle, which goes through the
// `setAutomationEnabled` callable. Everything else is observation.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/services/automation_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_shadows.dart';
import '../core/theme/app_text.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/page_shell.dart';

const _cOn = Color(0xFF1A7F5A);
const _cOff = Color(0xFF6A6F7A);
const _cWarn = Color(0xFFD4341F);

class AutomationScreen extends StatefulWidget {
  const AutomationScreen({super.key});

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  final AutomationService _svc = AutomationService();
  final TextEditingController _search = TextEditingController();

  /// all | enabled | disabled | failing
  String _filter = 'all';
  Map<String, AutomationTrigger> _triggers = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadTriggers();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadTriggers() async {
    try {
      final list = await _svc.triggers();
      if (!mounted) return;
      setState(() => _triggers = {for (final t in list) t.id: t});
    } catch (_) {
      // The list still renders from the rule documents alone.
    }
  }

  bool _matches(AutomationRule r) {
    switch (_filter) {
      case 'enabled':
        if (!r.enabled) return false;
        break;
      case 'disabled':
        if (r.enabled) return false;
        break;
      case 'failing':
        if (r.isHealthy) return false;
        break;
    }
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final label = _triggers[r.trigger]?.label ?? '';
    return '${r.id} ${r.trigger} $label ${r.templateId}'
        .toLowerCase()
        .contains(q);
  }

  Future<void> _toggle(AutomationRule r, bool on) async {
    setState(() => _busy = true);
    try {
      await _svc.setEnabled(r.id, on);
      AppSnackbar.show(
        title: on ? 'Enabled' : 'Disabled',
        message: on
            ? 'This automation will now run'
            : 'This automation will no longer run',
        background: on ? _cOn : _cOff,
      );
    } catch (_) {
      AppSnackbar.show(title: 'Error', message: 'Could not update automation');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Automation',
      icon: Icons.bolt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rules that decide WHY a communication happens. Recipients, copy '
            'and delivery are handled by the communication engine.',
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search automations',
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
          const SizedBox(height: 12),
          StreamBuilder<List<AutomationRule>>(
            stream: _svc.watchRules(),
            builder: (context, snap) {
              if (snap.hasError) {
                return _message(context, Icons.error_outline,
                    'Could not load automations', _cWarn);
              }
              if (!snap.hasData) {
                return const SizedBox(
                    height: 180,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4)));
              }
              final all = snap.data!;
              final shown = all.where(_matches).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _chip(context, 'All', 'all', all.length),
                      _chip(context, 'Enabled', 'enabled',
                          all.where((r) => r.enabled).length),
                      _chip(context, 'Disabled', 'disabled',
                          all.where((r) => !r.enabled).length),
                      if (all.any((r) => !r.isHealthy))
                        _chip(context, 'Needs attention', 'failing',
                            all.where((r) => !r.isHealthy).length),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (all.isEmpty)
                    _message(
                        context,
                        Icons.bolt_outlined,
                        'No automations configured yet. Rules are created '
                            'server-side and appear here once defined.',
                        p.textMuted)
                  else if (shown.isEmpty)
                    _message(context, Icons.search_off,
                        'No automations match this filter.', p.textMuted)
                  else
                    for (final r in shown) ...[
                      _ruleCard(context, r),
                      const SizedBox(height: 10),
                    ],
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Text('RECENT ACTIVITY',
              style: AppText.label(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 8),
          _history(context),
        ],
      ),
    );
  }

  Widget _ruleCard(BuildContext context, AutomationRule r) {
    final p = context.palette;
    final t = _triggers[r.trigger];
    return Container(
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: (r.enabled ? _cOn : _cOff).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(r.enabled ? 'ON' : 'OFF',
                    style: AppText.label(size: 10)
                        .copyWith(color: r.enabled ? _cOn : _cOff)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(t?.label ?? r.trigger,
                    style: AppText.label(size: 14)
                        .copyWith(color: p.textPrimary)),
              ),
              // The toggle is the ONLY mutation this screen performs, and it
              // goes through a callable — rules are never client-written.
              Switch(
                value: r.enabled,
                activeThumbColor: _cOn,
                onChanged: _busy ? null : (v) => _toggle(r, v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (t != null)
            Text('Fires from ${t.source}',
                style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _stat(context, Icons.article_outlined, 'Template', r.templateId),
              _stat(context, Icons.groups_outlined, 'Audience', r.audience),
              _stat(context, Icons.bolt_outlined, 'Fired',
                  '${r.fireCount}'),
              _stat(context, Icons.schedule, 'Last run',
                  r.lastFiredAt == null
                      ? 'never'
                      : DateFormat('d MMM, h:mm a').format(r.lastFiredAt!)),
              _stat(context, Icons.tag, 'Version', 'v${r.version}'),
            ],
          ),
          if (!r.isHealthy) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 14, color: _cWarn),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.lastError ?? '${r.failureCount} failure(s)',
                    style: AppText.body(size: 12).copyWith(color: _cWarn),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _history(BuildContext context) {
    final p = context.palette;
    return StreamBuilder<List<AutomationRun>>(
      stream: _svc.watchRuns(),
      builder: (context, snap) {
        // 🔴 `hasError` must be tested BEFORE `!hasData`. On a stream error
        // `hasData` never becomes true, so without this branch the panel spun
        // an infinite loader instead of saying it could not read
        // `automation_runs`. Same shape as the rules stream above.
        if (snap.hasError) {
          return _message(context, Icons.error_outline,
              'Could not load automation activity', _cWarn);
        }
        if (!snap.hasData) {
          return const SizedBox(
              height: 80,
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2))));
        }
        final runs = snap.data!;
        if (runs.isEmpty) {
          return _message(context, Icons.history,
              'No automation activity yet.', p.textMuted);
        }
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
          ),
          child: Column(
            children: [
              for (final run in runs.take(40))
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      Icon(
                        run.fired
                            ? Icons.check_circle_outline
                            : Icons.remove_circle_outline,
                        size: 15,
                        color: run.fired ? _cOn : p.textMuted,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _triggers[run.trigger]?.label ?? run.trigger,
                              style: AppText.body(size: 12.5)
                                  .copyWith(color: p.textPrimary),
                            ),
                            // The reason is the point of this log: "why did my
                            // automation not fire?" is the real question.
                            Text(run.explanation,
                                style: AppText.body(size: 11)
                                    .copyWith(color: p.textMuted)),
                          ],
                        ),
                      ),
                      if (run.createdAt != null)
                        Text(
                          DateFormat('d MMM, h:mm a').format(run.createdAt!),
                          style: AppText.body(size: 11)
                              .copyWith(color: p.textMuted),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(
      BuildContext context, IconData icon, String label, String value) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: p.textMuted),
        const SizedBox(width: 5),
        Text('$label: ',
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
        Text(value.isEmpty ? '—' : value,
            style: AppText.body(size: 11.5).copyWith(color: p.textSecondary)),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, String id, int count) {
    final p = context.palette;
    final on = _filter == id;
    return InkWell(
      onTap: () => setState(() => _filter = id),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? p.accent.withValues(alpha: 0.12) : p.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? p.accent : p.border),
        ),
        child: Text('$label · $count',
            style: AppText.label(size: 12)
                .copyWith(color: on ? p.accent : p.textSecondary)),
      ),
    );
  }

  Widget _message(
      BuildContext context, IconData icon, String text, Color color) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 26, color: color),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        ],
      ),
    );
  }
}
