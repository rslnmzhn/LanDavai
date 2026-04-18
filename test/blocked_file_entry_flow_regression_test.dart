import 'dart:io';

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
    'FileExplorerPage keeps remove-shared-file action reachable and wired to cache removal',
    (tester) async {
      _registerWidgetCleanup(tester);
      final sharedFile = File(
        '${harness.databaseHarness.rootDirectory.path}/report.txt',
      );
      await tester.runAsync(() async {
        await sharedFile.writeAsString('report');
      });
      final owner = FilesFeatureStateOwner(
        roots: <FileExplorerRoot>[
          FileExplorerRoot(
            label: 'My files',
            path: 'virtual://my-files',
            isSharedFolder: true,
            virtualDirectoryLoader: (folderPath) async {
              return FileExplorerVirtualDirectory(
                files: <FileExplorerVirtualFile>[
                  FileExplorerVirtualFile(
                    path: sharedFile.path,
                    virtualPath: 'report.txt',
                    subtitle: 'Shared docs / report.txt',
                    sizeBytes: 12,
                    modifiedAt: DateTime(2026, 1, 1, 10),
                    changedAt: DateTime(2026, 1, 1, 10),
                    removableSharedCacheId: 'cache-file-1',
                  ),
                ],
              );
            },
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

      expect(find.byTooltip('Убрать из общего доступа'), findsOneWidget);

      await tester.tap(find.byTooltip('Убрать из общего доступа'));
      await _pumpUntilVisible(tester, find.text('Убрать общий файл?'));
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await _pumpForUi(tester, frames: 12);

      expect(boundary.removeCacheByIdCalls, 1);
      expect(boundary.lastRemovedCacheId, 'cache-file-1');
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
      folderCaches: 0,
      selectionCaches: 1,
      totalFiles: 1,
    );
  }

  @override
  Future<bool> removeCacheById(String cacheId) async {
    removeCacheByIdCalls += 1;
    lastRemovedCacheId = cacheId;
    return onRemoveCacheById(cacheId);
  }
}
