import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanTransferPacketCodec {
  const LanTransferPacketCodec();

  EncodedLanPacket? encodeTransferRequest({
    required String instanceId,
    required String requestId,
    required String senderName,
    required String senderMacAddress,
    required String sharedCacheId,
    required String sharedLabel,
    required List<TransferAnnouncementItem> items,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'senderName': senderName,
      'senderMacAddress': senderMacAddress,
      'sharedCacheId': sharedCacheId,
      'sharedLabel': sharedLabel,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanTransferRequestPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeTransferDecision({
    required String instanceId,
    required String requestId,
    required bool approved,
    required String receiverName,
    required int createdAtMs,
    int? transferPort,
    List<String>? acceptedFileNames,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'approved': approved,
      'receiverName': receiverName,
      'createdAtMs': createdAtMs,
    };
    if (transferPort != null) {
      payload['transferPort'] = transferPort;
    }
    if (acceptedFileNames != null) {
      payload['acceptedFileNames'] = acceptedFileNames;
    }
    return encodeLanEnvelopePacket(
      prefix: lanTransferDecisionPrefix,
      payload: payload,
    );
  }

  LanTransferRequestPacket? parseTransferRequestPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanTransferRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final requestId = decoded['requestId'] as String?;
    final senderName = decoded['senderName'] as String?;
    final senderMacAddress = decoded['senderMacAddress'] as String?;
    final sharedCacheId = decoded['sharedCacheId'] as String?;
    final sharedLabel = decoded['sharedLabel'] as String?;
    final instanceId = decoded['instanceId'] as String?;
    final itemsRaw = decoded['items'];
    if (requestId == null ||
        senderName == null ||
        senderMacAddress == null ||
        sharedCacheId == null ||
        sharedLabel == null ||
        instanceId == null ||
        itemsRaw is! List<dynamic>) {
      return null;
    }

    final items = <TransferAnnouncementItem>[];
    for (final item in itemsRaw) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final parsed = TransferAnnouncementItem.fromJson(item);
      if (parsed != null) {
        items.add(parsed);
      }
    }
    if (items.isEmpty) {
      return null;
    }

    return LanTransferRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      senderName: senderName,
      senderMacAddress: senderMacAddress,
      sharedCacheId: sharedCacheId,
      sharedLabel: sharedLabel,
      items: items,
    );
  }

  LanTransferDecisionPacket? parseTransferDecisionPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanTransferDecisionPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final requestId = decoded['requestId'] as String?;
    final receiverName = decoded['receiverName'] as String?;
    final approved = decoded['approved'] as bool?;
    final instanceId = decoded['instanceId'] as String?;
    final transferPortRaw = decoded['transferPort'];
    int? transferPort;
    if (transferPortRaw is num) {
      transferPort = transferPortRaw.toInt();
    }
    List<String>? acceptedFileNames;
    final acceptedRaw = decoded['acceptedFileNames'];
    if (acceptedRaw is List<dynamic>) {
      acceptedFileNames = acceptedRaw
          .whereType<String>()
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toList(growable: false);
    }
    if (requestId == null ||
        receiverName == null ||
        approved == null ||
        instanceId == null) {
      return null;
    }

    return LanTransferDecisionPacket(
      instanceId: instanceId,
      requestId: requestId,
      receiverName: receiverName,
      approved: approved,
      transferPort: transferPort,
      acceptedFileNames: acceptedFileNames,
    );
  }
}
