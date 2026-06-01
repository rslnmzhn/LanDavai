import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'discovery_transport_adapter.dart';
import 'lan_clipboard_packet_sender.dart';
import 'lan_clipboard_protocol_handler.dart';
import 'lan_discovery_target_registry.dart';
import 'lan_discovery_session_callbacks.dart';
import 'lan_friend_packet_sender.dart';
import 'lan_friend_protocol_handler.dart';
import 'lan_incoming_datagram_admission.dart';
import 'lan_incoming_packet_dispatcher.dart';
import 'lan_internet_peer_endpoint.dart';
import 'lan_outgoing_packet_sender.dart';
import 'lan_packet_codec_models.dart';
import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_presence_announcement_sender.dart';
import 'lan_presence_protocol_handler.dart';
import 'lan_protocol_events.dart';
import 'lan_sender_allowlist_policy.dart';
import 'lan_share_packet_sender.dart';
import 'lan_share_protocol_handler.dart';
import 'lan_transfer_packet_sender.dart';
import 'lan_transfer_protocol_handler.dart';

export 'lan_internet_peer_endpoint.dart';

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
  late final LanOutgoingPacketSender _outgoingPacketSender =
      LanOutgoingPacketSender(
        transportAdapter: _transportAdapter,
        resolveTargetIp: _resolveUnicastTargetIp,
        port: discoveryPort,
        log: _log,
      );
  late final LanPresenceAnnouncementSender _presenceAnnouncementSender =
      LanPresenceAnnouncementSender(
        transportAdapter: _transportAdapter,
        packetCodec: _packetCodec,
        discoveryPort: discoveryPort,
        log: _log,
      );
  late final LanIncomingDatagramAdmission _incomingDatagramAdmission =
      LanIncomingDatagramAdmission(
        packetCodec: _packetCodec,
        senderAllowlistPolicy: _senderAllowlistPolicy,
        log: _log,
      );
  late final LanTransferPacketSender _transferPacketSender =
      LanTransferPacketSender(
        packetCodec: _packetCodec,
        outgoingPacketSender: _outgoingPacketSender,
      );
  late final LanFriendPacketSender _friendPacketSender = LanFriendPacketSender(
    packetCodec: _packetCodec,
    outgoingPacketSender: _outgoingPacketSender,
  );
  late final LanSharePacketSender _sharePacketSender = LanSharePacketSender(
    packetCodec: _packetCodec,
    outgoingPacketSender: _outgoingPacketSender,
    log: _log,
  );
  late final LanClipboardPacketSender _clipboardPacketSender =
      LanClipboardPacketSender(
        packetCodec: _packetCodec,
        outgoingPacketSender: _outgoingPacketSender,
        log: _log,
      );
  Timer? _beaconTimer;
  bool _started = false;
  final String _instanceId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
  String _localPeerId = '';
  final LanSenderAllowlistPolicy _senderAllowlistPolicy =
      LanSenderAllowlistPolicy();
  late final LanDiscoveryTargetRegistry _targetRegistry =
      LanDiscoveryTargetRegistry(
        isUsableTargetIp: _senderAllowlistPolicy.isUsablePacketSenderIp,
        discoveryPort: discoveryPort,
      );

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
    _targetRegistry.updateConfiguredTargetIps(configuredTargetIps);
    final sessionCallbacks = LanDiscoverySessionCallbacks(
      deviceName: deviceName,
      incoming: LanIncomingPacketCallbacks(
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

    try {
      await _transportAdapter.start(
        port: discoveryPort,
        localSourceIps: localSourceIps,
        onDatagram: (datagram) => _handleIncomingDatagram(
          datagram: datagram,
          sessionCallbacks: sessionCallbacks,
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
    _targetRegistry.updateInternetPeers(peers);
    _log(
      'Internet peers updated. count=${_targetRegistry.internetPeers.length}',
    );
  }

  Future<void> stop() async {
    _log('Stopping UDP discovery');
    _beaconTimer?.cancel();
    _beaconTimer = null;
    await _transportAdapter.stop();
    _started = false;
    _targetRegistry.clearConfiguredTargetIps();
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
    await _transferPacketSender.sendTransferRequest(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      senderName: senderName,
      senderMacAddress: senderMacAddress,
      sharedCacheId: sharedCacheId,
      sharedLabel: sharedLabel,
      items: items,
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
    await _transferPacketSender.sendTransferDecision(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      approved: approved,
      receiverName: receiverName,
      transferPort: transferPort,
      acceptedFileNames: acceptedFileNames,
    );
  }

  Future<void> sendFriendRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
  }) async {
    await _friendPacketSender.sendFriendRequest(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
    );
  }

  Future<void> sendFriendResponse({
    required String targetIp,
    required String requestId,
    required String responderName,
    required String responderMacAddress,
    required bool accepted,
  }) async {
    await _friendPacketSender.sendFriendResponse(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      responderName: responderName,
      responderMacAddress: responderMacAddress,
      accepted: accepted,
    );
  }

  Future<void> sendShareQuery({
    required String targetIp,
    required String requestId,
    required String requesterName,
  }) async {
    await _sharePacketSender.sendShareQuery(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      requesterName: requesterName,
    );
  }

  Future<void> sendShareAccessRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int transferPort,
  }) async {
    await _sharePacketSender.sendShareAccessRequest(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      transferPort: transferPort,
    );
  }

  Future<void> sendShareAccessResponse({
    required String targetIp,
    required String requestId,
    required String responderName,
    required bool approved,
    String? message,
  }) async {
    await _sharePacketSender.sendShareAccessResponse(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      responderName: responderName,
      approved: approved,
      message: message,
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
    await _sharePacketSender.sendShareCatalog(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
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
    await _sharePacketSender.sendDownloadRequest(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      cacheId: cacheId,
      selectedRelativePaths: selectedRelativePaths,
      selectedFolderPrefixes: selectedFolderPrefixes,
      transferPort: transferPort,
      previewMode: previewMode,
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
    await _sharePacketSender.sendDownloadResponse(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      responderName: responderName,
      approved: approved,
      phase: phase,
      message: message,
    );
  }

  Future<void> sendThumbnailSyncRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
  }) async {
    await _sharePacketSender.sendThumbnailSyncRequest(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      requesterName: requesterName,
      items: items,
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
    await _sharePacketSender.sendThumbnailPacket(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      ownerMacAddress: ownerMacAddress,
      cacheId: cacheId,
      relativePath: relativePath,
      thumbnailId: thumbnailId,
      bytes: bytes,
    );
  }

  Future<void> sendClipboardQuery({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
  }) async {
    await _clipboardPacketSender.sendClipboardQuery(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      maxEntries: maxEntries,
    );
  }

  Future<void> sendClipboardCatalog({
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
  }) async {
    await _clipboardPacketSender.sendClipboardCatalog(
      instanceId: _instanceId,
      targetIp: targetIp,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
    );
  }

  Future<void> _sendDiscoveryPing(String deviceName) async {
    await _presenceAnnouncementSender.announce(
      instanceId: _instanceId,
      deviceName: deviceName,
      localPeerId: _localPeerId,
      nearbyTransferPort: _nearbyTransferPortProvider?.call(),
      internetPeers: _targetRegistry.internetPeers,
      configuredTargetIps: _targetRegistry.configuredTargetIps,
    );
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

  void _log(String message) {
    developer.log(message, name: 'LanDiscoveryService');
  }

  void _handleIncomingDatagram({
    required Datagram datagram,
    required LanDiscoverySessionCallbacks sessionCallbacks,
  }) {
    final senderIp = datagram.address.address;
    final localIps = _transportAdapter.localIps;
    final accepted = _incomingDatagramAdmission.admit(
      bytes: datagram.data,
      senderIp: senderIp,
      localIps: localIps,
      localInstanceId: _instanceId,
      configuredTargetIps: _targetRegistry.configuredTargetIps,
      internetPeerIpAllowlist: _targetRegistry.internetPeerIpAllowlist,
    );
    if (accepted == null) {
      return;
    }

    _incomingPacketDispatcher.dispatch(
      packet: accepted.packet,
      senderIp: accepted.senderIp,
      observedAt: accepted.observedAt,
      callbacks: sessionCallbacks.incoming,
      onPresencePacketAccepted: () => _senderAllowlistPolicy
          .markPresenceAllowedSender(accepted.senderIp, accepted.observedAt),
      onDiscoveryResponseRequested: () {
        final response = _packetCodec.encodeDiscoveryResponse(
          instanceId: _instanceId,
          deviceName: sessionCallbacks.deviceName,
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
