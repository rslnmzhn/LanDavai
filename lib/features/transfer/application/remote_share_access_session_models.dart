import '../../discovery/data/lan_packet_codec_models.dart';
import '../../discovery/data/lan_discovery_service.dart';
import '../data/file_transfer_service.dart';
import '../data/transfer_storage_service.dart';
import 'shared_download_boundary.dart';
import 'transfer_session_coordinator.dart';

enum RemoteShareAccessStage {
  sendingRequest,
  waitingForApproval,
  syncingCatalog,
  rejected,
  failed,
}

class RemoteShareAccessState {
  const RemoteShareAccessState({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.stage,
    this.message,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final RemoteShareAccessStage stage;
  final String? message;

  String get statusMessage {
    switch (stage) {
      case RemoteShareAccessStage.sendingRequest:
        return message ?? 'Отправляем запрос доступа для $ownerName...';
      case RemoteShareAccessStage.waitingForApproval:
        return message ?? 'Ждём, пока $ownerName подтвердит доступ...';
      case RemoteShareAccessStage.syncingCatalog:
        return message ?? 'Синхронизируем список общих файлов с $ownerName...';
      case RemoteShareAccessStage.rejected:
        return message ?? '$ownerName отклонил запрос доступа.';
      case RemoteShareAccessStage.failed:
        return message ?? 'Не удалось получить доступ к общим файлам.';
    }
  }
}

class RemoteShareAccessProjectionLoadResult {
  const RemoteShareAccessProjectionLoadResult({
    required this.ownerIp,
    required this.cacheCount,
    required this.fileCount,
  });

  final String ownerIp;
  final int cacheCount;
  final int fileCount;
}

class RemoteShareAccessPreparedSnapshot {
  const RemoteShareAccessPreparedSnapshot({
    required this.sourcePath,
    required this.announcement,
    required this.diagnosticDetails,
    this.deleteAfterTransfer = true,
  });

  final String sourcePath;
  final TransferAnnouncementItem announcement;
  final Map<String, Object?> diagnosticDetails;
  final bool deleteAfterTransfer;
}

class RemoteShareAccessSnapshotPayload {
  const RemoteShareAccessSnapshotPayload({
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
  });

  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
}

class RemoteShareAccessDeps {
  const RemoteShareAccessDeps({
    required this.publishNotice,
    required this.writeDiagnostic,
    required this.fileTransferDiagnosticLogger,
    required this.applyRemoteShareAccessSnapshot,
    required this.buildSnapshotFile,
    required this.readPreparedFileMetrics,
    required this.sendSnapshotTransfer,
    required this.setSharedUploadPreparation,
    required this.clearSharedUploadPreparation,
  });

  final void Function(TransferSessionNotice notice) publishNotice;
  final void Function({
    required String stage,
    String? requestId,
    Map<String, Object?> details,
    Object? error,
    StackTrace? stackTrace,
  })
  writeDiagnostic;
  final TransferRuntimeDiagnosticCallback Function({
    required String requestId,
    required Map<String, Object?> baseDetails,
  })
  fileTransferDiagnosticLogger;
  final Future<RemoteShareAccessProjectionLoadResult> Function({
    required String ownerIp,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
  })
  applyRemoteShareAccessSnapshot;
  final Future<RemoteShareAccessPreparedSnapshot> Function({
    required String requestId,
  })
  buildSnapshotFile;
  final Future<({int sizeBytes, String sha256, int modifiedAtMs})> Function(
    String filePath,
  )
  readPreparedFileMetrics;
  final Future<void> Function({
    required String requestId,
    required String targetIp,
    required String receiverName,
    required int transferPort,
    required List<TransferSourceFile> files,
    Map<String, Object?> diagnosticDetails,
  })
  sendSnapshotTransfer;
  final void Function({
    required String requestId,
    required String requesterName,
    required SharedUploadPreparationStage stage,
  })
  setSharedUploadPreparation;
  final void Function({String? requestId}) clearSharedUploadPreparation;
}

class RemoteShareAccessSessionConfig {
  const RemoteShareAccessSessionConfig({
    required this.lanDiscoveryService,
    required this.fileTransferService,
    required this.transferStorageService,
    required this.localNameProvider,
    required this.localDeviceMacProvider,
    required this.isTrustedSender,
    required this.buildStableId,
  });

  final LanDiscoveryService lanDiscoveryService;
  final FileTransferService fileTransferService;
  final TransferStorageService transferStorageService;
  final String Function() localNameProvider;
  final String Function() localDeviceMacProvider;
  final bool Function(String? normalizedMac) isTrustedSender;
  final String Function(String input) buildStableId;
}

class RemoteShareAccessPendingIntent {
  RemoteShareAccessPendingIntent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.destinationDirectoryPath,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String destinationDirectoryPath;
}
