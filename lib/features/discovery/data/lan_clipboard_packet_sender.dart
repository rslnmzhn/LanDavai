import 'lan_outgoing_packet_sender.dart';
import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanClipboardPacketSender {
  const LanClipboardPacketSender({
    required LanPacketCodec packetCodec,
    required LanOutgoingPacketSender outgoingPacketSender,
    required void Function(String message) log,
  }) : _packetCodec = packetCodec,
       _outgoingPacketSender = outgoingPacketSender,
       _log = log;

  final LanPacketCodec _packetCodec;
  final LanOutgoingPacketSender _outgoingPacketSender;
  final void Function(String message) _log;

  Future<void> sendClipboardQuery({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanClipboardQueryPrefix,
      packet: _packetCodec.encodeClipboardQuery(
        instanceId: instanceId,
        requestId: requestId,
        requesterName: requesterName,
        requesterMacAddress: requesterMacAddress,
        maxEntries: maxEntries,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendClipboardCatalog({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
  }) async {
    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
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
    await _outgoingPacketSender.sendPacket(
      prefix: lanClipboardCatalogPrefix,
      packet: _packetCodec.encodeClipboardCatalog(
        instanceId: instanceId,
        requestId: requestId,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: fittedEntries,
        createdAtMs: createdAtMs,
      ),
      targetIp: targetIp,
    );
  }
}
