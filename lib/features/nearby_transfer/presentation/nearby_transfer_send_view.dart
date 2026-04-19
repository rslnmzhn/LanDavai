import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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
        if (store.transferProgress != null) ...[
          LinearProgressIndicator(value: store.transferProgress),
          const SizedBox(height: AppSpacing.sm),
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
