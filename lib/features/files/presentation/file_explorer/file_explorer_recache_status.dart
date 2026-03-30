import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../discovery/application/shared_cache_maintenance_boundary.dart';

class SharedRecacheStatusCard extends StatelessWidget {
  const SharedRecacheStatusCard({
    required this.progress,
    required this.details,
    required this.formatEta,
    super.key,
  });

  final double? progress;
  final SharedCacheMaintenanceProgress? details;
  final String Function(Duration eta) formatEta;

  @override
  Widget build(BuildContext context) {
    final processedFiles = details?.processedFiles ?? 0;
    final totalFiles = details?.totalFiles ?? 0;
    final cacheLabel = details?.currentCacheLabel.trim() ?? '';
    final relativePath = details?.currentRelativePath.trim() ?? '';
    final eta = details?.eta;
    final etaText = eta == null ? 'ETA --:--' : 'ETA ${formatEta(eta)}';
    final filesText = totalFiles > 0
        ? '$processedFiles/$totalFiles files'
        : '$processedFiles files';
    final normalizedProgress = progress?.clamp(0.0, 1.0).toDouble();

    final locationText = [
      cacheLabel,
      relativePath,
    ].where((value) => value.isNotEmpty).join(' • ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cached_rounded,
                size: 16,
                color: AppColors.brandPrimaryDark,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Re-caching shared files',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$filesText • $etaText',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (locationText.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              locationText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(
            value: normalizedProgress,
            minHeight: 4,
            color: AppColors.brandPrimary,
            backgroundColor: AppColors.mutedBorder,
          ),
        ],
      ),
    );
  }
}
