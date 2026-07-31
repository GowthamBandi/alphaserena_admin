// lib/widgets/subscription_plan_dialog.dart
//
// Commercial Plan Designer — two-pane enterprise editor. LEFT: the form
// sections (Identity, Pricing, Business Capacity, Premium Capabilities,
// Highlights, Visibility & status). RIGHT: a live buyer preview
// (PlanLivePreview) that re-renders on every keystroke and toggle, so the
// founder always sees exactly what a TrainerHQ buyer will see. Below ~940px
// the preview becomes the last section of a single column. Validation lives in
// PlanValidation via the controller; this widget is presentation + binding.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/core/validation/capability_dependencies.dart';
import 'package:alphaserena_admin_portel/core/widgets/app_text_field.dart';
import 'package:alphaserena_admin_portel/core/widgets/primary_button.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:alphaserena_admin_portel/widgets/app_snackbar.dart';
import 'package:alphaserena_admin_portel/widgets/plan_live_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/subscription_controller.dart';

class SubscriptionPlanDialog extends StatefulWidget {
  final bool isEdit;
  const SubscriptionPlanDialog({super.key, this.isEdit = false});

  @override
  State<SubscriptionPlanDialog> createState() => _SubscriptionPlanDialogState();
}

class _SubscriptionPlanDialogState extends State<SubscriptionPlanDialog> {
  final SubscriptionController ctrl = Get.find<SubscriptionController>();
  final TextEditingController _featureCtrl = TextEditingController();

  /// Two-pane threshold — below this the preview folds into the column.
  static const double _twoPaneMin = 940;

