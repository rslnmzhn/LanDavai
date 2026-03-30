import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanFriendPacketCodec {
  const LanFriendPacketCodec();

  EncodedLanPacket? encodeFriendRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'requesterMacAddress': requesterMacAddress,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanFriendRequestPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeFriendResponse({
    required String instanceId,
    required String requestId,
    required String responderName,
    required String responderMacAddress,
    required bool accepted,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'responderName': responderName,
      'responderMacAddress': responderMacAddress,
      'accepted': accepted,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanFriendResponsePrefix,
      payload: payload,
    );
  }

  LanFriendRequestPacket? parseFriendRequestPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanFriendRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final requesterMacAddress = decoded['requesterMacAddress'] as String?;
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        requesterMacAddress == null) {
      return null;
    }

    return LanFriendRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
    );
  }

  LanFriendResponsePacket? parseFriendResponsePacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanFriendResponsePrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final responderName = decoded['responderName'] as String?;
    final responderMacAddress = decoded['responderMacAddress'] as String?;
    final accepted = decoded['accepted'] as bool?;
    if (instanceId == null ||
        requestId == null ||
        responderName == null ||
        responderMacAddress == null ||
        accepted == null) {
      return null;
    }

    return LanFriendResponsePacket(
      instanceId: instanceId,
      requestId: requestId,
      responderName: responderName,
      responderMacAddress: responderMacAddress,
      accepted: accepted,
    );
  }
}
