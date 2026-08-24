import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/admin_controller.dart';
import '../controllers/subscription_controller.dart';
import '../core/constants/firestore_collections.dart';
import '../core/utils/console_errors.dart';
import '../models/admin_model.dart';
import '../models/subscription_plan_model.dart';
import '../models/audit_log_model.dart';
import '../widgets/page_shell.dart';
import '../core/widgets/console/console_chrome.dart';

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
      // "0 total" during a failed load is the same lie as an empty list.
      trailing: Obx(
        () => Text(
          ctrl.loadError.value != null ? "—" : "${ctrl.admins.length} total",
          style: AppText.body(
            size: 13,
          ).copyWith(color: context.palette.textMuted),
        ),
      ),
      child: Obx(() {
        // The classified failure comes BEFORE everything else, toolbar
        // included: an undeployed rule and an empty platform must never look
        // alike, and a filter chip reading "Pending 0" over a failed load is
        // that same claim of absence in miniature.
        final err = ctrl.loadError.value;
        if (err != null) {
          return ConsoleErrorState(error: err, onRetry: ctrl.retryLoad);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toolbar(context),
            // MODERATION IS A ROUND TRIP, so say so. Without this the console
            // looked inert between the tap and the stream update, which is
            // what invited the second tap that wrote a second audit row.
            Obx(
              () => ctrl.isProcessing.value
                  ? const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text('Applying the moderation change…'),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
            Obx(() {
              if (ctrl.isLoading.value && ctrl.admins.isEmpty) {
                return const SizedBox(
                  height: 240,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
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
        );
      }),
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
        Obx(
          () => Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _chip(context, "All", "all", ctrl.admins.length),
              _chip(context, "Active", "active", ctrl.countByStatus("active")),
              _chip(
                context,
                "Pending",
                "pending",
                ctrl.countByStatus("pending"),
              ),
              _chip(
                context,
                "Warning",
                "warning",
                ctrl.countByStatus("warning"),
              ),
              _chip(
                context,
                "Blocked",
                "blocked",
                ctrl.countByStatus("blocked"),
              ),
            ],
          ),
        ),
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
            Text(
              label,
              style: AppText.label(
                size: 13,
              ).copyWith(color: selected ? accent : p.textSecondary),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? accent.withValues(alpha: 0.18) : p.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                "$count",
                style: AppText.label(
                  size: 11,
                ).copyWith(color: selected ? accent : p.textMuted),
              ),
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
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label(
                              size: 14,
                            ).copyWith(color: p.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(a.status),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      a.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: p.textMuted),
                    ),
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
      return Row(
        children: [
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
        ],
      );
    }
    return Row(
      children: [
        Icon(Icons.cancel_outlined, size: 13, color: p.textMuted),
        const SizedBox(width: 5),
        Text(
          "No active subscription",
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
      ],
    );
  }

  Widget _actionsMenu(BuildContext context, AdminModel a) {
    final p = context.palette;
    final s = a.status.toLowerCase();
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: p.textMuted),
      position: PopupMenuPosition.under,
      // Closed while a moderation call is in flight. `AdminController` already
      // refuses the re-entry; this stops the founder attempting it.
      enabled: !ctrl.isProcessing.value,
      onSelected: (v) => _onAction(context, a, v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'view', child: Text('View details')),
        if (s == 'pending')
          const PopupMenuItem(value: 'approve', child: Text('Approve')),
        if (s == 'active' || s == 'pending')
          const PopupMenuItem(value: 'warn', child: Text('Issue warning')),
        if (s == 'warning' || s == 'blocked')
          const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
        // Renewal / plan change — the OTHER half of the SaaS commercial flow.
        // Provisioning creates the first grant from an access request; every
        // later off-platform payment is recorded here. Hidden while blocked:
        // the backend refuses to grant a blocked org, so offering it would be
        // a button whose write is always refused (reactivate first).
        if (s != 'blocked')
          const PopupMenuItem(
            value: 'grant',
            child: Text('Grant / renew subscription'),
          ),
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
      case 'grant':
        _grantDialog(context, a);
        break;
      case 'warn':
        _reasonDialog(
          context,
          title: 'Issue a warning',
          subtitle:
              'INTERNAL ONLY. A warning changes nothing for the organization — '
              'they keep full access and are not notified. This reason is '
              'visible to you here and in the audit log, and nowhere else.',
          hint: 'Why is this warning being issued?',
          confirmLabel: 'Send warning',
          confirmColor: _cWarning,
          onConfirm: (r) => ctrl.warn(a.docId, r),
        );
        break;
      case 'block':
        _reasonDialog(
          context,
          title: 'Block organization',
          subtitle:
              'Blocking disables the owner\'s sign-in and stops the organization writing anything. They are notified that they are blocked — but not why, so record the reason here for your own trail.',
          hint: 'Why is this organization being blocked?',
          confirmLabel: 'Block',
          confirmColor: _cBlocked,
          onConfirm: (r) => ctrl.block(a.docId, r),
        );
        break;
    }
  }

  // ── GRANT / RENEW DIALOG ────────────────────────────────────────────
  //
  // Mirrors the provisioning dialog in access_requests_screen.dart: plan
  // picker + term + the off-platform payment evidence. The reference is the
  // idempotency key — the backend refuses a reused one, so a double-submit
  // cannot double-extend an expiry. The term field is a CONTROLLER (not
  // initialValue) so switching plans visibly rewrites it — the provisioning
  // dialog's initialValue variant left the old number on screen while the
  // internal value changed underneath it.
  void _grantDialog(BuildContext context, AdminModel a) {
    final plans = Get.find<SubscriptionController>()
        .plans
        .where((pl) => pl.status == PlanStatus.published)
        .toList();
    if (plans.isEmpty) {
      Get.snackbar('No plans', 'Publish a plan in Subscriptions first.');
      return;
    }
    var planId = plans.first.docId;
    final monthsCtl =
        TextEditingController(text: '${plans.first.durationMonths}');
    final refCtl = TextEditingController();
    final amountCtl = TextEditingController();
    final name = a.organizationName.isNotEmpty ? a.organizationName : a.name;

    showDialog<void>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: Text('Grant subscription — $name'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Records a payment the team already collected outside the '
                  'platform and extends or changes the plan. An active '
                  'subscription is extended from its current expiry; a lapsed '
                  'one restarts from today.',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: planId,
                  decoration:
                      const InputDecoration(labelText: 'Trainersarena plan'),
                  items: plans
                      .map((pl) => DropdownMenuItem(
                            value: pl.docId,
                            child:
                                Text('${pl.planName} · ${pl.durationMonths} mo'),
                          ))
                      .toList(),
                  onChanged: (v) => setLocal(() {
                    planId = v ?? planId;
                    monthsCtl.text =
                        '${plans.firstWhere((pl) => pl.docId == planId).durationMonths}';
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: monthsCtl,
                  decoration: const InputDecoration(
                    labelText: 'Term (months)',
                    helperText:
                        'Defaults to the plan term; override for a negotiated term',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: refCtl,
                  decoration: const InputDecoration(
                    labelText: 'Payment reference (Razorpay id / bank ref)',
                    helperText:
                        'Also the idempotency key — reused references are refused',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtl,
                  decoration:
                      const InputDecoration(labelText: 'Amount collected (₹)'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final months = int.tryParse(monthsCtl.text.trim());
                final amount = double.tryParse(amountCtl.text.trim());
                if (refCtl.text.trim().isEmpty ||
                    months == null ||
                    months <= 0 ||
                    amount == null) {
                  Get.snackbar('Missing details',
                      'Plan term, payment reference and amount are required.');
                  return;
                }
                Navigator.of(dctx).pop();
                ctrl.grantSubscription(
                  adminUid: a.docId,
                  planId: planId,
                  months: months,
                  reference: refCtl.text,
                  amount: amount,
                );
              },
              child: const Text('Grant'),
            ),
          ],
        ),
      ),
    );
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
                          Text(
                            name,
                            style: AppText.title(
                              size: 20,
                            ).copyWith(color: p.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Owner: ${a.name}",
                            style: AppText.body(
                              size: 13,
                            ).copyWith(color: p.textMuted),
                          ),
                        ],
                      ),
                    ),
                    _statusChip(a.status),
                  ],
                ),
                const SizedBox(height: 20),
                _detail(context, Icons.email_outlined, "Email", a.email),
                _detail(
                  context,
                  Icons.phone_outlined,
                  "Phone",
                  a.phone.isEmpty ? "—" : a.phone,
                ),
                if ((a.address ?? '').isNotEmpty)
                  _detail(
                    context,
                    Icons.location_on_outlined,
                    "Address",
                    a.address!,
                  ),
                _detail(
                  context,
                  Icons.workspace_premium_outlined,
                  "Subscription",
                  a.isSubscriptionActive
                      ? "${a.planName ?? 'Active'}${a.planExpiry != null ? ' · expires ${DateFormat('d MMM yyyy').format(a.planExpiry!)}' : ''}"
                      : "No active subscription",
                ),
                _detail(
                  context,
                  Icons.groups_outlined,
                  "Plan limits",
                  "${l.maxTrainers} trainers · ${l.maxClients} clients",
                ),
                _detail(
                  context,
                  Icons.calendar_today_outlined,
                  "Joined",
                  DateFormat('d MMM yyyy').format(a.createdAt),
                ),
                if (a.lastLogin != null)
                  _detail(
                    context,
                    Icons.login_outlined,
                    "Last login",
                    DateFormat('d MMM yyyy, h:mm a').format(a.lastLogin!),
                  ),
                _detail(
                  context,
                  Icons.verified_user_outlined,
                  "Verified",
                  a.isVerified ? "Yes" : "No",
                ),
                if ((a.gstNumber ?? '').isNotEmpty)
                  _detail(
                    context,
                    Icons.receipt_long_outlined,
                    "GST",
                    a.gstNumber!,
                  ),
                if ((a.panNumber ?? '').isNotEmpty)
                  _detail(context, Icons.badge_outlined, "PAN", a.panNumber!),
                // ── Moderation trail (traceability: who moderated, when, why) ──
                if ((a.approvedBy ?? '').isNotEmpty)
                  _detail(
                    context,
                    Icons.how_to_reg_outlined,
                    "Approved by",
                    a.approvedBy!,
                  ),
                if ((a.statusReason ?? '').isNotEmpty)
                  _detail(
                    context,
                    Icons.gpp_maybe_outlined,
                    "Status note",
                    a.statusReason!,
                  ),
                if (a.statusUpdatedAt != null)
                  _detail(
                    context,
                    Icons.update_outlined,
                    "Status updated",
                    "${DateFormat('d MMM yyyy, h:mm a').format(a.statusUpdatedAt!)}"
                        "${(a.statusUpdatedBy ?? '').isNotEmpty ? ' · by ${_short(a.statusUpdatedBy!)}' : ''}",
                  ),
                const SizedBox(height: 18),
                Text(
                  "ACTIVITY (AUDIT TRAIL)",
                  style: AppText.label(size: 11).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 8),
                _auditTrail(context, a),
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
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
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
            child: Text(
              label,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: AppText.body(size: 13).copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Per-org AUDIT TRAIL — reads the existing server-written `audit_logs`
  //    (targetId == this org's uid). Read-only, index-free (equality + client
  //    sort), and degrades gracefully so the dialog never breaks.
  Widget _auditTrail(BuildContext context, AdminModel a) {
    final p = context.palette;
    final orgId = a.uid.isNotEmpty ? a.uid : a.docId;
    return FutureBuilder<({List<AuditLogModel> logs, ConsoleError? error})>(
      future: _loadOrgAudit(orgId),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        // An UNREAD record is not an EMPTY one. Kept to one line rather than a
        // full ConsoleErrorState: this is a section inside a detail dialog, and
        // the classified reason is what the operator actually needs.
        final err = snap.data?.error;
        if (err != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 14, color: p.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The audit trail could not be loaded, so this organization '
                  'may have recorded actions that are not shown. '
                  '${err.message}',
                  style: AppText.body(size: 12).copyWith(color: p.error),
                ),
              ),
            ],
          );
        }
        final logs = snap.data?.logs ?? const <AuditLogModel>[];
        if (logs.isEmpty) {
          return Text(
            "No recorded platform actions for this organization yet.",
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in logs.take(15))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.bolt, size: 14, color: p.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "${l.actionLabel} · by ${l.displayActor}"
                        "${l.createdAt != null ? ' · ${DateFormat('d MMM, h:mm a').format(l.createdAt!)}' : ''}",
                        style: AppText.body(
                          size: 12,
                        ).copyWith(color: p.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// The org's audit trail, WITH whether the read succeeded.
  ///
  /// 🔴 The failure used to be swallowed into an empty list, and the dialog
  /// rendered "No recorded platform actions for this organization yet." — a
  /// statement about the compliance record made on the strength of a read that
  /// did not happen. A denied rule, a missing index and a genuinely
  /// unmoderated organization were the same sentence, on the one surface whose
  /// whole purpose is answering "who did this, and when".
  ///
  /// Still never throws: not crashing the dialog was the right half of the
  /// original decision. What changes is that `failed` now travels with the
  /// (empty) list, so the caller can say "could not be loaded" instead of
  /// "there is nothing".
  Future<({List<AuditLogModel> logs, ConsoleError? error})> _loadOrgAudit(
    String orgId,
  ) async {
    if (orgId.isEmpty) return (logs: const <AuditLogModel>[], error: null);
    try {
      final snap = await FirebaseFirestore.instance
          .collection(FsCollections.auditLogs)
          .where('targetId', isEqualTo: orgId)
          .limit(25)
          .get();
      final list = snap.docs.map(AuditLogModel.fromSnapshot).toList()
        ..sort(
          (x, y) => (y.createdAt ?? DateTime(0)).compareTo(
            x.createdAt ?? DateTime(0),
          ),
        );
      return (logs: list, error: null);
    } catch (e) {
      // e.g. rule/index not yet deployed — never crash the dialog, but never
      // report the record as empty either.
      debugPrint('audit_logs read failed for $orgId: $e');
      return (
        logs: const <AuditLogModel>[],
        error: describeStreamError(e, subject: "this organization's audit trail"),
      );
    }
  }

  String _short(String uid) =>
      uid.length <= 10 ? uid : '${uid.substring(0, 10)}…';

  Widget _detailActions(BuildContext context, AdminModel a) {
    final s = a.status.toLowerCase();
    final buttons = <Widget>[];

    void add(String label, Color color, VoidCallback onTap) {
      buttons.add(
        OutlinedButton(
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
        ),
      );
    }

    if (s == 'pending') add("Approve", _cActive, () => ctrl.approve(a.docId));
    if (s == 'warning' || s == 'blocked') {
      add("Reactivate", _cActive, () => ctrl.reactivate(a.docId));
    }
    if (s == 'active' || s == 'pending') {
      add("Warn", _cWarning, () {
        _reasonDialog(
          context,
          title: 'Issue a warning',
          subtitle:
              'INTERNAL ONLY. A warning changes nothing for the organization — '
              'they keep full access and are not notified. This reason is '
              'visible to you here and in the audit log, and nowhere else.',
          hint: 'Why is this warning being issued?',
          confirmLabel: 'Send warning',
          confirmColor: _cWarning,
          onConfirm: (r) => ctrl.warn(a.docId, r),
        );
      });
    }
    if (s != 'blocked') {
      add("Block", _cBlocked, () {
        _reasonDialog(
          context,
          title: 'Block organization',
          subtitle:
              'Blocking disables the owner\'s sign-in and stops the organization writing anything. They are notified that they are blocked — but not why, so record the reason here for your own trail.',
          hint: 'Why is this organization being blocked?',
          confirmLabel: 'Block',
          confirmColor: _cBlocked,
          onConfirm: (r) => ctrl.block(a.docId, r),
        );
      });
    }

    return Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }

  // ── REASON DIALOG ───────────────────────────────────────────────────
  /// The reason prompt behind Warn and Block.
  ///
  /// [subtitle] states what the action ACTUALLY does. It exists because this
  /// dialog used to promise "Reason shown to the organization" — and nothing
  /// anywhere shows it.
  ///
  /// `warning` IS AN INTERNAL LABEL, and that is the product's intent rather
  /// than an unfinished feature. The evidence, traced end to end:
  ///
  ///   • TrainerHQ's own `AccountStatus` vocabulary (core/models/enums.dart)
  ///     lists pending / approved / active / blocked / inactive / removed.
  ///     `warning` is not in it, so the organization app has no such state.
  ///   • `orgCanOperate()` in firestore.rules gates on pending and blocked
  ///     only — a warned org keeps full access, by rule.
  ///   • `orgStatusEvent()` returns null for warning, so no notification is
  ///     ever produced.
  ///   • `grep statusReason` across TrainerHQ and the member app: no hits.
  ///
  /// So the copy says "internal only" rather than inventing a delivery path.
  /// The one place the code disagreed — `setAdminStatus` emitted the
  /// "Organization approved" automation trigger for every non-blocked status,
  /// warning included — was closed in `lib/admin_status_effects.ts`
  /// (`automationTriggerFor`), because this promise is only true if nothing
  /// downstream contacts the organization.
  ///
  /// The reason is REQUIRED. A moderation record with no stated reason is
  /// indistinguishable from a mistake three weeks later — the same argument the
  /// settlement engine already makes for a payout hold.
  void _reasonDialog(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String hint,
    required String confirmLabel,
    required Color confirmColor,
    required void Function(String reason) onConfirm,
  }) {
    final p = context.palette;
    final reasonCtrl = TextEditingController();
    Get.dialog(
      barrierDismissible: false,
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
                Text(
                  title,
                  style: AppText.title(size: 19).copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppText.body(
                    size: 12.5,
                  ).copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: 16),
                StatefulBuilder(
                  builder: (context, setState) {
                    final reason = reasonCtrl.text.trim();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: reasonCtrl,
                          maxLines: 3,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
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
                              child: Text(
                                "Cancel",
                                style: TextStyle(color: p.textMuted),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              // Disabled until a reason exists — see the note
                              // on this method.
                              onPressed: reason.isEmpty
                                  ? null
                                  : () {
                                      Get.back();
                                      onConfirm(reason);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: confirmColor,
                                foregroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: AppRadii.mdR,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              child: Text(confirmLabel),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
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
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
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
      child: Text(
        letter,
        style: AppText.label(size: size * 0.4).copyWith(color: p.accent),
      ),
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
          Icon(
            Icons.business_outlined,
            size: 40,
            color: p.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            "No organizations found",
            style: AppText.label(size: 14).copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            "Gyms that sign up (or match your filter) appear here.",
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }
}
