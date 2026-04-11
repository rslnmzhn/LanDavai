class TransferFileManifestItem {
  const TransferFileManifestItem({
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
  });

  final String fileName;
  final int sizeBytes;
  final String sha256;

  Map<String, Object> toJson() {
    return <String, Object>{
      'fileName': fileName,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
    };
  }

  static TransferFileManifestItem fromJson(Map<String, dynamic> json) {
    return TransferFileManifestItem(
      fileName: json['fileName'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      sha256: json['sha256'] as String,
    );
  }
}

class IncomingTransferRequest {
  IncomingTransferRequest({
    required this.requestId,
    required this.senderIp,
    required this.senderName,
    required this.senderMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
    required this.createdAt,
  });

  final String requestId;
  final String senderIp;
  final String senderName;
  final String senderMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferFileManifestItem> items;
  final DateTime createdAt;

  int get totalBytes => items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
}

class IncomingSharedDownloadRequest {
  IncomingSharedDownloadRequest({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.selectedRelativePaths,
    required this.selectedFolderPrefixes,
    required this.transferPort,
    required this.createdAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final String requesterMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<String> selectedRelativePaths;
  final List<String> selectedFolderPrefixes;
  final int? transferPort;
  final DateTime createdAt;

  bool get requestsWholeShare =>
      selectedRelativePaths.isEmpty && selectedFolderPrefixes.isEmpty;
  int get requestedFileCount => selectedRelativePaths.length;
  int get requestedFolderCount =>
      requestsWholeShare ? 1 : selectedFolderPrefixes.length;
  bool get isMixedSelection =>
      selectedRelativePaths.isNotEmpty && selectedFolderPrefixes.isNotEmpty;

  List<String> get requestedLabels {
    if (requestsWholeShare) {
      return <String>[sharedLabel];
    }
    return <String>[
      ...selectedRelativePaths,
      ...selectedFolderPrefixes,
    ].toList(growable: false);
  }
}
