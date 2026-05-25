import '../../transfer/data/file_hash_service.dart';
import '../domain/discovered_device.dart';
import 'remote_share_browser.dart';

typedef SendRemoteShareQuery =
    Future<void> Function({
      required String targetIp,
      required String requestId,
      required String requesterName,
    });

class RemoteShareOptionsCommandResult {
  const RemoteShareOptionsCommandResult({this.infoMessage, this.errorMessage});

  final String? infoMessage;
  final String? errorMessage;
}

class RemoteShareOptionsCommand {
  const RemoteShareOptionsCommand({
    required RemoteShareBrowser remoteShareBrowser,
    required FileHashService fileHashService,
    required SendRemoteShareQuery sendShareQuery,
    required String Function() localDeviceMacProvider,
    required String Function() localNameProvider,
    DateTime Function()? nowProvider,
    void Function(String message)? log,
  }) : _remoteShareBrowser = remoteShareBrowser,
       _fileHashService = fileHashService,
       _sendShareQuery = sendShareQuery,
       _localDeviceMacProvider = localDeviceMacProvider,
       _localNameProvider = localNameProvider,
       _now = nowProvider,
       _log = log;

  final RemoteShareBrowser _remoteShareBrowser;
  final FileHashService _fileHashService;
  final SendRemoteShareQuery _sendShareQuery;
  final String Function() _localDeviceMacProvider;
  final String Function() _localNameProvider;
  final DateTime Function()? _now;
  final void Function(String message)? _log;

  Future<RemoteShareOptionsCommandResult> load({
    required Iterable<DiscoveredDevice> devices,
  }) async {
    try {
      final targets = devices
          .where((device) => device.isAppDetected)
          .toList(growable: false);
      final result = await _remoteShareBrowser.startBrowse(
        targets: targets,
        receiverMacAddress: _localDeviceMacProvider(),
        requesterName: _localNameProvider(),
        requestId: _buildRequestId(),
        sendShareQuery: _sendShareQuery,
      );

      if (!result.hadTargets) {
        return const RemoteShareOptionsCommandResult(
          infoMessage: 'No Landa devices available for shared content.',
        );
      }
      if (result.optionCount == 0) {
        return const RemoteShareOptionsCommandResult(
          infoMessage: 'No shared folders/files found on LAN devices.',
        );
      }
      return const RemoteShareOptionsCommandResult();
    } catch (error) {
      final message = 'Failed to request remote shares: $error';
      _log?.call(message);
      return RemoteShareOptionsCommandResult(errorMessage: message);
    }
  }

  String _buildRequestId() {
    final now = _now?.call() ?? DateTime.now();
    return _fileHashService.buildStableId(
      'share-query|${now.microsecondsSinceEpoch}|${_localDeviceMacProvider()}',
    );
  }
}
