import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/discovery/presentation/remote_download_browser_page.dart';
import 'package:landa/features/files/presentation/file_explorer/local_file_viewer.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/transfer/application/transfer_session_coordinator.dart';
import 'package:landa/features/transfer/domain/transfer_request.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/core/utils/app_notification_service.dart';

import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets('Remote-share preview opens LocalFileViewerPage on simple tap', (
    tester,
  ) async {
    _registerWidgetCleanup(tester);
    final previewFile = File(
      '${harness.databaseHarness.rootDirectory.path}/remote-preview.txt',
    );
    await tester.runAsync(() async {
      await previewFile.writeAsString('preview');
    });

    await _seedCatalog(
      browser: harness.remoteShareBrowser,
      ownerIp: '192.168.1.44',
      ownerName: 'Remote device',
      cacheId: 'cache-1',
      displayName: 'Shared docs',
      filePath: 'remote-preview.txt',
    );

    final coordinator = _TestTransferSessionCoordinator(
      previewPathProvider: () async => previewFile.path,
      sharedCacheCatalog: harness.sharedCacheCatalog,
      sharedCacheIndexStore: harness.sharedCacheIndexStore,
      previewCacheOwner: harness.previewCacheOwner,
      downloadHistoryBoundary: harness.downloadHistoryBoundary,
      settings: harness.readModel.settings,
    );
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RemoteDownloadBrowserPage(
          onRefreshRemoteShares: () async {},
          remoteShareBrowser: harness.remoteShareBrowser,
          previewCacheOwner: harness.previewCacheOwner,
          transferSessionCoordinator: coordinator,
          useStandardAppDownloadFolder: true,
        ),
      ),
    );
    await tester.pump();
    await _pumpForUi(tester, frames: 20);

    await tester.tap(find.text('Без структуры'));
    await _pumpForUi(tester, frames: 8);

    expect(find.text('remote-preview.txt'), findsOneWidget);
    await tester.tap(find.text('remote-preview.txt'));
    await _pumpUntilFound(
      tester,
      find.byType(LocalFileViewerPage, skipOffstage: false),
      failureMessage: 'Remote-share preview did not open the file viewer.',
    );
    expect(
      find.byType(LocalFileViewerPage, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
    'selection survives filter switch and is pruned on invalidation',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _seedCatalog(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Docs',
        filePath: 'report.txt',
      );
      await _seedCatalog(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.55',
        ownerName: 'Remote B',
        cacheId: 'cache-b',
        displayName: 'Docs',
        filePath: 'notes.txt',
        requestId: 'request-2',
        startBrowse: false,
      );

      final coordinator = _TestTransferSessionCoordinator(
        previewPathProvider: () async => null,
        sharedCacheCatalog: harness.sharedCacheCatalog,
        sharedCacheIndexStore: harness.sharedCacheIndexStore,
        previewCacheOwner: harness.previewCacheOwner,
        downloadHistoryBoundary: harness.downloadHistoryBoundary,
        settings: harness.readModel.settings,
      );
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: RemoteDownloadBrowserPage(
            onRefreshRemoteShares: () async {},
            remoteShareBrowser: harness.remoteShareBrowser,
            previewCacheOwner: harness.previewCacheOwner,
            transferSessionCoordinator: coordinator,
            useStandardAppDownloadFolder: true,
          ),
        ),
      );
      await _pumpForUi(tester, frames: 20);

      await tester.tap(find.text('Без структуры'));
      await _pumpForUi(tester, frames: 8);

      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('report.txt'),
            matching: find.byType(ListTile),
          ),
          matching: find.byType(Checkbox),
        ),
      );
      await _pumpForUi(tester, frames: 4);
      expect(find.text('Скачать выбранные (1)'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Remote A'));
      await _pumpForUi(tester, frames: 8);
      expect(find.text('Скачать выбранные (1)'), findsOneWidget);

      await harness.remoteShareBrowser.applyRemoteCatalog(
        event: ShareCatalogEvent(
          requestId: 'request-1',
          ownerIp: '192.168.1.44',
          ownerName: 'Remote A',
          ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
          entries: const <SharedCatalogEntryItem>[],
          removedCacheIds: const <String>[],
          observedAt: DateTime(2026, 1, 3),
        ),
        ownerDisplayName: 'Remote A',
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
      );
      await _pumpForUi(tester, frames: 12);

      expect(find.text('Скачать выбранные (1)'), findsNothing);
    },
  );

  testWidgets('download starts only for explicitly selected files', (
    tester,
  ) async {
    _registerWidgetCleanup(tester);
    await _seedCatalog(
      browser: harness.remoteShareBrowser,
      ownerIp: '192.168.1.44',
      ownerName: 'Remote A',
      cacheId: 'cache-a',
      displayName: 'Docs',
      filePath: 'report.txt',
    );

    final coordinator = _TestTransferSessionCoordinator(
      previewPathProvider: () async => null,
      sharedCacheCatalog: harness.sharedCacheCatalog,
      sharedCacheIndexStore: harness.sharedCacheIndexStore,
      previewCacheOwner: harness.previewCacheOwner,
      downloadHistoryBoundary: harness.downloadHistoryBoundary,
      settings: harness.readModel.settings,
    );
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RemoteDownloadBrowserPage(
          onRefreshRemoteShares: () async {},
          remoteShareBrowser: harness.remoteShareBrowser,
          previewCacheOwner: harness.previewCacheOwner,
          transferSessionCoordinator: coordinator,
          useStandardAppDownloadFolder: true,
        ),
      ),
    );
    await _pumpForUi(tester, frames: 20);

    await tester.tap(find.text('Без структуры'));
    await _pumpForUi(tester, frames: 8);

    expect(find.text('Скачать выбранные (1)'), findsNothing);
    expect(coordinator.downloadCalls, 0);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('report.txt'),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(Checkbox),
      ),
    );
    await _pumpForUi(tester, frames: 4);
    await tester.tap(find.text('Скачать выбранные (1)'));
    await _pumpForUi(tester, frames: 8);

    expect(coordinator.downloadCalls, 1);
    expect(coordinator.lastSelectedByCache, <String, Set<String>>{
      'cache-a': <String>{'report.txt'},
    });
  });

  testWidgets(
    'view mode toggle switches between structured and flat projections',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _seedCatalog(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Docs',
        filePath: 'nested/report.txt',
      );

      final coordinator = _TestTransferSessionCoordinator(
        previewPathProvider: () async => null,
        sharedCacheCatalog: harness.sharedCacheCatalog,
        sharedCacheIndexStore: harness.sharedCacheIndexStore,
        previewCacheOwner: harness.previewCacheOwner,
        downloadHistoryBoundary: harness.downloadHistoryBoundary,
        settings: harness.readModel.settings,
      );
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: RemoteDownloadBrowserPage(
            onRefreshRemoteShares: () async {},
            remoteShareBrowser: harness.remoteShareBrowser,
            previewCacheOwner: harness.previewCacheOwner,
            transferSessionCoordinator: coordinator,
            useStandardAppDownloadFolder: true,
          ),
        ),
      );
      await _pumpForUi(tester, frames: 20);

      expect(find.text('report.txt'), findsNothing);

      await tester.tap(find.text('Без структуры'));
      await _pumpForUi(tester, frames: 12);

      expect(find.text('report.txt'), findsOneWidget);
    },
  );
}

