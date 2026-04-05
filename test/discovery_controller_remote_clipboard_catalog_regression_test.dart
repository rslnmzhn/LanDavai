import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/application/remote_clipboard_projection_store.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/discovery_transport_adapter.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_common.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/stub_discovery_network_interface_catalog.dart';
import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'DiscoveryController answers Windows-like oversized clipboard image queries with a packet-safe catalog that still projects remotely',
    () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_clipboard_catalog_regression_',
      );
      final database = harness.database;
      final deviceAliasRepository = DeviceAliasRepository(database: database);
      final deviceRegistry = DeviceRegistry(
        deviceAliasRepository: deviceAliasRepository,
      );
      final trustedLanPeerStore = TrustedLanPeerStore(
        deviceRegistry: deviceRegistry,
        deviceAliasRepository: deviceAliasRepository,
      );
      final transportAdapter = _FakeDiscoveryTransportAdapter(
        localIps: <String>{'192.168.1.10'},
      );
      final codec = LanPacketCodec();
      final lanDiscoveryService = LanDiscoveryService(
        transportAdapter: transportAdapter,
        packetCodec: codec,
      );
      final settingsStore = SettingsStore(
        appSettingsRepository: AppSettingsRepository(database: database),
      );
      final thumbnailCacheService = ThumbnailCacheService(database: database);
      final sharedFolderCacheRepository = SharedFolderCacheRepository(
        database: database,
      );
      final sharedCacheIndexStore = SharedCacheIndexStore(
        database: database,
        thumbnailCacheService: thumbnailCacheService,
      );
      final sharedCacheCatalog = SharedCacheCatalog(
        sharedCacheRecordStore: sharedFolderCacheRepository,
        sharedCacheIndexStore: sharedCacheIndexStore,
      );
      final fileHashService = FileHashService();
      final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
      final previewCacheOwner = PreviewCacheOwner(
        sharedCacheThumbnailStore: thumbnailCacheService,
        sharedCacheIndexStore: sharedCacheIndexStore,
        fileHashService: fileHashService,
      );
      final remoteShareBrowser = RemoteShareBrowser(
        sharedCacheCatalog: sharedCacheCatalog,
      );
      final remoteShareMediaProjectionBoundary =
          RemoteShareMediaProjectionBoundary(
            remoteShareBrowser: remoteShareBrowser,
            sharedCacheCatalog: sharedCacheCatalog,
            sharedCacheIndexStore: sharedCacheIndexStore,
            sharedCacheThumbnailStore: thumbnailCacheService,
            fileHashService: fileHashService,
            lanDiscoveryService: lanDiscoveryService,
          );
      final controller = DiscoveryController(
        lanDiscoveryService: lanDiscoveryService,
        networkHostScanner: _StubNetworkHostScanner(const <String, String?>{}),
        deviceRegistry: deviceRegistry,
        internetPeerEndpointStore: InternetPeerEndpointStore(
          friendRepository: FriendRepository(database: database),
        ),
        trustedLanPeerStore: trustedLanPeerStore,
        localPeerIdentityStore: localPeerIdentityStore,
        discoveryNetworkScopeStore: buildTestDiscoveryNetworkScopeStore(),
        settingsStore: settingsStore,
        appNotificationService: AppNotificationService.instance,
        transferHistoryRepository: TransferHistoryRepository(
          database: database,
        ),
        clipboardHistoryRepository: ClipboardHistoryRepository(
          database: database,
        ),
        clipboardCaptureService: ClipboardCaptureService(),
        remoteClipboardProjectionStore: RemoteClipboardProjectionStore(
          fileHashService: fileHashService,
        ),
        remoteShareBrowser: remoteShareBrowser,
        remoteShareMediaProjectionBoundary: remoteShareMediaProjectionBoundary,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: sharedCacheIndexStore,
        fileHashService: fileHashService,
        fileTransferService: FileTransferService(),
        transferStorageService: TransferStorageService(),
        previewCacheOwner: previewCacheOwner,
        pathOpener: PathOpener(),
      );

      addTearDown(() async {
        controller.dispose();
        previewCacheOwner.dispose();
        deviceRegistry.dispose();
        trustedLanPeerStore.dispose();
        await harness.dispose();
      });

      const requesterMac = '11:22:33:44:55:66';
      await trustedLanPeerStore.trustDevice(macAddress: requesterMac);

      final imagePath = await _createOversizedClipboardImage(
        harness.rootDirectory,
      );
      await ClipboardHistoryRepository(database: database).insert(
        ClipboardHistoryEntry(
          id: 'image-entry-1',
          type: ClipboardEntryType.image,
          contentHash: 'image:windows-like',
          imagePath: imagePath,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );

      await controller.start();
      transportAdapter.clearSentPackets();

      final queryPacket = codec.encodeClipboardQuery(
        instanceId: 'remote-instance',
        requestId: 'request-1',
        requesterName: 'Linux peer',
        requesterMacAddress: requesterMac,
        maxEntries: 5,
        createdAtMs: 1234,
      );

      expect(queryPacket, isNotNull);

      transportAdapter.emitDatagram(
        bytes: queryPacket!.bytes,
        senderIp: '192.168.1.44',
        senderPort: LanDiscoveryService.discoveryPort,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final responsePacket = transportAdapter.sentPackets.singleWhere(
        (packet) => packet.context == LanPacketCodec.clipboardCatalogPrefix,
      );
      final decoded =
          codec.decodeIncomingPacket(utf8.decode(responsePacket.bytes))
              as LanClipboardCatalogPacket?;

      expect(decoded, isNotNull);
      expect(
        responsePacket.bytes.length,
        lessThanOrEqualTo(lanMaxUdpPacketBytes),
      );
      expect(decoded!.entries, hasLength(1));
      expect(decoded.entries.single.entryType, 'image');
      expect(decoded.entries.single.imagePreviewBase64, isNotEmpty);

      final projectionStore = RemoteClipboardProjectionStore(
        fileHashService: fileHashService,
      );
      addTearDown(projectionStore.dispose);

      final applied = projectionStore.applyCatalog(
        ClipboardCatalogEvent(
          requestId: decoded.requestId,
          ownerIp: '192.168.1.10',
          ownerName: decoded.ownerName,
          ownerMacAddress: decoded.ownerMacAddress,
          observedAt: DateTime(2026),
          entries: decoded.entries,
        ),
      );

      expect(applied, isTrue);
      expect(projectionStore.entriesFor('192.168.1.10'), hasLength(1));
      expect(
        projectionStore.entriesFor('192.168.1.10').single.imageBytes,
        isNotEmpty,
      );
    },
  );
}

