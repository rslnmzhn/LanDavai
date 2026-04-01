import 'lan_packet_codec_models.dart';
import 'lan_protocol_events.dart';

class LanClipboardProtocolHandler {
  const LanClipboardProtocolHandler();

  ClipboardQueryEvent handleClipboardQueryPacket({
    required LanClipboardQueryPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return ClipboardQueryEvent(
      requestId: packet.requestId,
      requesterIp: senderIp,
      requesterName: packet.requesterName,
      requesterMacAddress: packet.requesterMacAddress,
      maxEntries: packet.maxEntries,
      observedAt: observedAt,
    );
  }

  ClipboardCatalogEvent handleClipboardCatalogPacket({
    required LanClipboardCatalogPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return ClipboardCatalogEvent(
      requestId: packet.requestId,
      ownerIp: senderIp,
      ownerName: packet.ownerName,
      ownerMacAddress: packet.ownerMacAddress,
      entries: packet.entries,
      observedAt: observedAt,
    );
  }
}
