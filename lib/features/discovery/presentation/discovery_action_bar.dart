import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/discovery_controller.dart';
import '../application/shared_cache_maintenance_boundary.dart';

class DiscoveryActionBar extends StatelessWidget {
  const DiscoveryActionBar({
    required this.sharedCacheMaintenanceBoundary,
    required this.sharedFolderIndexingProgress,
    required this.sharedFolderIndexingProgressValue,
    required this.isAddingShare,
    required this.isSendingTransfer,
    required this.onReceive,
    required this.onAdd,
    required this.onSend,
    super.key,
  });

  final SharedCacheMaintenanceBoundary sharedCacheMaintenanceBoundary;
  final SharedFolderIndexingProgress? sharedFolderIndexingProgress;
  final double? sharedFolderIndexingProgressValue;
  final bool isAddingShare;
  final bool isSendingTransfer;
  final Future<void> Function() onReceive;
  final Future<void> Function() onAdd;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalSpacing = AppSpacing.xs * 2;
            final availableWidth = (constraints.maxWidth - totalSpacing)
                .clamp(0, double.infinity)
                .toDouble();
            final perButtonWidth = availableWidth / 3;
            return Row(
              children: [
                Expanded(
                  child: _AdaptiveActionButton.filled(
                    onPressed: onReceive,
                    icon: Icons.arrow_downward,
                    label: 'discovery.action_bar.download'.tr(),
                    compactLabel: 'discovery.action_bar.download'.tr(),
                    tooltip: 'discovery.action_bar.download_tooltip'.tr(),
                    availableWidth: perButtonWidth,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: sharedCacheMaintenanceBoundary.isRecacheInProgress
                      ? _SharedRecacheActionButton(
                          progress: sharedCacheMaintenanceBoundary
                              .recacheProgressValue,
                          eta: sharedCacheMaintenanceBoundary
                              .recacheProgress
                              ?.eta,
                        )
                      : sharedFolderIndexingProgress != null
                      ? _SharedRecacheActionButton(
                          progress: sharedFolderIndexingProgressValue,
                          eta: sharedFolderIndexingProgress!.eta,
                        )
                      : _AdaptiveActionButton.outlined(
                          onPressed: isAddingShare ? null : onAdd,
                          icon: Icons.add,
                          label: 'discovery.action_bar.share'.tr(),
                          compactLabel: 'discovery.action_bar.share_compact'
                              .tr(),
                          tooltip: 'discovery.action_bar.share_tooltip'.tr(),
                          availableWidth: perButtonWidth,
                        ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _AdaptiveActionButton.filled(
                    onPressed: isSendingTransfer ? null : onSend,
                    icon: Icons.import_export_rounded,
                    label: 'discovery.action_bar.connect'.tr(),
                    compactLabel: 'discovery.action_bar.connect_compact'.tr(),
                    tooltip: 'discovery.action_bar.connect_tooltip'.tr(),
                    availableWidth: perButtonWidth,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _ActionButtonDensity { regular, compact, iconOnly }

class _AdaptiveActionButton extends StatelessWidget {
  const _AdaptiveActionButton.filled({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.compactLabel,
    required this.tooltip,
    required this.availableWidth,
  }) : _outlined = false;

  const _AdaptiveActionButton.outlined({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.compactLabel,
    required this.tooltip,
    required this.availableWidth,
  }) : _outlined = true;

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final String compactLabel;
  final String tooltip;
  final double availableWidth;
  final bool _outlined;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final buttonHeight =
        platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux ||
            platform == TargetPlatform.macOS
        ? 40.0
        : 44.0;
    final density = _resolveDensity(context);
    final horizontalPadding = switch (density) {
      _ActionButtonDensity.regular => AppSpacing.sm,
      _ActionButtonDensity.compact => AppSpacing.xs,
      _ActionButtonDensity.iconOnly => AppSpacing.xs,
    };
    final labelText = switch (density) {
      _ActionButtonDensity.regular => label,
      _ActionButtonDensity.compact => compactLabel,
      _ActionButtonDensity.iconOnly => '',
    };

    final content = density == _ActionButtonDensity.iconOnly
        ? Icon(icon, size: 18)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  labelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          );

    final style = (_outlined
        ? OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(buttonHeight),
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          )
        : FilledButton.styleFrom(
            minimumSize: Size.fromHeight(buttonHeight),
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          ));

    final button = SizedBox(
      height: buttonHeight,
      child: _outlined
          ? OutlinedButton(onPressed: onPressed, style: style, child: content)
          : FilledButton(onPressed: onPressed, style: style, child: content),
    );

    if (density == _ActionButtonDensity.iconOnly) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  _ActionButtonDensity _resolveDensity(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final fullWidth = _requiredLabelWidth(
      context: context,
      labelText: label,
      style: style,
    );
    if (availableWidth >= fullWidth) {
      return _ActionButtonDensity.regular;
    }

    final compactWidth = _requiredLabelWidth(
      context: context,
      labelText: compactLabel,
      style: style,
    );
    if (availableWidth >= compactWidth) {
      return _ActionButtonDensity.compact;
    }

    return _ActionButtonDensity.iconOnly;
  }

  double _requiredLabelWidth({
    required BuildContext context,
    required String labelText,
    required TextStyle? style,
  }) {
    return AppSpacing.sm * 2 +
        18 +
        6 +
        _measureSingleLineTextWidth(
          context: context,
          text: labelText,
          style: style,
        );
  }
}

class _SharedRecacheActionButton extends StatelessWidget {
  const _SharedRecacheActionButton({required this.progress, required this.eta});

  final double? progress;
  final Duration? eta;

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = (progress ?? 0).clamp(0.0, 1.0).toDouble();
    final percentText = '${(normalizedProgress * 100).round()}%';
    final etaTextFull = eta == null ? 'ETA --:--' : 'ETA ${_formatEta(eta!)}';
    final etaTextCompact = eta == null ? '--:--' : _formatEta(eta!);
    final platform = Theme.of(context).platform;
    final buttonHeight =
        platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux ||
            platform == TargetPlatform.macOS
        ? 40.0
        : 44.0;

    final percentStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: AppColors.textPrimary);
    final etaStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary);

    return SizedBox(
      height: buttonHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.mutedBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasSpaceForFullEta = _fitsProgressContent(
                context: context,
                maxWidth: constraints.maxWidth,
                percentText: percentText,
                etaText: etaTextFull,
                percentStyle: percentStyle,
                etaStyle: etaStyle,
                horizontalPadding: AppSpacing.sm,
              );
              final hasSpaceForCompactEta =
                  !hasSpaceForFullEta &&
                  _fitsProgressContent(
                    context: context,
                    maxWidth: constraints.maxWidth,
                    percentText: percentText,
                    etaText: etaTextCompact,
                    percentStyle: percentStyle,
                    etaStyle: etaStyle,
                    horizontalPadding: AppSpacing.xs,
                  );
              final shownEtaText = hasSpaceForFullEta
                  ? etaTextFull
                  : hasSpaceForCompactEta
                  ? etaTextCompact
                  : null;
              final horizontalPadding = shownEtaText == etaTextFull
                  ? AppSpacing.sm
                  : AppSpacing.xs;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: normalizedProgress,
                      child: Container(
                        color: AppColors.brandPrimary.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Row(
                      children: [
                        Text(
                          percentText,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: percentStyle,
                        ),
                        if (shownEtaText != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              shownEtaText,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              textAlign: TextAlign.right,
                              style: etaStyle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  bool _fitsProgressContent({
    required BuildContext context,
    required double maxWidth,
    required String percentText,
    required String etaText,
    required TextStyle? percentStyle,
    required TextStyle? etaStyle,
    required double horizontalPadding,
  }) {
    final percentWidth = _measureSingleLineTextWidth(
      context: context,
      text: percentText,
      style: percentStyle,
    );
    final etaWidth = _measureSingleLineTextWidth(
      context: context,
      text: etaText,
      style: etaStyle,
    );
    final requiredWidth =
        horizontalPadding * 2 + percentWidth + AppSpacing.xs + etaWidth;
    return requiredWidth <= maxWidth;
  }

  static String _formatEta(Duration eta) {
    final totalSeconds = eta.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

double _measureSingleLineTextWidth({
  required BuildContext context,
  required String text,
  required TextStyle? style,
}) {
  if (text.isEmpty) {
    return 0;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout(minWidth: 0, maxWidth: double.infinity);
  return painter.width;
}
