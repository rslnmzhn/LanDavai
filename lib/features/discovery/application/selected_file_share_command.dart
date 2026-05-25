import '../../transfer/application/shared_cache_catalog.dart';
import '../domain/discovered_device.dart';

typedef PickFilePaths = Future<List<String>> Function();
typedef SendFilesToDevice =
    Future<void> Function({
      required String targetIp,
      required String targetName,
      required List<String> selectedPaths,
    });

class SelectedFileShareCommandResult {
  const SelectedFileShareCommandResult({
    this.infoMessage,
    this.errorMessage,
    this.cancelled = false,
  });

  final String? infoMessage;
  final String? errorMessage;
  final bool cancelled;
}

class SelectedFileShareCommand {
  const SelectedFileShareCommand({
    required PickFilePaths pickFilePaths,
    required SharedCacheCatalog sharedCacheCatalog,
    required SendFilesToDevice sendFilesToDevice,
    required String Function() localDeviceMacProvider,
    void Function(String message)? log,
  }) : _pickFilePaths = pickFilePaths,
       _sharedCacheCatalog = sharedCacheCatalog,
       _sendFilesToDevice = sendFilesToDevice,
       _localDeviceMacProvider = localDeviceMacProvider,
       _log = log;

  final PickFilePaths _pickFilePaths;
  final SharedCacheCatalog _sharedCacheCatalog;
  final SendFilesToDevice _sendFilesToDevice;
  final String Function() _localDeviceMacProvider;
  final void Function(String message)? _log;

  Future<SelectedFileShareCommandResult> addSharedFiles() async {
    try {
      final paths = await _pickFilePaths();
      if (paths.isEmpty) {
        return const SelectedFileShareCommandResult(cancelled: true);
      }

      await _sharedCacheCatalog.buildOwnerSelectionCache(
        ownerMacAddress: _localDeviceMacProvider(),
        filePaths: paths,
        displayName: 'Selected files',
      );
      return const SelectedFileShareCommandResult(
        infoMessage: 'Shared files added.',
      );
    } catch (error) {
      final message = 'Failed to add shared files: $error';
      _log?.call(message);
      return SelectedFileShareCommandResult(errorMessage: message);
    }
  }

  Future<SelectedFileShareCommandResult> sendFilesToDevice(
    DiscoveredDevice? target,
  ) async {
    if (target == null) {
      return const SelectedFileShareCommandResult(
        errorMessage: 'Select a target device first.',
      );
    }

    try {
      final selectedPaths = await _pickFilePaths();
      if (selectedPaths.isEmpty) {
        return const SelectedFileShareCommandResult(cancelled: true);
      }
      await _sendFilesToDevice(
        targetIp: target.ip,
        targetName: target.displayName,
        selectedPaths: selectedPaths,
      );
      return const SelectedFileShareCommandResult();
    } catch (error) {
      final message = 'Failed to send transfer request: $error';
      _log?.call(message);
      return SelectedFileShareCommandResult(errorMessage: message);
    }
  }
}
