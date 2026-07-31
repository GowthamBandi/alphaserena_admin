// lib/widgets/plan_comparison_dialog.dart
//
// Side-by-side plan comparison (Stripe/Shopify pricing-table style) so the
// owner instantly sees how tiers differ across pricing, business capacity and
// premium features. Data-driven — no hardcoded Starter/Professional/Enterprise
// logic; it renders whatever plans exist, in sort order.

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/models/subscription_plan_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

final _inr = NumberFormat.decimalPattern('en_IN');

class PlanComparisonDialog extends StatelessWidget {
  final List<SubscriptionPlanModel> plans;
  const PlanComparisonDialog({super.key, required this.plans});

  static const double _labelW = 180;
  static const double _colW = 156;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 820),
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
              Flexible(
                child: plans.length < 2
                    ? _tooFew(context)
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: _table(context),
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
          Icon(Icons.table_chart_outlined, color: p.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text("Compare plans",
                style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
          ),
          IconButton(
              onPressed: Get.back,
              icon: Icon(Icons.close, color: p.textMuted)),
        ],
      ),
    );
  }

  Widget _table(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _planHeaderRow(context),
        _sectionRow(context, "Pricing"),
        _valueRow(context, "Monthly", (pl) => _price(pl.monthlyPrice)),
        _valueRow(context, "Yearly", (pl) => _price(pl.yearlyPrice)),
        _valueRow(context, "Yearly saving",
            (pl) => pl.yearlySavingsPct > 0 ? "${pl.yearlySavingsPct}%" : "—"),
        _sectionRow(context, "Business Capacity"),
        for (final r in PlanResource.values)
          _valueRow(context, r.label,
              (pl) => SubscriptionPlanModel.limitDisplay(pl.limitOf(r))),
        _sectionRow(context, "Premium Features"),
        for (final entry in PlanCapabilities.catalog)
          _boolRow(context, entry.value, (pl) => pl.capable(entry.key)),
      ],
    );
  }

  Widget _planHeaderRow(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        SizedBox(width: _labelW),
        for (final pl in plans)
          Container(
            width: _colW,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (pl.featured)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.star, size: 14, color: p.accent),
                    ),
                  Flexible(
                    child: Text(pl.planName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.cardTitle(size: 15)
                            .copyWith(color: p.textPrimary)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(pl.status.label,
                    style: AppText.body(size: 11).copyWith(color: p.textMuted)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionRow(BuildContext context, String title) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      width: _labelW + _colW * plans.length,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      color: p.surfaceAlt,
      child: Text(title.toUpperCase(),
          style: AppText.label(size: 11).copyWith(
              color: p.textSecondary, letterSpacing: 1)),
    );
  }

  Widget _valueRow(BuildContext context, String label,
      String Function(SubscriptionPlanModel) value) {
    final p = context.palette;
    return _row(context, label, [
      for (final pl in plans)
        Text(value(pl),
            style: AppText.body(size: 13).copyWith(color: p.textPrimary)),
    ]);
  }

  Widget _boolRow(BuildContext context, String label,
      bool Function(SubscriptionPlanModel) on) {
    final p = context.palette;
    return _row(context, label, [
      for (final pl in plans)
        on(pl)
            ? Icon(Icons.check_circle, size: 16, color: p.accent)
            : Icon(Icons.remove, size: 16, color: p.textMuted),
    ]);
  }

  Widget _row(BuildContext context, String label, List<Widget> cells) {
    final p = context.palette;
    return Container(
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _labelW,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Text(label,
                  style:
                      AppText.body(size: 13).copyWith(color: p.textSecondary)),
            ),
          ),
          for (final cell in cells)
            SizedBox(
              width: _colW,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                child: Align(alignment: Alignment.centerLeft, child: cell),
              ),
            ),
        ],
      ),
    );
  }

  String _price(double v) => v > 0 ? "₹${_inr.format(v.round())}" : "—";

  Widget _tooFew(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Text("Add at least two plans to compare them.",
            style: AppText.body(size: 13).copyWith(color: p.textMuted)),
      ),
    );
  }
}
