// The confirmation dialogs behind every organization action.
//
// A powerful action is never one click. Each dialog states, from the plan in
// `OrganizationLanguage.planFor`: WHAT will happen, WHO is affected, what
// CHANGES, whether it can be UNDONE — then asks for a reason where the audit
// trail needs one and, for Block, for the organization's name typed back.
// The dialog itself never calls the backend: it hands the decision to
// [AdminController], which re-reads the record, guards re-entry, calls the
// one callable and reports the outcome. The screen shows progress and result.

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/admin_controller.dart';
import '../../controllers/subscription_controller.dart';
import '../../core/services/action_outcomes.dart';
import '../../core/services/organization_language.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/serena/serena_ui.dart';
import '../../models/admin_model.dart';
import '../../models/subscription_model.dart';
import '../../models/subscription_plan_model.dart';

const Color kOrgDanger = Color(0xFFB3261E);

/// Routes an action to its dialog.
void showOrgActionDialog(
  BuildContext context, {
  required OrgAction action,
  required AdminModel org,
  required AdminController ctrl,
}) {
  if (action == OrgAction.grant) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GrantSubscriptionDialog(org: org, ctrl: ctrl),
    );
    return;
  }
  final plan = OrganizationLanguage.planFor(action, org, now: ctrl.clock());
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OrgConfirmDialog(plan: plan, org: org, ctrl: ctrl),
  );
}

/// The WHAT / WHO / CONSEQUENCES / REVERSIBILITY block shared by every dialog.
class OrgPlanSummary extends StatelessWidget {
  const OrgPlanSummary({
    super.key,
    required this.what,
    required this.who,
    required this.consequences,
    required this.reversibility,
  });

  final String what;
  final String who;
  final List<String> consequences;
  final String reversibility;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row(String label, Widget body) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.body(size: 10.5).copyWith(
              color: p.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          body,
        ],
      ),
    );
    TextStyle t() => AppText.body(size: 13).copyWith(color: p.textPrimary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('WHAT WILL HAPPEN', Text(what, style: t())),
        row('WHO IS AFFECTED', Text(who, style: t())),
        row(
          'WHAT CHANGES',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in consequences)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: t()),
                      Expanded(child: Text(c, style: t())),
                    ],
                  ),
                ),
            ],
          ),
        ),
        row('CAN IT BE UNDONE?', Text(reversibility, style: t())),
      ],
    );
  }
}

/// Approve / Reactivate / Warn / Block.
class OrgConfirmDialog extends StatefulWidget {
  const OrgConfirmDialog({
    super.key,
    required this.plan,
    required this.org,
    required this.ctrl,
  });

  final OrgActionPlan plan;
  final AdminModel org;
  final AdminController ctrl;

  @override
  State<OrgConfirmDialog> createState() => _OrgConfirmDialogState();
}

