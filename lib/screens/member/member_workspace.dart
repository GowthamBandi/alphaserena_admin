// MEMBER WORKSPACE — one member record, completely, read-only.
//
// Answers, top to bottom: who is this, which organization and coach, is their
// membership running and paid for, are they being served and using the app,
// what have they said, what has the platform recorded about them, and where
// the platform's real levers are (the organization, the trainer, Settlements).

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/admin_controller.dart';
import '../../controllers/admin_root_controller.dart';
import '../../controllers/client_controller.dart';
import '../../controllers/member_detail_controller.dart';
import '../../controllers/organization_detail_controller.dart' show Section;
import '../../controllers/platform_staff_controller.dart';
import '../../controllers/settlement_controller.dart';
import '../../controllers/trainer_controller.dart';
import '../../core/services/member_language.dart';
import '../../core/services/organization_language.dart';
import '../../core/services/trainer_language.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/console/console_chrome.dart';
import '../../core/widgets/serena/serena_ui.dart';
import '../../models/clints_model.dart';
import '../../models/member_payment_model.dart';
import '../../models/settlement_model.dart';
import '../clients_screen.dart' show memberAvatar, membershipStatus;
import '../organization/organization_workspace.dart'
    show severityColor, severityIcon;

/// Stable page ids — see console_destinations.dart.
const int _navOrganizations = 1;
const int _navTrainers = 2;
const int _navSettlements = 14;

class MemberWorkspace extends StatelessWidget {
  const MemberWorkspace({super.key, required this.ctrl, required this.detail});

  final ClientController ctrl;
  final MemberDetailController detail;

  static const _tabs = <(String, String)>[
    ('overview', 'Overview'),
    ('membership', 'Membership & payments'),
    ('activity', 'Coaching & activity'),
    ('voice', 'Feedback & history'),
    ('profile', 'Profile & technical'),
  ];

