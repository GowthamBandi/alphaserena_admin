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
    if (!isEdit) {
      ctrl.clearForm();
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 50, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                _header(),
                const SizedBox(height: 25),

                // ----------------------------------
                // BASIC INFO
                // ----------------------------------
                _section("Basic Info"),
                _textInput("Plan Title", ctrl.titleCtrl),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(child: _numberInput("Price", ctrl.priceCtrl)),
                    const SizedBox(width: 12),
                    Expanded(child: _numberInput("Old Price (optional)", ctrl.oldPriceCtrl)),
                  ],
                ),

                const SizedBox(height: 16),
                _durationDropdown(),

                const SizedBox(height: 25),
                _divider(),

                // ----------------------------------
                // POINTS
                // ----------------------------------
                _section("Plan Points"),
                _pointInput(),
                const SizedBox(height: 10),
                _pointsList(),

                const SizedBox(height: 25),
                _divider(),

                // ----------------------------------
                // BENEFITS
                // ----------------------------------
                _section("Benefits"),
                _benefitInput(),
                const SizedBox(height: 10),
                _benefitList(),

                const SizedBox(height: 25),
                _divider(),

                // ----------------------------------
                // NUMERIC LIMITS
                // ----------------------------------
                _section("Numeric Limits"),

                Row(
                  children: [
                    Expanded(child: _numberInput("Clients", ctrl.clientLimitCtrl)),
                    const SizedBox(width: 12),
                    Expanded(child: _numberInput("Trainers", ctrl.trainerLimitCtrl)),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(child: _numberInput("Exercise Library", ctrl.exerciseLimitCtrl)),
                    const SizedBox(width: 12),
                    Expanded(child: _numberInput("Workout Plans", ctrl.workoutLimitCtrl)),
                  ],
                ),

                const SizedBox(height: 30),

                _saveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(
            isEdit ? "Edit Subscription Plan" : "Create Subscription Plan",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.close),
        )
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION TITLE
  // ---------------------------------------------------------------------------
  Widget _section(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TEXT INPUT
  // ---------------------------------------------------------------------------
  Widget _textInput(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _numberInput(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DURATION DROPDOWN
  // ---------------------------------------------------------------------------
  Widget _durationDropdown() {
    return Obx(() {
      return DropdownButtonFormField(
        value: ctrl.duration.value,
        decoration: InputDecoration(
          labelText: "Billing Duration",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: ctrl.durationOptions
            .map((d) => DropdownMenuItem(value: d, child: Text(d)))
            .toList(),
        onChanged: (v) => ctrl.duration.value = v!,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // POINTS
  // ---------------------------------------------------------------------------
  Widget _pointInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => ctrl.pointInput.value = v,
            decoration: const InputDecoration(labelText: "Add plan point"),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle, size: 28, color: Colors.green),
          onPressed: ctrl.addPoint,
        )
      ],
    );
  }

  Widget _pointsList() {
    return Obx(() {
      return Column(
        children: ctrl.points
            .map(
              (p) => _listTile(
                icon: Icons.check_circle,
                color: Colors.green,
                text: p,
                onDelete: () => ctrl.points.remove(p),
              ),
            )
            .toList(),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // BENEFITS
  // ---------------------------------------------------------------------------
  Widget _benefitInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) => ctrl.benefitInput.value = v,
            decoration: const InputDecoration(labelText: "Add a benefit"),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle, size: 28, color: Colors.blue),
          onPressed: ctrl.addBenefit,
        )
      ],
    );
  }

  Widget _benefitList() {
    return Obx(() {
      return Column(
        children: ctrl.benefits
            .map(
              (b) => _listTile(
                icon: Icons.star,
                color: Colors.orange,
                text: b,
                onDelete: () => ctrl.benefits.remove(b),
              ),
            )
            .toList(),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // TILE
  // ---------------------------------------------------------------------------
  Widget _listTile({
    required IconData icon,
    required Color color,
    required String text,
    required VoidCallback onDelete,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.red, size: 18),
          onPressed: onDelete,
        )
      ],
    );
  }

  Widget _divider() => Divider(color: Colors.grey.shade300);

  // ---------------------------------------------------------------------------
  // SAVE BUTTON
  // ---------------------------------------------------------------------------
  Widget _saveButton() {
    return Obx(() {
      return Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton(
          onPressed: ctrl.isSaving.value ? null : ctrl.savePlan,
          child: ctrl.isSaving.value
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? "Save Changes" : "Create Plan"),
        ),
      );
    });
  }
}
