// lib/screens/subscriptions/subscriptions_screen.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/subscription_controller.dart';
import '../../models/subscription_plan_model.dart';
import '../../widgets/subscription_plan_dialog.dart';

class SubscriptionsScreen extends StatelessWidget {
  SubscriptionsScreen({super.key});

  final ctrl = Get.find<SubscriptionController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F7FB),

      appBar: AppBar(
        title: const Text("Subscription Plans"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),

      floatingActionButton: FloatingActionButton.extended(
        elevation: 2,
        backgroundColor: Colors.black,
        onPressed: () {
          ctrl.clearForm();
          Get.dialog(SubscriptionPlanDialog());
        },
        label: const Text("Create Plan"),
        icon: const Icon(Icons.add),
      ),

      body: Obx(() {
        if (ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (ctrl.plans.isEmpty) {
          return _emptyState();
        }

        return _grid();
      }),
    );
  }

  // ============================================================
  // GRID
  // ============================================================
  Widget _grid() {
    return LayoutBuilder(
      builder: (_, box) {
        int cross = 1;

        if (box.maxWidth > 1400)
          cross = 4;
        else if (box.maxWidth > 1100)
          cross = 3;
        else if (box.maxWidth > 700)
          cross = 2;

        return GridView.builder(
          padding: const EdgeInsets.all(24),
          itemCount: ctrl.plans.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (_, i) => _planCard(ctrl.plans[i]),
        );
      },
    );
  }

  // ============================================================
  // 🔥 PREMIUM PLAN CARD
  // ============================================================
  Widget _planCard(SubscriptionPlanModel p) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xffF9FAFB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 30,
            color: Colors.black.withOpacity(.06),
            offset: const Offset(0, 10),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ------------------------------------------------------
          // HEADER
          // ------------------------------------------------------
          Row(
            children: [
              Expanded(
                child: Text(
                  p.planName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              PopupMenuButton(
                icon: const Icon(Icons.more_horiz),
                onSelected: (v) {
                  if (v == "edit") {
                    ctrl.loadPlanForEdit(p);
                    Get.dialog(SubscriptionPlanDialog(isEdit: true));
                  } else {
                    ctrl.deletePlan(p.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: "edit", child: Text("Edit")),
                  PopupMenuItem(
                    value: "delete",
                    child: Text("Delete", style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 6),

          Text(
            "${p.durationMonths} Month${p.durationMonths > 1 ? 's' : ''}",
            style: TextStyle(color: Colors.grey.shade600),
          ),

          const SizedBox(height: 18),

          // ------------------------------------------------------
          // 🔥 PRICE HERO
          // ------------------------------------------------------
          Row(
            children: [
              Text(
                "₹${p.price.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              if (p.oldPrice != null)
                Text(
                  "₹${p.oldPrice!.toStringAsFixed(0)}",
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: Colors.grey,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 18),

          // ------------------------------------------------------
          // 🔥 LIMITS AS CHIPS (MODERN UX)
          // ------------------------------------------------------
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip("Clients", p.maxClients),
              _chip("Trainers", p.maxTrainers),
              _chip("Admins", p.maxAdmins),
              _chip("Workout Plans", p.maxWorkoutPlans),
              _chip("Workouts", p.maxWorkouts),
              _chip("Diet Plans", p.maxDietPlans),
            ],
          ),

          const SizedBox(height: 18),

          // ------------------------------------------------------
          // FEATURES
          // ------------------------------------------------------
          if (p.points.isNotEmpty) ...[
            const Text(
              "Features",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            ...p.points.map((e) => _feature(e)),
          ],

          const Spacer(),

          // ------------------------------------------------------
          // CTA (ADMIN)
          // ------------------------------------------------------
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    ctrl.loadPlanForEdit(p);
                    Get.dialog(SubscriptionPlanDialog(isEdit: true));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Manage Plan",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CHIP (LIMIT UI)
  // ============================================================
  Widget _chip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        "$label: $value",
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ============================================================
  // FEATURE ITEM
  // ============================================================
  Widget _feature(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY STATE (MODERN)
  // ============================================================
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade200,
            ),
            child: const Icon(Icons.auto_awesome, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            "No Plans Created",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text("Create your first subscription plan to get started"),
        ],
      ),
    );
  }
}
