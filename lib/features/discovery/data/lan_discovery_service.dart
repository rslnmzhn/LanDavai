import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'discovery_transport_adapter.dart';

part 'lan_packet_codec.dart';

class AppPresenceEvent {
  AppPresenceEvent({
    required this.ip,
    required this.deviceName,
    required this.observedAt,
    this.peerId,
    this.operatingSystem,
    this.deviceType,
  });

  final String ip;
  final String deviceName;
  final DateTime observedAt;
  final String? peerId;
  final String? operatingSystem;
  final String? deviceType;
}

class InternetPeerEndpoint {
  const InternetPeerEndpoint({
    required this.friendId,
    required this.host,
    required this.port,
  });

  final String friendId;
  final String host;
  final int port;
}

class TransferAnnouncementItem {
  TransferAnnouncementItem({
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
  });

  final String fileName;
  final int sizeBytes;
  final String sha256;

  Map<String, Object> toJson() {
    return <String, Object>{
      'fileName': fileName,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
    };
  }

  static TransferAnnouncementItem? fromJson(Map<String, dynamic> json) {
    final fileName = json['fileName'] as String?;
    final sizeRaw = json['sizeBytes'];
    final sha256 = json['sha256'] as String?;
    if (fileName == null || sizeRaw is! num || sha256 == null) {
      return null;
    }

    return TransferAnnouncementItem(
      fileName: fileName,
      sizeBytes: sizeRaw.toInt(),
      sha256: sha256,
    );
  }
}

class TransferRequestEvent {
  TransferRequestEvent({
    required this.requestId,
    required this.senderIp,
    required this.senderName,
    required this.senderMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
    required this.observedAt,
  });

  final String requestId;
  final String senderIp;
  final String senderName;
  final String senderMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferAnnouncementItem> items;
  final DateTime observedAt;
}

class TransferDecisionEvent {
  TransferDecisionEvent({
    required this.requestId,
    required this.approved,
    required this.receiverName,
    required this.receiverIp,
    required this.transferPort,
    required this.observedAt,
    this.acceptedFileNames,
  });

  final String requestId;
  final bool approved;
  final String receiverName;
  final String receiverIp;
  final int? transferPort;
  final DateTime observedAt;
  final List<String>? acceptedFileNames;
}

class FriendRequestEvent {
  const FriendRequestEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final String requesterMacAddress;
  final DateTime observedAt;
}

class FriendResponseEvent {
  const FriendResponseEvent({
    required this.requestId,
    required this.responderIp,
    required this.responderName,
    required this.responderMacAddress,
    required this.accepted,
    required this.observedAt,
  });

  final String requestId;
  final String responderIp;
  final String responderName;
  final String responderMacAddress;
  final bool accepted;
  final DateTime observedAt;
}

class ShareQueryEvent {
  ShareQueryEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final DateTime observedAt;
}

class SharedCatalogFileItem {
  SharedCatalogFileItem({
    required this.relativePath,
    required this.sizeBytes,
    this.thumbnailId,
  });

  final String relativePath;
  final int sizeBytes;
  final String? thumbnailId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'relativePath': relativePath,
      'sizeBytes': sizeBytes,
      'thumbnailId': thumbnailId,
    };
  }

  static SharedCatalogFileItem? fromJson(Map<String, dynamic> json) {
    final relativePath = json['relativePath'] as String?;
    final sizeRaw = json['sizeBytes'];
    if (relativePath == null || sizeRaw is! num) {
      return null;
    }
    return SharedCatalogFileItem(
      relativePath: relativePath,
      sizeBytes: sizeRaw.toInt(),
      thumbnailId: json['thumbnailId'] as String?,
    );
  }
}

class SharedCatalogEntryItem {
  SharedCatalogEntryItem({
    required this.cacheId,
    required this.displayName,
    required this.itemCount,
    required this.totalBytes,
    required this.files,
  });

  final String cacheId;
  final String displayName;
  final int itemCount;
  final int totalBytes;
  final List<SharedCatalogFileItem> files;

