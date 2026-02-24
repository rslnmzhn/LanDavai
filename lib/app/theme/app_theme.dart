import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

class AppTheme {
  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.brandPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.brandPrimary,
          secondary: AppColors.brandAccent,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          error: AppColors.error,
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bgBase,
      textTheme: AppTypography.textTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgBase,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.mutedBorder),
        ),
      ),
    );
  }

  const AppTheme._();
}
