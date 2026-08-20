// lib/screens/operations_screen.dart
//
// DOMAIN 8 — OPERATIONS CENTER. The founder's daily triage home: a single,
// severity-ranked "what needs my attention across the platform" feed with
// jump-to-action links. Derives from existing controllers (no new streams).

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/admin_root_controller.dart';
import '../controllers/operations_controller.dart';
import '../core/services/ops_incident_service.dart';
import '../models/ops_incident_model.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/page_shell.dart';

const _cCritical = Color(0xFFD4341F);
const _cWarning = Color(0xFFB06A00);
const _cInfo = Color(0xFF3B6FD4);
const _cClear = Color(0xFF1A7F5A);

Color _sevColor(OpsSeverity s) {
  switch (s) {
    case OpsSeverity.critical:
      return _cCritical;
    case OpsSeverity.warning:
      return _cWarning;
    case OpsSeverity.info:
      return _cInfo;
  }
}

String _sevLabel(OpsSeverity s) {
  switch (s) {
    case OpsSeverity.critical:
      return 'Critical';
    case OpsSeverity.warning:
      return 'Attention';
    case OpsSeverity.info:
      return 'For info';
  }
}

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
        // Touch the source lists so the badge stays live.
        final total = ctrl.totalCount;
        // 🔴 "All clear" IS A CLAIM ABOUT DATA THAT HAS BEEN READ.
        //
        // The body below already distinguishes LOADING from EMPTY, and
        // `anyLoading`'s docstring says it exists for exactly that reason.
        // This badge did not: with no alerts yet it rendered a green "All
        // clear" while the body was still showing its spinner — the two halves
        // of one screen contradicting each other, and a founder reads this
        // half at a glance. A count that is zero because nothing has been
        // counted is not health.
        //
        // Only the all-clear branch is gated: once an alert exists (including
        // the SA-11 blind-spot cards) the count is real and worth showing even
        // while a slower feed is still arriving.
        final unproven = total == 0 && ctrl.anyLoading;
        return Text(
          unproven
              ? 'Checking…'
              : total == 0
                  ? 'All clear'
                  : '$total need${total == 1 ? 's' : ''} attention',
          style: AppText.body(size: 13).copyWith(
            color: !unproven && total == 0 ? _cClear : p.textMuted,
          ),
        );
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everything that needs you across the platform, right now.',
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          Obx(() {
            final alerts = ctrl.alerts; // reactive read of the source lists
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _summary(context, 'Critical', ctrl.criticalCount, _cCritical),
                    const SizedBox(width: 12),
                    _summary(context, 'Attention', ctrl.warningCount, _cWarning),
                    const SizedBox(width: 12),
                    _summary(context, 'For info', ctrl.infoCount, _cInfo),
                  ],
                ),
                const SizedBox(height: 18),
                if (ctrl.anyLoading && alerts.isEmpty)
                  const SizedBox(
                    height: 200,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4)),
                  )
                else if (alerts.isEmpty)
                  _allClear(context)
                else
                  for (final a in alerts) ...[
                    _alertCard(context, a),
                    const SizedBox(height: 10),
                  ],
                // ── B-11A triage section: the two founder-writable queues ──
                // Rendered even when the feed above is "all clear" only if
                // rows exist; resolving here is what keeps the feed clear.
                if (ctrl.opsIncidents.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Operator incidents',
                      style: AppText.title(size: 16)
                          .copyWith(color: context.palette.textPrimary)),
                  const SizedBox(height: 10),
                  for (final i in ctrl.opsIncidents) ...[
                    _incidentCard(context, i),
                    const SizedBox(height: 10),
                  ],
                ],
                if (ctrl.paymentAlerts.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Payment integrity alerts',
                      style: AppText.title(size: 16)
                          .copyWith(color: context.palette.textPrimary)),
                  const SizedBox(height: 10),
                  for (final a in ctrl.paymentAlerts) ...[
                    _paymentAlertCard(context, a),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── B-11A triage cards ─────────────────────────────────────────────────

  final OpsIncidentService _incidentService = OpsIncidentService();

  Color _incidentColor(OpsIncidentModel i) =>
      i.isP0 ? _cCritical : (i.severity == 'P1' ? _cWarning : _cInfo);

  Widget _incidentCard(BuildContext context, OpsIncidentModel i) {
    final p = context.palette;
    final c = _incidentColor(i);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: c.withValues(alpha: 0.4)),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(i.severity,
                    style: AppText.label(size: 10).copyWith(color: c)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(i.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(size: 13)
                        .copyWith(color: p.textPrimary)),
              ),
              if (i.occurrences > 1)
                Text('×${i.occurrences}',
                    style: AppText.label(size: 12).copyWith(color: c)),
              if (i.isAcknowledged) ...[
                const SizedBox(width: 8),
                Icon(Icons.visibility_outlined,
                    size: 16, color: p.textMuted),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(i.summary,
              style: AppText.body(size: 12.5).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          SelectableText('ref ${i.correlationId} · fn ${i.fn}',
              style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 6),
          Text(i.action,
              style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          const SizedBox(height: 10),
          Row(
            children: [
              if (i.isOpen)
                OutlinedButton(
                  onPressed: () => _guarded(
                    () => _incidentService.acknowledgeIncident(i.id),
                    'Incident acknowledged.',
                  ),
                  child: const Text('Acknowledge'),
                ),
              if (i.isOpen) const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _resolveDialog(
                  context,
                  title: 'Resolve incident',
                  onResolve: (note) =>
                      _incidentService.resolveIncident(i.id, note: note),
                ),
                child: const Text('Resolve'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentAlertCard(BuildContext context, Map<String, dynamic> a) {
    final p = context.palette;
    final id = (a['id'] ?? '').toString();
    final kind = (a['kind'] ?? a['type'] ?? 'payment alert').toString();
    final orderId = (a['orderId'] ?? a['razorpayOrderId'] ?? '').toString();
    final detail = (a['detail'] ?? a['message'] ?? a['reason'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: _cCritical.withValues(alpha: 0.4)),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kind,
              style: AppText.label(size: 13).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          if (detail.isNotEmpty)
            Text(detail,
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          SelectableText(
              orderId.isEmpty ? 'alert $id' : 'order $orderId · alert $id',
              style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => _resolveDialog(
              context,
              title: 'Resolve payment alert',
              onResolve: (note) =>
                  _incidentService.resolvePaymentAlert(id, note: note),
            ),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  /// Resolution requires a note — "resolved" with no record of HOW is the
  /// queue lying to the next person who reads it.
  ///
  /// The dialog OWNS its TextEditingController and returns the note through
  /// Navigator.pop. Do NOT refactor to `.whenComplete(controller.dispose)` —
  /// the dialog's exit animation is still rebuilding the TextField when the
  /// future resolves, and that exact crash has shipped in this console twice.
  Future<void> _resolveDialog(
    BuildContext context, {
    required String title,
    required Future<void> Function(String note) onResolve,
  }) async {
    final note = await Get.dialog<String>(
      _ResolveNoteDialog(title: title),
      barrierDismissible: false,
    );
    if (note == null) return;
    await _guarded(() => onResolve(note), 'Resolved.');
  }

  Future<void> _guarded(
      Future<void> Function() op, String successMessage) async {
    try {
      await op();
      AppSnackbar.show(title: 'Done', message: successMessage);
    } catch (e) {
      AppSnackbar.show(
        title: 'Could not update',
        message: '$e',
        background: _cCritical,
      );
    }
  }

  Widget _summary(BuildContext context, String label, int value, Color c) {
    final p = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(color: value > 0 ? c.withValues(alpha: 0.4) : p.border),
          boxShadow: AppShadows.card(p.isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: AppText.title(size: 24)
                    .copyWith(color: value > 0 ? c : p.textMuted)),
            const SizedBox(height: 2),
            Text(label,
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _alertCard(BuildContext context, OpsAlert a) {
    final p = context.palette;
    final c = _sevColor(a.severity);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.cardR,
        onTap: a.onTap ??
            () => Get.find<AdminRootController>().changePage(a.navIndex),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
            boxShadow: AppShadows.card(p.isDark),
          ),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: AppRadii.smR,
                ),
                child: Icon(a.icon, size: 20, color: c),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _sevPill(a.severity),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(a.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(size: 14)
                                  .copyWith(color: p.textPrimary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(a.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.actionLabel,
                      style: AppText.label(size: 12).copyWith(color: c)),
                  Icon(Icons.chevron_right, size: 18, color: c),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // (triage cards above; feed widgets below)

  Widget _sevPill(OpsSeverity s) {
    final c = _sevColor(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(_sevLabel(s),
          style: AppText.label(size: 10).copyWith(color: c)),
    );
  }

  Widget _allClear(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _cClear.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline,
                size: 34, color: _cClear),
          ),
          const SizedBox(height: 14),
          Text('All clear',
              style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'No approvals, lapses, payment incidents, quota breaches, open tickets or delivery issues need you right now.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Owns its TextEditingController so disposal happens in a State that has
/// genuinely left the tree — never via `.whenComplete` on the dialog future,
/// which resolves while the exit animation still rebuilds the TextField (a
/// crash this console has shipped twice; see the resolve-dialog call site).
class _ResolveNoteDialog extends StatefulWidget {
  const _ResolveNoteDialog({required this.title});
  final String title;

  @override
  State<_ResolveNoteDialog> createState() => _ResolveNoteDialogState();
}

class _ResolveNoteDialogState extends State<_ResolveNoteDialog> {
  final TextEditingController _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _note,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'What was done (required)',
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
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
              setState(() => _error = 'A resolution note is required.');
              return;
            }
            Navigator.of(context).pop(n);
          },
          child: const Text('Resolve'),
        ),
      ],
    );
  }
}
