import 'dart:async';

import '../data/file_transfer_service.dart';
import '../domain/transfer_request.dart';
import 'remote_share_access_session_contracts.dart';
import 'remote_share_access_session_models.dart';
import 'shared_download_boundary.dart';
import 'transfer_session_coordinator.dart';

class RemoteShareAccessSender {
  RemoteShareAccessSender({
    required String Function() localNameProvider,
    required RemoteShareAccessDeps deps,
    required RemoteShareAccessSnapshotResponseSender sendShareAccessResponse,
  }) : _localNameProvider = localNameProvider,
       _deps = deps,
       _sendShareAccessResponse = sendShareAccessResponse;

  final String Function() _localNameProvider;
  final RemoteShareAccessDeps _deps;
  final RemoteShareAccessSnapshotResponseSender _sendShareAccessResponse;

  String get _localName => _localNameProvider();

  Future<void> approve(IncomingRemoteShareAccessRequest request) async {
    _deps.setSharedUploadPreparation(
      requestId: request.requestId,
      requesterName: request.requesterName,
      stage: SharedUploadPreparationStage.resolvingSelection,
    );
    _deps.writeDiagnostic(
      stage: 'share_access_request_approved',
      requestId: request.requestId,
      details: <String, Object?>{
        'requesterIp': request.requesterIp,
        'requesterName': request.requesterName,
        'transferPort': request.transferPort,
      },
    );

    try {
      _deps.writeDiagnostic(
        stage: 'share_access_snapshot_prepare_start',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
        },
      );
      final snapshotFile = await _deps.buildSnapshotFile(
        requestId: request.requestId,
      );
      _deps.setSharedUploadPreparation(
        requestId: request.requestId,
        requesterName: request.requesterName,
        stage: SharedUploadPreparationStage.preparingTransfer,
      );
      _deps.writeDiagnostic(
        stage: 'share_access_snapshot_prepare_complete',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
          'snapshotPath': snapshotFile.sourcePath,
          'snapshotBytes': snapshotFile.announcement.sizeBytes,
          'snapshotSha256': snapshotFile.announcement.sha256,
          ...snapshotFile.diagnosticDetails,
        },
      );
      final metrics = await _deps.readPreparedFileMetrics(
        snapshotFile.sourcePath,
      );
      _deps.writeDiagnostic(
        stage: 'share_access_snapshot_send_preflight',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
          'snapshotPath': snapshotFile.sourcePath,
          'preSendBytes': metrics.sizeBytes,
          'preSendSha256': metrics.sha256,
          'preSendModifiedAtMs': metrics.modifiedAtMs,
          'sameFinalPathReopened':
              snapshotFile.diagnosticDetails['finalPath'] ==
              snapshotFile.sourcePath,
          ...snapshotFile.diagnosticDetails,
        },
      );
      if (metrics.sizeBytes != snapshotFile.announcement.sizeBytes ||
          metrics.sha256.toLowerCase() !=
              snapshotFile.announcement.sha256.toLowerCase()) {
        throw StateError('Shared-access snapshot changed after preparation.');
      }
      await _sendShareAccessResponse(
        targetIp: request.requesterIp,
        requestId: request.requestId,
        responderName: _localName,
        approved: true,
        message: 'Доступ разрешён. Синхронизируем список общих файлов.',
      );
      _deps.clearSharedUploadPreparation(requestId: request.requestId);
      unawaited(
        _deps.sendSnapshotTransfer(
          requestId: request.requestId,
          targetIp: request.requesterIp,
          receiverName: request.requesterName,
          transferPort: request.transferPort,
          files: <TransferSourceFile>[
            TransferSourceFile(
              sourcePath: snapshotFile.sourcePath,
              fileName: snapshotFile.announcement.fileName,
              sizeBytes: snapshotFile.announcement.sizeBytes,
              sha256: snapshotFile.announcement.sha256,
              deleteAfterTransfer: true,
            ),
          ],
          diagnosticDetails: <String, Object?>{
            'pathKind': 'share_access_snapshot',
            'snapshot': true,
            ...snapshotFile.diagnosticDetails,
          },
        ),
      );
    } catch (error, stackTrace) {
      _deps.clearSharedUploadPreparation(requestId: request.requestId);
      _deps.writeDiagnostic(
        stage: 'share_access_prepare_failure',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
        },
        error: error,
        stackTrace: stackTrace,
      );
      await _sendShareAccessResponse(
        targetIp: request.requesterIp,
        requestId: request.requestId,
        responderName: _localName,
        approved: false,
        message: 'Не удалось подготовить список общих файлов.',
      );
      _deps.publishNotice(
        TransferSessionNotice(
          errorMessage: 'Не удалось подготовить доступ к общим папкам: $error',
        ),
      );
    }
  }
}
