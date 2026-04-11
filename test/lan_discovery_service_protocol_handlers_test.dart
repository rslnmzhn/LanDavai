import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/discovery_transport_adapter.dart';
import 'package:landa/features/discovery/data/lan_clipboard_protocol_handler.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_friend_protocol_handler.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_presence_protocol_handler.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/data/lan_share_protocol_handler.dart';
import 'package:landa/features/discovery/data/lan_transfer_protocol_handler.dart';

void main() {
  late LanPacketCodec codec;
  late FakeDiscoveryTransportAdapter transportAdapter;
  late RecordingPresenceHandler presenceHandler;
  late RecordingTransferHandler transferHandler;
  late RecordingFriendHandler friendHandler;
  late RecordingShareHandler shareHandler;
  late RecordingClipboardHandler clipboardHandler;
  late LanDiscoveryService service;

  setUp(() {
    codec = LanPacketCodec();
    transportAdapter = FakeDiscoveryTransportAdapter(
      localIps: <String>{'192.168.1.10'},
    );
    presenceHandler = RecordingPresenceHandler();
    transferHandler = RecordingTransferHandler();
    friendHandler = RecordingFriendHandler();
    shareHandler = RecordingShareHandler();
    clipboardHandler = RecordingClipboardHandler();
    service = LanDiscoveryService(
      transportAdapter: transportAdapter,
      packetCodec: codec,
      presenceProtocolHandler: presenceHandler,
      transferProtocolHandler: transferHandler,
      friendProtocolHandler: friendHandler,
      shareProtocolHandler: shareHandler,
      clipboardProtocolHandler: clipboardHandler,
    );
  });

  tearDown(() async {
    await service.stop();
  });

  test('delegates presence handling to explicit handler boundary', () async {
    final detectedEvent = AppPresenceEvent(
      ip: '192.168.1.24',
      deviceName: 'Handled peer',
      observedAt: DateTime.fromMillisecondsSinceEpoch(1),
      peerId: 'peer-24',
    );
    presenceHandler.nextResult = PresenceHandlingResult(
      detectedEvent: detectedEvent,
      shouldRespondToDiscover: true,
    );
    AppPresenceEvent? receivedEvent;

    await service.start(
      deviceName: 'Local workstation',
      localPeerId: 'local-peer',
      localSourceIps: const <String>{'192.168.1.10'},
      onAppDetected: (event) {
        receivedEvent = event;
      },
    );
    transportAdapter.clearSentPackets();

    transportAdapter.emitDatagram(
      bytes: utf8.encode(
        codec.encodeDiscoveryRequest(
          instanceId: 'remote-instance',
          deviceName: 'Remote node',
          localPeerId: 'remote-peer',
        ),
      ),
      senderIp: '192.168.1.24',
      senderPort: LanDiscoveryService.discoveryPort,
    );

    expect(presenceHandler.calls, 1);
    expect(receivedEvent, same(detectedEvent));
    expect(
      transportAdapter.sentPackets.map((packet) => packet.context),
      contains('discover-response'),
    );
  });

  test('delegates transfer and friend families to explicit handlers', () async {
    final transferRequestEvent = TransferRequestEvent(
      requestId: 'request-1',
      senderIp: 'sentinel-transfer-ip',
      senderName: 'Handled transfer sender',
      senderMacAddress: 'aa:bb:cc:dd:ee:ff',
      sharedCacheId: 'cache-1',
      sharedLabel: 'Docs',
      items: <TransferAnnouncementItem>[
        TransferAnnouncementItem(
          fileName: 'handled.txt',
          sizeBytes: 1,
          sha256: 'hash',
        ),
      ],
      observedAt: DateTime.fromMillisecondsSinceEpoch(2),
    );
    final transferDecisionEvent = TransferDecisionEvent(
      requestId: 'request-1',
      approved: true,
      receiverName: 'Handled receiver',
      receiverIp: 'sentinel-receiver-ip',
      transferPort: 40405,
      observedAt: DateTime.fromMillisecondsSinceEpoch(3),
      acceptedFileNames: <String>['handled.txt'],
    );
    final friendRequestEvent = FriendRequestEvent(
      requestId: 'friend-1',
      requesterIp: 'sentinel-friend-request-ip',
      requesterName: 'Handled requester',
      requesterMacAddress: '11:22:33:44:55:66',
      observedAt: DateTime.fromMillisecondsSinceEpoch(4),
    );
    final friendResponseEvent = FriendResponseEvent(
      requestId: 'friend-1',
      responderIp: 'sentinel-friend-response-ip',
      responderName: 'Handled responder',
      responderMacAddress: '66:55:44:33:22:11',
      accepted: true,
      observedAt: DateTime.fromMillisecondsSinceEpoch(5),
    );
    transferHandler.nextRequestEvent = transferRequestEvent;
    transferHandler.nextDecisionEvent = transferDecisionEvent;
    friendHandler.nextRequestEvent = friendRequestEvent;
    friendHandler.nextResponseEvent = friendResponseEvent;

    TransferRequestEvent? receivedTransferRequest;
    TransferDecisionEvent? receivedTransferDecision;
    FriendRequestEvent? receivedFriendRequest;
    FriendResponseEvent? receivedFriendResponse;

    await service.start(
      deviceName: 'Local workstation',
      localPeerId: 'local-peer',
      localSourceIps: const <String>{'192.168.1.10'},
      onAppDetected: (_) {},
      onTransferRequest: (event) {
        receivedTransferRequest = event;
      },
      onTransferDecision: (event) {
        receivedTransferDecision = event;
      },
      onFriendRequest: (event) {
        receivedFriendRequest = event;
      },
      onFriendResponse: (event) {
        receivedFriendResponse = event;
      },
    );

    transportAdapter.emitDatagram(
      bytes: codec
          .encodeTransferRequest(
            instanceId: 'remote-instance',
            requestId: 'request-1',
            senderName: 'Alice',
            senderMacAddress: 'aa:bb:cc:dd:ee:ff',
            sharedCacheId: 'cache-1',
            sharedLabel: 'Docs',
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'report.pdf',
                sizeBytes: 42,
                sha256: 'hash-1',
              ),
            ],
            createdAtMs: 1,
          )!
          .bytes,
      senderIp: '192.168.1.24',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeTransferDecision(
            instanceId: 'remote-instance',
            requestId: 'request-1',
            approved: true,
            receiverName: 'Bob',
            transferPort: 40405,
            acceptedFileNames: <String>['report.pdf'],
            createdAtMs: 2,
          )!
          .bytes,
      senderIp: '192.168.1.24',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeFriendRequest(
            instanceId: 'remote-instance',
            requestId: 'friend-1',
            requesterName: 'Charlie',
            requesterMacAddress: '11:22:33:44:55:66',
            createdAtMs: 3,
          )!
          .bytes,
      senderIp: '192.168.1.25',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeFriendResponse(
            instanceId: 'remote-instance',
            requestId: 'friend-1',
            responderName: 'Dana',
            responderMacAddress: '66:55:44:33:22:11',
            accepted: true,
            createdAtMs: 4,
          )!
          .bytes,
      senderIp: '192.168.1.25',
      senderPort: LanDiscoveryService.discoveryPort,
    );

    expect(transferHandler.transferRequestCalls, 1);
    expect(transferHandler.transferDecisionCalls, 1);
    expect(friendHandler.friendRequestCalls, 1);
    expect(friendHandler.friendResponseCalls, 1);
    expect(receivedTransferRequest, same(transferRequestEvent));
    expect(receivedTransferDecision, same(transferDecisionEvent));
    expect(receivedFriendRequest, same(friendRequestEvent));
    expect(receivedFriendResponse, same(friendResponseEvent));
  });

  test('delegates share and clipboard families to explicit handlers', () async {
    final shareQueryEvent = ShareQueryEvent(
      requestId: 'share-1',
      requesterIp: 'sentinel-share-query-ip',
      requesterName: 'Handled share requester',
      observedAt: DateTime.fromMillisecondsSinceEpoch(6),
    );
    final shareCatalogEvent = ShareCatalogEvent(
      requestId: 'share-1',
      ownerIp: 'sentinel-share-owner-ip',
      ownerName: 'Handled owner',
      ownerMacAddress: 'aa:aa:aa:aa:aa:aa',
      entries: const <SharedCatalogEntryItem>[],
      removedCacheIds: <String>['stale'],
      observedAt: DateTime.fromMillisecondsSinceEpoch(7),
    );
    final downloadRequestEvent = DownloadRequestEvent(
      requestId: 'download-1',
      requesterIp: 'sentinel-download-ip',
      requesterName: 'Handled downloader',
      requesterMacAddress: 'bb:bb:bb:bb:bb:bb',
      cacheId: 'cache-2',
      selectedRelativePaths: <String>['docs/report.pdf'],
      selectedFolderPrefixes: const <String>[],
      previewMode: true,
      observedAt: DateTime.fromMillisecondsSinceEpoch(8),
    );
    final downloadResponseEvent = DownloadResponseEvent(
      requestId: 'download-1',
      responderIp: 'sentinel-download-response-ip',
      responderName: 'Handled sender',
      approved: false,
      message: 'Rejected',
      observedAt: DateTime.fromMillisecondsSinceEpoch(8),
    );
    final thumbnailSyncEvent = ThumbnailSyncRequestEvent(
      requestId: 'thumb-sync-1',
      requesterIp: 'sentinel-thumb-sync-ip',
      requesterName: 'Handled sync requester',
      items: const <ThumbnailSyncItem>[
        ThumbnailSyncItem(
          cacheId: 'cache-3',
          relativePath: 'image.png',
          thumbnailId: 'thumb-1',
        ),
      ],
      observedAt: DateTime.fromMillisecondsSinceEpoch(9),
    );
    final thumbnailPacketEvent = ThumbnailPacketEvent(
      requestId: 'thumb-packet-1',
      ownerIp: 'sentinel-thumb-owner-ip',
      ownerMacAddress: 'cc:cc:cc:cc:cc:cc',
      cacheId: 'cache-3',
      relativePath: 'image.png',
      thumbnailId: 'thumb-1',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      observedAt: DateTime.fromMillisecondsSinceEpoch(10),
    );
    final clipboardQueryEvent = ClipboardQueryEvent(
      requestId: 'clip-1',
      requesterIp: 'sentinel-clipboard-query-ip',
      requesterName: 'Handled clipboard requester',
      requesterMacAddress: 'dd:dd:dd:dd:dd:dd',
      maxEntries: 5,
      observedAt: DateTime.fromMillisecondsSinceEpoch(11),
    );
    final clipboardCatalogEvent = ClipboardCatalogEvent(
      requestId: 'clip-1',
      ownerIp: 'sentinel-clipboard-owner-ip',
      ownerName: 'Handled clipboard owner',
      ownerMacAddress: 'ee:ee:ee:ee:ee:ee',
      entries: const <ClipboardCatalogItem>[
        ClipboardCatalogItem(
          id: 'clip-entry-1',
          entryType: 'text',
          createdAtMs: 12,
          textValue: 'hello',
        ),
      ],
      observedAt: DateTime.fromMillisecondsSinceEpoch(12),
    );
    shareHandler.nextShareQueryEvent = shareQueryEvent;
    shareHandler.nextShareCatalogEvent = shareCatalogEvent;
    shareHandler.nextDownloadRequestEvent = downloadRequestEvent;
    shareHandler.nextDownloadResponseEvent = downloadResponseEvent;
    shareHandler.nextThumbnailSyncRequestEvent = thumbnailSyncEvent;
    shareHandler.nextThumbnailPacketEvent = thumbnailPacketEvent;
    clipboardHandler.nextClipboardQueryEvent = clipboardQueryEvent;
    clipboardHandler.nextClipboardCatalogEvent = clipboardCatalogEvent;

    ShareQueryEvent? receivedShareQuery;
    ShareCatalogEvent? receivedShareCatalog;
    DownloadRequestEvent? receivedDownloadRequest;
    DownloadResponseEvent? receivedDownloadResponse;
    ThumbnailSyncRequestEvent? receivedThumbnailSyncRequest;
    ThumbnailPacketEvent? receivedThumbnailPacket;
    ClipboardQueryEvent? receivedClipboardQuery;
    ClipboardCatalogEvent? receivedClipboardCatalog;

    await service.start(
      deviceName: 'Local workstation',
      localPeerId: 'local-peer',
      localSourceIps: const <String>{'192.168.1.10'},
      onAppDetected: (_) {},
      onShareQuery: (event) {
        receivedShareQuery = event;
      },
      onShareCatalog: (event) {
        receivedShareCatalog = event;
      },
      onDownloadRequest: (event) {
        receivedDownloadRequest = event;
      },
      onDownloadResponse: (event) {
        receivedDownloadResponse = event;
      },
      onThumbnailSyncRequest: (event) {
        receivedThumbnailSyncRequest = event;
      },
      onThumbnailPacket: (event) {
        receivedThumbnailPacket = event;
      },
      onClipboardQuery: (event) {
        receivedClipboardQuery = event;
      },
      onClipboardCatalog: (event) {
        receivedClipboardCatalog = event;
      },
    );

    transportAdapter.emitDatagram(
      bytes: codec
          .encodeShareQuery(
            instanceId: 'remote-instance',
            requestId: 'share-1',
            requesterName: 'Owner',
            createdAtMs: 5,
          )!
          .bytes,
      senderIp: '192.168.1.26',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeShareCatalog(
            instanceId: 'remote-instance',
            requestId: 'share-1',
            ownerName: 'Owner',
            ownerMacAddress: 'aa:aa:aa:aa:aa:aa',
            entries: <SharedCatalogEntryItem>[
              SharedCatalogEntryItem(
                cacheId: 'cache-2',
                displayName: 'Docs',
                itemCount: 1,
                totalBytes: 42,
                files: <SharedCatalogFileItem>[
                  SharedCatalogFileItem(
                    relativePath: 'docs/report.pdf',
                    sizeBytes: 42,
                  ),
                ],
              ),
            ],
            removedCacheIds: <String>['stale'],
            createdAtMs: 6,
          )!
          .bytes,
      senderIp: '192.168.1.26',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeDownloadRequest(
            instanceId: 'remote-instance',
            requestId: 'download-1',
            requesterName: 'Owner',
            requesterMacAddress: 'bb:bb:bb:bb:bb:bb',
            cacheId: 'cache-2',
            selectedRelativePaths: <String>['docs/report.pdf'],
            selectedFolderPrefixes: const <String>[],
            previewMode: true,
            createdAtMs: 7,
          )!
          .bytes,
      senderIp: '192.168.1.26',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeDownloadResponse(
            instanceId: 'remote-instance',
            requestId: 'download-1',
            responderName: 'Owner',
            approved: false,
            message: 'Rejected',
            createdAtMs: 7,
          )!
          .bytes,
      senderIp: '192.168.1.26',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeThumbnailSyncRequest(
            instanceId: 'remote-instance',
            requestId: 'thumb-sync-1',
            requesterName: 'Owner',
            items: const <ThumbnailSyncItem>[
              ThumbnailSyncItem(
                cacheId: 'cache-3',
                relativePath: 'image.png',
                thumbnailId: 'thumb-1',
              ),
            ],
            createdAtMs: 8,
          )!
          .bytes,
      senderIp: '192.168.1.26',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeThumbnailPacket(
            instanceId: 'remote-instance',
            requestId: 'thumb-packet-1',
            ownerMacAddress: 'cc:cc:cc:cc:cc:cc',
            cacheId: 'cache-3',
            relativePath: 'image.png',
            thumbnailId: 'thumb-1',
            bytes: Uint8List.fromList(<int>[9, 8, 7]),
            createdAtMs: 9,
          )!
          .bytes,
      senderIp: '192.168.1.26',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeClipboardQuery(
            instanceId: 'remote-instance',
            requestId: 'clip-1',
            requesterName: 'Owner',
            requesterMacAddress: 'dd:dd:dd:dd:dd:dd',
            maxEntries: 5,
            createdAtMs: 10,
          )!
          .bytes,
      senderIp: '192.168.1.27',
      senderPort: LanDiscoveryService.discoveryPort,
    );
    transportAdapter.emitDatagram(
      bytes: codec
          .encodeClipboardCatalog(
            instanceId: 'remote-instance',
            requestId: 'clip-1',
            ownerName: 'Owner',
            ownerMacAddress: 'ee:ee:ee:ee:ee:ee',
            entries: const <ClipboardCatalogItem>[
              ClipboardCatalogItem(
                id: 'clip-entry-1',
                entryType: 'text',
                createdAtMs: 12,
                textValue: 'hello',
              ),
            ],
            createdAtMs: 11,
          )!
          .bytes,
      senderIp: '192.168.1.27',
      senderPort: LanDiscoveryService.discoveryPort,
    );

    expect(shareHandler.shareQueryCalls, 1);
    expect(shareHandler.shareCatalogCalls, 1);
    expect(shareHandler.downloadRequestCalls, 1);
    expect(shareHandler.downloadResponseCalls, 1);
    expect(shareHandler.thumbnailSyncRequestCalls, 1);
    expect(shareHandler.thumbnailPacketCalls, 1);
    expect(clipboardHandler.clipboardQueryCalls, 1);
    expect(clipboardHandler.clipboardCatalogCalls, 1);
    expect(receivedShareQuery, same(shareQueryEvent));
    expect(receivedShareCatalog, same(shareCatalogEvent));
    expect(receivedDownloadRequest, same(downloadRequestEvent));
    expect(receivedDownloadResponse, same(downloadResponseEvent));
    expect(receivedThumbnailSyncRequest, same(thumbnailSyncEvent));
    expect(receivedThumbnailPacket, same(thumbnailPacketEvent));
    expect(receivedClipboardQuery, same(clipboardQueryEvent));
    expect(receivedClipboardCatalog, same(clipboardCatalogEvent));
  });
}

