// lib/controllers/admin_login_controller.dart

import 'package:alphaserena_admin_portel/widgets/app_snackbar.dart';
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
    try {
      isLoading.value = true;

      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
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

  Future<void> logout() async {
    await _auth.signOut();
  }
}
