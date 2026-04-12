import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/application/video_link_session_boundary.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
import 'package:landa/features/history/application/download_history_boundary.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/history/domain/transfer_history_record.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/application/transfer_session_coordinator.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:landa/features/transfer/domain/transfer_request.dart';

import 'test_support/test_app_database.dart';
import 'test_support/stub_discovery_network_interface_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransferSessionCoordinator', () {
    late TestAppDatabaseHarness harness;
    late SharedFolderCacheRepository sharedFolderCacheRepository;
    late ThumbnailCacheService thumbnailCacheService;
    late SharedCacheIndexStore sharedCacheIndexStore;
    late SharedCacheCatalog sharedCacheCatalog;
    late PreviewCacheOwner previewCacheOwner;
    late FileHashService fileHashService;
    late CapturingLanDiscoveryService lanDiscoveryService;
    late TransferHistoryRepository transferHistoryRepository;
    late DownloadHistoryBoundary downloadHistoryBoundary;

    setUp(() async {
      harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_transfer_session_',
      );
      thumbnailCacheService = ThumbnailCacheService(database: harness.database);
      sharedFolderCacheRepository = SharedFolderCacheRepository(
        database: harness.database,
      );
      sharedCacheIndexStore = SharedCacheIndexStore(
        database: harness.database,
        thumbnailCacheService: thumbnailCacheService,
      );
      sharedCacheCatalog = SharedCacheCatalog(
        sharedCacheRecordStore: sharedFolderCacheRepository,
        sharedCacheIndexStore: sharedCacheIndexStore,
      );
      fileHashService = FileHashService();
      previewCacheOwner = PreviewCacheOwner(
        sharedCacheThumbnailStore: thumbnailCacheService,
        sharedCacheIndexStore: sharedCacheIndexStore,
        fileHashService: fileHashService,
        previewArtifactDirectoryProvider: () async {
          final directory = Directory(
            '${harness.rootDirectory.path}${Platform.pathSeparator}preview_artifacts',
          );
          await directory.create(recursive: true);
          return directory;
        },
      );
      lanDiscoveryService = CapturingLanDiscoveryService();
      transferHistoryRepository = TransferHistoryRepository(
        database: harness.database,
      );
      downloadHistoryBoundary = DownloadHistoryBoundary(
        transferHistoryRepository: transferHistoryRepository,
      );
    });

    tearDown(() async {
      previewCacheOwner.dispose();
      sharedCacheCatalog.dispose();
      await harness.dispose();
    });

    test(
      'single-file remote download sends transfer request before hash computation completes',
      () async {
        final ownerFile = File(
          p.join(harness.rootDirectory.path, 'shared', 'archive.7z'),
        );
        await ownerFile.parent.create(recursive: true);
        await ownerFile.writeAsBytes(List<int>.filled(32, 7));
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFile.path],
          displayName: 'Shared archive',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );
        final fileHashService = ControlledFileHashService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-1',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: <String>['archive.7z'],
            selectedFolderPrefixes: const <String>[],
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );

        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        unawaited(
          coordinator.respondToIncomingSharedDownloadRequest(
            requestId: 'download-request-1',
            approved: true,
          ),
        );

        for (var i = 0; i < 40; i += 1) {
          if (lanDiscoveryService.transferRequests.isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(lanDiscoveryService.transferRequests, hasLength(1));
        expect(
          lanDiscoveryService.transferRequests.single.items.single.sha256,
          isEmpty,
        );
        expect(fileHashService.pendingPaths, hasLength(1));

        fileHashService.completeAll(withHash: 'lazy-hash');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
    );

    test(
      'single-file remote download resolves deferred hash before sending approved transfer',
      () async {
        final ownerFile = File(
          p.join(harness.rootDirectory.path, 'shared', 'archive.7z'),
        );
        await ownerFile.parent.create(recursive: true);
        await ownerFile.writeAsBytes(List<int>.filled(32, 9));
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFile.path],
          displayName: 'Shared archive',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );
        final fileHashService = ControlledFileHashService();
        final fileTransferService = CapturingSendFileTransferService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-2',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: <String>['archive.7z'],
            selectedFolderPrefixes: const <String>[],
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        unawaited(
          coordinator.respondToIncomingSharedDownloadRequest(
            requestId: 'download-request-2',
            approved: true,
          ),
        );
        for (var i = 0; i < 40; i += 1) {
          if (lanDiscoveryService.transferRequests.isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(lanDiscoveryService.transferRequests, hasLength(1));

        coordinator.handleTransferDecisionEvent(
          TransferDecisionEvent(
            requestId: lanDiscoveryService.transferRequests.single.requestId,
            approved: true,
            receiverName: 'Remote peer',
            receiverIp: '192.168.1.40',
            transferPort: 40404,
            acceptedFileNames: const <String>['archive.7z'],
            observedAt: DateTime(2026),
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fileTransferService.sendFilesCalls, 0);

        fileHashService.completeAll(withHash: 'lazy-hash-2');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(fileTransferService.sendFilesCalls, 1);
        expect(fileTransferService.lastFiles, hasLength(1));
        expect(fileTransferService.lastFiles.single.sha256, 'lazy-hash-2');
      },
    );

    test(
      'sender direct shared download connects to provided transfer port without transfer request',
      () async {
        final ownerFile = File(
          p.join(harness.rootDirectory.path, 'shared_direct', 'report.txt'),
        );
        await ownerFile.parent.create(recursive: true);
        await ownerFile.writeAsString('hello');
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFile.path],
          displayName: 'Shared docs',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );
        final fileHashService = ControlledFileHashService();
        final fileTransferService = CapturingSendFileTransferService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'direct-download-1',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: <String>['report.txt'],
            selectedFolderPrefixes: const <String>[],
            transferPort: 40404,
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        unawaited(
          coordinator.respondToIncomingSharedDownloadRequest(
            requestId: 'direct-download-1',
            approved: true,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fileTransferService.sendFilesCalls, 1);
        expect(fileTransferService.lastFiles.single.fileName, 'report.txt');
        expect(fileTransferService.lastFiles.single.sha256, isEmpty);
        expect(fileHashService.pendingPaths, isEmpty);
        expect(lanDiscoveryService.transferRequests, isEmpty);
      },
    );

    test(
      'incoming shared download request waits for sender approval and exposes request summary',
      () async {
        final ownerFile = File(
          p.join(
            harness.rootDirectory.path,
            'shared_sender_ui',
            'docs',
            'a.txt',
          ),
        );
        await ownerFile.parent.create(recursive: true);
        await ownerFile.writeAsString('hello');
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFile.path],
          displayName: 'Shared docs',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'sender-approval-1',
            requesterIp: '192.168.1.55',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>['a.txt'],
            selectedFolderPrefixes: const <String>[],
            transferPort: 40404,
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        final request = coordinator.incomingSharedDownloadRequests.single;
        expect(request.requesterName, 'Remote peer');
        expect(request.sharedLabel, 'Shared docs');
        expect(request.selectedRelativePaths, <String>['a.txt']);
        expect(lanDiscoveryService.transferRequests, isEmpty);
      },
    );

    test(
      'rejecting incoming shared download request prevents transfer start and notifies requester',
      () async {
        final ownerFile = File(
          p.join(harness.rootDirectory.path, 'shared_sender_reject', 'a.txt'),
        );
        await ownerFile.parent.create(recursive: true);
        await ownerFile.writeAsString('hello');
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFile.path],
          displayName: 'Shared docs',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'sender-reject-1',
            requesterIp: '192.168.1.55',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>['a.txt'],
            selectedFolderPrefixes: const <String>[],
            transferPort: 40404,
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'sender-reject-1',
          approved: false,
        );

        expect(coordinator.incomingSharedDownloadRequests, isEmpty);
        expect(lanDiscoveryService.downloadResponses, hasLength(1));
        expect(lanDiscoveryService.downloadResponses.single.approved, isFalse);
        expect(lanDiscoveryService.transferRequests, isEmpty);
      },
    );

    test(
      'approving incoming shared download request exposes sender preparation state before sending',
      () async {
        final ownerFile = File(
          p.join(harness.rootDirectory.path, 'shared_sender_prepare', 'a.txt'),
        );
        await ownerFile.parent.create(recursive: true);
        await ownerFile.writeAsString('hello');
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFile.path],
          displayName: 'Shared docs',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );
        final fileHashService = ControlledFileHashService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'sender-approve-1',
            requesterIp: '192.168.1.55',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>[],
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );

        final approveFuture = coordinator
            .respondToIncomingSharedDownloadRequest(
              requestId: 'sender-approve-1',
              approved: true,
            );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          coordinator.sharedUploadPreparationState?.stage,
          SharedUploadPreparationStage.resolvingSelection,
        );
        expect(lanDiscoveryService.transferRequests, isEmpty);

        fileHashService.completeAll(withHash: 'sender-hash');
        for (var i = 0; i < 40; i += 1) {
          if (lanDiscoveryService.transferRequests.isNotEmpty) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        expect(
          coordinator.sharedUploadPreparationState?.stage,
          SharedUploadPreparationStage.waitingForRequester,
        );
        expect(lanDiscoveryService.transferRequests, hasLength(1));
        await approveFuture;
      },
    );

    test(
      'repeated shared download preparation reuses cached manifest hashes when files are unchanged',
      () async {
        final ownerFileA = File(
          p.join(harness.rootDirectory.path, 'shared_cached', 'a.txt'),
        );
        final ownerFileB = File(
          p.join(harness.rootDirectory.path, 'shared_cached', 'b.txt'),
        );
        await ownerFileA.parent.create(recursive: true);
        await ownerFileA.writeAsString('alpha');
        await ownerFileB.writeAsString('beta');
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFileA.path, ownerFileB.path],
          displayName: 'Shared docs',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );
        final fileHashService = CountingFileHashService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-cache-1',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>[],
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-cache-1',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fileHashService.computeCalls, 2);
        final cachedEntries = await sharedCacheIndexStore.readIndexEntries(
          cache,
        );
        expect(
          cachedEntries.where((entry) => (entry.sha256 ?? '').isNotEmpty),
          hasLength(2),
        );

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-cache-2',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>[],
            previewMode: false,
            observedAt: DateTime(2026, 1, 2),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-cache-2',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fileHashService.computeCalls, 2);
        expect(coordinator.preparedTransferScopeCacheHits, 1);
        expect(coordinator.preparedTransferScopeCacheEntryCount, 1);
      },
    );

    test(
      'whole-root shared download reuses prepared scope when fingerprint is unchanged',
      () async {
        final ownerRoot = Directory(
          p.join(harness.rootDirectory.path, 'shared_fingerprint_root'),
        );
        await Directory(
          p.join(ownerRoot.path, 'docs', 'sub'),
        ).create(recursive: true);
        await File(p.join(ownerRoot.path, 'docs', 'a.txt')).writeAsString('a');
        await File(
          p.join(ownerRoot.path, 'docs', 'sub', 'b.txt'),
        ).writeAsString('b');
        final cacheResult = await sharedCacheCatalog.upsertOwnerFolderCache(
          ownerMacAddress: '02:00:00:00:00:01',
          folderPath: ownerRoot.path,
          displayName: 'Docs',
        );
        final cache = cacheResult.record;
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );

        final fileHashService = CountingFileHashService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-root-1',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>[],
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-root-1',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fileHashService.computeCalls, 2);
        expect(coordinator.preparedTransferScopeCacheHits, 0);
        expect(coordinator.preparedTransferScopeCacheEntryCount, 1);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-root-2',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>[],
            previewMode: false,
            observedAt: DateTime(2026, 1, 2),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-root-2',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fileHashService.computeCalls, 2);
        expect(coordinator.preparedTransferScopeCacheHits, 1);
        expect(coordinator.preparedTransferScopeCacheEntryCount, 1);
      },
    );

    test(
      'nested folder shared download reuses prepared scope until fingerprint changes',
      () async {
        final ownerRoot = Directory(
          p.join(harness.rootDirectory.path, 'shared_fingerprint_nested'),
        );
        await Directory(
          p.join(ownerRoot.path, 'docs', 'sub'),
        ).create(recursive: true);
        await File(p.join(ownerRoot.path, 'docs', 'a.txt')).writeAsString('a');
        await File(
          p.join(ownerRoot.path, 'docs', 'sub', 'b.txt'),
        ).writeAsString('b');
        await File(p.join(ownerRoot.path, 'top.txt')).writeAsString('top');
        var cache = (await sharedCacheCatalog.upsertOwnerFolderCache(
          ownerMacAddress: '02:00:00:00:00:01',
          folderPath: ownerRoot.path,
          displayName: 'Docs',
        )).record;
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );

        final fileHashService = CountingFileHashService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-prefix-1',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>['docs'],
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-prefix-1',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fileHashService.computeCalls, 2);
        expect(coordinator.preparedTransferScopeCacheHits, 0);
        expect(coordinator.preparedTransferScopeCacheEntryCount, 1);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-prefix-2',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>['docs'],
            previewMode: false,
            observedAt: DateTime(2026, 1, 2),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-prefix-2',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fileHashService.computeCalls, 2);
        expect(coordinator.preparedTransferScopeCacheHits, 1);
        expect(coordinator.preparedTransferScopeCacheEntryCount, 1);

        await File(p.join(ownerRoot.path, 'docs', 'c.txt')).writeAsString('c');
        cache = await sharedCacheCatalog.refreshOwnerFolderSubdirectoryEntries(
          cache,
          relativeFolderPath: 'docs',
        );
        final changedFingerprint = await sharedCacheIndexStore
            .readTreeFingerprint(cache, relativeFolderPath: 'docs');

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-prefix-3',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>['docs'],
            previewMode: false,
            observedAt: DateTime(2026, 1, 3),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-prefix-3',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(changedFingerprint.itemCount, 3);
        expect(fileHashService.computeCalls, greaterThan(2));
        expect(coordinator.preparedTransferScopeCacheHits, 1);
        expect(coordinator.preparedTransferScopeCacheEntryCount, 2);
      },
    );

    test(
      'approving mixed-case nested folder shared download prepares sender transfer files successfully',
      () async {
        final ownerRoot = Directory(
          p.join(harness.rootDirectory.path, 'shared_mixed_case_folder'),
        );
        await Directory(
          p.join(ownerRoot.path, 'ReactProjects', 'AppOne', 'src'),
        ).create(recursive: true);
        await Directory(
          p.join(ownerRoot.path, 'ReactProjects', 'AppTwo', 'src'),
        ).create(recursive: true);
        for (var index = 0; index < 80; index += 1) {
          await File(
            p.join(
              ownerRoot.path,
              'ReactProjects',
              'AppOne',
              'src',
              'file_$index.txt',
            ),
          ).writeAsString('app-one-$index');
          await File(
            p.join(
              ownerRoot.path,
              'ReactProjects',
              'AppTwo',
              'src',
              'file_$index.txt',
            ),
          ).writeAsString('app-two-$index');
        }

        final cache = (await sharedCacheCatalog.upsertOwnerFolderCache(
          ownerMacAddress: '02:00:00:00:00:01',
          folderPath: ownerRoot.path,
          displayName: 'Workspace',
        )).record;
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );

        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-mixed-case-folder',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>['ReactProjects'],
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));

        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-mixed-case-folder',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(lanDiscoveryService.downloadResponses, isEmpty);
        expect(lanDiscoveryService.transferRequests, hasLength(1));
        expect(lanDiscoveryService.transferRequests.single.items, isNotEmpty);
        expect(
          lanDiscoveryService.transferRequests.single.items.every(
            (item) => item.fileName.startsWith('ReactProjects/'),
          ),
          isTrue,
        );
        expect(coordinator.takePendingNotice()?.errorMessage, isNull);
      },
    );

    test(
      'preview requests stay outside prepared transfer scope reuse cache',
      () async {
        final ownerFile = File(
          p.join(harness.rootDirectory.path, 'shared_preview_scope', 'a.txt'),
        );
        await ownerFile.parent.create(recursive: true);
        await ownerFile.writeAsString('alpha');
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFile.path],
          displayName: 'Shared docs',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );

        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'preview-request-1',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>['a.txt'],
            selectedFolderPrefixes: const <String>[],
            previewMode: true,
            observedAt: DateTime(2026),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(coordinator.incomingSharedDownloadRequests, isEmpty);
        expect(coordinator.preparedTransferScopeCacheHits, 0);
        expect(coordinator.preparedTransferScopeCacheEntryCount, 0);
      },
    );

    test(
      'shared download preparation recomputes cached hash when indexed file metadata changed',
      () async {
        final ownerFile = File(
          p.join(harness.rootDirectory.path, 'shared_changed', 'a.txt'),
        );
        await ownerFile.parent.create(recursive: true);
        await ownerFile.writeAsString('alpha');
        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[ownerFile.path],
          displayName: 'Shared docs',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );
        await sharedCacheIndexStore.persistCachedManifestEntries(
          record: cache,
          entries: <SharedFolderIndexEntry>[
            SharedFolderIndexEntry(
              relativePath: 'a.txt',
              sizeBytes: ownerFile.lengthSync(),
              modifiedAtMs: ownerFile
                  .statSync()
                  .modified
                  .millisecondsSinceEpoch,
              absolutePath: ownerFile.path,
              sha256: 'stale-hash',
            ),
          ],
        );

        await ownerFile.writeAsString('changed-content', flush: true);
        final updatedModifiedAt = DateTime.now().add(
          const Duration(seconds: 1),
        );
        await ownerFile.setLastModified(updatedModifiedAt);

        final fileHashService = CountingFileHashService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleDownloadRequestEvent(
          DownloadRequestEvent(
            requestId: 'download-request-changed',
            requesterIp: '192.168.1.40',
            requesterName: 'Remote peer',
            requesterMacAddress: '11:22:33:44:55:66',
            cacheId: cache.cacheId,
            selectedRelativePaths: const <String>[],
            selectedFolderPrefixes: const <String>[],
            previewMode: false,
            observedAt: DateTime(2026),
          ),
        );
        expect(coordinator.incomingSharedDownloadRequests, hasLength(1));
        await coordinator.respondToIncomingSharedDownloadRequest(
          requestId: 'download-request-changed',
          approved: true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(fileHashService.computeCalls, 1);
        final updatedEntries = await sharedCacheIndexStore.readIndexEntries(
          cache,
        );
        expect(updatedEntries.single.sha256, isNot('stale-hash'));
      },
    );

    test(
      'protocol transfer request updates incoming session truth in coordinator',
      () {
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: 'transfer-1',
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
          ),
        );

        final notice = coordinator.takePendingNotice();
        expect(coordinator.incomingRequests, hasLength(1));
        expect(coordinator.incomingRequests.single.requestId, 'transfer-1');
        expect(
          notice?.infoMessage,
          'Incoming transfer request from Remote peer.',
        );
        expect(notice?.clearError, isTrue);
      },
    );

    test(
      'approved incoming transfer is coordinated without controller-owned session truth',
      () async {
        final fileTransferService = SuccessfulReceiveFileTransferService(
          resultBuilder: (destinationDirectory) => FileTransferResult(
            success: true,
            message: 'ok',
            savedPaths: <String>[
              '${destinationDirectory.path}${Platform.pathSeparator}report.txt',
            ],
            receivedItems: const <TransferFileManifestItem>[
              TransferFileManifestItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
            totalBytes: 12,
            destinationDirectory: destinationDirectory.path,
            hashVerified: true,
          ),
        );
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: 'transfer-2',
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
          ),
        );

        await coordinator.respondToTransferRequest(
          requestId: 'transfer-2',
          approved: true,
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        final receiverCaches = await sharedFolderCacheRepository.listCaches(
          role: SharedFolderCacheRole.receiver,
          ownerMacAddress: '11:22:33:44:55:66',
          peerMacAddress: '02:00:00:00:00:01',
        );
        final history = downloadHistoryBoundary.records;

        expect(coordinator.incomingRequests, isEmpty);
        expect(lanDiscoveryService.transferDecisions, hasLength(1));
        expect(lanDiscoveryService.transferDecisions.single.approved, isTrue);
        expect(receiverCaches, hasLength(1));
        expect(history, hasLength(1));
        expect(history.single.direction, TransferHistoryDirection.download);
        expect(fileTransferService.startReceiverCalls, 1);
      },
    );

    test(
      'remote-share download uses standard desktop root when standard folder setting is enabled',
      () async {
        final fileTransferService = SuccessfulReceiveFileTransferService(
          resultBuilder: (destinationDirectory) => FileTransferResult(
            success: true,
            message: 'ok',
            savedPaths: <String>[
              '${destinationDirectory.path}${Platform.pathSeparator}report.txt',
            ],
            receivedItems: const <TransferFileManifestItem>[
              TransferFileManifestItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
            totalBytes: 12,
            destinationDirectory: destinationDirectory.path,
            hashVerified: true,
          ),
        );
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{'report.txt'},
          },
          selectedFolderPrefixesByCache: const <String, Set<String>>{},
          useStandardAppDownloadFolder: true,
        );

        expect(transferStorageService.resolveReceiveCalls, 1);
        expect(transferStorageService.pickDesktopDownloadDirectoryCalls, 0);
        expect(lanDiscoveryService.downloadRequests, hasLength(1));

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: lanDiscoveryService.downloadRequests.single.requestId,
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
          ),
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        final history = downloadHistoryBoundary.records;
        expect(fileTransferService.startReceiverCalls, 1);
        expect(
          fileTransferService.lastDestinationDirectoryPath,
          transferStorageService.standardReceiveDirectory.path,
        );
        expect(history, hasLength(1));
        expect(
          history.single.rootPath,
          transferStorageService.standardReceiveDirectory.path,
        );
      },
    );

    test(
      'direct shared download start includes transfer port and skips transfer-request round-trip',
      () async {
        final fileTransferService = SuccessfulReceiveFileTransferService(
          resultBuilder: (destinationDirectory) => FileTransferResult(
            success: true,
            message: 'ok',
            savedPaths: <String>[
              '${destinationDirectory.path}${Platform.pathSeparator}report.txt',
            ],
            receivedItems: const <TransferFileManifestItem>[
              TransferFileManifestItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
            totalBytes: 12,
            destinationDirectory: destinationDirectory.path,
            hashVerified: true,
          ),
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{'report.txt'},
          },
          preferDirectStart: true,
          useStandardAppDownloadFolder: true,
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        expect(lanDiscoveryService.downloadRequests, hasLength(1));
        expect(lanDiscoveryService.downloadRequests.single.transferPort, 40404);
        expect(lanDiscoveryService.transferRequests, isEmpty);
        expect(lanDiscoveryService.transferDecisions, isEmpty);
        expect(fileTransferService.startReceiverCalls, 1);
      },
    );

    test(
      'shared download exposes waiting preparation state before transfer bytes arrive',
      () async {
        final fileTransferService = PendingReceiveFileTransferService(
          port: 40404,
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{'report.txt'},
          },
          preferDirectStart: true,
          useStandardAppDownloadFolder: true,
        );

        expect(coordinator.isPreparingSharedDownload, isTrue);
        expect(
          coordinator.sharedDownloadPreparationState?.stage,
          SharedDownloadPreparationStage.waitingForRemote,
        );
        expect(
          coordinator.sharedDownloadPreparationState?.message,
          'Ждём, пока Remote peer начнёт передачу...',
        );
      },
    );

    test(
      'remote-share download uses picked desktop directory when standard folder setting is disabled',
      () async {
        final customRoot = Directory(
          '${harness.rootDirectory.path}${Platform.pathSeparator}custom_desktop_root',
        );
        final fileTransferService = SuccessfulReceiveFileTransferService(
          resultBuilder: (destinationDirectory) => FileTransferResult(
            success: true,
            message: 'ok',
            savedPaths: <String>[
              '${destinationDirectory.path}${Platform.pathSeparator}report.txt',
            ],
            receivedItems: const <TransferFileManifestItem>[
              TransferFileManifestItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
            totalBytes: 12,
            destinationDirectory: destinationDirectory.path,
            hashVerified: true,
          ),
        );
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
          pickedDesktopDownloadDirectory: customRoot,
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{'report.txt'},
          },
          selectedFolderPrefixesByCache: const <String, Set<String>>{},
          useStandardAppDownloadFolder: false,
        );

        expect(transferStorageService.resolveReceiveCalls, 0);
        expect(transferStorageService.pickDesktopDownloadDirectoryCalls, 1);
        expect(lanDiscoveryService.downloadRequests, hasLength(1));

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: lanDiscoveryService.downloadRequests.single.requestId,
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
          ),
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        final history = downloadHistoryBoundary.records;
        expect(fileTransferService.startReceiverCalls, 1);
        expect(
          fileTransferService.lastDestinationDirectoryPath,
          customRoot.path,
        );
        expect(history, hasLength(1));
        expect(history.single.rootPath, customRoot.path);
      },
    );

    test(
      'canceling desktop directory picker aborts remote-share download without side effects',
      () async {
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
          pickedDesktopDownloadDirectory: null,
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{'report.txt'},
          },
          selectedFolderPrefixesByCache: const <String, Set<String>>{},
          useStandardAppDownloadFolder: false,
        );

        expect(transferStorageService.pickDesktopDownloadDirectoryCalls, 1);
        expect(lanDiscoveryService.downloadRequests, isEmpty);
        expect(downloadHistoryBoundary.records, isEmpty);
        expect(coordinator.takePendingNotice(), isNull);
      },
    );

    test(
      'unsupported picker platforms keep remote-share downloads on the default path flow',
      () async {
        final fileTransferService = SuccessfulReceiveFileTransferService(
          resultBuilder: (destinationDirectory) => FileTransferResult(
            success: true,
            message: 'ok',
            savedPaths: <String>[
              '${destinationDirectory.path}${Platform.pathSeparator}report.txt',
            ],
            receivedItems: const <TransferFileManifestItem>[
              TransferFileManifestItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
            totalBytes: 12,
            destinationDirectory: destinationDirectory.path,
            hashVerified: true,
          ),
        );
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
          supportsDesktopDownloadPicker: false,
          publishesReceivedDownloadsToUserDownloads: true,
          publishedDownloadPaths: <String>[
            '${harness.rootDirectory.path}${Platform.pathSeparator}Downloads${Platform.pathSeparator}Landa${Platform.pathSeparator}report.txt',
          ],
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{'report.txt'},
          },
          selectedFolderPrefixesByCache: const <String, Set<String>>{},
          useStandardAppDownloadFolder: false,
        );

        expect(transferStorageService.resolveReceiveCalls, 1);
        expect(transferStorageService.pickDesktopDownloadDirectoryCalls, 0);
        expect(lanDiscoveryService.downloadRequests, hasLength(1));

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: lanDiscoveryService.downloadRequests.single.requestId,
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
          ),
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        final history = downloadHistoryBoundary.records;
        expect(transferStorageService.publishToUserDownloadsCalls, 1);
        expect(history, hasLength(1));
        expect(
          history.single.rootPath,
          Directory(
            transferStorageService.publishedDownloadPaths!.single,
          ).parent.path,
        );
      },
    );

    test(
      'single file-only remote download preserves its relative path by default',
      () async {
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
        );
        final fileTransferService = AllocatingReceiveFileTransferService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{'docs/sub/report.txt'},
          },
          useStandardAppDownloadFolder: true,
        );

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: lanDiscoveryService.downloadRequests.single.requestId,
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'docs/sub/report.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
            ],
          ),
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        final history = downloadHistoryBoundary.records.single;
        expect(fileTransferService.lastDestinationRelativeRootPrefix, isNull);
        expect(
          history.rootPath,
          transferStorageService.standardReceiveDirectory.path,
        );
        expect(
          history.savedPaths.map(p.normalize).toList(growable: false),
          <String>[
            p.join(
              transferStorageService.standardReceiveDirectory.path,
              'docs',
              'sub',
              'report.txt',
            ),
          ].map(p.normalize).toList(growable: false),
        );
      },
    );

    test(
      'multi-file file-only remote downloads preserve relative paths by default and keep custom desktop root as history root',
      () async {
        final customRoot = Directory(
          '${harness.rootDirectory.path}${Platform.pathSeparator}picked_root',
        );
        final fileTransferService = SuccessfulReceiveFileTransferService(
          resultBuilder: (destinationDirectory) => FileTransferResult(
            success: true,
            message: 'ok',
            savedPaths: <String>[
              '${destinationDirectory.path}${Platform.pathSeparator}docs${Platform.pathSeparator}a.txt',
              '${destinationDirectory.path}${Platform.pathSeparator}docs${Platform.pathSeparator}sub${Platform.pathSeparator}b.txt',
            ],
            receivedItems: const <TransferFileManifestItem>[
              TransferFileManifestItem(
                fileName: 'docs/a.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
              TransferFileManifestItem(
                fileName: 'docs/sub/b.txt',
                sizeBytes: 12,
                sha256: 'def456',
              ),
            ],
            totalBytes: 24,
            destinationDirectory: destinationDirectory.path,
            hashVerified: true,
          ),
        );
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
          pickedDesktopDownloadDirectory: customRoot,
        );
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{'docs/a.txt', 'docs/sub/b.txt'},
          },
          useStandardAppDownloadFolder: false,
        );

        expect(lanDiscoveryService.downloadRequests, hasLength(1));
        expect(
          lanDiscoveryService.downloadRequests.single.selectedRelativePaths,
          containsAll(<String>['docs/a.txt', 'docs/sub/b.txt']),
        );

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: lanDiscoveryService.downloadRequests.single.requestId,
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'docs/a.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
              TransferAnnouncementItem(
                fileName: 'docs/sub/b.txt',
                sizeBytes: 12,
                sha256: 'def456',
              ),
            ],
          ),
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        final history = downloadHistoryBoundary.records;
        expect(
          fileTransferService.lastDestinationDirectoryPath,
          customRoot.path,
        );
        expect(history, hasLength(1));
        expect(history.single.rootPath, customRoot.path);
        expect(
          history.single.savedPaths,
          containsAll(<String>[
            '${customRoot.path}${Platform.pathSeparator}docs${Platform.pathSeparator}a.txt',
            '${customRoot.path}${Platform.pathSeparator}docs${Platform.pathSeparator}sub${Platform.pathSeparator}b.txt',
          ]),
        );
      },
    );

    test(
      'nested folder downloads send folder prefixes instead of expanding massive path lists',
      () async {
        final ownerRoot = Directory(
          p.join(harness.rootDirectory.path, 'shared_large'),
        );
        await Directory(
          p.join(ownerRoot.path, 'docs', 'sub'),
        ).create(recursive: true);
        await File(p.join(ownerRoot.path, 'docs', 'a.txt')).writeAsString('a');
        await File(
          p.join(ownerRoot.path, 'docs', 'sub', 'b.txt'),
        ).writeAsString('b');
        await File(p.join(ownerRoot.path, 'top.txt')).writeAsString('top');

        final cache = await sharedCacheCatalog.buildOwnerSelectionCache(
          ownerMacAddress: '02:00:00:00:00:01',
          filePaths: <String>[
            p.join(ownerRoot.path, 'docs', 'a.txt'),
            p.join(ownerRoot.path, 'docs', 'sub', 'b.txt'),
            p.join(ownerRoot.path, 'top.txt'),
          ],
          displayName: 'Docs',
        );
        await sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: '02:00:00:00:00:01',
        );

        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: const <String, Set<String>>{},
          selectedFolderPrefixesByCache: <String, Set<String>>{
            cache.cacheId: <String>{'docs'},
          },
          useStandardAppDownloadFolder: true,
        );

        expect(lanDiscoveryService.downloadRequests, hasLength(1));
        expect(
          lanDiscoveryService.downloadRequests.single.selectedRelativePaths,
          isEmpty,
        );
        expect(
          lanDiscoveryService.downloadRequests.single.selectedFolderPrefixes,
          <String>['docs'],
        );
      },
    );

    test(
      'whole-cache remote download preserves the shared root folder on receive and in history',
      () async {
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
        );
        final fileTransferService = AllocatingReceiveFileTransferService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{},
          },
          useStandardAppDownloadFolder: true,
        );

        expect(lanDiscoveryService.downloadRequests, hasLength(1));
        expect(
          lanDiscoveryService.downloadRequests.single.selectedRelativePaths,
          isEmpty,
        );

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: lanDiscoveryService.downloadRequests.single.requestId,
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'a.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
              TransferAnnouncementItem(
                fileName: 'sub/b.txt',
                sizeBytes: 24,
                sha256: 'def456',
              ),
            ],
          ),
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        final history = downloadHistoryBoundary.records.single;
        final expectedRoot = p.join(
          transferStorageService.standardReceiveDirectory.path,
          'Docs',
        );
        expect(fileTransferService.startReceiverCalls, 1);
        expect(fileTransferService.lastDestinationRelativeRootPrefix, 'Docs');
        expect(history.rootPath, expectedRoot);
        expect(
          history.savedPaths,
          containsAll(<String>[
            p.join(expectedRoot, 'a.txt'),
            p.join(expectedRoot, 'sub', 'b.txt'),
          ]),
        );
      },
    );

    test(
      'published whole-cache folder downloads keep the shared root as history root',
      () async {
        final transferStorageService = RecordingTransferStorageService(
          rootDirectory: harness.rootDirectory,
          supportsDesktopDownloadPicker: false,
          publishesReceivedDownloadsToUserDownloads: true,
          publishedDownloadPaths: <String>[
            p.join(
              harness.rootDirectory.path,
              'Downloads',
              'Landa',
              'Docs',
              'a.txt',
            ),
            p.join(
              harness.rootDirectory.path,
              'Downloads',
              'Landa',
              'Docs',
              'sub',
              'b.txt',
            ),
          ],
        );
        final fileTransferService = AllocatingReceiveFileTransferService();
        final coordinator = _buildCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          previewCacheOwner: previewCacheOwner,
          downloadHistoryBoundary: downloadHistoryBoundary,
          rootDirectory: harness.rootDirectory,
        );
        addTearDown(coordinator.dispose);

        await coordinator.requestDownloadFromRemoteFiles(
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          selectedRelativePathsByCache: <String, Set<String>>{
            'remote-cache': <String>{},
          },
          useStandardAppDownloadFolder: false,
        );

        coordinator.handleTransferRequestEvent(
          TransferRequestEvent(
            requestId: lanDiscoveryService.downloadRequests.single.requestId,
            senderIp: '192.168.1.40',
            senderName: 'Remote peer',
            senderMacAddress: '11:22:33:44:55:66',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'a.txt',
                sizeBytes: 12,
                sha256: 'abc123',
              ),
              TransferAnnouncementItem(
                fileName: 'sub/b.txt',
                sizeBytes: 24,
                sha256: 'def456',
              ),
            ],
          ),
        );
        await _waitForDownloadHistoryRecords(
          boundary: downloadHistoryBoundary,
          expectedCount: 1,
        );

        final history = downloadHistoryBoundary.records.single;
        expect(
          history.rootPath,
          p.join(harness.rootDirectory.path, 'Downloads', 'Landa', 'Docs'),
        );
        expect(
          history.savedPaths,
          containsAll(transferStorageService.publishedDownloadPaths!),
        );
      },
    );
  });

  test(
    'DiscoveryController routes transfer protocol callbacks through TransferSessionCoordinator',
    () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_transfer_controller_',
      );
      final database = harness.database;
      final deviceAliasRepository = DeviceAliasRepository(database: database);
      final deviceRegistry = DeviceRegistry(
        deviceAliasRepository: deviceAliasRepository,
      );
      final friendRepository = FriendRepository(database: database);
      final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
      final settingsStore = SettingsStore(
        appSettingsRepository: AppSettingsRepository(database: database),
      );
      final trustedLanPeerStore = TrustedLanPeerStore(
        deviceRegistry: deviceRegistry,
        deviceAliasRepository: deviceAliasRepository,
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
      final previewCacheOwner = PreviewCacheOwner(
        sharedCacheThumbnailStore: thumbnailCacheService,
        sharedCacheIndexStore: sharedCacheIndexStore,
        fileHashService: fileHashService,
      );
      final lanDiscoveryService = CapturingLanDiscoveryService();
      final transferHistoryRepository = TransferHistoryRepository(
        database: database,
      );
      final downloadHistoryBoundary = DownloadHistoryBoundary(
        transferHistoryRepository: transferHistoryRepository,
      );
      final remoteShareBrowser = RemoteShareBrowser(
        sharedCacheCatalog: sharedCacheCatalog,
      );
      final videoLinkShareService = VideoLinkShareService();
      late final DiscoveryController controller;
      final transferSessionCoordinator = TransferSessionCoordinator(
        lanDiscoveryService: lanDiscoveryService,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: sharedCacheIndexStore,
        fileHashService: fileHashService,
        fileTransferService: FileTransferService(),
        transferStorageService: TransferStorageService(),
        downloadHistoryBoundary: downloadHistoryBoundary,
        previewCacheOwner: previewCacheOwner,
        appNotificationService: AppNotificationService.instance,
        settingsProvider: () => settingsStore.settings,
        localNameProvider: () => controller.localName,
        localDeviceMacProvider: () => controller.localDeviceMac,
        isTrustedSender: (normalizedMac) =>
            trustedLanPeerStore.isTrustedMac(normalizedMac),
        resolveRemoteOwnerMac:
            ({required String ownerIp, required String cacheId}) =>
                remoteShareBrowser.ownerMacForCache(
                  ownerIp: ownerIp,
                  cacheId: cacheId,
                ),
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
      final discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore();
      controller = DiscoveryController(
        lanDiscoveryService: lanDiscoveryService,
        networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
        deviceRegistry: deviceRegistry,
        internetPeerEndpointStore: InternetPeerEndpointStore(
          friendRepository: friendRepository,
        ),
        trustedLanPeerStore: trustedLanPeerStore,
        localPeerIdentityStore: localPeerIdentityStore,
        discoveryNetworkScopeStore: discoveryNetworkScopeStore,
        settingsStore: settingsStore,
        appNotificationService: AppNotificationService.instance,
        transferHistoryRepository: transferHistoryRepository,
        downloadHistoryBoundary: downloadHistoryBoundary,
        clipboardHistoryRepository: ClipboardHistoryRepository(
          database: database,
        ),
        clipboardCaptureService: ClipboardCaptureService(),
        remoteShareBrowser: remoteShareBrowser,
        remoteShareMediaProjectionBoundary: remoteShareMediaProjectionBoundary,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: sharedCacheIndexStore,
        fileHashService: fileHashService,
        fileTransferService: FileTransferService(),
        transferStorageService: TransferStorageService(),
        previewCacheOwner: previewCacheOwner,
        pathOpener: PathOpener(),
        transferSessionCoordinator: transferSessionCoordinator,
      );
      final videoLinkSessionBoundary = VideoLinkSessionBoundary(
        videoLinkShareService: videoLinkShareService,
        hostAddressProvider: () => controller.localIp,
        hostChangeListenable: controller,
      );

      try {
        await controller.start();

        expect(lanDiscoveryService.onTransferRequest, isNotNull);
        expect(lanDiscoveryService.onTransferDecision, isNotNull);
        expect(lanDiscoveryService.onDownloadRequest, isNotNull);

        lanDiscoveryService.onTransferRequest!(
          TransferRequestEvent(
            requestId: 'transfer-3',
            senderIp: '192.168.1.50',
            senderName: 'LAN peer',
            senderMacAddress: '22:33:44:55:66:77',
            sharedCacheId: 'remote-cache',
            sharedLabel: 'Shared docs',
            observedAt: DateTime(2026),
            items: <TransferAnnouncementItem>[
              TransferAnnouncementItem(
                fileName: 'notes.txt',
                sizeBytes: 7,
                sha256: 'def456',
              ),
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(transferSessionCoordinator.incomingRequests, hasLength(1));
        expect(
          transferSessionCoordinator.incomingRequests.single.requestId,
          'transfer-3',
        );
        expect(
          controller.infoMessage,
          'Incoming transfer request from LAN peer.',
        );
        expect(videoLinkSessionBoundary.activeSession, isNull);
      } finally {
        videoLinkSessionBoundary.dispose();
        controller.dispose();
        remoteShareBrowser.dispose();
        previewCacheOwner.dispose();
        sharedCacheCatalog.dispose();
        await harness.dispose();
      }
    },
  );
}

TransferSessionCoordinator _buildCoordinator({
  required CapturingLanDiscoveryService lanDiscoveryService,
  required SharedCacheCatalog sharedCacheCatalog,
  required SharedCacheIndexStore sharedCacheIndexStore,
  required FileHashService fileHashService,
  required PreviewCacheOwner previewCacheOwner,
  required DownloadHistoryBoundary downloadHistoryBoundary,
  required Directory rootDirectory,
  FileTransferService? fileTransferService,
  TransferStorageService? transferStorageService,
}) {
  return TransferSessionCoordinator(
    lanDiscoveryService: lanDiscoveryService,
    sharedCacheCatalog: sharedCacheCatalog,
    sharedCacheIndexStore: sharedCacheIndexStore,
    fileHashService: fileHashService,
    fileTransferService: fileTransferService ?? FileTransferService(),
    transferStorageService:
        transferStorageService ??
        RecordingTransferStorageService(rootDirectory: rootDirectory),
    downloadHistoryBoundary: downloadHistoryBoundary,
    previewCacheOwner: previewCacheOwner,
    appNotificationService: AppNotificationService.instance,
    settingsProvider: () => AppSettings.defaults,
    localNameProvider: () => 'Local device',
    localDeviceMacProvider: () => '02:00:00:00:00:01',
    isTrustedSender: (_) => false,
    resolveRemoteOwnerMac:
        ({required String ownerIp, required String cacheId}) {
          return null;
        },
  );
}

Future<void> _waitForDownloadHistoryRecords({
  required DownloadHistoryBoundary boundary,
  required int expectedCount,
}) async {
  for (var i = 0; i < 20; i += 1) {
    if (boundary.records.length >= expectedCount) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class CapturingLanDiscoveryService extends LanDiscoveryService {
  final List<SentTransferRequest> transferRequests = <SentTransferRequest>[];
  final List<SentTransferDecision> transferDecisions = <SentTransferDecision>[];
  final List<SentDownloadRequest> downloadRequests = <SentDownloadRequest>[];
  final List<SentDownloadResponse> downloadResponses = <SentDownloadResponse>[];
  void Function(TransferRequestEvent event)? onTransferRequest;
  void Function(TransferDecisionEvent event)? onTransferDecision;
  void Function(DownloadRequestEvent event)? onDownloadRequest;
  void Function(DownloadResponseEvent event)? onDownloadResponse;

  @override
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
    void Function(ShareCatalogEvent event)? onShareCatalog,
    void Function(DownloadRequestEvent event)? onDownloadRequest,
    void Function(DownloadResponseEvent event)? onDownloadResponse,
    void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest,
    void Function(ThumbnailPacketEvent event)? onThumbnailPacket,
    void Function(ClipboardQueryEvent event)? onClipboardQuery,
    void Function(ClipboardCatalogEvent event)? onClipboardCatalog,
  }) async {
    this.onTransferRequest = onTransferRequest;
    this.onTransferDecision = onTransferDecision;
    this.onDownloadRequest = onDownloadRequest;
    this.onDownloadResponse = onDownloadResponse;
  }

  @override
  Future<void> sendTransferDecision({
    required String targetIp,
    required String requestId,
    required bool approved,
    required String receiverName,
    int? transferPort,
    List<String>? acceptedFileNames,
  }) async {
    transferDecisions.add(
      SentTransferDecision(
        targetIp: targetIp,
        requestId: requestId,
        approved: approved,
        receiverName: receiverName,
        transferPort: transferPort,
        acceptedFileNames: acceptedFileNames,
      ),
    );
  }

  @override
  Future<void> sendTransferRequest({
    required String targetIp,
    required String requestId,
    required String senderName,
    required String senderMacAddress,
    required String sharedCacheId,
    required String sharedLabel,
    required List<TransferAnnouncementItem> items,
  }) async {
    transferRequests.add(
      SentTransferRequest(
        targetIp: targetIp,
        requestId: requestId,
        senderName: senderName,
        senderMacAddress: senderMacAddress,
        sharedCacheId: sharedCacheId,
        sharedLabel: sharedLabel,
        items: items,
      ),
    );
  }

  @override
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
    downloadRequests.add(
      SentDownloadRequest(
        targetIp: targetIp,
        requestId: requestId,
        requesterName: requesterName,
        requesterMacAddress: requesterMacAddress,
        cacheId: cacheId,
        selectedRelativePaths: List<String>.from(selectedRelativePaths),
        selectedFolderPrefixes: List<String>.from(selectedFolderPrefixes),
        transferPort: transferPort,
        previewMode: previewMode,
      ),
    );
  }

  @override
  Future<void> sendDownloadResponse({
    required String targetIp,
    required String requestId,
    required String responderName,
    required bool approved,
    String? message,
  }) async {
    downloadResponses.add(
      SentDownloadResponse(
        targetIp: targetIp,
        requestId: requestId,
        responderName: responderName,
        approved: approved,
        message: message,
      ),
    );
  }

  @override
  Future<void> stop() async {}
}

class SentTransferDecision {
  const SentTransferDecision({
    required this.targetIp,
    required this.requestId,
    required this.approved,
    required this.receiverName,
    required this.transferPort,
    required this.acceptedFileNames,
  });

  final String targetIp;
  final String requestId;
  final bool approved;
  final String receiverName;
  final int? transferPort;
  final List<String>? acceptedFileNames;
}

class SentTransferRequest {
  const SentTransferRequest({
    required this.targetIp,
    required this.requestId,
    required this.senderName,
    required this.senderMacAddress,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
  });

  final String targetIp;
  final String requestId;
  final String senderName;
  final String senderMacAddress;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferAnnouncementItem> items;
}

class SentDownloadRequest {
  const SentDownloadRequest({
    required this.targetIp,
    required this.requestId,
    required this.requesterName,
    required this.requesterMacAddress,
    required this.cacheId,
    required this.selectedRelativePaths,
    required this.selectedFolderPrefixes,
    required this.transferPort,
    required this.previewMode,
  });

  final String targetIp;
  final String requestId;
  final String requesterName;
  final String requesterMacAddress;
  final String cacheId;
  final List<String> selectedRelativePaths;
  final List<String> selectedFolderPrefixes;
  final int? transferPort;
  final bool previewMode;
}

class SentDownloadResponse {
  const SentDownloadResponse({
    required this.targetIp,
    required this.requestId,
    required this.responderName,
    required this.approved,
    required this.message,
  });

  final String targetIp;
  final String requestId;
  final String responderName;
  final bool approved;
  final String? message;
}

class SuccessfulReceiveFileTransferService extends FileTransferService {
  SuccessfulReceiveFileTransferService({required this.resultBuilder});

  final FileTransferResult Function(Directory destinationDirectory)
  resultBuilder;
  int startReceiverCalls = 0;
  String? lastDestinationDirectoryPath;

  @override
  Future<TransferReceiveSession> startReceiver({
    required String requestId,
    required List<TransferFileManifestItem>? expectedItems,
    required Directory destinationDirectory,
    Duration timeout = const Duration(minutes: 3),
    void Function(int receivedBytes, int totalBytes)? onProgress,
    String? destinationRelativeRootPrefix,
    Future<String> Function({
      required Directory destinationDirectory,
      required String relativePath,
    })?
    destinationPathAllocator,
  }) async {
    startReceiverCalls += 1;
    lastDestinationDirectoryPath = destinationDirectory.path;
    final result = resultBuilder(destinationDirectory);
    onProgress?.call(result.totalBytes, result.totalBytes);
    return TransferReceiveSession(
      port: 40404,
      result: Future<FileTransferResult>.value(result),
      close: () async {},
    );
  }
}

class CapturingSendFileTransferService extends FileTransferService {
  int sendFilesCalls = 0;
  List<TransferSourceFile> lastFiles = const <TransferSourceFile>[];

  @override
  Future<void> sendFiles({
    required String host,
    required int port,
    required String requestId,
    required List<TransferSourceFile> files,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    sendFilesCalls += 1;
    lastFiles = List<TransferSourceFile>.from(files);
  }
}

class ControlledFileHashService extends FileHashService {
  final Map<String, Completer<String>> _completersByPath =
      <String, Completer<String>>{};

  List<String> get pendingPaths =>
      _completersByPath.keys.toList(growable: false);

  @override
  Future<String> computeSha256ForPath(String filePath) {
    final completer = Completer<String>();
    _completersByPath[filePath] = completer;
    return completer.future;
  }

  void completeAll({required String withHash}) {
    final completers = _completersByPath.values.toList(growable: false);
    _completersByPath.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) {
        completer.complete(withHash);
      }
    }
  }
}

