// lib/screens/coupon_code_screen.dart
//
// Founder-managed discount codes (collection: coupon_codes). Full CRUD —
// allowed by the security rules (super-admin read/write).

import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/core/widgets/app_text_field.dart';
import 'package:alphaserena_admin_portel/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../controllers/coupon_controller.dart';
import '../models/coupon_model.dart';
import '../widgets/page_shell.dart';

const _cActive = Color(0xFF1A7F5A);
const _cInactive = Color(0xFF9AA0A6);
const _cExpired = Color(0xFFD4341F);

class CouponCodeScreen extends StatelessWidget {
  CouponCodeScreen({super.key});

  final CouponController ctrl = Get.find<CouponController>();
  final TextEditingController _searchCtrl = TextEditingController();

  String _discountText(CouponModel c) => c.isPercentage
      ? "${c.discountValue.toStringAsFixed(0)}% off"
      : "₹${c.discountValue.toStringAsFixed(0)} off";

  bool _isExpired(CouponModel c) => c.validTo.isBefore(DateTime.now());

  void _create() {
    ctrl.clearForm();
    _openDialog(Get.context!, isEdit: false);
  }

  void _edit(BuildContext context, CouponModel c) {
    ctrl.loadForEdit(c);
    _openDialog(context, isEdit: true);
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      title: "Coupons",
      icon: Icons.discount_outlined,
      trailing: ElevatedButton.icon(
        onPressed: _create,
        icon: const Icon(Icons.add, size: 18),
        label: const Text("New coupon"),
        style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => ctrl.searchQuery.value = v,
            decoration: InputDecoration(
              hintText: "Search coupon codes…",
              prefixIcon:
                  Icon(Icons.search, color: context.palette.textMuted),
              filled: true,
              fillColor: context.palette.surface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.smR,
                  borderSide: BorderSide(color: context.palette.border)),
            ),
          ),
          const SizedBox(height: 16),
          Obx(() {
            if (ctrl.isLoading.value && ctrl.coupons.isEmpty) {
              return const SizedBox(
                  height: 220,
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4)));
            }
            final q = ctrl.searchQuery.value.toLowerCase();
            final list = ctrl.coupons
                .where((c) =>
                    q.isEmpty ||
                    c.code.toLowerCase().contains(q) ||
                    c.description.toLowerCase().contains(q))
                .toList();
            if (list.isEmpty) return _empty(context);
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final c in list)
                  SizedBox(width: 360, child: _card(context, c)),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, CouponModel c) {
    final p = context.palette;
    final expired = _isExpired(c);
    final stateColor =
        !c.isActive ? _cInactive : (expired ? _cExpired : _cActive);
    final stateText =
        !c.isActive ? "Disabled" : (expired ? "Expired" : "Active");

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: AppRadii.smR),
              child: Icon(Icons.local_offer_outlined,
                  color: p.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title(size: 18)
                          .copyWith(color: p.textPrimary, letterSpacing: 1)),
                  Text(_discountText(c),
                      style: AppText.label(size: 13)
                          .copyWith(color: p.accent)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999)),
              child: Text(stateText,
                  style:
                      AppText.label(size: 11).copyWith(color: stateColor)),
            ),
          ]),
          if (c.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(c.description,
                style: AppText.body(size: 13).copyWith(color: p.textSecondary)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Icon(Icons.event_outlined, size: 14, color: p.textMuted),
            const SizedBox(width: 6),
            Text("Till ${DateFormat('d MMM yyyy').format(c.validTo)}",
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
            const Spacer(),
            Icon(Icons.confirmation_number_outlined,
                size: 14, color: p.textMuted),
            const SizedBox(width: 6),
            Text("${c.usedCount}/${c.maxUsage} used",
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          ]),
          const SizedBox(height: 8),
          Divider(height: 1, color: p.border),
          Row(children: [
            const Spacer(),
            Obx(() {
              // keep the switch reactive to list updates
              ctrl.coupons.length;
              return Switch(
                value: c.isActive,
                activeThumbColor: p.accent,
                onChanged: (_) => ctrl.toggleCoupon(c.docId, c.isActive),
              );
            }),
            IconButton(
              tooltip: 'Edit',
              icon: Icon(Icons.edit_outlined, color: p.textMuted, size: 20),
              onPressed: () => _edit(context, c),
            ),
            IconButton(
              tooltip: 'Disable',
              icon: const Icon(Icons.delete_outline,
                  color: _cExpired, size: 20),
              onPressed: () => _confirmDelete(context, c),
            ),
          ]),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, CouponModel c) {
    final p = context.palette;
    Get.dialog(AlertDialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      title: const Text("Disable coupon?"),
      content: Text("“${c.code}” will be turned off and stop working.",
          style: AppText.body(size: 13).copyWith(color: p.textSecondary)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text("Cancel", style: TextStyle(color: p.textMuted))),
        ElevatedButton(
          onPressed: () {
            Get.back();
            ctrl.deleteCoupon(c.docId);
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: _cExpired,
              foregroundColor: Colors.white,
              shape:
                  const RoundedRectangleBorder(borderRadius: AppRadii.mdR)),
          child: const Text("Disable"),
        ),
      ],
    ));
  }

  // ── CREATE / EDIT DIALOG ────────────────────────────────────────────
  void _openDialog(BuildContext context, {required bool isEdit}) {
    final p = context.palette;
    Get.dialog(Dialog(
      backgroundColor: p.background,
      insetPadding: const EdgeInsets.all(20),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? "Edit coupon" : "Create coupon",
                  style:
                      AppText.title(size: 20).copyWith(color: p.textPrimary)),
              const SizedBox(height: 18),
              AppTextField(
                controller: ctrl.codeCtrl,
                label: "Coupon code",
                icon: Icons.local_offer_outlined,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: ctrl.descCtrl,
                label: "Description (optional)",
                icon: Icons.notes,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: AppTextField(
                    controller: ctrl.discountCtrl,
                    label: "Discount value",
                    icon: Icons.percent,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _typeToggle(context)),
              ]),
              const SizedBox(height: 14),
              AppTextField(
                controller: ctrl.maxUsageCtrl,
                label: "Max usage",
                icon: Icons.confirmation_number_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _dateField(context, "Valid from", ctrl.validFrom)),
                const SizedBox(width: 12),
                Expanded(
                    child: _dateField(context, "Valid to", ctrl.validTo)),
              ]),
              const SizedBox(height: 22),
              Row(children: [
                TextButton(
                    onPressed: () => Get.back(),
                    child: Text("Cancel",
                        style: TextStyle(color: p.textMuted))),
                const Spacer(),
                SizedBox(
                  width: 170,
                  child: Obx(() => PrimaryButton(
                        label: isEdit ? "Update" : "Create",
                        icon: Icons.check,
                        isLoading: ctrl.isSaving.value,
                        onPressed: ctrl.saveCoupon,
                      )),
                ),
              ]),
            ],
          ),
        ),
      ),
    ));
  }

  Widget _typeToggle(BuildContext context) {
    final p = context.palette;
    Widget opt(String label, bool percent) {
      return Expanded(
        child: Obx(() {
          final sel = ctrl.isPercentage.value == percent;
          return InkWell(
            onTap: () => ctrl.isPercentage.value = percent,
            borderRadius: AppRadii.smR,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: sel ? p.accent.withValues(alpha: 0.12) : p.surface,
                borderRadius: AppRadii.smR,
                border: Border.all(color: sel ? p.accent : p.border),
              ),
              child: Text(label,
                  style: AppText.label(size: 13).copyWith(
                      color: sel ? p.accent : p.textSecondary)),
            ),
          );
        }),
      );
    }

    return Row(children: [opt("%", true), const SizedBox(width: 8), opt("₹", false)]);
  }

  Widget _dateField(BuildContext context, String label, Rx<DateTime> rx) {
    final p = context.palette;
    return Obx(() => InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: rx.value,
              firstDate: DateTime(2024),
              lastDate: DateTime(2100),
            );
            if (picked != null) rx.value = picked;
          },
          borderRadius: AppRadii.smR,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: p.inputFill,
              borderRadius: AppRadii.smR,
              border: Border.all(color: p.border),
            ),
            child: Row(children: [
              Icon(Icons.event_outlined, size: 18, color: p.accent),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppText.body(size: 11)
                          .copyWith(color: p.textMuted)),
                  Text(DateFormat('d MMM yyyy').format(rx.value),
                      style: AppText.label(size: 13)
                          .copyWith(color: p.textPrimary)),
                ],
              ),
            ]),
          ),
        ));
  }

  Widget _empty(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.accent.withValues(alpha: 0.10)),
          child: Icon(Icons.discount_outlined, size: 34, color: p.accent),
        ),
        const SizedBox(height: 16),
        Text("No coupons yet",
            style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
        const SizedBox(height: 6),
        Text("Create discount codes gyms can use at checkout.",
            style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        const SizedBox(height: 18),
        ElevatedButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text("Create coupon")),
      ]),
    );
  }
}
