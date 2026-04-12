import 'lan_packet_codec_models.dart';
import 'lan_protocol_events.dart';

class LanShareProtocolHandler {
  const LanShareProtocolHandler();

  ShareQueryEvent handleShareQueryPacket({
    required LanShareQueryPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return ShareQueryEvent(
      requestId: packet.requestId,
      requesterIp: senderIp,
      requesterName: packet.requesterName,
      observedAt: observedAt,
    );
  }

  ShareAccessRequestEvent handleShareAccessRequestPacket({
    required LanShareAccessRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return ShareAccessRequestEvent(
      requestId: packet.requestId,
      requesterIp: senderIp,
      requesterName: packet.requesterName,
      requesterMacAddress: packet.requesterMacAddress,
      transferPort: packet.transferPort,
      observedAt: observedAt,
    );
  }

  ShareAccessResponseEvent handleShareAccessResponsePacket({
    required LanShareAccessResponsePacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return ShareAccessResponseEvent(
      requestId: packet.requestId,
      responderIp: senderIp,
      responderName: packet.responderName,
      approved: packet.approved,
      observedAt: observedAt,
      message: packet.message,
    );
  }

  ShareCatalogEvent handleShareCatalogPacket({
    required LanShareCatalogPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return ShareCatalogEvent(
      requestId: packet.requestId,
      ownerIp: senderIp,
      ownerName: packet.ownerName,
      ownerMacAddress: packet.ownerMacAddress,
      entries: packet.entries,
      removedCacheIds: packet.removedCacheIds,
      observedAt: observedAt,
    );
  }

  DownloadRequestEvent handleDownloadRequestPacket({
    required LanDownloadRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return DownloadRequestEvent(
      requestId: packet.requestId,
      requesterIp: senderIp,
      requesterName: packet.requesterName,
      requesterMacAddress: packet.requesterMacAddress,
      cacheId: packet.cacheId,
      selectedRelativePaths: packet.selectedRelativePaths,
      selectedFolderPrefixes: packet.selectedFolderPrefixes,
      transferPort: packet.transferPort,
      previewMode: packet.previewMode,
      observedAt: observedAt,
    );
  }

  DownloadResponseEvent handleDownloadResponsePacket({
    required LanDownloadResponsePacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return DownloadResponseEvent(
      requestId: packet.requestId,
      responderIp: senderIp,
      responderName: packet.responderName,
      approved: packet.approved,
      message: packet.message,
      observedAt: observedAt,
    );
  }

  ThumbnailSyncRequestEvent handleThumbnailSyncRequestPacket({
    required LanThumbnailSyncRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return ThumbnailSyncRequestEvent(
      requestId: packet.requestId,
      requesterIp: senderIp,
      requesterName: packet.requesterName,
      items: packet.items,
      observedAt: observedAt,
    );
  }

  ThumbnailPacketEvent handleThumbnailPacket({
    required LanThumbnailPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return ThumbnailPacketEvent(
      requestId: packet.requestId,
      ownerIp: senderIp,
      ownerMacAddress: packet.ownerMacAddress,
      cacheId: packet.cacheId,
      relativePath: packet.relativePath,
      thumbnailId: packet.thumbnailId,
      bytes: packet.bytes,
      observedAt: observedAt,
    );
  }
}
