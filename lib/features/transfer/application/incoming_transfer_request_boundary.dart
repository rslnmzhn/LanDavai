import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../discovery/data/device_alias_repository.dart';
import '../../discovery/data/lan_discovery_service.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../data/file_transfer_service.dart';
import '../data/transfer_storage_service.dart';
import '../domain/transfer_request.dart';
import 'incoming_transfer_request_helpers.dart';
import 'remote_file_preview_transfer_boundary.dart';
import 'shared_download_boundary.dart';
import 'transfer_path_policy.dart';
import 'transfer_session_coordinator.dart';

class IncomingTransferRequestBoundary extends ChangeNotifier {
  IncomingTransferRequestBoundary({
    required LanDiscoveryService lanDiscoveryService,
    required IncomingTransferMissingFileFilter missingFileFilter,
    required FileTransferService fileTransferService,
    required TransferStorageService transferStorageService,
    required SharedDownloadBoundary sharedDownloadBoundary,
    required RemoteFilePreviewTransferBoundary
    remoteFilePreviewTransferBoundary,
    required TransferPathPolicy pathPolicy,
    required String Function() localNameProvider,
    required bool Function(String? normalizedMac) isTrustedSender,
    required void Function(TransferSessionNotice notice) publishNotice,
    required IncomingDownloadProgressUpdater updateDownloadProgress,
    required void Function({int? totalBytes}) resetDownloadProgress,
    required void Function(int currentBytes) resetDownloadSpeed,
    required void Function(int currentBytes) updateDownloadSpeed,
    required void Function() clearDownloadSpeed,
    required void Function() notifyOwner,
    required IncomingTransferDiagnosticLoggerFactory
    fileTransferDiagnosticLogger,
    required IncomingTransferResultWaiter waitForIncomingTransferResult,
    required void Function(String requestId, TransferReceiveSession session)
    registerActiveReceiveSession,
    required TransferReceiveSession? Function(String requestId)
    removeActiveReceiveSession,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _missingFileFilter = missingFileFilter,
       _fileTransferService = fileTransferService,
       _transferStorageService = transferStorageService,
       _sharedDownloadBoundary = sharedDownloadBoundary,
       _remoteFilePreviewTransferBoundary = remoteFilePreviewTransferBoundary,
       _pathPolicy = pathPolicy,
       _localNameProvider = localNameProvider,
       _isTrustedSender = isTrustedSender,
       _publishNotice = publishNotice,
       _updateDownloadProgress = updateDownloadProgress,
       _resetDownloadProgress = resetDownloadProgress,
       _resetDownloadSpeed = resetDownloadSpeed,
       _updateDownloadSpeed = updateDownloadSpeed,
       _clearDownloadSpeed = clearDownloadSpeed,
       _notifyOwner = notifyOwner,
       _fileTransferDiagnosticLogger = fileTransferDiagnosticLogger,
       _waitForIncomingTransferResult = waitForIncomingTransferResult,
       _registerActiveReceiveSession = registerActiveReceiveSession,
       _removeActiveReceiveSession = removeActiveReceiveSession;

  final LanDiscoveryService _lanDiscoveryService;
  final IncomingTransferMissingFileFilter _missingFileFilter;
  final FileTransferService _fileTransferService;
  final TransferStorageService _transferStorageService;
  final SharedDownloadBoundary _sharedDownloadBoundary;
  final RemoteFilePreviewTransferBoundary _remoteFilePreviewTransferBoundary;
  final TransferPathPolicy _pathPolicy;
  final String Function() _localNameProvider;
  final bool Function(String? normalizedMac) _isTrustedSender;
  final void Function(TransferSessionNotice notice) _publishNotice;
  final IncomingDownloadProgressUpdater _updateDownloadProgress;
  final void Function({int? totalBytes}) _resetDownloadProgress;
  final void Function(int currentBytes) _resetDownloadSpeed;
  final void Function(int currentBytes) _updateDownloadSpeed;
  final void Function() _clearDownloadSpeed;
  final void Function() _notifyOwner;
  final IncomingTransferDiagnosticLoggerFactory _fileTransferDiagnosticLogger;
  final IncomingTransferResultWaiter _waitForIncomingTransferResult;
  final void Function(String requestId, TransferReceiveSession session)
  _registerActiveReceiveSession;
  final TransferReceiveSession? Function(String requestId)
  _removeActiveReceiveSession;

  final List<IncomingTransferRequest> _incomingRequests =
      <IncomingTransferRequest>[];
  bool _disposed = false;

  String get _localName => _localNameProvider();

  List<IncomingTransferRequest> get incomingRequests =>
      List<IncomingTransferRequest>.unmodifiable(_incomingRequests);

  Future<void> respondToTransferRequest({
    required String requestId,
    required bool approved,
    bool forPreview = false,
    String? previewRelativePath,
    String? destinationDirectoryOverridePath,
    SharedDownloadReceiveLayout receiveLayout =
        SharedDownloadReceiveLayout.preserveRelativeStructure,
  }) async {
    final index = _incomingRequests.indexWhere((r) => r.requestId == requestId);
    if (index < 0) {
      return;
    }

    final request = _incomingRequests[index];
    final isPreview = forPreview;
    TransferReceiveSession? receiveSession;
    var skippedExistingCount = 0;
    var itemsToReceive = request.items;
    var decisionApproved = approved;
    final previewCompleter = isPreview
        ? _remoteFilePreviewTransferBoundary.takePreviewResultCompleter(
            request.requestId,
          )
        : null;

    try {
      if (decisionApproved) {
        final destinationDirectory = isPreview
            ? await _remoteFilePreviewTransferBoundary
                  .resolvePreviewArtifactDirectory()
            : destinationDirectoryOverridePath != null
            ? Directory(destinationDirectoryOverridePath)
            : await _transferStorageService.resolveReceiveDirectory(
                appFolderName: 'Landa',
              );
        final destinationRelativeRootPrefix =
            !isPreview &&
                receiveLayout == SharedDownloadReceiveLayout.preserveSharedRoot
            ? _pathPolicy.resolveReceiveRootPrefix(request.sharedLabel)
            : null;

        if (isPreview) {
          final normalizedPreviewPath = previewRelativePath == null
              ? null
              : _pathPolicy.normalizeForMatch(previewRelativePath);
          if (normalizedPreviewPath != null &&
              normalizedPreviewPath.isNotEmpty) {
            itemsToReceive = request.items
                .where(
                  (item) =>
                      _pathPolicy.normalizeForMatch(item.fileName) ==
                      normalizedPreviewPath,
                )
                .toList(growable: false);
          }
          if (itemsToReceive.isEmpty && request.items.isNotEmpty) {
            itemsToReceive = <TransferFileManifestItem>[request.items.first];
          }
        } else {
          _sharedDownloadBoundary.setPreparation(
            requestId: request.requestId,
            ownerName: request.senderName,
            stage: SharedDownloadPreparationStage.checkingExistingLocalFiles,
          );
          itemsToReceive = await _missingFileFilter.filterMissingIncomingItems(
            items: request.items,
            destinationDirectory: destinationDirectory,
            destinationRelativeRootPrefix: destinationRelativeRootPrefix,
          );
          skippedExistingCount = request.items.length - itemsToReceive.length;
        }

        final expectedBytes = itemsToReceive.fold<int>(
          0,
          (sum, item) => sum + item.sizeBytes,
        );

        if (itemsToReceive.isNotEmpty) {
          _sharedDownloadBoundary.setPreparation(
            requestId: request.requestId,
            ownerName: request.senderName,
            stage: SharedDownloadPreparationStage.startingReceiver,
          );
          _resetDownloadProgress(totalBytes: expectedBytes);
          _resetDownloadSpeed(0);
          _notifyOwner();

          if (!isPreview) {
            unawaited(
              _transferStorageService.showAndroidDownloadProgressNotification(
                requestId: request.requestId,
                senderName: request.senderName,
                receivedBytes: 0,
                totalBytes: expectedBytes,
              ),
            );
          }

          var lastNotifiedAtMs = 0;
          var lastNotifiedPercent = -1;
          receiveSession = await _fileTransferService.startReceiver(
            requestId: request.requestId,
            expectedItems: request.items,
            destinationDirectory: destinationDirectory,
            destinationRelativeRootPrefix: destinationRelativeRootPrefix,
            onDiagnosticEvent: isPreview
                ? null
                : _fileTransferDiagnosticLogger(
                    requestId: request.requestId,
                    baseDetails: <String, Object?>{
                      'pathKind': 'legacy',
                      'senderIp': request.senderIp,
                      'senderName': request.senderName,
                      'sharedCacheId': request.sharedCacheId,
                    },
                  ),
            onProgress: (received, total) {
              if (received > 0) {
                _sharedDownloadBoundary.clearPreparation(
                  requestId: request.requestId,
                );
              }
              _updateDownloadProgress(
                requestId: request.requestId,
                receivedBytes: received,
                totalBytes: total,
              );
              _updateDownloadSpeed(received);
              _notifyOwner();

              if (isPreview) {
                return;
              }

              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final percent = total <= 0
                  ? -1
                  : (received * 100 ~/ total).clamp(0, 100);
              final isFinalChunk = total > 0 && received >= total;
              final hasMeaningfulPercentStep =
                  percent >= 0 &&
                  (lastNotifiedPercent < 0 ||
                      percent >= lastNotifiedPercent + 2);
              final shouldNotify =
                  isFinalChunk ||
                  nowMs - lastNotifiedAtMs >= 600 ||
                  hasMeaningfulPercentStep;
              if (!shouldNotify) {
                return;
              }
              lastNotifiedAtMs = nowMs;
              if (percent >= 0) {
                lastNotifiedPercent = percent;
              }
              unawaited(
                _transferStorageService.showAndroidDownloadProgressNotification(
                  requestId: request.requestId,
                  senderName: request.senderName,
                  receivedBytes: received,
                  totalBytes: total,
                ),
              );
            },
          );
          _registerActiveReceiveSession(request.requestId, receiveSession);
          unawaited(
            _waitForIncomingTransferResult(
              request: request,
              session: receiveSession,
              acceptedItems: itemsToReceive,
              persistToUserDownloads: !isPreview,
              recordHistory: !isPreview,
              sendCompletionNotification: !isPreview,
              destinationRelativeRootPrefix: destinationRelativeRootPrefix,
              previewCompleter: previewCompleter,
            ),
          );
        } else {
          _sharedDownloadBoundary.clearPreparation(
            requestId: request.requestId,
          );
          _resetDownloadProgress();
          _clearDownloadSpeed();
          if (isPreview) {
            decisionApproved = false;
            if (previewCompleter != null && !previewCompleter.isCompleted) {
              previewCompleter.complete(null);
            }
          }
        }
      }

      await _lanDiscoveryService.sendTransferDecision(
        targetIp: request.senderIp,
        requestId: request.requestId,
        approved: decisionApproved,
        receiverName: _localName,
        transferPort: decisionApproved ? receiveSession?.port : null,
        acceptedFileNames: decisionApproved
            ? itemsToReceive
                  .map((item) => item.fileName)
                  .toList(growable: false)
            : null,
      );

      _removeIncomingRequestAt(index);
      if (!decisionApproved) {
        _sharedDownloadBoundary.clearPreparation(requestId: request.requestId);
        _publishNotice(
          TransferSessionNotice(
            infoMessage: isPreview
                ? 'Preview request was declined.'
                : 'Transfer declined.',
            clearError: true,
          ),
        );
      } else if (isPreview) {
        _sharedDownloadBoundary.clearPreparation(requestId: request.requestId);
        _publishNotice(
          const TransferSessionNotice(
            infoMessage: 'Preview accepted. Waiting for file stream...',
            clearError: true,
          ),
        );
      } else if (itemsToReceive.isEmpty) {
        _sharedDownloadBoundary.clearPreparation(requestId: request.requestId);
        _publishNotice(
          const TransferSessionNotice(
            infoMessage:
                'All requested files already exist locally. Transfer skipped.',
            clearError: true,
          ),
        );
      } else if (skippedExistingCount > 0) {
        _sharedDownloadBoundary.setPreparation(
          requestId: request.requestId,
          ownerName: request.senderName,
          stage: SharedDownloadPreparationStage.waitingForRemote,
        );
        _publishNotice(
          TransferSessionNotice(
            infoMessage:
                'Transfer accepted. Skipping $skippedExistingCount existing file(s), waiting for missing files...',
            clearError: true,
          ),
        );
      } else {
        _sharedDownloadBoundary.setPreparation(
          requestId: request.requestId,
          ownerName: request.senderName,
          stage: SharedDownloadPreparationStage.waitingForRemote,
        );
        _publishNotice(
          const TransferSessionNotice(
            infoMessage: 'Transfer accepted. Waiting for file stream...',
            clearError: true,
          ),
        );
      }
    } catch (error) {
      _sharedDownloadBoundary.clearPreparation(requestId: request.requestId);
      if (receiveSession != null) {
        await receiveSession.close();
        _removeActiveReceiveSession(request.requestId);
      }
      if (previewCompleter != null && !previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
      _remoteFilePreviewTransferBoundary.discardPreviewResultCompleter(
        request.requestId,
      );
      _log('Failed to respond to transfer request: $error');
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Failed to respond to transfer request: $error',
        ),
      );
    }
  }

  void handleTransferRequestEvent(TransferRequestEvent event) {
    _upsertIncomingRequest(mapIncomingTransferRequestEvent(event));
    final normalizedSenderMac = DeviceAliasRepository.normalizeMac(
      event.senderMacAddress,
    );
    final pendingRemoteDownload = _sharedDownloadBoundary
        .consumePendingRemoteDownload(event);
    if (pendingRemoteDownload != null) {
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Auto-accepting download transfer from ${event.senderName}.',
          clearError: true,
        ),
      );
      unawaited(
        respondToTransferRequest(
          requestId: event.requestId,
          approved: true,
          destinationDirectoryOverridePath:
              pendingRemoteDownload.destinationDirectoryPath,
          receiveLayout: pendingRemoteDownload.receiveLayout,
        ),
      );
      return;
    }

