import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
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
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:landa/features/transfer/domain/transfer_request.dart';

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransferSessionCoordinator', () {
    late TestAppDatabaseHarness harness;
    late SharedFolderCacheRepository sharedFolderCacheRepository;
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
      sharedFolderCacheRepository = SharedFolderCacheRepository(
        database: harness.database,
      );
      sharedCacheIndexStore = SharedCacheIndexStore(database: harness.database);
      sharedCacheCatalog = SharedCacheCatalog(
        sharedFolderCacheRepository: sharedFolderCacheRepository,
        sharedCacheIndexStore: sharedCacheIndexStore,
      );
      fileHashService = FileHashService();
      previewCacheOwner = PreviewCacheOwner(
        sharedFolderCacheRepository: sharedFolderCacheRepository,
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
        await Future<void>.delayed(const Duration(milliseconds: 20));

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
      final settingsStore = SettingsStore(
        appSettingsRepository: AppSettingsRepository(database: database),
      );
      final trustedLanPeerStore = TrustedLanPeerStore(
        deviceRegistry: deviceRegistry,
        deviceAliasRepository: deviceAliasRepository,
      );
      final sharedFolderCacheRepository = SharedFolderCacheRepository(
        database: database,
      );
      final sharedCacheIndexStore = SharedCacheIndexStore(database: database);
      final sharedCacheCatalog = SharedCacheCatalog(
        sharedFolderCacheRepository: sharedFolderCacheRepository,
        sharedCacheIndexStore: sharedCacheIndexStore,
      );
      final fileHashService = FileHashService();
      final previewCacheOwner = PreviewCacheOwner(
        sharedFolderCacheRepository: sharedFolderCacheRepository,
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
      controller = DiscoveryController(
        lanDiscoveryService: lanDiscoveryService,
        networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
        deviceRegistry: deviceRegistry,
        internetPeerEndpointStore: InternetPeerEndpointStore(
          friendRepository: friendRepository,
        ),
        trustedLanPeerStore: trustedLanPeerStore,
        friendRepository: friendRepository,
        settingsStore: settingsStore,
        appNotificationService: AppNotificationService.instance,
        transferHistoryRepository: transferHistoryRepository,
        downloadHistoryBoundary: downloadHistoryBoundary,
        clipboardHistoryRepository: ClipboardHistoryRepository(
          database: database,
        ),
        clipboardCaptureService: ClipboardCaptureService(),
        remoteShareBrowser: remoteShareBrowser,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: sharedCacheIndexStore,
        sharedFolderCacheRepository: sharedFolderCacheRepository,
        fileHashService: fileHashService,
        fileTransferService: FileTransferService(),
        transferStorageService: TransferStorageService(),
        previewCacheOwner: previewCacheOwner,
        videoLinkShareService: VideoLinkShareService(),
        pathOpener: PathOpener(),
        transferSessionCoordinator: transferSessionCoordinator,
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
        expect(controller.videoLinkShareSession, isNull);
      } finally {
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

class CapturingLanDiscoveryService extends LanDiscoveryService {
  final List<SentTransferDecision> transferDecisions = <SentTransferDecision>[];
  void Function(TransferRequestEvent event)? onTransferRequest;
  void Function(TransferDecisionEvent event)? onTransferDecision;
  void Function(DownloadRequestEvent event)? onDownloadRequest;

  @override
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
    this.onTransferRequest = onTransferRequest;
    this.onTransferDecision = onTransferDecision;
    this.onDownloadRequest = onDownloadRequest;
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

class SuccessfulReceiveFileTransferService extends FileTransferService {
  SuccessfulReceiveFileTransferService({required this.resultBuilder});

  final FileTransferResult Function(Directory destinationDirectory)
  resultBuilder;
  int startReceiverCalls = 0;

  @override
  Future<TransferReceiveSession> startReceiver({
    required String requestId,
    required List<TransferFileManifestItem> expectedItems,
    required Directory destinationDirectory,
    Duration timeout = const Duration(minutes: 3),
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    startReceiverCalls += 1;
    final result = resultBuilder(destinationDirectory);
    onProgress?.call(result.totalBytes, result.totalBytes);
    return TransferReceiveSession(
      port: 40404,
      result: Future<FileTransferResult>.value(result),
      close: () async {},
    );
  }
}

class RecordingTransferStorageService extends TransferStorageService {
  RecordingTransferStorageService({required this.rootDirectory});

  final Directory rootDirectory;

  @override
  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    final directory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}incoming',
    );
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<List<String>> publishToUserDownloads({
    required List<String> sourcePaths,
    required List<String> relativePaths,
    String appFolderName = 'Landa',
  }) async {
    return sourcePaths;
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
    String? preferredSourceIp,
  }) async {
    return result;
  }
}
