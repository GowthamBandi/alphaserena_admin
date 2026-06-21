import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/admin_controller.dart';
import '../models/admin_model.dart';
import '../widgets/page_shell.dart';

const _cActive = Color(0xFF1A7F5A);
const _cPending = Color(0xFF3B6FD4);
const _cWarning = Color(0xFFB06A00);
const _cBlocked = Color(0xFFD4341F);

Color _statusColor(String s) {
  switch (s.toLowerCase()) {
    case 'active':
      return _cActive;
    case 'pending':
      return _cPending;
    case 'warning':
      return _cWarning;
    case 'blocked':
      return _cBlocked;
    default:
      return const Color(0xFF9AA0A6);
  }
}

class AdminsScreen extends StatelessWidget {
  AdminsScreen({super.key});

  final AdminController ctrl = Get.find<AdminController>();
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: "Organizations",
      icon: Icons.business_outlined,
      trailing: Obx(() => Text(
            "${ctrl.admins.length} total",
            style: AppText.body(size: 13)
                .copyWith(color: context.palette.textMuted),
          )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toolbar(context),
          const SizedBox(height: 16),
          Obx(() {
            if (ctrl.isLoading.value && ctrl.admins.isEmpty) {
              return const SizedBox(
                height: 240,
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              );
            }
            final list = ctrl.filtered;
            if (list.isEmpty) return _empty(context);
            return Column(
              children: [
                for (final a in list) ...[
                  _row(context, a),
                  const SizedBox(height: 10),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── TOOLBAR ─────────────────────────────────────────────────────────
  Widget _toolbar(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => ctrl.search.value = v,
          decoration: InputDecoration(
            hintText: "Search organizations, owners, emails…",
            prefixIcon: Icon(Icons.search, color: p.textMuted),
            filled: true,
            fillColor: p.surface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.border),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Obx(() => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _chip(context, "All", "all", ctrl.admins.length),
                _chip(context, "Active", "active",
                    ctrl.countByStatus("active")),
                _chip(context, "Pending", "pending",
                    ctrl.countByStatus("pending")),
                _chip(context, "Warning", "warning",
                    ctrl.countByStatus("warning")),
                _chip(context, "Blocked", "blocked",
                    ctrl.countByStatus("blocked")),
              ],
            )),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, String value, int count) {
    final p = context.palette;
    final selected = ctrl.statusFilter.value == value;
    final accent = value == 'all' ? p.accent : _statusColor(value);
    return InkWell(
      onTap: () => ctrl.statusFilter.value = value,
      borderRadius: AppRadii.smR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : p.surface,
          borderRadius: AppRadii.smR,
          border: Border.all(color: selected ? accent : p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppText.label(size: 13)
                    .copyWith(color: selected ? accent : p.textSecondary)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color:
                    selected ? accent.withValues(alpha: 0.18) : p.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text("$count",
                  style: AppText.label(size: 11)
                      .copyWith(color: selected ? accent : p.textMuted)),
            ),
          ],
        ),
      ),
    );
  }

  // ── ROW ─────────────────────────────────────────────────────────────
  Widget _row(BuildContext context, AdminModel a) {
    final p = context.palette;
    final name = a.organizationName.isNotEmpty ? a.organizationName : a.name;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadii.cardR,
        onTap: () => _showDetails(context, a),
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
              _avatar(context, name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label(size: 14)
                                  .copyWith(color: p.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(a.status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(a.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(size: 12)
                            .copyWith(color: p.textMuted)),
                    const SizedBox(height: 5),
                    _subscriptionLine(context, a),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _actionsMenu(context, a),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subscriptionLine(BuildContext context, AdminModel a) {
    final p = context.palette;
    if (a.isSubscriptionActive) {
      final exp = a.planExpiry != null
          ? " · expires ${DateFormat('d MMM yyyy').format(a.planExpiry!)}"
          : "";
      return Row(children: [
        const Icon(Icons.verified, size: 13, color: _cActive),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            "${a.planName ?? 'Subscribed'}$exp",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(size: 12).copyWith(color: p.textSecondary),
          ),
        ),
      ]);
    }
    return Row(children: [
      Icon(Icons.cancel_outlined, size: 13, color: p.textMuted),
      const SizedBox(width: 5),
      Text("No active subscription",
          style: AppText.body(size: 12).copyWith(color: p.textMuted)),
    ]);
  }

  Widget _actionsMenu(BuildContext context, AdminModel a) {
    final p = context.palette;
    final s = a.status.toLowerCase();
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: p.textMuted),
      position: PopupMenuPosition.under,
      onSelected: (v) => _onAction(context, a, v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'view', child: Text('View details')),
        if (s == 'pending')
          const PopupMenuItem(value: 'approve', child: Text('Approve')),
        if (s == 'active' || s == 'pending')
          const PopupMenuItem(value: 'warn', child: Text('Issue warning')),
        if (s == 'warning' || s == 'blocked')
          const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
        if (s != 'blocked')
          const PopupMenuItem(
            value: 'block',
            child: Text('Block', style: TextStyle(color: _cBlocked)),
          ),
      ],
    );
  }