class RecordingPresenceHandler extends LanPresenceProtocolHandler {
  int calls = 0;
  PresenceHandlingResult nextResult = const PresenceHandlingResult();

  @override
  PresenceHandlingResult handlePresencePacket({
    required LanDiscoveryPresencePacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    calls += 1;
    return nextResult;
  }
}

class RecordingTransferHandler extends LanTransferProtocolHandler {
  int transferRequestCalls = 0;
  int transferDecisionCalls = 0;
  TransferRequestEvent? nextRequestEvent;
  TransferDecisionEvent? nextDecisionEvent;

  @override
  TransferRequestEvent handleTransferRequestPacket({
    required LanTransferRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    transferRequestCalls += 1;
    return nextRequestEvent ??
        super.handleTransferRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }

  @override
  TransferDecisionEvent handleTransferDecisionPacket({
    required LanTransferDecisionPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    transferDecisionCalls += 1;
    return nextDecisionEvent ??
        super.handleTransferDecisionPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }
}

class RecordingFriendHandler extends LanFriendProtocolHandler {
  int friendRequestCalls = 0;
  int friendResponseCalls = 0;
  FriendRequestEvent? nextRequestEvent;
  FriendResponseEvent? nextResponseEvent;

  @override
  FriendRequestEvent handleFriendRequestPacket({
    required LanFriendRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    friendRequestCalls += 1;
    return nextRequestEvent ??
        super.handleFriendRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }

  @override
  FriendResponseEvent handleFriendResponsePacket({
    required LanFriendResponsePacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    friendResponseCalls += 1;
    return nextResponseEvent ??
        super.handleFriendResponsePacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }
}

class RecordingShareHandler extends LanShareProtocolHandler {
  int shareQueryCalls = 0;
  int shareCatalogCalls = 0;
  int downloadRequestCalls = 0;
  int downloadResponseCalls = 0;
  int thumbnailSyncRequestCalls = 0;
  int thumbnailPacketCalls = 0;
  ShareQueryEvent? nextShareQueryEvent;
  ShareCatalogEvent? nextShareCatalogEvent;
  DownloadRequestEvent? nextDownloadRequestEvent;
  DownloadResponseEvent? nextDownloadResponseEvent;
  ThumbnailSyncRequestEvent? nextThumbnailSyncRequestEvent;
  ThumbnailPacketEvent? nextThumbnailPacketEvent;

  @override
  ShareQueryEvent handleShareQueryPacket({
    required LanShareQueryPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    shareQueryCalls += 1;
    return nextShareQueryEvent ??
        super.handleShareQueryPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }

  @override
  ShareCatalogEvent handleShareCatalogPacket({
    required LanShareCatalogPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    shareCatalogCalls += 1;
    return nextShareCatalogEvent ??
        super.handleShareCatalogPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }

  @override
  DownloadRequestEvent handleDownloadRequestPacket({
    required LanDownloadRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    downloadRequestCalls += 1;
    return nextDownloadRequestEvent ??
        super.handleDownloadRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }

  @override
  DownloadResponseEvent handleDownloadResponsePacket({
    required LanDownloadResponsePacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    downloadResponseCalls += 1;
    return nextDownloadResponseEvent ??
        super.handleDownloadResponsePacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }

  @override
  ThumbnailSyncRequestEvent handleThumbnailSyncRequestPacket({
    required LanThumbnailSyncRequestPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    thumbnailSyncRequestCalls += 1;
    return nextThumbnailSyncRequestEvent ??
        super.handleThumbnailSyncRequestPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }

  @override
  ThumbnailPacketEvent handleThumbnailPacket({
    required LanThumbnailPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    thumbnailPacketCalls += 1;
    return nextThumbnailPacketEvent ??
        super.handleThumbnailPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }
}

class RecordingClipboardHandler extends LanClipboardProtocolHandler {
  int clipboardQueryCalls = 0;
  int clipboardCatalogCalls = 0;
  ClipboardQueryEvent? nextClipboardQueryEvent;
  ClipboardCatalogEvent? nextClipboardCatalogEvent;

  @override
  ClipboardQueryEvent handleClipboardQueryPacket({
    required LanClipboardQueryPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    clipboardQueryCalls += 1;
    return nextClipboardQueryEvent ??
        super.handleClipboardQueryPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }

  @override
  ClipboardCatalogEvent handleClipboardCatalogPacket({
    required LanClipboardCatalogPacket packet,
    required String senderIp,
    required DateTime observedAt,
  }) {
    clipboardCatalogCalls += 1;
    return nextClipboardCatalogEvent ??
        super.handleClipboardCatalogPacket(
          packet: packet,
          senderIp: senderIp,
          observedAt: observedAt,
        );
  }
}

class FakeDiscoveryTransportAdapter implements DiscoveryTransportAdapter {
  FakeDiscoveryTransportAdapter({required Set<String> localIps})
    : _localIps = Set<String>.from(localIps);

  final Set<String> _localIps;
  final List<RecordedTransportPacket> sentPackets = <RecordedTransportPacket>[];
  void Function(Datagram datagram)? _onDatagram;
  bool _started = false;

  @override
  Set<String> get localIps => Set<String>.unmodifiable(_localIps);

  @override
  bool get isStarted => _started;

  @override
  int? get boundPort => LanDiscoveryService.discoveryPort;

  @override
  Future<void> start({
    required int port,
    required void Function(Datagram datagram) onDatagram,
    required Set<String> localSourceIps,
  }) async {
    _started = true;
    _localIps
      ..clear()
      ..addAll(localSourceIps);
    _onDatagram = onDatagram;
  }

  @override
  Future<void> stop() async {
    _started = false;
    _onDatagram = null;
  }

  @override
  void send({
    required List<int> bytes,
    required InternetAddress address,
    required int port,
    required String context,
  }) {
    sentPackets.add(
      RecordedTransportPacket(
        bytes: Uint8List.fromList(bytes),
        address: address,
        port: port,
        context: context,
      ),
    );
  }

  void emitDatagram({
    required List<int> bytes,
    required String senderIp,
    required int senderPort,
  }) {
    final callback = _onDatagram;
    if (callback == null) {
      throw StateError('Transport callback is not registered.');
    }
    callback(
      Datagram(
        Uint8List.fromList(bytes),
        InternetAddress(senderIp),
        senderPort,
      ),
    );
  }

  void clearSentPackets() {
    sentPackets.clear();
  }
}

class RecordedTransportPacket {
  const RecordedTransportPacket({
    required this.bytes,
    required this.address,
    required this.port,
    required this.context,
  });

  final Uint8List bytes;
  final InternetAddress address;
  final int port;
  final String context;
}
