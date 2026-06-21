import 'package:alphaserena_admin_portel/controllers/admin_login_controller.dart';
import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_shadows.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/core/widgets/app_text_field.dart';
import 'package:alphaserena_admin_portel/core/widgets/gradient_title.dart';
import 'package:alphaserena_admin_portel/core/widgets/primary_button.dart';
import 'package:alphaserena_admin_portel/widgets/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AdminLoginScreen extends StatelessWidget {
  AdminLoginScreen({super.key});

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _login = Get.find<AdminLoginController>();

  void _submit() {
    final email = _email.text.trim();
    final pass = _password.text;
    if (email.isEmpty || pass.isEmpty) {
      AppSnackbar.show(
        title: 'Missing details',
        message: 'Enter your email and password.',
      );
      return;
    }
    _login.loginAdmin(email: email, password: pass);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: AppRadii.lgR,
                border: Border.all(color: p.border),
                boxShadow: AppShadows.card(p.isDark),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const GradientTitle('ALPHASERENA', size: 34),
                  const SizedBox(height: 6),
                  Text(
                    'FOUNDER CONSOLE',
                    textAlign: TextAlign.center,
                    style: AppText.label(size: 13).copyWith(
                      color: p.textSecondary,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: p.textMuted),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Restricted — authorized super admins only.',
                          textAlign: TextAlign.center,
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  AppTextField(
                    controller: _email,
                    label: 'Email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    controller: _password,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    isPassword: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 28),
                  Obx(
                    () => PrimaryButton(
                      label: 'Sign In',
                      icon: Icons.shield_outlined,
                      isLoading: _login.isLoading.value,
                      onPressed: _submit,
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