  Map<String, Object> toJson() {
    return <String, Object>{
      'cacheId': cacheId,
      'displayName': displayName,
      'itemCount': itemCount,
      'totalBytes': totalBytes,
      'files': files.map((file) => file.toJson()).toList(growable: false),
    };
  }

  static SharedCatalogEntryItem? fromJson(Map<String, dynamic> json) {
    final cacheId = json['cacheId'] as String?;
    final displayName = json['displayName'] as String?;
    final itemCountRaw = json['itemCount'];
    final totalBytesRaw = json['totalBytes'];
    final filesRaw = json['files'];
    if (cacheId == null ||
        displayName == null ||
        itemCountRaw is! num ||
        totalBytesRaw is! num ||
        filesRaw is! List<dynamic>) {
      return null;
    }

    final files = <SharedCatalogFileItem>[];
    for (final file in filesRaw) {
      if (file is! Map<String, dynamic>) {
        continue;
      }
      final parsed = SharedCatalogFileItem.fromJson(file);
      if (parsed != null) {
        files.add(parsed);
      }
    }
    return SharedCatalogEntryItem(
      cacheId: cacheId,
      displayName: displayName,
      itemCount: itemCountRaw.toInt(),
      totalBytes: totalBytesRaw.toInt(),
      files: files,
    );
  }
}

class ShareCatalogEvent {
  ShareCatalogEvent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
    required this.removedCacheIds,
    required this.observedAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
  final List<String> removedCacheIds;
  final DateTime observedAt;
}

class DownloadRequestEvent {
  DownloadRequestEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.cacheId,
    required this.selectedRelativePaths,
    required this.previewMode,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final String requesterMacAddress;
  final String cacheId;
  final List<String> selectedRelativePaths;
  final bool previewMode;

  final DateTime observedAt;
}

class ClipboardCatalogItem {
  const ClipboardCatalogItem({
    required this.id,
    required this.entryType,
    required this.createdAtMs,
    this.textValue,
    this.imagePreviewBase64,
  });

  final String id;
  final String entryType;
  final int createdAtMs;
  final String? textValue;
  final String? imagePreviewBase64;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'entryType': entryType,
      'createdAtMs': createdAtMs,
      'textValue': textValue,
      'imagePreviewBase64': imagePreviewBase64,
    };
  }

  static ClipboardCatalogItem? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final entryType = json['entryType'] as String?;
    final createdAtRaw = json['createdAtMs'];
    if (id == null || entryType == null || createdAtRaw is! num) {
      return null;
    }
    return ClipboardCatalogItem(
      id: id,
      entryType: entryType,
      createdAtMs: createdAtRaw.toInt(),
      textValue: json['textValue'] as String?,
      imagePreviewBase64: json['imagePreviewBase64'] as String?,
    );
  }
}

class ClipboardQueryEvent {
  const ClipboardQueryEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.maxEntries,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final String requesterMacAddress;
  final int maxEntries;
  final DateTime observedAt;
}

class ClipboardCatalogEvent {
  const ClipboardCatalogEvent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
    required this.observedAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String ownerMacAddress;
  final List<ClipboardCatalogItem> entries;
  final DateTime observedAt;
}

class ThumbnailSyncItem {
  const ThumbnailSyncItem({
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
  });

  final String cacheId;
  final String relativePath;
  final String thumbnailId;

  Map<String, Object> toJson() {
    return <String, Object>{
      'cacheId': cacheId,
      'relativePath': relativePath,
      'thumbnailId': thumbnailId,
    };
  }

  static ThumbnailSyncItem? fromJson(Map<String, dynamic> json) {
    final cacheId = json['cacheId'] as String?;
    final relativePath = json['relativePath'] as String?;
    final thumbnailId = json['thumbnailId'] as String?;
    if (cacheId == null || relativePath == null || thumbnailId == null) {
      return null;
    }
    return ThumbnailSyncItem(
      cacheId: cacheId,
      relativePath: relativePath,
      thumbnailId: thumbnailId,
    );
  }
}