    final previewIntent = _remoteFilePreviewTransferBoundary
        .consumePendingRemotePreview(event);
    if (previewIntent != null) {
      _remoteFilePreviewTransferBoundary.registerPreviewResultCompleter(
        requestId: event.requestId,
        completer: previewIntent.completer,
      );
      _publishNotice(
        TransferSessionNotice(
          infoMessage: 'Preparing remote preview from ${event.senderName}...',
          clearError: true,
        ),
      );
      unawaited(
        respondToTransferRequest(
          requestId: event.requestId,
          approved: true,
          forPreview: true,
          previewRelativePath: previewIntent.normalizedRelativePath,
        ),
      );
      return;
    }

    if (_isTrustedSender(normalizedSenderMac)) {
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Auto-accepting transfer from friend ${event.senderName}.',
          clearError: true,
        ),
      );
      unawaited(
        respondToTransferRequest(requestId: event.requestId, approved: true),
      );
      return;
    }

    unawaited(SystemSound.play(SystemSoundType.alert));
    _publishNotice(
      TransferSessionNotice(
        infoMessage: 'Incoming transfer request from ${event.senderName}.',
        clearError: true,
      ),
    );
  }

  void _upsertIncomingRequest(IncomingTransferRequest request) {
    _incomingRequests.removeWhere(
      (existing) => existing.requestId == request.requestId,
    );
    _incomingRequests.insert(0, request);
    _notify();
  }

  void _removeIncomingRequestAt(int index) {
    _incomingRequests.removeAt(index);
    _notify();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  void _log(String message) {
    developer.log(message, name: 'IncomingTransferRequestBoundary');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
