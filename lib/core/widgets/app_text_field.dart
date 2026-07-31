import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Standard text field matching the auth/login styling: filled, rounded 14,
/// accent focus border + prefix icon, optional password visibility toggle.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool isPassword;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final TextAlign textAlign;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.onSubmitted,
    this.textInputAction,
    this.autofillHints,
    this.autofocus = false,
    this.inputFormatters,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: widget.controller,
      obscureText: widget.isPassword && _obscured,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      textAlign: widget.textAlign,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      cursorColor: p.accent,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      autofocus: widget.autofocus,
      inputFormatters: widget.inputFormatters,
      style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon:
            widget.icon != null ? Icon(widget.icon, color: p.accent) : null,
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: p.accent,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
      ),
    );
  }
}