  /// Money input. NOT digitsOnly: a legacy plan priced at 999.50 loads that
  /// text into the field, and a digits-only formatter rewrites the whole value
  /// on the next keystroke — silently turning ₹999.50 into ₹99950. Digits plus
  /// a single decimal point, capped so the value always parses.
  static final List<TextInputFormatter> _moneyInput = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
    TextInputFormatter.withFunction((old, next) =>
        '.'.allMatches(next.text).length > 1 ? old : next),
    LengthLimitingTextInputFormatter(10),
  ];

  /// Capacity input. Length-capped because int.tryParse returns null past the
  /// 64-bit range, which would read back as a 0 the founder never typed.
  static final List<TextInputFormatter> _countInput = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(9),
  ];

  @override
  void initState() {
    super.initState();
    if (!widget.isEdit) ctrl.clearForm();
    // Re-evaluate capability dependencies whenever a capacity value changes so
    // impossible options auto-disable live (the RxMap toggle is watched by Obx;
    // the text fields are not, so we listen to them explicitly).
    for (final c in ctrl.limitCtrls.values) {
      c.addListener(_onLimitChanged);
    }
    // The live preview mirrors every text field — rebuild on any keystroke.
    for (final c in _previewTextCtrls) {
      c.addListener(_onFormTextChanged);
    }
  }

  List<TextEditingController> get _previewTextCtrls => [
        ctrl.planNameCtrl,
        ctrl.badgeCtrl,
        ctrl.monthlyPriceCtrl,
        ctrl.yearlyPriceCtrl,
      ];

  void _onLimitChanged() {
    ctrl.reconcileCapabilities();
    if (mounted) setState(() {});
  }

  void _onFormTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in ctrl.limitCtrls.values) {
      c.removeListener(_onLimitChanged);
    }
    for (final c in _previewTextCtrls) {
      c.removeListener(_onFormTextChanged);
    }
    _featureCtrl.dispose();
    super.dispose();
  }

  void _addFeature() {
    final t = _featureCtrl.text.trim();
    if (t.isEmpty) return;
    if (!ctrl.addPoint(t)) {
      // Only a duplicate can reach here (blank returned above) — say so
      // instead of appearing to accept a line the card would never show twice.
      AppSnackbar.show(
          title: "Already added", message: "That highlight is already listed.");
      return;
    }
    _featureCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 880),
        child: Container(
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: AppRadii.lgR,
            border: Border.all(color: p.border),
          ),
          child: LayoutBuilder(builder: (context, box) {
            final twoPane = box.maxWidth >= _twoPaneMin;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _header(context),
                Flexible(
                  child: twoPane ? _twoPaneBody(context) : _singleBody(context),
                ),
                _footer(context),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ── Layout bodies ────────────────────────────────────────────────────────
  Widget _twoPaneBody(BuildContext context) {
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _formSections(context),
          ),
        ),
        Container(
          width: 360,
          decoration: BoxDecoration(
            color: p.surfaceAlt.withValues(alpha: 0.4),
            border: Border(left: BorderSide(color: p.border)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.visibility_outlined, size: 16, color: p.accent),
                  const SizedBox(width: 8),
                  Text("Live preview",
                      style: AppText.cardTitle(size: 14)
                          .copyWith(color: p.textPrimary)),
                ]),
                const SizedBox(height: 12),
                _livePreview(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _singleBody(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _formSections(context),
          _section(context, Icons.visibility_outlined, "Buyer preview",
              "What gyms see on the subscription screen", _livePreview()),
        ],
      ),
    );
  }

  Widget _formSections(BuildContext context) {
    return Column(
      children: [
        _section(context, Icons.badge_outlined, "Identity",
            "Name, positioning and sort", _identity(context)),
        _section(context, Icons.currency_rupee, "Pricing",
            "Owner-set monthly & yearly — savings are computed",
            _pricing(context)),
        _section(context, Icons.speed_outlined, "Business Capacity",
            "How much this plan allows — toggle Unlimited to lift a cap",
            _limits(context)),
        _section(context, Icons.workspace_premium_outlined,
            "Premium Capabilities",
            "What this plan unlocks in the app — options auto-disable when the capacity can't support them",
            _capabilities(context)),
        _section(context, Icons.stars_outlined, "Highlights",
            "The bullet list buyers read on the plan card",
            _features(context)),
        _section(context, Icons.tune_outlined, "Visibility & status",
            "Where and whether this plan appears", _visibility(context)),
      ],
    );
  }

  // ── Live preview (rebuilds on Rx changes via Obx + text via setState) ────
  Widget _livePreview() {
    return Obx(() {
      return PlanLivePreview(
        planName: ctrl.planNameCtrl.text,
        badge: ctrl.badgeCtrl.text,
        status: ctrl.planStatus.value,
        featured: ctrl.featured.value,
        termMonths: ctrl.termMonths.value,
        monthlyPrice:
            double.tryParse(ctrl.monthlyPriceCtrl.text.trim()) ?? 0,
        yearlyPrice: double.tryParse(ctrl.yearlyPriceCtrl.text.trim()) ?? 0,
        limits: ctrl.currentLimits(),
        capabilities: Map<String, bool>.from(ctrl.capabilities),
        customPoints: ctrl.points.toList(),
        // Published peers' per-month prices, so BEST VALUE / savings framing
        // matches what TrainerHQ computes across the visible catalog.
        peerPerMonth: ctrl.publishedPeerPerMonth(),
      );
    });
  }

  // ── Header ─────────────────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined, color: p.accent, size: 22),
          const SizedBox(width: 10),
          Text(
            widget.isEdit ? "Edit plan" : "Create plan",
            style: AppText.title(size: 19).copyWith(color: p.textPrimary),
          ),
          const Spacer(),
          IconButton(
            onPressed: Get.back,
            icon: Icon(Icons.close, color: p.textMuted),
          ),
        ],
      ),
    );
  }

  // ── Identity ───────────────────────────────────────────────────────────
  Widget _identity(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: ctrl.planNameCtrl,
          label: "Plan name",
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: ctrl.descriptionCtrl,
          label: "Description (optional)",
          icon: Icons.notes_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: ctrl.badgeCtrl,
                label: "Badge (console-only, optional)",
                icon: Icons.local_offer_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                controller: ctrl.sortOrderCtrl,
                label: "Sort order",
                icon: Icons.sort,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Pricing ────────────────────────────────────────────────────────────
  Widget _pricing(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Billing term",
            style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        const SizedBox(height: 8),
        // Wrap, not Row — the same pattern the Status chips below use. As a Row
        // these chips could not break onto a second line, so a narrow dialog (or
        // a larger font / longer translation of "Monthly"/"Yearly") overflowed
        // the section instead of reflowing.
        Obx(() => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: BillingPeriod.values.map((bp) {
                final sel = ctrl.selectedPeriod == bp;
                return InkWell(
                  onTap: () => ctrl.termMonths.value = bp.months,
                  borderRadius: AppRadii.smR,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          sel ? p.accent.withValues(alpha: 0.12) : p.surface,
                      borderRadius: AppRadii.smR,
                      border: Border.all(color: sel ? p.accent : p.border),
                    ),
                    child: Text(
                      bp.label,
                      style: AppText.label(size: 13).copyWith(
                          color: sel ? p.accent : p.textSecondary),
                    ),
                  ),
                );
              }).toList(),
            )),
        const SizedBox(height: 8),
        Obx(() {
          final term = ctrl.termMonths.value;
          if (term != 1 && term != 12) {
            return Text(
              "This plan uses a $term-month term. Choose Monthly or Yearly to convert it, or leave it as-is.",
              style:
                  AppText.body(size: 12).copyWith(color: const Color(0xFFB06A00)),
            );
          }
          return Text(
            ctrl.selectedPeriod == BillingPeriod.yearly
                ? "This plan's default term is yearly (12 months of access)."
                : "This plan's default term is monthly (1 month of access).",
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          );
        }),
        const SizedBox(height: 14),
        // The dual-price contract, stated plainly. BOTH prices below are live:
        // the buyer picks a term in the app and the server charges the matching
        // one from this single plan. Previously only the default term's price
        // was ever charged and the other field was inert data — which is why
        // the Monthly/Yearly control never appeared to buyers at all.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.07),
            borderRadius: AppRadii.smR,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.swap_horiz, size: 16, color: p.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Buyers choose their term in the app and are charged the "
                  "matching price below. Leave a price blank to not offer "
                  "that term at all.",
                  style:
                      AppText.body(size: 12).copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                controller: ctrl.monthlyPriceCtrl,
                label: "Monthly price (₹)",
                icon: Icons.currency_rupee,
                keyboardType: TextInputType.number,
                inputFormatters: _moneyInput,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                controller: ctrl.yearlyPriceCtrl,
                label: "Yearly price (₹)",
                icon: Icons.currency_rupee,
                keyboardType: TextInputType.number,
                inputFormatters: _moneyInput,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Computed yearly savings — recomputes as either price changes.
        _SavingsHint(ctrl: ctrl),
      ],
    );
  }

  // ── Business Capacity ────────────────────────────────────────────────────
  static const Map<PlanResource, String> _limitHints = {
    PlanResource.teamMembers: "Trainer seats — enforced instantly by the server",
    PlanResource.activeClients: "Active clients across the whole gym",
    PlanResource.workoutPlans: "Workout programs the team can create",
    PlanResource.dietPlans: "Diet programs the team can create",
    PlanResource.exerciseLibrary: "Exercises the gym's library can hold",
  };

  Widget _limits(BuildContext context) {
    return Column(
      children: [
        for (final r in PlanResource.values) ...[
          _LimitRow(ctrl: ctrl, resource: r, hint: _limitHints[r] ?? ''),
          if (r != PlanResource.values.last) const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        _note(context,
            "Admin seats are fixed at 1. Team member seats are enforced live; the other capacities are enforced when the team creates items in the app."),
      ],
    );
  }

  // ── Premium Capabilities (live dependency gating) ────────────────────────
  Widget _capabilities(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      // EVERY observable this section renders must be READ HERE, inside the
      // Obx builder — that synchronous run is the only window in which GetX
      // records a dependency. A read that happens later (inside a nested
      // Builder/LayoutBuilder callback, or short-circuited away by `&&`)
      // registers nothing, and the switch then paints a stale value until some
      // unrelated rebuild happens to repaint the subtree.
      final limits = ctrl.currentLimits(); // subscribes: limitUnlimited
      final caps = Map<String, bool>.from(ctrl.capabilities); // subscribes: capabilities
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in PlanCapabilities.catalog)
            () {
              final blocker =
                  CapabilityDependencies.blockerFor(entry.key, limits);
              final enabled = blocker == null;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: p.surfaceAlt.withValues(alpha: 0.5),
                  borderRadius: AppRadii.mdR,
                  border: Border.all(color: p.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.value,
                              style: AppText.body(size: 14).copyWith(
                                  color: enabled
                                      ? p.textPrimary
                                      : p.textMuted)),
                          const SizedBox(height: 3),
                          Text(
                            PlanCapabilities.descriptions[entry.key] ?? '',
                            style: AppText.body(size: 12)
                                .copyWith(color: p.textMuted),
                          ),
                          if (blocker != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(blocker.explanation,
                                  style: AppText.body(size: 12).copyWith(
                                      color: const Color(0xFFB06A00))),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Switch.adaptive(
                      value: enabled && (caps[entry.key] ?? false),
                      onChanged: enabled
                          ? (v) => ctrl.capabilities[entry.key] = v
                          : null,
                    ),
                  ],
                ),
              );
            }(),
          const SizedBox(height: 2),
          Text(
            "Only capabilities the platform actually enforces can be sold. More arrive as the app ships their gates.",
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
        ],
      );
    });
  }

  // ── Highlights (custom only — the founder hand-writes every line) ────────
  Widget _features(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Custom highlights — founder's unique selling points.
        Text("Custom highlights",
            style:
                AppText.label(size: 13).copyWith(color: p.textPrimary)),
        const SizedBox(height: 2),
        Text(
            "Every bullet on the buyer's card, exactly as typed. Capacity is already shown by the chips, so it needs no bullet.",
            style: AppText.body(size: 12).copyWith(color: p.textMuted)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _featureCtrl,
                label: "Add a highlight",
                icon: Icons.add_task,
                onSubmitted: (_) => _addFeature(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _addFeature,
                style: ElevatedButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadii.mdR),
                ),
                child: const Text("Add"),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Obx(() {
          if (ctrl.points.isEmpty) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Text("No custom highlights added yet",
                  style:
                      AppText.body(size: 13).copyWith(color: p.textMuted)),
            );
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(ctrl.points.length, (i) {
              final text = ctrl.points[i];
              return Container(
                padding: const EdgeInsets.only(
                    left: 12, right: 6, top: 6, bottom: 6),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(size: 13)
                              .copyWith(color: p.accent)),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => ctrl.removePoint(i),
                      borderRadius: BorderRadius.circular(999),
                      child: Icon(Icons.close, size: 16, color: p.accent),
                    ),
                  ],
                ),
              );
            }),
          );
        }),
      ],
    );
  }

  // ── Visibility & status ──────────────────────────────────────────────────
  Widget _visibility(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Status",
            style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: PlanStatus.values.map((s) {
                final sel = ctrl.planStatus.value == s;
                return InkWell(
                  onTap: () {
                    ctrl.planStatus.value = s;
                    if (s != PlanStatus.published) ctrl.featured.value = false;
                  },
                  borderRadius: AppRadii.smR,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color:
                          sel ? p.accent.withValues(alpha: 0.12) : p.surface,
                      borderRadius: AppRadii.smR,
                      border: Border.all(color: sel ? p.accent : p.border),
                    ),
                    child: Text(s.label,
                        style: AppText.label(size: 13).copyWith(
                            color: sel ? p.accent : p.textSecondary)),
                  ),
                );
              }).toList(),
            )),
        const SizedBox(height: 6),
        Obx(() => Text(
              switch (ctrl.planStatus.value) {
                PlanStatus.published => 'Live and purchasable by gyms.',
                PlanStatus.hidden =>
                  'Retained for existing subscribers, hidden from new ones.',
                PlanStatus.archived =>
                  'Retired — not sold. Can be permanently deleted.',
              },
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            )),
        const SizedBox(height: 8),
        Obx(() {
          final canFeature = ctrl.planStatus.value == PlanStatus.published;
          return SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: canFeature && ctrl.featured.value,
            onChanged:
                canFeature ? (v) => ctrl.featured.value = v : null,
            title: Text("Featured",
                style: AppText.body(size: 14).copyWith(
                    color: canFeature ? p.textPrimary : p.textMuted)),
            subtitle: Text(
                canFeature
                    ? "Highlighted as the recommended plan"
                    : "Only a published plan can be featured",
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          );
        }),
      ],
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────
  Widget _footer(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Obx(() => PrimaryButton(
            label: widget.isEdit ? "Update plan" : "Create plan",
            icon: Icons.check,
            isLoading: ctrl.isSaving.value,
            onPressed: ctrl.savePlan,
          )),
    );
  }

  // ── Building blocks ──────────────────────────────────────────────────────
  Widget _note(BuildContext context, String text) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFB06A00).withValues(alpha: 0.10),
        borderRadius: AppRadii.smR,
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFB06A00), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style:
                    AppText.body(size: 12).copyWith(color: p.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, IconData icon, String title,
      String subtitle, Widget child) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: p.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary)),
            ),
          ]),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text(subtitle,
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── A single limit row: label + hint, number field, Unlimited toggle ────────
class _LimitRow extends StatelessWidget {
  final SubscriptionController ctrl;
  final PlanResource resource;
  final String hint;
  const _LimitRow(
      {required this.ctrl, required this.resource, required this.hint});

  /// The capacity field is sized, not flexed. Under the old `flex: 2` share it
  /// collapsed to ~23px on a 375px viewport, so a saved "50" rendered as "5"
  /// and "100" as "1" — the founder could not read the capacity they had set,
  /// and the row overflowed as well.
  static const double _fieldWidth = 96;

  /// Below this the label cannot sit beside the field and the Unlimited toggle
  /// without squeezing one of them out; the label moves to its own line.
  static const double _stackBelow = 420;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final unlimited = ctrl.limitUnlimited[resource] ?? false;

      final labelBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(resource.label,
              style: AppText.body(size: 14).copyWith(color: p.textPrimary)),
          if (hint.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(hint,
                style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          ],
        ],
      );

      final field = Opacity(
        opacity: unlimited ? 0.4 : 1,
        child: IgnorePointer(
          ignoring: unlimited,
          child: SizedBox(
            height: 46,
            width: _fieldWidth,
            child: TextField(
              controller: ctrl.limitCtrls[resource],
              keyboardType: TextInputType.number,
              inputFormatters: _SubscriptionPlanDialogState._countInput,
              style: TextStyle(color: p.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: unlimited ? "∞" : "0",
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ),
      );

      final unlimitedToggle = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible so a wider font or a longer translation of "Unlimited"
          // ellipsizes instead of overflowing the row.
          Flexible(
            child: Text("Unlimited",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          ),
          Switch.adaptive(
            value: unlimited,
            onChanged: (v) {
              ctrl.limitUnlimited[resource] = v;
              // Toggling Unlimited off must never present a value that
              // validation rejects — a leftover '0' becomes an empty field
              // the founder has to fill deliberately.
              if (!v && ctrl.limitCtrls[resource]!.text.trim() == '0') {
                ctrl.limitCtrls[resource]!.clear();
              }
              // Lifting/adding a cap can make a capability (im)possible —
              // keep enabled capabilities honest with the new capacity.
              ctrl.reconcileCapabilities();
            },
          ),
        ],
      );

      return LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < _stackBelow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelBlock,
                const SizedBox(height: 8),
                Row(
                  children: [
                    field,
                    const SizedBox(width: 8),
                    // Bounded so the toggle's label can ellipsize rather than
                    // push the row past the dialog's edge.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: unlimitedToggle,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: labelBlock),
              const SizedBox(width: 8),
              field,
              const SizedBox(width: 8),
              unlimitedToggle,
            ],
          );
        },
      );
    });
  }
}

