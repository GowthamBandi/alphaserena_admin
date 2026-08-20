// lib/screens/access_requests_screen.dart
//
// ACCESS REQUESTS — the intake and provisioning surface for TrainerArena SaaS.
//
// This is where TrainerArena's commercial flow lives now that the app no
// longer sells itself:
//
//   prospect submits  →  team contacts  →  payment link over WhatsApp  →
//   payment confirmed here  →  organization provisioned  →  temporary
//   credentials delivered  →  the org signs in to TrainerArena
//
// Every action calls a Cloud Function. `access_requests` denies client writes
// to everyone — super admins included — so the transition matrix and the
// provisioning idempotency key are enforced server-side, not by this UI.
//
// ⚠️ DOMAIN A. This screen is about TrainersArena's OWN subscription revenue.
// It must never share a surface with Settlements (index 14), which is member
// money the platform holds on organizations' behalf.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/access_request_controller.dart';
import '../controllers/subscription_controller.dart';
import '../core/services/saas_onboarding_service.dart';
import '../models/access_request_model.dart';
import '../models/subscription_plan_model.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/page_shell.dart';

class AccessRequestsScreen extends StatelessWidget {
  AccessRequestsScreen({super.key});

  final AccessRequestController ctrl = Get.find<AccessRequestController>();

  static final _dateFmt = DateFormat('d MMM yyyy, h:mm a');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Access Requests',
      icon: Icons.mark_email_unread_outlined,
      trailing: Obx(() => Text(
            ctrl.isLoading.value ? '—' : '${ctrl.openCount} open',
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Organizations asking for TrainersArena access. Contact them, take '
            'payment outside the platform, record it here, then provision the '
            'organization and send the temporary credentials.',
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          _filters(context),
          const SizedBox(height: 16),
          // NOT Expanded: PageShell hosts its child inside a
          // SingleChildScrollView, so height is unbounded here — an Expanded
          // child throws at layout and the whole page renders BLANK. Found by
          // driving the real console against the emulator (2026-08-20); the
          // widget test gave the screen bounded constraints and passed.
          Obx(() => _list(context)),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => ctrl.search.value = v,
            decoration: InputDecoration(
              hintText: 'Search organization, owner, email or phone',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Obx(() => DropdownButton<String>(
              value: ctrl.statusFilter.value,
              underline: const SizedBox(),
              items: [
                const DropdownMenuItem(value: 'open', child: Text('Open')),
                const DropdownMenuItem(value: 'all', child: Text('All')),
                ...[
                  SaasOnboardingService.requested,
                  SaasOnboardingService.contacted,
                  SaasOnboardingService.paymentPending,
                  SaasOnboardingService.paymentConfirmed,
                  SaasOnboardingService.approved,
                  SaasOnboardingService.organizationCreated,
                  SaasOnboardingService.rejected,
                ].map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(SaasOnboardingService.label(s)),
                    )),
              ],
              onChanged: (v) => ctrl.statusFilter.value = v ?? 'open',
            )),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Refresh',
          onPressed: ctrl.retryLoad,
          icon: Icon(Icons.refresh, color: p.textMuted),
        ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    final p = context.palette;
    if (ctrl.isLoading.value) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final err = ctrl.loadError.value;
    if (err != null) {
      // A failed stream must never render as "no requests yet" — that reads
      // as "nobody wants the product" and invites the founder to do nothing.
      return SizedBox(
        height: 280,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: p.textMuted),
              const SizedBox(height: 12),
              Text(err.message, style: AppText.body(size: 13)),
              if (err.remedy != null) ...[
                const SizedBox(height: 6),
                Text(err.remedy!,
                    style: AppText.body(size: 12)
                        .copyWith(color: p.textMuted)),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: ctrl.retryLoad,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final items = ctrl.filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          ctrl.requests.isEmpty
              ? 'No access requests yet.'
              : 'No requests match this filter.',
          style: AppText.body(size: 13).copyWith(color: p.textMuted),
        ),
      );
    }
    return ListView.separated(
      // The page scrolls as one surface (PageShell's scroll view); this list
      // must shrink-wrap rather than claim a viewport of its own.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _RequestCard(
        request: items[i],
        onOpen: () => _openDetail(context, items[i]),
      ),
    );
  }

  void _openDetail(BuildContext context, AccessRequestModel r) {
    showDialog<void>(
      context: context,
      builder: (_) => _RequestDetailDialog(request: r, ctrl: ctrl),
    );
  }

  static String formatDate(DateTime? d) =>
      d == null ? '—' : _dateFmt.format(d);
}

