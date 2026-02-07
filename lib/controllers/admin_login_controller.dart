import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class AdminLoginController extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final String masterAdminEmail = "gowtham#master91@gmail.com"; // <<< SET THIS

  var isLoading = false.obs;

  Future<void> loginAdmin({
    required String email,
    required String password,
  }) async {
    try {
      isLoading.value = true;

      // TRY LOGIN
      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      // CHECK MASTER ADMIN
      if (credential.user!.email != masterAdminEmail) {
        // NOT MASTER ADMIN → LOGOUT + ERROR
        await _auth.signOut();

        Get.snackbar(
          "Access Denied",
          "You are not authorized to access the Admin Dashboard.",
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      // ALLOWED → GO TO DASHBOARD
   Get.offAll(()=> AdminRootScreen());
    } on FirebaseAuthException catch (e) {
      String message = "Login failed";

      if (e.code == 'user-not-found') {
        message = "Admin account not found";
      } else if (e.code == 'wrong-password') {
        message = "Incorrect password";
      }

      Get.snackbar("Error", message, snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }
}
