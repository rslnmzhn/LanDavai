import 'dart:typed_data';

import 'lan_clipboard_packet_codec.dart';
import 'lan_friend_packet_codec.dart';
import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';
import 'lan_presence_packet_codec.dart';
import 'lan_share_packet_codec.dart';
import 'lan_transfer_packet_codec.dart';

export 'lan_packet_codec_models.dart';

// Thin compatibility facade over family-specific protocol codecs.
class LanPacketCodec {
  static const String discoverPrefix = lanDiscoverPrefix;
  static const String responsePrefix = lanResponsePrefix;
  static const String transferRequestPrefix = lanTransferRequestPrefix;
  static const String transferDecisionPrefix = lanTransferDecisionPrefix;
  static const String friendRequestPrefix = lanFriendRequestPrefix;
  static const String friendResponsePrefix = lanFriendResponsePrefix;
  static const String shareQueryPrefix = lanShareQueryPrefix;
  static const String shareCatalogPrefix = lanShareCatalogPrefix;
  static const String downloadRequestPrefix = lanDownloadRequestPrefix;
  static const String downloadResponsePrefix = lanDownloadResponsePrefix;
  static const String thumbnailSyncRequestPrefix =
      lanThumbnailSyncRequestPrefix;
  static const String thumbnailPacketPrefix = lanThumbnailPacketPrefix;
  static const String clipboardQueryPrefix = lanClipboardQueryPrefix;
  static const String clipboardCatalogPrefix = lanClipboardCatalogPrefix;

  static const Map<String, String> protocolPrefixes = lanProtocolPrefixes;

  LanPacketCodec({String? operatingSystem, String? deviceType})
    : _presenceCodec = LanPresencePacketCodec(
        operatingSystem: operatingSystem,
        deviceType: deviceType,
      );

  final LanPresencePacketCodec _presenceCodec;
  final LanTransferPacketCodec _transferCodec = const LanTransferPacketCodec();
  final LanFriendPacketCodec _friendCodec = const LanFriendPacketCodec();
  final LanSharePacketCodec _shareCodec = const LanSharePacketCodec();
  final LanClipboardPacketCodec _clipboardCodec =
      const LanClipboardPacketCodec();

  String encodeDiscoveryRequest({
    required String instanceId,
    required String deviceName,
    required String localPeerId,
    int? nearbyTransferPort,
  }) {
    return _presenceCodec.encodeDiscoveryRequest(
      instanceId: instanceId,
      deviceName: deviceName,
      localPeerId: localPeerId,
      nearbyTransferPort: nearbyTransferPort,
    );
  }

  String encodeDiscoveryResponse({
    required String instanceId,
    required String deviceName,
    required String localPeerId,
    int? nearbyTransferPort,
  }) {
    return _presenceCodec.encodeDiscoveryResponse(
      instanceId: instanceId,
      deviceName: deviceName,
      localPeerId: localPeerId,
      nearbyTransferPort: nearbyTransferPort,
    );
  }

  LanDiscoveryPresencePacket? decodeDiscoveryPacket(String message) {
    return _presenceCodec.decodeDiscoveryPacket(message);
  }

  LanInboundPacket? decodeIncomingPacket(String message) {
    final discoveryPacket = decodeDiscoveryPacket(message);
    if (discoveryPacket != null) {
      return discoveryPacket;
    }

    final splitIndex = message.indexOf('|');
    if (splitIndex <= 0) {
      return null;
    }

    final prefix = message.substring(0, splitIndex).trim();
    switch (prefix) {
      case lanTransferRequestPrefix:
        return _transferCodec.parseTransferRequestPacket(message);
      case lanTransferDecisionPrefix:
        return _transferCodec.parseTransferDecisionPacket(message);
      case lanFriendRequestPrefix:
        return _friendCodec.parseFriendRequestPacket(message);
      case lanFriendResponsePrefix:
        return _friendCodec.parseFriendResponsePacket(message);
      case lanShareQueryPrefix:
        return _shareCodec.parseShareQueryPacket(message);
      case lanShareCatalogPrefix:
        return _shareCodec.parseShareCatalogPacket(message);
      case lanDownloadRequestPrefix:
        return _shareCodec.parseDownloadRequestPacket(message);
      case lanDownloadResponsePrefix:
        return _shareCodec.parseDownloadResponsePacket(message);
      case lanThumbnailSyncRequestPrefix:
        return _shareCodec.parseThumbnailSyncRequestPacket(message);
      case lanThumbnailPacketPrefix:
        return _shareCodec.parseThumbnailPacket(message);
      case lanClipboardQueryPrefix:
        return _clipboardCodec.parseClipboardQueryPacket(message);
      case lanClipboardCatalogPrefix:
        return _clipboardCodec.parseClipboardCatalogPacket(message);
    }

    return null;
  }

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
    return _transferCodec.encodeTransferRequest(
      instanceId: instanceId,
      requestId: requestId,
      senderName: senderName,
      senderMacAddress: senderMacAddress,
      sharedCacheId: sharedCacheId,
      sharedLabel: sharedLabel,
      items: items,
      createdAtMs: createdAtMs,
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
    return _transferCodec.encodeTransferDecision(
      instanceId: instanceId,
      requestId: requestId,
      approved: approved,
      receiverName: receiverName,
      createdAtMs: createdAtMs,
      transferPort: transferPort,
      acceptedFileNames: acceptedFileNames,
    );
  }

