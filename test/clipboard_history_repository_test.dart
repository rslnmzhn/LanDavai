import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/clipboard/domain/clipboard_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late ClipboardHistoryRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    database = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE clipboard_history (
              id TEXT PRIMARY KEY,
              entry_type TEXT NOT NULL,
              content_hash TEXT NOT NULL,
              text_value TEXT,
              image_path TEXT,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE INDEX idx_clipboard_history_created
            ON clipboard_history(created_at DESC)
          ''');
          await db.execute('''
            CREATE INDEX idx_clipboard_history_hash
            ON clipboard_history(content_hash)
          ''');
        },
      ),
    );
    repository = ClipboardHistoryRepository.withDatabaseProvider(
      databaseProvider: () async => database,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('lists newest entries first', () async {
    final now = DateTime.now();
    await repository.insert(
      ClipboardHistoryEntry(
        id: 'first',
        type: ClipboardEntryType.text,
        contentHash: 'text:first',
        textValue: 'first',
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
    );
    await repository.insert(
      ClipboardHistoryEntry(
        id: 'second',
        type: ClipboardEntryType.text,
        contentHash: 'text:second',
        textValue: 'second',
        createdAt: now,
      ),
    );

    final entries = await repository.listRecent();

    expect(entries.map((entry) => entry.id), <String>['second', 'first']);
  });

  test('deletes entry by id and returns removed row', () async {
    final createdAt = DateTime.now();
    await repository.insert(
      ClipboardHistoryEntry(
        id: 'image-entry',
        type: ClipboardEntryType.image,
        contentHash: 'image:hash',
        imagePath: r'C:\tmp\entry.png',
        createdAt: createdAt,
      ),
    );

    final removed = await repository.deleteById('image-entry');
    final persisted = await repository.findById('image-entry');

    expect(removed, isNotNull);
    expect(removed!.id, 'image-entry');
    expect(removed.type, ClipboardEntryType.image);
    expect(removed.imagePath, r'C:\tmp\entry.png');
    expect(persisted, isNull);
  });

  test('trimToMaxEntries removes oldest entries and returns them', () async {
    final now = DateTime.now();
    await repository.insert(
      ClipboardHistoryEntry(
        id: 'oldest',
        type: ClipboardEntryType.text,
        contentHash: 'text:oldest',
        textValue: 'oldest',
        createdAt: now.subtract(const Duration(minutes: 3)),
      ),
    );
    await repository.insert(
      ClipboardHistoryEntry(
        id: 'middle',
        type: ClipboardEntryType.text,
        contentHash: 'text:middle',
        textValue: 'middle',
        createdAt: now.subtract(const Duration(minutes: 2)),
      ),
    );
    await repository.insert(
      ClipboardHistoryEntry(
        id: 'newest',
        type: ClipboardEntryType.text,
        contentHash: 'text:newest',
        textValue: 'newest',
        createdAt: now,
      ),
    );

    final removed = await repository.trimToMaxEntries(2);
    final kept = await repository.listRecent();

    expect(removed.map((entry) => entry.id), <String>['oldest']);
    expect(kept.map((entry) => entry.id), <String>['newest', 'middle']);
  });
}
