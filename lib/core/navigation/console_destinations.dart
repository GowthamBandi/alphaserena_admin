// THE FOUNDER'S OPERATING MODEL, WRITTEN DOWN ONCE.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHAT THIS REPLACED, AND WHY IT MATTERED
// ─────────────────────────────────────────────────────────────────────────────
// The sidebar was a flat list of 18 entries in the order the screens were
// BUILT. That is a changelog, not an information architecture, and it read
// like one:
//
//   • Access Requests — the commercial intake queue, the first thing a founder
//     opens on a working day — was LAST, at index 17, because it shipped last.
//   • Operations Center — the triage home — sat at 10, between Audit Log and
//     Platform Staff.
//   • Settlements (money the platform holds FOR organizations) sat two rows
//     from Payments (TrainersArena's OWN revenue) with nothing saying they are
//     different kinds of money.
//   • Food Database and Exercise Library — content authoring, touched monthly —
//     outranked both.
//
// ─────────────────────────────────────────────────────────────────────────────
// WHY THE INTEGERS SURVIVE
// ─────────────────────────────────────────────────────────────────────────────
// `AdminRootController.selectedIndex` is an int, `_buildPage` is a switch on
// it, and OTHER SCREENS JUMP BY LITERAL: `OperationsController` carries
// `_navAdmins = 1`, `_navPayments = 5`, `_navSupport = 7`,
// `_navCommunication = 8`, and the dashboard carries `opsNavIndex = 10`.
// Renumbering to fix the ORDER would silently repoint every one of those jump
// targets at the wrong screen — a defect with no compile error and no visible
// symptom until a founder follows an alert to the wrong page.
//
// So the integer stays what it always was: a STABLE IDENTIFIER. What this file
// adds is that display order and grouping are no longer THE SAME THING as
// identity. [kConsoleSections] decides what the founder sees and in what order;
// [ConsoleDestination.id] decides which page opens. They are now independent,
// and `test/nav_reachability_test.dart` pins the relationship rather than
// assuming position == id.
//
// ─────────────────────────────────────────────────────────────────────────────
// THE RULE FOR ADDING A SECTION
// ─────────────────────────────────────────────────────────────────────────────
// Every section here is backed by collections and callables that EXIST. There
// is deliberately no "Security", "Configuration" or "Provisioning" section:
//
//   • Provisioning is not a place, it is the terminal transition of an access
//     request, so it lives inside Onboarding rather than pretending to be its
//     own destination.
//   • A Security/IAM section would need the permission engine that
//     `docs/platform-iam-architecture.md` marks as DESIGN ONLY — 11 roles and a
//     permission matrix that no backend implements. Platform Staff is the part
//     that is real, and it is read-only by construction (`master_admins` is
//     `allow write: if false`), so it sits under Governance where a read-only
//     surface belongs.
//   • System/Configuration would be a section of one — the tax table — which is
//     already reachable where a founder looks for it, inside Commercial.
//
// Do not add a section to make the sidebar look complete. An empty promise in
// a founder console is worse than an absence, because the founder plans around
// it.

import 'package:flutter/material.dart';

/// One reachable page in the console.
@immutable
class ConsoleDestination {
  const ConsoleDestination({
    required this.id,
    required this.label,
    required this.icon,
    required this.purpose,
  });

  /// The page index `AdminRootController._buildPage` switches on.
  ///
  /// STABLE AND LOAD-BEARING. Other controllers jump to these literals; see
  /// the file header. Never renumber to reorder — reorder [kConsoleSections].
  final int id;

  /// What the founder reads in the sidebar.
  final String label;

  final IconData icon;

  /// One line answering "what am I looking at?" — surfaced as the sidebar
  /// tooltip and available to page headers, so the answer lives with the
  /// destination instead of being retyped per screen.
  final String purpose;
}

/// A group of destinations that a founder thinks about together.
@immutable
class ConsoleSection {
  const ConsoleSection({
    required this.title,
    required this.destinations,
  });

  final String title;
  final List<ConsoleDestination> destinations;
}

