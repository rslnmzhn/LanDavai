import 'package:flutter/material.dart';

import 'app_colors.dart';

class AppTypography {
  static TextTheme textTheme() {
    const baseColor = AppColors.textPrimary;
    return const TextTheme(
      headlineSmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: baseColor,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: baseColor,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Manrope',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      labelMedium: TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: baseColor,
      ),
    );
  }

  const AppTypography._();
}
