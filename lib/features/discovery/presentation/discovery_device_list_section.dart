import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../settings/domain/app_settings.dart';
import '../../transfer/application/transfer_session_coordinator.dart';
import '../application/discovery_read_model.dart';
import '../domain/discovered_device.dart';
import 'discovery_network_scope_selector.dart';

class DiscoveryDeviceListSection extends StatelessWidget {
  const DiscoveryDeviceListSection({
    required this.readModel,
    required this.devices,
    required this.errorMessage,
    required this.isManualRefreshInProgress,
    required this.transferSessionCoordinator,
    required this.onRefresh,
    required this.onSelectDeviceByIp,
    required this.onSelectNetworkScope,
    required this.onOpenDeviceActionsMenu,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    super.key,
  });

  final DiscoveryReadModel readModel;
  final List<DiscoveredDevice> devices;
  final String? errorMessage;
  final bool isManualRefreshInProgress;
  final TransferSessionCoordinator transferSessionCoordinator;
  final Future<void> Function() onRefresh;
  final void Function(String ip) onSelectDeviceByIp;
  final void Function(String scopeId) onSelectNetworkScope;
  final Future<void> Function(DiscoveredDevice device, Offset? globalPosition)
  onOpenDeviceActionsMenu;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          _NetworkSummaryCard(readModel: readModel, total: devices.length),
          const SizedBox(height: AppSpacing.md),
          DiscoveryNetworkScopeSelector(
            readModel: readModel,
            onSelectScope: onSelectNetworkScope,
          ),
          const SizedBox(height: AppSpacing.md),
          if (errorMessage != null) ...[
            _ErrorBanner(message: errorMessage!),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (transferSessionCoordinator.isUploading ||
              transferSessionCoordinator.isDownloading) ...[
            _TransferProgressCard(
              transferSessionCoordinator: transferSessionCoordinator,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (isManualRefreshInProgress) ...[
            const LinearProgressIndicator(
              minHeight: 3,
              color: AppColors.brandPrimary,
              backgroundColor: AppColors.mutedBorder,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Expanded(
            child: devices.isEmpty
                ? _EmptyState(readModel: readModel, onRefresh: onRefresh)
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, index) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (_, index) => _DeviceTile(
                      device: devices[index],
                      selected:
                          readModel.selectedDevice?.ip == devices[index].ip,
                      onSelect: onSelectDeviceByIp,
                      onOpenActionsMenu: onOpenDeviceActionsMenu,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NetworkSummaryCard extends StatelessWidget {
  const _NetworkSummaryCard({required this.readModel, required this.total});

  final DiscoveryReadModel readModel;
  final int total;

  @override
  Widget build(BuildContext context) {
    final selected = readModel.selectedDevice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.lan, color: AppColors.brandPrimary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    readModel.localName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Local IP: ${readModel.localIp ?? "Detecting..."}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Devices: $total • App detected: ${readModel.appDetectedCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    readModel.isAppInForeground
                        ? 'Auto scan interval: ${readModel.settings.backgroundScanInterval.label}'
                        : 'Background mode: ${readModel.settings.backgroundScanInterval.label}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    selected == null
                        ? 'Target: not selected'
                        : 'Target: ${selected.displayName} (${selected.ip})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.error),
      ),
    );
  }
}

class _TransferProgressCard extends StatelessWidget {
  const _TransferProgressCard({required this.transferSessionCoordinator});

  final TransferSessionCoordinator transferSessionCoordinator;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfer Progress',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (transferSessionCoordinator.isUploading) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Upload: ${(transferSessionCoordinator.uploadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _formatRateAndEta(
                  speedBytesPerSecond:
                      transferSessionCoordinator.uploadSpeedBytesPerSecond,
                  eta: transferSessionCoordinator.uploadEta,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              LinearProgressIndicator(
                value: transferSessionCoordinator.uploadProgress,
                minHeight: 6,
                color: AppColors.brandPrimary,
                backgroundColor: AppColors.mutedBorder,
              ),
            ],
            if (transferSessionCoordinator.isDownloading) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Download: ${(transferSessionCoordinator.downloadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _formatRateAndEta(
                  speedBytesPerSecond:
                      transferSessionCoordinator.downloadSpeedBytesPerSecond,
                  eta: transferSessionCoordinator.downloadEta,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              LinearProgressIndicator(
                value: transferSessionCoordinator.downloadProgress,
                minHeight: 6,
                color: AppColors.success,
                backgroundColor: AppColors.mutedBorder,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRateAndEta({
    required double speedBytesPerSecond,
    required Duration? eta,
  }) {
    final speedText = speedBytesPerSecond > 0
        ? _formatSpeed(speedBytesPerSecond)
        : '-- B/s';
    final etaText = eta == null ? 'ETA --:--' : 'ETA ${_formatEta(eta)}';
    return '$speedText • $etaText';
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    final kb = bytesPerSecond / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB/s';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB/s';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB/s';
  }

  String _formatEta(Duration eta) {
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

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.onSelect,
    required this.onOpenActionsMenu,
  });

  final DiscoveredDevice device;
  final bool selected;
  final void Function(String ip) onSelect;
  final Future<void> Function(DiscoveredDevice device, Offset? globalPosition)
  onOpenActionsMenu;

  @override
  Widget build(BuildContext context) {
    final targetPlatform = Theme.of(context).platform;
    final isDesktopPlatform =
        targetPlatform == TargetPlatform.windows ||
        targetPlatform == TargetPlatform.linux ||
        targetPlatform == TargetPlatform.macOS;
    final isHighlighted = device.isAppDetected;
    final tileBackground = selected
        ? AppColors.brandAccent.withValues(alpha: 0.22)
        : isHighlighted
        ? AppColors.brandPrimary.withValues(alpha: 0.09)
        : AppColors.surface;
    final borderColor = selected
        ? AppColors.brandPrimary
        : isHighlighted
        ? AppColors.brandPrimary.withValues(alpha: 0.45)
        : AppColors.mutedBorder;
    final iconColor = isHighlighted
        ? AppColors.brandPrimary
        : AppColors.mutedIcon;
    final iconData = switch (device.deviceCategory) {
      DeviceCategory.phone => Icons.smartphone_rounded,
      DeviceCategory.pc => Icons.computer_rounded,
      DeviceCategory.unknown => Icons.devices,
    };
    final subtitle = [
      device.ip,
      if (device.macAddress != null) 'MAC ${device.macAddress}',
      if (device.operatingSystem != null && device.operatingSystem!.isNotEmpty)
        'OS ${device.operatingSystem}',
    ].join(' • ');

    return Container(
      decoration: BoxDecoration(
        color: tileBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: isDesktopPlatform
            ? null
            : (details) => onOpenActionsMenu(device, details.globalPosition),
        onSecondaryTapDown: isDesktopPlatform
            ? (details) => onOpenActionsMenu(device, details.globalPosition)
            : null,
        child: ListTile(
          minTileHeight: 56,
          onTap: () => onSelect(device.ip),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          leading: Icon(iconData, color: iconColor),
          title: Text(
            device.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: device.isTrusted ? 'Friend' : 'Not a friend yet',
                child: Icon(
                  device.isTrusted ? Icons.star : Icons.star_border,
                  color: device.isTrusted
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _StatusChip(device: device, selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.device, required this.selected});

  final DiscoveredDevice device;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.brandPrimary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Text(
          'Target',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.brandPrimaryDark),
        ),
      );
    }
    if (device.isAppDetected) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Text(
          'App found',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.success),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.mutedIcon.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        device.isReachable ? 'LAN host' : 'Stale',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.readModel, required this.onRefresh});

  final DiscoveryReadModel readModel;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final selectedRange = readModel.selectedNetworkRange;
    final description = selectedRange == null
        ? 'Make sure you are on the same Wi-Fi / LAN and refresh.'
        : 'No devices are visible in ${selectedRange.subnetCidr}. Try refreshing or switch back to "Все".';
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_find, size: 48, color: AppColors.mutedIcon),
              const SizedBox(height: AppSpacing.sm),
              Text(
                selectedRange == null
                    ? 'No devices found yet'
                    : 'No devices found in this network',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onRefresh,
                child: const Text('Refresh scan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
