// lib/main.dart

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_login_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/controllers/audit_controller.dart';
import 'package:alphaserena_admin_portel/controllers/communication_controller.dart';
import 'package:alphaserena_admin_portel/controllers/coupon_controller.dart';
import 'package:alphaserena_admin_portel/controllers/dashboard_controller.dart';
import 'package:alphaserena_admin_portel/controllers/operations_controller.dart';
import 'package:alphaserena_admin_portel/controllers/platform_staff_controller.dart';
import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/controllers/support_controller.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/core/controllers/session_controller.dart';
import 'package:alphaserena_admin_portel/core/theme/app_theme.dart';

import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:alphaserena_admin_portel/screens/auth/admin_login_screen.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// =============================================================
/// 🚀 ENTRY POINT
/// =============================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _start();
}

const FirebaseOptions _firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyDGN75XqBCS2gI3adaM1AkZgQbZDxCJyHk",
  authDomain: "trainershq-f5ded.firebaseapp.com",
  projectId: "trainershq-f5ded",
  storageBucket: "trainershq-f5ded.firebasestorage.app",
  messagingSenderId: "790123355865",
  appId: "1:790123355865:web:720324d19e8d7a49d6a8c8",
);

/// Boot with a recoverable failure path: a failed Firebase init (offline
/// startup, blocked network) shows a retry screen instead of a blank crash
/// before the first frame.
Future<void> _start() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions);
    }
    runApp(const AlphaSerenaAdminApp());
  } catch (e) {
    if (kDebugMode) debugPrint("🔥 FIREBASE INIT FAILED → $e");
    runApp(const _BootstrapErrorApp());
  }
}

/// Minimal, dependency-free failure screen shown when Firebase itself could
/// not initialize. Deliberately generic — no internals are surfaced.
class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    "Couldn't start the console",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your internet connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// =============================================================
/// 🔐 AUTH-LAYER BINDINGS
/// Registered before the first frame so the gate is ready.
/// =============================================================
class AppBindings extends Bindings {
  @override
  void dependencies() {
    // Secure session gate — verifies master_admins on EVERY auth change.
    if (!Get.isRegistered<SessionController>()) {
      Get.put(SessionController(), permanent: true);
    }
    if (!Get.isRegistered<AdminLoginController>()) {
      Get.put(AdminLoginController(), permanent: true);
    }
  }
}

/// =============================================================
/// 🌐 ROOT APP
/// =============================================================
class AlphaSerenaAdminApp extends StatelessWidget {
  const AlphaSerenaAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AlphaSerena Admin',
      debugShowCheckedModeBanner: false,
      initialBinding: AppBindings(),

      // Shared design system (brand red + Teko/Poppins/Inter).
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,

      // 🔥 SINGLE ENTRY POINT — a reactive gate, not a bare hasData check.
      home: const RootGate(),
    );
  }
}

/// =============================================================
/// 🔄 ROOT GATE (SOURCE OF TRUTH FOR SESSION)
/// Booting → loader · authorized master → console · else → login.
/// SessionController has already verified master_admins, so a merely
/// authenticated (non-master) user can never reach the console here.
/// =============================================================
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Get.find<SessionController>();
    return Obx(() {
      if (session.isBooting.value) return const _BootLoader();
      if (session.isAuthorized) return const MasterAdminBootstrap();
      return AdminLoginScreen();
    });
  }
}

/// =============================================================
/// 🚀 BOOTSTRAP (CONSOLE CONTROLLERS INIT)
/// Only ever built for a verified master admin.
/// =============================================================
class MasterAdminBootstrap extends StatefulWidget {
  const MasterAdminBootstrap({super.key});

  @override
  State<MasterAdminBootstrap> createState() => _MasterAdminBootstrapState();
}

class _MasterAdminBootstrapState extends State<MasterAdminBootstrap> {
  final RxBool isReady = false.obs;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (kDebugMode) debugPrint("🚀 MASTER ADMIN BOOT → ${user.uid}");

    try {
      _safePut(AdminRootController());
      _safePut(DashboardController());
      _safePut(AdminController());
      _safePut(TrainerController());
      _safePut(CouponController());
      _safePut(SubscriptionController());
      _safePut(SupportController());
      _safePut(CommunicationController());
      _safePut(AuditController());
      // Operations Center derives from Admin/Support/Communication — register last.
      _safePut(OperationsController());
      _safePut(PlatformStaffController());

      if (kDebugMode) debugPrint("✅ ALL CONTROLLERS INITIALIZED");
      isReady.value = true;
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint("🔥 BOOT ERROR → $e");
        debugPrint("📍 STACK → $s");
      }
    }
  }

  void _safePut<T>(T controller) {
    if (!Get.isRegistered<T>()) {
      Get.put<T>(controller, permanent: true);
    }
  }

  @override
  void dispose() {
    super.dispose();
    // The console subtree is being unmounted (logout / access revoked). Tear
    // down every console controller so streams close and a later sign-in
    // boots from clean state instead of inheriting cached data.
    Future.microtask(_teardownConsoleControllers);
  }

  static void _teardownConsoleControllers() {
    // Derived controllers first, AdminRootController last.
    _safeDelete<OperationsController>();
    _safeDelete<PlatformStaffController>();
    _safeDelete<AuditController>();
    _safeDelete<CommunicationController>();
    _safeDelete<SupportController>();
    _safeDelete<SubscriptionController>();
    _safeDelete<CouponController>();
    _safeDelete<TrainerController>();
    _safeDelete<AdminController>();
    _safeDelete<DashboardController>();
    _safeDelete<AdminRootController>();
    if (kDebugMode) debugPrint("🧹 CONSOLE CONTROLLERS TORN DOWN");
  }

  static void _safeDelete<T>() {
    if (Get.isRegistered<T>()) {
      Get.delete<T>(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!isReady.value) return const _BootLoader();
      return AdminRootScreen();
    });
  }
}

/// =============================================================
/// ⏳ LOADING SCREEN (REUSABLE)
/// =============================================================
class _BootLoader extends StatelessWidget {
  const _BootLoader();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
