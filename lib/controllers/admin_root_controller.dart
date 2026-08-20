import 'dart:async';
import 'dart:developer';
import 'package:alphaserena_admin_portel/screens/admins_screen.dart';
import 'package:alphaserena_admin_portel/screens/audit_log_screen.dart';
import 'package:alphaserena_admin_portel/screens/automation_screen.dart';
import 'package:alphaserena_admin_portel/screens/engagement_intelligence_screen.dart';
import 'package:alphaserena_admin_portel/screens/clients_screen.dart';
import 'package:alphaserena_admin_portel/screens/communication_screen.dart';
import 'package:alphaserena_admin_portel/screens/coupon_code_screen.dart';
import 'package:alphaserena_admin_portel/screens/dash_board_responsive_screen.dart';
import 'package:alphaserena_admin_portel/screens/global_exercise_screen.dart';
import 'package:alphaserena_admin_portel/screens/global_food_screen.dart';
import 'package:alphaserena_admin_portel/screens/operations_screen.dart';
import 'package:alphaserena_admin_portel/screens/payments_screen.dart';
import 'package:alphaserena_admin_portel/screens/platform_staff_screen.dart';
import 'package:alphaserena_admin_portel/screens/settlement_screen.dart';
import 'package:alphaserena_admin_portel/screens/access_requests_screen.dart';
import 'package:alphaserena_admin_portel/screens/subscriptions_screen.dart';
import 'package:alphaserena_admin_portel/screens/support_screen.dart';
import 'package:alphaserena_admin_portel/screens/trainers_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ============================================================================
/// ADMIN ROOT CONTROLLER — MASTER ADMIN PANEL (PRODUCTION GRADE)
/// Handles:
/// - Navigation state
/// - Lazy page loading
/// - Page caching
/// - Session safety
/// - Logout
/// - UI sync
/// ============================================================================
class AdminRootController extends GetxController {
  // ===========================================================================
  // CORE SERVICES
  // ===========================================================================
  // Resolved LAZILY so the console shell and its screens can be constructed in
  // a widget test without an initialized Firebase app. Matches the controllers
  // that already do this.
  late final FirebaseAuth _auth = FirebaseAuth.instance;

  // ===========================================================================
  // NAVIGATION STATE
  // ===========================================================================
  final RxInt selectedIndex = 0.obs;

  /// Prevent invalid index crashes. MUST equal the last sidebar entry — a
  /// mismatch is how a finished screen ends up shipped and unreachable.
  /// `test/nav_reachability_test.dart` pins the two together.
  final int maxIndex = 17;

  // ===========================================================================
  // PAGE CACHE (LAZY LOADED)
  // ===========================================================================
  final Map<int, Widget> _pageCache = {};

  // ===========================================================================
  // UI STATE
  // ===========================================================================
  final RxBool isInitialized = false.obs;
  final RxBool isLoading = false.obs;

  // ===========================================================================
  // USER STATE
  // ===========================================================================
  final Rxn<User> currentUser = Rxn<User>();

  StreamSubscription<User?>? _authSub;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================
  @override
  void onInit() {
    super.onInit();

    log("🧠 [AdminRootController] Initialized");

    _bindAuthState();
  }

  @override
  void onClose() {
    _authSub?.cancel();
    super.onClose();
  }

  // ===========================================================================
  // AUTH STATE LISTENER (SAFE)
  // Navigation/authorization stays with SessionController + RootGate; this
  // subscription only mirrors the user for UI and resets nav state on logout.
  // ===========================================================================
  void _bindAuthState() {
    _authSub = _auth.authStateChanges().listen((user) {
      currentUser.value = user;

      if (user == null) {
        log("❌ [AdminRoot] User logged out");
        _handleLogoutNavigation();
        return;
      }

      log("✅ [AdminRoot] User active → ${user.uid}");

      if (!isInitialized.value) {
        _initialize();
      }
    });
  }

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================
  Future<void> _initialize() async {
    try {
      isLoading.value = true;

      log("🚀 [AdminRoot] Bootstrapping...");

      // 🔥 preload first screen only
      _pageCache[0] = _buildPage(0);

      isInitialized.value = true;

      log("✅ [AdminRoot] Ready");
    } catch (e, s) {
      log("🔥 [AdminRoot] Init error\n$e\n$s");
    } finally {
      isLoading.value = false;
    }
  }

