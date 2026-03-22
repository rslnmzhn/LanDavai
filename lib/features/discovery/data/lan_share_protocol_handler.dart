import 'lan_packet_codec.dart';
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
      previewMode: packet.previewMode,
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
