// TRAINER WORKSPACE — one coach, completely, read-only.
//
// Answers, top to bottom: who is this, which organization, can they work
// right now and why not, who do they coach, what has the platform recorded
// about them, and where the platform's real lever is (the organization).

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/admin_controller.dart';
import '../../controllers/admin_root_controller.dart';
import '../../controllers/platform_staff_controller.dart';
import '../../controllers/trainer_controller.dart';
import '../../controllers/organization_detail_controller.dart' show Section;
import '../../controllers/trainer_detail_controller.dart';
import '../../core/services/organization_language.dart';
import '../../core/services/trainer_language.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/console/console_chrome.dart';
import '../../core/widgets/serena/serena_ui.dart';
import '../../models/clints_model.dart';
import '../../models/trainer_model.dart';
import '../organization/organization_workspace.dart'
    show severityColor, severityIcon;
import '../trainers_screen.dart' show standingStatus;

/// Organizations' page index — stable identifier, see console_destinations.
const int _navOrganizations = 1;

class TrainerWorkspace extends StatelessWidget {
  const TrainerWorkspace({super.key, required this.ctrl, required this.detail});

  final TrainerController ctrl;
  final TrainerDetailController detail;

  static const _tabs = <(String, String)>[
    ('overview', 'Overview'),
    ('members', 'Members coached'),
    ('history', 'History'),
    ('profile', 'Profile & technical'),
  ];

