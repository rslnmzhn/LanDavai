import 'lan_packet_codec.dart';
import 'lan_protocol_events.dart';

class LanFriendProtocolHandler {
  const LanFriendProtocolHandler();

  FriendRequestEvent handleFriendRequestPacket({
    required LanFriendRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return FriendRequestEvent(
      requestId: packet.requestId,
      requesterIp: senderIp,
      requesterName: packet.requesterName,
      requesterMacAddress: packet.requesterMacAddress,
      observedAt: observedAt,
    );
  }

  FriendResponseEvent handleFriendResponsePacket({
    required LanFriendResponsePacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    return FriendResponseEvent(
      requestId: packet.requestId,
      responderIp: senderIp,
      responderName: packet.responderName,
      responderMacAddress: packet.responderMacAddress,
      accepted: packet.accepted,
      observedAt: observedAt,
    );
  }
}
