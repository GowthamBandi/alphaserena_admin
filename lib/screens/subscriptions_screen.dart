// lib/screens/subscriptions_screen.dart

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/subscription_controller.dart';
import '../models/subscription_plan_model.dart';
import '../widgets/page_shell.dart';
import '../widgets/plan_comparison_dialog.dart';
import '../widgets/subscription_plan_dialog.dart';
import '../widgets/trainer_preview_dialog.dart';

final _inr = NumberFormat.decimalPattern('en_IN');

class SubscriptionsScreen extends StatelessWidget {
  SubscriptionsScreen({super.key});

  final SubscriptionController ctrl = Get.find<SubscriptionController>();

  void _create() {
    ctrl.clearForm();
    Get.dialog(const SubscriptionPlanDialog());
  }

  void _edit(SubscriptionPlanModel p) {
    ctrl.loadPlanForEdit(p);
    Get.dialog(const SubscriptionPlanDialog(isEdit: true));
  }

  void _confirmDelete(BuildContext context, SubscriptionPlanModel plan) {
    final p = context.palette;
    Get.dialog(
      AlertDialog(
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
        title: const Text("Delete plan?"),
        content: Text(
          "“${plan.planName}” will be removed from the catalog. Gyms already on this plan keep their subscription.",
          style: AppText.body(size: 13).copyWith(color: p.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text("Cancel", style: TextStyle(color: p.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              ctrl.deletePlan(plan.docId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4341F),
              foregroundColor: Colors.white,
              shape:
                  const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
            ),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  // ── Status badge ──────────────────────────────────────────────────────
  Widget _statusBadge(BuildContext context, PlanStatus status) {
    final p = context.palette;
    final color = switch (status) {
      PlanStatus.published => const Color(0xFF1A7F5A),
      PlanStatus.hidden => p.textMuted,
      PlanStatus.archived => const Color(0xFFB06A00),
    };
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(status.label,
          style: AppText.label(size: 11).copyWith(color: color)),
    );
  }

  // ── Card action menu (status-aware) ────────────────────────────────────
  List<PopupMenuEntry<String>> _cardMenu(SubscriptionPlanModel plan) {
    return [
      const PopupMenuItem(value: 'edit', child: Text('Edit')),
      const PopupMenuItem(value: 'preview', child: Text('Trainer preview')),
      const PopupMenuItem(value: 'clone', child: Text('Duplicate')),
      const PopupMenuDivider(),
      // Status transitions — only the ones valid from the current state.
      if (plan.status != PlanStatus.published)
        const PopupMenuItem(value: 'publish', child: Text('Publish')),
      if (plan.status == PlanStatus.published)
        const PopupMenuItem(value: 'hide', child: Text('Hide')),
      if (plan.status == PlanStatus.archived)
        const PopupMenuItem(value: 'hide', child: Text('Restore to hidden')),
      if (plan.status != PlanStatus.archived)
        const PopupMenuItem(value: 'archive', child: Text('Archive')),
      // Deletion is only offered once a plan is safely archived.
      if (plan.status == PlanStatus.archived) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: Text('Delete', style: TextStyle(color: Color(0xFFD4341F))),
        ),
      ],
    ];
  }

  void _onCardAction(
      BuildContext context, SubscriptionPlanModel plan, String v) {
    switch (v) {
      case 'edit':
        _edit(plan);
      case 'preview':
        _preview();
      case 'clone':
        ctrl.clonePlan(plan);
      case 'publish':
        ctrl.setPlanStatus(plan, PlanStatus.published);
      case 'hide':
        ctrl.setPlanStatus(plan, PlanStatus.hidden);
      case 'archive':
        ctrl.setPlanStatus(plan, PlanStatus.archived);
      case 'delete':
        _confirmDelete(context, plan);
    }
  }

  void _compare() {
    Get.dialog(PlanComparisonDialog(
      plans: ctrl.filteredPlans.length >= 2 ? ctrl.filteredPlans : ctrl.plans,
    ));
  }

  void _preview() {
    Get.dialog(TrainerPreviewDialog(plans: ctrl.publishedPlans));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PageShell(
      title: "Subscription Plans",
      icon: Icons.workspace_premium_outlined,
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _preview,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text("Preview"),
          ),
          OutlinedButton.icon(
            onPressed: _compare,
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text("Compare"),
          ),
          ElevatedButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text("New plan"),
            style: ElevatedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
      child: Obx(() {
        if (ctrl.isLoading.value && ctrl.plans.isEmpty) {
          return const SizedBox(
            height: 260,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        }
        if (ctrl.plans.isEmpty) return _empty(context);
        final shown = ctrl.filteredPlans;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _statusFilters(context),
            const SizedBox(height: 18),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text("No plans in this view.",
                      style: AppText.body(size: 13)
                          .copyWith(color: p.textMuted)),
                ),
              )
            else
              Wrap(
                spacing: 18,
                runSpacing: 18,
                children: [
                  for (final plan in shown)
                    SizedBox(width: 320, child: _planCard(context, plan)),
                ],
              ),
          ],
        );
      }),
    );
  }

  Widget _statusFilters(BuildContext context) {
    final p = context.palette;
    Widget chip(String label, PlanStatus? status, int count) {
      final sel = ctrl.statusFilter.value == status;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: () => ctrl.statusFilter.value = status,
          borderRadius: AppRadii.smR,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? p.accent.withValues(alpha: 0.12) : p.surface,
              borderRadius: AppRadii.smR,
              border: Border.all(color: sel ? p.accent : p.border),
            ),
            child: Text("$label · $count",
                style: AppText.label(size: 12)
                    .copyWith(color: sel ? p.accent : p.textSecondary)),
          ),
        ),
      );
    }

    return Wrap(
      children: [
        chip("All", null, ctrl.plans.length),
        chip("Published", PlanStatus.published,
            ctrl.statusCount(PlanStatus.published)),
        chip("Hidden", PlanStatus.hidden, ctrl.statusCount(PlanStatus.hidden)),
        chip("Archived", PlanStatus.archived,
            ctrl.statusCount(PlanStatus.archived)),
      ],
    );
  }

  // ── PLAN CARD ───────────────────────────────────────────────────────
  Widget _planCard(BuildContext context, SubscriptionPlanModel plan) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.lgR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.planName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title(size: 20)
                        .copyWith(color: p.textPrimary)),
              ),
              if (plan.featured)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.star, size: 16, color: p.accent),
                ),
              if (plan.badge.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(plan.badge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label(size: 11).copyWith(color: p.accent)),
                ),
              if (plan.status != PlanStatus.published)
                _statusBadge(context, plan.status),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, color: p.textMuted),
                position: PopupMenuPosition.under,
                onSelected: (v) => _onCardAction(context, plan, v),
                itemBuilder: (_) => _cardMenu(plan),
              ),
            ],
          ),
          Text(
            plan.billingPeriod == BillingPeriod.yearly
                ? "Billed yearly"
                : "Billed monthly",
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),

          // Price hero — the live (charged) price for this billing period.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text("₹${_inr.format(plan.price.round())}",
                    style: AppText.display(size: 34).copyWith(color: p.accent)),
                const SizedBox(width: 4),
                Text(plan.billingPeriod == BillingPeriod.yearly ? "/yr" : "/mo",
                    style: AppText.body(size: 13).copyWith(color: p.textMuted)),
              ],
            ),
          ),
          // Secondary price + computed yearly saving, when both are set. The
          // saving always shows the annual advantage regardless of billing.
          if (plan.monthlyPrice > 0 && plan.yearlyPrice > 0) ...[
            const SizedBox(height: 4),
            Text(
              (plan.billingPeriod == BillingPeriod.yearly
                      ? "₹${_inr.format(plan.monthlyPrice.round())}/mo if billed monthly"
                      : "₹${_inr.format(plan.yearlyPrice.round())}/yr if billed yearly") +
                  (plan.yearlySavingsPct > 0
                      ? " · yearly saves ${plan.yearlySavingsPct}%"
                      : ""),
              style: AppText.body(size: 12).copyWith(
                color: plan.yearlySavingsPct > 0
                    ? const Color(0xFF1A7F5A)
                    : p.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 16),

          // Limits (Unlimited-aware)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _limitChip(context, Icons.groups_outlined, "Team",
                  SubscriptionPlanModel.limitDisplay(
                      plan.limitOf(PlanResource.teamMembers))),
              _limitChip(context, Icons.people_outline, "Clients",
                  SubscriptionPlanModel.limitDisplay(
                      plan.limitOf(PlanResource.activeClients))),
              _limitChip(context, Icons.list_alt, "Workout plans",
                  SubscriptionPlanModel.limitDisplay(
                      plan.limitOf(PlanResource.workoutPlans))),
              _limitChip(context, Icons.restaurant_menu, "Diet plans",
                  SubscriptionPlanModel.limitDisplay(
                      plan.limitOf(PlanResource.dietPlans))),
              _limitChip(context, Icons.bolt, "Exercises",
                  SubscriptionPlanModel.limitDisplay(
                      plan.limitOf(PlanResource.exerciseLibrary))),
            ],
          ),

          // Enabled capabilities.
          if (plan.capabilities.values.any((v) => v)) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in PlanCapabilities.catalog)
                  if (plan.capable(entry.key))
                    _capabilityChip(context, entry.value),
              ],
            ),
          ],

          if (plan.points.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...plan.points.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle,
                          size: 17, color: p.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(e,
                            style: AppText.feature(size: 13)
                                .copyWith(color: p.textSecondary)),
                      ),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _edit(plan),
              style: OutlinedButton.styleFrom(
                foregroundColor: p.accent,
                side: BorderSide(color: p.accent),
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text("Manage plan"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitChip(
      BuildContext context, IconData icon, String label, String value) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: AppRadii.smR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: p.textMuted),
          const SizedBox(width: 6),
          Text("$label ",
              style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          Text(value,
              style: AppText.label(size: 12).copyWith(color: p.textPrimary)),
        ],
      ),
    );
  }

  Widget _capabilityChip(BuildContext context, String label) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check, size: 12, color: p.accent),
          const SizedBox(width: 4),
          Text(label,
              style: AppText.label(size: 11).copyWith(color: p.accent)),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.accent.withValues(alpha: 0.10),
            ),
            child: Icon(Icons.auto_awesome, size: 36, color: p.accent),
          ),
          const SizedBox(height: 16),
          Text("No plans yet",
              style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
          const SizedBox(height: 6),
          Text("Create your first Tier-1 plan for gyms to subscribe to.",
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Create plan"),
          ),
        ],
      ),
    );
  }
}
