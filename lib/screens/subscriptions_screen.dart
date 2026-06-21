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
import '../widgets/subscription_plan_dialog.dart';

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
              ctrl.deletePlan(plan.id);
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

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: "Subscription Plans",
      icon: Icons.workspace_premium_outlined,
      trailing: ElevatedButton.icon(
        onPressed: _create,
        icon: const Icon(Icons.add, size: 18),
        label: const Text("New plan"),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      child: Obx(() {
        if (ctrl.isLoading.value && ctrl.plans.isEmpty) {
          return const SizedBox(
            height: 260,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        }
        if (ctrl.plans.isEmpty) return _empty(context);
        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            for (final plan in ctrl.plans)
              SizedBox(width: 320, child: _planCard(context, plan)),
          ],
        );
      }),
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
              if (!plan.isActive)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: p.textMuted.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text("Inactive",
                      style: AppText.label(size: 11)
                          .copyWith(color: p.textMuted)),
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, color: p.textMuted),
                position: PopupMenuPosition.under,
                onSelected: (v) {
                  if (v == 'edit') _edit(plan);
                  if (v == 'delete') _confirmDelete(context, plan);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete',
                        style: TextStyle(color: Color(0xFFD4341F))),
                  ),
                ],
              ),
            ],
          ),
          Text(
            "${plan.durationMonths} month${plan.durationMonths > 1 ? 's' : ''}",
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),

          // Price hero
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text("₹${_inr.format(plan.price.round())}",
                  style: AppText.display(size: 34).copyWith(color: p.accent)),
              const SizedBox(width: 8),
              if (plan.oldPrice != null && plan.oldPrice! > 0)
                Text("₹${_inr.format(plan.oldPrice!.round())}",
                    style: AppText.body(size: 14).copyWith(
                      color: p.textMuted,
                      decoration: TextDecoration.lineThrough,
                    )),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: p.border),
          const SizedBox(height: 16),

          // Limits
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _limitChip(context, Icons.fitness_center, "Trainers",
                  plan.maxTrainers),
              _limitChip(context, Icons.people_outline, "Clients",
                  plan.maxClients),
              _limitChip(context, Icons.list_alt, "Workout plans",
                  plan.maxWorkoutPlans),
              _limitChip(context, Icons.restaurant_menu, "Diet plans",
                  plan.maxDietPlans),
              _limitChip(context, Icons.bolt, "Workouts", plan.maxWorkouts),
            ],
          ),

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
      BuildContext context, IconData icon, String label, int value) {
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
          Text("$value",
              style: AppText.label(size: 12).copyWith(color: p.textPrimary)),
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
