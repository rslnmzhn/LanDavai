import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/presentation/discovery_receive_panel_sheet.dart';
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

  testWidgets('Remote-share preview opens LocalFileViewerPage', (tester) async {
    _registerWidgetCleanup(tester);
    final previewFile = File(
      '${harness.databaseHarness.rootDirectory.path}/remote-preview.txt',
    );
    await tester.runAsync(() async {
      await previewFile.writeAsString('preview');
    });

    final remoteShareBrowser = harness.remoteShareBrowser;
    final ownerIp = '192.168.1.44';
    final requestId = 'request-1';
    final entry = SharedCatalogEntryItem(
      cacheId: 'cache-1',
      displayName: 'Shared docs',
      itemCount: 1,
      totalBytes: 12,
      files: <SharedCatalogFileItem>[
        SharedCatalogFileItem(
          relativePath: 'remote-preview.txt',
          sizeBytes: 12,
          thumbnailId: 'thumb-1',
        ),
      ],
    );

    await remoteShareBrowser.applyRemoteCatalog(
      event: ShareCatalogEvent(
        requestId: requestId,
        ownerIp: ownerIp,
        ownerName: 'Remote device',
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        entries: <SharedCatalogEntryItem>[entry],
        removedCacheIds: const <String>[],
        observedAt: DateTime(2026, 1, 2),
      ),
      ownerDisplayName: 'Remote device',
      ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
    );
    remoteShareBrowser.selectOwner(ownerIp);

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
        home: Scaffold(
          body: DiscoveryReceivePanelSheet(
            onRefreshRemoteShares: () async {},
            remoteShareBrowser: remoteShareBrowser,
            previewCacheOwner: harness.previewCacheOwner,
            transferSessionCoordinator: coordinator,
          ),
        ),
      ),
    );
    await tester.pump();
    await _pumpForUi(tester, frames: 20);

    expect(find.text('remote-preview.txt'), findsOneWidget);
    await tester.tap(find.byTooltip('Preview before download'));
    await _pumpUntilFound(
      tester,
      find.byType(LocalFileViewerPage, skipOffstage: false),
      failureMessage: 'Remote-share preview did not open the file viewer.',
    );
    final viewerFinder = find.byType(
      LocalFileViewerPage,
      skipOffstage: false,
    );
    expect(viewerFinder, findsOneWidget);
    await _pumpForUi(tester, frames: 4);
    await _closeCurrentRoute(tester, viewerFinder.first);
    await _flushDbTimers(tester);
  });
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

Future<void> _closeCurrentRoute(WidgetTester tester, Finder anchor) async {
  final context = tester.element(anchor);
  Navigator.of(context).pop();
  await _pumpForUi(tester, frames: 8);
}

Future<void> _flushDbTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await _pumpForUi(tester, frames: 4);
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
}
