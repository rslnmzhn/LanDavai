import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/discovery/presentation/remote_download_browser_page.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/history/application/download_history_boundary.dart';
import 'package:landa/features/transfer/application/remote_file_preview_transfer_boundary.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/application/transfer_session_coordinator.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'localized_test_app.dart';
import 'test_discovery_controller.dart';

Future<void> pumpRemoteBrowser(
  WidgetTester tester, {
  required TestRemoteShareTransferCoordinator coordinator,
  required TrackingRemoteShareBrowser browser,
  required TestDiscoveryControllerHarness harness,
}) async {
  await tester.pumpWidget(
    buildLocalizedTestApp(
      home: RemoteDownloadBrowserPage(
        readModel: harness.readModel,
        remoteShareBrowser: browser,
        previewCacheOwner: harness.previewCacheOwner,
        transferSessionCoordinator: coordinator,
        remoteFilePreviewTransferBoundary:
            coordinator.remoteFilePreviewTransferBoundaryForTests,
        remoteShareAccessSessionBoundary:
            coordinator.remoteShareAccessSessionBoundary,
        transferCachePreparationBoundary:
            coordinator.transferCachePreparationBoundary,
        sharedDownloadBoundary: coordinator.sharedDownloadBoundary,
        useStandardAppDownloadFolder: true,
      ),
    ),
  );
  await pumpForUi(tester, frames: 20);
}

Future<void> seedRemoteCatalog({
  required TrackingRemoteShareBrowser browser,
  required String ownerIp,
  required String ownerName,
  required String cacheId,
  required String displayName,
  required String filePath,
  String requestId = 'request-1',
  bool startBrowse = true,
}) async {
  if (startBrowse) {
    await browser.startBrowse(
      targets: const <DiscoveredDevice>[],
      receiverMacAddress: 'aa:bb:cc:dd:ee:ff',
      requesterName: 'Receiver',
      requestId: requestId,
      responseWindow: Duration.zero,
      sendShareQuery:
          ({
            required String targetIp,
            required String requestId,
            required String requesterName,
          }) async {},
    );
  }
  await browser.applyRemoteCatalog(
    event: ShareCatalogEvent(
      requestId: requestId,
      ownerIp: ownerIp,
      ownerName: ownerName,
      ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
      entries: <SharedCatalogEntryItem>[
        SharedCatalogEntryItem(
          cacheId: cacheId,
          displayName: displayName,
          itemCount: 1,
          totalBytes: 12,
          files: <SharedCatalogFileItem>[
            SharedCatalogFileItem(relativePath: filePath, sizeBytes: 12),
          ],
        ),
      ],
      removedCacheIds: const <String>[],
      observedAt: DateTime(2026, 1, 2),
    ),
    ownerDisplayName: ownerName,
    ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
  );
}

Future<void> seedRemoteCatalogWithFiles({
  required TrackingRemoteShareBrowser browser,
  required String ownerIp,
  required String ownerName,
  required String cacheId,
  required String displayName,
  required List<String> files,
  String requestId = 'request-1',
  bool startBrowse = true,
}) async {
  if (startBrowse) {
    await browser.startBrowse(
      targets: const <DiscoveredDevice>[],
      receiverMacAddress: 'aa:bb:cc:dd:ee:ff',
      requesterName: 'Receiver',
      requestId: requestId,
      responseWindow: Duration.zero,
      sendShareQuery:
          ({
            required String targetIp,
            required String requestId,
            required String requesterName,
          }) async {},
    );
  }
  await browser.applyRemoteCatalog(
    event: ShareCatalogEvent(
      requestId: requestId,
      ownerIp: ownerIp,
      ownerName: ownerName,
      ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
      entries: <SharedCatalogEntryItem>[
        SharedCatalogEntryItem(
          cacheId: cacheId,
          displayName: displayName,
          itemCount: files.length,
          totalBytes: files.length * 12,
          files: files
              .map(
                (filePath) => SharedCatalogFileItem(
                  relativePath: filePath,
                  sizeBytes: 12,
                ),
              )
              .toList(growable: false),
        ),
      ],
      removedCacheIds: const <String>[],
      observedAt: DateTime(2026, 1, 2),
    ),
    ownerDisplayName: ownerName,
    ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
  );
}

