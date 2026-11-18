import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../discovery/data/device_alias_repository.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../data/file_transfer_service.dart';
import '../domain/transfer_request.dart';
import 'remote_share_access_file_cleanup.dart';
import 'remote_share_access_sender.dart';
import 'remote_share_access_session_models.dart';
import 'remote_share_access_snapshot_parser.dart';
import 'transfer_session_coordinator.dart';

class RemoteShareAccessSessionBoundary extends ChangeNotifier {
  RemoteShareAccessSessionBoundary({
    required RemoteShareAccessSessionConfig config,
    required RemoteShareAccessDeps deps,
    RemoteShareAccessSnapshotParser snapshotParser =
        const RemoteShareAccessSnapshotParser(),
    RemoteShareAccessSender? sender,
  }) : _config = config,
       _deps = deps,
       _snapshotParser = snapshotParser,
       _sender =
           sender ??
           RemoteShareAccessSender(
             localNameProvider: config.localNameProvider,
             deps: deps,
             sendShareAccessResponse:
                 config.lanDiscoveryService.sendShareAccessResponse,
           );

  final RemoteShareAccessSessionConfig _config;
  final RemoteShareAccessDeps _deps;
  final RemoteShareAccessSnapshotParser _snapshotParser;
  final RemoteShareAccessSender _sender;

  final List<IncomingRemoteShareAccessRequest> _incomingRequests =
      <IncomingRemoteShareAccessRequest>[];
  final Map<String, TransferReceiveSession> _activeSessions =
      <String, TransferReceiveSession>{};
  final Map<String, RemoteShareAccessPendingIntent> _pendingByRequestId =
      <String, RemoteShareAccessPendingIntent>{};

  RemoteShareAccessState? _state;
  bool _disposed = false;

  String get _localName => _config.localNameProvider();
  String get _localDeviceMac => _config.localDeviceMacProvider();

  List<IncomingRemoteShareAccessRequest> get incomingRequests =>
      List<IncomingRemoteShareAccessRequest>.unmodifiable(_incomingRequests);

  RemoteShareAccessState? get state => _state;

