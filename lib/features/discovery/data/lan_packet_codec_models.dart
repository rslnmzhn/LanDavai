import 'dart:typed_data';

class TransferAnnouncementItem {
  TransferAnnouncementItem({
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

  static TransferAnnouncementItem? fromJson(Map<String, dynamic> json) {
    final fileName = json['fileName'] as String?;
    final sizeRaw = json['sizeBytes'];
    final sha256 = json['sha256'] as String?;
    if (fileName == null || sizeRaw is! num || sha256 == null) {
      return null;
    }

    return TransferAnnouncementItem(
      fileName: fileName,
      sizeBytes: sizeRaw.toInt(),
      sha256: sha256,
    );
  }
}

class SharedCatalogFileItem {
  SharedCatalogFileItem({
    required this.relativePath,
    required this.sizeBytes,
    this.thumbnailId,
  });

  final String relativePath;
  final int sizeBytes;
  final String? thumbnailId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'relativePath': relativePath,
      'sizeBytes': sizeBytes,
      'thumbnailId': thumbnailId,
    };
  }

  static SharedCatalogFileItem? fromJson(Map<String, dynamic> json) {
    final relativePath = json['relativePath'] as String?;
    final sizeRaw = json['sizeBytes'];
    if (relativePath == null || sizeRaw is! num) {
      return null;
    }
    return SharedCatalogFileItem(
      relativePath: relativePath,
      sizeBytes: sizeRaw.toInt(),
      thumbnailId: json['thumbnailId'] as String?,
    );
  }
}

class SharedCatalogEntryItem {
  SharedCatalogEntryItem({
    required this.cacheId,
    required this.displayName,
    required this.itemCount,
    required this.totalBytes,
    required this.files,
  });

  final String cacheId;
  final String displayName;
  final int itemCount;
  final int totalBytes;
  final List<SharedCatalogFileItem> files;

  Map<String, Object> toJson() {
    return <String, Object>{
      'cacheId': cacheId,
      'displayName': displayName,
      'itemCount': itemCount,
      'totalBytes': totalBytes,
      'files': files.map((file) => file.toJson()).toList(growable: false),
    };
  }

  static SharedCatalogEntryItem? fromJson(Map<String, dynamic> json) {
    final cacheId = json['cacheId'] as String?;
    final displayName = json['displayName'] as String?;
    final itemCountRaw = json['itemCount'];
    final totalBytesRaw = json['totalBytes'];
    final filesRaw = json['files'];
    if (cacheId == null ||
        displayName == null ||
        itemCountRaw is! num ||
        totalBytesRaw is! num ||
        filesRaw is! List<dynamic>) {
      return null;
    }

    final files = <SharedCatalogFileItem>[];
    for (final file in filesRaw) {
      if (file is! Map<String, dynamic>) {
        continue;
      }
      final parsed = SharedCatalogFileItem.fromJson(file);
      if (parsed != null) {
        files.add(parsed);
      }
    }
    return SharedCatalogEntryItem(
      cacheId: cacheId,
      displayName: displayName,
      itemCount: itemCountRaw.toInt(),
      totalBytes: totalBytesRaw.toInt(),
      files: files,
    );
  }
}

class ClipboardCatalogItem {
  const ClipboardCatalogItem({
    required this.id,
    required this.entryType,
    required this.createdAtMs,
    this.textValue,
    this.imagePreviewBase64,
  });

  final String id;
  final String entryType;
  final int createdAtMs;
  final String? textValue;
  final String? imagePreviewBase64;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'entryType': entryType,
      'createdAtMs': createdAtMs,
      'textValue': textValue,
      'imagePreviewBase64': imagePreviewBase64,
    };
  }

  static ClipboardCatalogItem? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final entryType = json['entryType'] as String?;
    final createdAtRaw = json['createdAtMs'];
    if (id == null || entryType == null || createdAtRaw is! num) {
      return null;
    }
    return ClipboardCatalogItem(
      id: id,
      entryType: entryType,
      createdAtMs: createdAtRaw.toInt(),
      textValue: json['textValue'] as String?,
      imagePreviewBase64: json['imagePreviewBase64'] as String?,
    );
  }
}

class ThumbnailSyncItem {
  const ThumbnailSyncItem({
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
  });