class ThumbnailSyncRequestEvent {
  const ThumbnailSyncRequestEvent({
    required this.requestId,
    required this.requesterIp,
    required this.requesterName,
    required this.items,
    required this.observedAt,
  });

  final String requestId;
  final String requesterIp;
  final String requesterName;
  final List<ThumbnailSyncItem> items;
  final DateTime observedAt;
}

class ThumbnailPacketEvent {
  const ThumbnailPacketEvent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
    required this.bytes,
    required this.observedAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerMacAddress;
  final String cacheId;
  final String relativePath;
  final String thumbnailId;
  final Uint8List bytes;
  final DateTime observedAt;
}

class LanDiscoveryService {
  static const int discoveryPort = 40404;

  LanDiscoveryService({
    DiscoveryTransportAdapter? transportAdapter,
    LanPacketCodec? packetCodec,
  }) : _transportAdapter = transportAdapter ?? UdpDiscoveryTransportAdapter(),
       _packetCodec = packetCodec ?? LanPacketCodec();

  final DiscoveryTransportAdapter _transportAdapter;
  final LanPacketCodec _packetCodec;
  Timer? _beaconTimer;
  bool _started = false;
  final String _instanceId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
  String _localPeerId = '';
  List<InternetPeerEndpoint> _internetPeers = const <InternetPeerEndpoint>[];
  Set<String> _internetPeerIpAllowlist = <String>{};

  @visibleForTesting
  static const Map<String, String> protocolPrefixesForTest =
      LanPacketCodec.protocolPrefixes;

  @visibleForTesting
  void setLocalPeerIdForTest(String value) {
    _localPeerId = value.trim();
  }

  @visibleForTesting
  String buildDiscoveryMessageForTest(String deviceName) {
    return _packetCodec.encodeDiscoveryRequest(
      instanceId: _instanceId,
      deviceName: deviceName,
      localPeerId: _localPeerId,
    );
  }

  @visibleForTesting
  Map<String, Object?>? parseDiscoveryMessageForTest(String message) {
    final packet = _packetCodec.decodeDiscoveryPacket(message);
    if (packet == null) {
      return null;
    }
    return <String, Object?>{
      'prefix': packet.prefix,
      'instanceId': packet.instanceId,
      'deviceName': packet.deviceName,
      'operatingSystem': packet.operatingSystem,
      'deviceType': packet.deviceType,
      'peerId': packet.peerId,
    };
  }

  @visibleForTesting
  List<SharedCatalogEntryItem> fitShareCatalogEntriesForTest(
    List<SharedCatalogEntryItem> entries,
  ) {
    return _packetCodec.fitShareCatalogEntries(entries);
  }

  @visibleForTesting
  static String encodeEnvelopeForTest({
    required String prefix,
    required Map<String, Object?> payload,
  }) {
    return LanPacketCodec.encodeEnvelopeForTest(
      prefix: prefix,
      payload: payload,
    );
  }

  @visibleForTesting
  static Map<String, dynamic>? decodeEnvelopeForTest({
    required String message,
    required String expectedPrefix,
  }) {
    return LanPacketCodec.decodeEnvelopeForTest(
      message: message,
      expectedPrefix: expectedPrefix,
    );
  }

