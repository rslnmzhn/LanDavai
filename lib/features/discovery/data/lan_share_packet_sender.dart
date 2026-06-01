import 'dart:typed_data';

import 'lan_outgoing_packet_sender.dart';
import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';
import 'lan_share_catalog_chunk_encoder.dart';

class LanSharePacketSender {
  LanSharePacketSender({
    required LanPacketCodec packetCodec,
    required LanOutgoingPacketSender outgoingPacketSender,
    required void Function(String message) log,
  }) : _packetCodec = packetCodec,
       _outgoingPacketSender = outgoingPacketSender,
       _shareCatalogChunkEncoder = LanShareCatalogChunkEncoder(
         packetCodec: packetCodec,
         log: log,
       );

  final LanPacketCodec _packetCodec;
  final LanOutgoingPacketSender _outgoingPacketSender;
  final LanShareCatalogChunkEncoder _shareCatalogChunkEncoder;

  Future<void> sendShareQuery({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String requesterName,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanShareQueryPrefix,
      packet: _packetCodec.encodeShareQuery(
        instanceId: instanceId,
        requestId: requestId,
        requesterName: requesterName,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendShareAccessRequest({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int transferPort,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanShareAccessRequestPrefix,
      packet: _packetCodec.encodeShareAccessRequest(
        instanceId: instanceId,
        requestId: requestId,
        requesterName: requesterName,
        requesterMacAddress: requesterMacAddress,
        transferPort: transferPort,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendShareAccessResponse({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String responderName,
    required bool approved,
    String? message,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanShareAccessResponsePrefix,
      packet: _packetCodec.encodeShareAccessResponse(
        instanceId: instanceId,
        requestId: requestId,
        responderName: responderName,
        approved: approved,
        message: message,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendShareCatalog({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    List<String> removedCacheIds = const <String>[],
  }) async {
    final packets = _shareCatalogChunkEncoder.buildCatalogPackets(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (packets.isEmpty) {
      return;
    }
    await _outgoingPacketSender.sendPackets(
      prefix: lanShareCatalogPrefix,
      packets: packets,
      targetIp: targetIp,
    );
  }

  Future<void> sendDownloadRequest({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required String cacheId,
    List<String> selectedRelativePaths = const <String>[],
    List<String> selectedFolderPrefixes = const <String>[],
    int? transferPort,
    bool previewMode = false,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanDownloadRequestPrefix,
      packet: _packetCodec.encodeDownloadRequest(
        instanceId: instanceId,
        requestId: requestId,
        requesterName: requesterName,
        requesterMacAddress: requesterMacAddress,
        cacheId: cacheId,
        selectedRelativePaths: selectedRelativePaths,
        selectedFolderPrefixes: selectedFolderPrefixes,
        transferPort: transferPort,
        previewMode: previewMode,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendDownloadResponse({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String responderName,
    required bool approved,
    String? phase,
    String? message,
  }) async {
    await _outgoingPacketSender.sendPacket(
      prefix: lanDownloadResponsePrefix,
      packet: _packetCodec.encodeDownloadResponse(
        instanceId: instanceId,
        requestId: requestId,
        responderName: responderName,
        approved: approved,
        phase: phase,
        message: message,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendThumbnailSyncRequest({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
  }) async {
    if (items.isEmpty) {
      return;
    }
    await _outgoingPacketSender.sendPacket(
      prefix: lanThumbnailSyncRequestPrefix,
      packet: _packetCodec.encodeThumbnailSyncRequest(
        instanceId: instanceId,
        requestId: requestId,
        requesterName: requesterName,
        items: items,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendThumbnailPacket({
    required String instanceId,
    required String targetIp,
    required String requestId,
    required String ownerMacAddress,
    required String cacheId,
    required String relativePath,
    required String thumbnailId,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      return;
    }
    await _outgoingPacketSender.sendPacket(
      prefix: lanThumbnailPacketPrefix,
      packet: _packetCodec.encodeThumbnailPacket(
        instanceId: instanceId,
        requestId: requestId,
        ownerMacAddress: ownerMacAddress,
        cacheId: cacheId,
        relativePath: relativePath,
        thumbnailId: thumbnailId,
        bytes: bytes,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }
}
