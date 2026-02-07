// lib/screens/admin_root_screen.dart
import 'package:alphaserena_admin_portel/screens/admins_screen.dart';
import 'package:alphaserena_admin_portel/screens/clients_screen.dart';
import 'package:alphaserena_admin_portel/screens/coupon_code_screen.dart';
import 'package:alphaserena_admin_portel/screens/dash_board_responsive_screen.dart';
import 'package:alphaserena_admin_portel/screens/payments_screen.dart';
import 'package:alphaserena_admin_portel/screens/subscriptions_screen.dart';
import 'package:alphaserena_admin_portel/screens/top_nav_bar.dart';
import 'package:alphaserena_admin_portel/screens/trainers_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// AdminRootController - keeps track of selected page index
class AdminRootController extends GetxController {
  final selectedIndex = 0.obs;
  void changePage(int index) => selectedIndex.value = index;
}

/// Simple responsive helpers
class Responsive {
  static bool isDesktop(BuildContext c) => MediaQuery.of(c).size.width >= 1200;
  static bool isTablet(BuildContext c) =>
      MediaQuery.of(c).size.width >= 900 && MediaQuery.of(c).size.width < 1200;
  static bool isMobile(BuildContext c) => MediaQuery.of(c).size.width < 900;
}

/// Main root screen - contains sidebar + topbar + dynamic content
class AdminRootScreen extends StatelessWidget {
  AdminRootScreen({super.key});

  final AdminRootController ctrl = Get.put(AdminRootController());

  // // ignore: library_private_types_in_public_api
  // final List<_MenuItem> menuItems = const [
  //   _MenuItem("Dashboard", Icons.dashboard),
  //   _MenuItem("Admins", Icons.admin_panel_settings),
  //   _MenuItem("Trainers", Icons.fitness_center),
  //   _MenuItem("Clients", Icons.people),
  //   _MenuItem("Subscriptions", Icons.payment),_MenuItem("Coupon codes", Icons.discount),
  //   _MenuItem("Subscriptions", Icons.subscriptions),
  // ];

  // Placeholder widgets for each menu entry - replace with real screens later.
  final List<Widget> pages = [
    const DashboardScreenResponsive(),
    AdminsScreen(),
     TrainersScreen(),
    const ClientsScreen(),
    SubscriptionsScreen(),
     PaymentsScreen(),
    CouponCodeScreen() 
   
  ];

  @override
  Widget build(BuildContext context) {
    final bool desktop = Responsive.isDesktop(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      // On mobile/tablet a Drawer is used; on desktop show permanent sidebar
      drawer: desktop ? null : Drawer(child: SafeArea(child: _Sidebar())),
      body: SafeArea(
        child: Row(
          children: [
            if (desktop) SizedBox(width: 260, child: _Sidebar()),

            // Right side (topbar + dynamic content)
            Expanded(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  const TopNavBar(),
                  const SizedBox(height: 12),

                  // Body: dynamic content that changes per selection
                  Expanded(
                    child: Obx(() {
                      final int idx = ctrl.selectedIndex.value;
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: Container(
                          key: ValueKey<int>(idx),
                          padding: EdgeInsets.symmetric(
                            horizontal: desktop ? 24 : 12,
                            vertical: 12,
                          ),
                          child: pages[idx],
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

/// Simple menu item data
class _MenuItem {
  final String title;
  final IconData icon;
  const _MenuItem(this.title, this.icon);
}

/// Sidebar widget
class _Sidebar extends StatelessWidget {
  const _Sidebar({Key? key}) : super(key: key);

  Widget _brandHeader() {
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10)],
            ),
            child: const Icon(Icons.fitness_center, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("TrainersHQ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                SizedBox(height: 2),
                Text("Admin Panel", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AdminRootController ctrl = Get.find();
    final bool desktop = Responsive.isDesktop(context);

    final items = const [
      _MenuItem("Dashboard", Icons.dashboard),
      _MenuItem("Admins", Icons.admin_panel_settings),
      _MenuItem("Trainers", Icons.fitness_center),
      _MenuItem("Clients", Icons.people),
     
      // _MenuItem("Coupons", Icons.card_giftcard),
      _MenuItem("Subscriptions", Icons.subscriptions),
       _MenuItem("Payments", Icons.payment),
        _MenuItem("Coupon Codes", Icons.discount),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _brandHeader(),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text("MAIN", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ),
          const SizedBox(height: 6),
          Obx(() {
            final selected = ctrl.selectedIndex.value;
            return Column(
              children: List.generate(items.length, (i) {
                final isSelected = i == selected;
                return InkWell(
                  onTap: () {
                    ctrl.changePage(i);
                    // close drawer on mobile after selection
                    if (!desktop) Navigator.of(context).maybePop();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(items[i].icon, color: isSelected ? Colors.blue : Colors.grey.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            items[i].title,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? Colors.blue.shade700 : Colors.grey.shade900,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Container(
                            height: 24,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(child: Text("Active", style: TextStyle(fontSize: 11))),
                          )
                      ],
                    ),
                  ),
                );
              }),
            );
          }),
          const Spacer(),

          // Footer quick items (responsive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                const Divider(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 18, backgroundColor: Colors.grey.shade300, child: const Icon(Icons.person, color: Colors.white)),
                  title: const Text("Master Admin", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("master@company.com", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  trailing: IconButton(
                    onPressed: () {
                      // Quick logout (you should replace with real auth logout)
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text("Logout"),
                          content: const Text("Do you want to logout?"),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                // Add your actual logout logic here (e.g. FirebaseAuth.instance.signOut())
                                Get.snackbar("Logged out", "User has been logged out.");
                              },
                              child: const Text("Logout"),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.logout),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}







