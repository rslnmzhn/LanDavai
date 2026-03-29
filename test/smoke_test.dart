import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/discovery_page_entry.dart';
import 'package:landa/features/discovery/presentation/discovery_page.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets(
    'DiscoveryPage renders with injected dependencies and does not own controller disposal',
    (tester) async {
      final desktopWindowService = TrackingDesktopWindowService();
      final transferStorageService = StubTransferStorageService(
        rootDirectory: harness.databaseHarness.rootDirectory,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryPage(
            controller: harness.controller,
            readModel: harness.readModel,
            remoteShareBrowser: harness.remoteShareBrowser,
            sharedCacheMaintenanceBoundary:
                harness.sharedCacheMaintenanceBoundary,
            videoLinkSessionBoundary: harness.videoLinkSessionBoundary,
            sharedCacheCatalog: harness.sharedCacheCatalog,
            sharedCacheIndexStore: harness.sharedCacheIndexStore,
            previewCacheOwner: harness.previewCacheOwner,
            transferSessionCoordinator: harness.transferSessionCoordinator,
            downloadHistoryBoundary: harness.downloadHistoryBoundary,
            clipboardHistoryStore: harness.clipboardHistoryStore,
            remoteClipboardProjectionStore:
                harness.remoteClipboardProjectionStore,
            desktopWindowService: desktopWindowService,
            transferStorageService: transferStorageService,
            isBoundaryReady: false,
          ),
        ),
      );

      expect(find.text('Landa devices'), findsOneWidget);
      expect(harness.controller.startCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(harness.controller.disposeCalls, 0);
      expect(desktopWindowService.setMinimizeCalls, 0);
    },
  );

  testWidgets(
    'DiscoveryPageEntry starts injected controller above the screen lifecycle',
    (tester) async {
      final desktopWindowService = TrackingDesktopWindowService();
      final transferStorageService = StubTransferStorageService(
        rootDirectory: harness.databaseHarness.rootDirectory,
      );
      final composition = harness.createEntryComposition(
        desktopWindowService: desktopWindowService,
        transferStorageService: transferStorageService,
      );

      await tester.pumpWidget(
        MaterialApp(home: DiscoveryPageEntry(composition: composition)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Landa devices'), findsOneWidget);
      expect(harness.controller.startCalls, 1);
      expect(desktopWindowService.setMinimizeCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(harness.controller.disposeCalls, 0);
    },
  );

  testWidgets(
    'DiscoveryPage receive flow starts remote browse through RemoteShareBrowser',
    (tester) async {
      final desktopWindowService = TrackingDesktopWindowService();
      final transferStorageService = StubTransferStorageService(
        rootDirectory: harness.databaseHarness.rootDirectory,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryPage(
            controller: harness.controller,
            readModel: harness.readModel,
            remoteShareBrowser: harness.remoteShareBrowser,
            sharedCacheMaintenanceBoundary:
                harness.sharedCacheMaintenanceBoundary,
            videoLinkSessionBoundary: harness.videoLinkSessionBoundary,
            sharedCacheCatalog: harness.sharedCacheCatalog,
            sharedCacheIndexStore: harness.sharedCacheIndexStore,
            previewCacheOwner: harness.previewCacheOwner,
            transferSessionCoordinator: harness.transferSessionCoordinator,
            downloadHistoryBoundary: harness.downloadHistoryBoundary,
            clipboardHistoryStore: harness.clipboardHistoryStore,
            remoteClipboardProjectionStore:
                harness.remoteClipboardProjectionStore,
            desktopWindowService: desktopWindowService,
            transferStorageService: transferStorageService,
            isBoundaryReady: false,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Принять'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.remoteShareBrowser.startBrowseCalls, 1);
      expect(find.text('Выбор файлов из LAN'), findsOneWidget);

      final sheetContext = tester.element(find.text('Выбор файлов из LAN'));
      Navigator.of(sheetContext).pop();
      await tester.pumpAndSettle();
      await (harness.controller.lastLoadRemoteShareOptionsFuture ??
          Future<void>.value());
      await tester.pump();
    },
  );

  testWidgets('DiscoveryPage menu opens extracted friends sheet flow', (
    tester,
  ) async {
    final desktopWindowService = TrackingDesktopWindowService();
    final transferStorageService = StubTransferStorageService(
      rootDirectory: harness.databaseHarness.rootDirectory,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryPage(
          controller: harness.controller,
          readModel: harness.readModel,
          remoteShareBrowser: harness.remoteShareBrowser,
          sharedCacheMaintenanceBoundary:
              harness.sharedCacheMaintenanceBoundary,
          videoLinkSessionBoundary: harness.videoLinkSessionBoundary,
          sharedCacheCatalog: harness.sharedCacheCatalog,
          sharedCacheIndexStore: harness.sharedCacheIndexStore,
          previewCacheOwner: harness.previewCacheOwner,
          transferSessionCoordinator: harness.transferSessionCoordinator,
          downloadHistoryBoundary: harness.downloadHistoryBoundary,
          clipboardHistoryStore: harness.clipboardHistoryStore,
          remoteClipboardProjectionStore:
              harness.remoteClipboardProjectionStore,
          desktopWindowService: desktopWindowService,
          transferStorageService: transferStorageService,
          isBoundaryReady: false,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Friends'));
    await tester.pumpAndSettle();

    expect(
      find.text('Friendship requires confirmation from both devices.'),
      findsOneWidget,
    );
  });
}

class StubTransferStorageService extends TransferStorageService {
  StubTransferStorageService({required this.rootDirectory});

  final Directory rootDirectory;

  @override
  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    final directory = Directory(p.join(rootDirectory.path, 'incoming'));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<Directory?> resolveAndroidPublicDownloadsDirectory() async {
    return null;
  }
}
