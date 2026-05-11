import '../data/file_transfer_service.dart';
import '../../discovery/data/lan_packet_codec_models.dart';
import 'remote_share_access_session_models.dart';
import 'shared_download_boundary.dart';
import 'transfer_session_coordinator.dart';

typedef RemoteShareAccessDiagnosticWriter =
    void Function({
      required String stage,
      String? requestId,
      Map<String, Object?> details,
      Object? error,
      StackTrace? stackTrace,
    });

typedef RemoteShareAccessDiagnosticLoggerFactory =
    TransferRuntimeDiagnosticCallback Function({
      required String requestId,
      required Map<String, Object?> baseDetails,
    });

typedef RemoteShareAccessSnapshotApplier =
    Future<RemoteShareAccessProjectionLoadResult> Function({
      required String ownerIp,
      required String ownerName,
      required String ownerMacAddress,
      required List<SharedCatalogEntryItem> entries,
    });

typedef RemoteShareAccessSnapshotBuilder =
    Future<RemoteShareAccessPreparedSnapshot> Function({
      required String requestId,
    });

typedef RemoteShareAccessPreparedMetricsReader =
    Future<({int sizeBytes, String sha256, int modifiedAtMs})> Function(
      String filePath,
    );

typedef RemoteShareAccessSnapshotSender =
    Future<void> Function({
      required String requestId,
      required String targetIp,
      required String receiverName,
      required int transferPort,
      required List<TransferSourceFile> files,
      Map<String, Object?> diagnosticDetails,
    });

typedef RemoteShareAccessSnapshotResponseSender =
    Future<void> Function({
      required String targetIp,
      required String requestId,
      required String responderName,
      required bool approved,
      String? message,
    });

typedef RemoteShareAccessUploadPreparationSetter =
    void Function({
      required String requestId,
      required String requesterName,
      required SharedUploadPreparationStage stage,
    });

typedef RemoteShareAccessUploadPreparationClearer =
    void Function({String? requestId});

typedef RemoteShareAccessNoticePublisher =
    void Function(TransferSessionNotice notice);
