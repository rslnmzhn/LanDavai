import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_packet_codec_models.dart';

class LanClipboardCatalogPacketFitter {
  const LanClipboardCatalogPacketFitter({
    required LanPacketCodec packetCodec,
    required void Function(String message) log,
  }) : _packetCodec = packetCodec,
       _log = log;

  final LanPacketCodec _packetCodec;
  final void Function(String message) _log;

  EncodedLanPacket? buildCatalogPacket({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
    required int createdAtMs,
  }) {
    final fittedEntries = _packetCodec.fitClipboardCatalogEntries(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      createdAtMs: createdAtMs,
    );
    if (fittedEntries.length < entries.length) {
      _log(
        'Clipboard catalog trimmed for UDP: '
        'entries=${fittedEntries.length}/${entries.length}',
      );
    }
    return _packetCodec.encodeClipboardCatalog(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: fittedEntries,
      createdAtMs: createdAtMs,
    );
  }
}
