import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/application/remote_clipboard_projection_store.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';

void main() {
  late RemoteClipboardProjectionStore store;

  setUp(() {
    store = RemoteClipboardProjectionStore(fileHashService: FileHashService());
  });

  test('owns remote clipboard request lifecycle and projection updates', () {
    final requestId = store.beginRequest(
      ownerIp: '192.168.1.30',
      localDeviceMac: '02:00:00:00:00:01',
    );

    final applied = store.applyCatalog(
      ClipboardCatalogEvent(
        requestId: requestId,
        ownerIp: '192.168.1.30',
        ownerName: 'Remote peer',
        ownerMacAddress: '11:22:33:44:55:66',
        observedAt: DateTime(2026),
        entries: <ClipboardCatalogItem>[
          ClipboardCatalogItem(
            id: 'older-text',
            entryType: 'text',
            textValue: 'older',
            createdAtMs: 100,
          ),
          ClipboardCatalogItem(
            id: 'newer-image',
            entryType: 'image',
            imagePreviewBase64: base64Encode(<int>[1, 2, 3]),
            createdAtMs: 200,
          ),
        ],
      ),
    );

    store.finishRequest(requestId: requestId);

    expect(applied, isTrue);
    expect(store.isLoading, isFalse);
    expect(store.entriesFor('192.168.1.30'), hasLength(2));
    expect(store.entriesFor('192.168.1.30').first.id, 'newer-image');
    expect(
      store.entriesFor('192.168.1.30').first.type,
      ClipboardEntryType.image,
    );
    expect(store.entriesFor('192.168.1.30').first.imageBytes, <int>[1, 2, 3]);
  });

  test(
    'ignores remote clipboard catalogs for mismatched active request ids',
    () {
      store.beginRequest(
        ownerIp: '192.168.1.40',
        localDeviceMac: '02:00:00:00:00:01',
      );

      final applied = store.applyCatalog(
        ClipboardCatalogEvent(
          requestId: 'different-request',
          ownerIp: '192.168.1.40',
          ownerName: 'Remote peer',
          ownerMacAddress: '11:22:33:44:55:66',
          observedAt: DateTime(2026),
          entries: const <ClipboardCatalogItem>[
            ClipboardCatalogItem(
              id: 'remote-text',
              entryType: 'text',
              textValue: 'ignored',
              createdAtMs: 100,
            ),
          ],
        ),
      );

      expect(applied, isFalse);
      expect(store.entriesFor('192.168.1.40'), isEmpty);
      expect(store.isLoading, isTrue);
    },
  );
}
