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
      backgroundColor: const Color(0xfff7f8fa),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 20),
            _filters(),
            const SizedBox(height: 20),
            Expanded(child: _subscriptionTable()),
          ],
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
        const Text(
          "Subscription Payments",
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const Spacer(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // FILTERS (search + plan dropdown) — scalable
  // ---------------------------------------------------------------------------
  Widget _filters() {
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            decoration: InputDecoration(
              hintText: "Search by plan, payment ID, UID...",
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (v) => ctrl.searchQuery.value = v,
          ),
        ),
        const SizedBox(width: 20),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // PAYMENTS TABLE
  // ---------------------------------------------------------------------------
  Widget _subscriptionTable() {
    return Obx(() {
      if (ctrl.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }

      final data = ctrl.filteredList;

      if (data.isEmpty) {
        return const Center(
          child: Text(
            "No subscriptions found.",
            style: TextStyle(color: Colors.grey),
          ),
        );
      }

      return _table(data);
    });
  }

  // ---------------------------------------------------------------------------
  // TABLE UI
  // ---------------------------------------------------------------------------
  Widget _table(List<SubscriptionModel> list) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardStyle(),
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(child: Text("Plan", style: _colStyle)),
              Expanded(child: Text("Paid", style: _colStyle)),
              Expanded(child: Text("Duration", style: _colStyle)),
              Expanded(child: Text("Payment ID", style: _colStyle)),
              Expanded(child: Text("Start", style: _colStyle)),
              Expanded(child: Text("Expiry", style: _colStyle)),
              SizedBox(width: 40),
            ],
          ),
          const Divider(),

          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => _row(list[i]),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLE ROW
  // ---------------------------------------------------------------------------
  Widget _row(SubscriptionModel s) {
    return InkWell(
      onTap: () => _detailsDialog(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(s.planName, style: _rowText())),
            Expanded(child: Text("₹${s.amountPaid}", style: _rowText())),
            Expanded(child: Text("${s.durationMonths} Months", style: _rowText())),
            Expanded(child: Text(s.paymentId, style: _paymentID())),
            Expanded(child: Text(_fmt(s.startAt))),
            Expanded(child: Text(_fmt(s.expiryAt))),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DETAILS DIALOG
  // ---------------------------------------------------------------------------
  void _detailsDialog(SubscriptionModel s) {
    Get.dialog(
      Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 80),
        child: Container(
          width: 650,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Subscription Details",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 20),

                _info("Plan Name", s.planName),
                _info("Admin UID", s.adminUid),
                _info("Admin Doc ID", s.adminDocId),
                const Divider(),

                _info("Amount Paid", "₹${s.amountPaid}"),
                _info("Original Amount", "₹${s.originalAmount}"),
                _info("Discount", "₹${s.discountAmount}"),
                _info("Coupon Applied", s.couponApplied ? "Yes" : "No"),
                if (s.couponApplied) _info("Coupon Code", s.couponCode ?? "-"),
                const Divider(),

                _info("Payment ID", s.paymentId),
                _info("Order ID", s.orderId ?? "-"),
                _info("Signature", s.signature ?? "-"),
                const Divider(),

                _info("Start Date", _fmt(s.startAt)),
                _info("Expiry Date", _fmt(s.expiryAt)),
                const Divider(),

                const Text("Usage Limits",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),

                _limit("Admins", s.maxAdmins),
                _limit("Trainers", s.maxTrainers),
                _limit("Clients", s.maxClients),
                _limit("Workout Plans", s.maxWorkoutPlans),
                _limit("Workouts", s.maxWorkouts),
                _limit("Diet Plans", s.maxDietPlans),

                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () => Get.back(),
                    child: const Text("Close"),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------
  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(label, style: _lblStyle())),
          Expanded(child: Text(value, style: _valStyle())),
        ],
      ),
    );
  }

  Widget _limit(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 180, child: Text(label)),
          Text(" : "),
          Text("$value", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => "${d.day}/${d.month}/${d.year}";

  BoxDecoration _cardStyle() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          blurRadius: 14,
          spreadRadius: 1,
          offset: const Offset(0, 5),
          color: Colors.black.withOpacity(.07),
        )
      ],
    );
  }

  static const _colStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 14,
  );

  TextStyle _rowText() => const TextStyle(fontSize: 14);

  TextStyle _paymentID() =>
      const TextStyle(fontSize: 13, color: Colors.blue, fontWeight: FontWeight.w600);

  TextStyle _lblStyle() =>
      const TextStyle(fontWeight: FontWeight.w600, fontSize: 14);

  TextStyle _valStyle() => const TextStyle(color: Colors.black87, fontSize: 14);
}
