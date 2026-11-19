import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTypography {
  static const String primaryFontFamily = 'Manrope';
  static const String monoFontFamily = 'JetBrains Mono';

  static TextTheme textTheme() {
    const baseColor = AppColors.textPrimary;
    return const TextTheme(
      headlineSmall: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      titleLarge: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      titleMedium: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      bodyLarge: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      bodyMedium: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      bodySmall: TextStyle(
        fontFamily: primaryFontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      labelMedium: TextStyle(
        fontFamily: monoFontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
    );
  }

  const AppTypography._();
}
