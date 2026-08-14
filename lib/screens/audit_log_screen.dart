// lib/screens/audit_log_screen.dart
//
// DOMAIN 9 — SYSTEM · Audit Log. Read-only view of privileged platform actions
// (`audit_logs`). Search + action filter + per-entry detail.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/audit_controller.dart';
import '../models/audit_log_model.dart';
import '../widgets/page_shell.dart';

class AuditLogScreen extends StatelessWidget {
  AuditLogScreen({super.key});

  final AuditController ctrl = Get.find<AuditController>();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Audit Log',
      icon: Icons.receipt_long_outlined,
      // "300 recent" read as a total. The "+" is the whole point: it says the
      // number is a window, not a count of everything that ever happened.
      trailing: Obx(() => Text(
          ctrl.atCap
              ? '${ctrl.logs.length}+ (newest first)'
              : '${ctrl.logs.length} total',
          style: AppText.body(size: 13).copyWith(color: p.textMuted))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => ctrl.search.value = v,
            decoration: InputDecoration(
              hintText: 'Search action, actor, target…',
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
          const SizedBox(height: 14),
          Obx(() {
            final actions = ctrl.actions;
            if (actions.isEmpty) return const SizedBox.shrink();
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(context, 'All', 'all'),
                for (final a in actions) _chip(context, _pretty(a), a),
              ],
            );
          }),
          const SizedBox(height: 16),
          Obx(() {
            if (ctrl.hasError.value) return _error(context);
            if (ctrl.isLoading.value && ctrl.logs.isEmpty) {
              return const SizedBox(
                  height: 220,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            final list = ctrl.filtered;
            if (list.isEmpty) return _empty(context, ctrl);
            return Column(
              children: [
                for (final l in list) ...[
                  _row(context, l),
                  const SizedBox(height: 8),
                ],
                if (ctrl.atCap) _loadMore(context, ctrl),
              ],
            );
          }),
        ],
      ),
    );
  }

  String _pretty(String action) {
    final spaced = action
        .replaceAllMapped(
            RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .trim();
    if (spaced.isEmpty) return action;
    return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
  }

  Widget _chip(BuildContext context, String label, String value) {
    final p = context.palette;
    final selected = ctrl.actionFilter.value == value;
    return InkWell(
      onTap: () => ctrl.actionFilter.value = value,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? p.accent : p.border),
        ),
        child: Text(label,
            style: AppText.body(size: 12)
                .copyWith(color: selected ? p.accent : p.textMuted)),
      ),
    );
  }

  Widget _row(BuildContext context, AuditLogModel l) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.cardR,
        onTap: l.details.isEmpty ? null : () => _showDetails(context, l),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
            boxShadow: AppShadows.card(p.isDark),
          ),
          child: Row(
            children: [
              Container(
                height: 34,
                width: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.10),
                  borderRadius: AppRadii.smR,
                ),
                child: Icon(Icons.bolt, size: 18, color: p.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(l.actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(size: 13)
                                  .copyWith(color: p.textPrimary)),
                        ),
                        if (l.targetType.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _tag(context, l.targetType),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'by ${l.displayActor}'
                      '${l.targetId.isNotEmpty ? ' · target ${l.targetId}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppText.body(size: 12).copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l.createdAt == null
                    ? '—'
                    : DateFormat('d MMM, h:mm a').format(l.createdAt!),
                style: AppText.body(size: 11).copyWith(color: p.textMuted),
              ),
              if (l.details.isNotEmpty) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 18, color: p.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String label) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: AppText.label(size: 10).copyWith(color: p.textMuted)),
    );
  }

  void _showDetails(BuildContext context, AuditLogModel l) {
    final p = context.palette;
    Get.dialog(
      Dialog(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.actionLabel,
                    style:
                        AppText.title(size: 18).copyWith(color: p.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'by ${l.displayActor}'
                  '${l.createdAt != null ? ' · ${DateFormat('d MMM yyyy, h:mm:ss a').format(l.createdAt!)}' : ''}',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 16),
                if (l.targetId.isNotEmpty)
                  _kv(context, 'Target', l.targetId),
                if (l.targetType.isNotEmpty)
                  _kv(context, 'Target type', l.targetType),
                _kv(context, 'Actor uid', l.actorUid),
                if (l.details.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('DETAILS',
                      style:
                          AppText.label(size: 11).copyWith(color: p.textMuted)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: p.surfaceAlt, borderRadius: AppRadii.smR),
                    child: SelectableText(
                      l.details.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n'),
                      style: AppText.body(size: 12)
                          .copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Get.back(),
                    child: Text('Close', style: TextStyle(color: p.accent)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(k,
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          ),
          Expanded(
            child: SelectableText(v.isEmpty ? '—' : v,
                style: AppText.body(size: 12).copyWith(color: p.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// Lets the operator widen the window. Shown whenever the window is full,
  /// because from inside a full window there is no way to tell whether the
  /// trail ended or merely ran out of rows.
  Widget _loadMore(BuildContext context, AuditController ctrl) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        children: [
          Text(
            'Showing the newest ${ctrl.logs.length} entries. '
            'Older entries are not searched until they are loaded.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 10),
          Obx(() => OutlinedButton.icon(
                onPressed: ctrl.isLoadingMore.value ? null : ctrl.loadMore,
                icon: ctrl.isLoadingMore.value
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.history, size: 18),
                label: Text(ctrl.isLoadingMore.value
                    ? 'Loading…'
                    : 'Load ${AuditController.pageSize} older entries'),
              )),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AuditController ctrl) {
    final p = context.palette;

    // The three empty states are NOT the same statement. Saying "No audit
    // entries" when the search simply did not reach far enough tells the
    // founder an action never happened — in the surface whose whole job is
    // answering that question. See AuditController.emptyReason (SA-01).
    final reason = ctrl.emptyReason;
    final truncated = reason == AuditEmptyReason.noMatchInLoadedWindow;
    final (title, body) = switch (reason) {
      AuditEmptyReason.noEntriesAtAll => (
          'No audit entries',
          'Privileged actions (approvals, role changes, activations) appear here.',
        ),
      AuditEmptyReason.noMatchAnywhere => (
          'No matching entries',
          'No audit entry matches this search. The full trail is loaded, so '
              'there is no such entry.',
        ),
      AuditEmptyReason.noMatchInLoadedWindow => (
          'No match in the newest ${ctrl.logs.length} entries',
          'Older entries have not been loaded yet, so this is not proof the '
              'action never happened. Load older entries and search again.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            truncated ? Icons.manage_search : Icons.receipt_long_outlined,
            size: 40,
            color: truncated
                ? p.accent.withValues(alpha: 0.8)
                : p.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(body,
                textAlign: TextAlign.center,
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          ),
          if (truncated) ...[
            const SizedBox(height: 16),
            Obx(() => OutlinedButton.icon(
                  onPressed: ctrl.isLoadingMore.value ? null : ctrl.loadMore,
                  icon: const Icon(Icons.history, size: 18),
                  label: Text(ctrl.isLoadingMore.value
                      ? 'Loading…'
                      : 'Load ${AuditController.pageSize} older entries'),
                )),
          ],
        ],
      ),
    );
  }

  Widget _error(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.lock_outline,
              size: 38, color: p.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text('Could not load the audit log',
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Text('If this persists, the audit_logs read rule may not be deployed yet.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: ctrl.retry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.accent,
              side: BorderSide(color: p.accent),
              shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
            ),
          ),
        ],
      ),
    );
  }
}
