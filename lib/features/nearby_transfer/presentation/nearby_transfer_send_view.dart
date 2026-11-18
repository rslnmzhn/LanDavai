import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import 'nearby_transfer_connection_confirm_view.dart';
import 'nearby_transfer_device_list_widget.dart';
import 'nearby_transfer_mode_banner.dart';
import 'nearby_transfer_qr_view.dart';

class NearbyTransferSendView extends StatelessWidget {
  const NearbyTransferSendView({
    required this.store,
    required this.onDisconnectRequested,
    super.key,
  });

  final NearbyTransferSessionStore store;
  final Future<void> Function() onDisconnectRequested;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isWaitingForPeer =
        store.phase == NearbyTransferSessionPhase.waitingForPeer;
    final isIdleOrReset = store.phase == NearbyTransferSessionPhase.idle;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md + bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NearbyTransferModeBanner(
            label: store.modeLabel,
            message: store.bannerMessage,
            isError: store.bannerIsError,
            mode: store.mode,
            bannerCode: store.bannerCode,
            bannerArgs: store.bannerArgs,
          ),
          const SizedBox(height: AppSpacing.md),
          if (isWaitingForPeer && store.qrPayloadText != null) ...[
            NearbyTransferQrView(payload: store.qrPayloadText!),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _copySessionCode(context, store.qrPayloadText!),
                icon: const Icon(Icons.copy_rounded),
                label: Text('nearby_transfer.copy_session_code'.tr()),
              ),
            ),
          ] else if (isWaitingForPeer && store.bannerIsError) ...[
            _SendRetryCard(onRetry: store.prepareSendFlow),
          ] else if (isIdleOrReset) ...[
            _SendRetryCard(onRetry: store.prepareSendFlow),
          ] else if (isWaitingForPeer) ...[
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: AppSpacing.md),
          if (store.phase == NearbyTransferSessionPhase.awaitingHandshake)
            NearbyTransferConnectionConfirmView(store: store)
          else if (store.phase == NearbyTransferSessionPhase.connected ||
              store.phase == NearbyTransferSessionPhase.transferring)
            _SendActions(store: store)
          else if (isWaitingForPeer && store.qrPayloadText != null)
            Text(
              'nearby_transfer.waiting_for_peer'.tr(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (!store.hasActiveConnection) ...[
            const SizedBox(height: AppSpacing.lg),
            NearbyTransferDeviceListWidget(devices: store.candidateDevices),
          ],
          if (store.hasActiveConnection) ...[
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onDisconnectRequested,
                child: Text('nearby_transfer.disconnect'.tr()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copySessionCode(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('nearby_transfer.session_code_copied'.tr())),
      );
  }
}

class _SendRetryCard extends StatelessWidget {
  const _SendRetryCard({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'nearby_transfer.ip_unavailable_title'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'nearby_transfer.ip_unavailable_hint'.tr(),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: () => unawaited(onRetry()),
            icon: const Icon(Icons.refresh_rounded),
            label: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }
}

class _SendActions extends StatelessWidget {
  const _SendActions({required this.store});

  final NearbyTransferSessionStore store;

  @override
  Widget build(BuildContext context) {
    final progress = store.transferProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (store.isPreparingOutgoingSelection &&
            store.outgoingPreparationProgress != null) ...[
          LinearProgressIndicator(value: store.outgoingPreparationProgress),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'nearby_transfer.preparing_summary'.tr(
              namedArgs: <String, String>{
                'current': '${store.outgoingPreparationCompletedItemCount}',
                'total': '${store.outgoingPreparationTotalItemCount}',
              },
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (store.outgoingPreparationCurrentPath != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              store.outgoingPreparationCurrentPath!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ] else if (progress != null) ...[
          Text(
            'nearby_transfer.offer_sending'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'nearby_transfer.offer_progress_detail'.tr(
              namedArgs: <String, String>{
                'completed': _formatBytes(context, store.transferCompletedBytes),
                'total': _formatBytes(context, store.transferTotalBytes),
                'percent': '${(progress * 100).round()}',
              },
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (store.hasOutgoingSelection) ...[
          _OutgoingSelectionCard(store: store),
          const SizedBox(height: AppSpacing.md),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: store.canSendFiles ? store.sendFiles : null,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(
                store.shouldShowSendMore
                    ? 'nearby_transfer.choose_more_files'.tr()
                    : 'nearby_transfer.choose_files'.tr(),
              ),
            ),
            if (store.supportsDirectoryPicking)
              OutlinedButton.icon(
                onPressed: store.canSendDirectory ? store.sendDirectory : null,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(
                  store.shouldShowSendMore
                      ? 'nearby_transfer.choose_more_folder'.tr()
                      : 'nearby_transfer.choose_folder'.tr(),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _OutgoingSelectionCard extends StatelessWidget {
  const _OutgoingSelectionCard({required this.store});

  final NearbyTransferSessionStore store;
  static const int _maxVisibleChips = 8;

  @override
  Widget build(BuildContext context) {
    final rawLabel = store.outgoingSelectionLabel ?? '';
    final resolvedLabel = rawLabel == 'Файлы' && store.outgoingSelectionItemCount > 1
        ? 'nearby_transfer.selected_default_label'.tr()
        : rawLabel;
    final roots = store.outgoingSelectionRoots;
    final visibleRoots = roots.take(_maxVisibleChips).toList(growable: false);
    final hiddenCount = roots.length - visibleRoots.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'nearby_transfer.selected_title'.tr(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              resolvedLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'nearby_transfer.selected_summary'.tr(
                namedArgs: <String, String>{
                  'count': '${store.outgoingSelectionItemCount}',
                  'size': _formatBytes(
                    context,
                    store.outgoingSelectionTotalBytes,
                  ),
                },
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            if (visibleRoots.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final root in visibleRoots)
                    Chip(
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text(
                          root,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (hiddenCount > 0)
                    Chip(
                      label: Text(
                        'nearby_transfer.selected_more_items'.tr(
                          namedArgs: <String, String>{'count': '$hiddenCount'},
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatBytes(BuildContext context, int bytes) {
  if (bytes < 1024) {
    return 'common.format_size_b'.tr(
      namedArgs: <String, String>{'value': '$bytes'},
    );
  }
  if (bytes < 1024 * 1024) {
    return 'common.format_size_kb'.tr(
      namedArgs: <String, String>{'value': (bytes / 1024).toStringAsFixed(1)},
    );
  }
  if (bytes < 1024 * 1024 * 1024) {
    return 'common.format_size_mb'.tr(
      namedArgs: <String, String>{
        'value': (bytes / (1024 * 1024)).toStringAsFixed(1),
      },
    );
  }
  return 'common.format_size_gb'.tr(
    namedArgs: <String, String>{
      'value': (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1),
    },
  );
}
