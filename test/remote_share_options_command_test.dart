import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_options_command.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/shared_cache_record_store.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_remote_share_options_command_',
    );
  });

  tearDown(() async {
    await harness.dispose();
  });

  test('reports when no Landa devices can be queried', () async {
    final browser = _RecordingRemoteShareBrowser(catalog: _catalog(harness));
    final sentQueries = <_SentShareQuery>[];
    final command = _buildCommand(browser: browser, sentQueries: sentQueries);

    final result = await command.load(
      devices: <DiscoveredDevice>[
        DiscoveredDevice(ip: '192.168.1.10', lastSeen: DateTime(2026)),
      ],
    );

    expect(browser.startBrowseCalls, 1);
    expect(browser.lastTargets, isEmpty);
    expect(sentQueries, isEmpty);
    expect(result.errorMessage, isNull);
    expect(
      result.infoMessage,
      'No Landa devices available for shared content.',
    );
  });

  test(
    'queries only app-detected devices through RemoteShareBrowser',
    () async {
      final browser = _RecordingRemoteShareBrowser(
        catalog: _catalog(harness),
        optionCount: 2,
      );
      final sentQueries = <_SentShareQuery>[];
      final command = _buildCommand(
        browser: browser,
        sentQueries: sentQueries,
        nowProvider: () => DateTime.fromMicrosecondsSinceEpoch(123),
      );

      final result = await command.load(
        devices: <DiscoveredDevice>[
          DiscoveredDevice(
            ip: '192.168.1.20',
            isAppDetected: true,
            lastSeen: DateTime(2026),
          ),
          DiscoveredDevice(ip: '192.168.1.21', lastSeen: DateTime(2026)),
        ],
      );

      expect(result.infoMessage, isNull);
      expect(result.errorMessage, isNull);
      expect(browser.lastReceiverMacAddress, '11:22:33:44:55:66');
      expect(browser.lastRequesterName, 'Local');
      expect(browser.lastTargets.map((device) => device.ip), <String>[
        '192.168.1.20',
      ]);
      expect(sentQueries, hasLength(1));
      expect(sentQueries.single.targetIp, '192.168.1.20');
      expect(sentQueries.single.requesterName, 'Local');
      expect(sentQueries.single.requestId, browser.lastRequestId);
      expect(
        sentQueries.single.requestId,
        FileHashService().buildStableId('share-query|123|11:22:33:44:55:66'),
      );
    },
  );

  test('reports when queried devices return no shared content', () async {
    final browser = _RecordingRemoteShareBrowser(catalog: _catalog(harness));
    final sentQueries = <_SentShareQuery>[];
    final command = _buildCommand(browser: browser, sentQueries: sentQueries);

    final result = await command.load(
      devices: <DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.1.20',
          isAppDetected: true,
          lastSeen: DateTime(2026),
        ),
      ],
    );

    expect(sentQueries, hasLength(1));
    expect(result.errorMessage, isNull);
    expect(result.infoMessage, 'No shared folders/files found on LAN devices.');
  });

  test('maps browse startup failures to command error result', () async {
    final browser = _RecordingRemoteShareBrowser(
      catalog: _catalog(harness),
      error: StateError('network down'),
    );
    final logs = <String>[];
    final command = _buildCommand(
      browser: browser,
      sentQueries: <_SentShareQuery>[],
      log: logs.add,
    );

    final result = await command.load(
      devices: <DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.1.20',
          isAppDetected: true,
          lastSeen: DateTime(2026),
        ),
      ],
    );

    expect(
      result.errorMessage,
      contains('Failed to request remote shares: Bad state: network down'),
    );
    expect(logs.single, result.errorMessage);
  });
}

RemoteShareOptionsCommand _buildCommand({
  required _RecordingRemoteShareBrowser browser,
  required List<_SentShareQuery> sentQueries,
  DateTime Function()? nowProvider,
  void Function(String message)? log,
}) {
  return RemoteShareOptionsCommand(
    remoteShareBrowser: browser,
    fileHashService: FileHashService(),
    sendShareQuery:
        ({
          required String targetIp,
          required String requestId,
          required String requesterName,
        }) async {
          sentQueries.add(
            _SentShareQuery(
              targetIp: targetIp,
              requestId: requestId,
              requesterName: requesterName,
            ),
          );
        },
    localDeviceMacProvider: () => '11:22:33:44:55:66',
    localNameProvider: () => 'Local',
    nowProvider: nowProvider,
    log: log,
  );
}

class _RecordingRemoteShareBrowser extends RemoteShareBrowser {
  _RecordingRemoteShareBrowser({
    required SharedCacheCatalog catalog,
    this.optionCount = 0,
    this.error,
  }) : super(sharedCacheCatalog: catalog);

  final int optionCount;
  final Object? error;

  int startBrowseCalls = 0;
  List<DiscoveredDevice> lastTargets = <DiscoveredDevice>[];
  String? lastReceiverMacAddress;
  String? lastRequesterName;
  String? lastRequestId;

  @override
  Future<RemoteBrowseStartResult> startBrowse({
    required List<DiscoveredDevice> targets,
    required String receiverMacAddress,
    required String requesterName,
    required String requestId,
    required Future<void> Function({
      required String targetIp,
      required String requestId,
      required String requesterName,
    })
    sendShareQuery,
    Duration responseWindow = const Duration(milliseconds: 900),
  }) async {
    startBrowseCalls += 1;
    lastTargets = targets;
    lastReceiverMacAddress = receiverMacAddress;
    lastRequesterName = requesterName;
    lastRequestId = requestId;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    for (final target in targets) {
      await sendShareQuery(
        targetIp: target.ip,
        requestId: requestId,
        requesterName: requesterName,
      );
    }
    return RemoteBrowseStartResult(
      hadTargets: targets.isNotEmpty,
      optionCount: optionCount,
    );
  }
}

class _SentShareQuery {
  const _SentShareQuery({
    required this.targetIp,
    required this.requestId,
    required this.requesterName,
  });

  final String targetIp;
  final String requestId;
  final String requesterName;
}

SharedCacheCatalog _catalog(TestAppDatabaseHarness harness) {
  return SharedCacheCatalog(
    sharedCacheRecordStore: _NoopSharedCacheRecordStore(),
    sharedCacheIndexStore: SharedCacheIndexStore(
      database: harness.database,
      thumbnailCacheService: ThumbnailCacheService(database: harness.database),
    ),
  );
}

class _NoopSharedCacheRecordStore implements SharedCacheRecordStore {
  @override
  Future<void> deleteCacheRecord(String cacheId) async {}

  @override
  Future<SharedFolderCacheRecord?> findCacheById(String cacheId) async => null;

  @override
  Future<SharedFolderCacheRecord?> findOwnerCacheByRootPath({
    required String ownerMacAddress,
    required String rootPath,
  }) async => null;

  @override
  Future<List<SharedFolderCacheRecord>> listCaches({
    SharedFolderCacheRole? role,
    String? ownerMacAddress,
    String? peerMacAddress,
  }) async => const <SharedFolderCacheRecord>[];

  @override
  Future<int> rebindOwnerCachesToMac({required String ownerMacAddress}) async =>
      0;

  @override
  Future<void> upsertCacheRecord(SharedFolderCacheRecord record) async {}
}
