import 'dart:async';

import '../data/file_transfer_service.dart';
import '../domain/transfer_request.dart';

typedef IncomingCompletionDiagnosticWriter =
    void Function({
      required String stage,
      String? requestId,
      Map<String, Object?> details,
      Object? error,
      StackTrace? stackTrace,
    });

typedef IncomingTransferResultWaiter =
    Future<void> Function({
      required IncomingTransferRequest request,
      required TransferReceiveSession session,
      required List<TransferFileManifestItem> acceptedItems,
      required bool persistToUserDownloads,
      required bool recordHistory,
      required bool sendCompletionNotification,
      String? destinationRelativeRootPrefix,
      Completer<String?>? previewCompleter,
    });
