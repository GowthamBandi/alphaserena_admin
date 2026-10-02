// ORGANIZATION WORKSPACE — one organization, completely, safely.
//
// Reads top to bottom the way an administrator asks: who is this, what is
// their standing, what do they pay for, who belongs to them, what has
// happened, what is wrong, what can I do and what will it do. Words come from
// core/services/organization_language.dart; data from
// OrganizationDetailController (live record + eight related feeds, each with
// its own unread/failed state); every mutation from AdminController.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/admin_controller.dart';
import '../../controllers/admin_root_controller.dart';
import '../../controllers/access_request_controller.dart';
import '../../controllers/organization_detail_controller.dart';
import '../../controllers/platform_staff_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../../core/services/organization_language.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/console/console_chrome.dart';
import '../../core/widgets/serena/serena_ui.dart';
import '../../models/access_request_model.dart';
import '../../models/admin_model.dart';
import '../../models/audit_log_model.dart';
import '../../models/clints_model.dart';
import '../../models/subscription_model.dart';
import '../../models/trainer_model.dart';
import 'organization_action_dialogs.dart';

/// Access Requests' page index — stable identifier, see console_destinations.
const int _navAccessRequests = 17;

SerenaStatus standingStatus(OrgStanding s) => switch (s) {
  OrgStanding.approved => SerenaStatus.active,
  OrgStanding.awaitingApproval => SerenaStatus.pending,
  OrgStanding.warning => SerenaStatus.warning,
  OrgStanding.blocked => SerenaStatus.blocked,
  OrgStanding.unknown => SerenaStatus.neutral,
};

Color severityColor(BuildContext context, OrgIssueSeverity s) => switch (s) {
  OrgIssueSeverity.critical => context.serena.error,
  OrgIssueSeverity.attention => context.serena.statusWarning,
  OrgIssueSeverity.info => context.serena.info,
};

IconData severityIcon(OrgIssueSeverity s) => switch (s) {
  OrgIssueSeverity.critical => Icons.error_outline,
  OrgIssueSeverity.attention => Icons.warning_amber_outlined,
  OrgIssueSeverity.info => Icons.info_outline,
};

/// The compact "N need attention" pill for a record, or nothing.
class AttentionPill extends StatelessWidget {
  const AttentionPill({super.key, required this.issues});
  final List<OrgIssue> issues;

  @override
  Widget build(BuildContext context) {
    final worst = OrganizationLanguage.sortIssues(
      issues,
    ).where((i) => i.needsAttention).toList();
    if (worst.isEmpty) return const SizedBox.shrink();
    final s = worst.first.severity;
    return ConsolePill(
      label: s == OrgIssueSeverity.critical
          ? 'Urgent · ${worst.length}'
          : 'Needs attention · ${worst.length}',
      color: severityColor(context, s),
      icon: severityIcon(s),
    );
  }
}

class OrganizationWorkspace extends StatelessWidget {
  const OrganizationWorkspace({
    super.key,
    required this.ctrl,
    required this.detail,
  });

  final AdminController ctrl;
  final OrganizationDetailController detail;

  static const _tabs = <(String, String)>[
    ('overview', 'Overview'),
    ('people', 'People'),
    ('subscription', 'Subscription & payments'),
    ('history', 'History'),
    ('profile', 'Profile & technical'),
  ];

  String? _staffName(String uid) {
    if (!Get.isRegistered<PlatformStaffController>()) return null;
    for (final s in Get.find<PlatformStaffController>().staff) {
      if (s.uid == uid) return s.displayEmail;
    }
    return null;
  }

