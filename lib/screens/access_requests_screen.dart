// lib/screens/access_requests_screen.dart
//
// ACCESS REQUESTS — where gyms ask to join Trainersarena, and the team turns a
// request into an organization.
//
// The pipeline, all of it server-enforced:
//   received → contacted → payment link sent → payment recorded → ORGANIZATION
//   CREATED (a sign-in, an organization record and a paid plan; one-time
//   password shown once). Any open request can be rejected; a rejected one
//   can be reopened. Nothing else exists (no cancel, expiry or revoke).
//
// The screen is a WORK QUEUE, not an archive: open requests are listed
// oldest-first because the one that has waited longest is the sale most at
// risk; completed ones newest-first. Every row says who, which gym, what they
// want, why, how long they have waited, what stage they are at and the one
// thing to do next. Identifiers live under "Technical details".
//
// ⚠️ DOMAIN A. This is Trainersarena's OWN subscription revenue. It must never
// share a surface with Settlements (member money the platform holds for gyms).

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../controllers/access_request_controller.dart';
import '../controllers/admin_controller.dart';
import '../controllers/admin_root_controller.dart';
import '../controllers/subscription_controller.dart';
import '../core/services/access_request_language.dart';
import '../core/services/saas_onboarding_service.dart';
import '../models/access_request_model.dart';
import '../models/subscription_plan_model.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/page_shell.dart';

const _cNew = Color(0xFF3B6FD4);
const _cTalking = Color(0xFF6C5CE7);
const _cReady = Color(0xFF1A7F5A);
const _cCreated = Color(0xFF2E7D32);
const _cRejected = Color(0xFFB3261E);
const _cOverdue = Color(0xFFD4341F);
const _cWaiting = Color(0xFFB06A00);
const _cMuted = Color(0xFF6A6F7A);

/// Sidebar destination of the Organizations screen (console_destinations.dart).
const int _navOrganizations = 1;

Color _groupColor(RequestGroup g) => switch (g) {
  RequestGroup.newRequests => _cNew,
  RequestGroup.inConversation => _cTalking,
  RequestGroup.readyToCreate => _cReady,
  RequestGroup.created => _cCreated,
  RequestGroup.rejected => _cRejected,
  RequestGroup.unknown => _cMuted,
};

IconData _groupIcon(RequestGroup g) => switch (g) {
  RequestGroup.newRequests => Icons.mark_email_unread_outlined,
  RequestGroup.inConversation => Icons.forum_outlined,
  RequestGroup.readyToCreate => Icons.verified_outlined,
  RequestGroup.created => Icons.check_circle_outline,
  RequestGroup.rejected => Icons.block_outlined,
  RequestGroup.unknown => Icons.help_outline,
};

class AccessRequestsScreen extends StatelessWidget {
  AccessRequestsScreen({super.key});

