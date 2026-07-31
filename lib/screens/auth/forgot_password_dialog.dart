import 'package:alphaserena_admin_portel/controllers/admin_login_controller.dart';
import 'package:alphaserena_admin_portel/core/theme/app_colors.dart';
import 'package:alphaserena_admin_portel/core/theme/app_radii.dart';
import 'package:alphaserena_admin_portel/core/theme/app_text.dart';
import 'package:alphaserena_admin_portel/core/widgets/app_text_field.dart';
import 'package:alphaserena_admin_portel/core/widgets/primary_button.dart';
import 'package:alphaserena_admin_portel/widgets/app_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Owner-only account recovery.
///
/// Eligibility is enforced by the `requestOwnerPasswordReset` Cloud Function —
/// only the platform owner's account ever receives a reset email — and the
/// confirmation shown here is identical for every input, so the dialog leaks
/// nothing about which emails exist.
class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({super.key});

  static Future<void> show() {
    return Get.dialog<void>(
      const ForgotPasswordDialog(),
      barrierDismissible: true,
    );
  }

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  final TextEditingController _email = TextEditingController();
  final AdminLoginController _login = Get.find<AdminLoginController>();

  static final RegExp _emailPattern =
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      AppSnackbar.show(
        title: 'Invalid email',
        message: 'Enter a valid email address.',
      );
      return;
    }

    final completed = await _login.requestOwnerPasswordReset(email);
    if (!mounted || !completed) return;

    Get.back();
    AppSnackbar.show(
      title: 'Request received',
      message:
          'If this email belongs to the platform owner, a reset link has been sent.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.lgR,
            border: Border.all(color: p.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Reset password',
                style: AppText.label(size: 16).copyWith(color: p.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Account recovery is restricted to the platform owner. '
                'Enter the owner email to receive a reset link.',
                style: AppText.body(size: 13).copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: 20),
              AppTextField(
                controller: _email,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Get.back(),
                      child: Text(
                        'Cancel',
                        style: AppText.label(size: 13)
                            .copyWith(color: p.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Obx(
                      () => PrimaryButton(
                        label: 'Send reset link',
                        height: 48,
                        isLoading: _login.isResetting.value,
                        onPressed: _submit,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
