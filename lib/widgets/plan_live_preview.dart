// lib/widgets/plan_live_preview.dart
//
// Live buyer preview — the founder's confidence screen. Renders what a
// TrainerHQ buyer will see for the CURRENT designer form state, mirroring the
// app's plan-card presentation rules exactly:
//   • price hero with "₹X/mo" beside it on multi-month terms;
//   • BEST VALUE and savings are CROSS-PLAN arithmetic over the published
//     catalog (cheapest per-month wins; baseline is the costliest per-month;
//     a tie has no winner) — never a per-plan invented claim;
//   • the plan's `points` list and the five limit chips, in TrainerHQ's
//     wording (Trainers / Clients / Workout plans / Diet plans / Exercises);
//   • NO badge pill and NO featured styling — TrainerHQ does not render the
//     `badge`/`featured` fields, so the buyer card never shows them; a note
//     below the card says so when either is set.
// Pure presentation: it takes plain values so it is directly widget-testable
// without Firebase or the controller.

import 'package:alphaserena_admin_portel/core/services/plan_highlights.dart';
import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _inr = NumberFormat.decimalPattern('en_IN');

class PlanLivePreview extends StatelessWidget {
  final String planName;

  /// Console-only label — TrainerHQ never renders it. Non-empty values only
  /// trigger the "console-only" note under the card.
  final String badge;
  final PlanStatus status;

  /// Console-only flag — TrainerHQ never renders it (see [badge]).
  final bool featured;

  /// The plan's term in months (1 = monthly, 12 = yearly; legacy terms kept).
  final int termMonths;
  final double monthlyPrice;
  final double yearlyPrice;

  /// Decoded limits (-1 = unlimited). A missing entry reads as 0.
  final Map<PlanResource, int> limits;

  /// Part of the plan configuration, but the buyer card renders nothing for it
  /// — capabilities gate features inside TrainerHQ, they are not card copy.
  final Map<String, bool> capabilities;

  /// The founder's hand-written highlight lines — the ONLY source of the
  /// card's bullet list. Nothing is generated from limits or capabilities.
  final List<String> customPoints;

  /// Per-month prices of the OTHER published plans in the catalog, so BEST
  /// VALUE and savings can be computed exactly the way TrainerHQ computes
  /// them (across the whole visible catalog). Empty = this is the only plan,
  /// so no value framing is shown — just like the app.
  final List<double> peerPerMonth;

  const PlanLivePreview({
    super.key,
    required this.planName,
    required this.badge,
    required this.status,
    required this.featured,
    required this.termMonths,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.limits,
    required this.capabilities,
    required this.customPoints,
    this.peerPerMonth = const [],
  });

  // ── TrainerHQ math (mirrored from the app's _planSelector) ────────────────
  double get _price => termMonths >= 12 ? yearlyPrice : monthlyPrice;
  double get _perMonth => termMonths > 0 ? _price / termMonths : _price;