class _OrgConfirmDialogState extends State<OrgConfirmDialog> {
  final _reason = TextEditingController();
  final _typed = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _typed.dispose();
    super.dispose();
  }

  String get _name => OrganizationLanguage.displayName(widget.org);

  bool get _reasonOk =>
      !widget.plan.requiresReason || _reason.text.trim().isNotEmpty;
  bool get _typedOk =>
      !widget.plan.requiresTypedName || _typed.text.trim() == _name.trim();
  bool get _valid => _reasonOk && _typedOk;

  Future<void> _confirm() async {
    final ctrl = widget.ctrl;
    final org = widget.org;
    final reason = _reason.text.trim();
    Navigator.of(context).pop();
    switch (widget.plan.action) {
      case OrgAction.approve:
        await ctrl.approve(org);
      case OrgAction.reactivate:
        await ctrl.reactivate(org);
      case OrgAction.warn:
        await ctrl.warn(org, reason);
      case OrgAction.block:
        await ctrl.block(org, reason);
      case OrgAction.reapplyEffects:
        await ctrl.reapplyStatusEffects(org);
      case OrgAction.grant:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final plan = widget.plan;
    final danger = plan.action.isDestructive;
    return AlertDialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      title: Text(
        plan.title,
        style: AppText.title(size: 20).copyWith(color: p.textPrimary),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrgPlanSummary(
                what: plan.what,
                who: plan.who,
                consequences: plan.consequences,
                reversibility: plan.reversibility,
              ),
              if (plan.requiresReason) ...[
                const SizedBox(height: 4),
                TextField(
                  controller: _reason,
                  maxLines: 3,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Reason (required — goes to the audit log)',
                    hintText: plan.action == OrgAction.block
                        ? 'Why is this organization being blocked?'
                        : 'Why is this warning being recorded?',
                    filled: true,
                    fillColor: p.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.smR,
                      borderSide: BorderSide(color: p.border),
                    ),
                  ),
                ),
              ],
              if (plan.requiresTypedName) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _typed,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Type the organization name to continue',
                    hintText: _name,
                    helperText: _typed.text.isNotEmpty && !_typedOk
                        ? 'Does not match "$_name"'
                        : null,
                    filled: true,
                    fillColor: p.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: AppRadii.smR,
                      borderSide: BorderSide(color: p.border),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _confirm : null,
          style: danger
              ? FilledButton.styleFrom(backgroundColor: kOrgDanger)
              : null,
          child: Text(plan.confirmLabel),
        ),
      ],
    );
  }
}

/// Record payment / change plan — an explicit sequence, then a review.
///
///   1. plan          2. term (the plan's own, or a negotiated one)
///   3. pricing basis (the plan's list price for that term — shown, not typed)
///   4. amount collected   5. the difference, named (discount / above list / comp)
///   6. reference (the once-only evidence key)   7. effective dates
///   8. review, then confirm.
///
/// The console computes NOTHING that is sent: it sends the plan, the term,
/// the reference and what was collected. The server reads the plan's list
/// price itself, stamps the pricing evidence on the receipt, extends the
/// expiry from the live record and returns all of it; the outcome banner
/// shows the server's figures, never this preview.
class GrantSubscriptionDialog extends StatefulWidget {
  const GrantSubscriptionDialog({
    super.key,
    required this.org,
    required this.ctrl,
  });

  final AdminModel org;
  final AdminController ctrl;

  @override
  State<GrantSubscriptionDialog> createState() =>
      _GrantSubscriptionDialogState();
}

class _GrantSubscriptionDialogState extends State<GrantSubscriptionDialog> {
  List<SubscriptionPlanModel> _plans = const [];
  String? _planId;

  /// A [SoldTerm.key] (`monthly` | `yearly` | `plan`) — one of the terms the
  /// plan SELLS — or `custom` for a negotiated number of months.
  String _termMode = 'plan';
  final _months = TextEditingController();
  final _reference = TextEditingController();
  final _amount = TextEditingController();
  bool _acknowledgeDifference = false;
  bool _review = false;
  String? _error;

  /// The organization's CURRENT plan is not among the published plans (it
  /// was hidden, archived or deleted): the dialog says so instead of quietly
  /// preselecting another plan and calling a renewal a "plan change".
  bool _currentPlanUnlisted = false;
  Worker? _catalogWorker;

  SubscriptionController? get _catalog =>
      Get.isRegistered<SubscriptionController>()
      ? Get.find<SubscriptionController>()
      : null;

  /// `subscription.planId` — the plan's identity. The display name is only a
  /// fallback for legacy records that never stored the id (ORG-16): a
  /// renamed plan used to preselect the FIRST plan and label a same-plan
  /// renewal a "PLAN CHANGE".
  String get _currentPlanId =>
      (widget.org.subscription?['planId'] ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    _loadPlans();
    final c = _catalog;
    if (_plans.isEmpty && c != null) {
      // Still loading (or failed) when the dialog opened: follow the catalog
      // so the dialog fills in instead of claiming nothing is published.
      _catalogWorker = everAll([c.plans, c.isLoading, c.loadError], (_) {
        if (!mounted || _plans.isNotEmpty) return;
        setState(_loadPlans);
      });
    }
  }

