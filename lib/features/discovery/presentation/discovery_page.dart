import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/discovery_controller.dart';
import '../data/lan_discovery_service.dart';
import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  late final DiscoveryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DiscoveryController(
      lanDiscoveryService: LanDiscoveryService(),
      networkHostScanner: NetworkHostScanner(),
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final devices = _controller.devices;
        return Scaffold(
          appBar: AppBar(
            title: const Text('LAN Devices'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _controller.state == DiscoveryFlowState.discovering
                    ? null
                    : _controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                _NetworkSummaryCard(
                  controller: _controller,
                  total: devices.length,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_controller.errorMessage != null) ...[
                  _ErrorBanner(message: _controller.errorMessage!),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_controller.state == DiscoveryFlowState.discovering) ...[
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: AppColors.brandPrimary,
                    backgroundColor: AppColors.mutedBorder,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Expanded(
                  child: devices.isEmpty
                      ? _EmptyState(onRefresh: _controller.refresh)
                      : ListView.separated(
                          itemCount: devices.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (_, index) =>
                              _DeviceTile(device: devices[index]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NetworkSummaryCard extends StatelessWidget {
  const _NetworkSummaryCard({required this.controller, required this.total});

  final DiscoveryController controller;
  final int total;

  @override
  Widget build(BuildContext context) {
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
                    controller.localName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Local IP: ${controller.localIp ?? "Detecting..."}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Devices: $total  •  App detected: ${controller.appDetectedCount}',
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

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = device.isAppDetected;
    final tileBackground = isHighlighted
        ? AppColors.brandPrimary.withValues(alpha: 0.09)
        : AppColors.surface;
    final borderColor = isHighlighted
        ? AppColors.brandPrimary.withValues(alpha: 0.45)
        : AppColors.mutedBorder;
    final iconColor = isHighlighted
        ? AppColors.brandPrimary
        : AppColors.mutedIcon;
    final subtitle = device.deviceName ?? 'Unknown LAN host';

    return Container(
      decoration: BoxDecoration(
        color: tileBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        minTileHeight: 56,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: Icon(Icons.devices, color: iconColor),
        title: Text(device.ip, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: _StatusChip(device: device),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.device});

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
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
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
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
                'No devices found yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Make sure you are on the same Wi-Fi / LAN and refresh.',
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
