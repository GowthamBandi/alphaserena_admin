// lib/screens/platform_staff_screen.dart
//
// PLATFORM IAM (Phase F) — Platform Staff (the people who OPERATE the platform),
// deliberately SEPARATE from Organizations (gym owners / customers).
//
// Repo-supported today: a READ-ONLY list of the real super admins from
// `master_admins`. Staff provisioning is server-only (security rules), so there
// are NO write actions here. The "Designed roles" panel documents the future IAM
// role model (see docs/platform-iam-architecture.md) — not yet provisioned.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/platform_staff_controller.dart';
import '../models/platform_staff_model.dart';
import '../widgets/page_shell.dart';

const _cLive = Color(0xFF1A7F5A);
const _cPlanned = Color(0xFF6A6F7A);

class PlatformStaffScreen extends StatelessWidget {
  PlatformStaffScreen({super.key});

  final PlatformStaffController ctrl = Get.find<PlatformStaffController>();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Platform Staff',
      icon: Icons.shield_outlined,
      trailing: Obx(() => Text('${ctrl.total} active',
          style: AppText.body(size: 13).copyWith(color: p.textMuted))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The people who operate the platform (super admins) — separate from '
            'Organizations (gym owners). Provisioning is server-side; this view is read-only.',
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          _provisioningNote(context),
          const SizedBox(height: 20),
          Text('ACTIVE PLATFORM STAFF',
              style: AppText.label(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 10),
          Obx(() {
            if (ctrl.hasError.value) return _error(context);
            if (ctrl.isLoading.value && ctrl.staff.isEmpty) {
              return const SizedBox(
                  height: 160,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            if (ctrl.staff.isEmpty) {
              return _empty(context);
            }
            return Column(
              children: [
                for (final s in ctrl.staff) ...[
                  _staffCard(context, s),
                  const SizedBox(height: 10),
                ],
              ],
            );
          }),
          const SizedBox(height: 24),
          Text('DESIGNED ROLE MODEL (IAM FOUNDATION)',
              style: AppText.label(size: 11).copyWith(color: p.textMuted)),
          const SizedBox(height: 4),
          Text(
            'The role hierarchy the platform is designed to support. Only '
            '“Founder / Super Admin” is provisioned today; the rest are the '
            'planned model (see docs/platform-iam-architecture.md) and require a '
            'platform_staff collection + role/claims engine to activate.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 12),
          _designedRoles(context),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _provisioningNote(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.07),
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Staff accounts are provisioned server-side (scripts/set_super_admin.js) '
              'and the security rules make master_admins writes server-only — so '
              'creating/editing staff from this console is intentionally disabled. '
              'In-app invite/role management is a documented future capability.',
              style: AppText.body(size: 12).copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staffCard(BuildContext context, PlatformStaffModel s) {
    final p = context.palette;
    return Container(
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
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              s.displayEmail.isNotEmpty ? s.displayEmail[0].toUpperCase() : '?',
              style: AppText.label(size: 16).copyWith(color: p.accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: SelectableText(s.displayEmail,
                          maxLines: 1,
                          style: AppText.label(size: 14)
                              .copyWith(color: p.textPrimary)),
                    ),
                    const SizedBox(width: 8),
                    _roleChip(s.roleEnum),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'UID ${s.uid}'
                  '${s.createdAt != null ? '  ·  since ${DateFormat('d MMM yyyy').format(s.createdAt!)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(PlatformRole role) {
    final c = role.isProvisionedToday ? _cLive : _cPlanned;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(role.label,
          style: AppText.label(size: 11).copyWith(color: c)),
    );
  }

  Widget _designedRoles(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < PlatformRole.values.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            _roleRow(context, PlatformRole.values[i]),
          ],
        ],
      ),
    );
  }

  Widget _roleRow(BuildContext context, PlatformRole role) {
    final p = context.palette;
    final live = role.isProvisionedToday;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(live ? Icons.check_circle : Icons.circle_outlined,
              size: 16, color: live ? _cLive : p.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(role.label,
                style: AppText.body(size: 13).copyWith(color: p.textPrimary)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: (live ? _cLive : _cPlanned).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(live ? 'Provisioned' : 'Planned',
                style: AppText.label(size: 10)
                    .copyWith(color: live ? _cLive : _cPlanned)),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 44),
      alignment: Alignment.center,
      child: Text('No platform staff found.',
          style: AppText.body(size: 13).copyWith(color: p.textMuted)),
    );
  }

  Widget _error(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 34, color: p.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text('Could not load platform staff',
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 12),
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