  void _loadPlans() {
    final c = _catalog;
    _plans = c == null
        ? const []
        : c.plans.where((pl) => pl.status == PlanStatus.published).toList();
    if (_plans.isEmpty) return;
    final id = _currentPlanId;
    SubscriptionPlanModel? current;
    if (id.isNotEmpty) {
      current = _plans.where((pl) => pl.docId == id).firstOrNull;
    } else {
      final name = (widget.org.planName ?? '').trim();
      if (name.isNotEmpty) {
        current = _plans.where((pl) => pl.planName == name).firstOrNull;
      }
    }
    _currentPlanUnlisted =
        current == null &&
        (id.isNotEmpty || (widget.org.planName ?? '').trim().isNotEmpty);
    _planId = (current ?? _plans.first).docId;
    final m = widget.org.subscription?['months'];
    _resetToPlan(preferMonths: current != null && m is num ? m.toInt() : null);
  }

  List<SoldTerm> get _terms {
    final pl = _plan!;
    return OrganizationLanguage.soldTerms(
      livePrice: pl.price,
      liveMonths: pl.durationMonths,
      authoredMonthly: pl.authoredMonthlyPrice,
      authoredYearly: pl.authoredYearlyPrice,
    );
  }

  /// Plain text for an amount field: exact paise, never rounded. A plan
  /// priced ₹1,499.50 used to prefill "1500" and then flag a spurious
  /// "₹0.50 ABOVE the list price" that the founder had to acknowledge.
  static String _plainAmount(double? v) {
    if (v == null || !v.isFinite || v <= 0) return '';
    final minor = (v * 100).round();
    return minor % 100 == 0
        ? '${minor ~/ 100}'
        : (minor / 100).toStringAsFixed(2);
  }

  void _resetToPlan({int? preferMonths}) {
    final terms = _terms;
    final pl = _plan!;
    final pick =
        terms.where((t) => t.months == preferMonths).firstOrNull ??
        terms.where((t) => t.months == pl.durationMonths).firstOrNull ??
        terms.first;
    _termMode = pick.key;
    _months.text = '${pick.months}';
    _amount.text = _plainAmount(pick.listPrice);
    _acknowledgeDifference = false;
  }

  @override
  void dispose() {
    _catalogWorker?.dispose();
    _months.dispose();
    _reference.dispose();
    _amount.dispose();
    super.dispose();
  }

  SubscriptionPlanModel? get _plan => _planId == null
      ? null
      : _plans.where((pl) => pl.docId == _planId).firstOrNull;

  SoldTerm? get _soldTerm => _termMode == 'custom'
      ? null
      : (_terms.where((t) => t.key == _termMode).firstOrNull ?? _terms.first);

  static final RegExp _monthsPattern = RegExp(r'^\d{1,3}$');

  /// Rupees with at most two decimals, digits only: rejects NaN, Infinity,
  /// "1e9", negatives, commas and sub-paise amounts the server would round
  /// away (the receipt would then contradict its own evidence).
  static final RegExp _amountPattern = RegExp(r'^\d{1,10}(\.\d{1,2})?$');

  int? get _monthsValue {
    if (_termMode != 'custom') return _soldTerm?.months;
    final t = _months.text.trim();
    return _monthsPattern.hasMatch(t) ? int.parse(t) : null;
  }

  double? get _amountValue {
    final t = _amount.text.trim();
    return _amountPattern.hasMatch(t) ? double.parse(t) : null;
  }

  /// The list price the SERVER will resolve for this grant (C4) — shown, and
  /// sent back as `expectedListPrice` so a re-price while the dialog was open
  /// is refused instead of silently stamping a discount nobody acknowledged.
  GrantList? get _list {
    final pl = _plan;
    final m = _monthsValue;
    if (pl == null || m == null) return null;
    return OrganizationLanguage.listForGrant(
      livePrice: pl.price,
      liveMonths: pl.durationMonths,
      authoredMonthly: pl.authoredMonthlyPrice,
      authoredYearly: pl.authoredYearlyPrice,
      months: m,
    );
  }