Future<void> _seedCatalog({
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

Future<void> _pumpForUi(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  String? failureMessage,
  int maxFrames = 120,
}) async {
  for (var i = 0; i < maxFrames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure(
    failureMessage ?? 'Expected widget was not found after pumping.',
  );
}

void _registerWidgetCleanup(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpForUi(tester);
  });
}

class _TestTransferSessionCoordinator extends TransferSessionCoordinator {
  _TestTransferSessionCoordinator({
    required Future<String?> Function() previewPathProvider,
    required super.sharedCacheCatalog,
    required super.sharedCacheIndexStore,
    required super.previewCacheOwner,
    required super.downloadHistoryBoundary,
    required AppSettings settings,
  }) : _previewPathProvider = previewPathProvider,
       super(
         lanDiscoveryService: LanDiscoveryService(),
         fileHashService: FileHashService(),
         fileTransferService: FileTransferService(),
         transferStorageService: TransferStorageService(),
         appNotificationService: AppNotificationService.instance,
         settingsProvider: () => settings,
         localNameProvider: () => 'Local',
         localDeviceMacProvider: () => '02:00:00:00:00:01',
         isTrustedSender: (_) => true,
         resolveRemoteOwnerMac: ({required ownerIp, required cacheId}) => null,
       );

  final Future<String?> Function() _previewPathProvider;
  int downloadCalls = 0;
  Map<String, Set<String>>? lastSelectedByCache;

  @override
  List<IncomingTransferRequest> get incomingRequests =>
      const <IncomingTransferRequest>[];

  @override
  Future<String?> requestRemoteFilePreview({
    required String ownerIp,
    required String ownerName,
    required String cacheId,
    required String relativePath,
  }) async {
    return _previewPathProvider();
  }

  @override
  Future<void> requestDownloadFromRemoteFiles({
    required String ownerIp,
    required String ownerName,
    required Map<String, Set<String>> selectedRelativePathsByCache,
    required bool useStandardAppDownloadFolder,
  }) async {
    downloadCalls += 1;
    lastSelectedByCache = selectedRelativePathsByCache;
  }
}
