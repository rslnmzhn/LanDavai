import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:landa/features/discovery/presentation/discovery_page.dart';
import 'package:landa/features/history/domain/transfer_history_record.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;
  late RecordingPathOpener pathOpener;

  setUp(() async {
    pathOpener = RecordingPathOpener();
    harness = await TestDiscoveryControllerHarness.create(
      pathOpener: pathOpener,
    );
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets('History sheet shows populated records and open-folder action', (
    tester,
  ) async {
    _registerWidgetCleanup(tester);
    final rootDirectory = Directory(
      p.join(harness.databaseHarness.rootDirectory.path, 'history'),
    );
    await tester.runAsync(() async {
      await rootDirectory.create(recursive: true);
    });
    final savedFile = File(p.join(rootDirectory.path, 'report.txt'));
    await tester.runAsync(() async {
      await savedFile.writeAsString('history');
    });

    await tester.runAsync(() async {
      await harness.downloadHistoryBoundary.recordDownload(
        id: 'history-1',
        peerName: 'Remote device',
        rootPath: rootDirectory.path,
        savedPaths: <String>[savedFile.path],
        fileCount: 1,
        totalBytes: savedFile.lengthSync(),
        status: TransferHistoryStatus.completed,
        createdAtMs: DateTime(2026, 1, 3).millisecondsSinceEpoch,
      );
    });

    await _pumpDiscoveryPage(tester, harness: harness);
    await _openMenu(
      tester,
      isLeftHanded: harness.readModel.settings.isLeftHandedMode,
    );
    await tester.tap(find.widgetWithText(ListTile, 'Download history'));
    await _pumpForUi(tester, frames: 20);

    expect(find.text('История загрузок'), findsOneWidget);
    expect(find.text('report.txt'), findsOneWidget);
    expect(find.text('Открыть папку'), findsOneWidget);

    await tester.tap(find.text('report.txt'));
    await _pumpForUi(tester, frames: 8);
    await tester.tap(find.text('Открыть папку'));
    await _pumpForUi(tester, frames: 8);

    expect(pathOpener.openCalls, 2);
    expect(pathOpener.lastPath, rootDirectory.path);

    await _closeCurrentRoute(tester, find.text('История загрузок').first);
    await _flushDbTimers(tester);
  });
}

Future<void> _pumpDiscoveryPage(
  WidgetTester tester, {
  required TestDiscoveryControllerHarness harness,
}) async {
  final transferStorageService = _StubTransferStorageService(
    rootDirectory: harness.databaseHarness.rootDirectory,
  );

  await tester.pumpWidget(
    MaterialApp(
      home: DiscoveryPage(
        controller: harness.controller,
        readModel: harness.readModel,
        remoteShareBrowser: harness.remoteShareBrowser,
        sharedCacheMaintenanceBoundary: harness.sharedCacheMaintenanceBoundary,
        videoLinkSessionBoundary: harness.videoLinkSessionBoundary,
        sharedCacheCatalog: harness.sharedCacheCatalog,
        sharedCacheIndexStore: harness.sharedCacheIndexStore,
        previewCacheOwner: harness.previewCacheOwner,
        transferSessionCoordinator: harness.transferSessionCoordinator,
        downloadHistoryBoundary: harness.downloadHistoryBoundary,
        clipboardHistoryStore: harness.clipboardHistoryStore,
        remoteClipboardProjectionStore: harness.remoteClipboardProjectionStore,
        desktopWindowService: TrackingDesktopWindowService(),
        transferStorageService: transferStorageService,
        isBoundaryReady: true,
      ),
    ),
  );
  await tester.pump();
  await _pumpForUi(tester, frames: 20);
}

Future<void> _openMenu(
  WidgetTester tester, {
  required bool isLeftHanded,
}) async {
  final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
  if (isLeftHanded) {
    scaffoldState.openDrawer();
  } else {
    scaffoldState.openEndDrawer();
  }
  await _pumpForUi(tester, frames: 20);
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
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

class _StubTransferStorageService extends TransferStorageService {
  _StubTransferStorageService({required this.rootDirectory});

  final Directory rootDirectory;

  @override
  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    final directory = Directory(p.join(rootDirectory.path, 'incoming'));
    directory.createSync(recursive: true);
    return Future<Directory>.value(directory);
  }

  @override
  Future<Directory?> resolveAndroidPublicDownloadsDirectory() async {
    return null;
  }
}