  String _actor(String uid, TrainerModel t) {
    String? staff(String u) {
      if (!Get.isRegistered<PlatformStaffController>()) return null;
      for (final s in Get.find<PlatformStaffController>().staff) {
        if (s.uid == u) return s.displayEmail;
      }
      return null;
    }

    final me = Get.isRegistered<AdminController>()
        ? Get.find<AdminController>().currentUid()
        : null;
    if (uid == (t.assignedBy ?? '')) return 'the organization owner';
    if (uid == t.docId || uid == t.uid) return 'the trainer';
    return OrganizationLanguage.actor(uid, currentUid: me, staffName: staff);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final now = ctrl.clock();
      final t = detail.trainer.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _backRow(context),
          const SizedBox(height: 12),
          if (detail.loading.value && t == null)
            const Column(
              children: [
                ConsoleSkeletonRow(),
                SizedBox(height: 10),
                ConsoleSkeletonRow(),
              ],
            )
          else if (detail.notFound.value)
            ConsoleEmptyState(
              icon: Icons.search_off,
              title: 'Trainer not found',
              message:
                  'No trainer record exists with id ${detail.trainerId}. It may have '
                  'been removed by a backend correction, or the link is stale.',
              action: TextButton(
                onPressed: ctrl.closeTrainer,
                child: const Text('Back to all trainers'),
              ),
            )
          else if (t == null && detail.error.value != null)
            ConsoleErrorState(
              error: detail.error.value!,
              onRetry: detail.listen,
            )
          else if (t != null) ...[
            _header(context, t, now),
            const SizedBox(height: 12),
            _tabBar(context),
            const SizedBox(height: 14),
            switch (detail.tab.value) {
              'members' => _members(context, t, now),
              'history' => _history(context, t, now),
              'profile' => _profile(context, t, now),
              _ => _overview(context, t, now),
            },
          ],
        ],
      );
    });
  }

  Widget _backRow(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        TextButton.icon(
          onPressed: ctrl.closeTrainer,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('All trainers'),
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
          message: 'Reload members, history and profile',
          child: IconButton(
            onPressed: detail.loadAll,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ),
      ],
    );
  }

  List<TrainerIssue> _issues(TrainerModel t, DateTime now) {
    final out = [
      ...TrainerLanguage.issues(
        t,
        org: ctrl.orgOf(t),
        orgKnown: ctrl.orgsKnown,
        now: now,
      ),
      if (detail.members.done.value)
        ...TrainerLanguage.memberIssues(t, detail.members.data.value!),
    ];
    return TrainerLanguage.sortIssues(out);
  }

  Widget _header(BuildContext context, TrainerModel t, DateTime now) {
    final p = context.palette;
    final standing = TrainerLanguage.standingOf(t);
    final org = ctrl.orgOf(t);
    final issues = _issues(t, now);
    final flagged = issues.where((i) => i.needsAttention).toList();
    final name = TrainerLanguage.displayName(t);
    final working = TrainerLanguage.workingLine(t, org);
    return ConsoleCard(
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 720;
          final factW = box.maxWidth - (narrow ? 70 : 90);
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(context, t, size: narrow ? 44 : 56),
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
                        if (standing != TrainerStanding.removed)
                          ConsolePill(
                            label: TrainerLanguage.accessLabel(t),
                            color: t.orgActive == true
                                ? context.serena.statusActive
                                : p.textMuted,
                          ),
                        if (flagged.isNotEmpty)
                          ConsolePill(
                            label:
                                flagged.first.severity ==
                                    OrgIssueSeverity.critical
                                ? 'Urgent · ${flagged.length}'
                                : 'Needs attention · ${flagged.length}',
                            color: severityColor(
                              context,
                              flagged.first.severity,
                            ),
                            icon: severityIcon(flagged.first.severity),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      working,
                      style: AppText.label(size: 13).copyWith(
                        color: working.startsWith('Working')
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
                          Icons.corporate_fare_outlined,
                          ctrl.orgName(t),
                          factW,
                        ),
                        _fact(
                          context,
                          Icons.mail_outline,
                          TrainerLanguage.email(t),
                          factW,
                        ),
                        if ((t.specialization ?? '').trim().isNotEmpty)
                          _fact(
                            context,
                            Icons.sports_gymnastics_outlined,
                            t.specialization!.trim(),
                            factW,
                          ),
                        _fact(
                          context,
                          Icons.calendar_today_outlined,
                          TrainerLanguage.joinedLine(t, now: now),
                          factW,
                        ),
                        _fact(
                          context,
                          Icons.login_outlined,
                          TrainerLanguage.signInLine(t, now: now),
                          factW,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((t.assignedBy ?? '').isNotEmpty)
                MergeSemantics(
                  child: Semantics(
                    label: 'Open organization: ${ctrl.orgName(t)}',
                    child: FilledButton.icon(
                      onPressed: () => _openOrganization(t),
                      icon: const Icon(Icons.corporate_fare_outlined, size: 16),
                      label: const Text('Open organization'),
                    ),
                  ),
                ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              const SizedBox(height: 14),
              narrow
                  ? actions
                  : Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        },
      ),
    );
  }

  void _openOrganization(TrainerModel t) {
    final id = (t.assignedBy ?? '').trim();
    if (id.isEmpty) return;
    if (Get.isRegistered<AdminController>()) {
      Get.find<AdminController>().openOrganizationFromElsewhere(id);
    }
    if (Get.isRegistered<AdminRootController>()) {
      Get.find<AdminRootController>().changePage(_navOrganizations);
    }
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

  Widget _avatar(BuildContext context, TrainerModel t, {double size = 48}) {
    final p = context.palette;
    final url = (t.profilePicUrl ?? '').trim();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Text(
        TrainerLanguage.initial(t),
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

  Widget _tabBar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        return Obx(() {
          final cur = detail.tab.value;
          final total =
              detail.memberTotal.value ?? detail.members.data.value?.length;
          String label(String key, String base) {
            if (narrow) {
              return switch (key) {
                'members' => 'Members',
                'profile' => 'Profile',
                _ => base,
              };
            }
            return key == 'members' && total != null ? '$base · $total' : base;
          }

          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (key, base) in _tabs)
                ConsoleChip(
                  label: label(key, base),
                  active: cur == key,
                  onTap: () => detail.tab.value = key,
                ),
            ],
          );
        });
      },
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

  Widget _issueTile(BuildContext context, TrainerIssue i) {
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
          ],
        ),
      ),
    );
  }

  Widget _section<T>(
    BuildContext context, {
    required Section<T> s,
    required String title,
    required Future<void> Function() retry,
    required Widget Function(T data) body,
  }) {
    final p = context.palette;
    return ConsoleCard(
      title: title,
      child: Obx(() {
        if (s.loading.value && !s.done.value) return const ConsoleSkeletonRow();
        final err = s.error.value;
        if (err != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 16, color: p.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This section could not be loaded, so it may be hiding records. ${err.message}',
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

  // ── OVERVIEW ──────────────────────────────────────────────────────────────

  Widget _overview(BuildContext context, TrainerModel t, DateTime now) {
    final p = context.palette;
    final issues = _issues(t, now);
    final flagged = issues.where((i) => i.needsAttention).toList();
    final info = issues.where((i) => !i.needsAttention).toList();
    final unread = detail.unreadSections;
    final org = ctrl.orgOf(t);
    final standing = TrainerLanguage.standingOf(t);
    final total =
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
              if (flagged.isEmpty &&
                  detail.members.loading.value &&
                  !detail.members.done.value)
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
                for (final i in flagged) _issueTile(context, i),
              if (!ctrl.orgsKnown || ctrl.orgsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ctrl.orgsError != null
                        ? 'Not checked: the organization list could not be loaded, so organization-related issues would not show here.'
                        : 'The organization list is still loading; organization-related checks follow.',
                    style: AppText.body(size: 12).copyWith(
                      color: ctrl.orgsError != null ? p.error : p.textMuted,
                    ),
                  ),
                ),
              if (unread.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Not checked: ${unread.join(', ')} could not be loaded, so issues there would not show here.',
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
                for (final i in info) _issueTile(context, i),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'ORGANIZATION',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Belongs to', ctrl.orgName(t)),
              if (org != null) ...[
                _kv(
                  context,
                  'Organization standing',
                  OrganizationLanguage.standingOf(org).label,
                ),
                _kv(
                  context,
                  'Organization operating',
                  OrganizationLanguage.operatingLine(org),
                ),
                _kv(
                  context,
                  'Owner',
                  '${OrganizationLanguage.ownerName(org)} · ${OrganizationLanguage.ownerEmail(org)}',
                ),
                _kv(
                  context,
                  'Trainer seats',
                  OrganizationLanguage.seatLine(
                    org.trainerIds.length,
                    org.subscriptionLimits.maxTrainers,
                    'in use',
                  ),
                ),
                _kv(
                  context,
                  'On the seat list',
                  org.trainerIds.contains(TrainerLanguage.id(t)) ? 'Yes' : 'No',
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'The platform does not manage trainers directly: activating, pausing, removing, '
                'restoring and permissions are the owner\'s, in the Trainersarena app. What the '
                'platform can do is act on the organization — approve, block, reactivate or record '
                'a payment — and every trainer inherits the result.',
                style: AppText.body(
                  size: 12.5,
                ).copyWith(color: p.textSecondary),
              ),
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
                label: 'App access',
                value: TrainerLanguage.accessLabel(t),
              ),
              ConsoleStat(
                label: 'Members coached',
                value: total == null
                    ? (detail.members.error.value != null ? '—' : '…')
                    : '$total',
                hint: 'Members whose coach is this trainer',
              ),
              ConsoleStat(
                label: 'Permissions',
                value: TrainerLanguage.permissionsLine(t.permissions),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── MEMBERS ───────────────────────────────────────────────────────────────

  Widget _members(BuildContext context, TrainerModel t, DateTime now) {
    return _section<List<ClientModel>>(
      context,
      s: detail.members,
      title: 'MEMBERS COACHED',
      retry: detail.loadMembers,
      body: (list) {
        final p = context.palette;
        final total = detail.memberTotal.value;
        if (list.isEmpty && (total ?? 0) == 0) {
          return Text(
            'No member has this trainer as their coach.',
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          );
        }
        final active = list.where((m) => m.membershipActive).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              total == null
                  ? 'At least ${list.length} members (total could not be counted) · $active with an active membership'
                  : '$total members · $active with an active membership'
                        '${list.length < total ? ' · showing the first ${list.length}' : ''}',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 8),
            for (final m in list) _memberRow(context, m, t),
          ],
        );
      },
    );
  }

  Widget _memberRow(BuildContext context, ClientModel m, TrainerModel t) {
    final p = context.palette;
    final sameOrg = (m.adminId ?? '') == (t.assignedBy ?? '');
    return Semantics(
      label:
          '${m.name}, membership ${m.membershipActive ? 'active' : 'inactive'}'
          '${sameOrg ? '' : ', belongs to a different organization'}',
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
            if (!sameOrg)
              ConsolePill(
                label: 'Different organization',
                color: context.serena.error,
                icon: Icons.sync_problem,
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

  // ── HISTORY ───────────────────────────────────────────────────────────────

  Widget _history(BuildContext context, TrainerModel t, DateTime now) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          context,
          s: detail.audit,
          title: 'PLATFORM HISTORY',
          retry: detail.loadAudit,
          body: (list) {
            final events = TrainerLanguage.timeline([
              for (final l in list)
                if (TrainerLanguage.fromAudit(l, actorOf: (u) => _actor(u, t))
                    case final e?)
                  e,
            ]);
            if (events.isEmpty) {
              return Text(
                'No recorded platform actions for this trainer yet. Actions taken before the '
                'audit log existed are not shown.',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (list.length >= kTrainerAuditRowsLimit)
                  Text(
                    'Showing the most recent $kTrainerAuditRowsLimit entries; older ones are in the Audit Log.',
                    style: AppText.body(size: 12).copyWith(color: p.textMuted),
                  ),
                for (final e in events) _eventRow(context, e, now),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'WHAT IS NOT SHOWN HERE',
          child: Text(
            'Employment records, salary, HR documents, notes and HR events are the organization\'s '
            'private staff records. The platform deliberately has no access to them, so they never '
            'appear in this console.',
            style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _eventRow(BuildContext context, TrainerEvent e, DateTime now) {
    final p = context.palette;
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
            Icon(Icons.history, size: 16, color: p.textMuted),
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
                    '${e.actor.isNotEmpty ? 'by ${e.actor} · ' : ''}$when',
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

  Widget _profile(BuildContext context, TrainerModel t, DateTime now) {
    final p = context.palette;
    String orDash(String? s) =>
        (s ?? '').trim().isEmpty ? 'Not recorded' : s!.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConsoleCard(
          title: 'PROFILE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Name', TrainerLanguage.displayName(t)),
              _kv(
                context,
                'Sign-in email',
                TrainerLanguage.email(t),
                copy: true,
              ),
              _kv(context, 'Phone', orDash(t.phone), copy: true),
              _kv(context, 'Specialization', orDash(t.specialization)),
              _kv(context, 'Experience', orDash(t.experience)),
              _kv(context, 'Bio', orDash(t.bio)),
              _kv(context, 'Verified flag', t.isVerified ? 'Yes' : 'No'),
              _kv(
                context,
                'Permissions',
                TrainerLanguage.permissionsLine(t.permissions),
              ),
              _kv(context, 'Sign-in enabled', switch (TrainerLanguage.standingOf(
                t,
              )) {
                TrainerStanding.working =>
                  'Yes, unless changed outside the platform — the console cannot read Firebase Auth directly',
                TrainerStanding.onHold =>
                  'No — the backend disables sign-in when a trainer is put on hold or restored',
                TrainerStanding.removed =>
                  'No — disabled when the trainer was removed',
                TrainerStanding.unknown => 'Unknown',
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'PUBLIC COACH PROFILE (WHAT MEMBERS SEE)',
          child: Obx(() {
            final s = detail.coachProfile;
            if (s.error.value != null) {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Could not be read. ${s.error.value!.message}',
                      style: AppText.body(size: 12.5).copyWith(color: p.error),
                    ),
                  ),
                  TextButton(
                    onPressed: detail.loadCoachProfile,
                    child: const Text('Retry'),
                  ),
                ],
              );
            }
            if (!s.done.value) return const ConsoleSkeletonRow();
            final cp = s.data.value;
            if (cp == null) {
              return Text(
                'No public profile has been projected for this trainer yet.',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(context, 'Shown as', orDash(cp['name']?.toString())),
                _kv(context, 'Title', orDash(cp['title']?.toString())),
                _kv(context, 'Listed status', orDash(cp['status']?.toString())),
                _kv(context, 'Verified', cp['verified'] == true ? 'Yes' : 'No'),
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
                'Trainer id (Auth uid)',
                TrainerLanguage.id(t),
                copy: true,
              ),
              _kv(context, 'Organization id', orDash(t.assignedBy), copy: true),
              _kv(context, 'Raw status', t.status),
              _kv(context, 'isDeleted', '${t.isDeleted}'),
              _kv(
                context,
                'removedAt',
                t.removedAt?.toIso8601String() ?? 'null',
              ),
              _kv(context, 'orgActive', '${t.orgActive}'),
              _kv(
                context,
                'createdFrom',
                orDash(t.metadata?['createdFrom']?.toString()),
              ),
              _kv(
                context,
                'Record created',
                OrganizationLanguage.exactTime(t.createdAt),
              ),
              _kv(
                context,
                'Record updated',
                OrganizationLanguage.exactTime(t.updatedAt),
              ),
              _kv(
                context,
                'Legacy clientIds field',
                t.clientIds.isEmpty
                    ? 'empty'
                    : '${t.clientIds.length} ids (not maintained by the backend — see Members coached)',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