  /// (bestValue, savingsPct) computed over peers + this plan, mirroring
  /// TrainerHQ: baseline = costliest per-month, cheapest per-month wears BEST
  /// VALUE, an all-equal tie has no winner, savings shown only on multi-month
  /// terms.
  (bool, int) get _valueFraming {
    // An UNPRICED plan has no commercial position to claim. A fresh Create-plan
    // form (or a cleared price field) leaves _perMonth at 0, which would
    // otherwise read as "cheaper than every peer" and award this plan BEST
    // VALUE — a false claim shown for the whole authoring session. Such a plan
    // can never reach the catalog anyway: PlanValidation and the backend both
    // reject a non-positive live price.
    if (_price <= 0) return (false, 0);
    // Peers are published plans, so their per-month price is positive; drop any
    // non-positive value defensively so a malformed legacy doc cannot drag the
    // "cheapest" baseline to 0 and hand every plan a BEST VALUE badge.
    final all = <double>[...peerPerMonth.where((pm) => pm > 0), _perMonth];
    if (all.length < 2) return (false, 0);
    double baseline = 0, best = double.infinity;
    for (final pm in all) {
      if (pm > baseline) baseline = pm;
      if (pm < best) best = pm;
    }
    final hasSpread = all.any((pm) => pm > best);
    final bestValue = hasSpread && _perMonth <= best;
    final savings = baseline > 0 && termMonths > 1
        ? ((1 - _perMonth / baseline) * 100).round()
        : 0;
    return (bestValue, savings);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final highlights = PlanHighlights.sanitize(customPoints);
    final consoleOnly = badge.trim().isNotEmpty || featured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusStrip(context),
        const SizedBox(height: 12),
        _planCard(context, highlights),
        const SizedBox(height: 10),
        Text(
          "Exactly what gyms see on the subscription screen.",
          style: AppText.body(size: 11).copyWith(color: p.textMuted),
        ),
        if (consoleOnly)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Badge and Featured organize this console — buyers don't see them.",
              style: AppText.body(size: 11)
                  .copyWith(color: const Color(0xFFB06A00)),
            ),
          ),
      ],
    );
  }

  // ── Status strip ──────────────────────────────────────────────────────────
  Widget _statusStrip(BuildContext context) {
    final p = context.palette;
    final (text, color) = switch (status) {
      PlanStatus.published => (
          "Published — live to buyers",
          const Color(0xFF1A7F5A)
        ),
      PlanStatus.hidden => (
          "Hidden — buyers won't see this",
          const Color(0xFFB06A00)
        ),
      PlanStatus.archived => ("Archived — retired from sale", p.textMuted),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadii.smR,
      ),
      child: Row(
        children: [
          Icon(
            status == PlanStatus.published
                ? Icons.public
                : status == PlanStatus.hidden
                    ? Icons.visibility_off_outlined
                    : Icons.inventory_2_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: AppText.label(size: 12).copyWith(color: color)),
          ),
        ],
      ),
    );
  }

  // ── The plan card the buyer sees ─────────────────────────────────────────
  Widget _planCard(BuildContext context, List<String> highlights) {
    final p = context.palette;
    final name = planName.trim().isEmpty ? "Untitled plan" : planName.trim();
    final showPerMonth = termMonths > 1;
    final (bestValue, savings) = _valueFraming;
    final showSavings = savings > 0 && termMonths > 1;
    final durationText = "$termMonths Month${termMonths == 1 ? '' : 's'}";
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.lgR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppText.title(size: 17).copyWith(color: p.textPrimary)),
              ),
              if (bestValue) _pill(context, "BEST VALUE"),
            ],
          ),
          const SizedBox(height: 2),
          // TrainerHQ's duration line, with the savings suffix it appends on
          // multi-month plans ("12 Months  ·  save 20% / month").
          Text(
            showSavings
                ? "$durationText  ·  save $savings% / month"
                : durationText,
            style: AppText.body(size: 11).copyWith(
                color:
                    showSavings ? const Color(0xFF1A7F5A) : p.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text("₹${_inr.format(_price.round())}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(size: 26)
                        .copyWith(color: p.textPrimary)),
              ),
              if (showPerMonth) ...[
                const SizedBox(width: 6),
                Text("₹${_inr.format(_perMonth.round())}/mo",
                    style:
                        AppText.body(size: 12).copyWith(color: p.textMuted)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 12),
          if (highlights.isEmpty)
            Text("No highlights yet — add them in the Highlights section.",
                style: AppText.body(size: 12).copyWith(color: p.textMuted))
          else
            for (final pt in highlights)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: p.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(pt,
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textSecondary)),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 12),
          // TrainerHQ's five limit chips, in its wording and order.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _cap(context, "Trainers", _limitText(PlanResource.teamMembers)),
              _cap(context, "Clients", _limitText(PlanResource.activeClients)),
              _cap(context, "Workout plans",
                  _limitText(PlanResource.workoutPlans)),
              _cap(context, "Diet plans", _limitText(PlanResource.dietPlans)),
              _cap(context, "Exercises",
                  _limitText(PlanResource.exerciseLibrary)),
            ],
          ),
        ],
      ),
    );
  }

  String _limitText(PlanResource r) =>
      SubscriptionPlanModel.limitDisplay(limits[r] ?? 0);

  Widget _pill(BuildContext context, String text) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child:
          Text(text, style: AppText.label(size: 10).copyWith(color: p.accent)),
    );
  }

  Widget _cap(BuildContext context, String label, String value) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration:
          BoxDecoration(color: p.surfaceAlt, borderRadius: AppRadii.smR),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text("$label ",
            style: AppText.body(size: 11).copyWith(color: p.textMuted)),
        Text(value,
            style: AppText.label(size: 11).copyWith(color: p.textPrimary)),
      ]),
    );
  }
}
