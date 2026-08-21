// lib/screens/admin_root_screen.dart

import 'package:alphaserena_admin_portel/core/controllers/session_controller.dart';
import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/screens/top_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/admin_root_controller.dart';
import '../core/navigation/console_destinations.dart';

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
      drawer: desktop ? null : const Drawer(child: SafeArea(child: ConsoleSidebar())),

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
                child: const ConsoleSidebar(),
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
///
/// PUBLIC so a widget test can drive the REAL sidebar. It was private, and the
/// first attempt at a render test reconstructed its flattening in the test
/// file instead — which promptly failed on an overflow the production widget
/// does not have, because the copy had drifted within minutes of being written.
/// A navigation test that exercises a replica proves nothing about the sidebar
/// the founder uses.
class ConsoleSidebar extends StatelessWidget {
  const ConsoleSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AdminRootController>();
    final desktop = Responsive.isDesktop(context);

    final p = context.palette;

    // The rows to render: section headers interleaved with their destinations,
    // flattened once so a single ListView can virtualise the whole sidebar.
    // Built from `kConsoleSections`, which is the ONLY place order and grouping
    // are decided — see lib/core/navigation/console_destinations.dart.
    final rows = <_SidebarRow>[
      for (final section in kConsoleSections) ...[
        _SidebarRow.header(section.title),
        for (final d in section.destinations) _SidebarRow.destination(d),
      ],
    ];

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
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final row = rows[i];

                if (row.header != null) {
                  return Padding(
                    // Generous lead-in above a header, tight below it, so a
                    // header reads as attached to the group it names rather
                    // than floating between two of them.
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: i == 0 ? 4 : 18,
                      bottom: 6,
                    ),
                    child: Text(
                      row.header!.toUpperCase(),
                      style: AppText.label(size: 11).copyWith(
                        color: p.textMuted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  );
                }

                final d = row.destination!;
                final isSelected = d.id == selected;

                return _SidebarTile(
                  destination: d,
                  isSelected: isSelected,
                  onTap: () {
                    ctrl.changePage(d.id);
                    if (!desktop) Navigator.of(context).maybePop();
                  },
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

/// One flattened sidebar row: either a section header or a destination.
@immutable
class _SidebarRow {
  const _SidebarRow.header(this.header) : destination = null;
  const _SidebarRow.destination(this.destination) : header = null;

  final String? header;
  final ConsoleDestination? destination;
}

/// A single navigable row.
///
/// Extracted from the builder closure so the selected/unselected treatment is
/// defined ONCE. It previously lived inline, which is how a sidebar ends up
/// with two subtly different hover states.
class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final ConsoleDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Semantics(
      button: true,
      selected: isSelected,
      label: destination.label,
      // The purpose line is announced to a screen reader, which otherwise gets
      // a bare noun ("Settlements") with no way to tell it from Revenue.
      hint: destination.purpose,
      // The label is supplied above, so the child `Text` must not ALSO
      // contribute one — without this the node merges to "Settlements
      // Settlements" and a screen reader says the name twice on every row.
      excludeSemantics: true,
      // ⚠️ LOAD-BEARING, AND THE REASON THE LINE ABOVE IS SAFE.
      //
      // `excludeSemantics` drops the WHOLE subtree — including the InkWell's
      // tap ACTION and its focus node. Without this line the row still
      // ANNOUNCES as a button (button: true, above) while offering assistive
      // technology no way to activate it: the exact "Semantics(button) with no
      // onTap" shape this codebase has shipped four times. A pointer tap keeps
      // working, so a widget test that taps by finder cannot see the defect —
      // which is why `console_sidebar_test.dart` asserts SemanticsAction.tap
      // is PRESENT, not merely that tapping works.
      onTap: onTap,
      child: Tooltip(
        message: destination.purpose,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.smR,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: isSelected
                  ? p.accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: AppRadii.smR,
            ),
            child: Row(
              children: [
                Icon(
                  destination.icon,
                  size: 20,
                  color: isSelected ? p.accent : p.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
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
        ),
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

// The menu model used to live here as a private `_MenuItem`, which made the
// sidebar the SOURCE of the navigation model rather than a renderer of it.
// It now lives in lib/core/navigation/console_destinations.dart, so grouping
// and order are decided in one reviewable place and page identity (the integer
// other controllers jump to) is decoupled from display position.
