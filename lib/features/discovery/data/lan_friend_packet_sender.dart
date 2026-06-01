import 'lan_outgoing_packet_sender.dart';
import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_packet_codec_common.dart';

class LanFriendPacketSender {
  const LanFriendPacketSender({
    required LanPacketCodec packetCodec,
    required LanOutgoingPacketSender outgoingPacketSender,
  }) : _packetCodec = packetCodec,
       _outgoingPacketSender = outgoingPacketSender;

  final LanPacketCodec _packetCodec;
  final LanOutgoingPacketSender _outgoingPacketSender;

  Future<void> sendFriendRequest({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanFriendRequestPrefix,
      packet: _packetCodec.encodeFriendRequest(
        instanceId: instanceId,
        requestId: requestId,
        requesterName: requesterName,
        requesterMacAddress: requesterMacAddress,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendFriendResponse({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String responderName,
    required String responderMacAddress,
    required bool accepted,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanFriendResponsePrefix,
      packet: _packetCodec.encodeFriendResponse(
        instanceId: instanceId,
        requestId: requestId,
        responderName: responderName,
        responderMacAddress: responderMacAddress,
        accepted: accepted,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }
}
