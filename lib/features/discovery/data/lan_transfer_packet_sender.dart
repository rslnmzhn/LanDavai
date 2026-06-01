import 'lan_outgoing_packet_sender.dart';
import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanTransferPacketSender {
  const LanTransferPacketSender({
    required LanPacketCodec packetCodec,
    required LanOutgoingPacketSender outgoingPacketSender,
  }) : _packetCodec = packetCodec,
       _outgoingPacketSender = outgoingPacketSender;

  final LanPacketCodec _packetCodec;
  final LanOutgoingPacketSender _outgoingPacketSender;

  Future<void> sendTransferRequest({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String senderName,
    required String senderMacAddress,
    required String sharedCacheId,
    required String sharedLabel,
    required List<TransferAnnouncementItem> items,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanTransferRequestPrefix,
      packet: _packetCodec.encodeTransferRequest(
        instanceId: instanceId,
        requestId: requestId,
        senderName: senderName,
        senderMacAddress: senderMacAddress,
        sharedCacheId: sharedCacheId,
        sharedLabel: sharedLabel,
        items: items,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendTransferDecision({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required bool approved,
    required String receiverName,
    int? transferPort,
    List<String>? acceptedFileNames,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanTransferDecisionPrefix,
      packet: _packetCodec.encodeTransferDecision(
        instanceId: instanceId,
        requestId: requestId,
        approved: approved,
        receiverName: receiverName,
        transferPort: transferPort,
        acceptedFileNames: acceptedFileNames,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }
}
