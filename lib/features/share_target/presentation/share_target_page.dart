import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../discovery/application/discovery_read_model.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../transfer/application/transfer_session_coordinator.dart';
import '../application/share_receive_boundary.dart';

class ShareTargetPage extends StatefulWidget {
  const ShareTargetPage({
    super.key,
    required this.shareReceiveBoundary,
    required this.readModel,
    required this.transferSessionCoordinator,
  });

  final ShareReceiveBoundary shareReceiveBoundary;
  final DiscoveryReadModel readModel;
  final TransferSessionCoordinator transferSessionCoordinator;

  @override
  State<ShareTargetPage> createState() => _ShareTargetPageState();
}

class _ShareTargetPageState extends State<ShareTargetPage> {
  bool _isSending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    widget.shareReceiveBoundary.addListener(_handleBoundaryChanged);
    widget.readModel.addListener(_handleReadModelChanged);
  }

  @override
  void dispose() {
    widget.shareReceiveBoundary.removeListener(_handleBoundaryChanged);
    widget.readModel.removeListener(_handleReadModelChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingFiles = widget.shareReceiveBoundary.pendingFiles;
    final friends = widget.readModel.friendDevices;
    final content = _buildContent(
      context: context,
      pendingFiles: pendingFiles,
      friends: friends,
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          widget.shareReceiveBoundary.clearPendingShare();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bgBase,
        appBar: AppBar(
          title: Text('share_target.title'.tr()),
          backgroundColor: AppColors.bgBase,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          actions: [
            TextButton(
              onPressed: _isSending ? null : _openApp,
              child: Text('share_target.open_app'.tr()),
            ),
          ],
        ),
        body: SafeArea(child: content),
      ),
    );
  }

  Widget _buildContent({
    required BuildContext context,
    required List<String> pendingFiles,
    required List<DiscoveredDevice> friends,
  }) {
    if (_isSending) {
      return _CenteredState(
        icon: Icons.sync_rounded,
        title: 'share_target.sending_title'.tr(),
        message: 'share_target.sending_message'.tr(),
        child: const Padding(
          padding: EdgeInsets.only(top: AppSpacing.md),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return _CenteredState(
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.error,
        title: 'share_target.error_title'.tr(),
        message: _errorMessage!,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: FilledButton(
            onPressed: () => setState(() => _errorMessage = null),
            child: Text('common.retry'.tr()),
          ),
        ),
      );
    }

    if (pendingFiles.isEmpty) {
      return _CenteredState(
        icon: Icons.inbox_rounded,
        title: 'share_target.empty_payload_title'.tr(),
        message: 'share_target.empty_payload_message'.tr(),
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: FilledButton(
            onPressed: _openApp,
            child: Text('share_target.open_app'.tr()),
          ),
        ),
      );
    }

    if (friends.isEmpty) {
      return _CenteredState(
        icon: Icons.people_outline_rounded,
        title: 'share_target.empty_friends_title'.tr(),
        message: 'share_target.empty_friends_message'.tr(),
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: FilledButton(
            onPressed: _openApp,
            child: Text('share_target.open_app'.tr()),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: friends.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ShareSummaryCard(fileCount: pendingFiles.length);
        }
        final device = friends[index - 1];
        return _FriendDeviceTile(
          device: device,
          onTap: () => _sendToDevice(device),
        );
      },
    );
  }

  void _handleBoundaryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleReadModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendToDevice(DiscoveredDevice device) async {
    final files = widget.shareReceiveBoundary.pendingFiles;
    if (files.isEmpty || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await widget.transferSessionCoordinator.outgoingTransferSendBoundary
          .sendFilesToDevice(
            targetIp: device.ip,
            targetName: device.displayName,
            selectedPaths: files,
          );
      widget.shareReceiveBoundary.clearPendingShare();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = 'share_target.error_message'.tr(
            namedArgs: <String, String>{'error': '$error'},
          );
          _isSending = false;
        });
      }
    }
  }

  void _openApp() {
    widget.shareReceiveBoundary.clearPendingShare();
    Navigator.of(context).maybePop();
  }
}

class _ShareSummaryCard extends StatelessWidget {
  const _ShareSummaryCard({required this.fileCount});

  final int fileCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.ios_share_rounded,
              color: AppColors.brandPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'share_target.ready_title'.tr(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'share_target.file_count'.tr(
                    namedArgs: <String, String>{'count': '$fileCount'},
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendDeviceTile extends StatelessWidget {
  const _FriendDeviceTile({required this.device, required this.onTap});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final online = device.isAppDetected || device.isReachable;
    final iconData = switch (device.deviceCategory) {
      DeviceCategory.phone => Icons.smartphone_rounded,
      DeviceCategory.pc => Icons.computer_rounded,
      DeviceCategory.unknown => Icons.devices_rounded,
    };

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.mutedBorder),
          ),
          child: Row(
            children: [
              Icon(iconData, color: AppColors.brandPrimary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      online
                          ? 'share_target.device_online'.tr()
                          : 'share_target.device_offline'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _OnlineIndicator(online: online),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineIndicator extends StatelessWidget {
  const _OnlineIndicator({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: online ? AppColors.success : AppColors.textMuted,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    this.iconColor = AppColors.brandPrimary,
    this.child,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color iconColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}
