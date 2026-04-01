import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:landa/features/discovery/presentation/discovery_page.dart';
import 'package:landa/features/discovery/presentation/discovery_side_menu_surface.dart';
import 'package:landa/features/files/application/file_explorer_contract.dart';
import 'package:landa/features/files/application/files_feature_state_owner.dart';
import 'package:landa/features/files/presentation/file_explorer/local_file_viewer.dart';
import 'package:landa/features/files/presentation/file_explorer_page.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets('Discovery menu opens Files surface', (tester) async {
    _registerWidgetCleanup(tester);
    final transferStorageService = _StubTransferStorageService(
      rootDirectory: harness.databaseHarness.rootDirectory,
    );
    await _pumpDiscoveryPage(
      tester,
      harness: harness,
      transferStorageService: transferStorageService,
    );

    await _openMenu(
      tester,
      isLeftHanded: harness.readModel.settings.isLeftHandedMode,
    );
    expect(find.text('Menu'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Files'), findsOneWidget);
    final menuSurface = tester.widget<DiscoverySideMenuSurface>(
      find.byType(DiscoverySideMenuSurface).first,
    );
    final openFuture = menuSurface.onOpenFiles();
    Navigator.of(tester.element(find.text('Menu'))).pop();
    await _pumpForUi(tester, frames: 4);
    expect(transferStorageService.resolveReceiveCalls, greaterThan(0));
    await tester.pump();
    final openError = tester.takeException();
    expect(openError, isNull);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isTrue);
    await _pumpUntilFound(
      tester,
      find.byType(FileExplorerPage, skipOffstage: false),
      failureMessage: 'File explorer route did not open from discovery menu.',
    );
    await _flushAsync(tester);
    expect(find.text('Files'), findsWidgets);
    await _closeCurrentRoute(tester, find.byType(FileExplorerPage).first);
    await _pumpForUi(tester, frames: 12);
    await openFuture;
    await _flushDbTimers(tester);
  });

  testWidgets('File explorer can launch LocalFileViewerPage', (tester) async {
    _registerWidgetCleanup(tester);
    final file = File(
      p.join(harness.databaseHarness.rootDirectory.path, 'viewer-sample.txt'),
    );
    await tester.runAsync(() async {
      await file.writeAsString('hello');
    });

    final owner = FilesFeatureStateOwner(
      roots: <FileExplorerRoot>[
        FileExplorerRoot(
          label: 'My files',
          path: 'virtual://viewer',
          virtualFiles: <FileExplorerVirtualFile>[
            FileExplorerVirtualFile(
              path: file.path,
              virtualPath: 'viewer-sample.txt',
              sizeBytes: file.lengthSync(),
              modifiedAt: DateTime(2026, 1, 1),
              changedAt: DateTime(2026, 1, 1),
            ),
          ],
        ),
      ],
    );
    addTearDown(owner.dispose);
    await owner.initialize();

    await tester.pumpWidget(
      MaterialApp(
        home: FileExplorerPage(
          owner: owner,
          previewCacheOwner: harness.previewCacheOwner,
          sharedCacheMaintenanceBoundary: harness.sharedCacheMaintenanceBoundary,
        ),
      ),
    );
    await _pumpForUi(tester, frames: 20);
    expect(find.text('viewer-sample.txt'), findsOneWidget);
    await tester.tap(find.text('viewer-sample.txt'));
    await _pumpUntilFound(
      tester,
      find.byType(LocalFileViewerPage, skipOffstage: false),
      failureMessage: 'Local file viewer route did not open from file list.',
    );
    await _flushAsync(tester);
    await _closeCurrentRoute(tester, find.byType(LocalFileViewerPage).first);
    await _pumpForUi(tester, frames: 12);
    await _flushDbTimers(tester);
  });
}

Future<void> _pumpDiscoveryPage(
  WidgetTester tester, {
  required TestDiscoveryControllerHarness harness,
  _StubTransferStorageService? transferStorageService,
}) async {
  final resolvedTransferStorageService =
      transferStorageService ??
      _StubTransferStorageService(
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
        transferStorageService: resolvedTransferStorageService,
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

Future<void> _flushAsync(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await _pumpForUi(tester, frames: 4);
}

Future<void> _flushDbTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
  await _pumpForUi(tester, frames: 4);
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

class _StubTransferStorageService extends TransferStorageService {
  _StubTransferStorageService({required this.rootDirectory});

  final Directory rootDirectory;
  int resolveReceiveCalls = 0;

  @override
  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    resolveReceiveCalls += 1;
    final directory = Directory(p.join(rootDirectory.path, 'incoming'));
    directory.createSync(recursive: true);
    return Future<Directory>.value(directory);
  }

  @override
  Future<Directory?> resolveAndroidPublicDownloadsDirectory() async {
    return null;
  }
}
