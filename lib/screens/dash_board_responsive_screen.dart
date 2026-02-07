import 'package:alphaserena_admin_portel/widgets/page_shell.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/dashboard_controller.dart';
import '../../models/admin_model.dart';

class DashboardScreenResponsive extends StatelessWidget {
  const DashboardScreenResponsive({super.key});

  Widget kpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            spreadRadius: -2,
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  String _fmtCurrency(double v) {
    if (v >= 1e7) {
      return '₹${(v / 1e7).toStringAsFixed(2)} Cr';
    } else if (v >= 1e5) {
      return '₹${(v / 1e5).toStringAsFixed(2)} L';
    } else {
      return '₹${v.toStringAsFixed(0)}';
    }
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    if (d is DateTime) {
      final dt = d;
      return "${dt.day}/${dt.month}/${dt.year}";
    }
    if (d is Timestamp) {
      final dt = d.toDate();
      return "${dt.day}/${dt.month}/${dt.year}";
    }
    try {
      final dt = DateTime.tryParse(d.toString());
      if (dt != null) return "${dt.day}/${dt.month}/${dt.year}";
    } catch (_) {}
    return d.toString();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(DashboardController());

    return PageShell(
      title: "Dashboard",
      icon: Icons.dashboard_outlined,
      child: LayoutBuilder(
        builder: (context, box) {
          final isMobile = box.maxWidth < 650;
          final isTablet = box.maxWidth < 1100 && box.maxWidth >= 650;

          return Obx(() {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KPI section → auto wrap
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    kpiCard("Admins", "${ctrl.adminCount.value}", Icons.admin_panel_settings, Colors.deepPurple),
                    kpiCard("Trainers", "${ctrl.trainerCount.value}", Icons.fitness_center, Colors.blue),
                    kpiCard("Clients", "${ctrl.clientCount.value}", Icons.people, Colors.green),
                    kpiCard("Revenue", "${_fmtCurrency(ctrl.revenue.value)}", Icons.currency_rupee, Colors.orange),
                  ],
                ),

                const SizedBox(height: 30),

                // Activity + Requests → responsive layout
                if (!isMobile) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Recent Requests
                      Expanded(child: _recentRequestsCard(ctrl)),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: isTablet ? 340 : 420,
                        child: _activityCard(ctrl),
                      ),
                    ],
                  ),
                ] else ...[
                  _recentRequestsCard(ctrl),
                  const SizedBox(height: 16),
                  _activityCard(ctrl),
                ],
              ],
            );
          });
        },
      ),
    );
  }

  Widget _recentRequestsCard(DashboardController ctrl) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
          )
        ],
      ),
      child: Obx(() {
        final list = ctrl.pendingAdminRequests;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text("Pending Admin Requests", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text("${list.length}", style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text("No pending requests", style: TextStyle(color: Colors.grey.shade600))),
              )
            else
              ...list.take(6).map((a) => _requestRow(a, ctrl)).toList(),
          ],
        );
      }),
    );
  }

  Widget _requestRow(AdminModel a, DashboardController ctrl) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(radius: 20, child: Text(a.name.isNotEmpty ? a.name[0].toUpperCase() : 'A')),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(a.email, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => ctrl.updateAdminStatus(a.docId, "approved"),
              child: const Text("Approve"),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => ctrl.updateAdminStatus(a.docId, "blocked"),
              child: const Text("Reject"),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(),
      ],
    );
  }

  Widget _activityCard(DashboardController ctrl) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
          )
        ],
      ),
      child: Obx(() {
        final act = ctrl.recentActivity;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Recent Activity", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (act.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text("No recent activity", style: TextStyle(color: Colors.grey.shade600))),
              )
            else
              ...act.map((e) {
                final title = e['title'] ?? 'User';
                final subtitle = e['subtitle'] ?? '';
                final time = e['time'];
                final timeStr = _fmtDate(time);
                return Column(
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
                      title: Text("$title $subtitle"),
                      subtitle: Text(timeStr, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ),
                    const Divider(),
                  ],
                );
              }).toList(),
          ],
        );
      }),
    );
  }
}
