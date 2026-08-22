// lib/main.dart

import 'dart:async';
import 'package:alphaserena_admin_portel/controllers/admin_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_login_controller.dart';
import 'package:alphaserena_admin_portel/controllers/admin_root_controller.dart';
import 'package:alphaserena_admin_portel/controllers/audit_controller.dart';
import 'package:alphaserena_admin_portel/controllers/billing_config_controller.dart';
import 'package:alphaserena_admin_portel/controllers/client_controller.dart';
import 'package:alphaserena_admin_portel/controllers/communication_controller.dart';
import 'package:alphaserena_admin_portel/controllers/coupon_controller.dart';
import 'package:alphaserena_admin_portel/controllers/crash_reports_controller.dart';
import 'package:alphaserena_admin_portel/controllers/dashboard_controller.dart';
import 'package:alphaserena_admin_portel/controllers/global_exercise_controller.dart';
import 'package:alphaserena_admin_portel/controllers/global_food_controller.dart';
import 'package:alphaserena_admin_portel/controllers/operations_controller.dart';
import 'package:alphaserena_admin_portel/controllers/payments_controller.dart';
import 'package:alphaserena_admin_portel/controllers/platform_staff_controller.dart';
import 'controllers/access_request_controller.dart';
import 'package:alphaserena_admin_portel/controllers/settlement_controller.dart';
import 'package:alphaserena_admin_portel/controllers/subscription_controller.dart';
import 'package:alphaserena_admin_portel/controllers/support_controller.dart';
import 'package:alphaserena_admin_portel/controllers/trainer_controller.dart';
import 'package:alphaserena_admin_portel/core/controllers/session_controller.dart';
import 'package:alphaserena_admin_portel/core/theme/app_theme.dart';
import 'package:alphaserena_admin_portel/dev/emulator_guard.dart';

import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:alphaserena_admin_portel/screens/auth/admin_login_screen.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:alphaserena_admin_portel/core/constants/firestore_collections.dart';
import 'package:alphaserena_admin_portel/core/utils/fatal_reporter.dart';
import 'package:alphaserena_admin_portel/core/utils/crash_reporter.dart';
import 'package:alphaserena_admin_portel/dev/crash_test_panel.dart';

/// =============================================================
/// 🚀 ENTRY POINT
/// =============================================================
/// THE CONSOLE HAD NO GLOBAL ERROR HANDLER AT ALL.
///
/// No `runZonedGuarded`, no `FlutterError.onError` — so an uncaught async
/// error in a god-mode console vanished silently. Both handlers now route
/// through `reportFatal`, which stamps the build identity onto every report
/// and writes through a swappable sink.
Future<void> main() async {
  runZonedGuarded(
    () async {
      // Inside the zone so the binding and runApp share one zone.
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        reportFatal('FlutterError', details.exception, details.stack);
      };
      await _start();
    },
    (Object error, StackTrace stack) =>
        reportFatal('Uncaught zone error', error, stack),
  );
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
/// Points the console at a local Firebase emulator suite instead of the live
/// project. OFF unless explicitly asked for at build time:
///
/// ```bash
/// flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
/// ```
///
/// This exists so the console's WRITE paths (every one of which goes through a
/// Cloud Function) can be exercised end to end without pointing a test run at
/// the project that serves live organizations. With the flag absent the value
/// is the empty string, so production boot is byte-identical to before.
const String _useEmulator = String.fromEnvironment('USE_FIREBASE_EMULATOR');

/// Host the emulators are reachable on. Overridable so the console can be
/// driven from a different machine than the one running the suite.
const String _emulatorHost = String.fromEnvironment(
  'FIREBASE_EMULATOR_HOST',
  defaultValue: 'localhost',
);

