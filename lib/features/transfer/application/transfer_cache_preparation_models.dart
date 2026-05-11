import '../../discovery/data/lan_packet_codec_models.dart';
import '../data/file_transfer_service.dart';
import '../domain/transfer_request.dart';

enum SharedDownloadPreparationStage {
  preparingRequest,
  checkingExistingLocalFiles,
  startingReceiver,
  waitingForRemote,
}

enum SharedUploadPreparationStage {
  resolvingSelection,
  preparingTransfer,
  waitingForRequester,
}

enum SharedDownloadHashPreparationMode { full, cachedOnly, none }

class SharedDownloadPreparationState {
  const SharedDownloadPreparationState({
    required this.requestId,
    required this.ownerName,
    required this.stage,
  });

  final String requestId;
  final String ownerName;
  final SharedDownloadPreparationStage stage;

  String get message {
    switch (stage) {
      case SharedDownloadPreparationStage.preparingRequest:
        return 'Подготавливаем запрос для $ownerName...';
      case SharedDownloadPreparationStage.checkingExistingLocalFiles:
        return 'Проверяем, какие файлы уже есть локально...';
      case SharedDownloadPreparationStage.startingReceiver:
        return 'Запускаем приём для $ownerName...';
      case SharedDownloadPreparationStage.waitingForRemote:
        return 'Ждём, пока $ownerName начнёт передачу...';
    }
  }
}

class SharedUploadPreparationState {
  const SharedUploadPreparationState({
    required this.requestId,
    required this.requesterName,
    required this.stage,
  });

  final String requestId;
  final String requesterName;
  final SharedUploadPreparationStage stage;

  String get message {
    switch (stage) {
      case SharedUploadPreparationStage.resolvingSelection:
        return 'Определяем, что нужно отправить для $requesterName...';
      case SharedUploadPreparationStage.preparingTransfer:
        return 'Подготавливаем отправку для $requesterName...';
      case SharedUploadPreparationStage.waitingForRequester:
        return 'Ждём, пока $requesterName подтвердит приём...';
    }
  }
}

class SharedDownloadPreparedFile {
  const SharedDownloadPreparedFile({
    required this.sourcePath,
    required this.announcement,
    this.deleteAfterTransfer = false,
  });

  final String sourcePath;
  final TransferAnnouncementItem announcement;
  final bool deleteAfterTransfer;
}

class SharedDownloadWholeShareSendPlan {
  const SharedDownloadWholeShareSendPlan({
    required this.manifestItems,
    required this.firstBatchFiles,
    required this.resolveBatch,
  });

  final List<TransferFileManifestItem> manifestItems;
  final List<TransferSourceFile> firstBatchFiles;
  final Future<TransferSourceBatch> Function(int startIndex) resolveBatch;
}
