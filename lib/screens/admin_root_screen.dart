// lib/screens/admin_root_screen.dart

import 'package:alphaserena_admin_portel/screens/top_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/admin_root_controller.dart';

/// =============================================================
/// RESPONSIVE UTIL
/// =============================================================
class Responsive {
  static bool isDesktop(BuildContext c) => MediaQuery.of(c).size.width >= 1200;
  static bool isTablet(BuildContext c) =>
      MediaQuery.of(c).size.width >= 900 && MediaQuery.of(c).size.width < 1200;
  static bool isMobile(BuildContext c) => MediaQuery.of(c).size.width < 900;
}

/// =============================================================
/// ADMIN ROOT SCREEN — PRODUCTION READY
/// =============================================================
class AdminRootScreen extends StatelessWidget {
  AdminRootScreen({super.key});

  final AdminRootController ctrl = Get.find<AdminRootController>();

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),

      // Drawer for mobile/tablet
      drawer: desktop ? null : const Drawer(child: SafeArea(child: _Sidebar())),

      body: SafeArea(
        child: Row(
          children: [
            if (desktop) const SizedBox(width: 260, child: _Sidebar()),

            /// ================= RIGHT PANEL =================
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  const TopNavBar(),
                  const SizedBox(height: 12),

                  /// ================= PAGE CONTENT =================
                  Expanded(
                    child: Obx(() {
                      final page = ctrl.currentPage;

                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: Container(
                          key: ValueKey(ctrl.selectedIndex.value),
                          padding: EdgeInsets.symmetric(
                            horizontal: desktop ? 24 : 12,
                            vertical: 12,
                          ),
                          child: page,
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// =============================================================
/// SIDEBAR
/// =============================================================
class _Sidebar extends StatelessWidget {
  const _Sidebar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminRootController>();
    final desktop = Responsive.isDesktop(context);

    final items = const [
      _MenuItem("Dashboard", Icons.dashboard),
      _MenuItem("Admins", Icons.admin_panel_settings),
      _MenuItem("Trainers", Icons.fitness_center),
      _MenuItem("Clients", Icons.people),
      _MenuItem("Subscriptions", Icons.subscriptions),
      _MenuItem("Payments", Icons.payment),
      _MenuItem("Coupon Codes", Icons.discount),
    ];

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          const _BrandHeader(),
          const SizedBox(height: 8),

          /// ================= MENU =================
          Expanded(
            child: Obx(() {
              final selected = ctrl.selectedIndex.value;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final isSelected = i == selected;

                  return InkWell(
                    onTap: () {
                      ctrl.changePage(i);
                      if (!desktop) Navigator.of(context).maybePop();
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue.shade50
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            items[i].icon,
                            color: isSelected
                                ? Colors.blue
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              items[i].title,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ),

          /// ================= FOOTER =================
          const Divider(height: 1),
          const _SidebarFooter(),
        ],
      ),
    );
  }
}

/// =============================================================
/// BRAND HEADER
/// =============================================================
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.fitness_center, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "TrainersHQ",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 2),
              Text(
                "Admin Panel",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// =============================================================
/// FOOTER (LOGOUT)
/// =============================================================
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminRootController>();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: Colors.grey.shade300,
          child: const Icon(Icons.person, color: Colors.white),
        ),
        title: const Text(
          "Master Admin",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text("master@company.com"),
        trailing: IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Logout"),
                content: const Text("Do you want to logout?"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await ctrl.logout(); // 🔥 centralized logout
                    },
                    child: const Text("Logout"),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// =============================================================
/// MENU MODEL
/// =============================================================
class _MenuItem {
  final String title;
  final IconData icon;

  const _MenuItem(this.title, this.icon);
}
