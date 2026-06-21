// lib/widgets/subscription_plan_dialog.dart

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/core/widgets/app_text_field.dart';
import 'package:alphaserena_admin_portel/core/widgets/primary_button.dart';
import 'package:alphaserena_admin_portel/widgets/app_snackbar.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    if (!widget.isEdit) ctrl.clearForm();
  }

  @override
  void dispose() {
    _featureCtrl.dispose();
    super.dispose();
  }

  void _addFeature() {
    final t = _featureCtrl.text.trim();
    if (t.isEmpty) return;
    ctrl.points.add(t);
    _featureCtrl.clear();
  }

  void _submit() {
    if (ctrl.planNameCtrl.text.trim().isEmpty) {
      AppSnackbar.show(title: "Missing", message: "Plan name is required");
      return;
    }
    final price = double.tryParse(ctrl.priceCtrl.text);
    if (price == null || price <= 0) {
      AppSnackbar.show(title: "Missing", message: "Enter a valid price");
      return;
    }
    ctrl.savePlan();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _section(context, "Plan info", _planInfo(context)),
                      _section(context, "Pricing", _pricing()),
                      _section(context, "Features", _features(context)),
                      _section(context, "Capacity limits", _limits(context)),
                    ],
                  ),
                ),
              ),
              _footer(context),
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
          Text(
            widget.isEdit ? "Edit subscription plan" : "Create subscription plan",
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

  Widget _planInfo(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: ctrl.planNameCtrl,
          label: "Plan name",
          icon: Icons.workspace_premium_outlined,
        ),
        const SizedBox(height: 16),
        Text("Duration",
            style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        const SizedBox(height: 8),
        Obx(() => Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ctrl.durationOptions.map((m) {
                final sel = ctrl.durationMonths.value == m;
                return InkWell(
                  onTap: () => ctrl.durationMonths.value = m,
                  borderRadius: AppRadii.smR,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel
                          ? p.accent.withValues(alpha: 0.12)
                          : p.surface,
                      borderRadius: AppRadii.smR,
                      border:
                          Border.all(color: sel ? p.accent : p.border),
                    ),
                    child: Text(
                      "$m Month${m > 1 ? 's' : ''}",
                      style: AppText.label(size: 13).copyWith(
                          color: sel ? p.accent : p.textSecondary),
                    ),
                  ),
                );
              }).toList(),
            )),
      ],
    );
  }

  Widget _pricing() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppTextField(
            controller: ctrl.priceCtrl,
            label: "Price (₹)",
            icon: Icons.currency_rupee,
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AppTextField(
            controller: ctrl.oldPriceCtrl,
            label: "Old price (optional)",
            keyboardType: TextInputType.number,
          ),
        ),
      ],
    );
  }

  Widget _features(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _featureCtrl,
                label: "Add a feature",
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
              child: Text("No features added yet",
                  style:
                      AppText.body(size: 13).copyWith(color: p.textMuted)),
            );
          }
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(ctrl.points.length, (i) {
              return Container(
                padding:
                    const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(ctrl.points[i],
                        style: AppText.body(size: 13)
                            .copyWith(color: p.accent)),
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

  Widget _limits(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Row(children: [
          Expanded(child: _num("Max admins", ctrl.maxAdminsCtrl)),
          const SizedBox(width: 12),
          Expanded(child: _num("Max trainers", ctrl.maxTrainersCtrl)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _num("Max clients", ctrl.maxClientsCtrl)),
          const SizedBox(width: 12),
          Expanded(child: _num("Max workout plans", ctrl.maxWorkoutPlansCtrl)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _num("Max workouts", ctrl.maxWorkoutsCtrl)),
          const SizedBox(width: 12),
          Expanded(child: _num("Max diet plans", ctrl.maxDietPlansCtrl)),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFB06A00).withValues(alpha: 0.10),
            borderRadius: AppRadii.smR,
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Color(0xFFB06A00), size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "These limits are saved into the plan and enforced in real time once a gym subscribes (and read by the trainersHQ app).",
                  style:
                      AppText.body(size: 12).copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _num(String label, TextEditingController c) => AppTextField(
        controller: c,
        label: label,
        keyboardType: TextInputType.number,
      );

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
            onPressed: _submit,
          )),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) {
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
          Text(title,
              style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