Color _statusColor(String status, BuildContext context) {
  final p = context.palette;
  return switch (status) {
    SaasOnboardingService.requested => const Color(0xFF6A6F7A),
    SaasOnboardingService.contacted => const Color(0xFF3B6FD4),
    SaasOnboardingService.paymentPending => const Color(0xFFB8860B),
    SaasOnboardingService.paymentConfirmed => const Color(0xFF1A7F5A),
    SaasOnboardingService.approved => const Color(0xFF1A7F5A),
    SaasOnboardingService.organizationCreated => const Color(0xFF2E7D32),
    SaasOnboardingService.rejected => const Color(0xFFB3261E),
    _ => p.textMuted,
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = _statusColor(status, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        SaasOnboardingService.label(status),
        style: AppText.body(size: 11).copyWith(
          color: c,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onOpen});
  final AccessRequestModel request;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          request.organizationName.isEmpty
                              ? '(no organization name)'
                              : request.organizationName,
                          style: AppText.title(size: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StatusChip(request.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${request.ownerName}  ·  ${request.contactLine}',
                    style:
                        AppText.body(size: 12).copyWith(color: p.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (request.locationLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      request.locationLine,
                      style:
                          AppText.body(size: 12).copyWith(color: p.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              AccessRequestsScreen.formatDate(request.createdAt),
              style: AppText.body(size: 11).copyWith(color: p.textMuted),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// DETAIL + ACTIONS
// ───────────────────────────────────────────────────────────────────────────

class _RequestDetailDialog extends StatefulWidget {
  const _RequestDetailDialog({required this.request, required this.ctrl});
  final AccessRequestModel request;
  final AccessRequestController ctrl;

  @override
  State<_RequestDetailDialog> createState() => _RequestDetailDialogState();
}

class _RequestDetailDialogState extends State<_RequestDetailDialog> {
  final _note = TextEditingController();

  /// Always read the LIVE row, so an action taken in this dialog is reflected
  /// immediately and a stale snapshot can never drive the next decision.
  AccessRequestModel get _r => widget.ctrl.requests.firstWhere(
        (e) => e.id == widget.request.id,
        orElse: () => widget.request,
      );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Obx(() {
          final r = _r;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.organizationName,
                              style: AppText.title(size: 18)),
                          const SizedBox(height: 4),
                          _StatusChip(r.status),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kv(context, 'Owner', r.ownerName),
                      _kv(context, 'Email', r.email),
                      _kv(context, 'Phone', r.phone),
                      if (r.whatsapp.isNotEmpty && r.whatsapp != r.phone)
                        _kv(context, 'WhatsApp', r.whatsapp),
                      if (r.locationLine.isNotEmpty)
                        _kv(context, 'Location', r.locationLine),
                      if (r.teamSize != null)
                        _kv(context, 'Team size', '${r.teamSize}'),
                      if (r.message.isNotEmpty)
                        _kv(context, 'Message', r.message),
                      _kv(context, 'Received',
                          AccessRequestsScreen.formatDate(r.createdAt)),
                      if (r.paymentEvidence != null) ...[
                        const SizedBox(height: 12),
                        _paymentPanel(context, r.paymentEvidence!),
                      ],
                      if (r.isProvisioned) ...[
                        const SizedBox(height: 12),
                        _provisionedPanel(context, r),
                      ],
                      const SizedBox(height: 16),
                      _notesPanel(context, r),
                      const SizedBox(height: 16),
                      _historyPanel(context, r),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.ctrl.actionError.value != null) ...[
                      Text(
                        widget.ctrl.actionError.value!,
                        style: AppText.body(size: 12)
                            .copyWith(color: const Color(0xFFB3261E)),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _actions(context, r),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style:
                    AppText.body(size: 12).copyWith(color: p.textMuted)),
          ),
          Expanded(child: SelectableText(v, style: AppText.body(size: 13))),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, String title, List<Widget> children,
      {Color? tint}) {
    final p = context.palette;
    final c = tint ?? p.border;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppText.body(size: 12).copyWith(
                  fontWeight: FontWeight.w700, color: p.textMuted)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _paymentPanel(BuildContext context, AccessRequestPayment e) =>
      _panel(context, 'PAYMENT RECORDED', [
        _kv(context, 'Reference', e.reference),
        _kv(context, 'Amount', '₹${e.amount.toStringAsFixed(2)}'),
        if (e.note.isNotEmpty) _kv(context, 'Note', e.note),
        _kv(context, 'Confirmed',
            AccessRequestsScreen.formatDate(e.confirmedAt)),
      ], tint: const Color(0xFF1A7F5A));

  Widget _provisionedPanel(BuildContext context, AccessRequestModel r) =>
      _panel(context, 'ORGANIZATION CREATED', [
        _kv(context, 'Org UID', r.provisionedOrgUid ?? '—'),
        _kv(context, 'Created',
            AccessRequestsScreen.formatDate(r.provisionedAt)),
        Text(
          'The temporary password was shown once, at provisioning, and is '
          'stored nowhere. If it was lost, the owner uses "Forgot password" '
          'on the TrainersArena sign-in screen.',
          style: AppText.body(size: 11)
              .copyWith(color: context.palette.textMuted),
        ),
      ], tint: const Color(0xFF2E7D32));

  Widget _notesPanel(BuildContext context, AccessRequestModel r) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('INTERNAL NOTES',
            style: AppText.body(size: 12).copyWith(
                fontWeight: FontWeight.w700, color: p.textMuted)),
        const SizedBox(height: 8),
        if (r.notes.isEmpty)
          Text('None yet.',
              style: AppText.body(size: 12).copyWith(color: p.textMuted))
        else
          ...r.notes.map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${n.text}  (${AccessRequestsScreen.formatDate(n.at)})',
                  style: AppText.body(size: 12),
                ),
              )),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _note,
                decoration: const InputDecoration(
                  hintText: 'Add an internal note',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: widget.ctrl.isProcessing.value
                  ? null
                  : () async {
                      final ok =
                          await widget.ctrl.addNote(r.id, _note.text);
                      if (ok) _note.clear();
                    },
              child: const Text('Add'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _historyPanel(BuildContext context, AccessRequestModel r) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('HISTORY',
            style: AppText.body(size: 12).copyWith(
                fontWeight: FontWeight.w700, color: p.textMuted)),
        const SizedBox(height: 8),
        ...r.statusHistory.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${SaasOnboardingService.label(h.status)} · '
                '${AccessRequestsScreen.formatDate(h.at)}'
                '${h.note.isNotEmpty ? ' — ${h.note}' : ''}',
                style:
                    AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
            )),
      ],
    );
  }

  Widget _actions(BuildContext context, AccessRequestModel r) {
    final busy = widget.ctrl.isProcessing.value;

    if (r.isProvisioned) {
      // Terminal. Nothing here may create a second organization, and the
      // server refuses anyway — but an enabled button that always fails is
      // its own defect.
      return Text(
        'This request has been provisioned. Manage the organization from '
        'the Admins section.',
        style: AppText.body(size: 12)
            .copyWith(color: context.palette.textMuted),
      );
    }

    final canProvision = r.status == SaasOnboardingService.paymentConfirmed ||
        r.status == SaasOnboardingService.approved;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (r.status == SaasOnboardingService.requested)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => widget.ctrl
                    .setStatus(r.id, SaasOnboardingService.contacted),
            child: const Text('Mark contacted'),
          ),
        if (r.status == SaasOnboardingService.requested ||
            r.status == SaasOnboardingService.contacted)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => widget.ctrl
                    .setStatus(r.id, SaasOnboardingService.paymentPending),
            child: const Text('Payment pending'),
          ),
        if (r.status != SaasOnboardingService.paymentConfirmed &&
            r.status != SaasOnboardingService.approved &&
            r.status != SaasOnboardingService.rejected)
          FilledButton.tonal(
            onPressed: busy ? null : () => _confirmPayment(context, r),
            child: const Text('Confirm payment'),
          ),
        if (r.status != SaasOnboardingService.rejected)
          TextButton(
            onPressed: busy
                ? null
                : () => widget.ctrl
                    .setStatus(r.id, SaasOnboardingService.rejected),
            child: const Text('Reject'),
          ),
        if (r.status == SaasOnboardingService.rejected)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => widget.ctrl
                    .setStatus(r.id, SaasOnboardingService.requested),
            child: const Text('Reopen'),
          ),
        FilledButton(
          onPressed: (busy || !canProvision)
              ? null
              : () => _provision(context, r),
          child: Text(busy ? 'Working…' : 'Create organization'),
        ),
      ],
    );
  }

  Future<void> _confirmPayment(
      BuildContext context, AccessRequestModel r) async {
    final refCtl = TextEditingController();
    final amtCtl = TextEditingController();
    final noteCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Confirm payment received'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Record the payment the team already collected. This is '
              'evidence of a payment taken outside the platform — it moves '
              'no money and never enters member settlements.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refCtl,
              decoration: const InputDecoration(
                labelText: 'Payment reference (Razorpay id / bank ref)',
                helperText: 'Also the idempotency key — reused references '
                    'are refused',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: amtCtl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Amount collected (₹)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtl,
              decoration:
                  const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(amtCtl.text.trim());
    if (refCtl.text.trim().isEmpty || amount == null) {
      widget.ctrl.actionError.value =
          'A payment reference and a numeric amount are both required.';
      return;
    }
    final done = await widget.ctrl.setStatus(
      r.id,
      SaasOnboardingService.paymentConfirmed,
      note: noteCtl.text,
      paymentReference: refCtl.text,
      paymentAmount: amount,
    );
    if (done) {
      AppSnackbar.show(
        title: 'Payment recorded',
        message: 'The request is ready to provision.',
        background: const Color(0xFF1A7F5A),
      );
    }
  }

  Future<void> _provision(
      BuildContext context, AccessRequestModel r) async {
    final plans = Get.find<SubscriptionController>()
        .plans
        .where((p) => p.status == PlanStatus.published)
        .toList();
    if (plans.isEmpty) {
      widget.ctrl.actionError.value =
          'No published plan to assign. Publish a plan in Subscriptions '
          'first.';
      return;
    }

    var planId = plans.first.docId;
    var months = plans.first.durationMonths;
    // A controller, not initialValue: switching plans must visibly rewrite
    // the term, or the screen shows one number while the grant uses another.
    final monthsCtl = TextEditingController(text: '$months');
    final emailCtl = TextEditingController(text: r.email);
    final ownerCtl = TextEditingController(text: r.ownerName);
    final orgCtl = TextEditingController(text: r.organizationName);
    final phoneCtl = TextEditingController(text: r.phone);

    final go = await showDialog<bool>(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setLocal) => AlertDialog(
          title: const Text('Create organization'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Creates the Firebase Auth account, the organization '
                    'record, and the subscription — then shows a temporary '
                    'password ONCE. It is stored nowhere.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: planId,
                    decoration:
                        const InputDecoration(labelText: 'TrainersArena plan'),
                    items: plans
                        .map((p) => DropdownMenuItem(
                              value: p.docId,
                              child: Text(
                                  '${p.planName} · ${p.durationMonths} mo'),
                            ))
                        .toList(),
                    onChanged: (v) => setLocal(() {
                      planId = v ?? planId;
                      months = plans
                          .firstWhere((p) => p.docId == planId)
                          .durationMonths;
                      monthsCtl.text = '$months';
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: monthsCtl,
                    decoration: const InputDecoration(
                      labelText: 'Term (months)',
                      helperText: 'Defaults to the plan term; override for a '
                          'negotiated term',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => months = int.tryParse(v) ?? months,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: orgCtl,
                    decoration:
                        const InputDecoration(labelText: 'Organization name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ownerCtl,
                    decoration:
                        const InputDecoration(labelText: 'Owner name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailCtl,
                    decoration: const InputDecoration(
                      labelText: 'Sign-in email',
                      helperText: 'This becomes their TrainersArena login',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneCtl,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (go != true) return;

    final res = await widget.ctrl.provision(
      requestId: r.id,
      planId: planId,
      months: months,
      email: emailCtl.text,
      ownerName: ownerCtl.text,
      organizationName: orgCtl.text,
      phone: phoneCtl.text,
    );
    if (res == null) return;
    if (!context.mounted) return;

    if (res.alreadyProvisioned) {
      // Honest: there is no second password, because there was no second
      // organization. Inventing one here would mean resetting a credential
      // the organization may already be using.
      await showDialog<void>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Already provisioned'),
          content: Text(
            'This request already created organization ${res.uid}. No second '
            'organization was created and no new password was issued.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    await _showCredentials(context, res);
  }

  /// The ONE time the temporary password is ever visible. It is not in
  /// Firestore, not in the audit log and not in this app's state after this
  /// dialog closes — so the copy says so plainly rather than letting the
  /// founder assume they can come back for it.
  Future<void> _showCredentials(
      BuildContext context, ProvisionResult res) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        title: const Text('Organization created'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send these credentials to the organization. THIS PASSWORD IS '
                'SHOWN ONCE — it is stored nowhere and cannot be retrieved. '
                'If it is lost, the owner uses "Forgot password" on the '
                'TrainersArena sign-in screen.',
              ),
              const SizedBox(height: 14),
              SelectableText('Email:  ${res.email ?? ''}',
                  style: AppText.body(size: 14)),
              const SizedBox(height: 6),
              SelectableText('Temporary password:  ${res.tempPassword ?? ''}',
                  style: AppText.title(size: 15)),
              const SizedBox(height: 10),
              Text('Access expires ${res.expiry ?? '—'}',
                  style: AppText.body(size: 12)
                      .copyWith(color: context.palette.textMuted)),
            ],
          ),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: 'TrainersArena sign-in\n'
                    'Email: ${res.email ?? ''}\n'
                    'Temporary password: ${res.tempPassword ?? ''}\n'
                    'Please change your password after signing in.',
              ));
              AppSnackbar.show(
                title: 'Copied',
                message: 'Credentials copied to the clipboard.',
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
