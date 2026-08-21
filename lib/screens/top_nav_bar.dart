import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/core/controllers/session_controller.dart';
import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'legal/legal_screen.dart';

/// Top navigation bar (constant across pages).
///
/// ── WHAT WAS REMOVED, AND WHY ───────────────────────────────────────────
/// This bar used to carry three controls that did nothing:
///
///   • a "Search anything…" TextField with no controller, no `onChanged` and
///     no `onSubmitted` — the most prominent affordance in the console, inert
///     on every screen;
///   • a notification bell that raised `Get.snackbar("…not implemented")`;
///   • a Profile menu item that did the same.
///
/// A founder console that ships controls which announce their own absence
/// teaches its only user that the interface cannot be trusted — and a search
/// box that silently swallows typing is worse than no search box, because the
/// founder concludes the platform has no matching organization.
///
/// They are gone rather than stubbed. What replaced the search field is the
/// one thing this bar can state truthfully and usefully: WHICH ACCOUNT is
/// signed in. Global search is a real feature and belongs in a change that
/// actually builds it.
class TopNavBar extends StatelessWidget {
  const TopNavBar({super.key});

  void _onProfileTap(BuildContext context) {
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 16, 0),
      items: [
        PopupMenuItem(
          child: ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text("Legal & About"),
            onTap: () {
              Navigator.pop(context);
              AdminLegalScreen.open();
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
                },
              );
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
          const Spacer(),
          // The signed-in identity. Real, and worth stating: this console is
          // god-mode over every organization on the platform, so "which
          // account am I in" is a question the chrome should answer without
          // being asked.
          Flexible(
            child: Obx(() {
              final email = Get.find<SessionController>().user.value?.email;
              if (email == null || email.isEmpty) {
                return const SizedBox.shrink();
              }
              return Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              );
            }),
          ),
          const SizedBox(width: 12),
          // The ONLY route to Logout below 1200px, where the sidebar (and its
          // properly-labelled logout IconButton) collapses into a drawer.
          //
          // It was a bare GestureDetector on a CircleAvatar: no semantics, no
          // tooltip, and not focusable — so a keyboard-only or screen-reader
          // operator could not sign out of a god-mode console at all. Tooltip +
          // InkWell restore the label, the button role, keyboard focus and
          // Enter/Space activation.
          Tooltip(
            message: 'Account menu — legal, about and sign out',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _onProfileTap(context),
                customBorder: const CircleBorder(),
                child: Semantics(
                  button: true,
                  label: 'Account menu',
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: p.accent.withValues(alpha: 0.12),
                    child: Icon(Icons.person, color: p.accent),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
