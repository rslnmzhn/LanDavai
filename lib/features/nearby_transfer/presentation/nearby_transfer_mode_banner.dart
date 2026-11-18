import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import '../data/nearby_transfer_transport_adapter.dart';

class NearbyTransferModeBanner extends StatelessWidget {
  const NearbyTransferModeBanner({
    required this.label,
    required this.message,
    required this.isError,
    this.mode,
    this.bannerCode,
    this.bannerArgs = const <String, String>{},
    super.key,
  });

  final String label;
  final String? message;
  final bool isError;
  final NearbyTransferMode? mode;
  final NearbyTransferBannerCode? bannerCode;
  final Map<String, String> bannerArgs;

  @override
  Widget build(BuildContext context) {
    final localizedLabel = switch (mode) {
      NearbyTransferMode.wifiDirect => 'nearby_transfer.mode_wifi_direct'.tr(),
      NearbyTransferMode.lanFallback => 'nearby_transfer.mode_lan'.tr(),
      null => label.isEmpty ? 'nearby_transfer.mode_preparing'.tr() : label,
    };
    final resolvedMessage = _resolveMessage();
    final text = resolvedMessage == null || resolvedMessage.trim().isEmpty
        ? 'nearby_transfer.mode_prefix'.tr(
            namedArgs: <String, String>{'label': localizedLabel},
          )
        : 'nearby_transfer.mode_with_message'.tr(
            namedArgs: <String, String>{
              'label': localizedLabel,
              'message': resolvedMessage,
            },
          );
    final color = isError ? AppColors.error : AppColors.brandPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }

  String? _resolveMessage() {
    final code = bannerCode;
    if (code == null) {
      return message;
    }
    return switch (code) {
      NearbyTransferBannerCode.usingWifiDirect =>
        'nearby_transfer.banner_wifi_direct'.tr(),
      NearbyTransferBannerCode.usingLanFallback =>
        'nearby_transfer.banner_lan_fallback'.tr(),
      NearbyTransferBannerCode.noLocalIp =>
        'nearby_transfer.banner_no_local_ip'.tr(),
      NearbyTransferBannerCode.portFallback =>
        'nearby_transfer.banner_port_fallback'.tr(),
      NearbyTransferBannerCode.connectFailed =>
        'nearby_transfer.banner_connect_failed'.tr(namedArgs: bannerArgs),
      NearbyTransferBannerCode.qrInvalid =>
        'nearby_transfer.banner_qr_invalid'.tr(),
      NearbyTransferBannerCode.receiveNotReady =>
        'nearby_transfer.banner_receive_not_ready'.tr(),
      NearbyTransferBannerCode.verifyCodeExpired =>
        'nearby_transfer.verify_code_expired'.tr(),
      NearbyTransferBannerCode.verifyCodeCooldown =>
        'nearby_transfer.verify_code_cooldown'.tr(namedArgs: bannerArgs),
      NearbyTransferBannerCode.verifyCodeFormatError =>
        'nearby_transfer.verify_code_format_error'.tr(),
      NearbyTransferBannerCode.verifyCodeInvalid =>
        'nearby_transfer.verify_code_invalid'.tr(),
      NearbyTransferBannerCode.connected =>
        'nearby_transfer.banner_connected'.tr(),
      NearbyTransferBannerCode.previewUnavailable =>
        'nearby_transfer.banner_preview_unavailable'.tr(),
      NearbyTransferBannerCode.preparingReceive =>
        'nearby_transfer.banner_preparing_receive'.tr(),
      NearbyTransferBannerCode.preparingList =>
        'nearby_transfer.banner_preparing_list'.tr(),
      NearbyTransferBannerCode.preparingFiles =>
        'nearby_transfer.banner_preparing_files'.tr(),
      NearbyTransferBannerCode.offerSent =>
        'nearby_transfer.banner_offer_sent'.tr(),
      NearbyTransferBannerCode.confirmOnPeer =>
        'nearby_transfer.banner_confirm_on_peer'.tr(),
      NearbyTransferBannerCode.enterCode =>
        'nearby_transfer.banner_enter_code'.tr(),
      NearbyTransferBannerCode.chooseToDownload =>
        'nearby_transfer.banner_choose_to_download'.tr(),
      NearbyTransferBannerCode.peerCanSelect =>
        'nearby_transfer.banner_peer_can_select'.tr(),
      NearbyTransferBannerCode.receiveCompleted =>
        'nearby_transfer.banner_receive_completed'.tr(namedArgs: bannerArgs),
      NearbyTransferBannerCode.disconnected =>
        'nearby_transfer.banner_disconnected'.tr(),
      NearbyTransferBannerCode.busy => 'nearby_transfer.banner_busy'.tr(),
      NearbyTransferBannerCode.rejected =>
        'nearby_transfer.banner_rejected'.tr(),
    };
  }
}