  final AccessRequestController ctrl = Get.find<AccessRequestController>();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: 'Access Requests',
      icon: Icons.mark_email_unread_outlined,
      trailing: Obx(() {
        // Guarded by isLoading / loadError: a count is a claim about data read.
        if (ctrl.isLoading.value) {
          return Text(
            'Loading…',
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          );
        }
        if (ctrl.loadError.value != null) {
          return Text(
            'Could not load',
            style: AppText.body(size: 13).copyWith(color: _cRejected),
          );
        }
        final n = ctrl.openCount;
        return Text(
          n == 0 ? 'Nothing waiting' : '$n need${n == 1 ? 's' : ''} attention',
          style: AppText.body(
            size: 13,
          ).copyWith(color: n == 0 ? _cReady : p.textMuted),
        );
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gyms asking to join Trainersarena. Contact them, record their '
            'payment, then create their organization account and send the '
            'sign-in details.',
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          _summary(context),
          const SizedBox(height: 16),
          _filters(context),
          const SizedBox(height: 14),
          // NOT Expanded: PageShell hosts its child inside a
          // SingleChildScrollView, so height is unbounded here — an Expanded
          // child throws at layout and the whole page renders BLANK.
          Obx(() => _list(context)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── SUMMARY TILES (each one a filter) ──────────────────────────────────
  Widget _summary(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoading.value || ctrl.loadError.value != null) {
        return const SizedBox.shrink();
      }
      final now = DateTime.now();
      final overdue = ctrl.overdueCount(now: now);
      final tiles = <_Tile>[
        _Tile(
          'new',
          'New',
          ctrl.groupCount(RequestGroup.newRequests),
          'Not yet contacted',
          _cNew,
          Icons.mark_email_unread_outlined,
        ),
        _Tile(
          'conversation',
          'In conversation',
          ctrl.groupCount(RequestGroup.inConversation),
          'Talking, or waiting for payment',
          _cTalking,
          Icons.forum_outlined,
        ),
        _Tile(
          'ready',
          'Ready to create',
          ctrl.groupCount(RequestGroup.readyToCreate),
          'Payment received — create their account',
          _cReady,
          Icons.verified_outlined,
        ),
        _Tile(
          'overdue',
          'Overdue',
          overdue,
          'Waiting ${AccessRequestLanguage.overdueAfterDays}+ days',
          _cOverdue,
          Icons.timer_off_outlined,
        ),
        _Tile(
          'created',
          'Created',
          ctrl.recentCount(RequestGroup.created, now: now),
          'Last ${AccessRequestLanguage.recentWindowDays} days',
          _cCreated,
          Icons.check_circle_outline,
        ),
        _Tile(
          'rejected',
          'Rejected',
          ctrl.recentCount(RequestGroup.rejected, now: now),
          'Last ${AccessRequestLanguage.recentWindowDays} days',
          _cRejected,
          Icons.block_outlined,
        ),
      ];
      final active = ctrl.statusFilter.value;
      return LayoutBuilder(
        builder: (_, box) {
          final perRow = box.maxWidth >= 1100
              ? 6
              : box.maxWidth >= 700
              ? 3
              : 2;
          final w = (box.maxWidth - 12 * (perRow - 1)) / perRow;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final t in tiles)
                SizedBox(width: w, child: _tile(context, t, active == t.key)),
            ],
          );
        },
      );
    });
  }

  Widget _tile(BuildContext context, _Tile t, bool active) {
    final p = context.palette;
    final lit = t.count > 0;
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: active,
        label:
            '${t.label}: ${t.count}. ${t.hint}. '
            '${active ? 'Filter active, tap to show everything waiting.' : 'Tap to show only these.'}',
        child: Tooltip(
          message: t.hint,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadii.cardR,
              onTap: () => ctrl.statusFilter.value = active ? 'open' : t.key,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: active ? t.color.withValues(alpha: 0.10) : p.surface,
                  borderRadius: AppRadii.cardR,
                  border: Border.all(
                    color: active
                        ? t.color
                        : (lit ? t.color.withValues(alpha: 0.4) : p.border),
                    width: active ? 1.5 : 1,
                  ),
                  boxShadow: AppShadows.card(p.isDark),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(
                        t.icon,
                        size: 18,
                        color: lit ? t.color : p.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${t.count}',
                              style: AppText.title(
                                size: 22,
                              ).copyWith(color: lit ? t.color : p.textMuted),
                            ),
                            Text(
                              t.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.body(
                                size: 12,
                              ).copyWith(color: p.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── FILTERS ────────────────────────────────────────────────────────────
  Widget _filters(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final f = ctrl.statusFilter.value;
      final searchText = ctrl.search.value;
      final hasFilters = ctrl.hasActiveFilters;
      final chips = <String>[
        'open',
        'new',
        'conversation',
        'ready',
        'created',
        'rejected',
        'all',
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in chips)
                MergeSemantics(
                  child: Semantics(
                    button: true,
                    selected: f == key,
                    label: '${AccessRequestLanguage.filterLabel(key)} filter',
                    child: ChoiceChip(
                      label: ExcludeSemantics(
                        child: Text(AccessRequestLanguage.filterLabel(key)),
                      ),
                      selected: f == key,
                      onSelected: (_) => ctrl.statusFilter.value = key,
                      showCheckmark: false,
                      selectedColor: p.accent.withValues(alpha: 0.12),
                      labelStyle: AppText.label(
                        size: 12,
                      ).copyWith(color: f == key ? p.accent : p.textSecondary),
                      side: BorderSide(color: f == key ? p.accent : p.border),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (_, box) {
              final field = _SearchField(
                initial: searchText,
                onChanged: (v) => ctrl.search.value = v,
              );
              final trailing = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasFilters)
                    TextButton(
                      onPressed: ctrl.clearFilters,
                      child: const Text('Clear filters'),
                    ),
                  Obx(() {
                    final at = ctrl.lastUpdatedAt.value;
                    return Text(
                      at == null
                          ? ''
                          : 'Live · updated ${AccessRequestLanguage.ago(at, now: DateTime.now())}',
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: p.textMuted),
                    );
                  }),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Reload the list',
                    child: IconButton(
                      onPressed: ctrl.retryLoad,
                      icon: Icon(Icons.refresh, size: 18, color: p.textMuted),
                    ),
                  ),
                ],
              );
              if (box.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [field, const SizedBox(height: 6), trailing],
                );
              }
              return Row(
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 12),
                  trailing,
                ],
              );
            },
          ),
        ],
      );
    });
  }

  // ── LIST ───────────────────────────────────────────────────────────────
  Widget _list(BuildContext context) {
    final p = context.palette;
    if (ctrl.isLoading.value) return _loading(context);

    final err = ctrl.loadError.value;
    if (err != null) {
      // A failed stream must never render as "no requests yet" — that reads
      // as "nobody wants the product" and invites the founder to do nothing.
      return _panel(
        context,
        icon: Icons.cloud_off_outlined,
        color: _cRejected,
        title: "We couldn't load access requests",
        body:
            '${err.message}${err.remedy != null ? '\n${err.remedy}' : ''}'
            '\nNothing on this screen is a decision until the list loads.',
        action: OutlinedButton.icon(
          onPressed: ctrl.retryLoad,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retry'),
        ),
      );
    }

    final items = ctrl.filtered;
    if (items.isEmpty) {
      if (ctrl.requests.isEmpty) {
        return _panel(
          context,
          icon: Icons.inbox_outlined,
          color: _cReady,
          title: 'No access requests yet',
          body:
              'When a gym asks to join Trainersarena from the app, their '
              'request appears here.',
        );
      }
      if (ctrl.hasActiveFilters) {
        return _panel(
          context,
          icon: Icons.filter_alt_off_outlined,
          color: p.textMuted,
          title: 'No requests match these filters',
          body:
              'There are ${ctrl.requests.length} request${ctrl.requests.length == 1 ? '' : 's'} in total. '
              'Change the stage or clear your search.',
          action: TextButton(
            onPressed: ctrl.clearFilters,
            child: const Text('Clear filters'),
          ),
        );
      }
      return _panel(
        context,
        icon: Icons.check_circle_outline,
        color: _cReady,
        title: "You're all caught up",
        body: 'There are no access requests waiting for review.',
      );
    }

    final now = DateTime.now();
    final unknown = items
        .where((r) => !AccessRequestLanguage.isKnownStatus(r.status))
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              '${items.length} request${items.length == 1 ? '' : 's'} · '
              '${AccessRequestLanguage.filterLabel(ctrl.statusFilter.value)}',
              style: AppText.label(size: 12).copyWith(color: p.textMuted),
            ),
            Text(
              ctrl.statusFilter.value == 'created' ||
                      ctrl.statusFilter.value == 'rejected'
                  ? 'Newest first'
                  : 'Longest waiting first',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ],
        ),
        if (unknown > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$unknown request${unknown == 1 ? ' has' : 's have'} a stage this '
              'console does not recognise — open them to see the stored value.',
              style: AppText.body(size: 12).copyWith(color: _cWaiting),
            ),
          ),
        const SizedBox(height: 10),
        for (final r in items) ...[
          _RequestRow(
            request: r,
            now: now,
            ctrl: ctrl,
            onOpen: () => _openDetail(context, r),
            onPrimary: () => _primaryAction(context, r),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _loading(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        for (int i = 0; i < 3; i++) ...[
          Container(
            height: 88,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.cardR,
              border: Border.all(color: p.border),
            ),
            alignment: Alignment.center,
            child: i == 1
                ? Semantics(
                    label: 'Loading requests',
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _panel(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    Widget? action,
  }) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Container(
            height: 56,
            width: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppText.title(size: 18).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    );
  }

  // ── ACTIONS (shared by row buttons and the detail dialog) ──────────────
  void _openDetail(BuildContext context, AccessRequestModel r) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _RequestDetailDialog(request: r, ctrl: ctrl, screen: this),
    );
  }

  Future<void> _primaryAction(
    BuildContext context,
    AccessRequestModel r,
  ) async {
    if (r.isProvisioned) return _openOrganization(r);
    switch (r.status) {
      case SaasOnboardingService.requested:
        await _move(
          r,
          SaasOnboardingService.contacted,
          done: 'Marked as contacted. The request moved to "In conversation".',
        );
      case SaasOnboardingService.contacted:
        await _move(
          r,
          SaasOnboardingService.paymentPending,
          done:
              'Recorded that the payment link was sent. The request stays '
              'under "In conversation" until the payment is recorded.',
        );
      case SaasOnboardingService.paymentPending:
        await recordPayment(context, r);
      case SaasOnboardingService.paymentConfirmed:
      case SaasOnboardingService.approved:
        await createOrganization(context, r);
      case SaasOnboardingService.rejected:
        await reopen(context, r);
      default:
        _openDetail(context, r);
    }
  }

  /// Opens the Organizations screen on the organization this request created.
  /// The created record is found by its id (`provisionedOrgUid`), because the
  /// founder may have edited the name or sign-in email at creation — the
  /// request's own values need not match. Falls back to the request's
  /// organization name, then email, when the record is not (yet) in the list.
  void _openOrganization(AccessRequestModel r) {
    if (Get.isRegistered<AdminController>()) {
      final a = Get.find<AdminController>();
      a.statusFilter.value = 'all';
      String query = '';
      for (final org in a.admins) {
        if (org.docId == r.provisionedOrgUid ||
            org.uid == r.provisionedOrgUid) {
          query = org.email.isNotEmpty ? org.email : org.organizationName;
          break;
        }
      }
      if (query.isEmpty) {
        query = r.organizationName.trim().isNotEmpty
            ? r.organizationName.trim()
            : r.email;
      }
      a.search.value = query;
      // The Organizations section has a workspace now: land ON the record,
      // not on a list narrowed to it. Kept the search narrowing above so the
      // list behind the workspace still shows the one row when closed.
      if ((r.provisionedOrgUid ?? '').isNotEmpty) {
        a.openOrganization(r.provisionedOrgUid!);
      }
    }
    if (Get.isRegistered<AdminRootController>()) {
      Get.find<AdminRootController>().changePage(_navOrganizations);
    }
  }

  Future<bool> _move(
    AccessRequestModel r,
    String status, {
    required String done,
    String? note,
  }) async {
    final ok = await ctrl.setStatus(r.id, status, note: note);
    if (ok) {
      AppSnackbar.show(title: 'Done', message: done, background: _cReady);
    } else {
      AppSnackbar.show(
        title: 'Nothing was changed',
        message: ctrl.actionError.value ?? 'Please try again.',
        background: _cRejected,
      );
    }
    return ok;
  }

  Future<void> reject(BuildContext context, AccessRequestModel r) async {
    final reason = await Get.dialog<String>(
      _ReasonDialog(
        title: 'Reject this request?',
        lead:
            '${AccessRequestLanguage.requesterName(r)} of '
            '${AccessRequestLanguage.organizationName(r)} will not get a '
            'Trainersarena account. Nothing else changes: no account exists '
            'yet, and no payment is moved.',
        consequence:
            'The request moves to "Rejected" and stays in history. '
            'You can reopen it later if this was a mistake.',
        fieldLabel: 'Reason (required — kept in the request history)',
        confirmLabel: 'Reject request',
        destructive: true,
      ),
      barrierDismissible: false,
    );
    if (reason == null) return;
    await _move(
      r,
      SaasOnboardingService.rejected,
      note: reason,
      done: 'Request rejected. It is now under "Rejected" with your reason.',
    );
  }

  Future<void> reopen(BuildContext context, AccessRequestModel r) async {
    final ok = await Get.dialog<bool>(
      _ConfirmDialog(
        title: 'Reopen this request?',
        body:
            '${AccessRequestLanguage.organizationName(r)} goes back to the '
            'start of the queue as "New". The earlier rejection and its reason '
            'stay in the history.',
        confirmLabel: 'Reopen',
      ),
      barrierDismissible: false,
    );
    if (ok != true) return;
    await _move(
      r,
      SaasOnboardingService.requested,
      done: 'Request reopened. It is back under "New".',
    );
  }

  Future<void> recordPayment(BuildContext context, AccessRequestModel r) async {
    final result = await Get.dialog<_PaymentInput>(
      _PaymentDialog(request: r),
      barrierDismissible: false,
    );
    if (result == null) return;
    final ok = await ctrl.setStatus(
      r.id,
      SaasOnboardingService.paymentConfirmed,
      note: result.note,
      paymentReference: result.reference,
      paymentAmount: result.amount,
    );
    if (ok) {
      AppSnackbar.show(
        title: 'Payment recorded',
        message:
            'The request moved to "Ready to create". Create their '
            'organization when you are ready.',
        background: _cReady,
      );
    } else {
      AppSnackbar.show(
        title: 'Nothing was changed',
        message: ctrl.actionError.value ?? 'Please try again.',
        background: _cRejected,
      );
    }
  }

  Future<void> createOrganization(
    BuildContext context,
    AccessRequestModel r,
  ) async {
    final plans = Get.isRegistered<SubscriptionController>()
        ? Get.find<SubscriptionController>().plans
              .where((p) => p.status == PlanStatus.published)
              .toList()
        : <SubscriptionPlanModel>[];
    if (plans.isEmpty) {
      AppSnackbar.show(
        title: 'No plan to assign',
        message: 'Publish a plan under Plans first. Nothing was changed.',
        background: _cRejected,
      );
      return;
    }
    final input = await Get.dialog<_CreateInput>(
      _CreateOrganizationDialog(request: r, plans: plans),
      barrierDismissible: false,
    );
    if (input == null) return;

    final res = await ctrl.provision(
      requestId: r.id,
      planId: input.planId,
      months: input.months,
      email: input.email,
      ownerName: input.ownerName,
      organizationName: input.organizationName,
      phone: input.phone,
    );
    if (res == null) {
      AppSnackbar.show(
        // Only a DEFINITE refusal is "not created": a lost response may
        // have created it (C5).
        title: ctrl.createFailureDefinite.value
            ? 'Organization not created'
            : 'Creation outcome unknown',
        message: ctrl.actionError.value ?? 'Please try again.',
        background: _cRejected,
      );
      return;
    }
    if (res.alreadyProvisioned) {
      // Honest: there is no second password, because there was no second
      // organization. Inventing one would mean resetting a credential the
      // organization may already be using.
      await Get.dialog<void>(
        _ConfirmDialog(
          title: 'Already created',
          body:
              'This request already has an organization. No second '
              'organization was created and no new password was issued. If the '
              'owner lost their password, they can use "Forgot password" on the '
              'Trainersarena sign-in screen.',
          confirmLabel: 'OK',
          cancelLabel: null,
        ),
        barrierDismissible: false,
      );
      return;
    }
    await Get.dialog<void>(
      _CredentialsDialog(result: res, request: r, planLabel: input.planLabel),
      barrierDismissible: false,
    );
  }
}

