import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/features/discovery/application/shared_cache_maintenance_boundary.dart';
import 'package:landa/features/files/application/file_explorer_contract.dart';
import 'package:landa/features/files/application/files_feature_state_owner.dart';
import 'package:landa/features/files/presentation/file_explorer_page.dart';

import 'test_support/localized_test_app.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets(
    'FileExplorerPage keeps shared-folder actions visible and remove action reachable',
    (tester) async {
      _registerWidgetCleanup(tester);
      final mutableState = _MutableVirtualDirectoryState(
        folders: <FileExplorerVirtualFolder>[
          const FileExplorerVirtualFolder(
            name: 'Shared docs',
            folderPath: 'shared-docs',
            removableSharedCacheId: 'cache-1',
          ),
        ],
      );
      final owner = FilesFeatureStateOwner(
        roots: <FileExplorerRoot>[
          FileExplorerRoot(
            label: 'My files',
            path: 'virtual://my-files',
            isSharedFolder: true,
            virtualDirectoryLoader: (folderPath) async => mutableState.build(),
          ),
        ],
      );
      addTearDown(owner.dispose);
      await owner.initialize();

      final boundary = _RecordingSharedCacheMaintenanceBoundary(
        sharedCacheCatalog: harness.sharedCacheCatalog,
        sharedCacheIndexStore: harness.sharedCacheIndexStore,
        ownerMacAddressProvider: () => harness.controller.localDeviceMac,
        onRemoveCacheById: (cacheId) async => true,
      );
      addTearDown(boundary.dispose);

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: FileExplorerPage(
            owner: owner,
            previewCacheOwner: harness.previewCacheOwner,
            sharedCacheMaintenanceBoundary: boundary,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _pumpForUi(tester, frames: 20);

      expect(find.text('Shared docs'), findsOneWidget);
      expect(find.byTooltip('Пересобрать общий кэш'), findsOneWidget);
      expect(find.byTooltip('Убрать из общего доступа'), findsOneWidget);

      await tester.tap(find.byTooltip('Убрать из общего доступа'));
      await _pumpUntilVisible(tester, find.text('Убрать общий каталог?'));
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await _pumpForUi(tester, frames: 12);

      expect(boundary.removeCacheByIdCalls, 1);
      expect(boundary.lastRemovedCacheId, 'cache-1');
    },
  );
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 40,
}) async {
  for (var i = 0; i < maxFrames; i += 1) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

void _registerWidgetCleanup(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpForUi(tester);
  });
}

class _MutableVirtualDirectoryState {
  _MutableVirtualDirectoryState({
    required List<FileExplorerVirtualFolder> folders,
  }) : _folders = List<FileExplorerVirtualFolder>.from(folders);

  final List<FileExplorerVirtualFolder> _folders;

  FileExplorerVirtualDirectory build() {
    return FileExplorerVirtualDirectory(
      folders: List<FileExplorerVirtualFolder>.from(_folders),
    );
  }
}

class _RecordingSharedCacheMaintenanceBoundary
    extends SharedCacheMaintenanceBoundary {
  _RecordingSharedCacheMaintenanceBoundary({
    required super.sharedCacheCatalog,
    required super.sharedCacheIndexStore,
    required super.ownerMacAddressProvider,
    required this.onRemoveCacheById,
  }) : super(appNotificationService: AppNotificationService.instance);

  final Future<bool> Function(String cacheId) onRemoveCacheById;
  int removeCacheByIdCalls = 0;
  String? lastRemovedCacheId;

  @override
  Future<SharedCacheSummary> summarizeOwnerSharedContent({
    String virtualFolderPath = '',
  }) async {
    return const SharedCacheSummary(
      totalCaches: 1,
      folderCaches: 1,
      selectionCaches: 0,
      totalFiles: 2,
    );
  }

  @override
  Future<bool> removeCacheById(String cacheId) async {
    removeCacheByIdCalls += 1;
    lastRemovedCacheId = cacheId;
    return onRemoveCacheById(cacheId);
  }
}
