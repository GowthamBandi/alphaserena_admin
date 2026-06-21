import 'dart:developer';
import 'package:alphaserena_admin_portel/screens/admins_screen.dart';
import 'package:alphaserena_admin_portel/screens/clients_screen.dart';
import 'package:alphaserena_admin_portel/screens/coupon_code_screen.dart';
import 'package:alphaserena_admin_portel/screens/dash_board_responsive_screen.dart';
import 'package:alphaserena_admin_portel/screens/payments_screen.dart';
import 'package:alphaserena_admin_portel/screens/subscriptions_screen.dart';
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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ===========================================================================
  // NAVIGATION STATE
  // ===========================================================================
  final RxInt selectedIndex = 0.obs;

  /// Prevent invalid index crashes
  final int maxIndex = 6;

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

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================
  @override
  void onInit() {
    super.onInit();

    log("🧠 [AdminRootController] Initialized");

    _bindAuthState();
  }

  // ===========================================================================
  // AUTH STATE LISTENER (SAFE)
  // ===========================================================================
  void _bindAuthState() {
    _auth.authStateChanges().listen((user) {
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