  /// The preview of the evidence the server will stamp. Display only.
  GrantPreview? get _preview {
    final l = _list;
    final m = _monthsValue;
    final a = _amountValue;
    if (l == null || m == null || a == null) return null;
    return OrganizationLanguage.grantPreview(
      listPrice: l.listPrice,
      listTermMonths: l.listTermMonths,
      months: m,
      amount: a,
      term: l.term,
    );
  }

  bool get _needsAcknowledgement {
    final pv = _preview;
    if (pv == null) return false;
    return pv.differsFromList || pv.basis == 'negotiated_term' || pv.isComped;
  }

  bool get _samePlan {
    final id = _currentPlanId;
    if (id.isNotEmpty) return _planId == id;
    return _plan?.planName == widget.org.planName;
  }

  static const String _amountHelp =
      'Amount must be in rupees with at most two decimals, e.g. 4999 or '
      '4999.50 (0 for a comped term).';

  String? _validate() {
    if (_plan == null) return 'Choose a plan.';
    final m = _monthsValue;
    if (m == null || m <= 0 || m > 120) {
      return 'Term must be a whole number of months, 1–120.';
    }
    if (_reference.text.trim().isEmpty) {
      return 'A payment reference is required — it is the evidence and the '
          'once-only key.';
    }
    if (_amountValue == null) return _amountHelp;
    if (_needsAcknowledgement && !_acknowledgeDifference) {
      return 'This amount or term differs from the plan\'s list. Tick the '
          'confirmation to record it deliberately.';
    }
    return null;
  }

  /// The date the term will END, by the backend's rule: extend from
  /// max(now, planExpiry) with day-of-month clamping. A preview; the outcome
  /// banner shows the server's own expiry.
  DateTime _newEnd(DateTime now) => OrganizationLanguage.addMonthsClamped(
    OrganizationLanguage.grantBase(widget.org, now: now),
    _monthsValue ?? 0,
  );

