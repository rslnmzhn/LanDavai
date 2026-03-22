import 'lan_packet_codec.dart';
import 'lan_protocol_events.dart';

class LanTransferProtocolHandler {
  const LanTransferProtocolHandler();

  TransferRequestEvent handleTransferRequestPacket({
    required LanTransferRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return TransferRequestEvent(
      requestId: packet.requestId,
      senderIp: senderIp,
      senderName: packet.senderName,
      senderMacAddress: packet.senderMacAddress,
      sharedCacheId: packet.sharedCacheId,
      sharedLabel: packet.sharedLabel,
      items: packet.items,
      observedAt: observedAt,
    );
  }

  TransferDecisionEvent handleTransferDecisionPacket({
    required LanTransferDecisionPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return TransferDecisionEvent(
      requestId: packet.requestId,
      approved: packet.approved,
      receiverName: packet.receiverName,
      receiverIp: senderIp,
      transferPort: packet.transferPort,
      observedAt: observedAt,
      acceptedFileNames: packet.acceptedFileNames,
    );
  }
}
