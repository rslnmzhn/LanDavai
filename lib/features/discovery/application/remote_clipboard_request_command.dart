import '../../clipboard/application/remote_clipboard_projection_store.dart';
import '../../settings/domain/app_settings.dart';
import '../data/device_alias_repository.dart';
import '../domain/discovered_device.dart';

class RemoteClipboardRequestResult {
  const RemoteClipboardRequestResult({this.infoMessage, this.errorMessage});

  final String? infoMessage;
  final String? errorMessage;
}

class RemoteClipboardRequestCommand {
  RemoteClipboardRequestCommand({
    required RemoteClipboardProjectionStore remoteClipboardProjectionStore,
    required bool Function(String? normalizedMac) isTrustedMac,
    required String Function() localDeviceMacProvider,
    required String Function() localNameProvider,
    required AppSettings Function() settingsProvider,
    required Future<void> Function({
      required String targetIp,
      required String requestId,
      required String requesterName,
      required String requesterMacAddress,
      required int maxEntries,
    })
    sendClipboardQuery,
    Duration responseWindow = const Duration(milliseconds: 900),
    void Function(String message)? log,
  }) : _remoteClipboardProjectionStore = remoteClipboardProjectionStore,
       _isTrustedMac = isTrustedMac,
       _localDeviceMacProvider = localDeviceMacProvider,
       _localNameProvider = localNameProvider,
       _settingsProvider = settingsProvider,
       _sendClipboardQuery = sendClipboardQuery,
       _responseWindow = responseWindow,
       _log = log;

  final RemoteClipboardProjectionStore _remoteClipboardProjectionStore;
  final bool Function(String? normalizedMac) _isTrustedMac;
  final String Function() _localDeviceMacProvider;
  final String Function() _localNameProvider;
  final AppSettings Function() _settingsProvider;
  final Future<void> Function({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
  })
  _sendClipboardQuery;
  final Duration _responseWindow;
  final void Function(String message)? _log;

  Future<RemoteClipboardRequestResult> request(DiscoveredDevice device) async {
    if (!device.isAppDetected) {
      return const RemoteClipboardRequestResult(
        errorMessage: 'Remote clipboard is available only for Landa devices.',
      );
    }

    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (!_isTrustedMac(mac)) {
      return const RemoteClipboardRequestResult(
        errorMessage:
            'Remote clipboard is available only for confirmed friends.',
      );
    }

    final requestId = _remoteClipboardProjectionStore.beginRequest(
      ownerIp: device.ip,
      localDeviceMac: _localDeviceMacProvider(),
    );
    try {
      await _sendClipboardQuery(
        targetIp: device.ip,
        requestId: requestId,
        requesterName: _localNameProvider(),
        requesterMacAddress: _localDeviceMacProvider(),
        maxEntries: _settingsProvider().clipboardHistoryMaxEntries,
      );
      await Future<void>.delayed(_responseWindow);
      if (!_remoteClipboardProjectionStore.hasEntriesFor(device.ip)) {
        return RemoteClipboardRequestResult(
          infoMessage: 'Clipboard history from ${device.displayName} is empty.',
        );
      }
      return const RemoteClipboardRequestResult();
    } catch (error) {
      final message = 'Failed to request remote clipboard: $error';
      _log?.call(message);
      return RemoteClipboardRequestResult(errorMessage: message);
    } finally {
      _remoteClipboardProjectionStore.finishRequest(requestId: requestId);
    }
  }
}
