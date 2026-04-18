import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/features/discovery/application/shared_cache_maintenance_boundary.dart';
import 'package:landa/features/files/application/file_explorer_contract.dart';
import 'package:landa/features/files/application/files_feature_state_owner.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets('shared-file virtual entries keep remove cache wiring intact', (
    tester,
  ) async {
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
          virtualFiles: <FileExplorerVirtualFile>[
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
        ),
      ],
    );
    addTearDown(owner.dispose);
    await owner.initialize();
    expect(owner.state.entries, hasLength(1));
    expect(owner.state.entries.single.name, 'report.txt');
    expect(owner.state.entries.single.removableSharedCacheId, 'cache-file-1');

    final boundary = _RecordingSharedCacheMaintenanceBoundary(
      sharedCacheCatalog: harness.sharedCacheCatalog,
      sharedCacheIndexStore: harness.sharedCacheIndexStore,
      ownerMacAddressProvider: () => harness.controller.localDeviceMac,
      onRemoveCacheById: (cacheId) async => true,
    );
    addTearDown(boundary.dispose);

    await boundary.removeCacheById(
      owner.state.entries.single.removableSharedCacheId!,
    );

    expect(boundary.removeCacheByIdCalls, 1);
    expect(boundary.lastRemovedCacheId, 'cache-file-1');
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