  // ===========================================================================
  // NAVIGATION
  // ===========================================================================
  void changePage(int index) {
    if (index < 0 || index > maxIndex) {
      log("⚠️ Invalid page index → $index");
      return;
    }

    if (selectedIndex.value == index) return;

    selectedIndex.value = index;

    // 🔥 lazy load page
    if (!_pageCache.containsKey(index)) {
      _pageCache[index] = _buildPage(index);
    }

    log("📄 Page changed → $index");
  }

  // ===========================================================================
  // GET CURRENT PAGE
  // ===========================================================================
  Widget get currentPage {
    final idx = selectedIndex.value.clamp(0, maxIndex);

    return _pageCache[idx] ??= _buildPage(idx);
  }

  // ===========================================================================
  // PAGE FACTORY (LAZY)
  // ===========================================================================
  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const DashboardScreenResponsive();
      case 1:
        return AdminsScreen();
      case 2:
        return TrainersScreen();
      case 3:
        return ClientsScreen();
      case 4:
        return SubscriptionsScreen();
      case 5:
        return PaymentsScreen();
      case 6:
        return CouponCodeScreen();
      case 7:
        return SupportScreen();
      case 8:
        return CommunicationScreen();
      case 9:
        return AuditLogScreen();
      case 10:
        return OperationsScreen();
      case 11:
        return PlatformStaffScreen();
      // FOOD PLATFORM V1 — the Super Admin's sole authoring surface for the
      // global food library every organization reads.
      case 12:
        return const GlobalFoodScreen();
      // GLOBAL EXERCISE LIBRARY — the Super Admin's master exercise catalog.
      // Appended at 13 so every existing nav index stays stable (the
      // Operations Center's jump targets rely on them).
      case 13:
        return const GlobalExerciseScreen();
      // SETTLEMENTS — Tier-2 member money the platform holds on organizations'
      // behalf. Deliberately NOT merged into Payments (index 5): that screen is
      // System A, TrainersArena's OWN subscription revenue. The two must never
      // share a surface, because a founder reading a combined total would be
      // reading their own income and somebody else's money as one number.
      // Appended at 14 to keep every existing index stable.
      case 14:
        return const SettlementScreen();
      // AUTOMATION + ENGAGEMENT INTELLIGENCE — both were finished, both had
      // their backend callables deployed live (`listAutomationTriggers`,
      // `setAutomationEnabled`, `getEngagementIntelligence`), and neither had
      // a case here or a sidebar entry. 1,269 lines of founder capability
      // that nothing could open. Appended at 15/16 so every existing index —
      // which the Operations Centre's jump targets depend on — stays put.
      case 15:
        return const AutomationScreen();
      case 16:
        return const EngagementIntelligenceScreen();
      // ACCESS REQUESTS — TrainerArena's commercial intake. Appended at 17 so
      // every existing index stays put (the Operations Centre's jump targets
      // depend on them). This is System A (TrainersArena's own SaaS revenue),
      // deliberately nowhere near Settlements at 14.
      case 17:
        return AccessRequestsScreen();
      default:
        return const SizedBox();
    }
  }

  // ===========================================================================
  // LOGOUT (SAFE + CENTRALIZED)
  // ===========================================================================
  Future<void> logout() async {
    try {
      log("👋 [AdminRoot] Logging out...");

      // Sign out only. The reactive RootGate (driven by SessionController)
      // rebuilds to the login screen — there are no named routes to push.
      await _auth.signOut();

      _clearState();
    } catch (e) {
      log("🔥 Logout error → $e");
    }
  }

  // ===========================================================================
  // HANDLE AUTO LOGOUT (AUTH STATE)
  // ===========================================================================
  void _handleLogoutNavigation() {
    // No navigation here — RootGate reacts to the auth-state change and shows
    // the login screen automatically.
    _clearState();
  }

  // ===========================================================================
  // CLEAR STATE (IMPORTANT)
  // ===========================================================================
  void _clearState() {
    selectedIndex.value = 0;
    _pageCache.clear();
    isInitialized.value = false;
  }

  // ===========================================================================
  // OPTIONAL: REFRESH CURRENT PAGE
  // ===========================================================================
  void refreshCurrentPage() {
    final idx = selectedIndex.value;

    _pageCache.remove(idx);
    _pageCache[idx] = _buildPage(idx);

    update();

    log("🔄 Page refreshed → $idx");
  }

  // ===========================================================================
  // OPTIONAL: PRELOAD IMPORTANT PAGES
  // ===========================================================================
  void preloadPages(List<int> indexes) {
    for (final i in indexes) {
      if (!_pageCache.containsKey(i)) {
        _pageCache[i] = _buildPage(i);
      }
    }

    log("⚡ Preloaded pages → $indexes");
  }
}
