import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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
    final shouldShowQr =
        store.phase != NearbyTransferSessionPhase.awaitingHandshake &&
        store.phase != NearbyTransferSessionPhase.connected &&
        store.phase != NearbyTransferSessionPhase.transferring;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NearbyTransferModeBanner(
            label: store.modeLabel,
            message: store.bannerMessage,
            isError: store.bannerIsError,
          ),
          const SizedBox(height: AppSpacing.md),
          if (shouldShowQr && store.qrPayloadText != null)
            NearbyTransferQrView(payload: store.qrPayloadText!)
          else if (shouldShowQr)
            const Center(child: CircularProgressIndicator()),
          const SizedBox(height: AppSpacing.md),
          if (store.phase == NearbyTransferSessionPhase.awaitingHandshake)
            NearbyTransferConnectionConfirmView(store: store)
          else if (store.phase == NearbyTransferSessionPhase.connected ||
              store.phase == NearbyTransferSessionPhase.transferring)
            _SendActions(store: store)
          else
            Text(
              'nearby_transfer.waiting_for_peer'.tr(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: AppSpacing.lg),
          NearbyTransferDeviceListWidget(devices: store.candidateDevices),
          if (store.hasActiveConnection) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onDisconnectRequested,
              child: Text('nearby_transfer.disconnect'.tr()),
            ),
          ],
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
        ] else if (store.transferProgress != null) ...[
          LinearProgressIndicator(value: store.transferProgress),
          const SizedBox(height: AppSpacing.sm),
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
              onPressed: store.sendFiles,
              icon: const Icon(Icons.upload_file_rounded),
              label: Text(
                store.shouldShowSendMore
                    ? 'nearby_transfer.choose_more_files'.tr()
                    : 'nearby_transfer.choose_files'.tr(),
              ),
            ),
            if (store.canSendDirectory)
              OutlinedButton.icon(
                onPressed: store.sendDirectory,
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

  @override
  Widget build(BuildContext context) {
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
              store.outgoingSelectionLabel ?? '',
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
            if (store.outgoingSelectionRoots.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: store.outgoingSelectionRoots
                    .map((root) {
                      return Chip(
                        label: Text(root),
                        visualDensity: VisualDensity.compact,
                      );
                    })
                    .toList(growable: false),
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
