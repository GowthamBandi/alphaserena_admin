// lib/screens/payments/payments_screen.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/payments_controller.dart';
import '../../models/subscription_model.dart';

class PaymentsScreen extends StatelessWidget {
  PaymentsScreen({super.key});

  final ctrl = Get.put(PaymentsController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f6fa),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _header(),
            const SizedBox(height: 20),

            _kpiSection(),
            const SizedBox(height: 20),

            _middleSection(),
            const SizedBox(height: 20),

            _filters(),
            const SizedBox(height: 12),

            Expanded(child: _table()),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  Widget _header() {
    return Row(
      children: const [
        Text(
          "Payments Intelligence",
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  // ============================================================
  // KPI CARDS (🔥 CORE)
  // ============================================================
  Widget _kpiSection() {
    return Obx(() {
      return Row(
        children: [
          _kpi(
            "Total Revenue",
            ctrl.totalRevenue.value,
            ctrl.monthlyGrowth.value,
          ),

          _kpi("This Month", ctrl.monthRevenue.value, ctrl.monthlyGrowth.value),

          _kpi("Today", ctrl.todayRevenue.value, ctrl.dailyGrowth.value),

          _kpiCount("Transactions", ctrl.totalTransactions.value),
        ],
      );
    });
  }

  Widget _kpi(String title, double value, double growth) {
    final isUp = growth >= 0;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _label()),
            const SizedBox(height: 8),

            Text(
              "₹${value.toInt()}",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 6),

            Row(
              children: [
                Icon(
                  isUp ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: isUp ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  "${growth.toStringAsFixed(1)}%",
                  style: TextStyle(
                    color: isUp ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCount(String title, int value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(18),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _label()),
            const SizedBox(height: 8),
            Text(
              "$value",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MIDDLE SECTION (TOP ADMINS + PLAN BREAKDOWN)
  // ============================================================
  Widget _middleSection() {
    return Row(
      children: [
        Expanded(child: _topAdmins()),
        const SizedBox(width: 16),
        Expanded(child: _topPlans()),
      ],
    );
  }

  // ============================================================
  // TOP ADMINS
  // ============================================================
  Widget _topAdmins() {
    return Obx(() {
      final list = ctrl.topAdmins;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Top Paying Admins",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            ...list.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text(
                      "₹${e.value.toInt()}",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ============================================================
  // PLAN BREAKDOWN
  // ============================================================
  Widget _topPlans() {
    return Obx(() {
      final list = ctrl.topPlans;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Revenue by Plan",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 12),

            ...list.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text("₹${e.value.toInt()}"),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  // ============================================================
  // FILTERS
  // ============================================================
  Widget _filters() {
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            decoration: InputDecoration(
              hintText: "Search...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (v) => ctrl.searchQuery.value = v,
          ),
        ),
        const SizedBox(width: 12),

        Obx(() {
          return DropdownButton<String>(
            value: ctrl.selectedPlan.value,
            items: ctrl.availablePlans
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => ctrl.selectedPlan.value = v!,
          );
        }),
      ],
    );
  }

  // ============================================================
  // TABLE
  // ============================================================
  Widget _table() {
    return Obx(() {
      if (ctrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final list = ctrl.filteredList;

      if (list.isEmpty) {
        return const Center(child: Text("No payments found"));
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => _row(list[i]),
        ),
      );
    });
  }

  Widget _row(SubscriptionModel s) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(s.planName)),
          Expanded(child: Text("₹${s.amountPaid}")),
          Expanded(child: Text(s.adminUid)),
          Expanded(child: Text(s.paymentId)),
          Expanded(child: Text(_fmt(s.createdAt))),
          SizedBox(width: 48, child: _refundAction(s)),
        ],
      ),
    );
  }

  // ============================================================
  // FOUNDER REFUND ACTION
  // ============================================================
  Widget _refundAction(SubscriptionModel s) {
    // Fully refunded — nothing left to give back.
    if (s.isFullyRefunded) {
      return const Center(
        child: Text(
          "Refunded",
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      );
    }

    // No gateway payment id on the receipt — the backend can't refund it.
    final canRefund = s.razorpayPaymentId.isNotEmpty;

    return Center(
      child: IconButton(
        tooltip: canRefund
            ? "Refund…"
            : "No gateway payment id — cannot refund",
        icon: const Icon(Icons.currency_rupee, size: 18),
        color: Colors.grey.shade700,
        onPressed: canRefund ? () => _openRefundDialog(s) : null,
      ),
    );
  }

  void _openRefundDialog(SubscriptionModel s) {
    final maxRefundable = s.netAmount.floor();
    bool isPartial = false;
    bool revokeAccess = false;
    String? amountError;
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    Get.dialog(
      StatefulBuilder(
        builder: (context, setState) {
          bool isValid() {
            if (reasonCtrl.text.trim().isEmpty) return false;
            if (!isPartial) return true;
            final v = int.tryParse(amountCtrl.text.trim());
            return v != null && v >= 1 && v <= maxRefundable;
          }

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Container(
              width: 440,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Refund Payment",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 16),

                  // Context — org / plan / amounts
                  _refundInfoRow("Organization", s.adminUid),
                  _refundInfoRow("Plan", s.planName),
                  _refundInfoRow("Paid", "₹${s.amountPaid}"),
                  if (s.refundAmount > 0)
                    _refundInfoRow(
                      "Already refunded",
                      "₹${s.refundAmount.toInt()}",
                    ),
                  _refundInfoRow("Refundable", "₹$maxRefundable"),
                  const SizedBox(height: 16),

                  // Full vs partial
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text("Full refund"),
                        selected: !isPartial,
                        onSelected: (_) => setState(() {
                          isPartial = false;
                          amountError = null;
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("Partial"),
                        selected: isPartial,
                        onSelected: (_) => setState(() => isPartial = true),
                      ),
                    ],
                  ),

                  if (isPartial) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Amount (₹, 1–$maxRefundable)",
                        errorText: amountError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (v) => setState(() {
                        final n = int.tryParse(v.trim());
                        amountError =
                            (v.trim().isEmpty ||
                                (n != null && n >= 1 && n <= maxRefundable))
                            ? null
                            : "Enter a whole amount between 1 and $maxRefundable";
                      }),
                    ),
                  ],

                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      labelText: "Reason (required)",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),

                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: revokeAccess,
                    onChanged: (v) => setState(() => revokeAccess = v ?? false),
                    title: const Text(
                      "Also deactivate subscription",
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      "Ends the org's access now. The backend REJECTS the "
                      "whole refund if this is not the org's current "
                      "subscription payment — uncheck to refund an older "
                      "payment.",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Get.back(),
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 8),
                      Obx(() {
                        final busy = ctrl.isRefunding.value;
                        return ElevatedButton(
                          onPressed: busy || !isValid()
                              ? null
                              : () async {
                                  final ok = await ctrl.refundPayment(
                                    s,
                                    amount: isPartial
                                        ? int.parse(amountCtrl.text.trim())
                                        : null,
                                    reason: reasonCtrl.text.trim(),
                                    revokeAccess: revokeAccess,
                                  );
                                  if (ok) Get.back();
                                },
                          child: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("Refund"),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
      barrierDismissible: false,
    ).then((_) {
      // Dialog closed (save or cancel) — release the field controllers.
      amountCtrl.dispose();
      reasonCtrl.dispose();
    });
  }

  Widget _refundInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: _label())),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================
  BoxDecoration _card() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(blurRadius: 10, color: Colors.black.withValues(alpha: .05)),
      ],
    );
  }

  TextStyle _label() => const TextStyle(color: Colors.grey, fontSize: 13);

  String _fmt(DateTime d) => "${d.day}/${d.month}/${d.year}";
}