class _Tile {
  final String key, label, hint;
  final int count;
  final Color color;
  final IconData icon;
  const _Tile(
    this.key,
    this.label,
    this.count,
    this.hint,
    this.color,
    this.icon,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// SEARCH FIELD
// ═════════════════════════════════════════════════════════════════════════════
class _SearchField extends StatefulWidget {
  const _SearchField({required this.initial, required this.onChanged});
  final String initial;
  final ValueChanged<String> onChanged;
  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  );

  @override
  void didUpdateWidget(covariant _SearchField old) {
    super.didUpdateWidget(old);
    if (widget.initial.isEmpty && _c.text.isNotEmpty) _c.clear();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 18),
        hintText: 'Search by gym, requester, email, phone or city',
        hintStyle: AppText.body(size: 13).copyWith(color: p.textMuted),
        border: OutlineInputBorder(
          borderRadius: AppRadii.smR,
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.smR,
          borderSide: BorderSide(color: p.border),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ONE REQUEST ROW
// ═════════════════════════════════════════════════════════════════════════════
class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.now,
    required this.ctrl,
    required this.onOpen,
    required this.onPrimary,
  });
  final AccessRequestModel request;
  final DateTime now;
  final AccessRequestController ctrl;
  final VoidCallback onOpen;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = request;
    final g = AccessRequestLanguage.groupOf(r.status);
    final gc = _groupColor(g);
    final wait = AccessRequestLanguage.waitLevel(r, now: now);
    final waitColor = switch (wait) {
      WaitLevel.overdue => _cOverdue,
      WaitLevel.waiting => _cWaiting,
      WaitLevel.fresh => p.textMuted,
    };
    final waiting = AccessRequestLanguage.waitingLine(r, now: now);
    final action = AccessRequestLanguage.nextAction(r);
    final org = AccessRequestLanguage.organizationName(r);
    final who = AccessRequestLanguage.requesterName(r);
    final reason = AccessRequestLanguage.reason(r);

