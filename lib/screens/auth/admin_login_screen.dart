import 'package:alphaserena_admin_portel/controllers/admin_login_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminLoginScreen extends StatelessWidget {
  AdminLoginScreen({super.key});

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final loginController = Get.put(AdminLoginController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12.withOpacity(0.05),
                  blurRadius: 12,
                )
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Admin Login",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // EMAIL
                  Text("Email", style: TextStyle(fontSize: 14)),
                  TextFormField(
                    controller: _emailController,
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter email" : null,
                    decoration: InputDecoration(
                      hintText: "admin@example.com",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // PASSWORD
                  Text("Password", style: TextStyle(fontSize: 14)),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    validator: (v) =>
                        v == null || v.isEmpty ? "Enter password" : null,
                    decoration: InputDecoration(
                      hintText: "•••••••",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // LOGIN BUTTON
                  Obx(
                    () => SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: loginController.isLoading.value
                            ? null
                            : () {
                                if (_formKey.currentState!.validate()) {
                                  loginController.loginAdmin(
                                    email: _emailController.text,
                                    password: _passwordController.text,
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: loginController.isLoading.value
                            ? CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(
                                "Login",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
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

