import 'package:alphaserena_admin_portel/screens/admin_root_screen.dart';
import 'package:alphaserena_admin_portel/screens/auth/admin_login_screen.dart';
import 'package:alphaserena_admin_portel/screens/auth/auth_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: FirebaseOptions(
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

class AlphaSerenaAdminApp extends StatelessWidget {
  const AlphaSerenaAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'AlphaSerena Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const AuthWrapper(),
    );
  }
}