    return Obx(() {
      final busy = ctrl.busyRequestId.value == r.id;
      final locked = ctrl.isProcessing.value;
      return Semantics(
        container: true,
        label:
            '$org, requested by $who. ${AccessRequestLanguage.stageLabel(r.status)}. '
            '${waiting.isEmpty ? '' : '$waiting. '}${wait == WaitLevel.overdue ? 'Overdue. ' : ''}'
            'Reason: $reason.',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadii.cardR,
            onTap: onOpen,
            child: Container(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: AppRadii.cardR,
                border: Border.all(
                  color: wait == WaitLevel.overdue
                      ? _cOverdue.withValues(alpha: 0.5)
                      : p.border,
                ),
                boxShadow: AppShadows.card(p.isDark),
              ),
              padding: const EdgeInsets.all(14),
              child: LayoutBuilder(
                builder: (_, box) {
                  final narrow = box.maxWidth < 720;
                  final identity = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: gc.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            AccessRequestLanguage.initial(r),
                            style: AppText.label(size: 15).copyWith(color: gc),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    org,
                                    style: AppText.cardTitle(
                                      size: 15,
                                    ).copyWith(color: p.textPrimary),
                                  ),
                                  _pill(
                                    _groupIcon(g),
                                    AccessRequestLanguage.stageLabel(r.status),
                                    gc,
                                  ),
                                  if (wait == WaitLevel.overdue)
                                    _pill(
                                      Icons.timer_off_outlined,
                                      'Overdue',
                                      _cOverdue,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$who · ${r.contactLine.isEmpty ? 'No contact details' : r.contactLine}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(
                                  size: 12.5,
                                ).copyWith(color: p.textSecondary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AccessRequestLanguage.whatTheyWant(r),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(
                                  size: 12,
                                ).copyWith(color: p.textMuted),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '“$reason”',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(size: 12).copyWith(
                                  color: p.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                  final side = Column(
                    crossAxisAlignment: narrow
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end,
                    children: [
                      ExcludeSemantics(
                        child: Tooltip(
                          message:
                              'Requested ${AccessRequestLanguage.exact(r.createdAt)}',
                          child: Text(
                            waiting.isNotEmpty
                                ? waiting
                                : (g == RequestGroup.created
                                      ? 'Created ${AccessRequestLanguage.ago(r.provisionedAt ?? r.updatedAt, now: now)}'
                                      : 'Updated ${AccessRequestLanguage.ago(r.updatedAt ?? r.createdAt, now: now)}'),
                            style: AppText.label(
                              size: 12,
                            ).copyWith(color: waitColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else if (action != null)
                            MergeSemantics(
                              child: Semantics(
                                label: '$action: $org',
                                child: FilledButton(
                                  onPressed: locked && !r.isProvisioned
                                      ? null
                                      : onPrimary,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: gc,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: ExcludeSemantics(child: Text(action)),
                                ),
                              ),
                            ),
                          const SizedBox(width: 6),
                          MergeSemantics(
                            child: Semantics(
                              label: 'Details: $org',
                              child: TextButton(
                                onPressed: onOpen,
                                child: const ExcludeSemantics(
                                  child: Text('Details'),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [identity, const SizedBox(height: 10), side],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 12),
                      side,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
  }
}

Widget _pill(IconData? icon, String text, Color c) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: c.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(999),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
      ],
      Text(text, style: AppText.label(size: 11).copyWith(color: c)),
    ],
  ),
);

// ═════════════════════════════════════════════════════════════════════════════
// DETAIL — the review workspace
// ═════════════════════════════════════════════════════════════════════════════
class _RequestDetailDialog extends StatefulWidget {
  const _RequestDetailDialog({
    required this.request,
    required this.ctrl,
    required this.screen,
  });
  final AccessRequestModel request;
  final AccessRequestController ctrl;
  final AccessRequestsScreen screen;

  @override
  State<_RequestDetailDialog> createState() => _RequestDetailDialogState();
}

class _RequestDetailDialogState extends State<_RequestDetailDialog> {
  final _note = TextEditingController();
  bool _technical = false;

  /// Always read the LIVE row, so an action taken in this dialog is reflected
  /// immediately and a stale snapshot can never drive the next decision. If
  /// the row disappeared from the stream, say so instead of acting on a copy.
  AccessRequestModel? get _live {
    for (final e in widget.ctrl.requests) {
      if (e.id == widget.request.id) return e;
    }
    return null;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Obx(() {
          final r = _live;
          final now = DateTime.now();
          if (r == null) {
            return _gone(context);
          }
          final g = AccessRequestLanguage.groupOf(r.status);
          final gc = _groupColor(g);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AccessRequestLanguage.organizationName(r),
                            style: AppText.title(
                              size: 20,
                            ).copyWith(color: p.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Requested by ${AccessRequestLanguage.requesterName(r)} · '
                            '${AccessRequestLanguage.ago(r.createdAt, now: now)}',
                            style: AppText.body(
                              size: 12.5,
                            ).copyWith(color: p.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _pill(
                                _groupIcon(g),
                                AccessRequestLanguage.stageLabel(r.status),
                                gc,
                              ),
                              if (AccessRequestLanguage.waitLevel(
                                    r,
                                    now: now,
                                  ) ==
                                  WaitLevel.overdue)
                                _pill(
                                  Icons.timer_off_outlined,
                                  AccessRequestLanguage.waitingLine(
                                    r,
                                    now: now,
                                  ),
                                  _cOverdue,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
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
                      _stepper(context, r),
                      const SizedBox(height: 16),
                      if (g == RequestGroup.unknown) ...[
                        _notice(
                          context,
                          _cWaiting,
                          Icons.help_outline,
                          'This request is at a stage this console does not recognise ("${r.status}"). '
                          'No action is offered until the stored value is understood — see Technical details.',
                        ),
                        const SizedBox(height: 14),
                      ],
                      _section(context, 'Who is asking', [
                        _kv(
                          context,
                          'Requester',
                          AccessRequestLanguage.requesterName(r),
                        ),
                        _kv(
                          context,
                          'Organization',
                          AccessRequestLanguage.organizationName(r),
                        ),
                        _kv(
                          context,
                          'Email',
                          r.email.isEmpty ? 'Not provided' : r.email,
                        ),
                        _kv(
                          context,
                          'Phone',
                          r.phone.isEmpty ? 'Not provided' : r.phone,
                        ),
                        if (r.whatsapp.isNotEmpty && r.whatsapp != r.phone)
                          _kv(context, 'WhatsApp', r.whatsapp),
                        _kv(
                          context,
                          'Location',
                          r.locationLine.isEmpty
                              ? 'Not provided'
                              : r.locationLine,
                        ),
                        _kv(
                          context,
                          'Team size',
                          r.teamSize == null
                              ? 'Not provided'
                              : '${r.teamSize} people',
                        ),
                        _kv(
                          context,
                          'Requested',
                          '${AccessRequestLanguage.exact(r.createdAt)} '
                              '(${AccessRequestLanguage.ago(r.createdAt, now: now)})',
                        ),
                      ]),
                      const SizedBox(height: 14),
                      _section(context, 'Why they asked', [
                        Text(
                          AccessRequestLanguage.reason(r),
                          style: AppText.body(size: 13).copyWith(
                            color: r.message.trim().isEmpty
                                ? p.textMuted
                                : p.textPrimary,
                            fontStyle: r.message.trim().isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      if (r.isProvisioned)
                        _section(context, 'Organization created', [
                          Text(
                            'They can sign in to Trainersarena now. The temporary '
                            'password was shown once at creation and is stored nowhere; '
                            'if it was lost, the owner uses "Forgot password" on the '
                            'sign-in screen.',
                            style: AppText.body(
                              size: 13,
                            ).copyWith(color: p.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          _kv(
                            context,
                            'Created',
                            '${AccessRequestLanguage.exact(r.provisionedAt)} '
                                'by ${_by(_provisionedBy(r))}',
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => widget.screen._openOrganization(r),
                            icon: const Icon(Icons.arrow_outward, size: 16),
                            label: const Text('Open organization'),
                          ),
                        ], color: _cCreated)
                      else
                        _section(
                          context,
                          'What creating the organization allows',
                          [
                            Text(
                              AccessRequestLanguage.whatCreationAllows,
                              style: AppText.body(
                                size: 13,
                              ).copyWith(color: p.textSecondary),
                            ),
                          ],
                        ),
                      if (r.paymentEvidence != null) ...[
                        const SizedBox(height: 14),
                        _section(context, 'Payment recorded', [
                          _kv(
                            context,
                            'Amount',
                            '₹${r.paymentEvidence!.amount.toStringAsFixed(0)}',
                          ),
                          _kv(
                            context,
                            'Reference',
                            r.paymentEvidence!.reference,
                          ),
                          if (r.paymentEvidence!.note.isNotEmpty)
                            _kv(context, 'Note', r.paymentEvidence!.note),
                          _kv(
                            context,
                            'Recorded',
                            '${AccessRequestLanguage.exact(r.paymentEvidence!.confirmedAt)} '
                                'by ${_by(r.paymentEvidence!.confirmedBy)}',
                          ),
                          Text(
                            'This is the team\'s record of a payment taken outside the '
                            'platform. It moves no money.',
                            style: AppText.body(
                              size: 11.5,
                            ).copyWith(color: p.textMuted),
                          ),
                        ], color: _cReady),
                      ],
                      const SizedBox(height: 14),
                      _section(context, 'History', [
                        _timeline(context, r, now),
                      ]),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _note,
                              decoration: InputDecoration(
                                hintText:
                                    'Add an internal note (the requester never sees it)',
                                hintStyle: AppText.body(
                                  size: 12.5,
                                ).copyWith(color: p.textMuted),
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: widget.ctrl.isProcessing.value
                                ? null
                                : () async {
                                    final ok = await widget.ctrl.addNote(
                                      r.id,
                                      _note.text,
                                    );
                                    if (ok) {
                                      _note.clear();
                                      AppSnackbar.show(
                                        title: 'Note added',
                                        message:
                                            'It appears in the history below.',
                                        background: _cReady,
                                      );
                                    } else if (_note.text.trim().isNotEmpty) {
                                      AppSnackbar.show(
                                        title: 'Nothing was changed',
                                        message:
                                            widget.ctrl.actionError.value ??
                                            'Please try again.',
                                        background: _cRejected,
                                      );
                                    }
                                  },
                            child: const Text('Add note'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _technical = !_technical),
                        icon: Icon(
                          _technical ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                        ),
                        label: Text(
                          _technical
                              ? 'Hide technical details'
                              : 'Technical details',
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: p.textMuted,
                        ),
                      ),
                      if (_technical) _technicalPanel(context, r),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: _actions(context, r),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _gone(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 32, color: p.textMuted),
          const SizedBox(height: 10),
          Text(
            'This request is no longer in the list',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'It may have been removed while this window was open. No action is possible here.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _provisionedBy(AccessRequestModel r) {
    for (final e in r.statusHistory.reversed) {
      if (e.status == SaasOnboardingService.organizationCreated) return e.by;
    }
    return '';
  }

  String _by(String uid) => widget.ctrl.actorName(uid);

  // Stage stepper: five stops; rejected shows as a red state instead.
  Widget _stepper(BuildContext context, AccessRequestModel r) {
    final p = context.palette;
    if (r.status == SaasOnboardingService.rejected) {
      String reason = '';
      String by = '';
      DateTime? at;
      for (final e in r.statusHistory.reversed) {
        if (e.status == SaasOnboardingService.rejected) {
          reason = e.note;
          by = e.by;
          at = e.at;
          break;
        }
      }
      return _notice(
        context,
        _cRejected,
        Icons.block_outlined,
        'Rejected by ${_by(by)} · ${AccessRequestLanguage.exact(at)}'
        '${reason.isEmpty ? ' · no reason recorded' : ' — “$reason”'}. '
        'It can be reopened.',
      );
    }
    const stops = [
      SaasOnboardingService.requested,
      SaasOnboardingService.contacted,
      SaasOnboardingService.paymentPending,
      SaasOnboardingService.paymentConfirmed,
      SaasOnboardingService.organizationCreated,
    ];
    const names = ['Received', 'Contacted', 'Link sent', 'Paid', 'Created'];
    var current = stops.indexOf(r.status);
    if (r.status == SaasOnboardingService.approved) current = 3;
    if (r.isProvisioned) current = 4;
    return Semantics(
      label:
          'Progress: ${current < 0 ? 'unknown stage' : '${names[current]}, step ${current + 1} of 5'}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (int i = 0; i < stops.length; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: i <= current ? _cReady : p.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      names[i],
                      style: AppText.label(size: 10.5).copyWith(
                        color: i == current ? p.textPrimary : p.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < stops.length - 1) const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );
  }

  Widget _timeline(BuildContext context, AccessRequestModel r, DateTime now) {
    final p = context.palette;
    final entries = <({DateTime? at, String text, IconData icon})>[
      for (final e in r.statusHistory)
        (
          at: e.at,
          text:
              '${AccessRequestLanguage.eventLabel(e.status)} · by ${_by(e.by)}'
              '${e.note.isNotEmpty ? ' — “${e.note}”' : ''}',
          icon: Icons.circle,
        ),
      for (final n in r.notes)
        (
          at: n.at,
          text: 'Note by ${_by(n.by)}: “${n.text}”',
          icon: Icons.notes_outlined,
        ),
    ];
    entries.sort((a, b) {
      if (a.at == null && b.at == null) return 0;
      if (a.at == null) return 1;
      if (b.at == null) return -1;
      return a.at!.compareTo(b.at!);
    });
    if (entries.isEmpty) {
      return Text(
        'No history recorded for this request.',
        style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
      );
    }
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  e.icon,
                  size: e.icon == Icons.circle ? 8 : 14,
                  color: p.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e.text,
                    style: AppText.body(
                      size: 12.5,
                    ).copyWith(color: p.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: AccessRequestLanguage.exact(e.at),
                  child: Text(
                    AccessRequestLanguage.ago(e.at, now: now),
                    style: AppText.body(
                      size: 11.5,
                    ).copyWith(color: p.textMuted),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _technicalPanel(BuildContext context, AccessRequestModel r) {
    final p = context.palette;
    final rows = <MapEntry<String, String>>[
      MapEntry('Request id', r.id),
      MapEntry('Stored stage', r.status),
      if (r.provisionedOrgUid != null && r.provisionedOrgUid!.isNotEmpty)
        MapEntry('Organization id', r.provisionedOrgUid!),
      if (r.paymentEvidence != null)
        MapEntry('Payment reference', r.paymentEvidence!.reference),
      MapEntry('Created', AccessRequestLanguage.exact(r.createdAt)),
      MapEntry('Last updated', AccessRequestLanguage.exact(r.updatedAt)),
      for (final e in r.statusHistory)
        MapEntry(
          'History: ${e.status}',
          '${AccessRequestLanguage.exact(e.at)} · ${e.by}',
        ),
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'For troubleshooting — share with support or engineering.',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 6),
          for (final e in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 150,
                    child: Text(
                      e.key,
                      style: AppText.label(
                        size: 11,
                      ).copyWith(color: p.textMuted),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      e.value,
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<Widget> children, {
    Color? color,
  }) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (color ?? p.border).withValues(
          alpha: color == null ? 0.04 : 0.06,
        ),
        borderRadius: AppRadii.smR,
        border: Border.all(
          color: (color ?? p.border).withValues(
            alpha: color == null ? 1 : 0.35,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.label(
              size: 12,
            ).copyWith(color: color ?? p.textMuted),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: AppText.body(size: 13).copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(BuildContext context, Color c, IconData icon, String text) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: AppRadii.smR,
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: AppText.body(size: 13).copyWith(color: c),
              ),
            ),
          ],
        ),
      );

  // Footer: one primary verb, the reversals as quiet buttons, and what the
  // primary will do spelled out above it.
  Widget _actions(BuildContext context, AccessRequestModel r) {
    final p = context.palette;
    final busy = widget.ctrl.isProcessing.value;
    final err = widget.ctrl.actionError.value;
    final primary = AccessRequestLanguage.nextAction(r);
    final meaning = AccessRequestLanguage.nextActionMeaning(r);
    final g = AccessRequestLanguage.groupOf(r.status);
    final canReject = g.isOpen;
    final canRecordPayment =
        r.status == SaasOnboardingService.requested ||
        r.status == SaasOnboardingService.contacted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (err != null) ...[
          Text(
            err,
            style: AppText.body(size: 12.5).copyWith(color: _cRejected),
          ),
          const SizedBox(height: 8),
        ],
        if (meaning.isNotEmpty && primary != null)
          Text(
            '$primary — $meaning',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (canReject)
              TextButton(
                onPressed: busy ? null : () => widget.screen.reject(context, r),
                style: TextButton.styleFrom(foregroundColor: _cRejected),
                child: const Text('Reject'),
              ),
            if (canRecordPayment)
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => widget.screen.recordPayment(context, r),
                child: const Text('Record payment'),
              ),
            if (primary != null)
              FilledButton(
                onPressed: busy
                    ? null
                    : () => widget.screen._primaryAction(context, r),
                style: FilledButton.styleFrom(backgroundColor: _groupColor(g)),
                child: Text(busy ? 'Working…' : primary),
              ),
          ],
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DIALOGS
// ═════════════════════════════════════════════════════════════════════════════
class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
  });
  final String title, body, confirmLabel;
  final String? cancelLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      backgroundColor: p.surface,
      title: Text(
        title,
        style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
      ),
      content: Text(
        body,
        style: AppText.body(size: 13).copyWith(color: p.textSecondary),
      ),
      actions: [
        if (cancelLabel != null)
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text(cancelLabel!),
          ),
        FilledButton(
          onPressed: () => Get.back(result: true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// A confirmation that requires a written reason (rejection).
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.lead,
    required this.consequence,
    required this.fieldLabel,
    required this.confirmLabel,
    this.destructive = false,
  });
  final String title, lead, consequence, fieldLabel, confirmLabel;
  final bool destructive;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AlertDialog(
      backgroundColor: p.surface,
      title: Text(
        widget.title,
        style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.lead,
              style: AppText.body(size: 13).copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              widget.consequence,
              style: AppText.body(size: 13).copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: _cRejected)
              : null,
          onPressed: () {
            final t = _c.text.trim();
            if (t.isEmpty) {
              setState(
                () => _error =
                    'Write one line so the history explains this decision.',
              );
              return;
            }
            Get.back(result: t);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _PaymentInput {
  final String reference, note;
  final double amount;
  const _PaymentInput(this.reference, this.amount, this.note);
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.request});
  final AccessRequestModel request;
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _ref = TextEditingController();
  final _amt = TextEditingController();
  final _note = TextEditingController();
  String? _refError, _amtError;

  @override
  void dispose() {
    _ref.dispose();
    _amt.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = widget.request;
    return AlertDialog(
      backgroundColor: p.surface,
      title: Text(
        'Record payment',
        style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record the payment ${AccessRequestLanguage.requesterName(r)} '
                '(${AccessRequestLanguage.organizationName(r)}) already made outside '
                'the platform. This is your record of it — it moves no money. Once '
                'recorded, the request becomes "Ready to create".',
                style: AppText.body(size: 13).copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ref,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Payment reference',
                  helperText:
                      'The Razorpay payment id or bank reference. Each reference can be used once.',
                  helperMaxLines: 2,
                  errorText: _refError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _refError = null),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _amt,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount received (₹)',
                  errorText: _amtError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _amtError = null),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final ref = _ref.text.trim();
            final amt = double.tryParse(_amt.text.trim().replaceAll(',', ''));
            var ok = true;
            if (ref.isEmpty) {
              _refError = 'Enter the payment reference.';
              ok = false;
            }
            if (amt == null || amt < 0) {
              _amtError = 'Enter the amount as a number, e.g. 4999.';
              ok = false;
            }
            if (!ok) {
              setState(() {});
              return;
            }
            Get.back(result: _PaymentInput(ref, amt!, _note.text.trim()));
          },
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}

class _CreateInput {
  final String planId, planLabel, email, ownerName, organizationName, phone;
  final int months;
  const _CreateInput({
    required this.planId,
    required this.planLabel,
    required this.months,
    required this.email,
    required this.ownerName,
    required this.organizationName,
    required this.phone,
  });
}

/// Two steps: choose (plan, term, sign-in details) → review ("You are about
/// to…") → create. The review step is the deliberate confirmation.
class _CreateOrganizationDialog extends StatefulWidget {
  const _CreateOrganizationDialog({required this.request, required this.plans});
  final AccessRequestModel request;
  final List<SubscriptionPlanModel> plans;
  @override
  State<_CreateOrganizationDialog> createState() =>
      _CreateOrganizationDialogState();
}

class _CreateOrganizationDialogState extends State<_CreateOrganizationDialog> {
  late String _planId = widget.plans.first.docId;
  late final TextEditingController _months = TextEditingController(
    text: '${widget.plans.first.durationMonths}',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.request.email,
  );
  late final TextEditingController _owner = TextEditingController(
    text: widget.request.ownerName,
  );
  late final TextEditingController _org = TextEditingController(
    text: widget.request.organizationName,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.request.phone,
  );
  bool _review = false;
  String? _error;

  SubscriptionPlanModel get _plan =>
      widget.plans.firstWhere((p) => p.docId == _planId);

  @override
  void dispose() {
    for (final c in [_months, _email, _owner, _org, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _valid() {
    final m = int.tryParse(_months.text.trim());
    if (m == null || m < 1 || m > 120) {
      _error = 'Term must be between 1 and 120 months.';
      return false;
    }
    if (_email.text.trim().isEmpty || !_email.text.contains('@')) {
      _error = 'A valid sign-in email is required.';
      return false;
    }
    if (_owner.text.trim().isEmpty) {
      _error = 'The owner\'s name is required.';
      return false;
    }
    if (_phone.text.trim().isEmpty) {
      _error = 'A phone number is required.';
      return false;
    }
    _error = null;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final months = int.tryParse(_months.text.trim()) ?? _plan.durationMonths;
    return AlertDialog(
      backgroundColor: p.surface,
      title: Text(
        _review ? 'Review before creating' : 'Create organization',
        style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: _review ? _reviewStep(p, months) : _formStep(p),
        ),
      ),
      actions: _review
          ? [
              TextButton(
                onPressed: () => setState(() => _review = false),
                child: const Text('Back'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _cReady),
                onPressed: () => Get.back(
                  result: _CreateInput(
                    planId: _planId,
                    planLabel: AccessRequestLanguage.planSummary(_plan),
                    months: months,
                    email: _email.text.trim(),
                    ownerName: _owner.text.trim(),
                    organizationName: _org.text.trim(),
                    phone: _phone.text.trim(),
                  ),
                ),
                child: const Text('Create organization'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => setState(() {
                  if (_valid()) _review = true;
                }),
                child: const Text('Review'),
              ),
            ],
    );
  }

  Widget _formStep(AppPalette p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose the plan and check the sign-in details. These are pre-filled '
          'from the request — change them only if the requester asked you to.',
          style: AppText.body(size: 13).copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _planId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Plan',
            border: OutlineInputBorder(),
          ),
          items: widget.plans
              .map(
                (pl) => DropdownMenuItem(
                  value: pl.docId,
                  child: Text(
                    AccessRequestLanguage.planSummary(pl),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() {
            _planId = v ?? _planId;
            _months.text = '${_plan.durationMonths}';
          }),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _months,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Term (months)',
            helperText:
                'Pre-filled from the plan. Change only for a negotiated term.',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _org,
          decoration: const InputDecoration(
            labelText: 'Organization name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _owner,
          decoration: const InputDecoration(
            labelText: 'Owner name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _email,
          decoration: const InputDecoration(
            labelText: 'Sign-in email',
            helperText: 'This becomes their Trainersarena login.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          decoration: const InputDecoration(
            labelText: 'Phone',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: AppText.body(size: 12.5).copyWith(color: _cRejected),
          ),
        ],
      ],
    );
  }

  Widget _reviewStep(AppPalette p, int months) {
    final plan = _plan;
    Widget line(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: AppText.body(size: 13).copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'You are about to create a Trainersarena organization for '
          '${_owner.text.trim()} (${_org.text.trim()}).',
          style: AppText.body(size: 13.5).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 10),
        line('Plan', AccessRequestLanguage.planSummary(plan)),
        line('Term', '$months month${months == 1 ? '' : 's'}'),
        line('Sign-in email', _email.text.trim()),
        line('Phone', _phone.text.trim()),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _cWaiting.withValues(alpha: 0.08),
            borderRadius: AppRadii.smR,
            border: Border.all(color: _cWaiting.withValues(alpha: 0.35)),
          ),
          child: Text(
            'This happens immediately: their account and organization are created '
            'and the plan starts today. A temporary password is shown ONCE on the '
            'next screen and stored nowhere. This cannot be undone from here — if '
            'something is wrong, go Back.',
            style: AppText.body(size: 12.5).copyWith(color: p.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// The ONE time the temporary password is ever visible.
class _CredentialsDialog extends StatelessWidget {
  const _CredentialsDialog({
    required this.result,
    required this.request,
    required this.planLabel,
  });
  final ProvisionResult result;
  final AccessRequestModel request;
  final String planLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final expiry = result.expiry == null
        ? '—'
        : AccessRequestLanguage.exact(
            DateTime.tryParse(result.expiry!),
            withTime: false,
          );
    final text =
        'Trainersarena sign-in for ${request.organizationName}\n'
        'Email: ${result.email ?? ''}\n'
        'Temporary password: ${result.tempPassword ?? ''}\n'
        'Please change your password after signing in.';
    return AlertDialog(
      backgroundColor: p.surface,
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: _cCreated),
          const SizedBox(width: 8),
          Text(
            'Organization created',
            style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AccessRequestLanguage.requesterName(request)} can sign in to '
              'Trainersarena now. The request moved to "Organization created".',
              style: AppText.body(size: 13).copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: AppRadii.smR,
                border: Border.all(color: p.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Email: ${result.email ?? ''}',
                    style: AppText.body(size: 14),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    'Temporary password: ${result.tempPassword ?? ''}',
                    style: AppText.title(
                      size: 16,
                    ).copyWith(color: p.textPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Plan: $planLabel\nPlan ends: $expiry',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 10),
            Text(
              'Send these to the owner now. This password is shown once and stored '
              'nowhere; if it is lost, they use "Forgot password" on the sign-in screen.',
              style: AppText.body(size: 12.5).copyWith(color: _cWaiting),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            AppSnackbar.show(
              title: 'Copied',
              message: 'Sign-in details copied to the clipboard.',
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy sign-in details'),
        ),
        FilledButton(onPressed: () => Get.back(), child: const Text('Done')),
      ],
    );
  }
}