Future<void> pumpForUi(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> switchToFlatMode(WidgetTester tester) async {
  await pumpUntilRemoteBrowserReady(tester);
  await tester.tap(find.text('Без структуры'));
  await pumpForUi(tester, frames: 8);
}

Future<void> switchToStructuredMode(WidgetTester tester) async {
  await pumpUntilRemoteBrowserReady(tester);
  await tester.tap(find.text('Со структурой'));
  await pumpForUi(tester, frames: 8);
}

Future<void> pumpUntilRemoteBrowserReady(WidgetTester tester) async {
  await pumpUntilFound(
    tester,
    find.byWidgetPredicate(
      (widget) => widget is RemoteDownloadBrowserPage,
      skipOffstage: false,
    ),
    failureMessage: 'Remote download browser did not finish its initial build.',
  );
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  String? failureMessage,
  int maxFrames = 120,
}) async {
  for (var i = 0; i < maxFrames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    final exception = tester.takeException();
    if (exception != null) {
      throw TestFailure(
        '${failureMessage ?? 'Expected widget was not found after pumping.'}\n'
        'Underlying exception: $exception',
      );
    }
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure(
    failureMessage ?? 'Expected widget was not found after pumping.',
  );
}

void registerWidgetCleanup(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpForUi(tester);
  });
}

Future<void> setLargeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class TestRemoteShareTransferCoordinator extends TransferSessionCoordinator {
  factory TestRemoteShareTransferCoordinator({
    required Future<String?> Function() previewPathProvider,
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required PreviewCacheOwner previewCacheOwner,
    required DownloadHistoryBoundary downloadHistoryBoundary,
    required AppSettings settings,
    LanDiscoveryService? lanDiscoveryService,
  }) {
    final resolvedLanDiscoveryService =
        lanDiscoveryService ?? LanDiscoveryService();
    final previewBoundary = _TestRemoteFilePreviewTransferBoundary(
      previewPathProvider: previewPathProvider,
      resolvedPreviewCacheOwner: previewCacheOwner,
    );
    return TestRemoteShareTransferCoordinator._(
      resolvedLanDiscoveryService: resolvedLanDiscoveryService,
      resolvedRemoteFilePreviewTransferBoundary: previewBoundary,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      downloadHistoryBoundary: downloadHistoryBoundary,
      settings: settings,
    );
  }

  TestRemoteShareTransferCoordinator._({
    required LanDiscoveryService resolvedLanDiscoveryService,
    required RemoteFilePreviewTransferBoundary
    resolvedRemoteFilePreviewTransferBoundary,
    required super.sharedCacheCatalog,
    required super.sharedCacheIndexStore,
    required super.downloadHistoryBoundary,
    required AppSettings settings,
  }) : _remoteFilePreviewTransferBoundary =
           resolvedRemoteFilePreviewTransferBoundary,
       super(
         lanDiscoveryService: resolvedLanDiscoveryService,
         fileHashService: FileHashService(),
         fileTransferService: FileTransferService(),
         transferStorageService: TransferStorageService(),
         appNotificationService: AppNotificationService.instance,
         settingsProvider: () => settings,
         localNameProvider: () => 'Local',
         localDeviceMacProvider: () => '02:00:00:00:00:01',
         isTrustedSender: (_) => true,
         resolveRemoteOwnerMac: ({required ownerIp, required cacheId}) => null,
         remoteFilePreviewTransferBoundary:
             resolvedRemoteFilePreviewTransferBoundary,
       );

  final RemoteFilePreviewTransferBoundary _remoteFilePreviewTransferBoundary;
  int downloadCalls = 0;
  Map<String, Set<String>>? lastSelectedByCache;
  Map<String, Set<String>>? lastSelectedFolderPrefixesByCache;

  RemoteFilePreviewTransferBoundary
  get remoteFilePreviewTransferBoundaryForTests =>
      _remoteFilePreviewTransferBoundary;
}

class _TestRemoteFilePreviewTransferBoundary
    extends RemoteFilePreviewTransferBoundary {
  _TestRemoteFilePreviewTransferBoundary({
    required Future<String?> Function() previewPathProvider,
    required PreviewCacheOwner resolvedPreviewCacheOwner,
  }) : _previewPathProvider = previewPathProvider,
       super(
         lanDiscoveryService: LanDiscoveryService(),
         fileHashService: FileHashService(),
         previewCacheOwner: resolvedPreviewCacheOwner,
         settingsProvider: () => AppSettings.defaults,
         localNameProvider: () => 'Local',
         localDeviceMacProvider: () => '02:00:00:00:00:01',
         resolveRemoteOwnerMac: ({required ownerIp, required cacheId}) => null,
         publishNotice: (_) {},
       );

  final Future<String?> Function() _previewPathProvider;

  @override
  Future<String?> requestRemoteFilePreview({
    required String ownerIp,
    required String ownerName,
    required String cacheId,
    required String relativePath,
  }) {
    return _previewPathProvider();
  }
}
