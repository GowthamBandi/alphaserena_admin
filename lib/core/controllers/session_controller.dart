import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../../widgets/app_snackbar.dart';
import '../constants/firestore_collections.dart';

/// Secure session gate for the founder console.
///
/// Watches Firebase token state and, for ANY signed-in user — including a
/// session that Firebase restored on a web refresh — verifies the user is a
/// master admin via the `super_admin` claim or `master_admins/{uid}`. A
/// non-master is signed out immediately, so the console is NEVER shown to a
/// non-master even if a session was restored.
///
/// Listens to `idTokenChanges` (not `authStateChanges`) so a claim revoked or
/// an account disabled mid-session is re-checked on the next token refresh
/// instead of surviving until a full reload.
class SessionController extends GetxService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// True while resolving auth + master status — show a loader, never the console.
  final RxBool isBooting = true.obs;

  /// The signed-in AND verified master admin (null when unauthenticated).
  final Rxn<User> user = Rxn<User>();

  /// Whether the current user passed the `master_admins` check.
  final RxBool isMaster = false.obs;

  StreamSubscription<User?>? _authSub;

  /// Uid whose master status has been verified this session. Lets later token
  /// refreshes for the same uid re-verify silently (no boot loader flash).
  String? _verifiedUid;

  /// Re-entrancy guard: `_verifyMaster` force-refreshes the token, which
  /// re-fires `idTokenChanges`. Without this guard that event would loop.
  bool _verifying = false;

  /// The console may render ONLY when both are true.
  bool get isAuthorized => user.value != null && isMaster.value;

  @override
  void onInit() {
    _authSub = _auth.idTokenChanges().listen(_onAuthChanged);
    super.onInit();
  }

  Future<void> _onAuthChanged(User? u) async {
    // No session → show login.
    if (u == null) {
      user.value = null;
      isMaster.value = false;
      isBooting.value = false;
      _verifiedUid = null;
      return;
    }

    // Ignore the token event our own forced refresh emits mid-verification.
    if (_verifying) return;

    final isFirstVerify = _verifiedUid != u.uid;

    // First sight of this uid → hold the gate closed while we verify.
    // Subsequent token refreshes re-verify silently in the background.
    if (isFirstVerify) isBooting.value = true;

    _verifying = true;
    bool ok;
    try {
      ok = await _verifyMaster(u, forceRefresh: isFirstVerify);
    } finally {
      _verifying = false;
    }

    if (!ok) {
      // Authenticated but NOT authorized → block + sign out.
      user.value = null;
      isMaster.value = false;
      isBooting.value = false;
      _verifiedUid = null;
      AppSnackbar.show(
        title: 'Access Denied',
        message: isFirstVerify
            ? 'This account is not authorized for the admin console.'
            : 'Your access has been revoked. Please sign in again.',
      );
      await _auth.signOut(); // re-fires _onAuthChanged(null) → login
      return;
    }

    _verifiedUid = u.uid;
    user.value = u;
    isMaster.value = true;
    isBooting.value = false;
  }

  Future<bool> _verifyMaster(User user, {required bool forceRefresh}) async {
    try {
      // 1) Custom claim (preferred) — set by the backend's setRoleClaims
      //    callable or a master_admins bootstrap. It lives in the auth token,
      //    can't be forged by the client, and is enforceable in Firestore
      //    rules. Force-refresh on first verification so a freshly granted
      //    claim is seen without a manual re-login.
      final token = await _getTokenWithOfflineFallback(user, forceRefresh);
      if (token != null && token.claims?['role'] == 'super_admin') return true;

      // 2) Fallback: master_admins/{uid} doc — covers a manual bootstrap or any
      //    account created before the claim was set.
      final doc =
          await _db.collection(FsCollections.masterAdmins).doc(user.uid).get();
      return doc.exists;
    } catch (_) {
      // On any error, fail CLOSED (deny access).
      return false;
    }
  }

  /// A forced refresh needs the network. If it fails (offline startup), fall
  /// back to the cached token — its claims were server-signed at issuance and
  /// are still within their validity window, which is standard Firebase
  /// offline behavior. Any other failure returns null → caller falls through
  /// to the Firestore check / fail-closed path.
  Future<IdTokenResult?> _getTokenWithOfflineFallback(
    User user,
    bool forceRefresh,
  ) async {
    try {
      return await user.getIdTokenResult(forceRefresh);
    } catch (_) {
      if (!forceRefresh) return null;
      try {
        return await user.getIdTokenResult(false);
      } catch (_) {
        return null;
      }
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
