// ============================================================================
// THE SETTLEMENT WORKSPACE — the founder's surface for money the platform is
// holding on organizations' behalf.
//
// This screen has one job the dashboard does not: it answers "what must I do
// with other people's money right now". So it opens on the OUTSTANDING queue
// rather than on totals, every row is actionable, and the platform's float is
// shown as a single number that comes from the server rather than from a
// paginated client sum.
//
// NOTHING HERE WRITES FIRESTORE. Every action calls a super-admin Cloud
// Function through the controller; the rules deny client writes to
// `settlements` and the ledger outright.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import 'package:firebase_storage/firebase_storage.dart';

import '../controllers/settlement_controller.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_radii.dart';
import '../core/theme/app_text.dart';
import '../core/widgets/console/console_chrome.dart';
import '../models/settlement_model.dart';
import '../widgets/page_shell.dart';
import '../widgets/settlement/transfer_dialog.dart';

class SettlementScreen extends StatelessWidget {
  const SettlementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();

    return PageShell(
      title: 'Settlements',
      icon: Icons.account_balance_outlined,
      trailing: Obx(
        () => IconButton(
          tooltip: 'Refresh totals',
          onPressed: c.summaryLoading.value ? null : c.refreshSummary,
          icon: c.summaryLoading.value
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ),
      child: Obx(() {
        final err = c.error.value;
        if (err != null) {
          return ConsoleErrorState(error: err, onRetry: c.retryLoad);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FloatStrip(),
            const SizedBox(height: 18),
            const _ViewChips(),
            const SizedBox(height: 12),
            const _FilterBar(),
            const SizedBox(height: 14),
            if (c.loading.value)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              const _SettlementList(),
            const SizedBox(height: 24),
          ],
        );
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// THE FLOAT STRIP
// ═════════════════════════════════════════════════════════════════════════════

/// The platform's headline money position.
///
/// "Outstanding" is the FLOAT — customer money TrainersArena is currently
/// holding. It is rendered first, largest, and sourced from the server, because
/// it is the number a regulator, an accountant or an acquirer asks for before
/// any other. Page-level sums are shown separately and labelled as such, so a
/// filtered view can never be misread as the total liability.
class _FloatStrip extends StatelessWidget {
  const _FloatStrip();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;

    return Obx(() {
      final s = c.summary.value;
      // PLATFORM-WIDE, never page-scoped — see the counters in the controller.
      // A filtered view must not be able to report "nothing blocked".
      // Both are NULLABLE on purpose: a census that could not be read has no
      // number, and printing 0 for it is how this strip previously announced
      // "Nothing blocked" over blocked payouts.
      final overdue = c.overdueAvailable.value ? c.overdueTotal.value : null;
      final attention = c.needsAttentionCount;

      return LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth > 900;
          final tiles = <Widget>[
            _FloatTile(
              label: 'Held for organizations',
              value: s == null
                  ? '—'
                  : formatMinorCompact(s.outstandingMinor),
              sub: s == null
                  ? 'Loading…'
                  : '${s.outstandingCount} settlement'
                      '${s.outstandingCount == 1 ? '' : 's'}'
                      '${s.outstandingTruncated ? ' (capped)' : ''}',
              color: p.accent,
              emphasis: true,
              hint: 'Money the platform has collected from members and not yet '
                  'passed to the organization. This is the float — it belongs '
                  'to somebody else.',
            ),
            _FloatTile(
              label: 'Settled (24h)',
              value: s == null
                  ? '—'
                  : formatMinorCompact(s.settledLast24hMinor),
              // "auto-APPROVED", not "automatic". The server derives this from
              // `approvalMode == 'auto'`, which records who cleared the 24h
              // hold — never who moved the money. On the V1 manual rail NOTHING
              // is ever paid automatically: `executePayout` returns
              // `awaiting_manual` without transitioning, and only a founder's
              // evidenced Mark-Paid reaches `settled`. Saying "1 automatic" on
              // the one tile that reports money LEAVING invited exactly the
              // wrong conclusion — that the platform had paid a gym without
              // anyone doing it.
              sub: s == null
                  ? ''
                  : '${s.settledLast24hCount} paid · '
                      '${s.autoSettledLast24h} auto-approved',
              color: BrandColors.success,
            ),
            _FloatTile(
              label: 'Needs attention',
              value: attention == null ? '—' : '$attention',
              sub: attention == null
                  ? 'Census unavailable — retry totals'
                  : attention == 0
                      ? 'Nothing blocked'
                      : 'Blocked or failed payouts',
              color: attention == null
                  ? BrandColors.amber
                  : attention == 0
                      ? p.textMuted
                      : BrandColors.error,
            ),
            _FloatTile(
              label: 'Overdue',
              value: overdue == null ? '—' : '$overdue',
              sub: overdue == null
                  ? 'Count unavailable — retry totals'
                  : overdue == 0
                      ? 'Clock on schedule'
                      : 'Past the hold window',
              color: overdue == null || overdue > 0
                  ? BrandColors.amber
                  : p.textMuted,
              hint: 'Pending settlements whose hold window has elapsed. The '
                  'engine should have released these — if they persist, '
                  'something is blocking them.',
            ),
          ];

          return wide
              ? Row(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      Expanded(flex: i == 0 ? 2 : 1, child: tiles[i]),
                      if (i != tiles.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                )
              : Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final t in tiles)
                      SizedBox(width: (box.maxWidth - 12) / 2, child: t),
                  ],
                );
        },
      );
    });
  }
}