// ── Live "you save N%" hint driven by the two price fields ──────────────────
class _SavingsHint extends StatefulWidget {
  final SubscriptionController ctrl;
  const _SavingsHint({required this.ctrl});

  @override
  State<_SavingsHint> createState() => _SavingsHintState();
}

class _SavingsHintState extends State<_SavingsHint> {
  @override
  void initState() {
    super.initState();
    widget.ctrl.monthlyPriceCtrl.addListener(_onChange);
    widget.ctrl.yearlyPriceCtrl.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.ctrl.monthlyPriceCtrl.removeListener(_onChange);
    widget.ctrl.yearlyPriceCtrl.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final monthly = double.tryParse(widget.ctrl.monthlyPriceCtrl.text.trim()) ?? 0;
    final yearly = double.tryParse(widget.ctrl.yearlyPriceCtrl.text.trim()) ?? 0;
    final annual = monthly * 12;
    if (monthly <= 0 || yearly <= 0) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text("Enter both prices to see the yearly saving.",
            style: AppText.body(size: 12).copyWith(color: p.textMuted)),
      );
    }
    if (yearly >= annual) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text("Yearly is not cheaper than paying monthly — no saving shown.",
            style: AppText.body(size: 12).copyWith(color: const Color(0xFFB06A00))),
      );
    }
    final pct = ((1 - (yearly / annual)) * 100).round();
    final save = (annual - yearly).round();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A7F5A).withValues(alpha: 0.12),
        borderRadius: AppRadii.smR,
      ),
      child: Text("Yearly saves ₹$save ($pct%) vs 12 months at the monthly rate.",
          style: AppText.label(size: 13)
              .copyWith(color: const Color(0xFF1A7F5A))),
    );
  }
}