  String _actor(String uid, ClientModel m) {
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
    if (uid.isEmpty) return 'the system';
    if (uid == (m.adminId ?? '')) return 'the organization owner';
    if (uid == m.authUid) return 'the member';
    if ((m.trainerId ?? '').isNotEmpty && uid == m.trainerId) {
      return 'the coach';
    }
    if (Get.isRegistered<TrainerController>()) {
      final t = Get.find<TrainerController>().byId(uid);
      if (t != null) return 'trainer ${TrainerLanguage.displayName(t)}';
    }
    return OrganizationLanguage.actor(uid, currentUid: me, staffName: staff);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final now = ctrl.clock();
      final m = detail.member.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _backRow(context),
          const SizedBox(height: 12),
          if (detail.loading.value && m == null)
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
              title: 'Member not found',
              message:
                  'No member record exists with id ${detail.memberId}. The owner '
                  'may have deleted it, or the link is stale.',
              action: TextButton(
                onPressed: ctrl.closeMember,
                child: const Text('Back to all members'),
              ),
            )
          else if (m == null && detail.error.value != null)
            ConsoleErrorState(
              error: detail.error.value!,
              onRetry: detail.listen,
            )
          else if (m != null) ...[
            _header(context, m, now),
            const SizedBox(height: 12),
            _tabBar(context),
            const SizedBox(height: 14),
            switch (detail.tab.value) {
              'membership' => _membership(context, m, now),
              'activity' => _activity(context, m, now),
              'voice' => _voice(context, m, now),
              'profile' => _profile(context, m, now),
              _ => _overview(context, m, now),
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
          onPressed: ctrl.closeMember,
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('All members'),
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
          message: 'Reload payments, activity, feedback and history',
          child: IconButton(
            onPressed: detail.loadAll,
            icon: const Icon(Icons.refresh, size: 18),
          ),
        ),
      ],
    );
  }

  List<MemberIssue> _issues(ClientModel m, DateTime now) {
    final out = [
      ...ctrl.issuesOf(m, now: now),
      if (detail.payments.done.value)
        ...MemberLanguage.paymentIssues(detail.payments.data.value!),
      if (detail.siblings.done.value)
        ...MemberLanguage.siblingIssues(detail.siblings.data.value!.length),
    ];
    return MemberLanguage.sortIssues(out);
  }

  // ── header ────────────────────────────────────────────────────────────────

  Widget _header(BuildContext context, ClientModel m, DateTime now) {
    final p = context.palette;
    final state = MemberLanguage.membershipState(m, now: now);
    final issues = _issues(m, now);
    final flagged = issues.where((i) => i.needsAttention).toList();
    final name = MemberLanguage.displayName(m);
    final membership = MemberLanguage.membershipLine(m, now: now);
    final link = MemberLanguage.accountLink(m);
    return ConsoleCard(
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 720;
          final factW = box.maxWidth - (narrow ? 70 : 90);
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              memberAvatar(context, m, size: narrow ? 44 : 56),
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
                          label: state.label,
                          status: membershipStatus(state),
                        ),
                        ConsolePill(
                          label: link.label,
                          color: link == AccountLink.linked
                              ? context.serena.statusActive
                              : p.textMuted,
                          icon: link == AccountLink.linked
                              ? Icons.link
                              : Icons.link_off_outlined,
                        ),
                        if (MemberLanguage.statusIsInactive(m))
                          ConsolePill(
                            label: 'Switched off by owner',
                            color: p.textMuted,
                            icon: Icons.toggle_off_outlined,
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
                      membership,
                      style: AppText.label(size: 13).copyWith(
                        color: state.isCurrent
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
                          ctrl.orgName(m),
                          factW,
                        ),
                        _fact(
                          context,
                          Icons.sports_gymnastics_outlined,
                          ctrl.coachLine(m),
                          factW,
                        ),
                        _fact(
                          context,
                          Icons.alternate_email,
                          MemberLanguage.contactLine(m),
                          factW,
                        ),
                        _fact(
                          context,
                          Icons.calendar_today_outlined,
                          MemberLanguage.joinedLine(m, now: now),
                          factW,
                        ),
                        _fact(
                          context,
                          Icons.bolt_outlined,
                          MemberLanguage.activityLine(m, now: now),
                          factW,
                        ),
                        if (MemberLanguage.goalOf(m) != null)
                          _fact(
                            context,
                            Icons.flag_outlined,
                            'Goal: ${MemberLanguage.goalOf(m)}',
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
              if ((m.adminId ?? '').isNotEmpty)
                MergeSemantics(
                  child: Semantics(
                    label: 'Open organization: ${ctrl.orgName(m)}',
                    child: FilledButton.icon(
                      onPressed: () => _openOrganization(m),
                      icon: const Icon(Icons.corporate_fare_outlined, size: 16),
                      label: const Text('Open organization'),
                    ),
                  ),
                ),
              if (!MemberLanguage.isOwnerCoached(m))
                MergeSemantics(
                  child: Semantics(
                    label: 'Open trainer: ${ctrl.coachLine(m)}',
                    child: OutlinedButton.icon(
                      onPressed: () => _openTrainer(m),
                      icon: const Icon(
                        Icons.sports_gymnastics_outlined,
                        size: 16,
                      ),
                      label: const Text('Open trainer'),
                    ),
                  ),
                ),
              MergeSemantics(
                child: Semantics(
                  label: 'Open settlements for this member',
                  child: OutlinedButton.icon(
                    onPressed: () => _openSettlements(m),
                    icon: const Icon(Icons.account_balance_outlined, size: 16),
                    label: const Text('Settlements'),
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

  void _openOrganization(ClientModel m) {
    final id = (m.adminId ?? '').trim();
    if (id.isEmpty) return;
    if (Get.isRegistered<AdminController>()) {
      Get.find<AdminController>().openOrganizationFromElsewhere(id);
    }
    if (Get.isRegistered<AdminRootController>()) {
      Get.find<AdminRootController>().changePage(_navOrganizations);
    }
  }

  void _openTrainer(ClientModel m) {
    final id = (m.trainerId ?? '').trim();
    if (id.isEmpty) return;
    if (Get.isRegistered<TrainerController>()) {
      Get.find<TrainerController>().openTrainerFromElsewhere(id);
    }
    if (Get.isRegistered<AdminRootController>()) {
      Get.find<AdminRootController>().changePage(_navTrainers);
    }
  }

  void _openSettlements(ClientModel m) {
    if (Get.isRegistered<SettlementController>()) {
      // The Settlements search matches `clientId`; the record id is the key.
      Get.find<SettlementController>().search.value = m.docId;
    }
    if (Get.isRegistered<AdminRootController>()) {
      Get.find<AdminRootController>().changePage(_navSettlements);
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

  Widget _tabBar(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 700;
        return Obx(() {
          final cur = detail.tab.value;
          String label(String key, String base) => narrow
              ? switch (key) {
                  'membership' => 'Membership',
                  'activity' => 'Activity',
                  'voice' => 'Feedback',
                  'profile' => 'Profile',
                  _ => base,
                }
              : base;
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
            width: 160,
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

  Widget _issueTile(BuildContext context, MemberIssue i) {
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
    Widget? trailing,
  }) {
    final p = context.palette;
    return ConsoleCard(
      title: title,
      trailing: trailing,
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

  Widget _muted(BuildContext context, String text) => Text(
    text,
    style: AppText.body(size: 12.5).copyWith(color: context.palette.textMuted),
  );

  Widget _listRow(
    BuildContext context, {
    required String title,
    String subtitle = '',
    String trailing = '',
    IconData icon = Icons.circle_outlined,
    Color? tone,
    Map<String, dynamic> technical = const {},
    bool announce = true,
  }) {
    final p = context.palette;
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: tone ?? p.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.label(
                        size: 13,
                      ).copyWith(color: p.textPrimary),
                    ),
                    if (subtitle.trim().isNotEmpty)
                      Text(
                        subtitle,
                        style: AppText.body(
                          size: 11.5,
                        ).copyWith(color: p.textMuted),
                      ),
                  ],
                ),
              ),
              if (trailing.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  trailing,
                  textAlign: TextAlign.right,
                  style: AppText.body(size: 12).copyWith(
                    color: tone ?? p.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          if (technical.isNotEmpty) _technical(context, technical),
        ],
      ),
    );
    if (!announce) return row;
    return Semantics(
      label: '$title. $subtitle ${trailing.isEmpty ? '' : trailing}',
      child: row,
    );
  }

  Widget _technical(BuildContext context, Map<String, dynamic> tech) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            'Technical details',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                _dump(tech),
                style: AppText.body(size: 11).copyWith(color: p.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dump(Map<String, dynamic> m, [int depth = 0]) {
    final pad = '  ' * depth;
    final b = StringBuffer();
    final keys = m.keys.toList()..sort();
    for (final k in keys) {
      final v = m[k];
      if (v is Map) {
        b.writeln('$pad$k:');
        b.write(_dump(v.map((a, c) => MapEntry(a.toString(), c)), depth + 1));
      } else if (v is List) {
        b.writeln(
          '$pad$k: [${v.length} item${v.length == 1 ? '' : 's'}] ${v.length <= 6 ? v : ''}',
        );
      } else {
        b.writeln('$pad$k: ${_scalar(v)}');
      }
    }
    return b.toString();
  }

  static String _scalar(dynamic v) {
    final d = memberDate(v);
    if (d != null && v is! num) {
      return '${d.toIso8601String()} (${OrganizationLanguage.exactTime(d)})';
    }
    return v.toString();
  }

  static String _when(DateTime? t, DateTime now) => t == null
      ? 'date not recorded'
      : '${OrganizationLanguage.exact(t)} · ${OrganizationLanguage.relative(t, now: now)}';

  // ── OVERVIEW ──────────────────────────────────────────────────────────────

  Widget _overview(BuildContext context, ClientModel m, DateTime now) {
    final p = context.palette;
    final issues = _issues(m, now);
    final flagged = issues.where((i) => i.needsAttention).toList();
    final info = issues.where((i) => !i.needsAttention).toList();
    final unread = detail.unreadSections;
    final org = ctrl.orgOf(m);
    final trainer = ctrl.trainerOf(m);
    final state = MemberLanguage.membershipState(m, now: now);
    final checking =
        detail.payments.loading.value && !detail.payments.done.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConsoleCard(
          title: 'HEALTH',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (flagged.isEmpty && checking)
                _muted(context, 'Checking related records…')
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
              if (!MemberLanguage.isOwnerCoached(m) &&
                  (!ctrl.trainersKnown || ctrl.trainersError != null))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ctrl.trainersError != null
                        ? 'Not checked: the trainer list could not be loaded, so coach-related issues would not show here.'
                        : 'The trainer list is still loading; coach-related checks follow.',
                    style: AppText.body(size: 12).copyWith(
                      color: ctrl.trainersError != null ? p.error : p.textMuted,
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
          title: 'AT A GLANCE',
          child: Obx(() {
            final pays = detail.payments;
            final paid = pays.done.value
                ? pays.data.value!.fold<double>(
                    0,
                    (a, r) => a + (r.amount ?? 0),
                  )
                : null;
            final sessions = detail.workoutSessions;
            final checkins = detail.checkIns;
            String count(Section<List<DatedDoc>> s) => s.done.value
                ? '${s.data.value!.length}'
                : (s.error.value != null ? '—' : '…');
            return Wrap(
              spacing: 28,
              runSpacing: 16,
              children: [
                ConsoleStat(
                  label: 'Membership',
                  value: state.label,
                  hint: state.meaning,
                ),
                ConsoleStat(
                  label: 'Plan',
                  value: MemberLanguage.planName(m),
                  hint: MemberLanguage.sourceLine(m),
                ),
                ConsoleStat(
                  label: state == MembershipState.expired ? 'Ended' : 'Ends',
                  value: m.membershipExpiry == null
                      ? '—'
                      : OrganizationLanguage.exact(m.membershipExpiry),
                  hint: MemberLanguage.termLine(m, now: now),
                ),
                ConsoleStat(
                  label: 'Total paid (receipts)',
                  value: paid == null
                      ? (pays.error.value != null ? '—' : '…')
                      : OrganizationLanguage.rupees(paid),
                  hint: 'Sum of this member\'s receipts in this organization',
                ),
                ConsoleStat(
                  label: 'Setup',
                  value: MemberLanguage.activationLabel(m.activationStage),
                ),
                ConsoleStat(
                  label: 'Adherence',
                  value: MemberLanguage.adherenceLine(m),
                  hint: 'Computed daily by the backend from the member\'s logs',
                ),
                ConsoleStat(
                  label: 'Workouts logged',
                  value: count(sessions),
                  hint: 'Most recent $kMemberSessionRowsLimit at most',
                ),
                ConsoleStat(label: 'Check-ins', value: count(checkins)),
                ConsoleStat(
                  label: 'Activity',
                  value: MemberLanguage.activityState(m, now: now).label,
                  hint: MemberLanguage.activityLine(m, now: now),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'ORGANIZATION & COACH',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Belongs to', ctrl.orgName(m)),
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
              ],
              _kv(context, 'Coach', ctrl.coachLine(m)),
              if (trainer != null) ...[
                _kv(
                  context,
                  'Coach standing',
                  TrainerLanguage.standingOf(trainer).label,
                ),
                _kv(
                  context,
                  'Coach app access',
                  TrainerLanguage.accessLabel(trainer),
                ),
              ],
              _kv(
                context,
                'Coaching pause',
                MemberLanguage.pauseLine(m, now: now),
              ),
              _kv(
                context,
                'Check-in cadence',
                MemberLanguage.checkInLine(m, now: now),
              ),
              const SizedBox(height: 8),
              Text(
                'The platform does not manage members directly: memberships, coach '
                'assignment, plans and check-ins are the organization\'s, in the '
                'Trainersarena app; the profile is the member\'s, in theirs. What the '
                'platform can do is act on the organization and on the member\'s '
                'payments (Settlements).',
                style: AppText.body(
                  size: 12.5,
                ).copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── MEMBERSHIP & PAYMENTS ─────────────────────────────────────────────────

  Widget _membership(BuildContext context, ClientModel m, DateTime now) {
    final p = context.palette;
    final state = MemberLanguage.membershipState(m, now: now);
    final flag = MemberLanguage.flagDisagreement(m, now: now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConsoleCard(
          title: 'CURRENT TERM',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'State', '${state.label} — ${state.meaning}'),
              _kv(context, 'Plan', MemberLanguage.planName(m)),
              if (MemberLanguage.planId(m) != null)
                _kv(context, 'Plan id', MemberLanguage.planId(m)!, copy: true),
              _kv(
                context,
                'Amount recorded',
                MemberLanguage.amountPaid(m) == null
                    ? 'Not recorded'
                    : OrganizationLanguage.rupees(
                        MemberLanguage.amountPaid(m)!,
                      ),
              ),
              _kv(context, 'How it was sold', MemberLanguage.sourceLine(m)),
              _kv(context, 'Term', MemberLanguage.termLine(m, now: now)),
              _kv(context, 'Duration', _duration(m.membership)),
              _kv(
                context,
                'Frozen',
                m.membershipFrozen
                    ? 'Yes${m.membershipFrozenAt == null ? '' : ', since ${OrganizationLanguage.exactTime(m.membershipFrozenAt)}'}'
                    : 'No',
              ),
              _kv(
                context,
                'Active flag (stored)',
                m.membershipActive ? 'true' : 'false',
              ),
              if (flag != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    flag == 'flag_active_after_expiry'
                        ? 'The stored flag says active but the term has ended — see Health.'
                        : 'The stored flag says inactive but the term is still running — see Health.',
                    style: AppText.body(
                      size: 12.5,
                    ).copyWith(color: context.serena.statusWarning),
                  ),
                ),
              if ((m.membership?['razorpayPaymentId'] ?? '')
                  .toString()
                  .isNotEmpty)
                _kv(
                  context,
                  'Razorpay payment',
                  m.membership!['razorpayPaymentId'].toString(),
                  copy: true,
                ),
              if ((m.membership?['razorpayOrderId'] ?? '')
                  .toString()
                  .isNotEmpty)
                _kv(
                  context,
                  'Razorpay order',
                  m.membership!['razorpayOrderId'].toString(),
                  copy: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section<List<MemberPaymentModel>>(
          context,
          s: detail.payments,
          title: 'PAYMENT RECEIPTS',
          retry: detail.loadPayments,
          body: (list) {
            if (list.isEmpty) {
              return _muted(
                context,
                'No receipts. A membership recorded before receipts existed, or extended manually, leaves none.',
              );
            }
            final total = list.fold<double>(0, (a, r) => a + (r.amount ?? 0));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${OrganizationLanguage.plural(list.length, 'receipt')} · ${OrganizationLanguage.rupees(total)} in total'
                  '${list.length >= kMemberPaymentRowsLimit ? ' · showing the most recent $kMemberPaymentRowsLimit' : ''}',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
                const SizedBox(height: 6),
                for (final r in list) _paymentRow(context, r, now),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _section<List<SettlementModel>>(
          context,
          s: detail.settlements,
          title: 'SETTLEMENTS (MONEY OWED TO THE ORGANIZATION)',
          retry: detail.loadSettlements,
          trailing: TextButton(
            onPressed: () => _openSettlements(m),
            child: const Text('Open in Settlements'),
          ),
          body: (list) {
            if (list.isEmpty) {
              return _muted(
                context,
                'No settlement exists for this member\'s payments. Offline and coupon memberships move no money through the platform.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in list)
                  _listRow(
                    context,
                    icon: Icons.account_balance_outlined,
                    title:
                        '${formatMinor(s.grossMinor)} gross · ${formatMinor(s.netMinor)} net to the organization',
                    subtitle:
                        '${s.planName.isEmpty ? 'Plan not recorded' : s.planName} · ${_when(s.createdAt, now)}',
                    trailing: s.status.label,
                    tone: switch (s.status) {
                      SettlementStatus.settled => context.serena.statusActive,
                      SettlementStatus.failed ||
                      SettlementStatus.chargeback ||
                      SettlementStatus.refunded => context.serena.error,
                      SettlementStatus.onHold || SettlementStatus.underReview =>
                        context.serena.statusWarning,
                      _ => p.textSecondary,
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _duration(Map<String, dynamic>? t) {
    if (t == null) return 'Not recorded';
    final v = t['durationValue'];
    final u = (t['durationUnit'] ?? '').toString();
    if (v != null && u.isNotEmpty) return '$v $u${v == 1 ? '' : 's'}';
    final months = t['months'];
    if (months != null) return '$months month${months == 1 ? '' : 's'}';
    return 'Not recorded';
  }

  Widget _paymentRow(BuildContext context, MemberPaymentModel r, DateTime now) {
    final amount = r.amount == null
        ? 'amount not recorded'
        : OrganizationLanguage.rupees(r.amount!);
    final source = MemberLanguage.sourceOf(
      source: r.source.isEmpty ? null : r.source,
      method: r.method.isEmpty ? null : r.method,
      coupon: r.couponCode.isEmpty ? null : r.couponCode,
      online: r.isOnline,
    );
    return _listRow(
      context,
      icon: r.captureUnverified
          ? Icons.warning_amber_outlined
          : Icons.receipt_long_outlined,
      tone: r.captureUnverified ? context.serena.statusWarning : null,
      title:
          '$amount · ${r.planName.isEmpty ? 'Plan not recorded' : r.planName}',
      subtitle:
          '$source · ${_when(r.createdAt, now)}'
          '${r.expiry == null ? '' : ' · term to ${OrganizationLanguage.exact(r.expiry)}'}'
          '${r.captureUnverified ? ' · capture NOT confirmed by the gateway${r.captureNote.isEmpty ? '' : ' (${r.captureNote})'}' : ''}',
      trailing: r.settlementStatus.isEmpty
          ? ''
          : 'settlement ${r.settlementStatus.replaceAll('_', ' ')}',
      technical: {'receiptId': r.id, ...r.raw},
    );
  }

  // ── COACHING & ACTIVITY ───────────────────────────────────────────────────

  Widget _activity(BuildContext context, ClientModel m, DateTime now) {
    final p = context.palette;
    String s(dynamic v) => (v ?? '').toString().trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConsoleCard(
          title: 'COACHING STATE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(
                context,
                'Setup stage',
                MemberLanguage.activationLabel(m.activationStage) +
                    (m.activationStageAt == null
                        ? ''
                        : ' (since ${OrganizationLanguage.exact(m.activationStageAt)})'),
              ),
              _kv(context, 'Adherence', MemberLanguage.adherenceLine(m)),
              _kv(
                context,
                'Last app activity',
                MemberLanguage.activityLine(m, now: now),
              ),
              _kv(
                context,
                'Check-ins',
                MemberLanguage.checkInLine(m, now: now),
              ),
              _kv(
                context,
                'Coaching pause',
                MemberLanguage.pauseLine(m, now: now),
              ),
              _kv(
                context,
                'Nutrition targets',
                _targets(m.nutritionTargets ?? m.dietTargets),
              ),
              _kv(context, 'Lifestyle targets', _lifestyle(m.lifestyleTargets)),
              _kv(
                context,
                'Supplements',
                m.supplementPlan.isEmpty
                    ? 'None recorded'
                    : m.supplementPlan
                          .map((e) => e is Map ? s(e['name']) : s(e))
                          .where((e) => e.isNotEmpty)
                          .join(', '),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section<List<DatedDoc>>(
          context,
          s: detail.assignments,
          title: 'PLAN ASSIGNMENTS',
          retry: detail.loadAssignments,
          body: (list) => list.isEmpty
              ? _muted(
                  context,
                  'No workout or diet plan has been assigned to this member.',
                )
              : Column(
                  children: [
                    for (final d in list)
                      _listRow(
                        context,
                        icon: s(d.data['planType']) == 'diet'
                            ? Icons.restaurant_menu_outlined
                            : Icons.fitness_center_outlined,
                        title:
                            '${s(d.data['planName']).isEmpty ? 'Plan' : s(d.data['planName'])} (${s(d.data['planType']).isEmpty ? 'plan' : s(d.data['planType'])})',
                        subtitle:
                            'Assigned${s(d.data['assignedByName']).isEmpty ? '' : ' by ${s(d.data['assignedByName'])}'} · ${_when(d.at, now)}',
                        trailing: s(d.data['status']),
                        tone: s(d.data['status']) == 'active'
                            ? context.serena.statusActive
                            : null,
                        technical: d.data,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _section<List<DatedDoc>>(
          context,
          s: detail.workoutSessions,
          title: 'WORKOUT SESSIONS (MEMBER-LOGGED)',
          retry: detail.loadWorkoutSessions,
          body: (list) => list.isEmpty
              ? _muted(
                  context,
                  'No workout sessions logged from the member app.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (list.length >= kMemberSessionRowsLimit)
                      _muted(
                        context,
                        'Showing the most recent $kMemberSessionRowsLimit sessions.',
                      ),
                    for (final d in list.take(30))
                      _listRow(
                        context,
                        icon: Icons.directions_run_outlined,
                        title: s(d.data['planName']).isEmpty
                            ? 'Workout'
                            : s(d.data['planName']),
                        subtitle:
                            '${_when(d.at, now)}'
                            '${d.data['durationSeconds'] is num ? ' · ${((d.data['durationSeconds'] as num) / 60).round()} min' : ''}'
                            '${d.data['entries'] is List ? ' · ${(d.data['entries'] as List).length} exercises' : ''}'
                            '${s(d.data['memberNote']).isEmpty ? '' : ' · "${s(d.data['memberNote'])}"'}',
                        trailing: s(d.data['status']),
                        technical: d.data,
                      ),
                    if (list.length > 30)
                      _muted(
                        context,
                        '${list.length - 30} older sessions not listed.',
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < 900;
            final food = _section<List<DatedDoc>>(
              context,
              s: detail.nutritionDays,
              title: 'FOOD LOG (DAYS)',
              retry: detail.loadNutritionDays,
              body: (list) => list.isEmpty
                  ? _muted(context, 'No food logged from the member app.')
                  : Column(
                      children: [
                        for (final d in list.take(14))
                          _listRow(
                            context,
                            icon: Icons.restaurant_outlined,
                            title: d.at == null
                                ? d.id
                                : OrganizationLanguage.exact(d.at),
                            subtitle: _nutritionSummary(d.data),
                            trailing: d.data['coachReview'] is Map
                                ? 'reviewed'
                                : '',
                            technical: d.data,
                          ),
                        if (list.length > 14)
                          _muted(
                            context,
                            '${list.length - 14} older days not listed.',
                          ),
                      ],
                    ),
            );
            final life = _section<List<DatedDoc>>(
              context,
              s: detail.lifestyleDays,
              title: 'LIFESTYLE LOG (DAYS)',
              retry: detail.loadLifestyleDays,
              body: (list) => list.isEmpty
                  ? _muted(
                      context,
                      'No water, sleep or steps logged from the member app.',
                    )
                  : Column(
                      children: [
                        for (final d in list.take(14))
                          _listRow(
                            context,
                            icon: Icons.water_drop_outlined,
                            title: d.at == null
                                ? d.id
                                : OrganizationLanguage.exact(d.at),
                            subtitle: _lifestyleSummary(d.data),
                            technical: d.data,
                          ),
                        if (list.length > 14)
                          _muted(
                            context,
                            '${list.length - 14} older days not listed.',
                          ),
                      ],
                    ),
            );
            return narrow
                ? Column(children: [food, const SizedBox(height: 12), life])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: food),
                      const SizedBox(width: 12),
                      Expanded(child: life),
                    ],
                  );
          },
        ),
        const SizedBox(height: 12),
        _section<List<DatedDoc>>(
          context,
          s: detail.progress,
          title: 'PROGRESS LOG (ENTRIES THE MEMBER SHARED)',
          retry: detail.loadProgress,
          body: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _muted(
                context,
                'Only entries the member marked as shared are readable by the platform; private entries are never counted here.',
              ),
              if (list.isEmpty) _muted(context, 'No shared progress entries.'),
              for (final d in list)
                _listRow(
                  context,
                  icon: Icons.monitor_weight_outlined,
                  title: _progressTitle(d.data),
                  subtitle:
                      '${_when(d.at, now)}${s(d.data['note']).isEmpty ? '' : ' · "${s(d.data['note'])}"'}',
                  trailing: s(d.data['status']),
                  technical: d.data,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section<List<DatedDoc>>(
          context,
          s: detail.checkIns,
          title: 'CHECK-IN SUBMISSIONS',
          retry: detail.loadCheckIns,
          body: (list) => list.isEmpty
              ? _muted(context, 'The member has not submitted a check-in.')
              : Column(
                  children: [
                    for (final d in list)
                      _listRow(
                        context,
                        icon: Icons.fact_check_outlined,
                        title:
                            'Check-in ${s(d.data['status']).isEmpty ? '' : '· ${s(d.data['status'])}'}',
                        subtitle:
                            '${_when(d.at, now)}'
                            '${s(d.data['reviewedByName']).isEmpty ? '' : ' · reviewed by ${s(d.data['reviewedByName'])}'}'
                            '${s(d.data['coachResponse']).isEmpty ? '' : ' · coach: "${s(d.data['coachResponse'])}"'}',
                        technical: d.data,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _section<List<DatedDoc>>(
          context,
          s: detail.coachNotes,
          title: 'COACH NOTES',
          retry: detail.loadCoachNotes,
          body: (list) => list.isEmpty
              ? _muted(context, 'No coach notes recorded.')
              : Column(
                  children: [
                    for (final d in list)
                      _listRow(
                        context,
                        icon: Icons.sticky_note_2_outlined,
                        title: s(d.data['note']).isEmpty
                            ? 'Note'
                            : s(d.data['note']),
                        subtitle:
                            '${s(d.data['authorName']).isEmpty ? '' : 'by ${s(d.data['authorName'])} · '}${_when(d.at, now)}',
                        technical: d.data,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _section<List<DatedDoc>>(
          context,
          s: detail.weeklyReports,
          title: 'WEEKLY REPORTS',
          retry: detail.loadWeeklyReports,
          body: (list) => list.isEmpty
              ? _muted(context, 'No weekly report submissions.')
              : Column(
                  children: [
                    for (final d in list)
                      _listRow(
                        context,
                        icon: Icons.summarize_outlined,
                        title:
                            'Week ${s(d.data['periodKey']).isEmpty ? d.id : s(d.data['periodKey'])}',
                        subtitle: _when(d.at, now),
                        trailing: s(d.data['status']),
                        technical: d.data,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < 900;
            final onboarding = _section<Map<String, dynamic>?>(
              context,
              s: detail.onboarding,
              title: 'ONBOARDING',
              retry: detail.loadOnboarding,
              body: (d) => d == null
                  ? _muted(
                      context,
                      'The member has not completed onboarding in their app.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv(
                          context,
                          'Submitted',
                          _when(memberDate(d['submittedAt']), now),
                        ),
                        _kv(
                          context,
                          'Answers',
                          d['answers'] is List
                              ? '${(d['answers'] as List).length}'
                              : 'Not recorded',
                        ),
                        _technical(context, d),
                      ],
                    ),
            );
            final chat = _section<Map<String, dynamic>?>(
              context,
              s: detail.chat,
              title: 'CHAT THREAD',
              retry: detail.loadChat,
              body: (d) => d == null
                  ? _muted(
                      context,
                      'No chat thread exists between this member and their coach.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv(
                          context,
                          'Last message',
                          _lastMessage(d['lastMessage']),
                        ),
                        _kv(
                          context,
                          'Updated',
                          _when(
                            memberDate(d['updatedAt']) ??
                                memberDate(d['lastMessageAt']),
                            now,
                          ),
                        ),
                        if (d['unread'] is Map)
                          _kv(
                            context,
                            'Unread',
                            'member ${(d['unread'] as Map)['member'] ?? 0} · staff ${(d['unread'] as Map)['staff'] ?? 0}',
                          ),
                        Text(
                          'Message bodies are between the member and their coach; the console shows only the thread summary.',
                          style: AppText.body(
                            size: 12,
                          ).copyWith(color: p.textMuted),
                        ),
                      ],
                    ),
            );
            return narrow
                ? Column(
                    children: [onboarding, const SizedBox(height: 12), chat],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: onboarding),
                      const SizedBox(width: 12),
                      Expanded(child: chat),
                    ],
                  );
          },
        ),
      ],
    );
  }

  static String _progressTitle(Map<String, dynamic> d) {
    final t = [
      if (d['weightKg'] != null) '${d['weightKg']} kg',
      if (d['bodyFatPercent'] != null) '${d['bodyFatPercent']}% body fat',
      if (d['photos'] is List) '${(d['photos'] as List).length} photo(s)',
    ].join(' · ');
    return t.isEmpty ? 'Progress entry' : t;
  }

  /// `chats.lastMessage` is a map {senderName, text, type, at} on current
  /// threads and a plain string on legacy ones.
  static String _lastMessage(dynamic v) {
    if (v == null) return 'None';
    if (v is Map) {
      final text = (v['text'] ?? '').toString().trim();
      final who = (v['senderName'] ?? '').toString().trim();
      final type = (v['type'] ?? '').toString().trim();
      final body = text.isNotEmpty
          ? '"$text"'
          : (type.isEmpty ? 'a message' : 'a $type message');
      return who.isEmpty ? body : '$who: $body';
    }
    final t = v.toString().trim();
    return t.isEmpty ? 'None' : '"$t"';
  }

  static String _targets(Map<String, dynamic>? t) {
    if (t == null || t.isEmpty) return 'Not set';
    final parts = <String>[
      if (t['calories'] != null) '${t['calories']} kcal',
      if (t['protein'] != null) 'P ${t['protein']} g',
      if (t['carbs'] != null) 'C ${t['carbs']} g',
      if (t['fat'] != null) 'F ${t['fat']} g',
      if (t['fiber'] != null) 'fibre ${t['fiber']} g',
      if (t['waterMl'] != null) 'water ${t['waterMl']} ml',
    ];
    final by = (t['setByName'] ?? '').toString();
    return '${parts.isEmpty ? 'Set' : parts.join(' · ')}${by.isEmpty ? '' : ' · set by $by'}';
  }

  static String _lifestyle(Map<String, dynamic>? t) {
    if (t == null || t.isEmpty) return 'Not set';
    return [
      if (t['waterTargetMl'] != null) 'water ${t['waterTargetMl']} ml',
      if (t['stepsTarget'] != null) '${t['stepsTarget']} steps',
      if (t['sleepHoursTarget'] != null) 'sleep ${t['sleepHoursTarget']} h',
    ].join(' · ');
  }

  static String _nutritionSummary(Map<String, dynamic> d) {
    final c = d['computed'];
    if (c is Map) {
      final parts = <String>[
        if (c['calories'] != null) '${(c['calories'] as num).round()} kcal',
        if (c['protein'] != null) 'P ${(c['protein'] as num).round()} g',
        if (c['carbs'] != null) 'C ${(c['carbs'] as num).round()} g',
        if (c['fat'] != null) 'F ${(c['fat'] as num).round()} g',
      ];
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    final e = d['entries'];
    if (e is Map) {
      final live = e.values
          .where((v) => v is Map && v['deleted'] != true)
          .length;
      return '$live food entr${live == 1 ? 'y' : 'ies'}';
    }
    return 'Logged';
  }

  static String _lifestyleSummary(Map<String, dynamic> d) {
    final c = d['computed'];
    if (c is Map) {
      final parts = <String>[
        if (c['waterMl'] != null) 'water ${c['waterMl']} ml',
        if (c['steps'] != null) '${c['steps']} steps',
        if (c['sleepHours'] != null) 'sleep ${c['sleepHours']} h',
      ];
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    final e = d['events'];
    if (e is Map) return '${e.length} event${e.length == 1 ? '' : 's'}';
    return 'Logged';
  }

  // ── FEEDBACK & HISTORY ────────────────────────────────────────────────────

  Widget _voice(BuildContext context, ClientModel m, DateTime now) {
    final p = context.palette;
    String s(dynamic v) => (v ?? '').toString().trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          context,
          s: detail.orgReviews,
          title: 'RATING OF THE ORGANIZATION',
          retry: detail.loadOrgReviews,
          body: (list) => list.isEmpty
              ? _muted(context, 'The member has not rated the organization.')
              : Column(
                  children: [
                    for (final r in list)
                      _listRow(
                        context,
                        icon: Icons.star_outline,
                        tone: r.isCritical
                            ? context.serena.error
                            : (r.isPositive
                                  ? context.serena.statusActive
                                  : null),
                        title:
                            '${r.rating} / 5${r.hasComment ? ' — "${r.comment}"' : ''}',
                        subtitle: _when(r.lastActivity, now),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _section<List<DatedDoc>>(
          context,
          s: detail.coachReviews,
          title: 'RATING OF THE COACH',
          retry: detail.loadCoachReviews,
          body: (list) => list.isEmpty
              ? _muted(context, 'The member has not rated a coach.')
              : Column(
                  children: [
                    for (final d in list)
                      _listRow(
                        context,
                        icon: Icons.star_outline,
                        title:
                            '${s(d.data['rating'])} / 5${s(d.data['comment']).isEmpty ? '' : ' — "${s(d.data['comment'])}"'}',
                        subtitle:
                            'coach ${ctrl.coachName(s(d.data['coachId']))} · ${_when(d.at, now)}',
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _section<List<DatedDoc>>(
          context,
          s: detail.feedback,
          title: 'FEEDBACK SENT TO THE ORGANIZATION',
          retry: detail.loadFeedback,
          body: (list) => list.isEmpty
              ? _muted(context, 'No feedback from this member.')
              : Column(
                  children: [
                    for (final d in list)
                      _listRow(
                        context,
                        icon: d.data['requestTrainerChange'] == true
                            ? Icons.swap_horiz
                            : Icons.forum_outlined,
                        tone: s(d.data['status']) == 'open'
                            ? context.serena.statusWarning
                            : null,
                        title:
                            '${s(d.data['category']).isEmpty ? 'Feedback' : s(d.data['category'])}'
                            '${s(d.data['message']).isEmpty ? '' : ' — "${s(d.data['message'])}"'}',
                        subtitle:
                            '${_when(d.at, now)}'
                            '${d.data['rating'] != null ? ' · rated ${d.data['rating']}/5' : ''}'
                            '${d.data['anonymous'] == true ? ' · sent anonymously' : ''}'
                            '${d.data['requestTrainerChange'] == true ? ' · asked for a different coach' : ''}',
                        trailing: s(d.data['status']),
                        technical: d.data,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'HISTORY',
          child: Obx(() {
            final a = detail.audit;
            final pays = detail.payments;
            if ((a.loading.value && !a.done.value) ||
                (pays.loading.value && !pays.done.value)) {
              return const ConsoleSkeletonRow();
            }
            final errs = <String>[
              if (a.error.value != null)
                'platform actions (${a.error.value!.message})',
              if (pays.error.value != null)
                'receipts (${pays.error.value!.message})',
            ];
            final events = MemberLanguage.timeline([
              for (final l in a.data.value ?? const [])
                if (MemberLanguage.fromAudit(
                      l,
                      actorOf: (u) => _actor(u, m),
                      coachNameOf: ctrl.coachName,
                    )
                    case final e?)
                  e,
              for (final r in pays.data.value ?? const <MemberPaymentModel>[])
                MemberLanguage.fromPayment(r),
              if (m.createdAtKnown)
                MemberEvent(
                  at: m.createdAt,
                  title: 'Member record created',
                  detail: MemberLanguage.sourceLine(m),
                ),
              if (m.authUnlinkedAt != null)
                MemberEvent(
                  at: m.authUnlinkedAt,
                  title: 'Member deleted their account',
                  actor: 'the member',
                ),
              if (m.membershipFrozen && m.membershipFrozenAt != null)
                MemberEvent(
                  at: m.membershipFrozenAt,
                  title: 'Membership frozen',
                  actor: 'the organization owner',
                ),
            ]);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: p.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Incomplete: ${errs.join('; ')} could not be loaded.',
                            style: AppText.body(
                              size: 12.5,
                            ).copyWith(color: p.error),
                          ),
                        ),
                        TextButton(
                          onPressed: detail.loadAll,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                if ((a.data.value?.length ?? 0) >= kMemberAuditRowsLimit)
                  _muted(
                    context,
                    'Showing the most recent $kMemberAuditRowsLimit platform actions; older ones are in the Audit Log.',
                  ),
                if (events.isEmpty)
                  _muted(context, 'No recorded events for this member yet.')
                else
                  for (final e in events) _eventRow(context, e, now),
                const SizedBox(height: 8),
                Text(
                  'Coach changes appear here from the audit trail. The coach app\'s own assignment '
                  'event log is not readable by the platform.',
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  Widget _eventRow(BuildContext context, MemberEvent e, DateTime now) {
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
                  if (e.technical.isNotEmpty) _technical(context, e.technical),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PROFILE & TECHNICAL ───────────────────────────────────────────────────

  Widget _profile(BuildContext context, ClientModel m, DateTime now) {
    final p = context.palette;
    String orDash(String? s) =>
        (s ?? '').trim().isEmpty ? 'Not recorded' : s!.trim();
    String num(double? v, String unit) => v == null
        ? 'Not recorded'
        : '${v == v.roundToDouble() ? v.round() : v.toStringAsFixed(1)} $unit';
    final shared = m.sharedProfile ?? const <String, dynamic>{};
    Map<String, dynamic> sec(String k) => shared[k] is Map
        ? (shared[k] as Map).map((a, b) => MapEntry(a.toString(), b))
        : const {};
    final location = sec('location');
    final emergency = sec('emergencyContact');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConsoleCard(
          title: 'PROFILE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Name', MemberLanguage.displayName(m)),
              _kv(context, 'Email', MemberLanguage.email(m), copy: true),
              _kv(context, 'Phone', MemberLanguage.phone(m), copy: true),
              _kv(context, 'Gender', orDash(MemberLanguage.genderOf(m))),
              _kv(
                context,
                'Age',
                MemberLanguage.ageOf(m, now: now) == null
                    ? 'Not recorded'
                    : '${MemberLanguage.ageOf(m, now: now)}'
                          '${MemberLanguage.dateOfBirth(m) == null ? ' (typed once, may be stale)' : ' (born ${OrganizationLanguage.exact(MemberLanguage.dateOfBirth(m))})'}',
              ),
              _kv(context, 'Height', num(MemberLanguage.heightCm(m), 'cm')),
              _kv(context, 'Weight', num(MemberLanguage.weightKg(m), 'kg')),
              _kv(
                context,
                'Goal weight',
                num(MemberLanguage.goalWeightKg(m), 'kg'),
              ),
              _kv(context, 'Goal', orDash(MemberLanguage.goalOf(m))),
              if (location.isNotEmpty)
                _kv(
                  context,
                  'Location',
                  [
                        location['address'],
                        location['city'],
                        location['state'],
                        location['country'],
                      ]
                      .where((e) => (e ?? '').toString().trim().isNotEmpty)
                      .join(', '),
                ),
              if (emergency.isNotEmpty)
                _kv(
                  context,
                  'Emergency contact',
                  orDash(emergency['phone']?.toString()),
                  copy: true,
                ),
              _kv(
                context,
                'Photo',
                MemberLanguage.photoUrl(m) == null ? 'None' : 'On file',
              ),
              const SizedBox(height: 6),
              Text(
                MemberLanguage.hasSharedProfile(m)
                    ? 'Profile fields come from the member\'s own app (projected ${m.sharedProfileAt == null ? 'at an unrecorded time' : OrganizationLanguage.exactTime(m.sharedProfileAt)}), '
                          'falling back per field to the coach record. Only sections the member chose to share with their organization are projected.'
                    : 'The member has not shared a profile from their app; these fields are the coach record\'s.',
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _section<List<ClientModel>>(
          context,
          s: detail.siblings,
          title: 'OTHER MEMBERSHIPS OF THE SAME PERSON',
          retry: () => detail.loadSiblings(m),
          body: (list) => list.isEmpty
              ? _muted(
                  context,
                  m.authUid.isEmpty
                      ? 'Cannot be determined: this record is not linked to an app account.'
                      : 'This person holds no other membership record on the platform.',
                )
              : Column(
                  children: [
                    for (final o in list)
                      MergeSemantics(
                        child: Semantics(
                          button: true,
                          label: 'Open membership in ${ctrl.orgName(o)}',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => ctrl.openMember(o.docId),
                              child: _listRow(
                                context,
                                icon: Icons.corporate_fare_outlined,
                                title: ctrl.orgName(o),
                                subtitle:
                                    '${MemberLanguage.membershipLine(o, now: now)} · ${ctrl.coachLine(o)}',
                                trailing: 'open',
                                tone: p.accent,
                                announce: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        ConsoleCard(
          title: 'TECHNICAL DETAILS',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv(context, 'Member record id', m.docId, copy: true),
              _kv(
                context,
                'Auth uid',
                m.authUid.isEmpty ? 'none' : m.authUid,
                copy: true,
              ),
              _kv(context, 'Organization id', orDash(m.adminId), copy: true),
              _kv(
                context,
                'Trainer id',
                (m.trainerId ?? '').isEmpty
                    ? 'none (owner-coached)'
                    : m.trainerId!,
                copy: true,
              ),
              _kv(context, 'Raw status', m.status),
              _kv(context, 'membershipActive', '${m.membershipActive}'),
              _kv(
                context,
                'membershipExpiry',
                m.membershipExpiry?.toIso8601String() ?? 'null',
              ),
              _kv(context, 'membershipFrozen', '${m.membershipFrozen}'),
              _kv(context, 'activationStage', orDash(m.activationStage)),
              _kv(context, 'scheduleStatus', orDash(m.scheduleStatus)),
              _kv(context, 'authUnlinkReason', orDash(m.authUnlinkReason)),
              _kv(
                context,
                'Record created',
                m.createdAtKnown
                    ? OrganizationLanguage.exactTime(m.createdAt)
                    : 'not recorded',
              ),
              _kv(
                context,
                'Record updated',
                OrganizationLanguage.exactTime(m.updatedAt),
              ),
              _kv(
                context,
                'lastActivityAt',
                m.lastActivityAt?.toIso8601String() ?? 'null',
              ),
              _kv(
                context,
                'Reminder stamps',
                (m.notif ?? const {}).keys.isEmpty
                    ? 'none'
                    : (m.notif ?? const {}).keys.join(', '),
              ),
              const SizedBox(height: 8),
              Text(
                'Full document',
                style: AppText.body(size: 11).copyWith(
                  color: p.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.surfaceAlt,
                  borderRadius: AppRadii.smR,
                  border: Border.all(color: p.border),
                ),
                child: SelectableText(
                  _dump(m.raw),
                  style: AppText.body(
                    size: 11,
                  ).copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
