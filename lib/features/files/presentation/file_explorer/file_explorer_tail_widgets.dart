import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../application/files_feature_state_owner.dart';
import '../../application/preview_cache_owner.dart';
import 'file_explorer_widgets.dart';

class ExplorerEntityGridTile extends StatelessWidget {
  const ExplorerEntityGridTile({
    required this.entry,
    required this.tileExtent,
    required this.previewCacheOwner,
    required this.onTap,
    this.onDelete,
    super.key,
  });

  final FilesFeatureEntry entry;
  final double tileExtent;
  final PreviewCacheOwner previewCacheOwner;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: onDelete == null
          ? null
          : (details) async {
              final action = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                ),
                items: [
                  PopupMenuItem<String>(
                    value: 'remove',
                    child: Text('files.remove_from_sharing'.tr()),
                  ),
                ],
              );
              if (action == 'remove') {
                await onDelete!();
              }
            },
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        onLongPress: onDelete == null
            ? null
            : () async {
                await onDelete!();
              },
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const horizontalPadding = AppSpacing.xs;
              const verticalPadding = AppSpacing.xs;
              const nameHeight = 18.0;
              final availableWidth =
                  constraints.maxWidth - horizontalPadding * 2;
              final availableHeight =
                  constraints.maxHeight - verticalPadding * 2;
              final previewMaxHeight =
                  availableHeight - nameHeight - AppSpacing.xs;
              final previewSize = math
                  .min(availableWidth, previewMaxHeight)
                  .clamp(44, 170)
                  .toDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ExplorerEntityLeading(
                          isDirectory: entry.isDirectory,
                          filePath: entry.filePath,
                          previewCacheOwner: previewCacheOwner,
                          size: previewSize,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: nameHeight,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _GridNameLabel(
                          name: entry.name,
                          maxWidth: availableWidth,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GridNameLabel extends StatelessWidget {
  const _GridNameLabel({required this.name, required this.maxWidth});

  final String name;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall ?? const TextStyle();
    if (_fits(
      context: context,
      text: TextSpan(text: name, style: baseStyle),
      maxWidth: maxWidth,
    )) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: baseStyle,
      );
    }

    final suffixStyle =
        theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted) ??
        baseStyle.copyWith(color: AppColors.textMuted, fontSize: 10);
    final compact = _resolveCompact(
      context: context,
      baseStyle: baseStyle,
      suffixStyle: suffixStyle,
    );
    final start = compact.$1;
    final end = compact.$2;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$start…', style: baseStyle),
          TextSpan(text: end, style: suffixStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }

  (String, String) _resolveCompact({
    required BuildContext context,
    required TextStyle baseStyle,
    required TextStyle suffixStyle,
  }) {
    if (name.length <= 5) {
      return (name, '');
    }
    const suffixChars = 4;
    final suffix = name.length <= suffixChars
        ? name
        : name.substring(name.length - suffixChars);
    final maxPrefixChars = math.max(1, name.length - suffix.length);
    var bestPrefixChars = math.min(6, maxPrefixChars);

    for (var prefixChars = 1; prefixChars <= maxPrefixChars; prefixChars++) {
      final prefix = name.substring(0, prefixChars);
      final span = TextSpan(
        children: [
          TextSpan(text: '$prefix…', style: baseStyle),
          TextSpan(text: suffix, style: suffixStyle),
        ],
      );
      if (_fits(context: context, text: span, maxWidth: maxWidth)) {
        bestPrefixChars = prefixChars;
      } else {
        break;
      }
    }

    return (name.substring(0, bestPrefixChars), suffix);
  }

  bool _fits({
    required BuildContext context,
    required InlineSpan text,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: text,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: math.max(1, maxWidth));
    return !painter.didExceedMaxLines;
  }
}

class DisplayModeToggle extends StatelessWidget {
  const DisplayModeToggle({
    required this.isGrid,
    required this.onToggle,
    super.key,
  });

  final bool isGrid;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
        onPressed: onToggle,
        icon: Icon(
          isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
          size: 18,
        ),
        label: Text(isGrid ? 'files.list_view'.tr() : 'files.tile_view'.tr()),
      ),
    );
  }
}

class ExplorerErrorBanner extends StatelessWidget {
  const ExplorerErrorBanner({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text('common.retry'.tr())),
        ],
      ),
    );
  }
}
