import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/application/clipboard_history_store.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late ClipboardHistoryRepository repository;
  late FakeClipboardCaptureService captureService;
  late ClipboardHistoryStore store;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_clipboard_history_store_',
    );
    repository = ClipboardHistoryRepository(database: harness.database);
    captureService = FakeClipboardCaptureService();
    store = ClipboardHistoryStore(
      clipboardHistoryRepository: repository,
      clipboardCaptureService: captureService,
      transferStorageService: TransferStorageService(),
    );
  });

  tearDown(() async {
    store.dispose();
    await harness.dispose();
  });

  test(
    'loads canonical local clipboard history projection from repository',
    () async {
      await repository.insert(
        ClipboardHistoryEntry(
          id: 'entry-1',
          type: ClipboardEntryType.text,
          contentHash: 'text:first',
          textValue: 'first',
          createdAt: DateTime.fromMillisecondsSinceEpoch(200),
        ),
      );

      await store.load();

      expect(store.entries, hasLength(1));
      expect(store.entries.single.id, 'entry-1');
      expect(store.findLatest()!.contentHash, 'text:first');
    },
  );

  test(
    'captureSnapshot dedupes and trims through owner-backed history truth',
    () async {
      captureService.nextData = const ClipboardCaptureData(
        type: ClipboardEntryType.text,
        contentHash: 'text:first',
        textValue: 'first',
      );
      await store.captureSnapshot(maxEntries: 1);
      await store.captureSnapshot(maxEntries: 1);

      captureService.nextData = const ClipboardCaptureData(
        type: ClipboardEntryType.text,
        contentHash: 'text:second',
        textValue: 'second',
      );
      await store.captureSnapshot(maxEntries: 1);

      final rows = await repository.listRecent();

      expect(captureService.readCalls, 3);
      expect(rows, hasLength(1));
      expect(rows.single.contentHash, 'text:second');
      expect(store.entries, hasLength(1));
      expect(store.entries.single.textValue, 'second');
    },
  );

  test(
    'deleteEntry removes persisted image artifact and refreshes owner projection',
    () async {
      captureService.nextData = ClipboardCaptureData(
        type: ClipboardEntryType.image,
        contentHash: 'image:hash',
        imageBytes: Uint8List.fromList(const <int>[1, 2, 3, 4]),
      );
      await store.captureSnapshot(maxEntries: 10);

      final entry = store.entries.single;
      final imagePath = entry.imagePath!;

      expect(File(imagePath).existsSync(), isTrue);

      await store.deleteEntry(entry.id);

      expect(await repository.findById(entry.id), isNull);
      expect(store.entries, isEmpty);
      expect(File(imagePath).existsSync(), isFalse);
    },
  );

  test(
    'copyEntryToSystemClipboard routes full text payload through clipboard IO',
    () async {
      final entry = ClipboardHistoryEntry(
        id: 'text-entry',
        type: ClipboardEntryType.text,
        contentHash: 'text:full',
        textValue: 'Full clipboard text payload',
        createdAt: DateTime.fromMillisecondsSinceEpoch(200),
      );

      final result = await store.copyEntryToSystemClipboard(entry);

      expect(result, isNull);
      expect(captureService.lastWrittenText, 'Full clipboard text payload');
    },
  );

  test(
    'copyEntryToSystemClipboard reads persisted local image bytes only at action boundary',
    () async {
      captureService.nextData = ClipboardCaptureData(
        type: ClipboardEntryType.image,
        contentHash: 'image:hash',
        imageBytes: Uint8List.fromList(const <int>[1, 2, 3, 4]),
      );
      await store.captureSnapshot(maxEntries: 10);

      final entry = store.entries.single;

      final result = await store.copyEntryToSystemClipboard(entry);

      expect(result, isNull);
      expect(captureService.lastWrittenImageBytes, <int>[1, 2, 3, 4]);
    },
  );
}

class FakeClipboardCaptureService extends ClipboardCaptureService {
  ClipboardCaptureData? nextData;
  int readCalls = 0;
  String? lastWrittenText;
  Uint8List? lastWrittenImageBytes;

  @override
  Future<ClipboardCaptureData?> readCurrentClipboard() async {
    readCalls += 1;
    return nextData;
  }

  @override
  Future<bool> writeTextToClipboard(String text) async {
    lastWrittenText = text;
    return true;
  }

  @override
  Future<bool> writeImageBytesToClipboard(
    Uint8List imageBytes, {
    String suggestedName = 'clipboard-image.png',
  }) async {
    lastWrittenImageBytes = Uint8List.fromList(imageBytes);
    return true;
  }
}