class CountingFileHashService extends FileHashService {
  int computeCalls = 0;

  @override
  Future<String> computeSha256ForPath(String filePath) async {
    computeCalls += 1;
    return 'counted-hash-$computeCalls';
  }
}

class AllocatingReceiveFileTransferService extends FileTransferService {
  int startReceiverCalls = 0;
  String? lastDestinationDirectoryPath;
  String? lastDestinationRelativeRootPrefix;

  @override
  Future<TransferReceiveSession> startReceiver({
    required String requestId,
    required List<TransferFileManifestItem>? expectedItems,
    required Directory destinationDirectory,
    Duration timeout = const Duration(minutes: 3),
    void Function(int receivedBytes, int totalBytes)? onProgress,
    String? destinationRelativeRootPrefix,
    Future<String> Function({
      required Directory destinationDirectory,
      required String relativePath,
    })?
    destinationPathAllocator,
  }) async {
    startReceiverCalls += 1;
    lastDestinationDirectoryPath = destinationDirectory.path;
    lastDestinationRelativeRootPrefix = destinationRelativeRootPrefix;
    final savedPaths = <String>[];
    final manifestItems = expectedItems ?? const <TransferFileManifestItem>[];
    for (final item in manifestItems) {
      final destinationPath = destinationPathAllocator == null
          ? destinationRelativeRootPrefix == null ||
                    destinationRelativeRootPrefix.isEmpty
                ? p.join(destinationDirectory.path, item.fileName)
                : p.joinAll(<String>[
                    destinationDirectory.path,
                    destinationRelativeRootPrefix,
                    ...p.split(item.fileName),
                  ])
          : await destinationPathAllocator(
              destinationDirectory: destinationDirectory,
              relativePath: item.fileName,
            );
      savedPaths.add(destinationPath);
    }
    final totalBytes = manifestItems.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );
    onProgress?.call(totalBytes, totalBytes);
    return TransferReceiveSession(
      port: 40404,
      result: Future<FileTransferResult>.value(
        FileTransferResult(
          success: true,
          message: 'ok',
          savedPaths: savedPaths,
          receivedItems: manifestItems,
          totalBytes: totalBytes,
          destinationDirectory: destinationDirectory.path,
          hashVerified: true,
        ),
      ),
      close: () async {},
    );
  }
}

