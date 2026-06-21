import 'package:alphaserena_admin_portel/widgets/admin_approvel_widget.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/dashboard_controller.dart';
import '../../widgets/page_shell.dart';

class DashboardScreenResponsive extends StatelessWidget {
  const DashboardScreenResponsive({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DashboardController>();

    return PageShell(
      title: "Dashboard",
      icon: Icons.dashboard_outlined,
      child: Obx(() {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kpis(ctrl),
              const SizedBox(height: 28),

              _revenueSection(ctrl),
              const SizedBox(height: 28),

              _alertsSection(ctrl),
              const SizedBox(height: 28),

              _insightsSection(ctrl),
            ],
          ),
        );
      }),
    );
  }

  // ============================================================
  // 🔥 KPI STRIP
  // ============================================================
  Widget _kpis(DashboardController ctrl) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _kpi(
          "Admins",
          ctrl.adminCount.value.toString(),
          Icons.admin_panel_settings,
          Colors.deepPurple,
        ),
        _kpi(
          "Trainers",
          ctrl.trainerCount.value.toString(),
          Icons.fitness_center,
          Colors.blue,
        ),
        _kpi(
          "Clients",
          ctrl.clientCount.value.toString(),
          Icons.people,
          Colors.green,
        ),
        _kpi(
          "Revenue",
          "₹${ctrl.revenue.value.toStringAsFixed(0)}",
          Icons.currency_rupee,
          Colors.orange,
        ),
        _kpi(
          "Growth",
          "${ctrl.revenueGrowth.value.toStringAsFixed(1)}%",
          Icons.trending_up,
          Colors.teal,
        ),
      ],
    );
  }

  Widget _kpi(String title, String value, IconData icon, Color color) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 📈 REVENUE
  // ============================================================
  Widget _revenueSection(DashboardController ctrl) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Revenue Overview",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),

          if (ctrl.revenueChart.isEmpty)
            const Center(child: Text("No revenue data"))
          else
            Column(
              children: ctrl.revenueChart.map((e) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [Text(e['month']), Text("₹${e['revenue']}")],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // ⚠️ ALERTS
  // ============================================================
  Widget _alertsSection(DashboardController ctrl) {
    return LayoutBuilder(
      builder: (_, box) {
        final isWide = box.maxWidth > 900;

        return isWide
            ? Row(
                children: [
                  Expanded(child: _expiring(ctrl)),
                  const SizedBox(width: 16),
                  Expanded(child: AdminApprovalWidget(ctrl: ctrl)),
                ],
              )
            : Column(
                children: [
                  _expiring(ctrl),
                  const SizedBox(height: 16),
                  AdminApprovalWidget(ctrl: ctrl),
                ],
              );
      },
    );
  }

  Widget _expiring(DashboardController ctrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Expiring Soon",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (ctrl.expiringAdmins.isEmpty)
            const Text("No expiring subscriptions")
          else
            ...ctrl.expiringAdmins.map((a) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a.name),
                subtitle: const Text("Expires soon"),
              );
            }),
        ],
      ),
    );
  }

  // Widget _requests(DashboardController ctrl) {
  //   return Container(
  //     padding: const EdgeInsets.all(16),
  //     decoration: _card(),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         const Text(
  //           "Pending Admin Requests",
  //           style: TextStyle(fontWeight: FontWeight.bold),
  //         ),
  //         const SizedBox(height: 12),

  //         if (ctrl.pendingAdminRequests.isEmpty)
  //           const Text("No requests")
  //         else
  //           ...ctrl.pendingAdminRequests.map((a) {
  //             return ListTile(
  //               contentPadding: EdgeInsets.zero,
  //               title: Text(a.name),
  //               trailing: TextButton(
  //                 onPressed: () => ctrl.updateAdminStatus(a.docId, "active"),
  //                 child: const Text("Approve"),
  //               ),
  //             );
  //           }),
  //       ],
  //     ),
  //   );
  // }

  // ============================================================
  // 🔥 INSIGHTS
  // ============================================================
  Widget _insightsSection(DashboardController ctrl) {
    return LayoutBuilder(
      builder: (_, box) {
        final isWide = box.maxWidth > 900;

        return isWide
            ? Row(
                children: [
                  Expanded(child: _topAdmins(ctrl)),
                  const SizedBox(width: 16),
                  Expanded(child: _activity(ctrl)),
                ],
              )
            : Column(
                children: [
                  _topAdmins(ctrl),
                  const SizedBox(height: 16),
                  _activity(ctrl),
                ],
              );
      },
    );
  }

  Widget _topAdmins(DashboardController ctrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Top Admins",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (ctrl.topAdmins.isEmpty)
            const Text("No data")
          else
            ...ctrl.topAdmins.map((a) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a['name'] ?? 'Admin'),
                trailing: Text("₹${a['revenue']}"),
              );
            }),
        ],
      ),
    );
  }

  Widget _activity(DashboardController ctrl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Recent Activity",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (ctrl.recentActivity.isEmpty)
            const Text("No activity")
          else
            ...ctrl.recentActivity.map((e) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e['title']),
                subtitle: Text(e['subtitle']),
              );
            }),
        ],
      ),
    );
  }

  // ============================================================
  BoxDecoration _card() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 10),
      ],
    );
  }
}
