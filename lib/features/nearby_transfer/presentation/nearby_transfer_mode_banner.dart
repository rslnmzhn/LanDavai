import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';

class NearbyTransferModeBanner extends StatelessWidget {
  const NearbyTransferModeBanner({
    required this.label,
    required this.message,
    required this.isError,
    super.key,
  });

  final String label;
  final String? message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final text = message == null || message!.trim().isEmpty
        ? 'Режим: $label'
        : 'Режим: $label • $message';
    final color = isError ? AppColors.error : AppColors.brandPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}
