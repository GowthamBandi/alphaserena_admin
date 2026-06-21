// lib/controllers/admin_login_controller.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class AdminLoginController extends GetxController {
  // ===========================================================================
  // CORE SERVICES
  // ===========================================================================
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ===========================================================================
  // STATE
  // ===========================================================================
  final RxBool isLoading = false.obs;

  // ===========================================================================
  // LOGIN (PURE — NO NAVIGATION)
  // ===========================================================================
  Future<void> loginAdmin({
    required String email,
    required String password,
  }) async {
    try {
      isLoading.value = true;

      print("🔐 [Login] Attempting login...");
      print("📧 Email: $email");

      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final user = credential.user;

      if (user == null) {
        throw Exception("AUTH_USER_NULL");
      }

      print("🟢 [Login] Success → UID: ${user.uid}");

      // 🔥 VERIFY MASTER ACCESS
      final isMaster = await _isMasterAdmin(user.uid);

      if (!isMaster) {
        print("🚫 [Login] Not master admin → force logout");

        await _auth.signOut();

        Get.snackbar(
          "Access Denied",
          "You are not authorized to access this panel",
        );

        return;
      }

      print("✅ [Login] MASTER ADMIN VERIFIED");

      // ❗ DO NOTHING ELSE
      // AuthGate will auto-route
    } on FirebaseAuthException catch (e) {
      print("🔥 [Login ERROR] ${e.code}");

      String message = "Login failed";

      switch (e.code) {
        case 'user-not-found':
          message = "Account not found";
          break;
        case 'wrong-password':
          message = "Incorrect password";
          break;
        case 'invalid-email':
          message = "Invalid email";
          break;
      }

      Get.snackbar("Error", message);
    } catch (e, s) {
      print("🔥 [Login ERROR] $e");
      print("📍 Stack: $s");

      Get.snackbar("Error", "Something went wrong");
    } finally {
      isLoading.value = false;
    }
  }

  // ===========================================================================
  // MASTER ADMIN CHECK
  // ===========================================================================
  Future<bool> _isMasterAdmin(String uid) async {
    try {
      print("🔍 [MasterCheck] master_admins/$uid");

      final doc = await _db.collection("master_admins").doc(uid).get();

      if (!doc.exists) {
        print("❌ Not a master admin");
        return false;
      }

      print("✅ Master admin verified");
      return true;
    } on FirebaseException catch (e) {
      print("🔥 [Firestore ERROR] ${e.code}");

      if (e.code == 'permission-denied') {
        print("🚨 Firestore rules blocking access");
      }

      return false;
    } catch (e) {
      print("🔥 [MasterCheck ERROR] $e");
      return false;
    }
  }

  // ===========================================================================
  // LOGOUT (ALLOWED)
  // ===========================================================================
  Future<void> logout() async {
    print("👋 [Logout]");
    await _auth.signOut();

    // ❗ NO navigation here
    // AuthGate will redirect automatically
  }
}