  Future<void> start({
    required String deviceName,
    required String localPeerId,
    required void Function(AppPresenceEvent event) onAppDetected,
    void Function(TransferRequestEvent event)? onTransferRequest,
    void Function(TransferDecisionEvent event)? onTransferDecision,
    void Function(FriendRequestEvent event)? onFriendRequest,
    void Function(FriendResponseEvent event)? onFriendResponse,
    void Function(ShareQueryEvent event)? onShareQuery,
    void Function(ShareCatalogEvent event)? onShareCatalog,
    void Function(DownloadRequestEvent event)? onDownloadRequest,
    void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest,
    void Function(ThumbnailPacketEvent event)? onThumbnailPacket,
    void Function(ClipboardQueryEvent event)? onClipboardQuery,
    void Function(ClipboardCatalogEvent event)? onClipboardCatalog,
    String? preferredSourceIp,
  }) async {
    if (_started) {
      _log('start() ignored: service already running');
      return;
    }
    _started = true;
    _localPeerId = localPeerId.trim();

    try {
      await _transportAdapter.start(
        port: discoveryPort,
        preferredSourceIp: preferredSourceIp,
        onDatagram: (datagram) => _handleIncomingDatagram(
          datagram: datagram,
          deviceName: deviceName,
          onAppDetected: onAppDetected,
          onTransferRequest: onTransferRequest,
          onTransferDecision: onTransferDecision,
          onFriendRequest: onFriendRequest,
          onFriendResponse: onFriendResponse,
          onShareQuery: onShareQuery,
          onShareCatalog: onShareCatalog,
          onDownloadRequest: onDownloadRequest,
          onThumbnailSyncRequest: onThumbnailSyncRequest,
          onThumbnailPacket: onThumbnailPacket,
          onClipboardQuery: onClipboardQuery,
          onClipboardCatalog: onClipboardCatalog,
        ),
      );
    } catch (_) {
      _started = false;
      rethrow;
    }

    await _sendDiscoveryPing(deviceName);
    _beaconTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _sendDiscoveryPing(deviceName),
    );
  }

  void updateInternetPeers(List<InternetPeerEndpoint> peers) {
    final normalized = <InternetPeerEndpoint>[];
    final ipAllow = <String>{};
    for (final peer in peers) {
      final host = peer.host.trim();
      final friendId = peer.friendId.trim();
      if (host.isEmpty || friendId.isEmpty) {
        continue;
      }
      final port = peer.port <= 0 || peer.port > 65535
          ? discoveryPort
          : peer.port;
      final parsedIp = InternetAddress.tryParse(host);
      if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
        continue;
      }
      normalized.add(
        InternetPeerEndpoint(friendId: friendId, host: host, port: port),
      );
      ipAllow.add(parsedIp.address);
    }
    _internetPeers = normalized;
    _internetPeerIpAllowlist = ipAllow;
    _log('Internet peers updated. count=');
  }

  Future<void> stop() async {
    _log('Stopping UDP discovery');
    _beaconTimer?.cancel();
    _beaconTimer = null;
    await _transportAdapter.stop();
    _started = false;
  }

  Future<void> sendTransferRequest({
    required String targetIp,
    required String requestId,
    required String senderName,
    required String senderMacAddress,
    required String sharedCacheId,
    required String sharedLabel,
    required List<TransferAnnouncementItem> items,
  }) async {
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.transferRequestPrefix,
      packet: _packetCodec.encodeTransferRequest(
        instanceId: _instanceId,
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
    required String targetIp,
    required String requestId,
    required bool approved,
    required String receiverName,
    int? transferPort,
    List<String>? acceptedFileNames,
  }) async {
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.transferDecisionPrefix,
      packet: _packetCodec.encodeTransferDecision(
        instanceId: _instanceId,
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

  Future<void> sendFriendRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
  }) async {
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.friendRequestPrefix,
      packet: _packetCodec.encodeFriendRequest(
        instanceId: _instanceId,
        requestId: requestId,
        requesterName: requesterName,
        requesterMacAddress: requesterMacAddress,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendFriendResponse({
    required String targetIp,
    required String requestId,
    required String responderName,
    required String responderMacAddress,
    required bool accepted,
  }) async {
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.friendResponsePrefix,
      packet: _packetCodec.encodeFriendResponse(
        instanceId: _instanceId,
        requestId: requestId,
        responderName: responderName,
        responderMacAddress: responderMacAddress,
        accepted: accepted,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendShareQuery({
    required String targetIp,
    required String requestId,
    required String requesterName,
  }) async {
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.shareQueryPrefix,
      packet: _packetCodec.encodeShareQuery(
        instanceId: _instanceId,
        requestId: requestId,
        requesterName: requesterName,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendShareCatalog({
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    List<String> removedCacheIds = const <String>[],
  }) async {
    final fittedEntries = _packetCodec.fitShareCatalogEntries(entries);
    final originalFiles = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.files.length,
    );
    final fittedFiles = fittedEntries.fold<int>(
      0,
      (sum, entry) => sum + entry.files.length,
    );
    if (fittedEntries.length < entries.length || fittedFiles < originalFiles) {
      _log(
        'Share catalog trimmed for UDP: '
        'entries=${fittedEntries.length}/${entries.length}, '
        'files=$fittedFiles/$originalFiles',
      );
    }
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.shareCatalogPrefix,
      packet: _packetCodec.encodeShareCatalog(
        instanceId: _instanceId,
        requestId: requestId,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: fittedEntries,
        removedCacheIds: removedCacheIds,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendDownloadRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required String cacheId,
    List<String> selectedRelativePaths = const <String>[],
    bool previewMode = false,
  }) async {
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.downloadRequestPrefix,
      packet: _packetCodec.encodeDownloadRequest(
        instanceId: _instanceId,
        requestId: requestId,
        requesterName: requesterName,
        requesterMacAddress: requesterMacAddress,
        cacheId: cacheId,
        selectedRelativePaths: selectedRelativePaths,
        previewMode: previewMode,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendThumbnailSyncRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
  }) async {
    if (items.isEmpty) {
      return;
    }
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.thumbnailSyncRequestPrefix,
      packet: _packetCodec.encodeThumbnailSyncRequest(
        instanceId: _instanceId,
        requestId: requestId,
        requesterName: requesterName,
        items: items,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendThumbnailPacket({
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
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.thumbnailPacketPrefix,
      packet: _packetCodec.encodeThumbnailPacket(
        instanceId: _instanceId,
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

  Future<void> sendClipboardQuery({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
  }) async {
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.clipboardQueryPrefix,
      packet: _packetCodec.encodeClipboardQuery(
        instanceId: _instanceId,
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
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
  }) async {
    await _sendOutgoingPacket(
      prefix: LanPacketCodec.clipboardCatalogPrefix,
      packet: _packetCodec.encodeClipboardCatalog(
        instanceId: _instanceId,
        requestId: requestId,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: entries,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> _sendOutgoingPacket({
    required String prefix,
    required EncodedLanPacket? packet,
    required String targetIp,
  }) async {
    if (packet == null) {
      _log('Skipping $prefix packet: codec rejected payload.');
      return;
    }
    final targetAddress = _resolveUnicastTargetIp(targetIp);
    if (targetAddress == null) {
      _log('Skipping $prefix packet: invalid target IP "$targetIp".');
      return;
    }
    _transportAdapter.send(
      bytes: packet.bytes,
      address: targetAddress,
      port: discoveryPort,
      context: packet.prefix,
    );
  }

  Future<void> _sendDiscoveryPing(String deviceName) async {
    final request = _packetCodec.encodeDiscoveryRequest(
      instanceId: _instanceId,
      deviceName: deviceName,
      localPeerId: _localPeerId,
    );
    final bytes = utf8.encode(request);
    final localIps = _transportAdapter.localIps;

    _log('Broadcasting discover packet');
    _transportAdapter.send(
      bytes: bytes,
      address: InternetAddress('255.255.255.255'),
      port: discoveryPort,
      context: 'discover-broadcast',
    );
    for (final localIp in localIps) {
      final broadcast = _toBroadcastAddress(localIp);
      if (broadcast != null) {
        _transportAdapter.send(
          bytes: bytes,
          address: broadcast,
          port: discoveryPort,
          context: 'discover-subnet',
        );
        _log('Discover packet sent to ${broadcast.address}');
      }
    }

    for (final peer in _internetPeers) {
      final address = InternetAddress.tryParse(peer.host);
      if (address == null || address.type != InternetAddressType.IPv4) {
        continue;
      }
      _transportAdapter.send(
        bytes: bytes,
        address: address,
        port: peer.port,
        context: 'discover-friend-endpoint',
      );
      _log('Discover packet sent to friend endpoint ${peer.host}:${peer.port}');
    }
  }

  InternetAddress? _resolveUnicastTargetIp(String rawTargetIp) {
    final normalized = rawTargetIp.trim();
    final parsed = InternetAddress.tryParse(normalized);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return null;
    }
    if (!_isUsablePacketSenderIp(parsed.address)) {
      return null;
    }
    return parsed;
  }

  bool _isUsablePacketSenderIp(String ip) {
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return false;
    }
    if (parsed.address == '0.0.0.0' ||
        parsed.isLoopback ||
        parsed.isMulticast) {
      return false;
    }
    return parsed.address != '255.255.255.255';
  }

  InternetAddress? _toBroadcastAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return null;
    }
    return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
  }

  bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return false;
      }
    }
    return true;
  }

  bool _isSame24Subnet(String ip, String baseIp) {
    if (!_isValidIpv4(ip) || !_isValidIpv4(baseIp)) {
      return false;
    }
    final a = ip.split('.');
    final b = baseIp.split('.');
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }

  bool _isAllowedInternetSender(String senderIp) {
    if (_internetPeerIpAllowlist.isEmpty) {
      return false;
    }
    return _internetPeerIpAllowlist.contains(senderIp);
  }

  void _log(String message) {
    developer.log(message, name: 'LanDiscoveryService');
  }

  void _handleIncomingDatagram({
    required Datagram datagram,
    required String deviceName,
    required void Function(AppPresenceEvent event) onAppDetected,
    void Function(TransferRequestEvent event)? onTransferRequest,
    void Function(TransferDecisionEvent event)? onTransferDecision,
    void Function(FriendRequestEvent event)? onFriendRequest,
    void Function(FriendResponseEvent event)? onFriendResponse,
    void Function(ShareQueryEvent event)? onShareQuery,
    void Function(ShareCatalogEvent event)? onShareCatalog,
    void Function(DownloadRequestEvent event)? onDownloadRequest,
    void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest,
    void Function(ThumbnailPacketEvent event)? onThumbnailPacket,
    void Function(ClipboardQueryEvent event)? onClipboardQuery,
    void Function(ClipboardCatalogEvent event)? onClipboardCatalog,
  }) {
    final senderIp = datagram.address.address;
    if (!_isUsablePacketSenderIp(senderIp)) {
      _log('Ignoring packet from invalid sender IP: $senderIp');
      return;
    }

    final localIps = _transportAdapter.localIps;
    if (localIps.contains(senderIp)) {
      return;
    }

    final isAllowedInternetSender = _isAllowedInternetSender(senderIp);
    final isSenderInLocalSubnet = localIps.any(
      (localIp) => _isSame24Subnet(senderIp, localIp),
    );
    if (localIps.isNotEmpty &&
        !isSenderInLocalSubnet &&
        !isAllowedInternetSender) {
      _log('Ignoring packet from foreign subnet: $senderIp');
      return;
    }

    final message = utf8.decode(datagram.data, allowMalformed: true);
    final packet = _packetCodec.decodeIncomingPacket(message);
    if (packet == null || packet.instanceId == _instanceId) {
      return;
    }

    if (packet is LanDiscoveryPresencePacket) {
      if (packet.prefix == LanPacketCodec.discoverPrefix) {
        _log('Discover request from $senderIp');
        final response = _packetCodec.encodeDiscoveryResponse(
          instanceId: _instanceId,
          deviceName: deviceName,
          localPeerId: _localPeerId,
        );
        _transportAdapter.send(
          bytes: utf8.encode(response),
          address: datagram.address,
          port: datagram.port,
          context: 'discover-response',
        );
        _log('Discover response sent to $senderIp');
      } else if (packet.prefix == LanPacketCodec.responsePrefix) {
        _log(
          'Discover response received from '
          '$senderIp (${packet.deviceName})',
        );
        onAppDetected(
          AppPresenceEvent(
            ip: senderIp,
            deviceName: packet.deviceName,
            operatingSystem: packet.operatingSystem,
            deviceType: packet.deviceType,
            peerId: packet.peerId,
            observedAt: DateTime.now(),
          ),
        );
      }
      return;
    }

    if (packet is LanTransferRequestPacket) {
      _log(
        'Transfer request received from $senderIp '
        '(requestId=${packet.requestId})',
      );
      onTransferRequest?.call(
        TransferRequestEvent(
          requestId: packet.requestId,
          senderIp: senderIp,
          senderName: packet.senderName,
          senderMacAddress: packet.senderMacAddress,
          sharedCacheId: packet.sharedCacheId,
          sharedLabel: packet.sharedLabel,
          items: packet.items,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanTransferDecisionPacket) {
      _log(
        'Transfer decision received from $senderIp '
        '(requestId=${packet.requestId}, approved=${packet.approved})',
      );
      onTransferDecision?.call(
        TransferDecisionEvent(
          requestId: packet.requestId,
          approved: packet.approved,
          receiverName: packet.receiverName,
          receiverIp: senderIp,
          transferPort: packet.transferPort,
          observedAt: DateTime.now(),
          acceptedFileNames: packet.acceptedFileNames,
        ),
      );
      return;
    }

    if (packet is LanFriendRequestPacket) {
      _log(
        'Friend request received from $senderIp '
        '(requestId=${packet.requestId})',
      );
      onFriendRequest?.call(
        FriendRequestEvent(
          requestId: packet.requestId,
          requesterIp: senderIp,
          requesterName: packet.requesterName,
          requesterMacAddress: packet.requesterMacAddress,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanFriendResponsePacket) {
      _log(
        'Friend response received from $senderIp '
        '(requestId=${packet.requestId}, accepted=${packet.accepted})',
      );
      onFriendResponse?.call(
        FriendResponseEvent(
          requestId: packet.requestId,
          responderIp: senderIp,
          responderName: packet.responderName,
          responderMacAddress: packet.responderMacAddress,
          accepted: packet.accepted,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanShareQueryPacket) {
      onShareQuery?.call(
        ShareQueryEvent(
          requestId: packet.requestId,
          requesterIp: senderIp,
          requesterName: packet.requesterName,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanShareCatalogPacket) {
      onShareCatalog?.call(
        ShareCatalogEvent(
          requestId: packet.requestId,
          ownerIp: senderIp,
          ownerName: packet.ownerName,
          ownerMacAddress: packet.ownerMacAddress,
          entries: packet.entries,
          removedCacheIds: packet.removedCacheIds,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanDownloadRequestPacket) {
      onDownloadRequest?.call(
        DownloadRequestEvent(
          requestId: packet.requestId,
          requesterIp: senderIp,
          requesterName: packet.requesterName,
          requesterMacAddress: packet.requesterMacAddress,
          cacheId: packet.cacheId,
          selectedRelativePaths: packet.selectedRelativePaths,
          previewMode: packet.previewMode,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanThumbnailSyncRequestPacket) {
      onThumbnailSyncRequest?.call(
        ThumbnailSyncRequestEvent(
          requestId: packet.requestId,
          requesterIp: senderIp,
          requesterName: packet.requesterName,
          items: packet.items,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanThumbnailPacket) {
      onThumbnailPacket?.call(
        ThumbnailPacketEvent(
          requestId: packet.requestId,
          ownerIp: senderIp,
          ownerMacAddress: packet.ownerMacAddress,
          cacheId: packet.cacheId,
          relativePath: packet.relativePath,
          thumbnailId: packet.thumbnailId,
          bytes: packet.bytes,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanClipboardQueryPacket) {
      onClipboardQuery?.call(
        ClipboardQueryEvent(
          requestId: packet.requestId,
          requesterIp: senderIp,
          requesterName: packet.requesterName,
          requesterMacAddress: packet.requesterMacAddress,
          maxEntries: packet.maxEntries,
          observedAt: DateTime.now(),
        ),
      );
      return;
    }

    if (packet is LanClipboardCatalogPacket) {
      onClipboardCatalog?.call(
        ClipboardCatalogEvent(
          requestId: packet.requestId,
          ownerIp: senderIp,
          ownerName: packet.ownerName,
          ownerMacAddress: packet.ownerMacAddress,
          entries: packet.entries,
          observedAt: DateTime.now(),
        ),
      );
    }
  }
}