class _FloatTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;
  final bool emphasis;
  final String? hint;

  const _FloatTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    this.emphasis = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: emphasis ? color.withValues(alpha: 0.07) : p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(
          color: emphasis ? color.withValues(alpha: 0.35) : p.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: AppText.body(size: 10).copyWith(
                    color: p.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (hint != null)
                Icon(Icons.info_outline, size: 13, color: p.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.title(size: emphasis ? 34 : 26)
                  .copyWith(color: color),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
    return hint == null ? card : Tooltip(message: hint!, child: card);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FILTERS
// ═════════════════════════════════════════════════════════════════════════════

class _ViewChips extends StatelessWidget {
  const _ViewChips();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    return Obx(
      () => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final v in SettlementView.values)
            ConsoleChip(
              label: v.label,
              active: c.view.value == v,
              onTap: () => c.setView(v),
            ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatefulWidget {
  const _FilterBar();

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  // A StatefulWidget purely so this controller is disposed. A search field on a
  // StatelessWidget leaks its TextEditingController — a defect this console has
  // already had to fix elsewhere.
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;

    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 700;
        final field = TextField(
          controller: _search,
          onChanged: (v) => c.search.value = v,
          style: AppText.body(size: 13).copyWith(color: p.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText:
                'Search organization, member, plan, payment id, order id or UTR',
            hintStyle: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            prefixIcon: Icon(Icons.search, size: 18, color: p.textMuted),
            filled: true,
            fillColor: p.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.accent),
            ),
          ),
        );

        final orgPicker = Obx(() {
          final orgs = c.organizations;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: p.inputFill,
              borderRadius: AppRadii.smR,
              border: Border.all(color: p.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: c.orgFilter.value.isEmpty ? '' : c.orgFilter.value,
                isDense: true,
                isExpanded: true,
                style: AppText.body(size: 13).copyWith(color: p.textPrimary),
                dropdownColor: p.surface,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('All organizations'),
                  ),
                  for (final o in orgs)
                    DropdownMenuItem(
                      value: o.id,
                      child: Text(o.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => c.orgFilter.value = v ?? '',
              ),
            ),
          );
        });

        if (narrow) {
          return Column(
            children: [
              field,
              const SizedBox(height: 10),
              SizedBox(height: 46, child: orgPicker),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 3, child: field),
            const SizedBox(width: 12),
            SizedBox(width: 240, height: 46, child: orgPicker),
          ],
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// THE QUEUE
// ═════════════════════════════════════════════════════════════════════════════

class _SettlementList extends StatelessWidget {
  const _SettlementList();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;

    return Obx(() {
      // The exception queue is a different beast: alerts about payments with
      // NO settlement. Rendered with its own card shape so an operator can
      // never mistake one for money that is ready to move.
      if (c.view.value == SettlementView.exceptions) {
        return const _ExceptionList();
      }
      final rows = c.visible;

      if (rows.isEmpty) {
        return ConsoleEmptyState(
          icon: Icons.account_balance_outlined,
          title: c.settlements.isEmpty
              ? 'No settlements yet'
              : 'Nothing matches this view',
          // Always says WHY. An empty settlement queue and an over-narrow
          // filter look identical, and confusing the two during a payout
          // incident is expensive.
          message: c.settlements.isEmpty
              ? 'A settlement is created automatically when a member pays for '
                  'a membership through the platform. Offline payments the gym '
                  'collects at the counter never appear here — the gym already '
                  'holds that money.'
              : 'Clear the search or choose a different view.',
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 4),
            child: Text(
              '${rows.length} shown · ${formatMinor(c.visibleNetMinor)} '
              'outstanding on this page',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ),
          for (final s in rows) ...[
            _SettlementRow(settlement: s),
            const SizedBox(height: 8),
          ],
        ],
      );
    });
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EXCEPTION QUEUE — charged_not_activated (NOT settlements)
// ═════════════════════════════════════════════════════════════════════════════

class _ExceptionList extends StatelessWidget {
  const _ExceptionList();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;

    return Obx(() {
      if (c.exceptionsLoading.value) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      // 🔴 An UNREAD queue is not an EMPTY one. Rendering the empty state here
      // told the operator that nobody had been charged-without-activation, on
      // the strength of a stream that failed.
      final err = c.exceptionsError.value;
      if (err != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: ConsoleErrorState(error: err, onRetry: c.retryExceptions),
        );
      }
      final rows = c.exceptions;
      if (rows.isEmpty) {
        return const ConsoleEmptyState(
          icon: Icons.rule_folder_outlined,
          title: 'No exceptions',
          message: 'A payment lands here when it was captured at the gateway '
              'but the membership was never activated — no receipt and no '
              'settlement exist. The reconciliation sweep detects these '
              'within about 30 minutes.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BrandColors.amber.withValues(alpha: 0.08),
              borderRadius: AppRadii.smR,
              border:
                  Border.all(color: BrandColors.amber.withValues(alpha: 0.35)),
            ),
            child: Text(
              'These are NOT settlements. Each is a captured payment with no '
              'activated membership — the member paid, and nothing was '
              'delivered. Verify each at the Razorpay dashboard. The member\'s '
              'own app retry still activates it normally; nothing here will '
              'ever create a settlement automatically.',
              style: AppText.body(size: 11.5).copyWith(color: p.textSecondary),
            ),
          ),
          for (final a in rows) ...[
            _ExceptionCard(alert: a),
            const SizedBox(height: 8),
          ],
        ],
      );
    });
  }
}

class _ExceptionCard extends StatelessWidget {
  final ChargedOrderAlert alert;