  final String cacheId;
  final String relativePath;
  final String thumbnailId;

  Map<String, Object> toJson() {
    return <String, Object>{
      'cacheId': cacheId,
      'relativePath': relativePath,
      'thumbnailId': thumbnailId,
    };
  }

  static ThumbnailSyncItem? fromJson(Map<String, dynamic> json) {
    final cacheId = json['cacheId'] as String?;
    final relativePath = json['relativePath'] as String?;
    final thumbnailId = json['thumbnailId'] as String?;
    if (cacheId == null || relativePath == null || thumbnailId == null) {
      return null;
    }
    return ThumbnailSyncItem(
      cacheId: cacheId,
      relativePath: relativePath,
      thumbnailId: thumbnailId,
    );
  }
}

class EncodedLanPacket {
  const EncodedLanPacket({required this.prefix, required this.bytes});

  final String prefix;
  final Uint8List bytes;
}

abstract class LanInboundPacket {
  const LanInboundPacket({required this.instanceId});

  final String instanceId;
}

class LanDiscoveryPresencePacket extends LanInboundPacket {
  const LanDiscoveryPresencePacket({
    required this.prefix,
    required super.instanceId,
    required this.deviceName,
    this.operatingSystem,
    this.deviceType,
    this.peerId,
  });

  final String prefix;
  final String deviceName;
  final String? operatingSystem;
  final String? deviceType;
  final String? peerId;
}

class LanTransferRequestPacket extends LanInboundPacket {
  const LanTransferRequestPacket({
    required super.instanceId,
    required this.requestId,
    required this.senderName,
    required this.senderMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
  });

  final String requestId;
  final String senderName;
  final String senderMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferAnnouncementItem> items;
}

class LanTransferDecisionPacket extends LanInboundPacket {
  const LanTransferDecisionPacket({
    required super.instanceId,
    required this.requestId,
    required this.receiverName,
    required this.approved,
    required this.transferPort,
    this.acceptedFileNames,
  });

  final String requestId;
  final String receiverName;
  final bool approved;
  final int? transferPort;
  final List<String>? acceptedFileNames;
}

class LanFriendRequestPacket extends LanInboundPacket {
  const LanFriendRequestPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
  });

  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
}

class LanFriendResponsePacket extends LanInboundPacket {
  const LanFriendResponsePacket({
    required super.instanceId,
    required this.requestId,
    required this.responderName,
    required this.responderMacAddress,
    required this.accepted,
  });

  final String requestId;
  final String responderName;
  final String responderMacAddress;
  final bool accepted;
}

class LanShareQueryPacket extends LanInboundPacket {
  const LanShareQueryPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
  });

  final String requestId;
  final String requesterName;
}

class LanShareCatalogPacket extends LanInboundPacket {
  const LanShareCatalogPacket({
    required super.instanceId,
    required this.requestId,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
    required this.removedCacheIds,
  });

  final String requestId;
  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
  final List<String> removedCacheIds;
}

class LanDownloadRequestPacket extends LanInboundPacket {
  const LanDownloadRequestPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.cacheId,
    required this.selectedRelativePaths,
    required this.previewMode,
  });

  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
  final String cacheId;
  final List<String> selectedRelativePaths;
  final bool previewMode;
}

class LanThumbnailSyncRequestPacket extends LanInboundPacket {
  const LanThumbnailSyncRequestPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.items,
  });

  final String requestId;
  final String requesterName;
  final List<ThumbnailSyncItem> items;
}

class LanThumbnailPacket extends LanInboundPacket {
  const LanThumbnailPacket({
    required super.instanceId,
    required this.requestId,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
    required this.bytes,
  });

  final String requestId;
  final String ownerMacAddress;
  final String cacheId;
  final String relativePath;
  final String thumbnailId;
  final Uint8List bytes;
}

class LanClipboardQueryPacket extends LanInboundPacket {
  const LanClipboardQueryPacket({
    required super.instanceId,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.maxEntries,
  });

  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
  final int maxEntries;
}

class LanClipboardCatalogPacket extends LanInboundPacket {
  const LanClipboardCatalogPacket({
    required super.instanceId,
    required this.requestId,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
  });

  final String requestId;
  final String ownerName;
  final String ownerMacAddress;
  final List<ClipboardCatalogItem> entries;
}
