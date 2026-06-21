// lib/widgets/subscription_plan_dialog.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/subscription_controller.dart';

class SubscriptionPlanDialog extends StatelessWidget {
  final bool isEdit;

  SubscriptionPlanDialog({super.key, this.isEdit = false});

  final ctrl = Get.find<SubscriptionController>();

  @override
  Widget build(BuildContext context) {
    if (!isEdit) ctrl.clearForm();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 780),
        decoration: BoxDecoration(
          color: const Color(0xffF4F6FA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _section("Plan Info", _planInfo()),
                    _section("Pricing", _pricing()),
                    _section("Features", _features()),
                    _section("Capacity Limits", _limits()),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // HEADER
  // =========================================================
  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Text(
            isEdit ? "Edit Subscription Plan" : "Create Subscription Plan",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(onPressed: Get.back, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }

  // =========================================================
  // PLAN INFO
  // =========================================================
  Widget _planInfo() {
    return Column(
      children: [
        _input("Plan Name", ctrl.planNameCtrl),
        const SizedBox(height: 12),

        Obx(
          () => DropdownButtonFormField<int>(
            value: ctrl.durationMonths.value,
            decoration: _dec("Duration (Months)"),
            items: ctrl.durationOptions
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text("$e Month${e > 1 ? 's' : ''}"),
                  ),
                )
                .toList(),
            onChanged: (v) => ctrl.durationMonths.value = v ?? 1,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // PRICING
  // =========================================================
  Widget _pricing() {
    return Row(
      children: [
        Expanded(child: _number("Price (₹)", ctrl.priceCtrl)),
        const SizedBox(width: 12),
        Expanded(child: _number("Old Price (optional)", ctrl.oldPriceCtrl)),
      ],
    );
  }

  // =========================================================
  // FEATURES
  // =========================================================
  Widget _features() {
    return Column(
      children: [
        _addField("Add Feature", ctrl.pointInput, ctrl.addPoint),
        const SizedBox(height: 12),

        Obx(() {
          if (ctrl.points.isEmpty) {
            return const Text(
              "No features added",
              style: TextStyle(color: Colors.grey),
            );
          }

          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              ctrl.points.length,
              (i) => Chip(
                label: Text(ctrl.points[i]),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () => ctrl.removePoint(i),
              ),
            ),
          );
        }),
      ],
    );
  }

  // =========================================================
  // 🔥 LIMITS (CRITICAL + CLEAN UX)
  // =========================================================
  Widget _limits() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _number("Max Admins", ctrl.maxAdminsCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _number("Max Trainers", ctrl.maxTrainersCtrl)),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(child: _number("Max Clients", ctrl.maxClientsCtrl)),
            const SizedBox(width: 12),
            Expanded(
              child: _number("Max Workout Plans", ctrl.maxWorkoutPlansCtrl),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(child: _number("Max Workouts", ctrl.maxWorkoutsCtrl)),
            const SizedBox(width: 12),
            Expanded(child: _number("Max Diet Plans", ctrl.maxDietPlansCtrl)),
          ],
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "These values define platform limits and are enforced in real-time.",
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // FOOTER
  // =========================================================
  Widget _footer() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Obx(() {
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: ctrl.isSaving.value ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: ctrl.isSaving.value
                ? const CircularProgressIndicator()
                : Text(isEdit ? "Update Plan" : "Create Plan"),
          ),
        );
      }),
    );
  }

  // =========================================================
  // SUBMIT
  // =========================================================
  void _submit() {
    if (ctrl.planNameCtrl.text.trim().isEmpty) {
      Get.snackbar("Error", "Plan name required");
      return;
    }

    final price = double.tryParse(ctrl.priceCtrl.text);
    if (price == null || price <= 0) {
      Get.snackbar("Error", "Valid price required");
      return;
    }

    ctrl.savePlan();
  }

  // =========================================================
  // INPUTS
  // =========================================================
  Widget _input(String label, TextEditingController c) {
    return TextField(controller: c, decoration: _dec(label));
  }

  Widget _number(String label, TextEditingController c) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: _dec(label),
    );
  }

  Widget _addField(String hint, RxString rx, VoidCallback onAdd) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => rx.value = v,
            decoration: _dec(hint),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: onAdd, child: const Text("Add")),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xffF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