class PendingReceiveFileTransferService extends FileTransferService {
  PendingReceiveFileTransferService({required this.port});

  final int port;
  int startReceiverCalls = 0;

  @override
  Future<TransferReceiveSession> startReceiver({
    required String requestId,
    required List<TransferFileManifestItem>? expectedItems,
    required Directory destinationDirectory,
    Duration timeout = const Duration(minutes: 3),
    void Function(int receivedBytes, int totalBytes)? onProgress,
    String? destinationRelativeRootPrefix,
    Future<String> Function({
      required Directory destinationDirectory,
      required String relativePath,
    })?
    destinationPathAllocator,
  }) async {
    startReceiverCalls += 1;
    return TransferReceiveSession(
      port: port,
      result: Completer<FileTransferResult>().future,
      close: () async {},
    );
  }
}

class RecordingTransferStorageService extends TransferStorageService {
  RecordingTransferStorageService({
    required this.rootDirectory,
    this.supportsDesktopDownloadPicker = true,
    this.publishesReceivedDownloadsToUserDownloads = false,
    Directory? pickedDesktopDownloadDirectory,
    this.publishedDownloadPaths,
  }) : _pickedDesktopDownloadDirectory = pickedDesktopDownloadDirectory;

  final Directory rootDirectory;
  final Directory? _pickedDesktopDownloadDirectory;
  final List<String>? publishedDownloadPaths;
  int resolveReceiveCalls = 0;
  int pickDesktopDownloadDirectoryCalls = 0;
  int publishToUserDownloadsCalls = 0;