  void _onAction(BuildContext context, AdminModel a, String action) {
    switch (action) {
      case 'view':
        _showDetails(context, a);
        break;
      case 'approve':
        ctrl.approve(a.docId);
        break;
      case 'reactivate':
        ctrl.reactivate(a.docId);
        break;
      case 'warn':
        _reasonDialog(
          context,
          title: 'Issue a warning',
          hint: 'Reason shown to the organization',
          confirmLabel: 'Send warning',
          confirmColor: _cWarning,
          onConfirm: (r) => ctrl.warn(a.docId, r),
        );
        break;
      case 'block':
        _reasonDialog(
          context,
          title: 'Block organization',
          hint: 'Reason for blocking',
          confirmLabel: 'Block',
          confirmColor: _cBlocked,
          onConfirm: (r) => ctrl.block(a.docId, r),
        );
        break;
    }
  }

  // ── DETAILS DIALOG ──────────────────────────────────────────────────
  void _showDetails(BuildContext context, AdminModel a) {
    final p = context.palette;
    final name = a.organizationName.isNotEmpty ? a.organizationName : a.name;
    final l = a.subscriptionLimits;

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
                Row(
                  children: [
                    _avatar(context, name, size: 46),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: AppText.title(size: 20)
                                  .copyWith(color: p.textPrimary)),
                          const SizedBox(height: 2),
                          Text("Owner: ${a.name}",
                              style: AppText.body(size: 13)
                                  .copyWith(color: p.textMuted)),
                        ],
                      ),
                    ),
                    _statusChip(a.status),
                  ],
                ),
                const SizedBox(height: 20),
                _detail(context, Icons.email_outlined, "Email", a.email),
                _detail(context, Icons.phone_outlined, "Phone",
                    a.phone.isEmpty ? "—" : a.phone),
                if ((a.address ?? '').isNotEmpty)
                  _detail(context, Icons.location_on_outlined, "Address",
                      a.address!),
                _detail(
                  context,
                  Icons.workspace_premium_outlined,
                  "Subscription",
                  a.isSubscriptionActive
                      ? "${a.planName ?? 'Active'}${a.planExpiry != null ? ' · expires ${DateFormat('d MMM yyyy').format(a.planExpiry!)}' : ''}"
                      : "No active subscription",
                ),
                _detail(context, Icons.groups_outlined, "Plan limits",
                    "${l.maxTrainers} trainers · ${l.maxClients} clients"),
                _detail(context, Icons.calendar_today_outlined, "Joined",
                    DateFormat('d MMM yyyy').format(a.createdAt)),
                const SizedBox(height: 22),
                _detailActions(context, a),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(
      BuildContext context, IconData icon, String label, String value) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: p.textMuted),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(label,
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          ),
          Expanded(
            child: SelectableText(value,
                style: AppText.body(size: 13).copyWith(color: p.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _detailActions(BuildContext context, AdminModel a) {
    final s = a.status.toLowerCase();
    final buttons = <Widget>[];

    void add(String label, Color color, VoidCallback onTap) {
      buttons.add(OutlinedButton(
        onPressed: () {
          Get.back();
          onTap();
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: Text(label),
      ));
    }

    if (s == 'pending') add("Approve", _cActive, () => ctrl.approve(a.docId));
    if (s == 'warning' || s == 'blocked') {
      add("Reactivate", _cActive, () => ctrl.reactivate(a.docId));
    }
    if (s == 'active' || s == 'pending') {
      add("Warn", _cWarning, () {
        _reasonDialog(context,
            title: 'Issue a warning',
            hint: 'Reason shown to the organization',
            confirmLabel: 'Send warning',
            confirmColor: _cWarning,
            onConfirm: (r) => ctrl.warn(a.docId, r));
      });
    }
    if (s != 'blocked') {
      add("Block", _cBlocked, () {
        _reasonDialog(context,
            title: 'Block organization',
            hint: 'Reason for blocking',
            confirmLabel: 'Block',
            confirmColor: _cBlocked,
            onConfirm: (r) => ctrl.block(a.docId, r));
      });
    }

    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }

  // ── REASON DIALOG ───────────────────────────────────────────────────
  void _reasonDialog(
    BuildContext context, {
    required String title,
    required String hint,
    required String confirmLabel,
    required Color confirmColor,
    required void Function(String reason) onConfirm,
  }) {
    final p = context.palette;
    final reasonCtrl = TextEditingController();
    Get.dialog(
      Dialog(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        AppText.title(size: 19).copyWith(color: p.textPrimary)),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 3,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: hint,
                    filled: true,
                    fillColor: p.inputFill,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadii.smR,
                      borderSide: BorderSide(color: p.border),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child:
                          Text("Cancel", style: TextStyle(color: p.textMuted)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final r = reasonCtrl.text.trim();
                        Get.back();
                        onConfirm(r);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadii.mdR),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── SHARED ──────────────────────────────────────────────────────────
  Widget _statusChip(String status) {
    final c = _statusColor(status);
    final label = status.isEmpty
        ? "unknown"
        : "${status[0].toUpperCase()}${status.substring(1).toLowerCase()}";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: AppText.label(size: 11).copyWith(color: c)),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, String name, {double size = 38}) {
    final p = context.palette;
    final letter = name.trim().isEmpty ? "?" : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(letter,
          style: AppText.label(size: size * 0.4).copyWith(color: p.accent)),
    );
  }

  Widget _empty(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.business_outlined,
              size: 40, color: p.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text("No organizations found",
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Text("Gyms that sign up (or match your filter) appear here.",
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        ],
      ),
    );
  }
}
