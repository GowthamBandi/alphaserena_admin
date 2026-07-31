// lib/widgets/trainer_preview_dialog.dart
//
// "See it as a trainer" — the Super Admin previews what a gym owner sees in
// TrainerHQ's plan selector, without logging in. The per-month framing, BEST
// VALUE badge and savings % follow TrainerHQ's `_planSelector` math
// (price / months baseline; cheapest per-month wins; ties show no winner;
// savings shown only on multi-month plans). The plan's `badge` field is NOT
// rendered — TrainerHQ never shows it, and this dialog's whole point is
// buyer truth. One known PRESENTATION difference remains deliberate:
// styling/layout follow the console theme, not TrainerHQ's.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

final _inr = NumberFormat.decimalPattern('en_IN');

class TrainerPreviewDialog extends StatefulWidget {
  /// All published plans, in display order (what TrainerHQ streams).
  final List<SubscriptionPlanModel> plans;
  const TrainerPreviewDialog({super.key, required this.plans});

  @override
  State<TrainerPreviewDialog> createState() => _TrainerPreviewDialogState();
}

enum _Filter { all, monthly, yearly }

class _TrainerPreviewDialogState extends State<TrainerPreviewDialog> {
  _Filter _filter = _Filter.all;

  // ── TrainerHQ math (mirrored) ──────────────────────────────────────────
  double _perMonth(SubscriptionPlanModel pl) =>
      pl.durationMonths > 0 ? pl.price / pl.durationMonths : pl.price;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = widget.plans;

    // Baseline + best-value computed over ALL published plans (exactly what the
    // trainer sees), so filtering the view never distorts the numbers.
    double baseline = 0;
    String? bestValueId;
    if (all.length > 1) {
      double best = double.infinity;
      for (final pl in all) {
        final pm = _perMonth(pl);
        if (pm > baseline) baseline = pm;
        if (pm < best) {
          best = pm;
          bestValueId = pl.id;
        }
      }
      final distinct = all.where((pl) => _perMonth(pl) > best).length;
      if (distinct == 0) bestValueId = null; // a tie has no clear winner
    }

    final shown = all.where((pl) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.monthly:
          return pl.billingPeriod == BillingPeriod.monthly;
        case _Filter.yearly:
          return pl.billingPeriod == BillingPeriod.yearly;
      }
    }).toList();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 820),
        child: Container(
          decoration: BoxDecoration(
            color: p.background,
            borderRadius: AppRadii.lgR,
            border: Border.all(color: p.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(context),
              _filterBar(context),
              Flexible(
                child: all.isEmpty
                    ? _empty(context)
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        child: Column(
                          children: [
                            for (final pl in shown) ...[
                              _previewCard(context, pl,
                                  bestValue: pl.id == bestValueId,
                                  savingsPct: baseline > 0
                                      ? ((1 - _perMonth(pl) / baseline) * 100)
                                          .round()
                                      : 0),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
          Icon(Icons.visibility_outlined, color: p.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text("Trainer preview",
                style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
          ),
          IconButton(
              onPressed: Get.back,
              icon: Icon(Icons.close, color: p.textMuted)),
        ],
      ),
    );
  }

  Widget _filterBar(BuildContext context) {
    final p = context.palette;
    Widget chip(_Filter f, String label) {
      final sel = _filter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: () => setState(() => _filter = f),
          borderRadius: AppRadii.smR,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? p.accent.withValues(alpha: 0.12) : p.surface,
              borderRadius: AppRadii.smR,
              border: Border.all(color: sel ? p.accent : p.border),
            ),
            child: Text(label,
                style: AppText.label(size: 12)
                    .copyWith(color: sel ? p.accent : p.textSecondary)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(children: [
        chip(_Filter.all, "All"),
        chip(_Filter.monthly, "Monthly"),
        chip(_Filter.yearly, "Yearly"),
      ]),
    );
  }

  Widget _previewCard(BuildContext context, SubscriptionPlanModel pl,
      {required bool bestValue, required int savingsPct}) {
    final p = context.palette;
    final perMonth = _perMonth(pl);
    final showPerMonth = pl.durationMonths > 1;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.lgR,
        border: Border.all(
            color: bestValue ? p.accent : p.border,
            width: bestValue ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(pl.planName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppText.title(size: 18).copyWith(color: p.textPrimary)),
              ),
              if (bestValue) _pill(context, "BEST VALUE", p.accent),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              pl.billingPeriod == BillingPeriod.yearly
                  ? "Billed yearly"
                  : "Billed monthly",
              style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text("₹${_inr.format(pl.price.round())}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(size: 28)
                        .copyWith(color: p.textPrimary)),
              ),
              const SizedBox(width: 6),
              if (showPerMonth)
                Text("₹${_inr.format(perMonth.round())}/mo",
                    style:
                        AppText.body(size: 12).copyWith(color: p.textMuted)),
            ],
          ),
          // TrainerHQ shows the savings line only on multi-month plans.
          if (savingsPct > 0 && pl.durationMonths > 1) ...[
            const SizedBox(height: 4),
            Text("Save $savingsPct% per month vs the costliest plan",
                style: AppText.label(size: 12)
                    .copyWith(color: const Color(0xFF1A7F5A))),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _cap(context, "Team",
                SubscriptionPlanModel.limitDisplay(pl.limitOf(PlanResource.teamMembers))),
            _cap(context, "Clients",
                SubscriptionPlanModel.limitDisplay(pl.limitOf(PlanResource.activeClients))),
            _cap(context, "Workout Programs",
                SubscriptionPlanModel.limitDisplay(pl.limitOf(PlanResource.workoutPlans))),
            _cap(context, "Diet Programs",
                SubscriptionPlanModel.limitDisplay(pl.limitOf(PlanResource.dietPlans))),
            _cap(context, "Exercises",
                SubscriptionPlanModel.limitDisplay(
                    pl.limitOf(PlanResource.exerciseLibrary))),
          ]),
          if (pl.points.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final pt in pl.points)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.check_circle, size: 15, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(pt,
                          style: AppText.body(size: 13)
                              .copyWith(color: p.textSecondary))),
                ]),
              ),
          ],
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: AppText.label(size: 10).copyWith(color: color)),
      );

  Widget _cap(BuildContext context, String label, String value) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration:
          BoxDecoration(color: p.surfaceAlt, borderRadius: AppRadii.smR),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text("$label ",
            style: AppText.body(size: 12).copyWith(color: p.textMuted)),
        Text(value,
            style: AppText.label(size: 12).copyWith(color: p.textPrimary)),
      ]),
    );
  }

  Widget _empty(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Text("No published plans to preview.",
            style: AppText.body(size: 13).copyWith(color: p.textMuted)),
      ),
    );
  }
}