  Future<void> _confirm() async {
    final list = _list;
    Navigator.of(context).pop();
    await widget.ctrl.grantSubscription(
      org: widget.org,
      planId: _planId!,
      planName: _plan!.planName,
      months: _monthsValue!,
      reference: _reference.text.trim(),
      amount: _amountValue!,
      expectedListPrice: list?.listPrice,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = OrganizationLanguage.displayName(widget.org);
    final now = widget.ctrl.clock();
    final plan = OrganizationLanguage.planFor(
      OrgAction.grant,
      widget.org,
      now: now,
    );

    if (_plans.isEmpty) {
      final c = _catalog;
      final err = c?.loadError.value;
      final loading = c != null && c.isLoading.value;
      return AlertDialog(
        title: Text(
          err != null
              ? 'The plan catalog could not be loaded'
              : loading
              ? 'Loading the plan catalog…'
              : 'No plan can be recorded',
        ),
        content: Text(
          err != null
              ? '${err.message} Nothing was changed. Close this and try again '
                    'once the catalog loads.'
              : loading
              ? 'The published plans are still loading. Nothing was changed.'
              : 'There is no published Trainersarena plan to put the '
                    'organization on. Publish one under Commercial → Plans '
                    'first. Nothing was changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    InputDecoration deco(String label, {String? helper}) => InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      filled: true,
      fillColor: p.inputFill,
      border: OutlineInputBorder(
        borderRadius: AppRadii.smR,
        borderSide: BorderSide(color: p.border),
      ),
    );

    Widget step(String n, String title) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        '$n · $title',
        style: AppText.body(size: 11).copyWith(
          color: p.textMuted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );

    Widget basisLine() {
      final l = _list;
      final pv = _preview;
      final termWord = switch (l?.term) {
        'monthly' => ' (monthly term)',
        'yearly' => ' (yearly term)',
        'custom' => ' (the plan\'s own term)',
        _ => '',
      };
      final list = (l?.listPrice ?? 0) > 0
          ? '${OrganizationLanguage.rupees(l!.listPrice!)} for ${OrganizationLanguage.plural(l.listTermMonths!, 'month')}$termWord'
          : l == null
          ? 'enter a term to see it'
          : 'no list price on the plan';
      String verdict;
      Color tone = p.textSecondary;
      if (pv == null) {
        verdict = _amount.text.trim().isNotEmpty && _amountValue == null
            ? _amountHelp
            : 'Enter an amount to compare it with the list price.';
        if (_amountValue == null && _amount.text.trim().isNotEmpty) {
          tone = context.serena.error;
        }
      } else {
        switch (pv.basis) {
          case 'plan_term':
            if ((pv.discount ?? 0) > 0) {
              verdict =
                  'Discount of ${OrganizationLanguage.rupees(pv.discount!)} against the list price'
                  '${pv.isComped ? ' (comped term)' : ''}.';
              tone = context.serena.statusWarning;
            } else if ((pv.overpayment ?? 0) > 0) {
              verdict =
                  '${OrganizationLanguage.rupees(pv.overpayment!)} ABOVE the list price — check the reference before recording.';
              tone = context.serena.error;
            } else {
              verdict = 'Exactly the list price.';
              tone = context.serena.statusActive;
            }
          case 'negotiated_term':
            verdict =
                'A negotiated term: the list price is for ${OrganizationLanguage.plural(pv.listTermMonths ?? 0, 'month')}, '
                'so no discount is computed — the list basis is recorded on the receipt for comparison.';
            tone = context.serena.statusWarning;
          default:
            verdict =
                'The plan carries no list price; the receipt records the amount only.';
            tone = context.serena.statusWarning;
        }
      }
      return Container(
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
              'List price: $list',
              style: AppText.body(size: 12.5).copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              verdict,
              style: AppText.body(size: 12.5).copyWith(color: tone),
            ),
          ],
        ),
      );
    }

    Widget form() => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          plan.what,
          style: AppText.body(size: 13).copyWith(color: p.textSecondary),
        ),
        if (OrganizationLanguage.subscriptionOf(widget.org, now: now).state ==
            SubscriptionState.offBeforeEnd)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This organization is switched off although it is paid until '
              '${OrganizationLanguage.exact(widget.org.planExpiry)}. Recording '
              'a payment ADDS a new term on top of those days — record only a '
              'payment that was actually made, not to restore access.',
              style: AppText.body(
                size: 12.5,
              ).copyWith(color: context.serena.error),
            ),
          ),
        step('1', 'PLAN'),
        if (_currentPlanUnlisted)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'The organization\'s current plan'
              '${(widget.org.planName ?? '').trim().isEmpty ? '' : ' (${widget.org.planName!.trim()})'} '
              'is not published any more, so it cannot be renewed as it is — '
              'choose a published plan. That is a plan change.',
              style: AppText.body(
                size: 12.5,
              ).copyWith(color: context.serena.statusWarning),
            ),
          ),
        DropdownButtonFormField<String>(
          initialValue: _planId,
          isExpanded: true,
          decoration: deco('Trainersarena plan'),
          items: [
            for (final pl in _plans)
              DropdownMenuItem(
                value: pl.docId,
                child: Text(
                  '${pl.planName} · ${OrganizationLanguage.soldTerms(livePrice: pl.price, liveMonths: pl.durationMonths, authoredMonthly: pl.authoredMonthlyPrice, authoredYearly: pl.authoredYearlyPrice).map((t) => '${t.months} mo${t.listPrice == null ? '' : ' ${OrganizationLanguage.rupees(t.listPrice!)}'}').join(' / ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() {
            _planId = v ?? _planId;
            _resetToPlan();
          }),
        ),
        step('2', 'TERM'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Every term the plan SELLS — both terms of a dual-priced plan —
            // with the list price the server measures that term against.
            for (final t in _terms)
              ChoiceChip(
                label: Text(
                  '${t.label} · ${OrganizationLanguage.plural(t.months, 'month')}'
                  '${t.listPrice == null ? '' : ' · ${OrganizationLanguage.rupees(t.listPrice!)}'}',
                ),
                selected: _termMode == t.key,
                onSelected: (_) => setState(() {
                  _termMode = t.key;
                  _months.text = '${t.months}';
                  _amount.text = _plainAmount(t.listPrice);
                  _acknowledgeDifference = false;
                }),
              ),
            ChoiceChip(
              label: const Text('Negotiated term'),
              selected: _termMode == 'custom',
              onSelected: (_) => setState(() {
                _termMode = 'custom';
                _acknowledgeDifference = false;
              }),
            ),
          ],
        ),
        if (_termMode == 'custom') ...[
          const SizedBox(height: 8),
          TextField(
            controller: _months,
            keyboardType: TextInputType.number,
            // A different term is a different basis: the acknowledgement
            // given for the previous one does not carry over (ORG-14).
            onChanged: (_) => setState(() => _acknowledgeDifference = false),
            decoration: deco(
              'Term (months, 1–120)',
              helper:
                  'Only for a deal that is not the plan\'s own term. No discount is '
                  'computed for a negotiated term; the list basis is recorded.',
            ),
          ),
        ],
        step('3', 'PRICING BASIS'),
        basisLine(),
        step('4', 'AMOUNT COLLECTED'),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _acknowledgeDifference = false),
          decoration: deco(
            'Amount collected (₹)',
            helper:
                'What was actually received off-platform, in rupees (up to '
                'two decimals). 0 for a comped term.',
          ),
        ),
        step('5', 'EVIDENCE'),
        TextField(
          controller: _reference,
          onChanged: (_) => setState(() {}),
          decoration: deco(
            'Payment reference (Razorpay id / bank reference)',
            helper:
                'The evidence. Each reference can be recorded only once, on one organization.',
          ),
        ),
        if (_needsAcknowledgement) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acknowledgeDifference,
            onChanged: (v) =>
                setState(() => _acknowledgeDifference = v ?? false),
            title: Text(
              _preview?.isComped == true
                  ? 'I am recording a comped term (₹0) deliberately.'
                  : _preview?.basis == 'negotiated_term'
                  ? 'I am recording a negotiated term deliberately.'
                  : 'I am recording an amount that differs from the list price deliberately.',
              style: AppText.body(size: 12.5).copyWith(color: p.textPrimary),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: AppText.body(size: 12.5).copyWith(color: p.error),
          ),
        ],
      ],
    );

    Widget review() {
      final end = _newEnd(now);
      final base = OrganizationLanguage.grantBase(widget.org, now: now);
      final extends_ = base.isAfter(now);
      final pv = _preview!;
      final samePlan = _samePlan;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrgPlanSummary(
            what:
                'Records ${OrganizationLanguage.rupees(_amountValue!)} '
                '(reference ${_reference.text.trim()}) and puts $name on '
                '${_plan!.planName} for ${OrganizationLanguage.plural(_monthsValue!, 'month')}.',
            who: plan.who,
            consequences: [
              extends_
                  ? 'The term is added on top of the current end date '
                        '${OrganizationLanguage.exact(base)}: the plan will run '
                        'until about ${OrganizationLanguage.exact(end)} (the server sets the exact date).'
                  : 'The plan starts today and runs until about '
                        '${OrganizationLanguage.exact(end)} (the server sets the exact date).',
              switch (pv.basis) {
                'plan_term' =>
                  (pv.discount ?? 0) > 0
                      ? 'Pricing evidence on the receipt: list ${OrganizationLanguage.rupees(pv.listPrice!)}, '
                            'discount ${OrganizationLanguage.rupees(pv.discount!)}${pv.term == null ? '' : ' (${pv.term} term)'}.'
                      : (pv.overpayment ?? 0) > 0
                      ? 'Pricing evidence on the receipt: list ${OrganizationLanguage.rupees(pv.listPrice!)}, '
                            '${OrganizationLanguage.rupees(pv.overpayment!)} above list${pv.term == null ? '' : ' (${pv.term} term)'}.'
                      : 'Pricing evidence on the receipt: at list price${pv.term == null ? '' : ' (${pv.term} term)'}.',
                'negotiated_term' =>
                  'Pricing evidence on the receipt: negotiated term; list '
                      '${OrganizationLanguage.rupees(pv.listPrice!)} for '
                      '${OrganizationLanguage.plural(pv.listTermMonths!, 'month')}, no discount computed.',
                _ =>
                  'The plan carries no list price; the receipt records the amount only.',
              },
              samePlan
                  ? 'Limits stay the ${_plan!.planName} limits.'
                  : 'This is a PLAN CHANGE: limits switch to ${_plan!.planName} immediately '
                        '(${_plan!.limits.entries.map((e) => '${e.key.label} ${SubscriptionPlanModel.limitDisplay(e.value)}').join(', ')}); '
                        'any remaining days of the current term are kept as time on the new plan — nothing is prorated.',
              'A receipt is written with this evidence and the owner is sent a '
                  'notification (best effort). If the plan\'s list price changes '
                  'before you confirm, the server refuses and records nothing.',
              if (OrganizationLanguage.standingOf(widget.org) ==
                  OrgStanding.awaitingApproval)
                'The organization stays awaiting approval — recording payment does '
                    'not approve it.',
            ],
            reversibility: plan.reversibility,
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      title: Text(
        _review ? 'Review before recording — $name' : plan.title,
        style: AppText.title(size: 20).copyWith(color: p.textPrimary),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: _review ? review() : form()),
      ),
      actions: [
        if (_review)
          TextButton(
            onPressed: () => setState(() => _review = false),
            child: const Text('Back'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (!_review)
          FilledButton(
            onPressed: () {
              final err = _validate();
              setState(() {
                _error = err;
                if (err == null) _review = true;
              });
            },
            child: const Text('Review'),
          )
        else
          FilledButton(onPressed: _confirm, child: Text(plan.confirmLabel)),
      ],
    );
  }
}