  Future<void> requestAccess({
    required String ownerIp,
    required String ownerName,
  }) async {
    final activeState = _state;
    if (activeState != null &&
        activeState.ownerIp == ownerIp &&
        (activeState.stage == RemoteShareAccessStage.sendingRequest ||
            activeState.stage == RemoteShareAccessStage.waitingForApproval ||
            activeState.stage == RemoteShareAccessStage.syncingCatalog)) {
      return;
    }

    final requestId = _config.buildStableId(
      'share-access|$ownerIp|${DateTime.now().microsecondsSinceEpoch}|$_localDeviceMac',
    );
    _setState(
      requestId: requestId,
      ownerIp: ownerIp,
      ownerName: ownerName,
      stage: RemoteShareAccessStage.sendingRequest,
    );
    _deps.writeDiagnostic(
      stage: 'share_access_request_preparing',
      requestId: requestId,
      details: <String, Object?>{'ownerIp': ownerIp, 'ownerName': ownerName},
    );

    TransferReceiveSession? receiveSession;
    Directory? requestDirectory;
    try {
      final baseDirectory = await _config.transferStorageService
          .resolveRemoteShareAccessDirectory();
      requestDirectory = Directory(p.join(baseDirectory.path, requestId));
      await requestDirectory.create(recursive: true);
      receiveSession = await _config.fileTransferService.startReceiver(
        requestId: requestId,
        expectedItems: null,
        destinationDirectory: requestDirectory,
        onDiagnosticEvent: _deps.fileTransferDiagnosticLogger(
          requestId: requestId,
          baseDetails: <String, Object?>{
            'pathKind': 'share_access_snapshot',
            'ownerIp': ownerIp,
            'ownerName': ownerName,
          },
        ),
      );
      final pendingIntent = RemoteShareAccessPendingIntent(
        requestId: requestId,
        ownerIp: ownerIp,
        ownerName: ownerName,
        destinationDirectoryPath: requestDirectory.path,
      );
      _pendingByRequestId[requestId] = pendingIntent;
      _activeSessions[requestId] = receiveSession;
      unawaited(_waitForSnapshot(pendingIntent, receiveSession));

      await _config.lanDiscoveryService.sendShareAccessRequest(
        targetIp: ownerIp,
        requestId: requestId,
        requesterName: _localName,
        requesterMacAddress: _localDeviceMac,
        transferPort: receiveSession.port,
      );
      _deps.writeDiagnostic(
        stage: 'share_access_request_sent',
        requestId: requestId,
        details: <String, Object?>{
          'ownerIp': ownerIp,
          'ownerName': ownerName,
          'transferPort': receiveSession.port,
        },
      );
      if (_pendingByRequestId.containsKey(requestId)) {
        _setState(
          requestId: requestId,
          ownerIp: ownerIp,
          ownerName: ownerName,
          stage: RemoteShareAccessStage.waitingForApproval,
        );
      }
    } catch (error, stackTrace) {
      if (receiveSession != null) {
        await receiveSession.close();
      }
      _activeSessions.remove(requestId);
      _pendingByRequestId.remove(requestId);
      if (requestDirectory != null) {
        await cleanupRemoteShareAccessDirectory(requestDirectory);
      }
      _setState(
        requestId: requestId,
        ownerIp: ownerIp,
        ownerName: ownerName,
        stage: RemoteShareAccessStage.failed,
        message: 'Не удалось запросить доступ у $ownerName: $error',
      );
      _deps.writeDiagnostic(
        stage: 'share_access_request_failed',
        requestId: requestId,
        details: <String, Object?>{'ownerIp': ownerIp, 'ownerName': ownerName},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void handleRequestEvent(ShareAccessRequestEvent event) {
    final normalizedRequesterMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    _deps.writeDiagnostic(
      stage: 'share_access_request_received',
      requestId: event.requestId,
      details: <String, Object?>{
        'requesterIp': event.requesterIp,
        'requesterName': event.requesterName,
        'requesterMacAddress':
            normalizedRequesterMac ?? event.requesterMacAddress,
        'transferPort': event.transferPort,
      },
    );
    if (_config.isTrustedSender(normalizedRequesterMac)) {
      _deps.writeDiagnostic(
        stage: 'share_access_request_auto_approved_for_friend',
        requestId: event.requestId,
        details: <String, Object?>{
          'requesterIp': event.requesterIp,
          'requesterName': event.requesterName,
          'requesterMacAddress':
              normalizedRequesterMac ?? event.requesterMacAddress,
          'transferPort': event.transferPort,
        },
      );
      _deps.publishNotice(
        TransferSessionNotice(
          infoMessage:
              '${event.requesterName} is trusted. Granting shared access automatically.',
          clearError: true,
        ),
      );
      unawaited(
        _sender.approve(
          IncomingRemoteShareAccessRequest(
            requestId: event.requestId,
            requesterIp: event.requesterIp,
            requesterName: event.requesterName,
            requesterMacAddress: event.requesterMacAddress,
            transferPort: event.transferPort,
            createdAt: event.observedAt,
          ),
        ),
      );
      return;
    }
    unawaited(SystemSound.play(SystemSoundType.alert));
    _incomingRequests.removeWhere(
      (request) => request.requestId == event.requestId,
    );
    _incomingRequests.insert(
      0,
      IncomingRemoteShareAccessRequest(
        requestId: event.requestId,
        requesterIp: event.requesterIp,
        requesterName: event.requesterName,
        requesterMacAddress: event.requesterMacAddress,
        transferPort: event.transferPort,
        createdAt: event.observedAt,
      ),
    );
    _deps.publishNotice(
      TransferSessionNotice(
        infoMessage:
            '${event.requesterName} запрашивает доступ к вашим общим папкам.',
        clearError: true,
      ),
    );
    _notify();
  }

  void handleResponseEvent(ShareAccessResponseEvent event) {
    final pending = _pendingByRequestId[event.requestId];
    if (pending == null) {
      _deps.writeDiagnostic(
        stage: 'share_access_response_received',
        requestId: event.requestId,
        details: <String, Object?>{
          'responderIp': event.responderIp,
          'approved': event.approved,
          'message': event.message,
          'handled': false,
        },
      );
      return;
    }

    _deps.writeDiagnostic(
      stage: 'share_access_response_received',
      requestId: event.requestId,
      details: <String, Object?>{
        'responderIp': event.responderIp,
        'responderName': event.responderName,
        'approved': event.approved,
        'message': event.message,
      },
    );
    if (!event.approved) {
      final session = _activeSessions.remove(event.requestId);
      if (session != null) {
        unawaited(session.close());
      }
      _pendingByRequestId.remove(event.requestId);
      unawaited(
        cleanupRemoteShareAccessDirectory(
          Directory(pending.destinationDirectoryPath),
        ),
      );
      _setState(
        requestId: event.requestId,
        ownerIp: pending.ownerIp,
        ownerName: pending.ownerName,
        stage: RemoteShareAccessStage.rejected,
        message: event.message?.trim().isNotEmpty == true
            ? event.message
            : '${event.responderName} отклонил запрос доступа.',
      );
      return;
    }
    _setState(
      requestId: event.requestId,
      ownerIp: pending.ownerIp,
      ownerName: pending.ownerName,
      stage: RemoteShareAccessStage.syncingCatalog,
      message: '${pending.ownerName} разрешил доступ. Синхронизируем список...',
    );
  }

  Future<void> respondToIncomingRequest({
    required String requestId,
    required bool approved,
  }) async {
    final index = _incomingRequests.indexWhere(
      (request) => request.requestId == requestId,
    );
    if (index == -1) {
      return;
    }
    final request = _incomingRequests.removeAt(index);
    _notify();

    if (!approved) {
      _deps.writeDiagnostic(
        stage: 'share_access_request_rejected',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
        },
      );
      await _config.lanDiscoveryService.sendShareAccessResponse(
        targetIp: request.requesterIp,
        requestId: request.requestId,
        responderName: _localName,
        approved: false,
        message: 'Отправитель отклонил запрос доступа.',
      );
      _deps.publishNotice(
        TransferSessionNotice(
          infoMessage: 'Запрос доступа от ${request.requesterName} отклонён.',
          clearError: true,
        ),
      );
      return;
    }

    await _sender.approve(request);
  }

  void clearState({String? ownerIp}) {
    final current = _state;
    if (current == null) {
      return;
    }
    if (ownerIp != null && current.ownerIp != ownerIp) {
      return;
    }
    _state = null;
    _notify();
  }

  Future<void> _waitForSnapshot(
    RemoteShareAccessPendingIntent pendingIntent,
    TransferReceiveSession session,
  ) async {
    try {
      final result = await session.result;
      final requestId = pendingIntent.requestId;
      final wasRejected =
          _state?.requestId == requestId &&
          _state?.stage == RemoteShareAccessStage.rejected;
      if (wasRejected) {
        return;
      }
      _deps.writeDiagnostic(
        stage: 'share_access_snapshot_result',
        requestId: requestId,
        details: <String, Object?>{
          'success': result.success,
          'savedPathCount': result.savedPaths.length,
          'message': result.message,
        },
      );
      if (!result.success || result.savedPaths.isEmpty) {
        _setState(
          requestId: requestId,
          ownerIp: pendingIntent.ownerIp,
          ownerName: pendingIntent.ownerName,
          stage: RemoteShareAccessStage.failed,
          message: 'Не удалось получить список общих файлов: ${result.message}',
        );
        return;
      }

      final snapshot = await _snapshotParser.parse(result.savedPaths);
      final projectionResult = await _deps.applyRemoteShareAccessSnapshot(
        ownerIp: pendingIntent.ownerIp,
        ownerName: snapshot.ownerName,
        ownerMacAddress: snapshot.ownerMacAddress,
        entries: snapshot.entries,
      );
      _deps.writeDiagnostic(
        stage: 'share_access_snapshot_applied',
        requestId: requestId,
        details: <String, Object?>{
          'ownerIp': pendingIntent.ownerIp,
          'entryCount': snapshot.entries.length,
        },
      );
      _deps.writeDiagnostic(
        stage: 'share_access_projection_load_result',
        requestId: requestId,
        details: <String, Object?>{
          'ownerIp': projectionResult.ownerIp,
          'cacheCount': projectionResult.cacheCount,
          'fileCount': projectionResult.fileCount,
        },
      );
      _state = null;
      _deps.publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Доступ к общим папкам ${pendingIntent.ownerName} обновлён.',
          clearError: true,
        ),
      );
    } catch (error, stackTrace) {
      final wasRejected =
          _state?.requestId == pendingIntent.requestId &&
          _state?.stage == RemoteShareAccessStage.rejected;
      if (wasRejected) {
        return;
      }
      _deps.writeDiagnostic(
        stage: 'share_access_snapshot_failure',
        requestId: pendingIntent.requestId,
        details: <String, Object?>{
          'ownerIp': pendingIntent.ownerIp,
          'ownerName': pendingIntent.ownerName,
        },
        error: error,
        stackTrace: stackTrace,
      );
      _setState(
        requestId: pendingIntent.requestId,
        ownerIp: pendingIntent.ownerIp,
        ownerName: pendingIntent.ownerName,
        stage: RemoteShareAccessStage.failed,
        message: 'Не удалось синхронизировать общие папки: $error',
      );
    } finally {
      _pendingByRequestId.remove(pendingIntent.requestId);
      _activeSessions.remove(pendingIntent.requestId);
      await cleanupRemoteShareAccessDirectory(
        Directory(pendingIntent.destinationDirectoryPath),
      );
      _notify();
    }
  }

  void _setState({
    required String requestId,
    required String ownerIp,
    required String ownerName,
    required RemoteShareAccessStage stage,
    String? message,
  }) {
    final next = RemoteShareAccessState(
      requestId: requestId,
      ownerIp: ownerIp,
      ownerName: ownerName,
      stage: stage,
      message: message,
    );
    final current = _state;
    if (current?.requestId == next.requestId &&
        current?.ownerIp == next.ownerIp &&
        current?.ownerName == next.ownerName &&
        current?.stage == next.stage &&
        current?.message == next.message) {
      return;
    }
    _state = next;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final session in _activeSessions.values) {
      unawaited(session.close());
    }
    _activeSessions.clear();
    super.dispose();
  }
}
