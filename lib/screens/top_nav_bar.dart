import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Top navigation bar (constant across pages).
class TopNavBar extends StatelessWidget {
  const TopNavBar({super.key});

  void _onProfileTap(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 16, 0),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text("Profile"),
            onTap: () {
              Navigator.pop(context);
              Get.snackbar("Profile", "Open profile screen (not implemented)");
            },
          ),
        ),
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.logout_outlined),
            title: const Text("Logout"),
            onTap: () {
              Navigator.pop(context);
              Get.defaultDialog(
                  title: "Logout",
                  middleText: "Confirm logout?",
                  textCancel: "Cancel",
                  textConfirm: "Logout",
                  onConfirm: () {
                    Get.back();
                    Get.find<AdminRootController>().logout();
                  });
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bool isDesktop = Responsive.isDesktop(context);

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu, color: p.textSecondary),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search anything...",
                prefixIcon: Icon(Icons.search, color: p.textMuted),
                filled: true,
                fillColor: p.inputFill,
                isDense: true,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: AppRadii.smR,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => Get.snackbar(
                "Notifications", "Open notifications (not implemented)"),
            icon: Icon(Icons.notifications_outlined, color: p.textSecondary),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _onProfileTap(context),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: p.accent.withValues(alpha: 0.12),
              child: Icon(Icons.person, color: p.accent),
            ),
          ),
        ],
      ),
    );
  }
}
