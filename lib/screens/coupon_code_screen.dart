// lib/screens/coupon/coupon_code_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/coupon_controller.dart';
import '../../models/coupon_model.dart';

class CouponCodeScreen extends StatelessWidget {
  CouponCodeScreen({super.key});

  final ctrl = Get.find<CouponController>();
  final String adminUid =
      FirebaseAuth.instance.currentUser!.uid; // Replace with real admin UID

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
            const SizedBox(height: 20),

            _searchBar(),
            const SizedBox(height: 20),

            Expanded(child: _couponTable()),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _header() {
    return Row(
      children: [
        const Text(
          "Coupon Codes",
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: () => _openCreate(),
          icon: const Icon(Icons.add),
          label: const Text("Create Coupon"),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  Widget _searchBar() {
    return SizedBox(
      width: 300,
      child: TextField(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: "Search coupon...",
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (v) => ctrl.searchQuery.value = v,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _couponTable() {
    return Obx(() {
      if (ctrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final data = ctrl.coupons.where((c) {
        final q = ctrl.searchQuery.value.toLowerCase();
        return c.code.toLowerCase().contains(q) ||
            c.description.toLowerCase().contains(q);
      }).toList();

      if (data.isEmpty) {
        return const Center(child: Text("No coupons found"));
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(
          children: [
            _tableHeader(),
            const Divider(),

            Expanded(
              child: ListView.builder(
                itemCount: data.length,
                itemBuilder: (_, i) => _row(data[i]),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  Widget _tableHeader() {
    return Row(
      children: const [
        Expanded(child: Text("Code", style: _hdr)),
        Expanded(child: Text("Discount", style: _hdr)),
        Expanded(child: Text("Usage", style: _hdr)),
        Expanded(child: Text("Validity", style: _hdr)),
        Expanded(child: Text("Status", style: _hdr)),
        SizedBox(width: 80),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  Widget _row(CouponModel c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(c.code, style: _rowTxt)),
          Expanded(child: Text(_discountText(c), style: _rowTxt)),
          Expanded(child: Text("${c.usedCount}/${c.maxUsage}", style: _rowTxt)),
          Expanded(
            child: Text(
              "${_fmt(c.validFrom)} → ${_fmt(c.validTo)}",
              style: _rowTxt,
            ),
          ),
          Expanded(child: _statusBadge(c)),
          Row(
            children: [
              IconButton(
                onPressed: () => _openEdit(c),
                icon: const Icon(Icons.edit),
              ),
              IconButton(
                onPressed: () => ctrl.deleteCoupon(c.id),
                icon: const Icon(Icons.delete, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _statusBadge(CouponModel c) {
    bool expired = DateTime.now().isAfter(c.validTo);
    final active = c.isActive && !expired;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? Colors.green.shade100 : Colors.red.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        active ? "Active" : "Inactive",
        style: TextStyle(
          color: active ? Colors.green.shade700 : Colors.red.shade700,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  void _openCreate() {
    ctrl.clearForm();
    _openFormDialog(isEdit: false);
  }

  void _openEdit(CouponModel c) {
    ctrl.loadForEdit(c);
    _openFormDialog(isEdit: true);
  }

  void _openFormDialog({required bool isEdit}) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
        child: Container(
          width: 650,
          padding: const EdgeInsets.all(28),
          child: Obx(() {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TITLE
                Text(
                  isEdit ? "Edit Coupon" : "Create Coupon",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),

                // FORM FIELDS IN TWO COLUMN GRID
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl.codeCtrl,
                        decoration: const InputDecoration(
                          labelText: "Coupon Code",
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: ctrl.discountCtrl,
                        decoration: const InputDecoration(
                          labelText: "Discount Value",
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl.maxUsageCtrl,
                        decoration: const InputDecoration(
                          labelText: "Max Usage Count",
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: ctrl.descCtrl,
                        decoration: const InputDecoration(
                          labelText: "Description",
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // PERCENTAGE SWITCH
                SwitchListTile(
                  title: const Text("Percentage Discount?"),
                  value: ctrl.isPercentage.value,
                  onChanged: (v) => ctrl.isPercentage.value = v,
                  contentPadding: EdgeInsets.zero,
                ),

                const SizedBox(height: 16),

                // ACTIVE / INACTIVE TOGGLE (NEW)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Coupon Active?",
                      style: TextStyle(fontSize: 16),
                    ),
                    Switch(
                      value: isEdit
                          ? ctrl.coupons
                                .firstWhere(
                                  (x) => x.docId == ctrl.editDocId.value,
                                )
                                .isActive
                          : true,
                      onChanged: isEdit
                          ? (value) {
                              ctrl.toggleCoupon(ctrl.editDocId.value, !value);
                            }
                          : null, // disable toggle for new coupon
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // DATE PICKERS
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        title: Text(
                          "Valid From: ${_fmt(ctrl.validFrom.value)}",
                        ),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: Get.context!,
                            initialDate: ctrl.validFrom.value,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) ctrl.validFrom.value = picked;
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        title: Text("Valid To: ${_fmt(ctrl.validTo.value)}"),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: Get.context!,
                            initialDate: ctrl.validTo.value,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) ctrl.validTo.value = picked;
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // BUTTONS
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Get.back(),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () => ctrl.saveCoupon(),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 14,
                        ),
                      ),
                      child: Text(isEdit ? "Save Changes" : "Create Coupon"),
                    ),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  String _discountText(CouponModel c) {
    return c.isPercentage ? "${c.discountValue}%" : "₹${c.discountValue}";
  }

  String _fmt(DateTime d) => "${d.day}/${d.month}/${d.year}";

  BoxDecoration _card() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    boxShadow: [
      BoxShadow(
        blurRadius: 12,
        offset: const Offset(0, 4),
        color: Colors.black.withOpacity(.06),
      ),
    ],
  );

  static const _hdr = TextStyle(fontWeight: FontWeight.bold, fontSize: 14);

  final _rowTxt = const TextStyle(fontSize: 14);
}
