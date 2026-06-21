// lib/main.dart

import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_login_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/controllers/coupon_controller.dart';
import 'package:alphaserena_admin_portel/controllers/dashboard_controller.dart';
import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';

import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:alphaserena_admin_portel/screens/auth/admin_login_screen.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// =============================================================
/// 🚀 ENTRY POINT
/// =============================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDGN75XqBCS2gI3adaM1AkZgQbZDxCJyHk",
      authDomain: "trainershq-f5ded.firebaseapp.com",
      projectId: "trainershq-f5ded",
      storageBucket: "trainershq-f5ded.firebasestorage.app",
      messagingSenderId: "790123355865",
      appId: "1:790123355865:web:720324d19e8d7a49d6a8c8",
    ),
  );

  runApp(const AlphaSerenaAdminApp());
}

/// =============================================================
/// 🔐 AUTH LAYER BINDINGS (ONLY AUTH HERE)
/// =============================================================
class AppBindings extends Bindings {
  @override
  void dependencies() {
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

      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),

      // 🔥 SINGLE ENTRY POINT
      home: const AuthGate(),
    );
  }
}

/// =============================================================
/// 🔄 AUTH GATE (SOURCE OF TRUTH FOR SESSION)
/// =============================================================
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ⏳ WAIT FOR FIREBASE
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _BootLoader();
        }

        // ❌ NOT LOGGED IN
        if (!snapshot.hasData) {
          return AdminLoginScreen();
        }

        // ✅ USER EXISTS → LOAD MAIN APP
        return const MasterAdminBootstrap();
      },
    );
  }
}

/// =============================================================
/// 🚀 BOOTSTRAP (CRITICAL - CONTROLLERS INIT)
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

    debugPrint("🚀 MASTER ADMIN BOOT → ${user.uid}");

    try {
      // =====================================================
      // 🔥 SAFE CONTROLLER REGISTRATION
      // =====================================================

      _safePut(AdminRootController());
      _safePut(DashboardController());
      _safePut(AdminController());
      _safePut(TrainerController());
      _safePut(CouponController());
      _safePut(SubscriptionController());

      // Optional: preload data if needed
      // await Future.wait([...]);

      debugPrint("✅ ALL CONTROLLERS INITIALIZED");

      isReady.value = true;
    } catch (e, s) {
      debugPrint("🔥 BOOT ERROR → $e");
      debugPrint("📍 STACK → $s");
    }
  }

  /// 🔒 SAFE PUT (PREVENT DUPLICATES)
  void _safePut<T>(T controller) {
    if (!Get.isRegistered<T>()) {
      Get.put<T>(controller, permanent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!isReady.value) {
        return const _BootLoader();
      }

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