/// The console's information architecture, in the order a founder works.
///
/// Ordered by HOW OFTEN THE ANSWER CHANGES and how urgently it matters —
/// today's triage first, monthly content authoring last.
const List<ConsoleSection> kConsoleSections = <ConsoleSection>[
  // ── 1. What needs me right now ────────────────────────────────────────────
  ConsoleSection(
    title: 'Command Center',
    destinations: [
      ConsoleDestination(
        id: 0,
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        purpose: 'Platform health at a glance — organizations, revenue, growth',
      ),
      ConsoleDestination(
        id: 10,
        label: 'Operations Center',
        icon: Icons.monitor_heart_outlined,
        purpose: 'Everything that needs a decision today, in one queue',
      ),
    ],
  ),

  // ── 2. Turning prospects into paying organizations ────────────────────────
  // Provisioning is the terminal transition of a request, not a separate
  // destination, so it lives here rather than in a section of its own.
  ConsoleSection(
    title: 'Onboarding',
    destinations: [
      ConsoleDestination(
        id: 17,
        label: 'Access Requests',
        icon: Icons.mark_email_unread_outlined,
        purpose: 'Prospect intake through payment to a provisioned organization',
      ),
    ],
  ),

  // ── 3. Who is on the platform ─────────────────────────────────────────────
  // `admins/{uid}` IS the organization record; `organizationProfiles/{uid}` is
  // only its public storefront. So this reads "Organizations", not "Admins" —
  // the owner is a facet of the organization, not a separate population.
  ConsoleSection(
    title: 'Tenants',
    destinations: [
      ConsoleDestination(
        id: 1,
        label: 'Organizations',
        icon: Icons.corporate_fare_outlined,
        purpose: 'Every organization, its owner, plan, entitlement and standing',
      ),
      ConsoleDestination(
        id: 2,
        label: 'Trainers',
        icon: Icons.fitness_center_outlined,
        purpose: 'Coaching staff across every organization (read-only)',
      ),
      ConsoleDestination(
        id: 3,
        label: 'Members',
        icon: Icons.people_outline,
        purpose: 'End members across every organization (read-only)',
      ),
    ],
  ),

  // ── 4. Money ──────────────────────────────────────────────────────────────
  // Two kinds of money share this section but never a screen. Plans, Payments
  // and Coupons are SYSTEM A — TrainersArena's own subscription revenue.
  // Settlements is SYSTEM B — member money the platform holds on an
  // organization's behalf, a LIABILITY. A founder reading a combined total
  // would be reading their income and somebody else's money as one number.
  ConsoleSection(
    title: 'Commercial',
    destinations: [
      ConsoleDestination(
        id: 4,
        label: 'Plans',
        icon: Icons.subscriptions_outlined,
        purpose: 'The SaaS plan catalog organizations are sold — and its taxes',
      ),
      ConsoleDestination(
        id: 5,
        label: 'Revenue',
        icon: Icons.payments_outlined,
        purpose: 'What organizations have paid TrainersArena (System A)',
      ),
      ConsoleDestination(
        id: 6,
        label: 'Coupons',
        icon: Icons.discount_outlined,
        purpose: 'Discount codes against the plan catalog',
      ),
      ConsoleDestination(
        id: 14,
        label: 'Settlements',
        icon: Icons.account_balance_outlined,
        purpose: 'Member money owed OUT to organizations (System B — a liability)',
      ),
    ],
  ),

  // ── 5. Reaching and understanding organizations ───────────────────────────
  ConsoleSection(
    title: 'Engagement',
    destinations: [
      ConsoleDestination(
        id: 8,
        label: 'Announcements',
        icon: Icons.campaign_outlined,
        purpose: 'Platform-wide messages, scheduled or sent now',
      ),
      ConsoleDestination(
        id: 15,
        label: 'Automation',
        icon: Icons.bolt_outlined,
        purpose: 'Which automated triggers are armed, and their kill switches',
      ),
      ConsoleDestination(
        id: 16,
        label: 'Intelligence',
        icon: Icons.insights_outlined,
        purpose: 'Engagement and retention signals across organizations',
      ),
      ConsoleDestination(
        id: 7,
        label: 'Support',
        icon: Icons.support_agent_outlined,
        purpose: 'Feedback and support threads raised by organizations',
      ),
    ],
  ),

  // ── 6. Content every organization consumes ────────────────────────────────
  ConsoleSection(
    title: 'Content Library',
    destinations: [
      ConsoleDestination(
        id: 12,
        label: 'Food Database',
        icon: Icons.restaurant_menu_outlined,
        purpose: 'The global food catalog every organization reads',
      ),
      ConsoleDestination(
        id: 13,
        label: 'Exercise Library',
        icon: Icons.sports_gymnastics_outlined,
        purpose: 'The global exercise catalog every organization reads',
      ),
    ],
  ),

  // ── 7. Who did what, and who may ──────────────────────────────────────────
  ConsoleSection(
    title: 'Governance',
    destinations: [
      ConsoleDestination(
        id: 9,
        label: 'Audit Log',
        icon: Icons.receipt_long_outlined,
        purpose: 'Every privileged action taken on the platform, by whom',
      ),
      ConsoleDestination(
        id: 11,
        label: 'Platform Staff',
        icon: Icons.shield_outlined,
        purpose: 'Who holds super-admin authority (read-only by design)',
      ),
      ConsoleDestination(
        id: 18,
        label: 'Crash Reports',
        icon: Icons.bug_report_outlined,
        purpose: 'The console\'s own crash and error records, newest first',
      ),
    ],
  ),
];

/// Every destination, flattened, in sidebar order.
List<ConsoleDestination> get kConsoleDestinations =>
    [for (final s in kConsoleSections) ...s.destinations];

/// The destination for a page index, or null if the index routes to nothing.
ConsoleDestination? destinationForId(int id) {
  for (final s in kConsoleSections) {
    for (final d in s.destinations) {
      if (d.id == id) return d;
    }
  }
  return null;
}
