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
        BoxShadow(blurRadius: 10, color: Colors.black.withOpacity(.05)),
      ],
    );
  }

  TextStyle _label() => const TextStyle(color: Colors.grey, fontSize: 13);

  String _fmt(DateTime d) => "${d.day}/${d.month}/${d.year}";
}