Future<String> _createOversizedClipboardImage(Directory rootDirectory) async {
  final image = img.Image(width: 1800, height: 1200);
  for (var y = 0; y < image.height; y += 1) {
    for (var x = 0; x < image.width; x += 1) {
      image.setPixelRgb(
        x,
        y,
        (x * 37 + y * 11) % 255,
        (x * 13 + y * 29) % 255,
        (x * 17 + y * 19) % 255,
      );
    }
  }
  final imageFile = File(
    '${rootDirectory.path}${Platform.pathSeparator}oversized_clipboard.png',
  );
  await imageFile.writeAsBytes(img.encodePng(image), flush: true);
  return imageFile.path;
}

class _StubNetworkHostScanner extends NetworkHostScanner {
  _StubNetworkHostScanner(this.result) : super(allowTcpFallback: false);

  final Map<String, String?> result;

  @override
  Future<Map<String, String?>> scanActiveHosts({
    required Set<String> localSourceIps,
    Set<String> configuredTargetIps = const <String>{},
  }) async {
    return result;
  }
}

class _FakeDiscoveryTransportAdapter implements DiscoveryTransportAdapter {
  _FakeDiscoveryTransportAdapter({required Set<String> localIps})
    : _localIps = Set<String>.from(localIps);

  final Set<String> _localIps;
  final List<_RecordedTransportPacket> sentPackets =
      <_RecordedTransportPacket>[];
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
      _RecordedTransportPacket(
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

class _RecordedTransportPacket {
  const _RecordedTransportPacket({
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
