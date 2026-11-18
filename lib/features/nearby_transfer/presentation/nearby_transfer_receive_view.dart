import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import '../data/nearby_transfer_transport_adapter.dart';
import 'nearby_transfer_connection_confirm_view.dart';
import 'nearby_transfer_device_list_widget.dart';
import 'nearby_transfer_mode_banner.dart';
import 'nearby_transfer_receive_offer_section.dart';
import 'nearby_transfer_scanner_view.dart';

class NearbyTransferReceiveView extends StatefulWidget {
  const NearbyTransferReceiveView({
    required this.store,
    required this.onDisconnectRequested,
    super.key,
  });

  final NearbyTransferSessionStore store;
  final Future<void> Function() onDisconnectRequested;

  @override
  State<NearbyTransferReceiveView> createState() =>
      _NearbyTransferReceiveViewState();
}

class _NearbyTransferReceiveViewState extends State<NearbyTransferReceiveView> {
  late final TextEditingController _manualCodeController;

  NearbyTransferSessionStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _manualCodeController = TextEditingController();
    _store.addListener(_handleStoreChanged);
  }

  @override
  void didUpdateWidget(covariant NearbyTransferReceiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
    }
  }

  void _handleStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _store.removeListener(_handleStoreChanged);
    _manualCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isConnecting = _store.phase == NearbyTransferSessionPhase.connecting;
    final shouldShowScanner =
        !isConnecting &&
        _store.phase != NearbyTransferSessionPhase.awaitingHandshake &&
        _store.phase != NearbyTransferSessionPhase.connected &&
        _store.phase != NearbyTransferSessionPhase.transferring;

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
            label: _store.modeLabel,
            message: _store.bannerMessage,
            isError: _store.bannerIsError,
            mode: _store.mode,
            bannerCode: _store.bannerCode,
            bannerArgs: _store.bannerArgs,
          ),
          const SizedBox(height: AppSpacing.md),
          if (isConnecting) ...[
            _ConnectingStateCard(onCancel: () => _store.disconnect()),
          ] else if (shouldShowScanner) ...[
            NearbyTransferScannerView(
              liveScannerSupported: _store.liveQrScannerSupported,
              payloadValidator: _store.isValidQrPayloadText,
              onPayloadDetected: (payload) {
                unawaited(_store.handleQrPayloadText(payload));
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_store.phase == NearbyTransferSessionPhase.awaitingHandshake)
            NearbyTransferConnectionConfirmView(store: _store)
          else if (_store.phase == NearbyTransferSessionPhase.connected ||
              _store.phase == NearbyTransferSessionPhase.transferring)
            NearbyTransferReceiveOfferSection(store: _store)
          else if (!isConnecting) ...[
            Text(
              'nearby_transfer.scan_or_select'.tr(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            NearbyTransferDeviceListWidget(
              devices: _store.candidateDevices,
              selectedDeviceId: _store.selectedCandidateId,
              onSelectDevice: _store.mode == NearbyTransferMode.lanFallback
                  ? (candidate) => _store.connectToCandidate(candidate)
                  : null,
              onRefresh: _store.refreshCandidates,
            ),
            const SizedBox(height: AppSpacing.md),
            _ManualSessionCodeCard(
              controller: _manualCodeController,
              onConnect: _submitManualCode,
            ),
          ],
          if (_store.hasActiveConnection && !isConnecting) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onDisconnectRequested,
                child: Text('nearby_transfer.disconnect'.tr()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitManualCode() async {
    final text = _manualCodeController.text.trim();
    if (text.isEmpty) {
      return;
    }
    await _store.handleQrPayloadText(text);
    if (mounted && _store.hasActiveConnection) {
      _manualCodeController.clear();
    }
  }
}

class _ConnectingStateCard extends StatelessWidget {
  const _ConnectingStateCard({required this.onCancel});

  final Future<void> Function() onCancel;

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
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'nearby_transfer.connecting_to_peer'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () => unawaited(onCancel()),
            child: Text('nearby_transfer.cancel_connect'.tr()),
          ),
        ],
      ),
    );
  }
}

class _ManualSessionCodeCard extends StatelessWidget {
  const _ManualSessionCodeCard({
    required this.controller,
    required this.onConnect,
  });

  final TextEditingController controller;
  final Future<void> Function() onConnect;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'nearby_transfer.manual_code_label'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              hintText: 'nearby_transfer.manual_code_hint'.tr(),
              isDense: true,
            ),
            onSubmitted: (_) => unawaited(onConnect()),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => unawaited(onConnect()),
            icon: const Icon(Icons.link_rounded),
            label: Text('nearby_transfer.manual_code_connect'.tr()),
          ),
        ],
      ),
    );
  }
}
