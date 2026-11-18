import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/update/data/app_update_download_service.dart';
import 'package:landa/app/update/data/app_update_storage_service.dart';
import 'package:landa/app/update/domain/app_update_models.dart';
import 'package:landa/features/clipboard/application/clipboard_history_store.dart';
import 'package:landa/features/clipboard/application/remote_clipboard_projection_store.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/discovery/application/clipboard_packet_route_adapter.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/data/lan_share_catalog_chunk_reassembler.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_session_store.dart';
import 'package:landa/features/nearby_transfer/data/lan_nearby_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_file_picker.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_storage_service.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/data/qr_payload_codec.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/transfer/application/remote_share_access_snapshot_parser.dart';
import 'package:landa/features/transfer/application/transfer_cache_preparation_path_resolver.dart';
import 'package:landa/features/transfer/application/transfer_path_policy.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/data/transfer_header_codec.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:landa/features/transfer/domain/transfer_request.dart';
import 'package:path/path.dart' as p;

import 'test_support/fake_nearby_transfer.dart';
import 'test_support/test_app_database.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Security Adversarial Tests (Vulnerability Demonstrations)', () {
    // -------------------------------------------------------------------------
    // VULNERABILITY 1: Path Traversal in Thumbnail Receiver (Arbitrary File Write)
    // CWE-22: Improper Limitation of a Pathname to a Restricted Directory
    // Impact: Critical - Remote Code Execution / Arbitrary File Overwrite via UDP
    // -------------------------------------------------------------------------
    test(
      'ThumbnailCacheService.saveReceiverThumbnailBytes rejects directory traversal in cacheId and thumbnailId',
      () async {
        final harness = await TestAppDatabaseHarness.create(
          prefix: 'landa_thumb_vuln_',
        );
        addTearDown(harness.dispose);

        final service = ThumbnailCacheService(database: harness.database);
        final thumbRoot = await harness.database.resolveSharedThumbnailDirectory();

        final maliciousCacheId = '../../../../tmp';
        final maliciousThumbnailId = 'hacked_payload';
        final payloadBytes = Uint8List.fromList(utf8.encode('MALICIOUS_DATA'));

        final savedPath = await service.saveReceiverThumbnailBytes(
          ownerMacAddress: '00:11:22:33:44:55',
          cacheId: maliciousCacheId,
          thumbnailId: maliciousThumbnailId,
          bytes: payloadBytes,
        );

        expect(
          p.isWithin(thumbRoot.path, savedPath),
          isTrue,
          reason:
              'CWE-22: saveReceiverThumbnailBytes allowed writing outside thumbnail directory: $savedPath',
        );
      },
    );

    // -------------------------------------------------------------------------
    // VULNERABILITY 2: Path Traversal in Transfer Receive Root Prefix
    // CWE-22: Improper Limitation of a Pathname to a Restricted Directory
    // Impact: High - Overwriting files outside download folder
    // -------------------------------------------------------------------------
    test(
      'TransferPathPolicy rejects ".." and absolute paths in destinationRelativeRootPrefix',
      () {
        const policy = TransferPathPolicy();

        // 1. resolveReceiveRootPrefix rejects '..'
        final prefixFromDots = policy.resolveReceiveRootPrefix('..');
        expect(
          prefixFromDots,
          isNull,
          reason:
              'CWE-22: resolveReceiveRootPrefix("..") returned non-null enabling traversal',
        );

        // 2. buildReceiveRelativePath sanitizes destinationRelativeRootPrefix
        final relativePathWithAbsolute = policy.buildReceiveRelativePath(
          'test.bin',
          destinationRelativeRootPrefix: '/etc',
        );
        expect(
          p.isAbsolute(relativePathWithAbsolute),
          isFalse,
          reason:
              'CWE-22: buildReceiveRelativePath allowed absolute root prefix, escaping download directory',
        );

        final relativePathWithTraversal = policy.buildReceiveRelativePath(
          'test.bin',
          destinationRelativeRootPrefix: '../../evil',
        );
        expect(
          relativePathWithTraversal.startsWith('..'),
          isFalse,
          reason:
              'CWE-22: buildReceiveRelativePath returned path starting with ".."',
        );
      },
    );

    // -------------------------------------------------------------------------
    // VULNERABILITY 3: Clipboard Exfiltration via Spoofed MAC Address over UDP
    // CWE-290: Authentication Bypass by Spoofing
    // CWE-200: Exposure of Sensitive Information
    // Impact: Critical - Silent exfiltration of passwords, tokens, private text
    // -------------------------------------------------------------------------
    test(
      'ClipboardPacketRouteAdapter does not exfiltrate clipboard data to arbitrary IP spoofing a friend MAC',
      () async {
        final harness = await TestAppDatabaseHarness.create(
          prefix: 'landa_clip_vuln_',
        );
        addTearDown(harness.dispose);

        final recordingLanService = _RecordingLanDiscoveryService();
        final repository = ClipboardHistoryRepository(database: harness.database);

        final testEntry = ClipboardHistoryEntry(
          id: 'secret_entry_1',
          type: ClipboardEntryType.text,
          contentHash: 'hash123',
          textValue: 'SUPER_SECRET_PASSWORD_12345',
          createdAt: DateTime.now(),
        );
        await repository.insert(testEntry);

        final historyStore = ClipboardHistoryStore(
          clipboardHistoryRepository: repository,
          clipboardCaptureService: _FakeClipboardCaptureService(),
          transferStorageService: TransferStorageService(),
        );
        await historyStore.load();

        const friendMac = 'aa:bb:cc:dd:ee:ff';
        const friendIp = '192.168.1.55';
        final adapter = ClipboardPacketRouteAdapter(
          lanDiscoveryService: recordingLanService,
          clipboardHistoryStore: historyStore,
          remoteClipboardProjectionStore: RemoteClipboardProjectionStore(
            fileHashService: FileHashService(),
          ),
          settingsProvider: () => AppSettings.defaults,
          localNameProvider: () => 'MyDevice',
          localDeviceMacProvider: () => '11:22:33:44:55:66',
          isTrustedMac: (mac) => mac == friendMac,
          isTrustedSender: (ip, mac) => ip == friendIp && mac == friendMac,
        );

        // An attacker from 192.168.1.250 sends UDP query spoofing friendMac:
        await adapter.handleClipboardQuery(
          ClipboardQueryEvent(
            requestId: 'query-1',
            requesterIp: '192.168.1.250', // Attacker IP
            requesterName: 'Attacker',
            requesterMacAddress: friendMac, // Spoofed MAC
            maxEntries: 10,
            observedAt: DateTime.now(),
          ),
        );

        expect(
          recordingLanService.catalogs.isEmpty,
          isTrue,
          reason:
              'CWE-290/CWE-200: Clipboard history exfiltrated to attacker IP because MAC was spoofed in UDP packet!',
        );
      },
    );

    // -------------------------------------------------------------------------
    // VULNERABILITY 4: Zip Bomb / Decompression DoS in TransferHeaderCodec
    // CWE-409: Improper Handling of Highly Compressed Data (Data Amplification)
    // CWE-400: Uncontrolled Resource Consumption
    // Impact: High - Remote crash / Out of Memory (OOM) via TCP connection
    // -------------------------------------------------------------------------
    test(
      'TransferHeaderCodec.decode rejects decompression bombs exceeding safe size threshold',
      () {
        const codec = TransferHeaderCodec();

        final rawLargeData = Uint8List(16 * 1024 * 1024); // 16 MB of zeroes
        final compressedBomb = Uint8List.fromList(gzip.encode(rawLargeData));

        expect(
          () => codec.decode(compressedBomb),
          throwsA(
            predicate((e) =>
                e is FormatException &&
                e.toString().toLowerCase().contains('decompression limit')),
          ),
          reason:
              'CWE-409: TransferHeaderCodec.decode performs unbounded gzip decompression without size limit',
        );
      },
    );

    // -------------------------------------------------------------------------
    // VULNERABILITY 5: Unbounded Chunk Map Growth in LanShareCatalogChunkReassembler
    // CWE-400: Uncontrolled Resource Consumption
    // Impact: High - Memory exhaustion / DoS via spoofed UDP chunks
    // -------------------------------------------------------------------------
    test(
      'LanShareCatalogChunkReassembler rejects excessive chunkCount to prevent memory exhaustion',
      () {
        final reassembler = LanShareCatalogChunkReassembler();

        final maliciousPacket = LanShareCatalogPacket(
          instanceId: 'inst-1',
          requestId: 'req-1',
          ownerName: 'Evil',
          ownerMacAddress: '00:11:22:33:44:55',
          entries: const [],
          removedCacheIds: const [],
          chunkIndex: 0,
          chunkCount: 1000000,
        );

        final result = reassembler.consume(
          packet: maliciousPacket,
          senderIp: '192.168.1.100',
        );

        expect(
          result,
          isNull,
        );

        expect(
          reassembler.pendingCount,
          equals(0),
          reason:
              'CWE-400: Chunk reassembler tracked pending state for chunkCount = ${maliciousPacket.chunkCount}, enabling memory exhaustion DoS',
        );
      },
    );

    // -------------------------------------------------------------------------
    // VULNERABILITY 6: Path Traversal in AppUpdateStorageService.createTargetFile
    // CWE-22: Improper Limitation of a Pathname to a Restricted Directory
    // Impact: Medium/High - Overwriting files outside update directory
    // -------------------------------------------------------------------------
    test(
      'AppUpdateStorageService.createTargetFile sanitizes fileName against directory traversal',
      () async {
        final mockDir = await Directory.systemTemp.createTemp('mock_dl_');
        addTearDown(() => mockDir.delete(recursive: true));

        final storageService = AppUpdateStorageService(
          updateDirectoryResolver: () async => mockDir,
        );

        final targetFile = await storageService.createTargetFile(
          '../../outside_update.bin',
        );

        expect(
          p.isWithin(mockDir.path, targetFile.path),
          isTrue,
          reason:
              'CWE-22: createTargetFile allowed target file path to escape update directory: ${targetFile.path}',
        );
      },
    );

    // -------------------------------------------------------------------------
    // BUG 7: FileTransferService Reports Success When Zero Files Received
    // CWE-390 / CWE-754: Improper Check for Unusual or Exceptional Conditions
    // Impact: Medium - False positive transfer completion
    // -------------------------------------------------------------------------
    test(
      'FileTransferService._receiveFiles rejects transfer if expected items were specified but actual list is empty',
      () async {
        final service = FileTransferService();
        final tempDir = await Directory.systemTemp.createTemp('landa_xfer_test_');
        addTearDown(() => tempDir.delete(recursive: true));

        final expectedItem = const TransferFileManifestItem(
          fileName: 'important_document.pdf',
          sizeBytes: 1024,
          sha256: 'abc1234567890abcdef',
        );

        final session = await service.startReceiver(
          requestId: 'test-req-123',
          expectedItems: [expectedItem],
          destinationDirectory: tempDir,
        );

        final socket = await Socket.connect(InternetAddress.loopbackIPv4, session.port);
        final emptyHeader = const TransferHeader(
          requestId: 'test-req-123',
          files: [],
        );
        const headerCodec = TransferHeaderCodec();
        final encoded = headerCodec.encode(emptyHeader);

        final lengthBytes = ByteData(4)..setUint32(0, encoded.bytes.length, Endian.big);
        socket.add(lengthBytes.buffer.asUint8List());
        socket.add(encoded.bytes);
        await socket.flush();
        await socket.close();

        final result = await session.result;

        expect(
          result.success,
          isFalse,
          reason:
              'CWE-754: FileTransferService reported success=true despite receiving 0 of 1 expected files',
        );
      },
    );

    test(
      'NearbyTransferSessionStore rejects file offers while awaiting 2-digit handshake',
      () async {
        final harness = await TestDiscoveryControllerHarness.create();
        addTearDown(harness.dispose);
        final lanAdapter = FakeNearbyTransferTransportAdapter();
        final store = buildTestNearbyTransferStore(
          readModel: harness.readModel,
          lanAdapter: lanAdapter,
        );
        addTearDown(store.dispose);

        await store.prepareReceiveFlow();
        lanAdapter.emit(
          const NearbyTransferConnectedEvent(
            peer: NearbyTransferPeerDevice(
              deviceId: 'attacker-id',
              displayName: 'Attacker',
              host: '192.168.1.99',
            ),
            sessionId: 'sess-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(store.phase, NearbyTransferSessionPhase.awaitingHandshake);

        lanAdapter.emit(
          const NearbyTransferIncomingSelectionOfferedEvent(
            requestId: 'unauth-offer',
            label: 'Malicious',
            roots: <NearbyTransferRemoteOfferNode>[
              NearbyTransferRemoteOfferNode(
                id: 'f1',
                name: 'payload.apk',
                relativePath: 'payload.apk',
                kind: NearbyTransferRemoteOfferNodeKind.file,
                sizeBytes: 1024,
                previewKind: NearbyTransferRemotePreviewKind.none,
              ),
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(store.phase, NearbyTransferSessionPhase.awaitingHandshake);
        expect(store.hasIncomingOffer, isFalse);
      },
    );

    test(
      'LanNearbyTransportAdapter drops unauthenticated messages before connect and caps oversized lines',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('landa_nearby_sec_');
        addTearDown(() => tempDir.delete(recursive: true));
        final adapter = LanNearbyTransportAdapter(
          fileHashService: FileHashService(),
          fileTransferService: FileTransferService(),
          storageService: NearbyTransferStorageService(
            transferStorageService: TransferStorageService(),
          ),
          preferredPort: 0,
        );
        addTearDown(adapter.dispose);

        final receivedOffers = <NearbyTransferIncomingSelectionOfferedEvent>[];
        final errors = <NearbyTransferErrorEvent>[];
        final sub = adapter.events.listen((event) {
          if (event is NearbyTransferIncomingSelectionOfferedEvent) {
            receivedOffers.add(event);
          } else if (event is NearbyTransferErrorEvent) {
            errors.add(event);
          }
        });
        addTearDown(sub.cancel);

        final hosting = await adapter.startHostingSession(
          sessionId: 'host-session',
          localDeviceId: 'host-id',
          localDeviceName: 'Host',
        );

        final rawSocket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          hosting.port,
        );
        rawSocket.write(
          '${jsonEncode(<String, Object?>{
            'type': 'fileOffer',
            'requestId': 'r1',
            'label': 'Spoofed',
            'files': <Map<String, Object?>>[
              {'id': '1', 'relativePath': 'x.txt', 'sizeBytes': 1, 'sha256': 'a'},
            ],
          })}\n',
        );
        await rawSocket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(receivedOffers, isEmpty);

        // Stream > maxControlLineBytes without newline -> must disconnect with error instead of OOM
        rawSocket.add(
          Uint8List(LanNearbyTransportAdapter.maxControlLineBytes + 1024),
        );
        await rawSocket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(errors, isNotEmpty);
        await rawSocket.close();
      },
    );

    test(
      'RemoteShareAccessSnapshotParser rejects gzip decompression bombs',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('landa_snap_bomb_');
        addTearDown(() => tempDir.delete(recursive: true));
        final bombFile = File(p.join(tempDir.path, 'snapshot.json.gz'));
        await bombFile.writeAsBytes(gzip.encode(Uint8List(256 * 1024)));

        const parser = RemoteShareAccessSnapshotParser(
          maxDecompressedBytes: 64 * 1024,
        );
        await expectLater(
          parser.parse(<String>[bombFile.path]),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'VideoLinkShareService blocks oversized POST bodies, rate-limits brute force, and rejects symlinks',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('landa_vid_sec_');
        addTearDown(() => tempDir.delete(recursive: true));
        final videoFile = File(p.join(tempDir.path, 'clip.mp4'));
        await videoFile.writeAsBytes(Uint8List.fromList(<int>[0, 1, 2, 3]));
        final symlinkFile = Link(p.join(tempDir.path, 'linked.mp4'));
        await symlinkFile.create(videoFile.path);

        final service = VideoLinkShareService();
        addTearDown(service.stop);

        await expectLater(
          service.publish(
            filePath: symlinkFile.path,
            displayName: 'linked',
            password: 'secret',
            port: 0,
          ),
          throwsA(isA<ArgumentError>()),
        );

        final session = await service.publish(
          filePath: videoFile.path,
          displayName: 'clip.mp4',
          password: 'correct-password',
          port: 0,
        );

        await HttpOverrides.runWithHttpOverrides(() async {
          final client = HttpClient();
          addTearDown(() => client.close(force: true));

          // 1. Oversized POST body -> 413
          final bigReq = await client.post(
            InternetAddress.loopbackIPv4.address,
            session.port,
            '/auth',
          );
          bigReq.followRedirects = false;
          bigReq.add(Uint8List(VideoLinkShareService.maxAuthBodyBytes + 512));
          final bigRes = await bigReq.close();
          await bigRes.drain<void>();
          expect(bigRes.statusCode, HttpStatus.requestEntityTooLarge);

          // 2. Repeated wrong passwords -> lockout 429
          for (var i = 0; i < VideoLinkShareService.maxFailedAuthAttempts; i++) {
            final req = await client.post(
              InternetAddress.loopbackIPv4.address,
              session.port,
              '/auth',
            );
            req.followRedirects = false;
            req.write('password=wrong-$i');
            final res = await req.close();
            await res.drain<void>();
            expect(res.statusCode, HttpStatus.found);
          }
          final lockedReq = await client.post(
            InternetAddress.loopbackIPv4.address,
            session.port,
            '/auth',
          );
          lockedReq.followRedirects = false;
          lockedReq.write('password=correct-password');
          final lockedRes = await lockedReq.close();
          await lockedRes.drain<void>();
          expect(lockedRes.statusCode, HttpStatus.tooManyRequests);
        }, _RealHttpOverrides());
      },
    );

    test(
      'NearbyTransferFilePicker ignores symlinks and TransferCachePreparationPathResolver rejects traversal',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('landa_picker_sec_');
        final secretDir = await Directory.systemTemp.createTemp('landa_secret_');
        addTearDown(() async {
          await tempDir.delete(recursive: true);
          await secretDir.delete(recursive: true);
        });
        final safeFile = File(p.join(tempDir.path, 'safe.txt'));
        await safeFile.writeAsString('safe');
        final secretFile = File(p.join(secretDir.path, 'id_ed25519'));
        await secretFile.writeAsString('PRIVATE KEY');
        await Link(p.join(tempDir.path, 'leak_link')).create(secretFile.path);

        final picker = NearbyTransferFilePicker(
          supportsDirectoryPickingOverride: true,
          pickDirectoryPathInvoker: () async => tempDir.path,
        );
        final selection = await picker.pickDirectory();
        expect(selection, isNotNull);
        expect(selection!.entries.map((e) => e.sourcePath), <String>[safeFile.path]);

        const resolver = TransferCachePreparationPathResolver();
        final escaped = resolver.resolve(
          cache: SharedFolderCacheRecord(
            cacheId: 'c1',
            role: SharedFolderCacheRole.owner,
            ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
            rootPath: tempDir.path,
            displayName: 'Shared',
            indexFilePath: p.join(tempDir.path, 'idx.json'),
            itemCount: 1,
            totalBytes: 4,
            updatedAtMs: 1,
          ),
          entry: SharedFolderIndexEntry(
            relativePath: '../../etc/passwd',
            sizeBytes: 100,
            modifiedAtMs: 1,
          ),
        );
        expect(escaped, isNull);
      },
    );

    test(
      'NearbyTransferQrCodec rejects loopback, link-local, and public internet SSRF hosts',
      () {
        const codec = NearbyTransferQrCodec();
        for (final badHost in <String>[
          '127.0.0.1',
          '169.254.169.254',
          '8.8.8.8',
          'evil.example.com',
          '::1',
        ]) {
          final encoded = codec.encode(
            NearbyTransferQrPayload(
              deviceId: 'dev',
              sessionId: 's1',
              transportMode: NearbyTransferMode.lanFallback,
              transportInfo: <String, Object?>{
                'host': badHost,
                'port': 45321,
                'sessionId': 's1',
              },
            ),
          );
          expect(
            codec.decodeLanFallbackConnection(encoded),
            isNull,
            reason: 'Host $badHost must be rejected in LAN QR payload',
          );
        }

        for (final goodHost in <String>['192.168.1.25', '10.0.0.5', '172.20.1.4', '100.100.10.2']) {
          final encoded = codec.encode(
            NearbyTransferQrPayload(
              deviceId: 'dev',
              sessionId: 's1',
              transportMode: NearbyTransferMode.lanFallback,
              transportInfo: <String, Object?>{
                'host': goodHost,
                'port': 45321,
                'sessionId': 's1',
              },
            ),
          );
          expect(codec.decodeLanFallbackConnection(encoded)?.host, goodHost);
        }
      },
    );

    test(
      'AppUpdateDownloadService rejects insecure non-loopback HTTP asset URLs',
      () async {
        final mockDir = await Directory.systemTemp.createTemp('landa_upd_sec_');
        addTearDown(() => mockDir.delete(recursive: true));
        final service = AppUpdateDownloadService(
          storageService: AppUpdateStorageService(
            updateDirectoryResolver: () async => mockDir,
          ),
        );
        await expectLater(
          service.downloadAsset(
            const AppUpdateAsset(
              platform: 'linux',
              arch: 'x86_64',
              format: 'appimage',
              primary: true,
              fileName: 'landa.AppImage',
              size: 10,
              sha256: 'abcd',
              downloadUrl: 'http://evil.example.com/landa.AppImage',
            ),
          ),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });
}

// =============================================================================
// Helper Mocks for Isolated Adversarial Testing
// =============================================================================

class _RealHttpOverrides extends HttpOverrides {}

class _RecordedClipboardCatalog {
  const _RecordedClipboardCatalog({
    required this.targetIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
  });

  final String targetIp;
  final String ownerName;
  final String ownerMacAddress;
  final List<ClipboardCatalogItem> entries;
}

class _RecordingLanDiscoveryService extends LanDiscoveryService {
  final List<_RecordedClipboardCatalog> catalogs =
      <_RecordedClipboardCatalog>[];

  @override
  Future<void> sendClipboardCatalog({
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
  }) async {
    catalogs.add(
      _RecordedClipboardCatalog(
        targetIp: targetIp,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: entries,
      ),
    );
  }
}

class _FakeClipboardCaptureService extends ClipboardCaptureService {
  @override
  Future<bool> writeTextToClipboard(String text) async => true;

  @override
  Future<bool> writeImageBytesToClipboard(
    Uint8List imageBytes, {
    String suggestedName = 'clipboard-image.png',
  }) async => true;
}
