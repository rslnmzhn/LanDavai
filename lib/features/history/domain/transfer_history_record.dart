enum TransferHistoryDirection { download, upload }

enum TransferHistoryStatus { completed, failed }

class TransferHistoryRecord {
  TransferHistoryRecord({
    required this.id,
    required this.requestId,
    required this.direction,
    required this.peerName,
    required this.peerIp,
    required this.rootPath,
    required this.savedPaths,
    required this.fileCount,
    required this.totalBytes,
    required this.status,
    required this.createdAtMs,
  });

  final String id;
  final String? requestId;
  final TransferHistoryDirection direction;
  final String peerName;
  final String? peerIp;
  final String rootPath;
  final List<String> savedPaths;
  final int fileCount;
  final int totalBytes;
  final TransferHistoryStatus status;
  final int createdAtMs;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
}
