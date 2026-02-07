// lib/screens/subscriptions/subscriptions_screen.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/subscription_controller.dart';
import '../../widgets/subscription_plan_dialog.dart';
import '../../models/subscription_plan_model.dart';

class SubscriptionsScreen extends StatelessWidget {
  SubscriptionsScreen({super.key});

  final ctrl = Get.put(SubscriptionController());
  final bool isMasterAdmin = true; // real permission check later

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f8fa),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 26),
            Expanded(child: _grid()),
          ],
        ),
      ),
    );
  }

  // HEADER -------------------------------------------------------------
  Widget _header() {
    return Row(
      children: [
        const Text(
          "Subscription Plans",
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),

        const SizedBox(width: 12),

        Obx(() => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "${ctrl.plans.length} plans",
                style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            )),

        const Spacer(),

        if (isMasterAdmin)
          ElevatedButton.icon(
            onPressed: () {
              ctrl.clearForm();
              showDialog(
                context: Get.context!,
                builder: (_) => SubscriptionPlanDialog(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add),
            label: const Text("Create Plan"),
          ),
      ],
    );
  }

  // GRID ---------------------------------------------------------------
  Widget _grid() {
    return Obx(() {
      if (ctrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (ctrl.plans.isEmpty) {
        return const Center(
            child: Text("No plans available",
                style: TextStyle(color: Colors.grey, fontSize: 16)));
      }

      return LayoutBuilder(builder: (context, box) {
        int cross = 1;
        if (box.maxWidth > 1400) cross = 4;
        else if (box.maxWidth > 1100) cross = 3;
        else if (box.maxWidth > 800) cross = 2;

        return GridView.builder(
          itemCount: ctrl.plans.length,
          padding: const EdgeInsets.only(top: 10),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            mainAxisSpacing: 24,
            crossAxisSpacing: 24,
            childAspectRatio: 0.75,
          ),
          itemBuilder: (_, i) => _card(ctrl.plans[i], i),
        );
      });
    });
  }

  // CARD ---------------------------------------------------------------
  Widget _card(SubscriptionPlanModel plan, int index) {
    final isPopular = index == 1;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.white, Color(0xfff2f3f7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 6),
            color: Colors.black.withOpacity(.08),
          )
        ],
      ),
      child: Stack(
        children: [
          if (isPopular) _ribbon(),

          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // title
                Text(plan.title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),

                Text(plan.duration,
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                const SizedBox(height: 20),

                // price
                Row(
                  children: [
                    Text("\$${plan.price}",
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold)),
                    if (plan.oldPrice != null) ...[
                      const SizedBox(width: 12),
                      Text("\$${plan.oldPrice}",
                          style: const TextStyle(
                              color: Colors.red,
                              decoration: TextDecoration.lineThrough)),
                    ]
                  ],
                ),

                const SizedBox(height: 18),

                // FEATURES
                Text("Features",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800)),
                const SizedBox(height: 8),

                Expanded(
                  child: ListView(
                    children: [
                      ...plan.points.map((e) => _bullet(e, false)),

                      const SizedBox(height: 10),

                      Text("Benefits",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade800)),
                      const SizedBox(height: 8),

                      ...plan.benefits.map((e) => _bullet(e, true)),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // edit/delete
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                        onPressed: () => ctrl.deletePlan(plan.id),
                        child: const Text("Delete",
                            style: TextStyle(color: Colors.red))),
                    TextButton(
                        onPressed: () => _edit(plan),
                        child: const Text("Edit")),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // RIBBON --------------------------------------------------------------
  Widget _ribbon() {
    return Positioned(
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          color: Colors.deepPurple,
          borderRadius:
              BorderRadius.only(topRight: Radius.circular(20), bottomLeft: Radius.circular(16)),
        ),
        child: const Text("MOST POPULAR",
            style:
                TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // BULLET --------------------------------------------------------------
  Widget _bullet(String text, bool benefit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(benefit ? Icons.star : Icons.check_circle,
              size: 18, color: benefit ? Colors.orange : Colors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // OPEN EDIT -----------------------------------------------------------
  void _edit(SubscriptionPlanModel plan) {
    ctrl.loadPlanForEdit(plan);
    showDialog(
      context: Get.context!,
      builder: (_) => SubscriptionPlanDialog(isEdit: true),
    );
  }
}
