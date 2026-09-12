import 'package:flutter/foundation.dart';

import '../../discovery/data/device_alias_repository.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../domain/shared_folder_cache.dart';
import '../domain/transfer_request.dart';
import 'transfer_session_coordinator.dart';

class SharedDownloadRequestMapping {
  const SharedDownloadRequestMapping({
    required this.normalizedRequesterMac,
    required this.isPreviewRequest,
    required this.isTrustedFriendRequester,
    required this.notice,
    this.incomingRequest,
  });

  final String? normalizedRequesterMac;
  final bool isPreviewRequest;
  final bool isTrustedFriendRequester;
  final TransferSessionNotice notice;
  final IncomingSharedDownloadRequest? incomingRequest;
}

@immutable
class SharedDownloadRequestDiagnosticDetails {
  const SharedDownloadRequestDiagnosticDetails({
    required this.received,
    required this.autoApprovedForFriend,
  });

  final Map<String, Object?> received;
  final Map<String, Object?> autoApprovedForFriend;
}

class SharedDownloadRequestMapper {
  const SharedDownloadRequestMapper({
    required bool Function(String? normalizedMac) isTrustedSender,
    bool Function(String ip, String? normalizedMac)? isTrustedSenderIpAndMac,
  }) : _isTrustedSender = isTrustedSender,
       _isTrustedSenderIpAndMac = isTrustedSenderIpAndMac;

  final bool Function(String? normalizedMac) _isTrustedSender;
  final bool Function(String ip, String? normalizedMac)? _isTrustedSenderIpAndMac;

  SharedDownloadRequestMapping map({
    required DownloadRequestEvent event,
    required SharedFolderCacheRecord cache,
  }) {
    final normalizedRequesterMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    final isPreviewRequest = event.previewMode;
    final isAuthorized = _isTrustedSenderIpAndMac != null
        ? _isTrustedSenderIpAndMac(event.requesterIp, normalizedRequesterMac)
        : _isTrustedSender(normalizedRequesterMac);
    final isTrustedFriendRequester = !isPreviewRequest && isAuthorized;
    return SharedDownloadRequestMapping(
      normalizedRequesterMac: normalizedRequesterMac,
      isPreviewRequest: isPreviewRequest,
      isTrustedFriendRequester: isTrustedFriendRequester,
      notice: TransferSessionNotice(
        infoMessage: isPreviewRequest
            ? 'Preview request from ${event.requesterName}.'
            : isTrustedFriendRequester
            ? 'Trusted friend ${event.requesterName} requested "${cache.displayName}". Auto-approving.'
            : 'Download request from ${event.requesterName} for "${cache.displayName}".',
        clearError: true,
      ),
      incomingRequest: isPreviewRequest
          ? null
          : IncomingSharedDownloadRequest(
              requestId: event.requestId,
              requesterIp: event.requesterIp,
              requesterName: event.requesterName,
              requesterMacAddress: event.requesterMacAddress,
              sharedCacheId: cache.cacheId,
              sharedLabel: cache.displayName,
              selectedRelativePaths: List<String>.from(
                event.selectedRelativePaths,
              ),
              selectedFolderPrefixes: List<String>.from(
                event.selectedFolderPrefixes,
              ),
              transferPort: event.transferPort,
              createdAt: event.observedAt,
            ),
    );
  }

  SharedDownloadRequestDiagnosticDetails diagnostics({
    required DownloadRequestEvent event,
    required String? normalizedRequesterMac,
    String? cacheId,
  }) {
    final requestDetails = <String, Object?>{
      'requesterIp': event.requesterIp,
      'requesterName': event.requesterName,
      'requesterMacAddress':
          normalizedRequesterMac ?? event.requesterMacAddress,
      'cacheId': cacheId ?? event.cacheId,
      'selectedFileCount': event.selectedRelativePaths.length,
      'selectedFolderPrefixCount': event.selectedFolderPrefixes.length,
      'requestsWholeShare':
          event.selectedRelativePaths.isEmpty &&
          event.selectedFolderPrefixes.isEmpty,
    };
    return SharedDownloadRequestDiagnosticDetails(
      received: <String, Object?>{
        ...requestDetails,
        'previewMode': event.previewMode,
        'transferPort': event.transferPort,
      },
      autoApprovedForFriend: requestDetails,
    );
  }
}
