import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'discovery_transport_adapter.dart';
import 'lan_clipboard_protocol_handler.dart';
import 'lan_friend_protocol_handler.dart';
import 'lan_incoming_packet_dispatcher.dart';
import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';
import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_presence_protocol_handler.dart';
import 'lan_protocol_events.dart';
import 'lan_sender_allowlist_policy.dart';
import 'lan_share_protocol_handler.dart';
import 'lan_transfer_protocol_handler.dart';

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

class LanDiscoveryService {
  static const int discoveryPort = 40404;
  static const Duration defaultPresenceHeartbeatInterval = Duration(seconds: 4);

  LanDiscoveryService({
    DiscoveryTransportAdapter? transportAdapter,
    LanPacketCodec? packetCodec,
    LanPresenceProtocolHandler? presenceProtocolHandler,
    LanTransferProtocolHandler? transferProtocolHandler,
    LanFriendProtocolHandler? friendProtocolHandler,
    LanShareProtocolHandler? shareProtocolHandler,
    LanClipboardProtocolHandler? clipboardProtocolHandler,
    int? Function()? nearbyTransferPortProvider,
    Duration presenceHeartbeatInterval = defaultPresenceHeartbeatInterval,
  }) : _transportAdapter = transportAdapter ?? UdpDiscoveryTransportAdapter(),
       _packetCodec = packetCodec ?? LanPacketCodec(),
       _incomingPacketDispatcher = LanIncomingPacketDispatcher(
         presenceProtocolHandler: presenceProtocolHandler,
         transferProtocolHandler: transferProtocolHandler,
         friendProtocolHandler: friendProtocolHandler,
         shareProtocolHandler: shareProtocolHandler,
         clipboardProtocolHandler: clipboardProtocolHandler,
       ),
       _nearbyTransferPortProvider = nearbyTransferPortProvider,
       _presenceHeartbeatInterval = presenceHeartbeatInterval;

  final DiscoveryTransportAdapter _transportAdapter;
  final LanPacketCodec _packetCodec;
  final LanIncomingPacketDispatcher _incomingPacketDispatcher;
  final int? Function()? _nearbyTransferPortProvider;
  final Duration _presenceHeartbeatInterval;
  Timer? _beaconTimer;
  bool _started = false;
  final String _instanceId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
  String _localPeerId = '';
  List<InternetPeerEndpoint> _internetPeers = const <InternetPeerEndpoint>[];
  Set<String> _internetPeerIpAllowlist = <String>{};
  Set<String> _configuredTargetIps = <String>{};
  final LanSenderAllowlistPolicy _senderAllowlistPolicy =
      LanSenderAllowlistPolicy();

