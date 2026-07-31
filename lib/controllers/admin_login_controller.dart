// lib/controllers/admin_login_controller.dart

import 'package:alphaserena_admin_portel/widgets/app_snackbar.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

/// Handles ONLY the credential sign-in. Authorization (is this user a master
/// admin?) and all routing live in [SessionController], which verifies
/// `master_admins/{uid}` on every auth-state change. Keeping login "pure" means
/// there is a single, un-bypassable place where access is granted.
class AdminLoginController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final RxBool isLoading = false.obs;

  Future<void> loginAdmin({
    required String email,
    required String password,
  }) async {
    // Duplicate-submit guard: the button disables itself while loading, but
    // the password field's Enter-to-submit path does not — gate here so every
    // entry point is covered.
    if (isLoading.value) return;
    try {
      isLoading.value = true;

      // The password is passed verbatim — trimming here would reject any
      // password that legitimately contains edge whitespace.
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // ✅ Success. SessionController now verifies master status + routes.
      // Do NOT navigate or grant access from here.
    } on FirebaseAuthException catch (e) {
      AppSnackbar.show(title: "Login Failed", message: _messageFor(e.code));
    } catch (_) {
      AppSnackbar.show(title: "Error", message: "Something went wrong");
    } finally {
      isLoading.value = false;
    }
  }

  /// Generic messages — never reveal whether an email exists (avoids account
  /// enumeration). Newer Firebase returns `invalid-credential` for both a wrong
  /// password and an unknown email.
  String _messageFor(String code) {
    switch (code) {
      case 'invalid-email':
        return "Enter a valid email address";
      case 'user-disabled':
        return "This account has been disabled";
      case 'too-many-requests':
        return "Too many attempts. Please try again later.";
      case 'network-request-failed':
        return "Network error. Check your connection.";
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      default:
        return "Invalid email or password";
    }
  }

  final RxBool isResetting = false.obs;

  /// Owner-only password recovery. The server (`requestOwnerPasswordReset`)
  /// decides eligibility — only the platform owner receives an email — and the
  /// response is identical for owner, non-owner, and unknown emails, so this
  /// flow cannot be used to probe which accounts exist.
  ///
  /// Returns true when the request completed (show the generic confirmation),
  /// false only for a client-side transport failure (safe to surface — it
  /// reveals nothing about the account).
  Future<bool> requestOwnerPasswordReset(String email) async {
    if (isResetting.value) return false;
    try {
      isResetting.value = true;
      await FirebaseFunctions.instance
          .httpsCallable('requestOwnerPasswordReset')
          .call<void>({'email': email.trim()});
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
        AppSnackbar.show(
          title: 'Network error',
          message: 'Check your connection and try again.',
        );
        return false;
      }
      // Any server-side outcome stays generic — never reveal eligibility.
      return true;
    } catch (_) {
      return true;
    } finally {
      isResetting.value = false;
    }
  }
}