  const _ExceptionCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = alert;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: BrandColors.amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ConsolePill(
                label: 'EXCEPTION',
                color: BrandColors.amber,
                icon: Icons.report_gmailerrorred_outlined,
              ),
              const SizedBox(width: 8),
              ConsolePill(
                label: a.type == 'membership'
                    ? 'Member payment'
                    : a.type == 'subscription'
                        ? 'Org subscription'
                        : 'Unknown type',
                color: p.textMuted,
              ),
              const Spacer(),
              Text(
                a.amountPaise > 0 ? formatMinor(a.amountPaise) : '—',
                style: AppText.title(size: 18).copyWith(color: p.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _KV('Order', a.orderId, copyable: true),
          _KV('Payment', a.paymentId.isEmpty ? '—' : a.paymentId,
              copyable: a.paymentId.isNotEmpty),
          if (a.memberUid.isNotEmpty) _KV('Member uid', a.memberUid, copyable: true),
          if (a.adminUid.isNotEmpty) _KV('Buyer org', a.adminUid, copyable: true),
          _KV('Detected', _stamp(a.createdAt)),
          _KV(
            'Why exceptional',
            'Captured at the gateway; activation callback never completed. '
            'No receipt, no settlement.',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Tooltip(
                message:
                    'The verified recovery workflow (re-verify the payment '
                    'live at Razorpay, then activate through the canonical '
                    'path or refund) is designed but not yet enabled in the '
                    'backend. Until then: verify at the Razorpay dashboard '
                    'and use Refund there if the member should get their '
                    'money back.',
                child: OutlinedButton.icon(
                  onPressed: null, // deliberately disabled — no invented callable
                  icon: const Icon(Icons.build_circle_outlined, size: 16),
                  label: const Text('Recover — workflow not yet enabled'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Colour for a status. Kept in one place so a chip, a pill and a border can
/// never disagree about what "failed" looks like.
Color statusColor(BuildContext context, SettlementStatus s) {
  final p = context.palette;
  return switch (s) {
    SettlementStatus.settled => BrandColors.success,
    SettlementStatus.pending => p.accent,
    SettlementStatus.approved => const Color(0xFF2962FF),
    SettlementStatus.settling => const Color(0xFF7C4DFF),
    SettlementStatus.onHold => BrandColors.amber,
    SettlementStatus.underReview => BrandColors.amber,
    SettlementStatus.failed => BrandColors.error,
    SettlementStatus.chargeback => BrandColors.error,
    SettlementStatus.refunded => p.textMuted,
    SettlementStatus.cancelled => p.textMuted,
    SettlementStatus.unknown => p.textMuted,
  };
}

class _SettlementRow extends StatelessWidget {
  final SettlementModel settlement;

  const _SettlementRow({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = Get.find<SettlementController>();
    final s = settlement;
    final color = statusColor(context, s.status);

    return InkWell(
      borderRadius: AppRadii.cardR,
      onTap: () => _openDetail(context, s),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(
            color: s.status.needsAttention
                ? color.withValues(alpha: 0.45)
                : p.border,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth > 780;

            final identity = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  s.orgName.isEmpty ? s.adminId : s.orgName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle(size: 14)
                      .copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.memberName.isEmpty ? 'Member' : s.memberName} · '
                  '${s.planName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                ),
              ],
            );

            final money = Column(
              crossAxisAlignment:
                  wide ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatMinor(s.netMinor, currency: s.currency),
                  style: AppText.title(size: 19).copyWith(color: p.textPrimary),
                ),
                Text(
                  s.totalDeductionsMinor == 0
                      ? 'of ${formatMinor(s.grossMinor)}'
                      : 'of ${formatMinor(s.grossMinor)} · '
                          '−${formatMinor(s.totalDeductionsMinor)} fees',
                  style: AppText.body(size: 10.5).copyWith(color: p.textMuted),
                ),
              ],
            );

            final badges = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ConsolePill(label: s.status.label, color: color),
                if (!s.paymentState.isClean)
                  ConsolePill(
                    label: s.paymentState.label,
                    color: BrandColors.error,
                    icon: Icons.gavel_outlined,
                  ),
                if (!s.feesFinalized)
                  ConsolePill(
                    label: 'Fees pending',
                    color: BrandColors.amber,
                    icon: Icons.hourglass_empty,
                  ),
                if (s.approvalMode == 'auto')
                  ConsolePill(
                    label: 'Auto',
                    color: p.textMuted,
                    icon: Icons.bolt_outlined,
                  ),
                if (s.isOverdue)
                  ConsolePill(
                    label: 'Overdue',
                    color: BrandColors.amber,
                    icon: Icons.schedule,
                  ),
                if (!s.breakdownCloses)
                  ConsolePill(
                    label: 'Breakdown mismatch',
                    color: BrandColors.error,
                    icon: Icons.warning_amber_outlined,
                  ),
              ],
            );

            final clock = _ClockLabel(settlement: s);

            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  identity,
                  const SizedBox(height: 10),
                  money,
                  const SizedBox(height: 10),
                  badges,
                  const SizedBox(height: 6),
                  clock,
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 3, child: identity),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: badges),
                const SizedBox(width: 12),
                SizedBox(width: 132, child: clock),
                const SizedBox(width: 12),
                SizedBox(width: 150, child: money),
                const SizedBox(width: 6),
                Obx(
                  () => IconButton(
                    tooltip: 'Open settlement',
                    onPressed: c.acting.value
                        ? null
                        : () => _openDetail(context, s),
                    icon: Icon(Icons.chevron_right, color: p.textMuted),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The countdown to auto-settlement, or why there is no countdown.
///
/// Rendered as text rather than a live ticker: a payout queue is not a game,
/// and a per-row timer rebuilding every second on a list of three hundred rows
/// costs more than it communicates.
class _ClockLabel extends StatelessWidget {
  final SettlementModel settlement;

  const _ClockLabel({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = settlement;

    String text;
    Color color = p.textMuted;
    IconData icon = Icons.schedule;

    if (s.status == SettlementStatus.settled) {
      text = s.settledAt == null ? 'Settled' : _ago(s.settledAt!);
      icon = Icons.check_circle_outline;
      color = BrandColors.success;
    } else if (s.status.isTerminal) {
      text = s.status.label;
      icon = Icons.block_outlined;
    } else if (s.status == SettlementStatus.onHold) {
      text = 'Clock stopped';
      icon = Icons.pause_circle_outline;
      color = BrandColors.amber;
    } else if (s.status == SettlementStatus.underReview) {
      text = 'Awaiting review';
      icon = Icons.report_gmailerrorred_outlined;
      color = BrandColors.amber;
    } else if (s.status == SettlementStatus.settling) {
      text = 'In flight';
      icon = Icons.send_outlined;
      color = const Color(0xFF7C4DFF);
    } else if (s.status == SettlementStatus.approved) {
      text = 'Ready to pay';
      icon = Icons.task_alt;
      color = const Color(0xFF2962FF);
    } else if (s.status == SettlementStatus.failed) {
      text = 'Payout failed';
      icon = Icons.error_outline;
      color = BrandColors.error;
    } else {
      final left = s.timeUntilAutoSettle();
      if (left == null) {
        text = 'No clock';
      } else if (left == Duration.zero) {
        text = 'Due now';
        color = BrandColors.amber;
      } else if (left.inHours >= 1) {
        text = 'in ${left.inHours}h ${left.inMinutes % 60}m';
      } else {
        text = 'in ${left.inMinutes}m';
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body(size: 11.5).copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'just now';
}

String _stamp(DateTime? d) {
  if (d == null) return '—';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} ${d.year}, '
      '${two(d.hour)}:${two(d.minute)}';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// ═════════════════════════════════════════════════════════════════════════════
// DETAIL
// ═════════════════════════════════════════════════════════════════════════════

void _openDetail(BuildContext context, SettlementModel s) {
  final c = Get.find<SettlementController>();
  c.openSettlement(s);
  showDialog<void>(
    context: context,
    // A money action must not be dismissed by a stray tap mid-request.
    barrierDismissible: false,
    builder: (_) => const _SettlementDetailDialog(),
  ).then((_) => c.closeSettlement());
}

class _SettlementDetailDialog extends StatelessWidget {
  const _SettlementDetailDialog();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;

    return Dialog(
      backgroundColor: p.background,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardR),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Obx(() {
        // Keeps the pane in sync with the live list, so a status change caused
        // by the sweep — or by this dialog's own action — appears immediately.
        c.syncSelected();
        final s = c.selected.value;
        if (s == null) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailHeader(settlement: s),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final wide = box.maxWidth > 780;
                      final left = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MoneyBreakdown(settlement: s),
                          if (s.transfer != null || s.proof != null) ...[
                            const SizedBox(height: 14),
                            _TransferRecordCard(settlement: s),
                          ],
                          const SizedBox(height: 14),
                          _PartiesCard(settlement: s),
                          const SizedBox(height: 14),
                          _DestinationCard(settlement: s),
                          const SizedBox(height: 14),
                          _ReferencesCard(settlement: s),
                        ],
                      );
                      final right = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StateCard(settlement: s),
                          const SizedBox(height: 14),
                          const _TimelineCard(),
                          const SizedBox(height: 14),
                          const _LedgerCard(),
                          const SizedBox(height: 14),
                          const _WebhookCard(),
                        ],
                      );

                      if (!wide) {
                        return Column(
                          children: [left, const SizedBox(height: 14), right],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: left),
                          const SizedBox(width: 16),
                          Expanded(flex: 6, child: right),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const Divider(height: 1),
              _ActionBar(settlement: s),
            ],
          ),
        );
      }),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final SettlementModel settlement;

  const _DetailHeader({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = settlement;
    final color = statusColor(context, s.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadii.smR,
            ),
            child: Icon(Icons.account_balance_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatMinor(s.netMinor, currency: s.currency),
                  style: AppText.title(size: 24).copyWith(color: p.textPrimary),
                ),
                Text(
                  'to ${s.orgName.isEmpty ? s.adminId : s.orgName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(size: 12).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
          ConsolePill(label: s.status.label, color: color),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: p.textMuted),
          ),
        ],
      ),
    );
  }
}

