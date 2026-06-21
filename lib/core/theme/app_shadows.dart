import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Elevation / shadow tokens.
class AppShadows {
  AppShadows._();

  /// Soft shadow for standard content cards.
  static List<BoxShadow> card(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ];

  /// Accent glow used for highlighted / floating surfaces.
  static List<BoxShadow> get navGlow => [
        BoxShadow(
          color: BrandColors.accent.withValues(alpha: 0.25),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}
