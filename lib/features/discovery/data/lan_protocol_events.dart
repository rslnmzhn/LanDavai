import 'dart:typed_data';

import 'lan_packet_codec_models.dart';

// Shared decoded-packet event surface for protocol handlers and service callbacks.
class AppPresenceEvent {
  AppPresenceEvent({
    required this.ip,
    required this.deviceName,
    required this.observedAt,
    this.peerId,
    this.operatingSystem,
    this.deviceType,
    this.nearbyTransferPort,
  });

  final String ip;
  final String deviceName;
  final DateTime observedAt;
  final String? peerId;
  final String? operatingSystem;
  final String? deviceType;
  final int? nearbyTransferPort;
}

class TransferRequestEvent {
  TransferRequestEvent({
    required this.requestId,
    required this.senderIp,
    required this.senderName,
    required this.senderMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
    required this.observedAt,
  });

  final String requestId;
  final String senderIp;
  final String senderName;
  final String senderMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferAnnouncementItem> items;
  final DateTime observedAt;
}

class TransferDecisionEvent {
  TransferDecisionEvent({
    required this.requestId,
    required this.approved,
    required this.receiverName,
    required this.receiverIp,
    required this.transferPort,
    required this.observedAt,
    this.acceptedFileNames,
  });

  final String requestId;
  final bool approved;
  final String receiverName;
  final String receiverIp;
  final int? transferPort;
  final DateTime observedAt;
  final List<String>? acceptedFileNames;
}

class FriendRequestEvent {
  const FriendRequestEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final String requesterMacAddress;
  final DateTime observedAt;
}

class FriendResponseEvent {
  const FriendResponseEvent({
    required this.requestId,
    required this.responderIp,
    required this.responderName,
    required this.responderMacAddress,
    required this.accepted,
    required this.observedAt,
  });

  final String requestId;
  final String responderIp;
  final String responderName;
  final String responderMacAddress;
  final bool accepted;
  final DateTime observedAt;
}

class ShareQueryEvent {
  ShareQueryEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final DateTime observedAt;
}

class ShareCatalogEvent {
  ShareCatalogEvent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
    required this.removedCacheIds,
    required this.observedAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
  final List<String> removedCacheIds;
  final DateTime observedAt;
}

class DownloadRequestEvent {
  DownloadRequestEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.cacheId,
    required this.selectedRelativePaths,
    required this.selectedFolderPrefixes,
    this.transferPort,
    required this.previewMode,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final String requesterMacAddress;
  final String cacheId;
  final List<String> selectedRelativePaths;
  final List<String> selectedFolderPrefixes;
  final int? transferPort;
  final bool previewMode;
  final DateTime observedAt;
}

class DownloadResponseEvent {
  DownloadResponseEvent({
    required this.requestId,
    required this.responderIp,
    required this.responderName,
    required this.approved,
    required this.observedAt,
    this.message,
  });

  final String requestId;
  final String responderIp;
  final String responderName;
  final bool approved;
  final String? message;
  final DateTime observedAt;
}

class ClipboardQueryEvent {
  const ClipboardQueryEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.maxEntries,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final String requesterMacAddress;
  final int maxEntries;
  final DateTime observedAt;
}

class ClipboardCatalogEvent {
  const ClipboardCatalogEvent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
    required this.observedAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String ownerMacAddress;
  final List<ClipboardCatalogItem> entries;
  final DateTime observedAt;
}

class ThumbnailSyncRequestEvent {
  const ThumbnailSyncRequestEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.items,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final List<ThumbnailSyncItem> items;
  final DateTime observedAt;
}

class ThumbnailPacketEvent {
  const ThumbnailPacketEvent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
    required this.bytes,
    required this.observedAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerMacAddress;
  final String cacheId;
  final String relativePath;
  final String thumbnailId;
  final Uint8List bytes;
  final DateTime observedAt;
}
