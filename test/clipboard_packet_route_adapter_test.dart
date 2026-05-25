import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/application/clipboard_history_store.dart';
import 'package:landa/features/clipboard/application/remote_clipboard_projection_store.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/discovery/application/clipboard_packet_route_adapter.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ClipboardPacketRouteAdapter', () {
    test(
      'answers trusted clipboard queries with clipped text catalog',
      () async {
        final harness = await TestAppDatabaseHarness.create(
          prefix: 'landa_clipboard_route_adapter_',
        );
        addTearDown(harness.dispose);

        final clipboardStore = ClipboardHistoryStore(
          clipboardHistoryRepository: ClipboardHistoryRepository(
            database: harness.database,
          ),
          clipboardCaptureService: ClipboardCaptureService(),
          transferStorageService: TransferStorageService(),
        );
        await clipboardStore.appendEntry(
          entry: ClipboardHistoryEntry(
            id: 'entry-1',
            type: ClipboardEntryType.text,
            contentHash: 'text:long',
            textValue: 'a' * 7000,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        );

        final lanDiscoveryService = _RecordingLanDiscoveryService();
        final adapter = ClipboardPacketRouteAdapter(
          lanDiscoveryService: lanDiscoveryService,
          clipboardHistoryStore: clipboardStore,
          remoteClipboardProjectionStore: RemoteClipboardProjectionStore(
            fileHashService: FileHashService(),
          ),
          settingsProvider: () => AppSettings.defaults,
          localNameProvider: () => 'Local',
          localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
          isTrustedMac: (mac) => mac == '11:22:33:44:55:66',
        );

        await adapter.handleClipboardQuery(
          ClipboardQueryEvent(
            requestId: 'request-1',
            requesterIp: '192.168.1.44',
            requesterName: 'Remote',
            requesterMacAddress: '11-22-33-44-55-66',
            maxEntries: 1,
            observedAt: DateTime(2026),
          ),
        );

        expect(lanDiscoveryService.catalogs, hasLength(1));
        final catalog = lanDiscoveryService.catalogs.single;
        expect(catalog.targetIp, '192.168.1.44');
        expect(catalog.ownerName, 'Local');
        expect(catalog.ownerMacAddress, 'aa:bb:cc:dd:ee:ff');
        expect(catalog.entries.single.textValue, hasLength(6000));
      },
    );

    test('ignores clipboard queries from untrusted devices', () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_clipboard_route_adapter_untrusted_',
      );
      addTearDown(harness.dispose);

      final lanDiscoveryService = _RecordingLanDiscoveryService();
      final adapter = ClipboardPacketRouteAdapter(
        lanDiscoveryService: lanDiscoveryService,
        clipboardHistoryStore: ClipboardHistoryStore(
          clipboardHistoryRepository: ClipboardHistoryRepository(
            database: harness.database,
          ),
          clipboardCaptureService: ClipboardCaptureService(),
          transferStorageService: TransferStorageService(),
        ),
        remoteClipboardProjectionStore: RemoteClipboardProjectionStore(
          fileHashService: FileHashService(),
        ),
        settingsProvider: () => AppSettings.defaults,
        localNameProvider: () => 'Local',
        localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
        isTrustedMac: (_) => false,
      );

      await adapter.handleClipboardQuery(
        ClipboardQueryEvent(
          requestId: 'request-1',
          requesterIp: '192.168.1.44',
          requesterName: 'Remote',
          requesterMacAddress: '11:22:33:44:55:66',
          maxEntries: 1,
          observedAt: DateTime(2026),
        ),
      );

      expect(lanDiscoveryService.catalogs, isEmpty);
    });

    test('applies remote clipboard catalog through projection store', () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_clipboard_route_adapter_projection_',
      );
      addTearDown(harness.dispose);

      final projectionStore = RemoteClipboardProjectionStore(
        fileHashService: FileHashService(),
      );
      addTearDown(projectionStore.dispose);
      final adapter = ClipboardPacketRouteAdapter(
        lanDiscoveryService: _RecordingLanDiscoveryService(),
        clipboardHistoryStore: ClipboardHistoryStore(
          clipboardHistoryRepository: ClipboardHistoryRepository(
            database: harness.database,
          ),
          clipboardCaptureService: ClipboardCaptureService(),
          transferStorageService: TransferStorageService(),
        ),
        remoteClipboardProjectionStore: projectionStore,
        settingsProvider: () => AppSettings.defaults,
        localNameProvider: () => 'Local',
        localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
        isTrustedMac: (_) => true,
      );

      final result = adapter.handleClipboardCatalog(
        ClipboardCatalogEvent(
          requestId: 'request-1',
          ownerIp: '192.168.1.45',
          ownerName: 'Remote',
          ownerMacAddress: '11:22:33:44:55:66',
          observedAt: DateTime(2026),
          entries: <ClipboardCatalogItem>[
            ClipboardCatalogItem(
              id: 'remote-entry-1',
              entryType: 'text',
              createdAtMs: 1000,
              textValue: 'hello',
            ),
          ],
        ),
      );

      expect(result, isNotNull);
      expect(result!.ownerIp, '192.168.1.45');
      expect(projectionStore.entriesFor('192.168.1.45'), hasLength(1));
      expect(
        projectionStore.entriesFor('192.168.1.45').single.textValue,
        'hello',
      );
    });
  });
}

class _RecordedClipboardCatalog {
  const _RecordedClipboardCatalog({
    required this.targetIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
  });

  final String targetIp;
  final String ownerName;
  final String ownerMacAddress;
  final List<ClipboardCatalogItem> entries;
}

class _RecordingLanDiscoveryService extends LanDiscoveryService {
  final List<_RecordedClipboardCatalog> catalogs =
      <_RecordedClipboardCatalog>[];

  @override
  Future<void> sendClipboardCatalog({
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<ClipboardCatalogItem> entries,
  }) async {
    catalogs.add(
      _RecordedClipboardCatalog(
        targetIp: targetIp,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: entries,
      ),
    );
  }
}