  Future<void> start({
    required String deviceName,
    required String localPeerId,
    required Set<String> localSourceIps,
    Set<String> configuredTargetIps = const <String>{},
    required void Function(AppPresenceEvent event) onAppDetected,
    void Function(TransferRequestEvent event)? onTransferRequest,
    void Function(TransferDecisionEvent event)? onTransferDecision,
    void Function(FriendRequestEvent event)? onFriendRequest,
    void Function(FriendResponseEvent event)? onFriendResponse,
    void Function(ShareQueryEvent event)? onShareQuery,
    void Function(ShareAccessRequestEvent event)? onShareAccessRequest,
    void Function(ShareAccessResponseEvent event)? onShareAccessResponse,
    void Function(ShareCatalogEvent event)? onShareCatalog,
    void Function(DownloadRequestEvent event)? onDownloadRequest,
    void Function(DownloadResponseEvent event)? onDownloadResponse,
    void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest,
    void Function(ThumbnailPacketEvent event)? onThumbnailPacket,
    void Function(ClipboardQueryEvent event)? onClipboardQuery,
    void Function(ClipboardCatalogEvent event)? onClipboardCatalog,
  }) async {
    if (_started) {
      _log('start() ignored: service already running');
      return;
    }
    _started = true;
    _localPeerId = localPeerId.trim();
    _configuredTargetIps = configuredTargetIps
        .map((ip) => _resolveUnicastTargetIp(ip)?.address)
        .whereType<String>()
        .toSet();

    try {
      await _transportAdapter.start(
        port: discoveryPort,
        localSourceIps: localSourceIps,
        onDatagram: (datagram) => _handleIncomingDatagram(
          datagram: datagram,
          deviceName: deviceName,
          onAppDetected: onAppDetected,
          onTransferRequest: onTransferRequest,
          onTransferDecision: onTransferDecision,
          onFriendRequest: onFriendRequest,
          onFriendResponse: onFriendResponse,
          onShareQuery: onShareQuery,
          onShareAccessRequest: onShareAccessRequest,
          onShareAccessResponse: onShareAccessResponse,
          onShareCatalog: onShareCatalog,
          onDownloadRequest: onDownloadRequest,
          onDownloadResponse: onDownloadResponse,
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
      _presenceHeartbeatInterval,
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
    _configuredTargetIps = <String>{};
    _senderAllowlistPolicy.clear();
    _incomingPacketDispatcher.clear();
  }

  Future<void> broadcastPresenceNow({required String deviceName}) async {
    if (!_started) {
      return;
    }
    await _sendDiscoveryPing(deviceName);
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
      prefix: lanTransferRequestPrefix,
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
      prefix: lanTransferDecisionPrefix,
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
      prefix: lanFriendRequestPrefix,
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
      prefix: lanFriendResponsePrefix,
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
      prefix: lanShareQueryPrefix,
      packet: _packetCodec.encodeShareQuery(
        instanceId: _instanceId,
        requestId: requestId,
        requesterName: requesterName,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
      targetIp: targetIp,
    );
  }

  Future<void> sendShareAccessRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int transferPort,
  }) async {
    await _sendOutgoingPacket(
      prefix: lanShareAccessRequestPrefix,
      packet: _packetCodec.encodeShareAccessRequest(
        instanceId: _instanceId,
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
    required String targetIp,
    required String requestId,
    required String responderName,
    required bool approved,
    String? message,
  }) async {
    await _sendOutgoingPacket(
      prefix: lanShareAccessResponsePrefix,
      packet: _packetCodec.encodeShareAccessResponse(
        instanceId: _instanceId,
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
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    List<String> removedCacheIds = const <String>[],
  }) async {
    final packets = _packetCodec.encodeShareCatalogChunks(
      instanceId: _instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (packets.isEmpty) {
      _log('Skipping $lanShareCatalogPrefix packet: codec rejected payload.');
      return;
    }
    await _sendOutgoingPackets(
      prefix: lanShareCatalogPrefix,
      packets: packets,
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
    List<String> selectedFolderPrefixes = const <String>[],
    int? transferPort,
    bool previewMode = false,
  }) async {
    await _sendOutgoingPacket(
      prefix: lanDownloadRequestPrefix,
      packet: _packetCodec.encodeDownloadRequest(
        instanceId: _instanceId,
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
    required String targetIp,
    required String requestId,
    required String responderName,
    required bool approved,
    String? phase,
    String? message,
  }) async {
    await _sendOutgoingPacket(
      prefix: lanDownloadResponsePrefix,
      packet: _packetCodec.encodeDownloadResponse(
        instanceId: _instanceId,
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
    required String targetIp,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
  }) async {
    if (items.isEmpty) {
      return;
    }
    await _sendOutgoingPacket(
      prefix: lanThumbnailSyncRequestPrefix,
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
      prefix: lanThumbnailPacketPrefix,
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
      prefix: lanClipboardQueryPrefix,
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
    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
    final fittedEntries = _packetCodec.fitClipboardCatalogEntries(
      instanceId: _instanceId,
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
    await _sendOutgoingPacket(
      prefix: lanClipboardCatalogPrefix,
      packet: _packetCodec.encodeClipboardCatalog(
        instanceId: _instanceId,
        requestId: requestId,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: fittedEntries,
        createdAtMs: createdAtMs,
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

  Future<void> _sendOutgoingPackets({
    required String prefix,
    required List<EncodedLanPacket> packets,
    required String targetIp,
  }) async {
    final targetAddress = _resolveUnicastTargetIp(targetIp);
    if (targetAddress == null) {
      _log('Skipping $prefix packet: invalid target IP "$targetIp".');
      return;
    }
    for (final packet in packets) {
      _transportAdapter.send(
        bytes: packet.bytes,
        address: targetAddress,
        port: discoveryPort,
        context: packet.prefix,
      );
    }
  }

  Future<void> _sendDiscoveryPing(String deviceName) async {
    final nearbyTransferPort = _nearbyTransferPortProvider?.call();
    final request = _packetCodec.encodeDiscoveryRequest(
      instanceId: _instanceId,
      deviceName: deviceName,
      localPeerId: _localPeerId,
      nearbyTransferPort: nearbyTransferPort,
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

    for (final targetIp in _configuredTargetIps) {
      final address = InternetAddress.tryParse(targetIp);
      if (address == null || address.type != InternetAddressType.IPv4) {
        continue;
      }
      _transportAdapter.send(
        bytes: bytes,
        address: address,
        port: discoveryPort,
        context: 'discover-configured-target',
      );
      _log('Discover packet sent to configured target $targetIp');
    }
  }

  InternetAddress? _resolveUnicastTargetIp(String rawTargetIp) {
    final normalized = rawTargetIp.trim();
    final parsed = InternetAddress.tryParse(normalized);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return null;
    }
    if (!_senderAllowlistPolicy.isUsablePacketSenderIp(parsed.address)) {
      return null;
    }
    return parsed;
  }

  InternetAddress? _toBroadcastAddress(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return null;
    }
    return InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255');
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
    void Function(ShareAccessRequestEvent event)? onShareAccessRequest,
    void Function(ShareAccessResponseEvent event)? onShareAccessResponse,
    void Function(ShareCatalogEvent event)? onShareCatalog,
    void Function(DownloadRequestEvent event)? onDownloadRequest,
    void Function(DownloadResponseEvent event)? onDownloadResponse,
    void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest,
    void Function(ThumbnailPacketEvent event)? onThumbnailPacket,
    void Function(ClipboardQueryEvent event)? onClipboardQuery,
    void Function(ClipboardCatalogEvent event)? onClipboardCatalog,
  }) {
    final senderIp = datagram.address.address;
    if (!_senderAllowlistPolicy.isUsablePacketSenderIp(senderIp)) {
      _log('Ignoring packet from invalid sender IP: $senderIp');
      return;
    }

    final localIps = _transportAdapter.localIps;
    if (localIps.contains(senderIp)) {
      return;
    }

    final message = utf8.decode(datagram.data, allowMalformed: true);
    final packet = _packetCodec.decodeIncomingPacket(message);
    if (packet == null || packet.instanceId == _instanceId) {
      return;
    }

    if (!_senderAllowlistPolicy.isAllowedSenderForPacket(
      packet: packet,
      senderIp: senderIp,
      localIps: localIps,
      configuredTargetIps: _configuredTargetIps,
      internetPeerIpAllowlist: _internetPeerIpAllowlist,
      log: _log,
    )) {
      _log('Ignoring packet from foreign subnet: $senderIp');
      return;
    }
    final observedAt = DateTime.now();

    _incomingPacketDispatcher.dispatch(
      packet: packet,
      senderIp: senderIp,
      observedAt: observedAt,
      callbacks: LanIncomingPacketCallbacks(
        onAppDetected: onAppDetected,
        onTransferRequest: onTransferRequest,
        onTransferDecision: onTransferDecision,
        onFriendRequest: onFriendRequest,
        onFriendResponse: onFriendResponse,
        onShareQuery: onShareQuery,
        onShareAccessRequest: onShareAccessRequest,
        onShareAccessResponse: onShareAccessResponse,
        onShareCatalog: onShareCatalog,
        onDownloadRequest: onDownloadRequest,
        onDownloadResponse: onDownloadResponse,
        onThumbnailSyncRequest: onThumbnailSyncRequest,
        onThumbnailPacket: onThumbnailPacket,
        onClipboardQuery: onClipboardQuery,
        onClipboardCatalog: onClipboardCatalog,
      ),
      onPresencePacketAccepted: () => _senderAllowlistPolicy
          .markPresenceAllowedSender(senderIp, observedAt),
      onDiscoveryResponseRequested: () {
        final response = _packetCodec.encodeDiscoveryResponse(
          instanceId: _instanceId,
          deviceName: deviceName,
          localPeerId: _localPeerId,
          nearbyTransferPort: _nearbyTransferPortProvider?.call(),
        );
        _transportAdapter.send(
          bytes: utf8.encode(response),
          address: datagram.address,
          port: datagram.port,
          context: 'discover-response',
        );
      },
      log: _log,
    );
  }
}
