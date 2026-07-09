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
        return Text(
          total == 0 ? 'All clear' : '$total need${total == 1 ? 's' : ''} attention',
          style: AppText.body(size: 13).copyWith(
            color: total == 0 ? _cClear : p.textMuted,
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
                if (alerts.isEmpty)
                  _allClear(context)
                else
                  for (final a in alerts) ...[
                    _alertCard(context, a),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          }),
        ],
      ),
    );
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
        onTap: () => Get.find<AdminRootController>().changePage(a.navIndex),
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
            'No approvals, lapses, open tickets or delivery issues need you right now.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}
