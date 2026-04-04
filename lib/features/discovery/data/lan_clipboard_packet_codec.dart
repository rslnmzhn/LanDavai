import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanClipboardPacketCodec {
  const LanClipboardPacketCodec();

  static const int maxClipboardCatalogEntriesPerPacket = 24;

  EncodedLanPacket? encodeClipboardQuery({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'requesterMacAddress': requesterMacAddress,
      'maxEntries': maxEntries,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanClipboardQueryPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeClipboardCatalog({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'ownerName': ownerName,
      'ownerMacAddress': ownerMacAddress,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanClipboardCatalogPrefix,
      payload: payload,
    );
  }

  List<ClipboardCatalogItem> fitClipboardCatalogEntries({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
    required int createdAtMs,
  }) {
    final fitted = <ClipboardCatalogItem>[];
    for (final entry in entries.take(maxClipboardCatalogEntriesPerPacket)) {
      final candidate = <ClipboardCatalogItem>[...fitted, entry];
      final packet = encodeClipboardCatalog(
        instanceId: instanceId,
        requestId: requestId,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: candidate,
        createdAtMs: createdAtMs,
      );
      if (packet != null) {
        fitted.add(entry);
      }
    }
    return fitted;
  }

  LanClipboardQueryPacket? parseClipboardQueryPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanClipboardQueryPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final requesterMacAddress = decoded['requesterMacAddress'] as String?;
    final maxEntriesRaw = decoded['maxEntries'];
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        requesterMacAddress == null ||
        maxEntriesRaw is! num) {
      return null;
    }

    return LanClipboardQueryPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      maxEntries: maxEntriesRaw.toInt(),
    );
  }

  LanClipboardCatalogPacket? parseClipboardCatalogPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanClipboardCatalogPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final ownerName = decoded['ownerName'] as String?;
    final ownerMacAddress = decoded['ownerMacAddress'] as String?;
    final entriesRaw = decoded['entries'];
    if (instanceId == null ||
        requestId == null ||
        ownerName == null ||
        ownerMacAddress == null ||
        entriesRaw is! List<dynamic>) {
      return null;
    }

    final entries = <ClipboardCatalogItem>[];
    for (final rawEntry in entriesRaw) {
      if (rawEntry is! Map<String, dynamic>) {
        continue;
      }
      final parsed = ClipboardCatalogItem.fromJson(rawEntry);
      if (parsed != null) {
        entries.add(parsed);
      }
    }

    return LanClipboardCatalogPacket(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
    );
  }
}
