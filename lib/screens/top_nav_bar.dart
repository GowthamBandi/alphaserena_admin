import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Top navigation bar (constant across pages)
class TopNavBar extends StatelessWidget {
  const TopNavBar({super.key});

  void _onProfileTap(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 16, 0),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.person),
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
              // Replace with real logout
              Get.defaultDialog(
                  title: "Logout",
                  middleText: "Confirm logout?",
                  textCancel: "Cancel",
                  textConfirm: "Logout",
                  onConfirm: () {
                    Get.back();
                    Get.snackbar("Logged out", "User logged out (hook your auth logic).");
                  });
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = Responsive.isDesktop(context);
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search anything...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade100,
                isDense: true,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(onPressed: () => Get.snackbar("Notifications", "Open notifications (not implemented)"), icon: const Icon(Icons.notifications_outlined)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _onProfileTap(context),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey.shade300,
              child: const Icon(Icons.person, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