/// Refund an online receipt.
class RefundReceiptDialog extends StatefulWidget {
  const RefundReceiptDialog({
    super.key,
    required this.org,
    required this.receipt,
    required this.ctrl,
  });

  final AdminModel org;
  final SubscriptionModel receipt;
  final AdminController ctrl;

  @override
  State<RefundReceiptDialog> createState() => _RefundReceiptDialogState();
}

class _RefundReceiptDialogState extends State<RefundReceiptDialog> {
  bool _full = true;
  bool _revoke = false;
  final _amount = TextEditingController();
  final _reason = TextEditingController();

  /// ONE refund intent per dialog opening (C2): the server answers a repeat
  /// of the same intent with the stored outcome and never reaches the
  /// gateway twice. A new opening is a new decision, against the maximum
  /// recomputed from the live receipt.
  late final String _intentId = ActionOutcomes.newRefundIntentId();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// The most a PARTIAL refund may ask (whole rupees, the callable's unit).
  int get _max => OrganizationLanguage.maxPartialRefundRupees(widget.receipt);

  /// Revoking access is only meaningful — and only accepted by the backend —
  /// when this receipt is the organization's CURRENT subscription payment.
  bool get _isCurrent =>
      (widget.org.subscription?['razorpayPaymentId'] ?? '').toString() ==
      widget.receipt.razorpayPaymentId;

