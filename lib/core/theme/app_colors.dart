import 'package:flutter/material.dart';

/// Raw brand colors — theme-independent. The app's signature is the deep red
/// (`#D50000`) flowing into orange / deep-orange for gradients.
class BrandColors {
  BrandColors._();

  static const Color accent = Color(0xFFD50000); // redAccent.shade700
  static const Color accentSoft = Color(0xFFFF5252); // redAccent
  static const Color gradientOrange = Color(0xFFFB8C00); // orange.shade600
  static const Color gradientDeep = Color(0xFFFF6E40); // deepOrangeAccent
  static const Color success = Color(0xFF00C853); // greenAccent.shade700
  static const Color error = Color(0xFFFF5252);
  static const Color amber = Color(0xFFFFCA28); // dark-mode toggle sun

  /// Signature title / button gradient (ShaderMask, hero CTAs).
  static const List<Color> heroGradient = [accent, gradientOrange];

  /// Selected / highlighted card gradient.
  static const List<Color> selectedGradient = [accent, gradientDeep];
}

/// Theme-aware semantic palette, exposed as a [ThemeExtension] so widgets read
/// colors from `context.palette` and switch automatically with the theme.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color backgroundGradientEnd;
  final Color surface;
  final Color surfaceAlt;
  final Color inputFill;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color success;
  final Color error;
  final bool isDark;

  const AppPalette({
    required this.background,
    required this.backgroundGradientEnd,
    required this.surface,
    required this.surfaceAlt,
    required this.inputFill,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.success,
    required this.error,
    required this.isDark,
  });

  static const AppPalette light = AppPalette(
    background: Color(0xFFF4F6F8),
    backgroundGradientEnd: Color(0xFFF5F5F5), // grey.100
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEEEEEE), // grey.200
    inputFill: Color(0xFFF5F5F5), // grey.100
    border: Color(0xFFE0E0E0), // grey.300
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF616161), // grey.700
    textMuted: Color(0xFF757575), // grey.600
    accent: BrandColors.accent,
    success: BrandColors.success,
    error: BrandColors.error,
    isDark: false,
  );

  static const AppPalette dark = AppPalette(
    background: Color(0xFF000000),
    backgroundGradientEnd: Color(0xFF212121), // grey.900
    surface: Color(0xFF1A1A1A),
    surfaceAlt: Color(0xFF212121), // grey.900
    inputFill: Color(0xFF212121), // grey.900
    border: Color(0xFF616161), // grey.700
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF), // white70
    textMuted: Color(0xFFBDBDBD), // grey.400
    accent: BrandColors.accent,
    success: BrandColors.success,
    error: BrandColors.error,
    isDark: true,
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? backgroundGradientEnd,
    Color? surface,
    Color? surfaceAlt,
    Color? inputFill,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? success,
    Color? error,
    bool? isDark,
  }) {
    return AppPalette(
      background: background ?? this.background,
      backgroundGradientEnd:
          backgroundGradientEnd ?? this.backgroundGradientEnd,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      inputFill: inputFill ?? this.inputFill,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      error: error ?? this.error,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      backgroundGradientEnd:
          Color.lerp(backgroundGradientEnd, other.backgroundGradientEnd, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// Convenience accessor: `context.palette.accent`, etc.
extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
