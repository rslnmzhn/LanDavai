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

      await tester.longPress(find.text('report.txt'));
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
      find.byKey(
        const Key('remote-download-select-192.168.1.44|cache-a|report.txt'),
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
    'structured mode allows downloading a folder without selecting files one by one',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _seedCatalogWithFiles(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Share',
        files: <String>['docs/a.txt', 'docs/sub/b.txt', 'top.txt'],
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

      await tester.tap(find.widgetWithText(ChoiceChip, 'Remote A'));
      await _pumpForUi(tester, frames: 8);

      await tester.tap(find.textContaining('Share').first);
      await _pumpForUi(tester, frames: 8);
      expect(find.text('docs'), findsOneWidget);

      await tester.longPress(find.text('docs'));
      await _pumpForUi(tester, frames: 4);
      expect(find.text('Скачать выбранные (1)'), findsOneWidget);

      await tester.tap(find.text('Скачать выбранные (1)'));
      await _pumpForUi(tester, frames: 8);

      expect(coordinator.downloadCalls, 1);
      expect(coordinator.lastSelectedByCache, <String, Set<String>>{
        'cache-a': <String>{'docs/a.txt', 'docs/sub/b.txt'},
      });
    },
  );

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

  testWidgets(
    'all-devices structured view shows share folders and allows navigation without switching to a device filter',
    (tester) async {
      _registerWidgetCleanup(tester);
      await _seedCatalogWithFiles(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Share',
        files: <String>['docs/a.txt', 'top.txt'],
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

      expect(find.textContaining('Remote A • Share'), findsWidgets);

      await tester.tap(find.textContaining('Remote A • Share').first);
      await _pumpForUi(tester, frames: 8);

      expect(find.text('docs'), findsOneWidget);
      expect(find.text('top.txt'), findsOneWidget);
      expect(find.text('Remote A / Share / top.txt • 12 B'), findsOneWidget);
    },
  );

  testWidgets('download browser sort controls match Files surface patterns', (
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

    await tester.tap(find.byTooltip('Sort'));
    await _pumpForUi(tester, frames: 4);

    expect(find.text('A-Z'), findsOneWidget);
    expect(find.text('Z-A'), findsOneWidget);
    expect(find.text('Modified: newest'), findsOneWidget);
    expect(find.text('Created/changed: newest'), findsOneWidget);
    expect(find.text('Size: largest'), findsOneWidget);
    expect(find.text('Tile size'), findsOneWidget);
  });

  testWidgets(
    'long press and selection circle both toggle file selection while tap stays preview',
    (tester) async {
      _registerWidgetCleanup(tester);
      final previewFile = File(
        '${harness.databaseHarness.rootDirectory.path}/selection-preview.txt',
      );
      await tester.runAsync(() async {
        await previewFile.writeAsString('preview');
      });

      await _seedCatalog(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Docs',
        filePath: 'report.txt',
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
      await _pumpForUi(tester, frames: 20);

      await tester.tap(find.text('Без структуры'));
      await _pumpForUi(tester, frames: 8);

      await tester.longPress(find.text('report.txt'));
      await _pumpForUi(tester, frames: 4);
      expect(find.text('Скачать выбранные (1)'), findsOneWidget);

      await tester.longPress(find.text('report.txt'));
      await _pumpForUi(tester, frames: 4);
      expect(find.text('Скачать выбранные (1)'), findsNothing);

      await tester.tap(
        find.byKey(
          const Key('remote-download-select-192.168.1.44|cache-a|report.txt'),
        ),
      );
      await _pumpForUi(tester, frames: 4);
      expect(find.text('Скачать выбранные (1)'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const Key('remote-download-select-192.168.1.44|cache-a|report.txt'),
        ),
      );
      await _pumpForUi(tester, frames: 4);
      expect(find.text('Скачать выбранные (1)'), findsNothing);

      await tester.tap(find.text('report.txt'));
      await _pumpUntilFound(
        tester,
        find.byType(LocalFileViewerPage, skipOffstage: false),
        failureMessage: 'Simple tap should still open preview.',
      );
      expect(
        find.byType(LocalFileViewerPage, skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('category filter is available only in flat mode', (tester) async {
    await _setLargeSurface(tester);
    _registerWidgetCleanup(tester);
    await _seedCatalog(
      browser: harness.remoteShareBrowser,
      ownerIp: '192.168.1.44',
      ownerName: 'Remote A',
      cacheId: 'cache-a',
      displayName: 'Docs',
      filePath: 'report.pdf',
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

    expect(
      find.byKey(const Key('remote-download-flat-category-filter-bar')),
      findsNothing,
    );

    await tester.tap(find.text('Без структуры'));
    await _pumpForUi(tester, frames: 8);

    expect(
      find.byKey(const Key('remote-download-flat-category-filter-bar')),
      findsOneWidget,
    );
    expect(find.text('Показывать все'), findsOneWidget);
  });

  testWidgets('show all overrides flat category toggles', (tester) async {
    await _setLargeSurface(tester);
    _registerWidgetCleanup(tester);
    await _seedCatalogWithFiles(
      browser: harness.remoteShareBrowser,
      ownerIp: '192.168.1.44',
      ownerName: 'Remote A',
      cacheId: 'cache-a',
      displayName: 'Mixed',
      files: const <String>['photo.jpg', 'report.pdf', 'script.dart'],
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

    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('script.dart'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('remote-download-category-documents')),
    );
    await tester.tap(
      find.byKey(const Key('remote-download-category-documents')),
    );
    await _pumpForUi(tester, frames: 8);

    expect(find.text('photo.jpg'), findsNothing);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('script.dart'), findsNothing);

    await tester.drag(
      find.byKey(const Key('remote-download-flat-category-filter-bar')),
      const Offset(640, 0),
    );
    await _pumpForUi(tester, frames: 4);
    await tester.tap(find.byKey(const Key('remote-download-show-all-chip')));
    await _pumpForUi(tester, frames: 8);

    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('script.dart'), findsOneWidget);
  });

  testWidgets(
    'flat search respects selected categories while structured mode is unaffected',
    (tester) async {
      await _setLargeSurface(tester);
      _registerWidgetCleanup(tester);
      await _seedCatalogWithFiles(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Mixed',
        files: const <String>['nested/song.mp3', 'nested/report.pdf'],
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

      expect(
        find.byKey(const Key('remote-download-flat-category-filter-bar')),
        findsNothing,
      );
      expect(find.text('song.mp3'), findsNothing);

      await tester.tap(find.text('Без структуры'));
      await _pumpForUi(tester, frames: 8);

      await tester.ensureVisible(
        find.byKey(const Key('remote-download-category-documents')),
      );
      await tester.tap(
        find.byKey(const Key('remote-download-category-documents')),
      );
      await _pumpForUi(tester, frames: 8);

      expect(find.text('song.mp3'), findsNothing);
      expect(find.text('report.pdf'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'song');
      await _pumpForUi(tester, frames: 8);

      expect(find.text('song.mp3'), findsNothing);
      expect(find.text('report.pdf'), findsNothing);

      await tester.tap(find.text('Со структурой'));
      await _pumpForUi(tester, frames: 8);

      expect(
        find.byKey(const Key('remote-download-flat-category-filter-bar')),
        findsNothing,
      );
      expect(find.text('song.mp3'), findsNothing);
    },
  );

  testWidgets(
    'preview and download still work for visible files after category filtering',
    (tester) async {
      await _setLargeSurface(tester);
      _registerWidgetCleanup(tester);
      final previewFile = File(
        '${harness.databaseHarness.rootDirectory.path}/filtered-preview.pdf',
      );
      await tester.runAsync(() async {
        await previewFile.writeAsString('preview');
      });

      await _seedCatalogWithFiles(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Mixed',
        files: const <String>['cover.jpg', 'report.pdf'],
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
      await _pumpForUi(tester, frames: 20);

      await tester.tap(find.text('Без структуры'));
      await _pumpForUi(tester, frames: 8);
      await tester.ensureVisible(
        find.byKey(const Key('remote-download-category-documents')),
      );
      await tester.tap(
        find.byKey(const Key('remote-download-category-documents')),
      );
      await _pumpForUi(tester, frames: 8);

      expect(find.text('cover.jpg'), findsNothing);
      expect(find.text('report.pdf'), findsOneWidget);

      await tester.tap(find.text('report.pdf'));
      await _pumpUntilFound(
        tester,
        find.byType(LocalFileViewerPage, skipOffstage: false),
        failureMessage: 'Filtered preview did not open the file viewer.',
      );
      expect(
        find.byType(LocalFileViewerPage, skipOffstage: false),
        findsOneWidget,
      );

      Navigator.of(
        tester.element(find.byType(LocalFileViewerPage, skipOffstage: false)),
      ).pop();
      await _pumpForUi(tester, frames: 8);

      await tester.tap(
        find.byKey(
          const Key('remote-download-select-192.168.1.44|cache-a|report.pdf'),
        ),
      );
      await _pumpForUi(tester, frames: 4);
      await tester.tap(find.text('Скачать выбранные (1)'));
      await _pumpForUi(tester, frames: 8);

      expect(coordinator.downloadCalls, 1);
      expect(coordinator.lastSelectedByCache, <String, Set<String>>{
        'cache-a': <String>{'report.pdf'},
      });
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

Future<void> _seedCatalogWithFiles({
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

Future<void> _setLargeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