/// The money breakdown the founder is accountable for.
///
/// Every deduction is shown as its own line rather than as a single "fees"
/// total, because the three have different owners: Razorpay's cut, our
/// commission, and the tax we owe onward. A gym owner disputing their payout
/// asks about exactly one of them.
class _MoneyBreakdown extends StatelessWidget {
  final SettlementModel settlement;

  const _MoneyBreakdown({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = settlement;

    Widget line(
      String label,
      String value, {
      Color? color,
      bool bold = false,
      String? note,
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppText.body(size: 12.5).copyWith(
                        color: color ?? p.textSecondary,
                        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (note != null)
                      Text(
                        note,
                        style: AppText.body(size: 10.5)
                            .copyWith(color: p.textMuted),
                      ),
                  ],
                ),
              ),
              Text(
                value,
                style: AppText.body(size: 13).copyWith(
                  color: color ?? p.textPrimary,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );

    return ConsoleCard(
      title: 'MONEY',
      trailing: s.feesFinalized
          ? const ConsolePill(
              label: 'Final',
              color: BrandColors.success,
              icon: Icons.verified_outlined,
            )
          : const ConsolePill(
              label: 'Provisional',
              color: BrandColors.amber,
              icon: Icons.hourglass_empty,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line('Member paid', formatMinor(s.grossMinor), bold: true),
          const Divider(height: 18),
          line(
            'Gateway fee',
            '−${formatMinor(s.gatewayFeeMinor)}',
            note: s.terms.orgBearsGatewayFee
                ? "Razorpay's charge, deducted from the organization"
                : 'Absorbed by Trainersarena',
            color: p.textSecondary,
          ),
          line(
            'Gateway GST',
            '−${formatMinor(s.gatewayTaxMinor)}',
            color: p.textSecondary,
          ),
          line(
            'Platform fee',
            '−${formatMinor(s.platformFeeMinor)}',
            note: 'On gross at ${s.terms.platformFeeLabel}',
            color: p.textSecondary,
          ),
          line(
            'GST on platform fee',
            '−${formatMinor(s.platformFeeTaxMinor)}',
            color: p.textSecondary,
          ),
          if (s.refundedGrossMinor > 0)
            line(
              'Refunded to member',
              '−${formatMinor(s.refundedGrossMinor)}',
              color: BrandColors.error,
            ),
          const Divider(height: 18),
          line(
            'Settlement amount',
            formatMinor(s.netMinor),
            bold: true,
            color: p.accent,
          ),
          if (s.recoveryMinor > 0)
            line(
              'Recoverable from organization',
              formatMinor(s.recoveryMinor),
              color: BrandColors.error,
              bold: true,
              note: 'Reversed after we had already settled',
            ),
          if (!s.breakdownCloses) ...[
            const SizedBox(height: 10),
            _Warning(
              // A settlement whose parts do not sum to its gross is a genuine
              // anomaly. The backend refuses to post it to the ledger, so
              // showing it here is how a human finds out.
              'The parts of this settlement do not sum to the amount the '
              'member paid. It has NOT been posted to the ledger. Investigate '
              'before approving.',
            ),
          ],
          if (!s.feesFinalized) ...[
            const SizedBox(height: 10),
            _Warning(
              "Razorpay has not yet reported its actual fee, so this "
              "settlement amount is provisional. It cannot auto-settle until "
              "the fee is confirmed — the hourly sweep fetches it if the "
              "webhook does not arrive.",
              color: BrandColors.amber,
            ),
          ],
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final String message;
  final Color color;

  const _Warning(this.message, {this.color = BrandColors.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadii.smR,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_outlined, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppText.body(size: 11.5).copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// The manual transfer's permanent record — what was sent, when, how, and the
/// verified proof behind it. Only rendered once the backend accepted the
/// evidence; nothing here is ever the console's own claim.
class _TransferRecordCard extends StatelessWidget {
  final SettlementModel settlement;

  const _TransferRecordCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final t = s.transfer;
    final proof = s.proof;

    return ConsoleCard(
      title: 'TRANSFER',
      trailing: const ConsolePill(
        label: 'Evidenced',
        color: BrandColors.success,
        icon: Icons.verified_outlined,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t != null) ...[
            _KV('Transferred', _stamp(t.transferredAt)),
            _KV('Method', t.methodLabel),
            _KV('Amount', formatMinor(t.amountMinor)),
            _KV('UTR', t.utr, copyable: true),
            if (t.notes.isNotEmpty) _KV('Note to organization', t.notes),
          ],
          if (proof != null) ...[
            const Divider(height: 18),
            _KV('Proof', '${proof.fileName} · ${proof.sizeLabel}'),
            _KV('Uploaded by', proof.uploadedBy, copyable: true),
            _KV('Uploaded', _stamp(proof.uploadedAt)),
            _KV(
              'SHA-256',
              proof.sha256,
              copyable: true,
              hint: 'Computed by the backend from the stored bytes at '
                  'confirmation. Re-hash a downloaded copy to prove it is '
                  'the same document.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final url = await FirebaseStorage.instance
                      .ref(proof.storagePath)
                      .getDownloadURL();
                  await Clipboard.setData(ClipboardData(text: url));
                  messenger.showSnackBar(const SnackBar(
                    content: Text(
                      'Proof link copied — paste it into a new tab to view.',
                    ),
                    duration: Duration(seconds: 3),
                  ));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(
                    content: Text('Could not fetch the proof link: $e'),
                    backgroundColor: BrandColors.error,
                  ));
                }
              },
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Copy proof link'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PartiesCard extends StatelessWidget {
  final SettlementModel settlement;

  const _PartiesCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    return ConsoleCard(
      title: 'PARTIES',
      child: Column(
        children: [
          _KV('Organization', s.orgName.isEmpty ? '—' : s.orgName),
          _KV('Organization id', s.adminId, copyable: true),
          _KV('Member', s.memberName.isEmpty ? '—' : s.memberName),
          _KV('Member record', s.clientId, copyable: true),
          _KV('Plan', s.planName),
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final SettlementModel settlement;

  const _DestinationCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    final d = s.destination;

    return ConsoleCard(
      title: 'PAYOUT DESTINATION',
      child: d == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No destination recorded on this settlement yet. It is '
                  'resolved fresh from the organization\'s bank details at '
                  'approval — a gym that corrects its IFSC is paid to the new '
                  'one.',
                  style: AppText.body(size: 11.5)
                      .copyWith(color: context.palette.textMuted),
                ),
              ],
            )
          : Column(
              children: [
                _KV('Method', d.isUpi ? 'UPI' : 'Bank transfer'),
                _KV(d.isUpi ? 'UPI ID' : 'Account', d.label),
                if (!d.isUpi) _KV('IFSC', d.ifsc.isEmpty ? '—' : d.ifsc),
                if (!d.isUpi)
                  _KV('Bank', d.bankName.isEmpty ? '—' : d.bankName),
                _KV(
                  'Account name',
                  d.accountName.isEmpty ? '—' : d.accountName,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 12,
                      color: context.palette.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        // Stated explicitly so nobody goes looking for the full
                        // number: it is never stored here, by design.
                        'Stored masked. The full account number never enters '
                        'a settlement record, an audit log or a log line.',
                        style: AppText.body(size: 10.5)
                            .copyWith(color: context.palette.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _ReferencesCard extends StatelessWidget {
  final SettlementModel settlement;

  const _ReferencesCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    return ConsoleCard(
      title: 'REFERENCES',
      child: Column(
        children: [
          _KV('Payment id', s.razorpayPaymentId, copyable: true),
          _KV('Order id', s.razorpayOrderId, copyable: true),
          _KV('Receipt', s.memberPaymentId, copyable: true),
          if (s.utr.isNotEmpty) _KV('Bank reference (UTR)', s.utr, copyable: true),
          if (s.railPayoutId.isNotEmpty)
            _KV('Rail payout id', s.railPayoutId, copyable: true),
          if (s.payoutIdempotencyKey.isNotEmpty)
            _KV(
              'Idempotency key',
              s.payoutIdempotencyKey,
              copyable: true,
              hint: 'Query the payout rail with this key to establish what '
                  'actually happened, instead of guessing and risking a '
                  'double payment.',
            ),
          _KV('Captured', _stamp(s.capturedAt)),
          _KV('Created from', s.createdFrom.isEmpty ? '—' : s.createdFrom),
        ],
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  final SettlementModel settlement;

  const _StateCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final s = settlement;
    return ConsoleCard(
      title: 'STATE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KV('Settlement status', s.status.label),
          _KV('Payment at gateway', s.paymentState.label),
          _KV(
            'Auto-settles',
            s.autoSettleAt == null ? 'No clock running' : _stamp(s.autoSettleAt),
            hint: 'Precomputed when the settlement was created. A later change '
                'to the hold policy does not re-time an existing obligation.',
          ),
          _KV('Hold window', '${s.terms.holdHours} hours'),
          _KV('Platform fee rate', s.terms.platformFeeLabel),
          _KV(
            'Gateway fee borne by',
            s.terms.orgBearsGatewayFee ? 'Organization' : 'Trainersarena',
          ),
          _KV('Payout rail', s.payoutRail),
          if (s.payoutAttempt > 0)
            _KV('Payout attempts', '${s.payoutAttempt}'),
          if (s.approvedAt != null)
            _KV(
              'Approved',
              '${_stamp(s.approvedAt)}'
              '${s.approvalMode == 'auto' ? ' (automatic)' : ''}',
            ),
          if (s.settledAt != null) _KV('Settled', _stamp(s.settledAt)),
          if (s.holdReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Warning(s.holdReason, color: BrandColors.amber),
          ],
          if (s.reviewReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Warning(s.reviewReason, color: BrandColors.amber),
          ],
          if (s.lastFailureMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Warning(
              '${s.lastFailureMessage}'
              '${s.isRetryFutile ? '\n\nThis failure is permanent — retrying '
                  'will fail identically. The organization must correct its '
                  'bank details first.' : ''}',
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;

    return ConsoleCard(
      title: 'TIMELINE',
      child: Obx(() {
        if (c.detailLoading.value && c.timeline.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (c.timeline.isEmpty) {
          return Text(
            'No timeline entries.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in c.timeline) _TimelineTile(entry: e),
          ],
        );
      }),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  final SettlementTimelineEntry entry;

  const _TimelineTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = entry;

    // The actor is colour-coded because the first question asked about any
    // disputed payout is whether a human or the machine caused it.
    final (Color color, IconData icon) = e.isGateway
        ? (const Color(0xFF7C4DFF), Icons.cloud_outlined)
        : e.isSystem
            ? (p.textMuted, Icons.bolt_outlined)
            : (p.accent, Icons.person_outline);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.event.replaceAll('_', ' '),
                        style: AppText.body(size: 12).copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _stamp(e.createdAt),
                      style: AppText.body(size: 10)
                          .copyWith(color: p.textMuted),
                    ),
                  ],
                ),
                if (e.message.isNotEmpty)
                  Text(
                    e.message,
                    style:
                        AppText.body(size: 11.5).copyWith(color: p.textSecondary),
                  ),
                if (e.fromStatus != null && e.toStatus != null)
                  Text(
                    '${e.fromStatus!.label} → ${e.toStatus!.label}',
                    style: AppText.body(size: 10.5).copyWith(color: color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The double-entry legs behind this settlement.
///
/// Shown to the founder rather than hidden because the ledger is the reason the
/// numbers above can be trusted: every transaction balances, and an operator
/// who can see that is an operator who can answer an auditor.
class _LedgerCard extends StatelessWidget {
  const _LedgerCard();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;

    return ConsoleCard(
      title: 'LEDGER',
      child: Obx(() {
        if (c.ledger.isEmpty) {
          return Text(
            'No ledger entries yet. The float is posted once the gateway '
            'confirms its fee — until then the obligation exists as a '
            'settlement but not as a ledger transaction.',
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
          );
        }

        String? currentTxn;
        final rows = <Widget>[];
        for (final e in c.ledger) {
          if (e.txnId != currentTxn) {
            currentTxn = e.txnId;
            rows.add(
              Padding(
                padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 12, bottom: 4),
                child: Text(
                  e.event.replaceAll('_', ' ').toUpperCase(),
                  style: AppText.body(size: 10).copyWith(
                    color: p.textMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            );
          }
          rows.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      e.isDebit ? 'DR' : 'CR',
                      style: AppText.body(size: 10.5).copyWith(
                        color: e.isDebit ? p.accent : BrandColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.accountBase,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(size: 11.5)
                          .copyWith(color: p.textSecondary),
                    ),
                  ),
                  Text(
                    formatMinor(e.amountMinor),
                    style: AppText.body(size: 11.5).copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // The proof. Rendered because an unbalanced transaction would be a
        // serious defect and the operator should be able to see that it is not.
        final dr = c.ledger
            .where((e) => e.isDebit)
            .fold(0, (t, e) => t + e.amountMinor);
        final cr = c.ledger
            .where((e) => !e.isDebit)
            .fold(0, (t, e) => t + e.amountMinor);
        final balanced = dr == cr;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...rows,
            const Divider(height: 18),
            Row(
              children: [
                Icon(
                  balanced ? Icons.check_circle_outline : Icons.error_outline,
                  size: 14,
                  color: balanced ? BrandColors.success : BrandColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    balanced
                        ? 'Balanced · ${formatMinor(dr)} debits = '
                            '${formatMinor(cr)} credits'
                        : 'UNBALANCED · ${formatMinor(dr)} debits ≠ '
                            '${formatMinor(cr)} credits',
                    style: AppText.body(size: 11).copyWith(
                      color:
                          balanced ? BrandColors.success : BrandColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _WebhookCard extends StatelessWidget {
  const _WebhookCard();

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;

    return ConsoleCard(
      title: 'GATEWAY EVENTS',
      child: Obx(() {
        // 🔴 A DIAGNOSIS IS NOT AN EMPTY STATE. The copy below names a probable
        // cause ("the Razorpay webhook may not be registered"). Rendering it
        // for a stream that FAILED sends the operator to investigate the
        // gateway's configuration because a Firestore read was denied.
        if (c.webhookError.value) {
          return Text(
            'The webhook evidence for this payment could not be read, so this '
            'panel cannot say whether events exist. This is a console read '
            'failure — it is NOT evidence about the Razorpay webhook.',
            style: AppText.body(size: 11.5).copyWith(color: p.error),
          );
        }
        if (c.webhookEvents.isEmpty) {
          return Text(
            'No webhook events recorded for this payment. If the settlement '
            'is stuck on provisional fees, the Razorpay webhook may not be '
            'registered — see the architecture document.',
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in c.webhookEvents)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      w.isHealthy
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 14,
                      color: w.isHealthy
                          ? BrandColors.success
                          : BrandColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            w.event,
                            style: AppText.body(size: 11.5).copyWith(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (w.result.isNotEmpty)
                            Text(
                              w.result,
                              style: AppText.body(size: 10.5)
                                  .copyWith(color: p.textMuted),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _stamp(w.receivedAt),
                      style:
                          AppText.body(size: 10).copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _KV extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  final String? hint;

  const _KV(this.label, this.value, {this.copyable = false, this.hint});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 138,
            child: Text(
              label,
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ),
          Expanded(
            child: copyable
                // SelectableText so an operator can lift an id straight into
                // the Razorpay dashboard — the console rule for every
                // reference value.
                ? SelectableText(
                    value.isEmpty ? '—' : value,
                    style: AppText.body(size: 12).copyWith(
                      color: p.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : Text(
                    value.isEmpty ? '—' : value,
                    style:
                        AppText.body(size: 12).copyWith(color: p.textPrimary),
                  ),
          ),
          if (copyable && value.isNotEmpty)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$label copied'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.copy, size: 13, color: p.textMuted),
              ),
            ),
        ],
      ),
    );
    return hint == null ? row : Tooltip(message: hint!, child: row);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ACTIONS
// ═════════════════════════════════════════════════════════════════════════════

class _ActionBar extends StatelessWidget {
  final SettlementModel settlement;

  const _ActionBar({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<SettlementController>();
    final p = context.palette;
    final s = settlement;

    return Obx(() {
      final busy = c.acting.value;

      // The state machine, surfaced as buttons. Anything the backend would
      // refuse is simply not offered — a disabled-looking button that throws
      // "illegal transition" teaches an operator to distrust the console.
      final canApprove = const {
        SettlementStatus.pending,
        SettlementStatus.underReview,
        SettlementStatus.onHold,
      }.contains(s.status);
      final canHold = const {
        SettlementStatus.pending,
        SettlementStatus.underReview,
        SettlementStatus.approved,
        SettlementStatus.failed,
      }.contains(s.status);
      final canRelease = const {
        SettlementStatus.onHold,
        SettlementStatus.underReview,
      }.contains(s.status);
      final canRetry = s.status == SettlementStatus.failed;
      final canConfirm = s.status == SettlementStatus.approved ||
          s.status == SettlementStatus.settling;
      final canCancel = s.isActionable;
      final canRefund = !s.status.isTerminal && s.paymentState.isClean;

      return Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.status == SettlementStatus.settling)
              _Warning(
                'A payout is in flight and its outcome is unknown. Nothing can '
                'act on this settlement until it resolves — confirm it with '
                'the bank reference, or record the failure. Querying the rail '
                'with the idempotency key above tells you which.',
                color: BrandColors.amber,
              ),
            if (s.status.isTerminal)
              Text(
                'This settlement is ${s.status.label.toLowerCase()} and cannot '
                'be changed. Correct it with a ledger adjustment instead.',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            if (!s.status.isTerminal) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canApprove)
                    _ActionButton(
                      label: 'Approve',
                      icon: Icons.task_alt,
                      primary: true,
                      busy: busy,
                      onPressed: () => _approve(context, c, s),
                    ),
                  if (canConfirm)
                    _ActionButton(
                      // Named for what the founder is DOING, per state. Never
                      // "Mark Paid" — approval and payment are different facts.
                      label: s.status == SettlementStatus.settling
                          ? 'Confirm rail payout'
                          : 'Transfer to organization',
                      icon: Icons.receipt_long_outlined,
                      primary: true,
                      busy: busy,
                      onPressed: () => _confirm(context, c, s),
                    ),
                  if (canRetry)
                    _ActionButton(
                      label: 'Retry payout',
                      icon: Icons.refresh,
                      busy: busy,
                      onPressed: () => _run(
                        context,
                        () => c.retry(s.id),
                      ),
                    ),
                  if (canHold)
                    _ActionButton(
                      label: 'Hold',
                      icon: Icons.pause_circle_outline,
                      busy: busy,
                      onPressed: () => _reasonThen(
                        context,
                        title: 'Hold this settlement',
                        // The reason is mandatory in the backend too: a hold
                        // with no stated reason is indistinguishable from a
                        // mistake three weeks later.
                        message: 'The auto-settlement clock stops until you '
                            'release it. State why — this is recorded on the '
                            'timeline the organization can read.',
                        actionLabel: 'Hold',
                        onSubmit: (r) => c.hold(s.id, r),
                      ),
                    ),
                  if (canRelease)
                    _ActionButton(
                      label: 'Release',
                      icon: Icons.play_circle_outline,
                      busy: busy,
                      onPressed: () => _run(
                        context,
                        () => c.release(s.id),
                      ),
                    ),
                  if (canRefund)
                    _ActionButton(
                      label: 'Refund member',
                      icon: Icons.undo,
                      danger: true,
                      busy: busy,
                      onPressed: () => _refund(context, c, s),
                    ),
                  if (canCancel)
                    _ActionButton(
                      label: 'Cancel',
                      icon: Icons.block,
                      danger: true,
                      busy: busy,
                      onPressed: () => _reasonThen(
                        context,
                        title: 'Cancel this settlement',
                        message: 'This is permanent. The platform still holds '
                            'the member\'s money — cancelling only stops it '
                            'being paid through this record. Discharging the '
                            'liability needs a separate ledger adjustment.',
                        actionLabel: 'Cancel settlement',
                        onSubmit: (r) => c.cancel(s.id, r),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      );
    });
  }

  Future<void> _approve(
    BuildContext context,
    SettlementController c,
    SettlementModel s,
  ) async {
    final ok = await _confirmDialog(
      context,
      title: 'Approve ${formatMinor(s.netMinor)}?',
      message: 'This clears ${formatMinor(s.netMinor)} for payment to '
          '${s.orgName.isEmpty ? s.adminId : s.orgName}'
          '${s.destination == null ? '' : ' (${s.destination!.label})'}.\n\n'
          'On the manual rail nothing is transferred automatically: the '
          'settlement moves to Ready to pay, and you record the bank '
          'reference once you have sent the money.',
      actionLabel: 'Approve',
    );
    if (!ok || !context.mounted) return;
    await _run(context, () => c.approve(s.id));
  }

  Future<void> _confirm(
    BuildContext context,
    SettlementController c,
    SettlementModel s,
  ) async {
    // TWO different confirmations share this button, routed by status:
    //   settling → an AUTOMATED rail moved the money; the founder relays the
    //              UTR the rail reported. No evidence contract applies.
    //   approved → the V1 MANUAL transfer. The founder personally moved the
    //              money and must evidence it: date, method, exact amount,
    //              proof document. The backend enforces all of it again
    //              inside the settle transaction.
    if (s.status == SettlementStatus.settling) {
      final utr = await _promptDialog(
        context,
        title: 'Confirm the rail payout',
        message: 'Enter the bank reference (UTR) the payout rail reported. '
            'This closes the in-flight window.',
        label: 'UTR / bank reference',
        actionLabel: 'Confirm settled',
      );
      if (utr == null || utr.trim().isEmpty || !context.mounted) return;
      await _run(context, () => c.confirmPaid(s.id, utr.trim()));
      return;
    }

    // Manual transfer. Progress is adapted Rx→ValueNotifier so the dialog
    // stays free of GetX and unit-testable.
    final progress = ValueNotifier<double>(-1);
    final worker = ever<double>(c.uploadProgress, (v) => progress.value = v);
    try {
      final settled = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => TransferDialog(
          settlement: s,
          onUploadProof: ({
            required bytes,
            required fileName,
            required contentType,
          }) =>
              c.uploadProof(
            settlementId: s.id,
            bytes: bytes,
            fileName: fileName,
            contentType: contentType,
          ),
          onCancelUpload: c.cancelUpload,
          uploadProgress: progress,
          onSubmit: (sub) => c.confirmTransfer(
            settlementId: s.id,
            utr: sub.utr,
            transferredAt: sub.transferredAt,
            method: sub.method,
            amountMinor: sub.amountMinor,
            notes: sub.notes,
            internalNote: sub.internalNote,
            proofStoragePath: sub.proofStoragePath,
          ),
        ),
      );
      if (settled == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transfer confirmed — the settlement is settled.'),
            backgroundColor: BrandColors.success,
          ),
        );
      }
    } finally {
      worker.dispose();
      progress.dispose();
    }
  }

  Future<void> _refund(
    BuildContext context,
    SettlementController c,
    SettlementModel s,
  ) async {
    final reason = await _promptDialog(
      context,
      title: 'Refund the member',
      message: 'This refunds ${formatMinor(s.grossMinor)} to the member at '
          'Razorpay. It is irreversible.\n\n'
          'The settlement is not changed here: Razorpay confirms the refund by '
          'webhook, and the reversal is then applied to the settlement and the '
          'ledger together. Razorpay does NOT return its processing fee, so '
          'the platform absorbs it.',
      label: 'Reason (recorded in the audit log)',
      actionLabel: 'Refund in full',
      danger: true,
    );
    if (reason == null || !context.mounted) return;
    await _run(
      context,
      () => c.refund(s.razorpayPaymentId, reason: reason.trim()),
    );
  }
}

Future<void> _reasonThen(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  required Future<({bool ok, String message})> Function(String) onSubmit,
}) async {
  final reason = await _promptDialog(
    context,
    title: title,
    message: message,
    label: 'Reason (required)',
    actionLabel: actionLabel,
  );
  if (reason == null || reason.trim().isEmpty || !context.mounted) return;
  await _run(context, () => onSubmit(reason.trim()));
}

Future<void> _run(
  BuildContext context,
  Future<({bool ok, String message})> Function() action,
) async {
  final result = await action();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(result.message),
      backgroundColor:
          result.ok ? BrandColors.success : BrandColors.error,
      duration: Duration(seconds: result.ok ? 4 : 7),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;
  final bool danger;
  final bool busy;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = danger ? BrandColors.error : p.accent;

    if (primary) {
      return FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.smR),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.smR),
      ),
    );
  }
}

Future<bool> _confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: AppText.cardTitle(size: 17)),
      content: Text(message, style: AppText.body(size: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> _promptDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String label,
  required String actionLabel,
  bool danger = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PromptDialog(
      title: title,
      message: message,
      label: label,
      actionLabel: actionLabel,
      danger: danger,
    ),
  );
}

/// A StatefulWidget so the TextEditingController is owned by the dialog's OWN
/// state and disposed in [dispose].
///
/// The previous shape — a function-local controller torn down with
/// `.whenComplete(controller.dispose)` — is the exact defect this codebase has
/// shipped twice before: the future completes when the route STARTS closing,
/// the field is still attached during the pop animation, and the dispose lands
/// mid-frame as "A TextEditingController was used after being disposed",
/// taking the whole screen down with it.
class _PromptDialog extends StatefulWidget {
  final String title;
  final String message;
  final String label;
  final String actionLabel;
  final bool danger;

  const _PromptDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.actionLabel,
    required this.danger,
  });

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: AppText.cardTitle(size: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, style: AppText.body(size: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(borderRadius: AppRadii.smR),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.danger
              ? FilledButton.styleFrom(backgroundColor: BrandColors.error)
              : null,
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
