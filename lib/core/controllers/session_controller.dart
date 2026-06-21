import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../../widgets/app_snackbar.dart';

/// Secure session gate for the founder console.
///
/// Watches Firebase auth state and, for ANY signed-in user — including a session
/// that Firebase restored on a web refresh — verifies the user is a master admin
/// by reading `master_admins/{uid}`. A non-master is signed out immediately, so
/// the console is NEVER shown to a non-master even if a session was restored.
///
/// This closes the old gap where the gate trusted `authStateChanges().hasData`
/// alone and only checked master status inside the login button handler.
class SessionController extends GetxService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // TODO(phase-A): replace the literal with FsCollections.masterAdmins once the
  // shared collections constants file is added to this app.
  static const String _masterAdmins = 'master_admins';

  /// True while resolving auth + master status — show a loader, never the console.
  final RxBool isBooting = true.obs;

  /// The signed-in AND verified master admin (null when unauthenticated).
  final Rxn<User> user = Rxn<User>();

  /// Whether the current user passed the `master_admins` check.
  final RxBool isMaster = false.obs;

  StreamSubscription<User?>? _authSub;

  /// The console may render ONLY when both are true.
  bool get isAuthorized => user.value != null && isMaster.value;

  @override
  void onInit() {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
    super.onInit();
  }

  Future<void> _onAuthChanged(User? u) async {
    // No session → show login.
    if (u == null) {
      user.value = null;
      isMaster.value = false;
      isBooting.value = false;
      return;
    }

    // Session exists → verify master status BEFORE granting access.
    isBooting.value = true;
    final ok = await _verifyMaster(u);

    if (!ok) {
      // Authenticated but NOT authorized → block + sign out.
      user.value = null;
      isMaster.value = false;
      isBooting.value = false;
      AppSnackbar.show(
        title: 'Access Denied',
        message: 'This account is not authorized for the admin console.',
      );
      await _auth.signOut(); // re-fires _onAuthChanged(null) → login
      return;
    }

    user.value = u;
    isMaster.value = true;
    isBooting.value = false;
  }

  Future<bool> _verifyMaster(User user) async {
    try {
      // 1) Custom claim (preferred) — set by scripts/set_super_admin.js. It lives
      //    in the auth token, can't be forged by the client, and is enforceable
      //    in Firestore rules. Force-refresh so a freshly granted claim is seen
      //    without a manual re-login.
      final token = await user.getIdTokenResult(true);
      if (token.claims?['role'] == 'super_admin') return true;

      // 2) Fallback: master_admins/{uid} doc — covers a manual bootstrap or any
      //    account created before the claim was set.
      final doc = await _db.collection(_masterAdmins).doc(user.uid).get();
      return doc.exists;
    } catch (_) {
      // On any error, fail CLOSED (deny access).
      return false;
    }
  }

  /// Centralized sign-out. The reactive gate handles routing back to login.
  Future<void> logout() async {
    await _auth.signOut();
  }

  @override
  void onClose() {
    _authSub?.cancel();
    super.onClose();
  }
}
