import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanShareCatalogChunkEncoder {
  const LanShareCatalogChunkEncoder({
    required LanPacketCodec packetCodec,
    required void Function(String message) log,
  }) : _packetCodec = packetCodec,
       _log = log;

  final LanPacketCodec _packetCodec;
  final void Function(String message) _log;

  List<EncodedLanPacket> buildCatalogPackets({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    List<String> removedCacheIds = const <String>[],
    required int createdAtMs,
  }) {
    final packets = _packetCodec.encodeShareCatalogChunks(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
      createdAtMs: createdAtMs,
    );
    if (packets.isEmpty) {
      _log('Skipping $lanShareCatalogPrefix packet: codec rejected payload.');
    }
    return packets;
  }
}