  EncodedLanPacket? encodeFriendRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int createdAtMs,
  }) {
    return _friendCodec.encodeFriendRequest(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      createdAtMs: createdAtMs,
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
    return _friendCodec.encodeFriendResponse(
      instanceId: instanceId,
      requestId: requestId,
      responderName: responderName,
      responderMacAddress: responderMacAddress,
      accepted: accepted,
      createdAtMs: createdAtMs,
    );
  }

  EncodedLanPacket? encodeShareQuery({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required int createdAtMs,
  }) {
    return _shareCodec.encodeShareQuery(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      createdAtMs: createdAtMs,
    );
  }

  EncodedLanPacket? encodeShareCatalog({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    required List<String> removedCacheIds,
    required int createdAtMs,
  }) {
    return _shareCodec.encodeShareCatalog(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
      createdAtMs: createdAtMs,
    );
  }

  EncodedLanPacket? encodeDownloadRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required String cacheId,
    required List<String> selectedRelativePaths,
    required List<String> selectedFolderPrefixes,
    int? transferPort,
    required bool previewMode,
    required int createdAtMs,
  }) {
    return _shareCodec.encodeDownloadRequest(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      cacheId: cacheId,
      selectedRelativePaths: selectedRelativePaths,
      selectedFolderPrefixes: selectedFolderPrefixes,
      transferPort: transferPort,
      previewMode: previewMode,
      createdAtMs: createdAtMs,
    );
  }

  EncodedLanPacket? encodeDownloadResponse({
    required String instanceId,
    required String requestId,
    required String responderName,
    required bool approved,
    String? message,
    required int createdAtMs,
  }) {
    return _shareCodec.encodeDownloadResponse(
      instanceId: instanceId,
      requestId: requestId,
      responderName: responderName,
      approved: approved,
      message: message,
      createdAtMs: createdAtMs,
    );
  }

  EncodedLanPacket? encodeThumbnailSyncRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
    required int createdAtMs,
  }) {
    return _shareCodec.encodeThumbnailSyncRequest(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      items: items,
      createdAtMs: createdAtMs,
    );
  }

  EncodedLanPacket? encodeThumbnailPacket({
    required String instanceId,
    required String requestId,
    required String ownerMacAddress,
    required String cacheId,
    required String relativePath,
    required String thumbnailId,
    required Uint8List bytes,
    required int createdAtMs,
  }) {
    return _shareCodec.encodeThumbnailPacket(
      instanceId: instanceId,
      requestId: requestId,
      ownerMacAddress: ownerMacAddress,
      cacheId: cacheId,
      relativePath: relativePath,
      thumbnailId: thumbnailId,
      bytes: bytes,
      createdAtMs: createdAtMs,
    );
  }

  EncodedLanPacket? encodeClipboardQuery({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
    required int createdAtMs,
  }) {
    return _clipboardCodec.encodeClipboardQuery(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      maxEntries: maxEntries,
      createdAtMs: createdAtMs,
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
    return _clipboardCodec.encodeClipboardCatalog(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      createdAtMs: createdAtMs,
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
    return _clipboardCodec.fitClipboardCatalogEntries(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      createdAtMs: createdAtMs,
    );
  }

  List<SharedCatalogEntryItem> fitShareCatalogEntries(
    List<SharedCatalogEntryItem> entries,
  ) {
    return _shareCodec.fitShareCatalogEntries(entries);
  }

  static String encodeEnvelopeForTest({
    required String prefix,
    required Map<String, Object?> payload,
  }) {
    return encodeLanEnvelopeForTest(prefix: prefix, payload: payload);
  }

  static Map<String, dynamic>? decodeEnvelopeForTest({
    required String message,
    required String expectedPrefix,
  }) {
    return decodeLanEnvelope(message: message, expectedPrefix: expectedPrefix);
  }
}