  static final RegExp _wholeRupees = RegExp(r'^\d{1,9}$');

  /// A partial amount in whole rupees; null for a full refund (which sends
  /// no amount and returns the exact remainder, paise included).
  int? get _amountValue {
    if (_full) return null;
    final t = _amount.text.trim();
    return _wholeRupees.hasMatch(t) ? int.parse(t) : null;
  }

  bool get _amountOk {
    if (_full) return widget.receipt.netMinor > 0;
    final a = _amountValue;
    return a != null && a >= 1 && a <= _max;
  }

  bool get _valid => _amountOk && _reason.text.trim().isNotEmpty;

  Future<void> _confirm() async {
    Navigator.of(context).pop();
    await widget.ctrl.refund(
      org: widget.org,
      receipt: widget.receipt,
      amount: _full ? null : _amountValue,
      reason: _reason.text.trim(),
      revokeAccess: _revoke && _isCurrent,
      intentId: _intentId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = widget.receipt;
    final name = OrganizationLanguage.displayName(widget.org);
    final amt = _full ? r.netAmount : _amountValue?.toDouble();
    final pending = r.refunds.where((x) => x.isPending && x.counted).toList();
    return AlertDialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      title: Text(
        'Refund a payment — $name',
        style: AppText.title(size: 20).copyWith(color: p.textPrimary),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrgPlanSummary(
                what:
                    'Returns money to the organization through the payment '
                    'gateway (Razorpay) and marks the receipt as refunded.',
                who:
                    '$name — receipt of ${OrganizationLanguage.rupees(r.amountPaid)} '
                    'for ${r.planName.isEmpty ? 'an unnamed plan' : r.planName}'
                    '${r.refundMinor > 0 ? ' (${OrganizationLanguage.rupees(r.refundAmount)} already refunded, ${OrganizationLanguage.rupees(r.netAmount)} left)' : ''}',
                consequences: [
                  '${amt == null || !_amountOk ? 'The chosen amount' : OrganizationLanguage.rupees(amt)} '
                      'leaves the platform\'s account; the gateway pays it back to the '
                      'original payment method within its own timeline.',
                  if (pending.isNotEmpty)
                    'A refund of ${OrganizationLanguage.rupeesMinor(pending.fold<int>(0, (s, x) => s + x.amountMinor))} '
                        'is still pending at the gateway and already counts '
                        'against this receipt.',
                  _revoke && _isCurrent
                      ? 'The subscription is ENDED now: the organization stops operating '
                            'and its trainers are paused.'
                      : 'The subscription is not changed — the organization keeps '
                            'operating until its end date.',
                  'The refund is written to the audit log with your name and reason.',
                ],
                reversibility:
                    'Cannot be undone. Money sent back cannot be recalled '
                    'from here.',
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(
                      'Full refund · ${OrganizationLanguage.rupees(r.netAmount)}',
                    ),
                    selected: _full,
                    onSelected: (_) => setState(() => _full = true),
                  ),
                  ChoiceChip(
                    label: const Text('Part of it'),
                    selected: !_full,
                    onSelected: (_) => setState(() => _full = false),
                  ),
                ],
              ),
              if (r.refunds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Refunds already on this receipt',
                  style: AppText.body(
                    size: 11,
                  ).copyWith(color: p.textMuted, fontWeight: FontWeight.w700),
                ),
                for (final x in r.refunds)
                  Text(
                    OrganizationLanguage.refundLine(x),
                    style: AppText.body(
                      size: 12,
                    ).copyWith(color: p.textSecondary),
                  ),
              ],
              if (!_full) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Amount (₹, whole rupees, 1–$_max)',
                    filled: true,
                    fillColor: p.inputFill,
                    border: OutlineInputBorder(borderRadius: AppRadii.smR),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _reason,
                maxLines: 2,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Reason (required — goes to the audit log)',
                  filled: true,
                  fillColor: p.inputFill,
                  border: OutlineInputBorder(borderRadius: AppRadii.smR),
                ),
              ),
              if (_isCurrent)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _revoke,
                  onChanged: (v) => setState(() => _revoke = v ?? false),
                  title: const Text('Also end the subscription now'),
                  subtitle: const Text(
                    'This receipt is the organization\'s current subscription payment.',
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'This is not the current subscription payment, so the '
                    'subscription cannot be ended from this refund.',
                    style: AppText.body(size: 12).copyWith(color: p.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _confirm : null,
          style: FilledButton.styleFrom(backgroundColor: kOrgDanger),
          child: const Text('Refund'),
        ),
      ],
    );
  }
}
