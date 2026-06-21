// lib/screens/admin_root_screen.dart

import 'package:alphaserena_admin_portel/core/controllers/session_controller.dart';
import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
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
/// ADMIN ROOT SCREEN — console shell (design-system themed)
/// =============================================================
class AdminRootScreen extends StatelessWidget {
  AdminRootScreen({super.key});

  final AdminRootController ctrl = Get.find<AdminRootController>();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final desktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: p.background,

      // Drawer for mobile/tablet.
      drawer: desktop ? null : const Drawer(child: SafeArea(child: _Sidebar())),

      body: SafeArea(
        child: Row(
          children: [
            if (desktop)
              Container(
                width: 260,
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(right: BorderSide(color: p.border)),
                ),
                child: const _Sidebar(),
              ),

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
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminRootController>();
    final desktop = Responsive.isDesktop(context);

    final items = const [
      _MenuItem("Dashboard", Icons.dashboard_outlined),
      _MenuItem("Admins", Icons.admin_panel_settings_outlined),
      _MenuItem("Trainers", Icons.fitness_center_outlined),
      _MenuItem("Clients", Icons.people_outline),
      _MenuItem("Subscriptions", Icons.subscriptions_outlined),
      _MenuItem("Payments", Icons.payments_outlined),
      _MenuItem("Coupon Codes", Icons.discount_outlined),
    ];

    final p = context.palette;

    return Column(
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
                  borderRadius: AppRadii.smR,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? p.accent.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: AppRadii.smR,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          items[i].icon,
                          size: 20,
                          color: isSelected ? p.accent : p.textMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            items[i].title,
                            style: AppText.label(size: 14).copyWith(
                              color: isSelected ? p.accent : p.textSecondary,
                              fontWeight:
                                  isSelected ? FontWeight.w700 : FontWeight.w500,
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
        Divider(height: 1, color: p.border),
        const _SidebarFooter(),
      ],
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
    final p = context.palette;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: BrandColors.selectedGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: AppRadii.smR,
            ),
            child: const Icon(Icons.bolt, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "AlphaSerena",
                  style: AppText.cardTitle(size: 16)
                      .copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  "Founder Console",
                  style: AppText.body(size: 11).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// =============================================================
/// FOOTER (LOGGED-IN USER + LOGOUT)
/// =============================================================
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter();

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminRootController>();
    final p = context.palette;

    // Show the real signed-in founder's email.
    final email =
        Get.find<SessionController>().user.value?.email ?? 'Signed in';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: p.accent.withValues(alpha: 0.12),
          child: Icon(Icons.person, color: p.accent),
        ),
        title: Text(
          "Super Admin",
          style: AppText.label(size: 14).copyWith(color: p.textPrimary),
        ),
        subtitle: Text(
          email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.body(size: 11).copyWith(color: p.textMuted),
        ),
        trailing: IconButton(
          tooltip: 'Logout',
          icon: Icon(Icons.logout, color: p.textMuted),
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
                      await ctrl.logout(); // RootGate reacts → login screen
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