  String _actor(String uid) => OrganizationLanguage.actor(
    uid,
    currentUid: ctrl.currentUid(),
    staffName: _staffName,
    ownerUid: detail.orgId,
  );

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final now = ctrl.clock();
      final a = detail.admin.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _backRow(context),
          const SizedBox(height: 12),
          if (detail.adminLoading.value && a == null)
            _skeleton()
          else if (detail.notFound.value)
            _notFound(context)
          else if (a == null && detail.adminError.value != null)
            ConsoleErrorState(
              error: detail.adminError.value!,
              onRetry: detail.listen,
            )
          else if (a != null) ...[
            _recordHealthBanner(context, a),
            _header(context, a, now),
            const SizedBox(height: 12),
            _progressAndOutcome(context, a),
            _tabBar(context),
            const SizedBox(height: 14),
            switch (detail.tab.value) {
              'people' => _people(context, a, now),
              'subscription' => _subscription(context, a, now),
              'history' => _history(context, a, now),
              'profile' => _profile(context, a, now),
              _ => _overview(context, a, now),
            },
          ],
        ],
      );
    });
  }

  // ── chrome ────────────────────────────────────────────────────────────────

  Widget _backRow(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        TextButton.icon(
          onPressed: ctrl.closeOrganization,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('All organizations'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Obx(() {
            final t = detail.lastReceived.value;
            return Text(
              t == null
                  ? 'Connecting…'
                  : 'Live · record updated ${OrganizationLanguage.exactTime(t)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            );
          }),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Reload trainers, members, payments, history and checks',
          child: IconButton(
            onPressed: detail.refreshRelated,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ),
      ],
    );
  }

  /// Said ABOVE the record whenever what is on screen is not a clean, live
  /// copy: the live read failed (the last good copy is shown, with its
  /// time), the latest version could not be read at all, or some fields are
  /// of the wrong type (shown blank). A record is never silently stale.
  Widget _recordHealthBanner(BuildContext context, AdminModel a) {
    final err = detail.adminError.value;
    final unreadableVersion = detail.recordUnreadable.value;
    final malformed = a.unreadable
        ? const <String>[]
        : a.malformedFields.toList();
    if (err == null && !a.unreadable && malformed.isEmpty) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    final t = detail.lastReceived.value;
    final String title;
    final String body;
    if (a.unreadable) {
      title = 'This organization\'s record could not be read';
      body =
          'Only its id${a.status == 'pending' ? '' : ' and status'} can be shown. It stays here '
          'so it can still be moderated; the record needs a repair by the '
          'backend team.';
    } else if (unreadableVersion) {
      title = 'Unreadable record — showing the last good copy';
      body =
          'The latest version of this record could not be read. What you see '
          'is the last readable copy${t == null ? '' : ', received ${OrganizationLanguage.exactTime(t)}'}; '
          'it may be out of date.';
    } else if (err != null) {
      title = 'Not live — showing the last good copy';
      body =
          'The live connection to this record failed${t == null ? '' : '; this copy was received ${OrganizationLanguage.exactTime(t)}'}. '
          '${err.message}';
    } else {
      title = 'Some fields on this record are of the wrong type';
      body =
          '${malformed.join(', ')} ${malformed.length == 1 ? 'is' : 'are'} '
          'stored in a shape the console cannot read, so ${malformed.length == 1 ? 'it shows' : 'they show'} '
          'as blank. Everything else on this page is the live record.';
    }
    final c = err != null || a.unreadable
        ? context.serena.error
        : context.serena.statusWarning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.08),
            borderRadius: AppRadii.smR,
            border: Border.all(color: c.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.report_gmailerrorred_outlined, size: 18, color: c),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.label(
                        size: 13.5,
                      ).copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      style: AppText.body(
                        size: 12.5,
                      ).copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              if (err != null && !unreadableVersion)
                TextButton(
                  onPressed: detail.listen,
                  child: const Text('Reconnect'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeleton() => Column(
    children: const [
      ConsoleSkeletonRow(),
      SizedBox(height: 10),
      ConsoleSkeletonRow(),
      SizedBox(height: 10),
      ConsoleSkeletonRow(),
    ],
  );

  Widget _notFound(BuildContext context) => ConsoleEmptyState(
    icon: Icons.search_off,
    title: 'Organization not found',
    message:
        'No organization record exists with id ${detail.orgId}. It may '
        'have been removed, or the link that brought you here is stale.',
    action: TextButton(
      onPressed: ctrl.closeOrganization,
      child: const Text('Back to all organizations'),
    ),
  );

  Widget _header(BuildContext context, AdminModel a, DateTime now) {
    final p = context.palette;
    final standing = OrganizationLanguage.standingOf(a);
    final sub = OrganizationLanguage.subscriptionOf(a, now: now);
    final issues = detail.issues(now: now);
    final name = OrganizationLanguage.displayName(a);
    // Read HERE, inside the Obx closure: a read inside LayoutBuilder's
    // builder is not tracked, and the buttons would stay enabled mid-call.
    final busy = ctrl.isProcessing.value;
    return ConsoleCard(
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 720;
          final factW = box.maxWidth - (narrow ? 70 : 90);
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(context, a, size: narrow ? 44 : 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            name,
                            style: AppText.title(
                              size: narrow ? 22 : 26,
                            ).copyWith(color: p.textPrimary),
                          ),
                        ),
                        SerenaStatusPill(
                          label: standing.label,
                          status: standingStatus(standing),
                        ),
                        AttentionPill(issues: issues),
                      ],
                    ),
                    if (OrganizationLanguage.nameIsOwnerFallback(a))
                      Text(
                        'No organization name recorded — showing the owner\'s name',
                        style: AppText.body(
                          size: 11.5,
                        ).copyWith(color: p.textMuted),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      OrganizationLanguage.operatingLine(a),
                      style: AppText.label(size: 13).copyWith(
                        color: OrganizationLanguage.canOperate(a)
                            ? context.serena.statusActive
                            : p.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 18,
                      runSpacing: 4,
                      children: [
                        _fact(
                          context,
                          Icons.workspace_premium_outlined,
                          '${sub.planName} · ${sub.label}'
                          '${sub.endsAt != null && sub.isActiveFlag ? ' · ends ${OrganizationLanguage.exact(sub.endsAt)}' : ''}',
                          factW,
                        ),
                        _fact(
                          context,
                          Icons.person_outline,
                          'Owner ${OrganizationLanguage.ownerName(a)} · ${OrganizationLanguage.ownerEmail(a)}',
                          factW,
                        ),
                        _fact(
                          context,
                          Icons.calendar_today_outlined,
                          OrganizationLanguage.createdLine(a, now: now),
                          factW,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = _actionButtons(context, a, now, busy);
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [identity, const SizedBox(height: 14), actions],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        },
      ),
    );
  }

  Widget _fact(
    BuildContext context,
    IconData icon,
    String text,
    double maxWidth,
  ) {
    final p = context.palette;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: p.textMuted),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, AdminModel a, {double size = 48}) {
    final p = context.palette;
    final url = (a.profilePicUrl ?? '').trim();
    final letter = OrganizationLanguage.initial(a);
    final fallback = Container(
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
    if (url.isEmpty) return ExcludeSemantics(child: fallback);
    return ExcludeSemantics(
      child: ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, e, s) => fallback,
        ),
      ),
    );
  }

  Widget _actionButtons(
    BuildContext context,
    AdminModel a,
    DateTime now,
    bool busy,
  ) {
    final actions = OrganizationLanguage.actionsFor(a);
    final primary = OrganizationLanguage.primaryAction(a, now: now);
    final name = OrganizationLanguage.displayName(a);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final act in actions)
          MergeSemantics(
            child: Semantics(
              label: '${OrganizationLanguage.actionLabelFor(act, a)}: $name',
              child: act == primary
                  ? FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => showOrgActionDialog(
                              context,
                              action: act,
                              org: a,
                              ctrl: ctrl,
                            ),
                      icon: Icon(_actionIcon(act), size: 16),
                      label: Text(OrganizationLanguage.actionLabelFor(act, a)),
                    )
                  : OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => showOrgActionDialog(
                              context,
                              action: act,
                              org: a,
                              ctrl: ctrl,
                            ),
                      style: act.isDestructive
                          ? OutlinedButton.styleFrom(
                              foregroundColor: kOrgDanger,
                              side: const BorderSide(color: kOrgDanger),
                            )
                          : null,
                      icon: Icon(_actionIcon(act), size: 16),
                      label: Text(OrganizationLanguage.actionLabelFor(act, a)),
                    ),
            ),
          ),
      ],
    );
  }

  IconData _actionIcon(OrgAction a) => switch (a) {
    OrgAction.approve => Icons.how_to_reg_outlined,
    OrgAction.warn => Icons.flag_outlined,
    OrgAction.block => Icons.block_outlined,
    OrgAction.reactivate => Icons.restart_alt_outlined,
    OrgAction.grant => Icons.receipt_long_outlined,
    OrgAction.reapplyEffects => Icons.sync_outlined,
  };

  Widget _progressAndOutcome(BuildContext context, AdminModel a) {
    final p = context.palette;
    return Obx(() {
      final busy = ctrl.isProcessing.value && ctrl.busyOrgId.value == a.docId;
      final raw = ctrl.lastOutcome.value;
      // Only THIS organization's outcome (ORG-17): an action still in flight
      // when the founder opened another organization reports on its own.
      final o = (raw != null && (raw.orgId == null || raw.orgId == a.docId))
          ? raw
          : null;
      if (!busy && o == null) return const SizedBox.shrink();
      if (busy) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            liveRegion: true,
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Applying the change… every action is disabled until the backend answers.',
                  style: AppText.body(
                    size: 12.5,
                  ).copyWith(color: p.textSecondary),
                ),
              ],
            ),
          ),
        );
      }
      final color = o!.ok ? context.serena.statusActive : context.serena.error;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: AppRadii.smR,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  o.ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.title,
                        style: AppText.label(
                          size: 13.5,
                        ).copyWith(color: p.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        o.message,
                        style: AppText.body(
                          size: 12.5,
                        ).copyWith(color: p.textSecondary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        switch (o.changed) {
                          true =>
                            'The record changed. ${OrganizationLanguage.exactTime(o.at)}',
                          false =>
                            'Nothing was changed. ${OrganizationLanguage.exactTime(o.at)}',
                          null =>
                            'Whether the record changed is not known. ${OrganizationLanguage.exactTime(o.at)}',
                        },
                        style: AppText.body(
                          size: 11.5,
                        ).copyWith(color: p.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  onPressed: ctrl.dismissOutcome,
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _tabBar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        // A chip is one line; on a phone the long labels and the people counts
        // would overflow it, so the words shrink with the width.
        final narrow = box.maxWidth < 560;
        return Obx(() {
          final t = detail.tab.value;
          final live = detail.liveTrainers.length;
          final total =
              detail.memberTotal.value ?? detail.members.data.value?.length;
          String label(String key, String base) {
            if (narrow) {
              return switch (key) {
                'subscription' => 'Subscription',
                'profile' => 'Profile',
                _ => base,
              };
            }
            return switch (key) {
              'people'
                  when detail.trainers.done.value ||
                      detail.members.done.value =>
                '$base · $live trainers · ${total ?? '?'} members',
              _ => base,
            };
          }

          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (key, base) in _tabs)
                ConsoleChip(
                  label: label(key, base),
                  active: t == key,
                  onTap: () => detail.tab.value = key,
                ),
            ],
          );
        });
      },
    );
  }

  // ── section helpers ───────────────────────────────────────────────────────

  /// Renders a feed with its own unread / failed / empty / data states.
  Widget _section<T>(
    BuildContext context, {
    required Section<T> s,
    required String title,
    required Future<void> Function() retry,
    required Widget Function(T data) body,
    Widget? trailing,
  }) {
    final p = context.palette;
    return ConsoleCard(
      title: title,
      trailing: trailing,
      child: Obx(() {
        if (s.loading.value && !s.done.value) {
          return const ConsoleSkeletonRow();
        }
        final err = s.error.value;
        if (err != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: p.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This section could not be loaded, so it may be hiding records. '
                  '${err.message}',
                  style: AppText.body(size: 12.5).copyWith(color: p.error),
                ),
              ),
              TextButton(onPressed: retry, child: const Text('Retry')),
            ],
          );
        }
        if (!s.done.value) return const ConsoleSkeletonRow();
        return body(s.data.value as T);
      }),
    );
  }

  Widget _kv(
    BuildContext context,
    String label,
    String value, {
    bool copy = false,
  }) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            ),
          ),
          Expanded(
            child: copy
                ? SelectableText(
                    value,
                    style: AppText.body(
                      size: 12.5,
                    ).copyWith(color: p.textPrimary),
                  )
                : Text(
                    value,
                    style: AppText.body(
                      size: 12.5,
                    ).copyWith(color: p.textPrimary),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _issueTile(BuildContext context, OrgIssue i, AdminModel a) {
    final p = context.palette;
    final c = severityColor(context, i.severity);
    return Semantics(
      label: '${i.severity.label}: ${i.title}',
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.06),
          borderRadius: AppRadii.smR,
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(severityIcon(i.severity), size: 16, color: c),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    i.title,
                    style: AppText.label(
                      size: 13,
                    ).copyWith(color: p.textPrimary),
                  ),
                ),
                ConsolePill(label: i.severity.label, color: c),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Why it matters: ${i.why}',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 3),
            Text(
              'What you can do: ${i.whatToDo}',
              style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
            ),
            if (i.offers != null &&
                (i.offers == OrgAction.reapplyEffects
                    ? OrganizationLanguage.standingOf(a) != OrgStanding.unknown
                    : OrganizationLanguage.actionsFor(
                        a,
                      ).contains(i.offers))) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: ctrl.isProcessing.value
                    ? null
                    : () => showOrgActionDialog(
                        context,
                        action: i.offers!,
                        org: a,
                        ctrl: ctrl,
                      ),
                child: Text(OrganizationLanguage.actionLabelFor(i.offers!, a)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── OVERVIEW ──────────────────────────────────────────────────────────────

  Widget _overview(BuildContext context, AdminModel a, DateTime now) {
    final p = context.palette;
    final issues = detail.issues(now: now);
    final flagged = issues.where((i) => i.needsAttention).toList();
    final info = issues.where((i) => !i.needsAttention).toList();
    final unread = detail.unreadSections;
    final sub = OrganizationLanguage.subscriptionOf(a, now: now);
    final standing = OrganizationLanguage.standingOf(a);
    final trainersLive = detail.trainers.done.value
        ? detail.liveTrainers.length
        : null;
    final membersTotal =
        detail.memberTotal.value ??
        (detail.members.done.value ? detail.members.data.value!.length : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConsoleCard(
          title: 'HEALTH',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (detail.anyRelatedLoading && flagged.isEmpty)
                Text(
                  'Checking related records…',
                  style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
                )
              else if (flagged.isEmpty)
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: context.serena.statusActive,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Everything looks good',
                      style: AppText.label(
                        size: 14,
                      ).copyWith(color: p.textPrimary),
                    ),
                  ],
                )
              else
                for (final i in flagged) _issueTile(context, i, a),
              if (unread.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Not checked: ${unread.join(', ')} could not be loaded, so issues '
                    'there would not show here.',
                    style: AppText.body(size: 12).copyWith(color: p.error),
                  ),
                ),
              if (info.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'For information',
                  style: AppText.body(size: 11).copyWith(
                    color: p.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                for (final i in info) _issueTile(context, i, a),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'AT A GLANCE',
          child: Wrap(
            spacing: 28,
            runSpacing: 16,
            children: [
              ConsoleStat(
                label: 'Standing',
                value: standing.label,
                hint: standing.meaning,
              ),
              ConsoleStat(
                label: 'Subscription',
                value: sub.label,
                hint: sub.sourceLabel,
              ),
              ConsoleStat(label: 'Plan', value: sub.planName),
              ConsoleStat(
                label: 'Trainers',
                value: trainersLive == null
                    ? (detail.trainers.error.value != null ? '—' : '…')
                    : OrganizationLanguage.seatLine(
                        trainersLive,
                        a.subscriptionLimits.maxTrainers,
                        '',
                      ),
                hint: 'Live trainer accounts against the plan\'s trainer limit',
              ),
              ConsoleStat(
                label: 'Members',
                value: membersTotal == null
                    ? (detail.members.error.value != null ? '—' : '…')
                    : OrganizationLanguage.seatLine(
                        membersTotal,
                        a.subscriptionLimits.maxClients,
                        '',
                      ),
                hint: 'Member records against the plan\'s member limit',
              ),
              ConsoleStat(
                label: 'Payments on file',
                value: detail.receipts.done.value
                    ? '${detail.receipts.data.value!.length}'
                    : (detail.receipts.error.value != null ? '—' : '…'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'IN WORDS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Standing', standing.meaning),
              _kv(context, 'Operating', OrganizationLanguage.operatingLine(a)),
              _kv(
                context,
                'Subscription',
                '${sub.planName} — ${sub.label}. ${sub.sourceLabel}.'
                    '${sub.endsAt != null ? ' Ends ${OrganizationLanguage.exact(sub.endsAt)} (${OrganizationLanguage.relative(sub.endsAt, now: now)}).' : ''}',
              ),
              _kv(
                context,
                'Origin',
                OrganizationLanguage.originLine(
                  a,
                  accessRequestFound:
                      detail.requests.done.value &&
                      (detail.requests.data.value ?? const []).isNotEmpty,
                ),
              ),
              _kv(
                context,
                'Owner sign-in',
                OrganizationLanguage.lastSignInLine(a, now: now),
              ),
              _kv(context, 'Storefront', _storefrontLine(a)),
              if ((a.statusReason ?? '').trim().isNotEmpty)
                _kv(
                  context,
                  'Latest status note',
                  '"${a.statusReason!.trim()}"'
                      '${a.statusUpdatedAt != null ? ' — ${OrganizationLanguage.exactTime(a.statusUpdatedAt)}' : ''}'
                      '${(a.statusUpdatedBy ?? '').isNotEmpty ? ' by ${_actor(a.statusUpdatedBy!)}' : ''}',
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _storefrontLine(AdminModel a) {
    if (detail.storefront.error.value != null) return 'Could not be read';
    if (!detail.storefront.done.value) return 'Checking…';
    final sf = detail.storefront.data.value;
    if (sf == null) {
      return 'No member-facing storefront yet (cannot appear in Discover)';
    }
    final published = sf['published'] == true;
    final active = sf['orgActive'];
    final handle = (sf['handle'] ?? '').toString();
    return '${published ? 'Published' : 'Not published'}'
        '${handle.isNotEmpty ? ' · @$handle' : ''}'
        ' · ${active == true
            ? 'listed as operating'
            : active == false
            ? 'listed as not operating'
            : 'operating flag not stamped'}';
  }

  // ── PEOPLE ────────────────────────────────────────────────────────────────

  Widget _people(BuildContext context, AdminModel a, DateTime now) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section<List<TrainerModel>>(
          context,
          s: detail.trainers,
          title: 'TRAINERS',
          retry: detail.loadTrainers,
          body: (list) => _trainersBody(context, a, list, now),
        ),
        const SizedBox(height: 12),
        _section<List<ClientModel>>(
          context,
          s: detail.members,
          title: 'MEMBERS',
          retry: detail.loadMembers,
          body: (list) => _membersBody(context, a, list, now),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'WHAT YOU CAN DO HERE',
          child: Text(
            'Trainers and members are managed by the organization in the '
            'Trainersarena app — adding, pausing, removing and restoring trainers, '
            'and every member action, are the owner\'s. The platform sees them and '
            'cannot change them. Blocking the organization pauses all of its '
            'trainers at once.',
            style: AppText.body(
              size: 12.5,
            ).copyWith(color: context.palette.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _trainersBody(
    BuildContext context,
    AdminModel a,
    List<TrainerModel> list,
    DateTime now,
  ) {
    final p = context.palette;
    final live = list
        .where((t) => !OrganizationLanguage.trainerIsRemoved(t))
        .toList();
    final removed = list.where(OrganizationLanguage.trainerIsRemoved).toList();
    final operating = OrganizationLanguage.canOperate(a);
    if (list.isEmpty) {
      return Text(
        'No trainer accounts belong to this organization.',
        style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          OrganizationLanguage.seatLine(
            live.length,
            a.subscriptionLimits.maxTrainers,
            'trainers',
          ),
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 8),
        for (final t in live) _trainerRow(context, t, operating, now),
        if (removed.isNotEmpty)
          // ExpansionTile paints on the nearest Material; inside a decorated
          // card it needs its own, or the framework asserts.
          Material(
            color: Colors.transparent,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '${OrganizationLanguage.plural(removed.length, 'removed trainer')} '
                '(no longer occupy seats)',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              ),
              children: [
                for (final t in removed)
                  _trainerRow(context, t, operating, now),
              ],
            ),
          ),
      ],
    );
  }

  Widget _trainerRow(
    BuildContext context,
    TrainerModel t,
    bool operating,
    DateTime now,
  ) {
    final p = context.palette;
    final removed = OrganizationLanguage.trainerIsRemoved(t);
    final status = removed ? 'Removed' : _cap(t.status);
    final stale = !removed && t.orgActive != null && t.orgActive != operating;
    final access = removed
        ? 'sign-in disabled'
        : t.orgActive == null
        ? 'access state not stamped'
        : t.orgActive!
        ? 'app access on'
        : 'app access paused';
    return Semantics(
      label: '${t.name}, $status, $access',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.name.isEmpty ? 'Name not recorded' : t.name,
                    style: AppText.label(
                      size: 13,
                    ).copyWith(color: p.textPrimary),
                  ),
                  Text(
                    t.email.isEmpty ? 'No email' : t.email,
                    style: AppText.body(
                      size: 11.5,
                    ).copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            SerenaStatusPill(
              label: status,
              status: removed
                  ? SerenaStatus.neutral
                  : t.status == 'active'
                  ? SerenaStatus.active
                  : SerenaStatus.pending,
            ),
            ConsolePill(
              label: access + (stale ? ' · OUT OF STEP' : ''),
              color: stale ? context.serena.error : p.textMuted,
              icon: stale ? Icons.sync_problem : null,
            ),
            if ((t.specialization ?? '').isNotEmpty)
              Text(
                t.specialization!,
                style: AppText.body(
                  size: 11.5,
                ).copyWith(color: p.textSecondary),
              ),
            Text(
              'Joined ${OrganizationLanguage.exact(t.createdAt)}',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
            Text(
              t.lastLogin == null
                  ? 'never signed in'
                  : 'signed in ${OrganizationLanguage.relative(t.lastLogin, now: now)}',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
            Text(
              '${t.clientIds.length} members assigned',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _membersBody(
    BuildContext context,
    AdminModel a,
    List<ClientModel> list,
    DateTime now,
  ) {
    final p = context.palette;
    final total = detail.memberTotal.value;
    final trainerNames = <String, String>{
      for (final t in detail.trainers.data.value ?? const <TrainerModel>[])
        (t.uid.isNotEmpty ? t.uid : t.docId): t.name,
    };
    if (list.isEmpty && (total ?? 0) == 0) {
      return Text(
        'No member records belong to this organization.',
        style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
      );
    }
    final active = list.where((m) => m.membershipActive).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          total == null
              ? 'At least ${list.length} members (total could not be counted) · '
                    '$active with an active membership'
              : list.length < total
              ? '$total members · showing the first ${list.length} read · '
                    '$active of those with an active membership'
              : '$total members · $active with an active membership',
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 8),
        for (final m in list) _memberRow(context, m, trainerNames, a, now),
      ],
    );
  }

  Widget _memberRow(
    BuildContext context,
    ClientModel m,
    Map<String, String> trainerNames,
    AdminModel a,
    DateTime now,
  ) {
    final p = context.palette;
    final coachId = (m.trainerId ?? '').trim();
    final coach = coachId.isEmpty
        ? 'no coach'
        : coachId == detail.orgId
        ? 'coached by the owner'
        : trainerNames[coachId] != null
        ? 'coach ${trainerNames[coachId]}'
        : 'coach not in this organization';
    final foreign =
        coachId.isNotEmpty &&
        coachId != detail.orgId &&
        trainerNames[coachId] == null;
    return Semantics(
      label:
          '${m.name}, membership ${m.membershipActive ? 'active' : 'inactive'}, $coach',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.name.isEmpty ? 'Name not recorded' : m.name,
                    style: AppText.label(
                      size: 13,
                    ).copyWith(color: p.textPrimary),
                  ),
                  Text(
                    [
                          m.email,
                          m.phone,
                        ].where((s) => s.trim().isNotEmpty).join(' · ').isEmpty
                        ? 'No contact recorded'
                        : [
                            m.email,
                            m.phone,
                          ].where((s) => s.trim().isNotEmpty).join(' · '),
                    style: AppText.body(
                      size: 11.5,
                    ).copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            SerenaStatusPill(
              label: m.membershipActive
                  ? 'Membership active'
                  : 'No active membership',
              status: m.membershipActive
                  ? SerenaStatus.active
                  : SerenaStatus.neutral,
            ),
            ConsolePill(
              label: coach,
              color: foreign ? context.serena.statusWarning : p.textMuted,
            ),
            if ((m.goal ?? '').isNotEmpty)
              Text(
                m.goal!,
                style: AppText.body(
                  size: 11.5,
                ).copyWith(color: p.textSecondary),
              ),
            Text(
              'Joined ${OrganizationLanguage.exact(m.createdAt)}',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  // ── SUBSCRIPTION & PAYMENTS ───────────────────────────────────────────────

  Widget _subscription(BuildContext context, AdminModel a, DateTime now) {
    final p = context.palette;
    final sub = OrganizationLanguage.subscriptionOf(a, now: now);
    final l = a.subscriptionLimits;
    // ORG-4: the real whitelist is the TOP-LEVEL `features` the backend
    // writes. `metadata` is owner-editable — it used to be read here, so an
    // owner could plant premium "capabilities" in the founder's view.
    final features = a.features;
    final currentPlanId = (a.subscription?['planId'] ?? '').toString();
    final currentPlan =
        Get.isRegistered<SubscriptionController>() && currentPlanId.isNotEmpty
        ? Get.find<SubscriptionController>().plans
              .where((pl) => pl.docId == currentPlanId)
              .firstOrNull
        : null;
    final planDeclaresNone =
        currentPlan != null && !currentPlan.capabilities.values.any((v) => v);
    final canGrant = OrganizationLanguage.actionsFor(
      a,
    ).contains(OrgAction.grant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConsoleCard(
          title: 'CURRENT PLAN',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canGrant)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: ctrl.isProcessing.value
                        ? null
                        : () => showOrgActionDialog(
                            context,
                            action: OrgAction.grant,
                            org: a,
                            ctrl: ctrl,
                          ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 16),
                    label: Text(
                      OrganizationLanguage.actionLabelFor(OrgAction.grant, a),
                    ),
                  ),
                ),
              Wrap(
                spacing: 28,
                runSpacing: 14,
                children: [
                  ConsoleStat(label: 'Plan', value: sub.planName),
                  ConsoleStat(
                    label: 'State',
                    value: sub.label,
                    color: switch (sub.state) {
                      SubscriptionState.none => p.textMuted,
                      SubscriptionState.offBeforeEnd => context.serena.error,
                      SubscriptionState.active => context.serena.statusActive,
                      SubscriptionState.expiringSoon =>
                        context.serena.statusWarning,
                      SubscriptionState.activePastEnd ||
                      SubscriptionState.activeNoEndDate => context.serena.error,
                    },
                  ),
                  ConsoleStat(
                    label: 'Ends',
                    value: sub.endsAt == null
                        ? (a.malformedFields.contains('planExpiry')
                              ? 'Plan end date unreadable'
                              : 'No plan end date on record')
                        : '${OrganizationLanguage.exact(sub.endsAt)} · ${OrganizationLanguage.relative(sub.endsAt, now: now)}',
                    hint: sub.endsAt == null && sub.lastPaymentEndsAt != null
                        ? 'The last payment says ${OrganizationLanguage.exact(sub.lastPaymentEndsAt)}, but the expiry sweep reads only the plan end date'
                        : null,
                  ),
                  ConsoleStat(
                    label: 'Started',
                    value: sub.startedAt == null
                        ? 'Not recorded'
                        : OrganizationLanguage.exact(sub.startedAt),
                  ),
                  ConsoleStat(label: 'Source', value: sub.sourceLabel),
                ],
              ),
              const SizedBox(height: 14),
              _kv(
                context,
                'Operating flag',
                a.isSubscriptionActive
                    ? 'On — the rules let the organization write'
                    : 'Off — every organization write is refused',
              ),
              if (sub.reference != null)
                _kv(context, 'Payment reference', sub.reference!, copy: true),
              if (sub.amount != null)
                _kv(
                  context,
                  'Last amount recorded',
                  OrganizationLanguage.rupees(sub.amount!),
                ),
              if (sub.months != null)
                _kv(
                  context,
                  'Last term',
                  OrganizationLanguage.plural(sub.months!, 'month'),
                ),
              if ((a.subscription?['grantedBy'] ?? '').toString().isNotEmpty)
                _kv(
                  context,
                  'Recorded by',
                  _actor(a.subscription!['grantedBy'].toString()),
                ),
              if (sub.endsAt != null && a.isSubscriptionActive)
                _kv(
                  context,
                  'Renewal due',
                  '${OrganizationLanguage.exact(sub.endsAt)} · a payment recorded '
                      'before then extends from that date, after it restarts from the day it is recorded',
                ),
              Obx(() {
                final list = detail.receipts.data.value;
                if (list == null || list.isEmpty) {
                  return const SizedBox.shrink();
                }
                final latest = list.first;
                final line = OrganizationLanguage.receiptPricingLine(latest);
                return _kv(
                  context,
                  'Latest dated receipt read',
                  '${OrganizationLanguage.rupees(latest.amountPaid)} · '
                      '${OrganizationLanguage.receiptState(latest).label}'
                      '${line.isEmpty ? ' · pricing evidence not stamped' : ' · $line'}'
                      '${list.length >= kReceiptRowsLimit ? ' · among the first $kReceiptRowsLimit receipts read, which are not ordered by date' : ''}',
                );
              }),
              const SizedBox(height: 10),
              Text(
                'PLAN LIMITS',
                style: AppText.body(size: 11).copyWith(
                  color: p.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ConsolePill(
                    label: _limit('trainers', l.maxTrainers),
                    color: p.textSecondary,
                  ),
                  ConsolePill(
                    label: _limit('members', l.maxClients),
                    color: p.textSecondary,
                  ),
                  ConsolePill(
                    label: _limit('workout plans', l.maxWorkoutPlans),
                    color: p.textSecondary,
                  ),
                  ConsolePill(
                    label: _limit('diet plans', l.maxDietPlans),
                    color: p.textSecondary,
                  ),
                  if (features != null)
                    for (final f in features)
                      ConsolePill(label: f, color: p.accent),
                ],
              ),
              const SizedBox(height: 8),
              _kv(
                context,
                'Premium features',
                '${OrganizationLanguage.featuresLine(a)}'
                    '${features != null && features.isNotEmpty && planDeclaresNone ? ' — from an earlier plan: the current plan declares no capabilities, and granting it leaves this list as it was.' : ''}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section<List<SubscriptionModel>>(
          context,
          s: detail.receipts,
          title: 'PAYMENTS & RECEIPTS',
          retry: detail.loadReceipts,
          body: (list) => _receiptsBody(context, a, list, now),
        ),
      ],
    );
  }

  String _limit(String noun, int v) => v <= 0
      ? '$noun: not set'
      : v >= 100000000
      ? '$noun: unlimited'
      : '$noun: up to $v';

  Widget _receiptsBody(
    BuildContext context,
    AdminModel a,
    List<SubscriptionModel> list,
    DateTime now,
  ) {
    final p = context.palette;
    if (list.isEmpty) {
      return Text(
        a.isSubscriptionActive
            ? 'No payment record names this organization. Activations before '
                  'receipts existed have none.'
            : 'No payments recorded for this organization.',
        style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (list.length >= kReceiptRowsLimit)
          Text(
            'Showing the first $kReceiptRowsLimit receipts the database '
            'returned. They are read in storage order, not by date, so newer '
            'or older receipts may be missing from this list.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        for (final r in list) _receiptRow(context, a, r, now),
      ],
    );
  }

  Widget _receiptRow(
    BuildContext context,
    AdminModel a,
    SubscriptionModel r,
    DateTime now,
  ) {
    final p = context.palette;
    final state = OrganizationLanguage.receiptState(r);
    final color = switch (state) {
      ReceiptState.paid => context.serena.statusActive,
      ReceiptState.recordedManually => p.textSecondary,
      ReceiptState.legacyGateway => p.textSecondary,
      ReceiptState.unverified => context.serena.statusWarning,
      ReceiptState.partiallyRefunded ||
      ReceiptState.refunded => context.serena.error,
    };
    final canRefund = OrganizationLanguage.canRefund(r);
    return Semantics(
      label:
          'Receipt ${OrganizationLanguage.rupees(r.amountPaid)}, ${state.label}, '
          '${r.createdAtKnown ? OrganizationLanguage.exact(r.createdAt) : 'date not recorded'}',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  OrganizationLanguage.rupees(r.amountPaid),
                  style: AppText.label(size: 14).copyWith(color: p.textPrimary),
                ),
                ConsolePill(label: state.label, color: color),
                Text(
                  r.planName.isEmpty ? 'plan not named' : r.planName,
                  style: AppText.body(
                    size: 12.5,
                  ).copyWith(color: p.textSecondary),
                ),
                Text(
                  r.termKnown
                      ? OrganizationLanguage.plural(r.durationMonths, 'month')
                      : 'term not recorded',
                  style: AppText.body(
                    size: 12.5,
                  ).copyWith(color: p.textSecondary),
                ),
                Text(
                  r.createdAtKnown
                      ? OrganizationLanguage.exactTime(r.createdAt)
                      : 'date not recorded',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
                if (r.refundMinor > 0)
                  Text(
                    '${OrganizationLanguage.rupees(r.refundAmount)} refunded',
                    style: AppText.body(
                      size: 12,
                    ).copyWith(color: context.serena.error),
                  ),
                if (canRefund)
                  TextButton(
                    onPressed: ctrl.isProcessing.value
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => RefundReceiptDialog(
                              org: a,
                              receipt: r,
                              ctrl: ctrl,
                            ),
                          ),
                    child: const Text('Refund…'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              state.meaning,
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
            Text(
              '${OrganizationLanguage.receiptCoverageLine(r)}'
              '${r.razorpayPaymentId.isNotEmpty
                  ? ' · gateway ${r.razorpayPaymentId}'
                  : (r.reference ?? '').isNotEmpty
                  ? ' · reference ${r.reference}'
                  : r.paymentId != r.id
                  ? ' · reference ${r.paymentId}'
                  : ''}'
              '${!r.hasPricingEvidence && r.couponApplied ? ' · coupon ${r.couponCode ?? ''} (−${OrganizationLanguage.rupees(r.discountAmount.toDouble())})' : ''}',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
            if (OrganizationLanguage.receiptCoverageDetail(r).isNotEmpty)
              Text(
                OrganizationLanguage.receiptCoverageDetail(r),
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            // The refund ledger (C1): every refund with its amount, status,
            // source and date — console refunds AND ones made in the
            // Razorpay dashboard.
            for (final x in r.refunds)
              Text(
                'Refund: ${OrganizationLanguage.refundLine(x)}',
                style: AppText.body(size: 11.5).copyWith(
                  color: x.isFailed ? p.textMuted : context.serena.error,
                ),
              ),
            if (OrganizationLanguage.receiptPricingLine(r).isNotEmpty)
              Text(
                'Pricing evidence: ${OrganizationLanguage.receiptPricingLine(r)}',
                style: AppText.body(size: 11.5).copyWith(
                  color:
                      ((r.pricingDiscount ?? 0) > 0 || (r.overpayment ?? 0) > 0)
                      ? context.serena.statusWarning
                      : p.textMuted,
                ),
              )
            else
              Text(
                'Pricing evidence: not stamped (receipt predates the evidence) — '
                'the list price at the time cannot be recovered from this record.',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  // ── HISTORY ───────────────────────────────────────────────────────────────

  Widget _history(BuildContext context, AdminModel a, DateTime now) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section<List<AccessRequestModel>>(
          context,
          s: detail.requests,
          title: 'HOW IT ENTERED THE SYSTEM',
          retry: detail.loadRequests,
          body: (list) => _originBody(context, a, list, now),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'MODERATION TRAIL ON THE RECORD',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(
                context,
                'Current standing',
                OrganizationLanguage.standingOf(a).label,
              ),
              _kv(
                context,
                'Last status change',
                a.statusUpdatedAt == null
                    ? 'Not recorded on the record'
                    : '${OrganizationLanguage.exactTime(a.statusUpdatedAt)}'
                          '${(a.statusUpdatedBy ?? '').isNotEmpty ? ' by ${_actor(a.statusUpdatedBy!)}' : ''}',
              ),
              _kv(
                context,
                'Reason on file',
                (a.statusReason ?? '').trim().isEmpty
                    ? 'None'
                    : a.statusReason!.trim(),
              ),
              Obx(() {
                // ORG-5: the record's `approvedBy` is rewritten on EVERY
                // status change (a blocked organization names its blocker),
                // so the approver comes from the audit trail.
                final ap = detail.audit.done.value
                    ? OrganizationLanguage.approvalFromAudit(
                        detail.audit.data.value ?? const [],
                      )
                    : null;
                return _kv(
                  context,
                  'Approved by',
                  !detail.audit.done.value
                      ? (detail.audit.error.value != null
                            ? 'Unknown — the audit trail could not be read'
                            : 'Reading the audit trail…')
                      : ap == null
                      ? 'No approval in the audit rows read'
                      : '${_actor(ap.actorUid)} — ${ap.how}'
                            '${ap.at == null ? '' : ', ${OrganizationLanguage.exactTime(ap.at)}'} (from the audit trail)',
                );
              }),
              _kv(
                context,
                'approvedBy on the record',
                (a.approvedBy ?? '').isEmpty
                    ? 'Not recorded'
                    : '${_actor(a.approvedBy!)} — the backend rewrites this field on every status change, so it names the last person to change the status',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section<List<AuditLogModel>>(
          context,
          s: detail.audit,
          title: 'TIMELINE',
          retry: detail.loadAudit,
          body: (_) => _timelineBody(context, a, now),
        ),
        const SizedBox(height: 12),
        Text(
          'The timeline is built only from records that were written when things '
          'happened: the audit log, the access request and the payment receipts. '
          'The current state of '
          'the organization is never turned into history.',
          style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
        ),
      ],
    );
  }

  Widget _originBody(
    BuildContext context,
    AdminModel a,
    List<AccessRequestModel> list,
    DateTime now,
  ) {
    final p = context.palette;
    if (list.isEmpty) {
      return Text(
        '${OrganizationLanguage.originLine(a)}. No access request points to this '
        'organization.',
        style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (list.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${list.length} access requests claim this organization — see Health.',
              style: AppText.body(
                size: 12.5,
              ).copyWith(color: context.serena.error),
            ),
          ),
        for (final r in list) ...[
          Text(
            'Created from access request',
            style: AppText.label(size: 13).copyWith(color: p.textPrimary),
          ),
          _kv(
            context,
            'Requested by',
            '${r.ownerName.isEmpty ? 'Name not provided' : r.ownerName} · ${r.contactLine}',
          ),
          _kv(
            context,
            'Asked for',
            '${r.organizationName}'
                '${r.locationLine.isNotEmpty ? ' · ${r.locationLine}' : ''}'
                '${r.teamSize != null ? ' · team of ${r.teamSize}' : ''}',
          ),
          _kv(
            context,
            'Their reason',
            r.message.trim().isEmpty
                ? 'Reason not provided'
                : '"${r.message.trim()}"',
          ),
          _kv(
            context,
            'Requested on',
            OrganizationLanguage.exactTime(r.createdAt),
          ),
          if (r.paymentEvidence != null)
            _kv(
              context,
              'Payment recorded',
              '${OrganizationLanguage.rupees(r.paymentEvidence!.amount)} · ref ${r.paymentEvidence!.reference}'
                  '${r.paymentEvidence!.confirmedBy.isNotEmpty ? ' · by ${_actor(r.paymentEvidence!.confirmedBy)}' : ''}'
                  '${r.paymentEvidence!.confirmedAt != null ? ' · ${OrganizationLanguage.exactTime(r.paymentEvidence!.confirmedAt)}' : ''}',
            ),
          _kv(
            context,
            'Decision',
            '${_requestDecision(r)}'
                '${r.provisionedAt != null ? ' · ${OrganizationLanguage.exactTime(r.provisionedAt)}' : ''}',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openAccessRequest(r),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Open the access request'),
            ),
          ),
        ],
      ],
    );
  }

  String _requestDecision(AccessRequestModel r) {
    final created = r.statusHistory.where(
      (e) => e.status == 'organization_created',
    );
    if (created.isNotEmpty) {
      final by = created.last.by;
      return 'Organization created by ${by == 'prospect' ? 'the requester' : _actor(by)}';
    }
    return 'Request status: ${r.status}';
  }

  void _openAccessRequest(AccessRequestModel r) {
    if (Get.isRegistered<AccessRequestController>()) {
      final c = Get.find<AccessRequestController>();
      c.statusFilter.value = 'all';
      c.search.value = r.email.isNotEmpty ? r.email : r.organizationName;
    }
    if (Get.isRegistered<AdminRootController>()) {
      Get.find<AdminRootController>().changePage(_navAccessRequests);
    }
  }

  Widget _timelineBody(BuildContext context, AdminModel a, DateTime now) {
    final p = context.palette;
    // Receipts are history too: a founder reading "what happened to this
    // organization" must see the money next to the moderation — and every
    // REFUND at its own time, not only inside the receipt dated at the
    // original payment (ORG-6).
    final timeline = OrganizationLanguage.historyEvents(
      audit: detail.audit.data.value ?? const <AuditLogModel>[],
      requests: detail.requests.data.value ?? const <AccessRequestModel>[],
      receipts: detail.receipts.data.value ?? const <SubscriptionModel>[],
      actorOf: _actor,
    );
    if (timeline.isEmpty) {
      return Text(
        'No recorded platform actions for this organization yet. Actions taken '
        'before the audit log existed are not shown.',
        style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((detail.audit.data.value?.length ?? 0) >= kAuditRowsLimit)
          Text(
            'Built from the first $kAuditRowsLimit audit entries the database '
            'returned — read in storage order, not by date, so entries of any '
            'age may be missing. The Audit Log section has the full trail.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        for (final e in timeline) _eventRow(context, e, now),
      ],
    );
  }

  Widget _eventRow(BuildContext context, OrgEvent e, DateTime now) {
    final p = context.palette;
    final icon = switch (e.kind) {
      OrgEventKind.admin => Icons.gavel_outlined,
      OrgEventKind.payment => Icons.payments_outlined,
      OrgEventKind.system => Icons.schedule_outlined,
      OrgEventKind.origin => Icons.mark_email_read_outlined,
      OrgEventKind.record => Icons.description_outlined,
    };
    final when = e.at == null
        ? 'time not recorded'
        : '${OrganizationLanguage.exactTime(e.at)} · ${OrganizationLanguage.relative(e.at, now: now)}';
    return Semantics(
      label: '${e.title}. ${e.actor.isNotEmpty ? 'By ${e.actor}. ' : ''}$when',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: p.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    style: AppText.label(
                      size: 13,
                    ).copyWith(color: p.textPrimary),
                  ),
                  Text(
                    '${e.actor.isNotEmpty ? 'by ${e.actor} · ' : ''}$when · ${e.kind.label}',
                    style: AppText.body(
                      size: 11.5,
                    ).copyWith(color: p.textMuted),
                  ),
                  if (e.detail.trim().isNotEmpty)
                    Text(
                      e.detail,
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: p.textSecondary),
                    ),
                  if (e.technical.isNotEmpty)
                    Material(
                      color: Colors.transparent,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            'Technical details',
                            style: AppText.body(
                              size: 11,
                            ).copyWith(color: p.textMuted),
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                [
                                  'source: ${e.source}',
                                  for (final kv in e.technical.entries)
                                    '${kv.key}: ${kv.value}',
                                ].join('\n'),
                                style: AppText.body(
                                  size: 11,
                                ).copyWith(color: p.textMuted),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PROFILE & TECHNICAL ───────────────────────────────────────────────────

  Widget _profile(BuildContext context, AdminModel a, DateTime now) {
    final p = context.palette;
    String orDash(String? s) =>
        (s ?? '').trim().isEmpty ? 'Not recorded' : s!.trim();
    final sf = detail.storefront.data.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConsoleCard(
          title: 'BUSINESS IDENTITY',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Organization name', orDash(a.organizationName)),
              _kv(context, 'Address', orDash(a.address)),
              _kv(
                context,
                'Area / State / PIN',
                [a.area, a.state, a.pincode]
                        .map((s) => (s ?? '').trim())
                        .where((s) => s.isNotEmpty)
                        .join(' · ')
                        .isEmpty
                    ? 'Not recorded'
                    : [a.area, a.state, a.pincode]
                          .map((s) => (s ?? '').trim())
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
              ),
              _kv(context, 'GST number', orDash(a.gstNumber), copy: true),
              _kv(context, 'PAN', orDash(a.panNumber), copy: true),
              _kv(
                context,
                'Languages',
                a.spokenLanguages.isEmpty
                    ? 'Not recorded'
                    : a.spokenLanguages.join(', '),
              ),
              _kv(context, 'Verified flag', a.isVerified ? 'Yes' : 'No'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'OWNER',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'What the organization record says. The owner can edit these '
                  'fields (and the creation date and sign-in time), so they are '
                  'not platform facts; the sign-in account itself lives in '
                  'Firebase Authentication.',
                  style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                ),
              ),
              _kv(context, 'Name', OrganizationLanguage.ownerName(a)),
              _kv(
                context,
                'Email on the record',
                OrganizationLanguage.ownerEmail(a),
                copy: true,
              ),
              _kv(context, 'Phone', orDash(a.phone), copy: true),
              _kv(context, 'Role on record', orDash(a.role)),
              _kv(
                context,
                'Sign-in',
                OrganizationLanguage.lastSignInLine(a, now: now),
              ),
              _kv(
                context,
                'Sign-in enabled',
                OrganizationLanguage.standingOf(a) == OrgStanding.blocked
                    ? 'Disabled by the block (the backend disables the account when blocking)'
                    : 'Enabled, unless the account was disabled outside this console — '
                          'the console cannot read Firebase Auth directly',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'STOREFRONT (MEMBER-FACING PAGE)',
          child: Obx(() {
            if (detail.storefront.error.value != null) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Could not be read. ${detail.storefront.error.value!.message}',
                      style: AppText.body(size: 12.5).copyWith(color: p.error),
                    ),
                  ),
                  TextButton(
                    onPressed: detail.loadStorefront,
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            if (!detail.storefront.done.value) {
              return const ConsoleSkeletonRow();
            }
            if (sf == null) {
              return Text(
                'No storefront yet — the owner builds it in their app.',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(
                  context,
                  'Published',
                  sf['published'] == true ? 'Yes' : 'No',
                ),
                _kv(context, 'Handle', orDash(sf['handle']?.toString())),
                _kv(
                  context,
                  'Listed as operating',
                  '${sf['orgActive'] ?? 'not stamped'}',
                ),
                _kv(
                  context,
                  'Rating',
                  sf['rating'] == null
                      ? 'None'
                      : '${sf['rating']} (${sf['reviewCount'] ?? 0} reviews)',
                ),
                _kv(context, 'City', orDash(sf['city']?.toString())),
              ],
            );
          }),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'TECHNICAL DETAILS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(
                context,
                'Organization id (owner uid)',
                detail.orgId,
                copy: true,
              ),
              if (a.uid != a.docId)
                _kv(context, 'uid field', a.uid, copy: true),
              _kv(
                context,
                'Record created (owner-editable)',
                a.createdAtKnown
                    ? OrganizationLanguage.exactTime(a.createdAt)
                    : 'not recorded',
              ),
              _kv(
                context,
                'Record updated',
                OrganizationLanguage.exactTime(a.updatedAt),
              ),
              _kv(context, 'Raw status', a.status),
              _kv(context, 'isSubscriptionActive', '${a.isSubscriptionActive}'),
              _kv(
                context,
                'planExpiry',
                a.planExpiry?.toIso8601String() ?? 'null',
              ),
              _kv(
                context,
                'metadata.createdFrom (owner-editable)',
                orDash(a.metadata?['createdFrom']?.toString()),
              ),
              _kv(
                context,
                'features (top-level)',
                a.features == null ? 'absent' : '[${a.features!.join(', ')}]',
              ),
              if (a.hasMalformedFields)
                _kv(context, 'Malformed fields', a.malformedFields.join(', ')),
              _kv(
                context,
                'Trainer seat ids',
                a.trainerIds.isEmpty ? 'none' : a.trainerIds.join(', '),
                copy: true,
              ),
              _kv(
                context,
                'subscription map',
                a.subscription == null
                    ? 'null'
                    : a.subscription!.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('\n'),
                copy: true,
              ),
              Obx(() => _kv(context, 'Quota alert', _quotaLine())),
              Obx(
                () => _kv(
                  context,
                  'Incidents',
                  detail.incidents.done.value
                      ? (detail.incidents.data.value!.isEmpty
                            ? 'none'
                            : detail.incidents.data.value!
                                  .map(
                                    (i) =>
                                        '${i['type']} · ${i['status']} · ${i['id']}',
                                  )
                                  .join('\n'))
                      : 'not read',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _quotaLine() {
    if (!detail.quota.done.value) return 'not read';
    final q = detail.quota.data.value;
    if (q == null) return 'none';
    final v = q['violations'];
    final parts = <String>[];
    if (v is List) {
      for (final x in v) {
        if (x is Map) {
          parts.add('${x['resource']} ${x['used']} of ${x['limit']}');
        }
      }
    }
    return '${q['status'] ?? 'open'}${parts.isEmpty ? '' : ' · ${parts.join(', ')}'}';
  }

  String _cap(String s) =>
      s.isEmpty ? 'Unknown' : '${s[0].toUpperCase()}${s.substring(1)}';
}
