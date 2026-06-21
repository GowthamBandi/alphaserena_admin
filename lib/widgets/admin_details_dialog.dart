// lib/widgets/admin_details_dialog.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/admin_model.dart';
import '../controllers/admin_analytics_controller.dart';

class AdminDetailsDialog extends StatelessWidget {
  final AdminModel admin;

  const AdminDetailsDialog({super.key, required this.admin});

  @override
  Widget build(BuildContext context) {
    final analytics = Get.put(AdminAnalyticsController(admin.uid));

    final limits = admin.subscriptionLimits;
    final sub = admin.subscription ?? {};

    return Dialog(
      backgroundColor: const Color(0xffF4F6FA),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          children: [
            _header(),

            Expanded(
              child: Obx(() {
                if (analytics.isLoading.value) {
                  return const Center(child: CircularProgressIndicator());
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _profileHero(),
                      const SizedBox(height: 16),

                      _infoGrid(),
                      const SizedBox(height: 16),

                      _subscriptionSection(sub),
                      const SizedBox(height: 16),

                      _limitsSection(limits),
                      const SizedBox(height: 16),

                      _usageSection(analytics, limits),
                      const SizedBox(height: 16),

                      _relationsSection(),
                      const SizedBox(height: 16),

                      _metaSection(),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics),
          const SizedBox(width: 10),
          const Text(
            "Admin Intelligence Panel",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HERO PROFILE
  // ============================================================
  Widget _profileHero() {
    return _card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.blue.shade100,
            child: Text(admin.name.isNotEmpty ? admin.name[0] : "?"),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  admin.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(admin.email),
                Text(admin.phone),
                Text(
                  admin.organizationName,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),

          Column(
            children: [
              _statusBadge(admin.status),
              const SizedBox(height: 6),
              if (admin.isVerified) const Chip(label: Text("Verified")),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFO GRID
  // ============================================================
  Widget _infoGrid() {
    return _gridCard([
      _info("Role", admin.role),
      _info("GST", admin.gstNumber ?? "-"),
      _info("PAN", admin.panNumber ?? "-"),
      _info("Languages", admin.spokenLanguages.join(", ")),
      _info("State", admin.state ?? "-"),
      _info("Area", admin.area ?? "-"),
      _info("Pincode", admin.pincode ?? "-"),
    ]);
  }

  // ============================================================
  // 💳 SUBSCRIPTION (REAL DATA)
  // ============================================================
  Widget _subscriptionSection(Map sub) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Billing & Subscription",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          _row("Plan", admin.planName ?? "-"),
          _row("Status", admin.isSubscriptionActive ? "Active" : "Inactive"),

          _row("Purchased On", admin.createdAt.toString()),
          _row("Expiry", admin.planExpiry?.toString() ?? "-"),

          _row("Price Paid", sub['pricePaid']?.toString() ?? "-"),
          _row("Payment ID", sub['paymentId'] ?? "-"),

          _row("Coupon", sub['couponCode'] ?? "No"),
          _row("Discount", sub['discount']?.toString() ?? "0"),
        ],
      ),
    );
  }

  // ============================================================
  // LIMITS
  // ============================================================
  Widget _limitsSection(AdminSubscriptionLimits l) {
    return _gridCard([
      _info("Max Trainers", "${l.maxTrainers}"),
      _info("Max Clients", "${l.maxClients}"),
      _info("Max Workouts", "${l.maxWorkoutPlans}"),
      _info("Max Diet Plans", "${l.maxDietPlans}"),
    ]);
  }

  // ============================================================
  // 🔥 LIVE USAGE
  // ============================================================
  Widget _usageSection(AdminAnalyticsController a, AdminSubscriptionLimits l) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Live Usage",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          _usage("Trainers", a.trainers.value, l.maxTrainers),
          _usage("Clients", a.clients.value, l.maxClients),
          _usage("Workouts", a.workouts.value, l.maxWorkoutPlans),
          _usage("Diet Plans", a.dietPlans.value, l.maxDietPlans),
        ],
      ),
    );
  }

  // ============================================================
  // RELATIONS
  // ============================================================
  Widget _relationsSection() {
    return _gridCard([
      _info("Total Trainers", admin.trainerIds.length.toString()),
      _info("Total Clients", admin.clientIds.length.toString()),
    ]);
  }

  // ============================================================
  // META
  // ============================================================
  Widget _metaSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "System Metadata",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          _row("UID", admin.uid),
          _row("Created", admin.createdAt.toString()),
          _row("Updated", admin.updatedAt.toString()),
          _row("Last Login", admin.lastLogin?.toString() ?? "-"),
          _row("Approved By", admin.approvedBy ?? "-"),
        ],
      ),
    );
  }

  // ============================================================
  // USAGE BAR
  // ============================================================
  Widget _usage(String label, int used, int max) {
    final progress = max == 0 ? 0.0 : (used / max).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(children: [Text(label), const Spacer(), Text("$used / $max")]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }

  // ============================================================
  // UI HELPERS
  // ============================================================
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(blurRadius: 14, color: Colors.black.withOpacity(.05)),
        ],
      ),
      child: child,
    );
  }

  Widget _gridCard(List<Widget> children) {
    return _card(
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: children.map((e) => SizedBox(width: 260, child: e)).toList(),
      ),
    );
  }

  Widget _info(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _row(String l, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(l)),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color =
        {
          "active": Colors.green,
          "pending": Colors.orange,
          "blocked": Colors.red,
        }[status] ??
        Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status.toUpperCase(), style: TextStyle(color: color)),
    );
  }
}
