import 'lan_clipboard_catalog_packet_fitter.dart';
import 'lan_outgoing_packet_sender.dart';
import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanClipboardPacketSender {
  LanClipboardPacketSender({
    required LanPacketCodec packetCodec,
    required LanOutgoingPacketSender outgoingPacketSender,
    required void Function(String message) log,
  }) : _packetCodec = packetCodec,
       _outgoingPacketSender = outgoingPacketSender,
       _clipboardCatalogPacketFitter = LanClipboardCatalogPacketFitter(
         packetCodec: packetCodec,
         log: log,
       );

  final LanPacketCodec _packetCodec;
  final LanOutgoingPacketSender _outgoingPacketSender;
  final LanClipboardCatalogPacketFitter _clipboardCatalogPacketFitter;

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
    final packet = _clipboardCatalogPacketFitter.buildCatalogPacket(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      createdAtMs: createdAtMs,
    );
    await _outgoingPacketSender.sendPacket(
      prefix: lanClipboardCatalogPrefix,
      packet: packet,
      targetIp: targetIp,
    );
  }
}