Future<void> _start() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: _firebaseOptions);
    }
    // ── CRASH PERSISTENCE ────────────────────────────────────────────────
    // Crashlytics does not exist on Flutter web, so production capture is a
    // Firestore write to the founder-only `console_crash_reports` collection,
    // attached BEHIND the existing reportFatal seam (both global handlers
    // already route through it). Installed immediately after Firebase init:
    // anything reported earlier was buffered and flushes now. Startup is
    // never blocked — the writer is fire-and-forget inside CrashReporter.
    CrashReporter.install(
      (doc) => FirebaseFirestore.instance
          .collection(FsCollections.consoleCrashReports)
          .add({...doc, 'at': FieldValue.serverTimestamp()}),
      emulatorMode: _useEmulator == 'true' && kDebugMode,
    );
    attachRemoteFatalSink(CrashReporter.handleFatal);
    CrashReporter.breadcrumb('BOOT_FIREBASE_READY');
    // Deliberately AFTER initializeApp and guarded by BOTH the opt-in flag and
    // kDebugMode: a release build can never be talked into a local backend even
    // if the define is passed by mistake.
    if (_useEmulator == 'true' && kDebugMode) {
      FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
      FirebaseFunctions.instance.useFunctionsEmulator(_emulatorHost, 5001);
      // Settlement proof uploads (settlement_proofs/…) must land in the same
      // sandbox as everything else — a proof written to PRODUCTION Storage
      // from an emulator run would be a data leak, not a test.
      await FirebaseStorage.instance.useStorageEmulator(_emulatorHost, 9199);
      debugPrint('⚠️  EMULATOR MODE — not talking to production');

      // ── PROVE IT, DO NOT ASSUME IT ──────────────────────────────────────
      // The calls above express an INTENTION, and a session once came up on
      // PRODUCTION with this exact flag set. The proof is therefore enforced
      // at sign-in — see `proveEmulatorSession` in MasterAdminBootstrap, which
      // blocks the console before a single controller is registered. There is
      // no pre-login gate because proving binding without a session would
      // require a public-read rule in production, and a login screen cannot
      // move money. See lib/dev/emulator_guard.dart for the full reasoning.
    }
    runApp(const AlphaSerenaAdminApp());
  } catch (e, s) {
    if (kDebugMode) debugPrint("🔥 FIREBASE INIT FAILED → $e");
    // Non-fatal by classification: the console SURVIVES into the retry
    // screen. The reporter buffers this until a later init succeeds — a
    // report about "Firebase could not start" cannot be written through the
    // Firebase that could not start.
    CrashReporter.reportNonFatal('Firebase init failed', e, s);
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

      // Crash-test triggers: in a normal build (`kCrashTestEnabled` false —
      // no --dart-define=CRASH_TEST=true) the child is returned UNTOUCHED, so
      // production layout is byte-identical to before. In an internal build
      // the panel overlays the app; the child must be `Positioned.fill` or
      // the Navigator is laid out loose and the whole login screen fails with
      // "RenderBox was not laid out" — found live on the first E2E run.
      builder: (context, child) {
        if (!kCrashTestEnabled) return child ?? const SizedBox.shrink();
        return Stack(
          children: [
            if (child != null) Positioned.fill(child: child),
            const CrashTestPanel(),
          ],
        );
      },
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

  /// Set when the post-login emulator proof FAILS. The console is replaced by
  /// the blocking screen rather than rendered — see `_initializeApp`.
  final Rxn<EmulatorProof> sessionProofFailure = Rxn<EmulatorProof>();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (kDebugMode) debugPrint("🚀 MASTER ADMIN BOOT → ${user.uid}");

    // ── POST-LOGIN EMULATOR PROOF ─────────────────────────────────────────
    // The pre-login check proved Firestore's endpoint; this proves the
    // SESSION — that the signed-in identity and the Storage bucket belong to
    // the emulator too. It runs before a single controller is registered, so
    // no stream and no money action can exist on an unproven session. This is
    // the check that would have caught a production account reaching a
    // console the operator believed was sandboxed.
    if (_useEmulator == 'true' && kDebugMode) {
      final proof = await proveEmulatorSession(host: _emulatorHost);
      logEmulatorProof(proof);
      if (!proof.allProven) {
        sessionProofFailure.value = proof;
        return;
      }
    }

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
      // SETTLEMENTS — Tier-2 money the platform holds on organizations'
      // behalf. Registered here because the page factory uses Get.find:
      // a missing registration crashes the section on open.
      _safePut(SettlementController());
      // ACCESS REQUESTS — TrainerArena SaaS onboarding. Registered here for
      // the same reason as SettlementController: the page factory uses
      // Get.find, so a missing registration crashes the section on open.
      _safePut(AccessRequestController());
      // CRASH REPORTS — same page-factory Get.find rule as the two above.
      _safePut(CrashReportsController());

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
    //
    // 🔴 THE FIVE BELOW ARE REGISTERED BY SCREENS, NOT BY `_safePut` ABOVE —
    // `payments_screen`, `clients_screen`, `global_food_screen`,
    // `global_exercise_screen` and `billing_config_dialog` each call
    // `Get.put(...)` on open. They were absent from this list, so they
    // outlived the session that created them: `PaymentsController` and
    // `ClientController` kept their `admin_payments_history` and `clients`
    // listeners open past sign-out (their `onClose`, which cancels the
    // subscription, only runs on `Get.delete`), and the next sign-in re-used
    // the same instances with the previous session's rows still in them —
    // which is exactly what the sentence above says this method prevents.
    // `test/controller_teardown_test.dart` now pins the two lists together.
    _safeDelete<BillingConfigController>();
    _safeDelete<GlobalFoodController>();
    _safeDelete<GlobalExerciseController>();
    _safeDelete<PaymentsController>();
    _safeDelete<ClientController>();
    _safeDelete<CrashReportsController>();
    _safeDelete<AccessRequestController>();
    _safeDelete<SettlementController>();
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
      // Fails CLOSED: an unproven session gets the blocking screen, never the
      // console. Checked before `isReady` so there is no frame in which a
      // money surface exists on an unverified environment.
      final failed = sessionProofFailure.value;
      if (failed != null) return EmulatorProofFailedApp(proof: failed);
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
