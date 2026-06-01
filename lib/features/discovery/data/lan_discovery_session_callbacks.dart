import 'lan_protocol_events.dart';

class LanDiscoverySessionCallbacks {
  const LanDiscoverySessionCallbacks({
    required this.deviceName,
    required this.incoming,
  });

  final String deviceName;
  final LanIncomingPacketCallbacks incoming;
}

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