  late final Directory standardReceiveDirectory = Directory(
    '${rootDirectory.path}${Platform.pathSeparator}incoming',
  );

  @override
  final bool supportsDesktopDownloadPicker;

  @override
  final bool publishesReceivedDownloadsToUserDownloads;

  @override
  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    resolveReceiveCalls += 1;
    await standardReceiveDirectory.create(recursive: true);
    return standardReceiveDirectory;
  }

  @override
  Future<Directory?> pickDesktopDownloadDirectory() async {
    pickDesktopDownloadDirectoryCalls += 1;
    final directory = _pickedDesktopDownloadDirectory;
    if (directory == null) {
      return null;
    }
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<List<String>> publishToUserDownloads({
    required List<String> sourcePaths,
    required List<String> relativePaths,
    String appFolderName = 'Landa',
  }) async {
    publishToUserDownloadsCalls += 1;
    return publishedDownloadPaths ?? sourcePaths;
  }

  @override
  Future<void> showAndroidDownloadProgressNotification({
    required String requestId,
    required String senderName,
    required int receivedBytes,
    required int totalBytes,
  }) async {}

  @override
  Future<void> showAndroidDownloadCompletedNotification({
    required String requestId,
    required List<String> savedPaths,
    required String directoryPath,
  }) async {}

  @override
  Future<void> showAndroidDownloadFailedNotification({
    required String requestId,
    required String message,
  }) async {}
}

class StubNetworkHostScanner extends NetworkHostScanner {
  StubNetworkHostScanner(this.result) : super(allowTcpFallback: false);

  final Map<String, String?> result;

  @override
  Future<Map<String, String?>> scanActiveHosts({
    required Set<String> localSourceIps,
    Set<String> configuredTargetIps = const <String>{},
  }) async {
    return result;
  }
}
