import 'lan_clipboard_protocol_handler.dart';
import 'lan_friend_protocol_handler.dart';
import 'lan_packet_codec_models.dart';
import 'lan_presence_protocol_handler.dart';
import 'lan_protocol_events.dart';
import 'lan_share_catalog_chunk_reassembler.dart';
import 'lan_share_protocol_handler.dart';
import 'lan_transfer_protocol_handler.dart';

class LanIncomingPacketCallbacks {
  const LanIncomingPacketCallbacks({
    required this.onAppDetected,
    this.onTransferRequest,
    this.onTransferDecision,
    this.onFriendRequest,
    this.onFriendResponse,
    this.onShareQuery,
    this.onShareAccessRequest,
    this.onShareAccessResponse,
    this.onShareCatalog,
    this.onDownloadRequest,
    this.onDownloadResponse,
    this.onThumbnailSyncRequest,
    this.onThumbnailPacket,
    this.onClipboardQuery,
    this.onClipboardCatalog,
  });

  final void Function(AppPresenceEvent event) onAppDetected;
  final void Function(TransferRequestEvent event)? onTransferRequest;
  final void Function(TransferDecisionEvent event)? onTransferDecision;
  final void Function(FriendRequestEvent event)? onFriendRequest;
  final void Function(FriendResponseEvent event)? onFriendResponse;
  final void Function(ShareQueryEvent event)? onShareQuery;
  final void Function(ShareAccessRequestEvent event)? onShareAccessRequest;
  final void Function(ShareAccessResponseEvent event)? onShareAccessResponse;
  final void Function(ShareCatalogEvent event)? onShareCatalog;
  final void Function(DownloadRequestEvent event)? onDownloadRequest;
  final void Function(DownloadResponseEvent event)? onDownloadResponse;
  final void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest;
  final void Function(ThumbnailPacketEvent event)? onThumbnailPacket;
  final void Function(ClipboardQueryEvent event)? onClipboardQuery;
  final void Function(ClipboardCatalogEvent event)? onClipboardCatalog;
}

class LanIncomingPacketDispatcher {
  LanIncomingPacketDispatcher({
    LanPresenceProtocolHandler? presenceProtocolHandler,
    LanTransferProtocolHandler? transferProtocolHandler,
    LanFriendProtocolHandler? friendProtocolHandler,
    LanShareProtocolHandler? shareProtocolHandler,
    LanClipboardProtocolHandler? clipboardProtocolHandler,
    LanShareCatalogChunkReassembler? shareCatalogChunkReassembler,
  }) : _presenceProtocolHandler =
           presenceProtocolHandler ?? const LanPresenceProtocolHandler(),
       _transferProtocolHandler =
           transferProtocolHandler ?? const LanTransferProtocolHandler(),
       _friendProtocolHandler =
           friendProtocolHandler ?? const LanFriendProtocolHandler(),
       _shareProtocolHandler =
           shareProtocolHandler ?? const LanShareProtocolHandler(),
       _clipboardProtocolHandler =
           clipboardProtocolHandler ?? const LanClipboardProtocolHandler(),
       _shareCatalogChunkReassembler =
           shareCatalogChunkReassembler ?? LanShareCatalogChunkReassembler();

  final LanPresenceProtocolHandler _presenceProtocolHandler;
  final LanTransferProtocolHandler _transferProtocolHandler;
  final LanFriendProtocolHandler _friendProtocolHandler;
  final LanShareProtocolHandler _shareProtocolHandler;
  final LanClipboardProtocolHandler _clipboardProtocolHandler;
  final LanShareCatalogChunkReassembler _shareCatalogChunkReassembler;

  void clear() {
    _shareCatalogChunkReassembler.clear();
  }

  void dispatch({
    required LanInboundPacket packet,
    required String senderIp,
    required DateTime observedAt,
    required LanIncomingPacketCallbacks callbacks,
    required void Function() onPresencePacketAccepted,
    required void Function() onDiscoveryResponseRequested,
    void Function(String message)? log,
  }) {
    if (packet is LanDiscoveryPresencePacket) {
      onPresencePacketAccepted();
      final result = _presenceProtocolHandler.handlePresencePacket(
        packet: packet,
        senderIp: senderIp,
        observedAt: observedAt,
      );
      if (result.shouldRespondToDiscover) {
        log?.call('Discover request from $senderIp');
        onDiscoveryResponseRequested();
        log?.call('Discover response sent to $senderIp');
      }
      final detectedEvent = result.detectedEvent;
      if (detectedEvent != null) {
        log?.call(
          'Discover response received from '
          '$senderIp (${detectedEvent.deviceName})',
        );
        callbacks.onAppDetected(detectedEvent);
      }
      return;
    }

    if (packet is LanTransferRequestPacket) {
      log?.call(
        'Transfer request received from $senderIp '
        '(requestId=${packet.requestId})',
      );
      callbacks.onTransferRequest?.call(
        _transferProtocolHandler.handleTransferRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanTransferDecisionPacket) {
      log?.call(
        'Transfer decision received from $senderIp '
        '(requestId=${packet.requestId}, approved=${packet.approved})',
      );
      callbacks.onTransferDecision?.call(
        _transferProtocolHandler.handleTransferDecisionPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanFriendRequestPacket) {
      log?.call(
        'Friend request received from $senderIp '
        '(requestId=${packet.requestId})',
      );
      callbacks.onFriendRequest?.call(
        _friendProtocolHandler.handleFriendRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanFriendResponsePacket) {
      log?.call(
        'Friend response received from $senderIp '
        '(requestId=${packet.requestId}, accepted=${packet.accepted})',
      );
      callbacks.onFriendResponse?.call(
        _friendProtocolHandler.handleFriendResponsePacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanShareQueryPacket) {
      callbacks.onShareQuery?.call(
        _shareProtocolHandler.handleShareQueryPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanShareAccessRequestPacket) {
      callbacks.onShareAccessRequest?.call(
        _shareProtocolHandler.handleShareAccessRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanShareAccessResponsePacket) {
      callbacks.onShareAccessResponse?.call(
        _shareProtocolHandler.handleShareAccessResponsePacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanShareCatalogPacket) {
      final reassembled = _shareCatalogChunkReassembler.consume(
        packet: packet,
        senderIp: senderIp,
        log: log,
      );
      if (reassembled == null) {
        return;
      }
      callbacks.onShareCatalog?.call(
        _shareProtocolHandler.handleShareCatalogPacket(
          packet: reassembled,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanDownloadRequestPacket) {
      callbacks.onDownloadRequest?.call(
        _shareProtocolHandler.handleDownloadRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanDownloadResponsePacket) {
      callbacks.onDownloadResponse?.call(
        _shareProtocolHandler.handleDownloadResponsePacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanThumbnailSyncRequestPacket) {
      callbacks.onThumbnailSyncRequest?.call(
        _shareProtocolHandler.handleThumbnailSyncRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanThumbnailPacket) {
      callbacks.onThumbnailPacket?.call(
        _shareProtocolHandler.handleThumbnailPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanClipboardQueryPacket) {
      callbacks.onClipboardQuery?.call(
        _clipboardProtocolHandler.handleClipboardQueryPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
      return;
    }

    if (packet is LanClipboardCatalogPacket) {
      callbacks.onClipboardCatalog?.call(
        _clipboardProtocolHandler.handleClipboardCatalogPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        ),
      );
    }
  }
}
