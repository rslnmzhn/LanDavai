import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import '../data/nearby_transfer_transport_adapter.dart';
import 'nearby_transfer_connection_confirm_view.dart';
import 'nearby_transfer_device_list_widget.dart';
import 'nearby_transfer_mode_banner.dart';
import 'nearby_transfer_scanner_view.dart';

class NearbyTransferReceiveView extends StatelessWidget {
  const NearbyTransferReceiveView({
    required this.store,
    required this.onDisconnectRequested,
    super.key,
  });

  final NearbyTransferSessionStore store;
  final Future<void> Function() onDisconnectRequested;

  @override
  Widget build(BuildContext context) {
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
          NearbyTransferScannerView(
            liveScannerSupported: store.liveQrScannerSupported,
            onPayloadDetected: (payload) {
              store.handleQrPayloadText(payload);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          if (store.phase == NearbyTransferSessionPhase.awaitingHandshake)
            NearbyTransferConnectionConfirmView(store: store)
          else if (store.phase == NearbyTransferSessionPhase.connected ||
              store.phase == NearbyTransferSessionPhase.transferring)
            _ConnectedReceiveState(store: store)
          else
            Text(
              'Отсканируйте QR или выберите устройство из списка ниже.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          const SizedBox(height: AppSpacing.lg),
          NearbyTransferDeviceListWidget(
            devices: store.candidateDevices,
            selectedDeviceId: store.selectedCandidateId,
            onSelectDevice: store.mode == NearbyTransferMode.lanFallback
                ? (candidate) => store.connectToCandidate(candidate)
                : null,
            onRefresh: store.refreshCandidates,
          ),
          if (store.hasActiveConnection) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onDisconnectRequested,
              child: const Text('Отключиться'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectedReceiveState extends StatelessWidget {
  const _ConnectedReceiveState({required this.store});

  final NearbyTransferSessionStore store;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          store.phase == NearbyTransferSessionPhase.transferring
              ? 'Получение файлов...'
              : 'Соединение установлено. Ожидаем файлы от подключённого устройства.',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (store.transferProgress != null) ...[
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: store.transferProgress),
        ],
      ],
    );
  }
}
